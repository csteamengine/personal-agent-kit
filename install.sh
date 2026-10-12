#!/usr/bin/env bash
# personal-agent-kit installer.
#
#   ./install.sh                          # kit only
#   ./install.sh --private ../my-overlay  # kit, then a private overlay on top
#
# Settings come from the environment, then from the overlay's overlay.env,
# then from the defaults below:
#   VAULT        agent vault to create or top up       (default: ~/AgentVault)
#   OWNER        your name as the agents should use it (default: "the user")
#   OWNER_HANDLE your margin-note handle, without @    (default: "me")
#   PUBLISH_DIR  where Fry publishes finished work     (default: $VAULT/05-Published)
#   CLAUDE_DIR   Claude Code config dir                (default: ~/.claude)
#
# Safe to re-run. Existing files in ~/.claude that the kit manages are backed
# up before being replaced; an existing settings.json is never overwritten.
# Existing vault files are never overwritten by the kit (the overlay may
# replace the kit's own templates, which is its job).
set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRIVATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --private) PRIVATE="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$PRIVATE" ] && [ -f "$PRIVATE/overlay.env" ]; then
  # shellcheck disable=SC1091
  . "$PRIVATE/overlay.env"
fi

: "${VAULT:=$HOME/AgentVault}"
: "${OWNER:=the user}"
: "${OWNER_HANDLE:=me}"
: "${PUBLISH_DIR:=$VAULT/05-Published}"
: "${CLAUDE_DIR:=$HOME/.claude}"
VAULT="${VAULT%/}"
TODAY="$(date +%Y-%m-%d)"
BACKUP="$CLAUDE_DIR/backups/kit-$(date +%Y%m%d-%H%M%S)"

say() { printf '  %s\n' "$*"; }

# Fill {{PLACEHOLDERS}} in a text file. Only these five are rendered; anything
# else in double braces ({{name}} in templates) is left for the agents.
esc() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }
render() {
  sed -e "s|{{VAULT}}|$(esc "$VAULT")|g" \
      -e "s|{{OWNER}}|$(esc "$OWNER")|g" \
      -e "s|{{OWNER_HANDLE}}|$(esc "$OWNER_HANDLE")|g" \
      -e "s|{{PUBLISH_DIR}}|$(esc "$PUBLISH_DIR")|g" \
      -e "s|{{DATE}}|$TODAY|g" "$1"
}

# Install one file: back up whatever is there, then write the rendered copy.
install_file() {
  local src="$1" dest="$2" mode="${3:-644}"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ]; then
    mkdir -p "$BACKUP/$(dirname "${dest#"$CLAUDE_DIR"/}")"
    cp -p "$dest" "$BACKUP/${dest#"$CLAUDE_DIR"/}"
  fi
  render "$src" > "$dest"
  chmod "$mode" "$dest"
}

# Copy a tree, rendering every file. $3 = "keep" skips files that already exist.
copy_tree() {
  local src="$1" dest="$2" policy="${3:-keep}" f rel
  (cd "$src" && find . -type f ! -name '.DS_Store' | sed 's|^\./||') | while IFS= read -r rel; do
    f="$dest/$rel"
    if [ -e "$f" ] && [ "$policy" = keep ]; then continue; fi
    mkdir -p "$(dirname "$f")"
    case "$rel" in
      *.md|*.json|*.sh|*.txt|*.base|*.canvas|.gitkeep) render "$src/$rel" > "$f" ;;
      *) cp -p "$src/$rel" "$f" ;;
    esac
  done
}

echo "personal-agent-kit"
say "vault:     $VAULT"
say "owner:     $OWNER (@$OWNER_HANDLE)"
say "claude:    $CLAUDE_DIR"
[ -n "$PRIVATE" ] && say "overlay:   $PRIVATE"

