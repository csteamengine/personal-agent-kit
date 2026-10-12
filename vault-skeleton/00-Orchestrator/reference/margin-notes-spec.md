# Margin notes: worked example

The rules live in `~/.claude/CLAUDE.md`. Full spec: https://pullmark.app/docs/experimental/margin-notes/. This is the worked example.

```markdown
The publish gate blocks on any unresolved conflict.

<!-- note @{{OWNER_HANDLE}}: only for scored items, not draft ones -->
<!-- note @leela: adjusted above, see decision 0003 -->
```

It is an HTML comment, so it stays out of rendered markdown.

In a list item, the note goes inside the item, directly after its last line, indented to the item's content, with no blank lines:

```markdown
- Ship the importer first
  <!-- note @hermes: no decision records this ordering -->
- Then the exporter
```
