# personal-agent-kit

A Claude Code setup where one session is an orchestrator that never does the work itself, and a small crew of persona agents does it, with an Obsidian vault as the team's shared memory.

- **One install step** puts the agents, global rules, hooks, and status line in `~/.claude` and creates an empty agent vault.
- **The orchestrator is Leela**: a session opened in the vault. She plans, writes handoffs, and delegates. She never writes the code, the design, or the research.
- **New specialists are hired, not shipped.** Farnsworth researches the real-world role, LaBarbara decides and writes the agent. The kit ships the pattern and the generic crew.
- **Everything about you lives in a separate private overlay**, layered on at install time, so this repo stays shareable.

## Install

On macOS, with Claude Code installed:

```bash
git clone <this repo> ~/personal-agent-kit
cd ~/personal-agent-kit
VAULT=~/AgentVault OWNER="Your Name" OWNER_HANDLE=you ./install.sh
```

With a private overlay (see below):

```bash
./install.sh --private ~/personal-agent-private
```

Then open the vault in Obsidian, and open a Claude Code session in the vault folder. That session is Leela.

`jq` is needed for the status line and for merging overlay settings (`brew install jq`). Re-running is safe: replaced files in `~/.claude` are backed up to `~/.claude/backups/kit-<timestamp>/`, an existing `settings.json` is never overwritten (the kit's version lands in `settings.kit.json` for you to merge), and existing vault files are never overwritten.

## What you get

| Piece | Where it lands | What it does |
|---|---|---|
| Global rules | `~/.claude/CLAUDE.md` | Response shape, linking, token economy, trackers, review etiquette, margin notes |
| Persona agents | `~/.claude/agents/` | Hermes, Farnsworth, LaBarbara, Fry, Scruffy |
| Utility agents | `~/.claude/agents/` | `codebase-explorer`, `plan-reviewer`, `plan-implementer`, `work-verifier` |
| Scratch tracker hook | `~/.claude/scripts/session-scratch-context.sh` | Re-injects the active `.scratch` tracker at start, resume, and after compaction |
| Status line | `~/.claude/statusline.sh` | Model, context use, session cost, plan spend, rate limits |
| Sound alerts | `~/.claude/sound-alert.sh` | A chime when a session needs you |
| Config backup | `~/.claude/scripts/config-backup.sh` | Optional: commits `~/.claude` to its own private repo, mirrors agents into the vault |
| `.gitignore` | `~/.claude/.gitignore` | Allowlist, so a git repo of `~/.claude` tracks only hand-written config, never history or credentials |
| Vault | `$VAULT` | Orchestrator charter, templates, roster, references |
| Orca scripts | `orca/` (not installed automatically) | Workspace and session management for Orca users; see `orca/README.md` |

## The workflow

### The crew

| Agent | Job | Never does |
|---|---|---|
| Leela (the vault session) | Orchestrates: discovery, handoffs, delegation, status | Produce a deliverable |
| Farnsworth | Researches what a human in a role actually does; writes a Job Spec | Decide the hire |
| LaBarbara | Hires or fires against a spec; writes the roster note and the agent file | Research |
| Hermes | Audits the vault against its own rules | Fix what he finds |
| Fry | Turns dense output into something you can read; publishes finished work | Change a claim |
| Scruffy | Drafts messages you will send under your name | Post anything |

### Hiring a specialist

1. Tell Leela what capability is missing.
2. Farnsworth writes `02-Job-Specs/job-spec-<role>.md`, grounded in your actual repos (list them in the vault `CLAUDE.md` under "Grounding repos").
3. LaBarbara decides. On a hire she writes both halves: `01-Team-Roster/<name>.md` (identity of record) and `~/.claude/agents/<name>.md` (the runnable agent).
4. Leela adds the agent to the roster index.

Agents are global, so a specialist hired here is available in any session, including one opened in a code repo, which is where implementation happens. The vault never edits a repo.

### Day to day

- **Projects** start as `03-Projects/<project>/overview.md`, with `decisions/` (numbered ADRs) and `handoffs/` (the context each delegated agent gets).
- **Agents write to disk and return a path**, so work survives the session.
- **Agents talk to each other** through margin notes, `<!-- note @handle: ... -->`, in the shared markdown. Leela watches for notes nobody answered.
- **Long work in a code repo** keeps a tracker in that repo's `.scratch/<topic>/TRACKER.md`, which the SessionStart hook re-injects after compaction.

The vault's own [using-the-team](vault-skeleton/00-Orchestrator/using-the-team.md) has the routing table.

## The private overlay

The kit holds machinery. Anything about you lives in a second, private repo with this shape:

```
personal-agent-private/
  overlay.env                    VAULT, OWNER, OWNER_HANDLE, PUBLISH_DIR defaults
  claude/CLAUDE.private.md       appended to ~/.claude/CLAUDE.md between markers
  claude/settings.private.json   deep-merged over settings.json (jq)
  vault/                         copied over the vault, replacing kit templates
    00-Orchestrator/working-with-me.md   how you read, your conventions, corrections log
    00-Orchestrator/voice.md             your measured voice profile (Scruffy needs it)
  memory/                        Claude Code memory for sessions opened in the vault
```

Every part is optional. `install.sh --private <path>` applies it after the kit, and the same `{{VAULT}}`, `{{OWNER}}`, `{{OWNER_HANDLE}}`, `{{PUBLISH_DIR}}` placeholders work in overlay files. Re-running replaces the appended `CLAUDE.md` section rather than duplicating it.

Why two repos: the machinery gets better with outside eyes, while the personal state grows over time. Mixed together, a public repo slowly accumulates private data.

### Writing your own `voice.md`

Measure it over text you actually wrote by hand (your own notes are best). Never build it from messages agents drafted in your name: that is a profile of agent output. Scruffy refuses to draft without it.

## Optional tools the kit works with but does not ship

| Tool | Used for |
|---|---|
| Obsidian | Reading and editing the vault; callouts render there |
| A local semantic search tool (e.g. Miyo) | Concept search over the vault; see `01-Team-Roster/reference/searching-the-vault.md` |
| Orca | Parallel worktree sessions and a workspace status board; see `orca/` |
| `gh` | The GitHub review-comment workflow |

## Placeholders

Files in `claude/` and `vault-skeleton/` use `{{VAULT}}`, `{{OWNER}}`, `{{OWNER_HANDLE}}`, `{{PUBLISH_DIR}}`, and `{{DATE}}`, which `install.sh` fills in. Other double-brace tokens (such as `{{name}}` in the templates) are for the agents to fill and are left alone.
