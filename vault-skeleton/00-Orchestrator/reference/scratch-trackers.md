# Session trackers (.scratch): full mechanics

The rule in `~/.claude/CLAUDE.md`: for work spanning more than one sitting, keep a tracker on disk, created in the first few turns. This is the layout and the bounds behind that rule.

## Resolving the scratch root

Use the worktree's own root, so a link to a scratch file opens in the same workspace:

```bash
SCRATCH="$(git rev-parse --show-toplevel 2>/dev/null)/.scratch"
```

Add `.scratch/` to your global gitignore. The scratch dies with the worktree on purpose: anything worth keeping past that belongs in the vault before then. Work that spans several worktrees keeps one tracker in the worktree that owns it; other sessions message that session rather than editing it.

The kit's `SessionStart` hook (`~/.claude/scripts/session-scratch-context.sh`) injects the newest tracker's first 30 lines at startup, resume, and after compaction.

## Layout

`$SCRATCH/<topic>/TRACKER.md`, with bulk output in `$SCRATCH/<topic>/notes/YYYY-MM-DD-<subject>.md` and rolled-over trackers in `archive/`. Topic folder name: lowercased ticket key plus a short slug when there is a ticket, otherwise a short kebab slug. Never a date in a folder name. Nothing at the `.scratch/` root.

## Tracker sections

In this order: `Now`, `Decisions`, `User corrections`, `Open questions`, `Findings`. A header above them carries the ticket link, a link to the durable doc if one exists, and the date of the last meaningful update. Everything needed to resume belongs in the first 30 lines.

Write to the tracker when, and only when:

- I decide something or overrule you. Record it immediately, before continuing.
- You learn something that cost real effort and would cost it again.
- You change direction.
- An open question opens or closes.

Never write a play-by-play, anything the code or `git log` already says, or anything that belongs in a durable doc. Link instead. The tracker's value is inversely proportional to its length.

## Bounds

`Now` three lines, overwritten wholesale. `Open questions` seven entries; an eighth means the topic should split. `Findings` fifteen. `User corrections` is never pruned. At 150 lines or a phase change, copy to `archive/TRACKER-<YYYY-MM-DD>.md` and rewrite, carrying forward all corrections, decisions still in force, and still-open questions.

Re-read the whole tracker before acting, and again immediately before editing it. Only the main session edits `TRACKER.md`; subagents write a `notes/` file and return its path.

Never silently drop scope, and never reverse a `Decisions` entry on your own.

## Resolving a vault for durable docs

Durable docs (ADRs, design docs, finished plans) do not go in `.scratch`. They go in a vault. Never hardcode a vault path. Resolve one in this order:

1. The vault named by the active persona or skill, looked up in `~/.claude/obsidian-vaults.json`: a flat name-to-absolute-path map with a `default` key. If the file is absent, skip this step.
2. `$OBSIDIAN_VAULT`.
3. `~/.claude/obsidian-vault`, a file holding one absolute path.

If you cannot resolve which vault, ask rather than guessing.
