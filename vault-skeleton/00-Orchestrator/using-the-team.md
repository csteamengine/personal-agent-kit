---
subject: Using Planet Express day to day
purpose: How to start projects, pick up work, and review it with the team
owner: Turanga Leela
---

# Using Planet Express

- **Describe the task, not the agent.** Naming one is a fallback, not the default.
- **New project:** seed a folder in `03-Projects/` before anyone touches code.
- **Picking up work:** route by what the change touches, not by habit. Plenty of tasks need no agent at all.
- **Reviewing work:** agents draft comments and **you post them.**
- **The one thing worth remembering:** give each reviewer a different question. A generic "review this" to three reviewers tends to find one defect; a targeted question per reviewer finds several with little overlap.

## A project starts with a vault folder, not with code

Create `03-Projects/<project>/` with `overview.md` (status, current team, open threads) plus `discovery/`, `decisions/`, and `handoffs/` as they are needed. That is the resumable state; a decision that only exists in chat did not happen.

## A capability gap is a job spec, not a reassignment

If the work needs a skill nobody on the roster has, it goes through the hiring pipeline. Don't stretch an existing agent's scope to cover a gap; that rule exists so each agent's remit stays legible.

| Step | Who | Output |
|---|---|---|
| Confirm a new role is actually wanted | Leela + {{OWNER}} | Conversation |
| Research the real job | Farnsworth | `02-Job-Specs/job-spec-<name>.md` |
| Decide hire / no-hire | LaBarbara | Roster note + subagent file |
| Add to the index | Leela | Roster table update |

> [!note]
> A roster note is not a proven capability. Treat a new hire's first few tasks as a trial, and check its `tools:` line against what its own prompt asks it to do: a prompt that requires Write access without granting it is the most common hiring defect.

## Route by the shape of the work

Once you have specialists, keep a table here mapping what a change touches to which agent judges it. Until then:

| Work | Reach for |
|---|---|
| A question that needs many files read | `codebase-explorer` |
| A drafted plan, before code exists | `plan-reviewer` |
| One chunk of an approved, partitioned plan | `plan-implementer` |
| Finished work, before you look at it | `work-verifier` (never the agent that wrote it) |
| Dense output you need to read | `fry` |
| A message going out under your name | `scruffy` |
| Is the vault still consistent? | `hermes` |
| Small, well-understood change | **Nobody. Just do it.** |

**Plans live in the vault, working state lives in the repo.** A design decision or plan goes in `03-Projects/<project>/`. Anything ephemeral goes in that repo's own `.scratch/`.

> [!important]
> A specialist may read a grounding repo freely, but implementation happens in a session opened in the repo itself, never from a vault session.

## Reviewing work

**The property that actually finds defects is a different question per reviewer, never "review this."** Name each reviewer's suspected weak spot in its prompt.

**You own the review conversation.** Agents draft comments for you to paste; nobody posts, and nobody resolves a thread a human opened.

> [!warning]
> Green CI is not evidence a stacked PR works. `mergeable` is a textual check on files touched, not compatibility, and a check run's green tick dates from the commit it ran on, not from now. Confirm the head still builds against the *current* base before calling anything ready.

## Two agents that are easy to mix up

| If the reader is... | Route to | Why the mistake is costly |
|---|---|---|
| {{OWNER}} | Fry | Makes dense output readable. A miss just confuses one message. |
| Someone else, with {{OWNER}} credited | Scruffy | Drafts in their voice, never posts. A miss misrepresents them publicly and doesn't undo. |
