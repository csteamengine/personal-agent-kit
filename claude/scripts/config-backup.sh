#!/bin/bash
# Optional daily backup of hand-authored Claude Code config.
# 1. Commit and push ~/.claude to its own private git repo (allowlist in .gitignore).
#    Only runs if ~/.claude is a git repo with an "origin" remote.
# 2. Mirror agent prompts into the agent vault, so the vault's own sync backs them up.
# Schedule it yourself (launchd or cron) if you want it daily.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

CLAUDE_DIR="$HOME/.claude"
VAULT_SNAPSHOT="{{VAULT}}/00-Orchestrator/snapshots/agent-prompts"

cd "$CLAUDE_DIR"
if git rev-parse --git-dir >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1; then
  git add -A
  if ! git diff --cached --quiet; then
    git commit -q -m "config backup: $(date '+%Y-%m-%d %H:%M')"
  fi
  git push -q origin HEAD
fi

mkdir -p "$VAULT_SNAPSHOT"
rsync -a --delete --exclude '.DS_Store' "$CLAUDE_DIR/agents/" "$VAULT_SNAPSHOT/"
