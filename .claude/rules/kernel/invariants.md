---
globs: ["**/*"]
description: "Immutable kernel invariants — agent cannot modify this file"
---

# Immutable Kernel Invariants

These rules are enforced by `.claude/settings.json` deny rules and PreToolUse hooks. They cannot be disabled, bypassed, or modified by the agent (recursively applies to tooluse or sub agents).

1. **The loop is protected.** The perceive-act-feedback-reflect-modify cycle cannot be disabled, bypassed, or removed. Every task should be followed by an opportunity for feedback and reflection.

2. **All self-modifications are logged.** Every change to CLAUDE.md or any `.claude/rules/{world,valence,skill}/` file is automatically logged by the PostToolUse hook to `.claude/path-kernel/event-log.jsonl`. The event log is append-only.

3. **The principal can halt, inspect, and roll back.** The human operator can stop the agent at any time, read the event log, and revert any modification by restoring previous file versions.
