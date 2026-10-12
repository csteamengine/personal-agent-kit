# GitHub review comments: the four surfaces, exact commands

The rule in `~/.claude/CLAUDE.md` is: fetch all four comment surfaces before saying a PR's comments are handled, never just the inline threads. This is the exact command for each.

1. Inline review threads:
   `gh api graphql` on `pullRequest.reviewThreads` (filter `isResolved == false`)
2. Review submission bodies (the summary box when someone submits a review):
   `gh api repos/{owner}/{repo}/pulls/{n}/reviews --jq '.[] | select(.body != "")'`
3. Issue-level comments (the "overall" comments at the bottom of the PR):
   `gh api repos/{owner}/{repo}/issues/{n}/comments --paginate`
4. The PR description itself, when a reviewer has edited it

For 2 and 3, filter out bots (`select(.user.login | endswith("[bot]") | not)`)
but scan bot output for AI-review findings, which arrive as a review body
rather than an inline thread.
