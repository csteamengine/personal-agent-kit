---
subject: {{OWNER}}
purpose: How {{OWNER}} works, and what that requires of the team
owner: Turanga Leela
---

# Working With {{OWNER}}

The operating manual for the person this team works for. Every agent reads it; Fry reads it before every task, because it is the spec for his output.

Keep it current. When {{OWNER}} corrects the team or states a preference, it goes here immediately, before continuing whatever was in progress.

> [!note]
> This is the kit's blank template. A private overlay replaces it with the real one.

## Who they are

- _(role, what they work on, how technical they are)_

## Environment

- _(machine, Claude Code desktop app or terminal, note-taking tool)_
- If they use the desktop app, interactive terminal slash commands (`/permissions`, `/config`, `/hooks`) are not available to them. Point at the app's UI or make the settings change directly.

## How they read

Well-formatted markdown **only for documents they read.** An artifact another agent will act on stays dense and complete.

| Rule | Why |
|---|---|
| Conclusion in the first sentence | Never make them read to reach the point |
| Short paragraphs | Dense blocks get skipped |
| Headings that are claims | Reading only the headers gives the gist |
| Tables for anything compared | A comparison in prose costs working memory |
| Every number in a table or bullet | A figure inside a sentence is invisible on a scan |
| Next actions in their own section | They can act without re-reading |

## Stated conventions

- No em dashes in prose meant for a person.
- Dates absolute, with the year.
- Nothing identified by a bare key: identifier, a few words, a link.

## Hard constraints on what you can recommend

Things they cannot approve, accounts they cannot use, identities that must not be mixed. Recommending something that violates one wastes their time and can misrepresent them.

- _(none recorded yet)_

## How they want to work with agents

- **Ask more up front.** Sort unknowns into **factual** (an agent can find out) versus **judgement** (only they can decide), and ask only the second kind.
- **Say plainly when something is assumed rather than verified.** Label an inference as an inference.
- **Verify before reporting a tool defect.** Isolate the command first.

## Corrections log

Append-only. Never pruned. Record the correction and the date.
