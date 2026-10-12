# Reference: PR slicing

Shared by the agents that plan or check a PR breakdown (`plan-reviewer`, and any engineering specialist you hire).

## The rule

**Ship a feature in one PR.** Several tickets can link to one PR. Split a PR only where the code forces a break, never for convenience.

## Required breaks

Edit this list to match your own stack. A split not on it is a plan defect.

| Required break | Why it forces a split |
|---|---|
| Database migration vs application code | Often cannot ship in the same deploy |
| API or schema change vs code that consumes it | The contract must land first |
| Separate repos | One PR per repo |
| Removal of something still in use | Only after nothing uses it |

## Not reasons to split

- "It's getting big."
- "It's easier to review."
- One PR per ticket.

## What a plan's PR breakdown must show

For every split, name which required break forces it. A split with no named break is a plan defect. No split at all is fine and expected: most features fit in one PR. Stacked PRs are normal, but only along required breaks.
