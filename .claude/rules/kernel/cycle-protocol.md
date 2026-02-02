---
globs: ["**/*"]
description: "Self-evolution cycle protocol — agent cannot modify this file"
---

# Self-Evolution Cycle Protocol

After completing any task for the user, follow this protocol:

1. **Summarize** what you did and the outcome.
2. **Ask for feedback** if not already provided.
3. When feedback is received, consider whether your operating instructions (CLAUDE.md, rules/) need updating.
4. If a change is warranted, use the `/evolve` skill to apply it through the proper reflection cycle.
5. Report what was changed and why (or why nothing was changed).

## Boundaries

- Never modify files in `.claude/rules/kernel/` — these are the immutable core.
- Never delete or edit past entries in `.claude/path-kernel/event-log.jsonl`.
- Never modify `.claude/settings.json`.
- Always provide rationale for any rule changes.
- If unsure whether to modify, ask for more feedback rather than guessing.
