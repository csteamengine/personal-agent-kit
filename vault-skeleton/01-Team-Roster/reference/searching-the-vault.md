# Reference: Searching the vault

Shared by every roster agent, so each agent file carries a short pointer here instead of the full text.

**grep when you know the exact string, or when you need completeness. Otherwise semantic search, if you have one.**

## grep

- Use it for an exact identifier, a handle, a filename, a ticket key, and **anything needing completeness**: an audit, a rename, a link check, "every file that mentions X".
- Use `-w` for a short term that is a substring of common words.
- An agent without `Bash` uses its `Grep` tool directly on vault files.

## Semantic search (optional)

A local semantic search tool (for example Miyo, which the kit does not ship) bridges vocabulary you do not know yet. Rules that hold for any of them:

- **A hit is never evidence that something exists, and the result count is evidence of nothing.** A tool that returns the top N chunks returns N plausible chunks whether or not N files match.
- **Scope it to the right folder before searching, not after.** A question sent to the wrong index returns plausible documents, never an empty result.
- **Paths first, then grep, then chunks only if needed.** Get file paths from the tool, grep those files with the vocabulary the result taught you, and read returned chunks only when the grep finds nothing.
- **A returned path may not be a filesystem path.** If the tool prefixes paths with an index name, substitute the real root before reading, or you will wrongly conclude the note does not exist.

## Read a section, not a file

Front matter and conclusion block first (about 30 lines), then `grep -n '^## '` for the headings, then only the section you need.

## Paths to keep out of results

Never cite a hit under `snapshots/` (pre-change copies kept for reverting), or under any tooling path (`.claude/`, `.agents/`, `skills/`): those are agent instructions, not durable documentation.