# 1. Claude Code config --------------------------------------------------------
echo "Installing Claude Code config"
install_file "$KIT_DIR/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
for a in "$KIT_DIR"/claude/agents/*.md; do
  install_file "$a" "$CLAUDE_DIR/agents/$(basename "$a")"
done
for s in "$KIT_DIR"/claude/scripts/*.sh; do
  install_file "$s" "$CLAUDE_DIR/scripts/$(basename "$s")" 755
done
install_file "$KIT_DIR/claude/statusline.sh" "$CLAUDE_DIR/statusline.sh" 755
install_file "$KIT_DIR/claude/sound-alert.sh" "$CLAUDE_DIR/sound-alert.sh" 755
[ -e "$CLAUDE_DIR/.gitignore" ] || install_file "$KIT_DIR/claude/gitignore" "$CLAUDE_DIR/.gitignore"

if [ -e "$CLAUDE_DIR/settings.json" ]; then
  render "$KIT_DIR/claude/settings.template.json" > "$CLAUDE_DIR/settings.kit.json"
  say "settings.json exists, left alone. Kit settings written to settings.kit.json: merge by hand."
else
  install_file "$KIT_DIR/claude/settings.template.json" "$CLAUDE_DIR/settings.json"
fi

if [ ! -e "$CLAUDE_DIR/obsidian-vaults.json" ]; then
  printf '{\n  "default": "%s",\n  "agents": "%s"\n}\n' "$VAULT" "$VAULT" > "$CLAUDE_DIR/obsidian-vaults.json"
fi

# 2. Agent vault ---------------------------------------------------------------
echo "Creating or topping up the agent vault"
mkdir -p "$VAULT"
copy_tree "$KIT_DIR/vault-skeleton" "$VAULT" keep
mkdir -p "$PUBLISH_DIR"

# 3. Private overlay -----------------------------------------------------------
if [ -n "$PRIVATE" ]; then
  echo "Applying private overlay"

  # 3a. Append personal global rules between markers, replacing any earlier copy.
  if [ -f "$PRIVATE/claude/CLAUDE.private.md" ]; then
    tmp="$(mktemp)"
    awk '/^<!-- private-overlay:start -->$/{skip=1} !skip{print} /^<!-- private-overlay:end -->$/{skip=0}' \
      "$CLAUDE_DIR/CLAUDE.md" > "$tmp"
    { cat "$tmp"; echo; echo '<!-- private-overlay:start -->'; render "$PRIVATE/claude/CLAUDE.private.md"; echo '<!-- private-overlay:end -->'; } \
      > "$CLAUDE_DIR/CLAUDE.md"
    rm -f "$tmp"
  fi

  # 3b. Vault files: the overlay's versions replace the kit's templates.
  [ -d "$PRIVATE/vault" ] && copy_tree "$PRIVATE/vault" "$VAULT" replace

  # 3c. Memory for sessions opened in the vault. Claude Code keys project
  #     memory by the session's path with every non-alphanumeric char as "-".
  if [ -d "$PRIVATE/memory" ]; then
    slug="$(printf '%s' "$VAULT" | sed 's/[^A-Za-z0-9]/-/g')"
    copy_tree "$PRIVATE/memory" "$CLAUDE_DIR/projects/$slug/memory" keep
  fi

  # 3d. Settings: deep-merge the overlay's settings on top (needs jq).
  if [ -f "$PRIVATE/claude/settings.private.json" ]; then
    target="$CLAUDE_DIR/settings.json"
    [ -e "$CLAUDE_DIR/settings.kit.json" ] && target="$CLAUDE_DIR/settings.kit.json"
    if command -v jq >/dev/null 2>&1; then
      tmp="$(mktemp)"
      render "$PRIVATE/claude/settings.private.json" > "$tmp.overlay"
      jq -s '.[0] * .[1]' "$target" "$tmp.overlay" > "$tmp" && mv "$tmp" "$target"
      rm -f "$tmp.overlay"
      say "merged overlay settings into $(basename "$target")"
    else
      say "jq not found: overlay settings not merged. Install jq and re-run."
    fi
  fi
fi

[ -d "$BACKUP" ] && say "previous versions of replaced files: $BACKUP"
echo "Done. Open a Claude Code session in $VAULT to talk to Leela."
