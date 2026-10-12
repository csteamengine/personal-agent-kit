# Orca workspace and session scripts

Shell helpers for running several AI agent sessions side by side in [Orca](https://github.com/stablyai/orca), one per worktree, without them stepping on each other or on you.

- Every script uses only commands in stock Orca's CLI (`orca worktree`, `orca terminal`, `orca automations`). Each script's header lists the ones it calls.
- Nothing here reads or writes Orca's data files. Orca keeps board state in memory and overwrites its storage from memory, so a direct edit is silently lost. Go through the CLI.
- Requirements: bash, `jq`, `perl`, `lsof`, `git`; `gh` for the reaper; `npx` for the Chrome wrapper. Written on macOS, with Linux fallbacks for `stat` and `sha1sum`.

## The scripts

| Script | What it does |
|---|---|
| `bin/orca-lease.sh` | Named-resource lease: N slots, strict FIFO queue, stale holders reaped, the next waiter woken by typing into its agent terminal. For anything only N sessions may use at once. |
| `bin/browser-queue.sh` | The browser lease (`orca-lease.sh --resource browser`), so two sessions never drive one Chrome. Shared mode by default. |
| `bin/chrome-mcp-per-worktree.sh` | Drop-in MCP command for `chrome-devtools-mcp` that gives each worktree its own Chrome profile. Enables per-session browser mode. |
| `bin/orca-status.sh` | Set a card's board status by label. Learns the ids of columns you add in Settings, since stock Orca cannot list them. |
| `bin/orca-card-note.sh` | Writes a fenced "why this card is here" block into the card's notes, leaving your own text alone, and sweeps blocks that went stale when the card moved. |
| `bin/worktree-reaper.sh` | Read-only report of worktrees whose PR is merged or closed and which hold no unsaved work. Works as an automation precheck. |
| `bin/scratch-tracker.sh` | Creates and bound-checks a per-worktree `.scratch/<topic>/TRACKER.md`, so multi-session work survives the session. |
| `bin/setup-automations.sh` | Recreates this kit's automations on a fresh install through `orca automations create`. Idempotent by name. |

Tests: `bash tests/orca-lease/test.sh` and `bash tests/status-and-note/test.sh`. Both run against a fake `orca` and touch nothing real.

## Install

```bash
# 1. Orca's CLI on PATH: let the app register `orca` (on macOS it lands at /usr/local/bin/orca).
#    Or point the scripts at it: export ORCA_BIN=/path/to/orca
# 2. Put bin/ on PATH, or call the scripts by absolute path.
# 3. Optional config; every file is optional:
mkdir -p ~/.config/agent-kit/orca && cp -R config.example/. ~/.config/agent-kit/orca/
```

| Variable | Default | Holds |
|---|---|---|
| `ORCA_BIN` | `orca` | The Orca CLI |
| `ORCA_KIT_CONFIG` | `~/.config/agent-kit/orca` | `statuses.tsv`, `verdicts.txt`, `reaper-repos`, `leases/<resource>.conf` |
| `ORCA_KIT_STATE` | `~/.local/state/agent-kit/orca` | Lease queues and logs, reaper output. Paths, ports and times only. |

## Board statuses on a fresh install

> [!important]
> Columns are created in the app (Settings, workspace statuses), not by the CLI. Stock Orca has no command to create, list or reorder them. The four built-ins have fixed ids: `todo`, `in-progress`, `in-review`, `completed`.

1. Add your columns in Settings. A suggested set for agent work:

   | Label | Meaning | Who sets it |
   |---|---|---|
   | In progress | The agent is working | Agent, at the start of a turn |
   | Needs me | Waiting on you: a decision, a review, a confirmation | Agent, at the end of a turn |
   | Idle | Finished, nothing pending | Agent, at the end of a turn |
   | Waiting on others | Waiting on a third party (a PR author, a reviewer) | Agent or script |
   | Done | The real outcome happened | You only |

2. Teach the scripts each new column's id, once. Drag any card into the column, then from that worktree:

   ```bash
   orca-status.sh learn --worktree "path:$(git rev-parse --show-toplevel)" "Needs me"
   orca-status.sh list
   ```

3. Agents then set status by label, never by a hard-coded id:

   ```bash
   orca-status.sh set --worktree "path:$(git rev-parse --show-toplevel)" "Needs me"
   ```

   An unknown label falls back to In review rather than failing the run. Always pass `--worktree`; `orca worktree set` without it fails.

The status is the notification. An agent should change it silently and not narrate it in chat.

## Automations on a fresh install

Automations are recreated with `orca automations create`, never by copying data files. `setup-automations.sh --repo <selector>` creates the kit's two; `--dry-run` prints the commands first. For your own:

```bash
orca automations create --name "Nightly triage" --trigger "0 2 * * *" \
  --precheck "my-precheck.sh" --prompt "$(cat prompts/triage.md)" \
  --provider claude --repo my-repo
```

- **Keep prompts in files** under version control and pass them with `"$(cat ...)"`; the CLI takes the prompt as text.
- **A precheck runs in a shell before every scheduled run.** Exit 0 dispatches the agent; anything else records a skipped run and costs no tokens.
- **Script-only chores** (like the card-note sweep) do their work inside the precheck and always exit 1, so no agent turn is ever spent.
- `orca automations list --json` before you rebuild a machine shows each automation's name, schedule, precheck and prompt to carry over.

## Leases

```bash
browser-queue.sh acquire --worktree "$WT"   # exit 0: yours. exit 10: queued, stop and wait to be woken
browser-queue.sh release --worktree "$WT"   # always, pass, fail or cancelled; close the browser first
```

A queued session ends its turn. When its slot frees, the script types a wake-up line into that workspace's agent terminal with `orca terminal send --enter`, which starts a new turn. Joining happens inside an atomic `mkdir` mutex, so racing joiners are never lost or reordered.

A holder is reaped when its workspace disappears from `orca worktree list`, or when it has not been busy for `GRACE` seconds. Configure "busy" per resource in `leases/<name>.conf` with `BUSY_PATTERN` (a `pgrep -f` pattern), `BUSY_CMD`, or `BUSY_PORT`. `config.example/leases/` has a per-session browser and a shared local stack.

## Card notes

```bash
orca-card-note.sh set --worktree "path:$WT" --src ci-watch --verdict "CI failing" \
  --counts "2 of 14 checks red" --needs "fix or re-run" --status-label "Needs me"
orca-card-note.sh sweep   # run on a schedule; drops blocks whose card has since moved
```

Verdicts are a closed list (override in `verdicts.txt`) so the vocabulary cannot drift. **Put counts, identifiers and status words in a note, never text copied from a PR, issue or customer record**: card notes end up in logs and screenshots.

## Known gaps on stock Orca

- `orca file open` switches focus to the opened file. Do not call it from an unattended script while you are working elsewhere.
- No CLI for workspace tags or for listing board columns, hence `statuses.tsv`.
- `worktree-reaper.sh` counts commits on no remote branch as unsaved, so a squash-merged branch whose remote branch was deleted reads as unsaved and is kept. That errs toward never losing work.
