# Token economy: why the rules exist

The rules live in `~/.claude/CLAUDE.md`. This is the reasoning behind them.

Running a shell command is free. What costs tokens is reading its result, and that result is then sent back to the model on every later turn for the rest of the conversation, not just once. A single large tool result compounds in cost with every step that comes after it.

Observed on a real task: a run that made about 150 tool calls, mostly re-running a full test suite after each small fix, cost over three times as much as a comparable run of about 50 calls doing pure investigation. Iteration count and result size drive cost more than which model is doing the thinking.

Record your own measurements here as you make them; a rule with evidence behind it survives the urge to skip it.
