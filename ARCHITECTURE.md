# Architecture: Self-Evolution Kernel

## Current Implementation (Claude Code Adapter)

Claude Code IS the LLM — no separate API calls. Behavior is shaped by CLAUDE.md and rules files.

### Self-Evolution Loop

```
user gives task → Claude acts using CLAUDE.md + rules
                → user provides feedback
                → Claude auto-invokes evolve skill (or user types /evolve)
                → Claude analyzes gap, classifies domain
                → Claude edits .claude/rules/{world,valence,skill}/*.md
                → hooks enforce invariants and log the change
                → next task uses evolved rules
```

### Skill Invocation: Explicit vs Implicit

The `/evolve` skill does not require explicit invocation. Claude Code loads skill
descriptions into context at session start. When the context matches a skill's
description, the agent auto-invokes it and loads the full SKILL.md procedure.

This was verified empirically via `test/cycle_protocol.bats`: a multi-turn test
gave the agent feedback ("you used bash grep instead of the Grep tool") without
mentioning `/evolve` or naming target files. The agent:

1. Recognized the feedback matched the evolve skill description
2. Auto-loaded the full 7-step procedure from SKILL.md
3. Classified the feedback as skill domain
4. Modified `.claude/rules/skill/tool-patterns.md`
5. Updated `state.json` with the correct schema (only defined in SKILL.md)
6. Incremented the CLAUDE.md version

The two-stage loading mechanism:

| Stage | What loads | When |
|-------|-----------|------|
| Session start | `description` field from SKILL.md frontmatter | Always — Claude knows what skills exist |
| Invocation | Full SKILL.md content (procedure, tables, schemas) | On `/evolve` command OR auto-invocation by model |

The `disable-model-invocation: true` frontmatter field can prevent auto-invocation,
restricting a skill to explicit `/command` use only. The evolve skill does not set
this, so both paths work.

**Implication**: SKILL.md is not just a convenience wrapper — it carries the
procedure (domain classification table, state.json schema, version increment logic)
that CLAUDE.md references but does not contain. Without SKILL.md, the agent would
have the intent to evolve (from CLAUDE.md) but not the structured procedure.

### Enforcement: Defense in Depth

| Layer               | Mechanism               | Purpose                                 |
| ------------------- | ----------------------- | --------------------------------------- |
| Settings deny rules | `.claude/settings.json` | Structural — agent cannot override      |
| PreToolUse hook     | `pre-edit-guard.sh`     | Blocks edits to protected files         |
| PostToolUse hook    | `post-edit-logger.sh`   | Auto-logs all mutable surface edits     |
| Kernel rules        | `.claude/rules/kernel/` | Behavioral instructions (always loaded) |

### Invariant Mapping

| Invariant                              | Enforcement                                            |
| -------------------------------------- | ------------------------------------------------------ |
| 1. Loop is protected                   | Kernel rules (always loaded), cycle-protocol.md        |
| 2. All modifications logged            | PostToolUse hooks (automatic), deny Write on event-log |
| 3. Principal can halt/inspect/rollback | Native (Ctrl+C, Read tool, git revert)                 |

### Internal Model Domains

| Domain  | Directory                | Question                                          |
| ------- | ------------------------ | ------------------------------------------------- |
| World   | `.claude/rules/world/`   | "What is?" — context, environment, self-knowledge |
| Valence | `.claude/rules/valence/` | "What matters?" — priorities, evaluation criteria |
| Skill   | `.claude/rules/skill/`   | "How to do?" — techniques, tool patterns          |

### Event Log Format

Append-only JSONL in `.claude/path-kernel/event-log.jsonl`. Each line is a JSON object:

```json
{
  "id": "uuid",
  "timestamp": "ISO 8601",
  "type": "modification:applied",
  "data": { "file": ".claude/rules/skill/tool-patterns.md" },
  "promptVersion": 0
}
```

Event types produced by hooks:
- `system:init` — SessionStart hook logs session initialization
- `modification:applied` — PostToolUse hook logs edits to mutable surfaces

Event types produced by the agent (via `append-event.sh`):
- `system:export` — `/export-state` skill logs snapshot creation

Event types available for future use:
- `feedback:human`, `reflection:analysis`, `modification:rejected`, `perception:situation`, `perception:outcome`

### Export Format (KernelSnapshot)

`/export-state` produces a self-contained JSON snapshot:

```json
{
  "schemaVersion": 1,
  "exportedAt": "ISO 8601",
  "source": "claude-code",
  "events": [],
  "currentPrompt": "contents of CLAUDE.md",
  "currentVersion": 1,
  "promptVersions": [],
  "protectedConfig": {},
  "internalModels": {
    "world": [
      { "filename": "environment.md", "content": "..." },
      { "filename": "self-model.md", "content": "..." }
    ],
    "valence": [
      { "filename": "priorities.md", "content": "..." },
      { "filename": "tradeoffs.md", "content": "..." }
    ],
    "skill": [
      { "filename": "tool-patterns.md", "content": "..." },
      { "filename": "domain-expertise.md", "content": "..." }
    ]
  }
}
```
