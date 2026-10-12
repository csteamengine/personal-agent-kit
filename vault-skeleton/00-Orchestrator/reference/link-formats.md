# Link formats and resolving an Obsidian link

The rule in `~/.claude/CLAUDE.md`: if a thing has a clickable form, use it, every time, not just on first mention. This is the worked table and the Obsidian-specific mechanics behind it.

## The table

| Thing | Form |
|---|---|
| File in the current repo | `[foo.ts](src/utils/foo.ts)`, or `[foo.ts:42](src/utils/foo.ts:42)` |
| File outside the repo | `[name](file:///absolute/path/to/file.md)` |
| GitHub repo | `https://github.com/owner/repo` |
| PR / issue | `[owner/repo#123](https://github.com/owner/repo/pull/123)` |
| Commit | `[a1b2c3d](https://github.com/owner/repo/commit/a1b2c3d) subject line` |
| Branch | `[name](https://github.com/owner/repo/tree/name)` |
| Code on GitHub | `.../blob/<sha>/path/file.ts#L42`, with a SHA not a branch |
| Diff | `[a...b](https://github.com/owner/repo/compare/a...b)` |
| Ticket | `[KEY-123](https://<your-tracker>/browse/KEY-123) (a few words on what it is)` |

## Resolving an Obsidian link

**Nothing opens a note in Obsidian itself from a chat link.** `obsidian://` URIs dispatch fine from a shell, but a markdown link using that scheme does nothing when clicked in the Claude Code desktop app. Do not emit them.

A clickable link opens the file in the app's own side panel instead. That is the best available.

**The only thing that decides whether a link works is whether the file sits under a directory this session has access to.** Inside one, a relative path, an absolute path, and `file://` all work. Percent-encoding makes no difference.

**Use an absolute path for every vault file.** A relative path resolves against the session's working directory, not against the vault the file lives in, so it silently points at the wrong root whenever the session is not rooted in that vault. Relative paths are for source files in the repo the session is working in, and nothing else.

**Never put a bare path in backticks and expect it to work.** Backticks make it code, not a link.

Outside every granted directory, a link opens the panel and then fails to load, which looks broken rather than denied. **So grant the other vault at the start of any session that will reference it**, by adding it as a working directory, rather than emitting links that fail.
