---
name: export-state
description: "Export kernel state as a portable KernelSnapshot for migration"
---

# /export-state — State Export for Migration

You are exporting the current kernel state into a portable snapshot format. This snapshot can be imported into a standalone agent instance (or another Claude Code project) to transfer accumulated learning.

## Purpose

The KernelSnapshot is the **migration currency** — a self-contained JSON file that preserves:
- All events (the full learning history)
- Current evolved rules (the accumulated expertise)
- Prompt version history (the evolution trajectory)
- Internal model state (world/valence/skill differentiation)

## Procedure

### Step 1: Gather All State

Read the following files:

1. **Event log**: `.claude/path-kernel/event-log.jsonl` — read all lines, parse each as JSON, collect into an array.
2. **Current rules** (internal models): Read `.claude/path-kernel/config.json` for the authoritative list of mutable rule files (`agentCanModify`). Read each file listed there. These span three domains under `.claude/rules/`: world, valence, and skill.
3. **Current CLAUDE.md**: The composed mutable surface.
4. **Cycle state**: `.claude/path-kernel/state.json` if it exists.
5. **Protected config**: `.claude/path-kernel/config.json`.

### Step 2: Assemble the Snapshot

Construct a JSON object matching the KernelSnapshot schema:

```json
{
  "schemaVersion": 1,
  "exportedAt": "<ISO 8601 timestamp>",
  "source": "claude-code",
  "events": [<all events from event-log.jsonl>],
  "currentPrompt": "<contents of CLAUDE.md>",
  "currentVersion": <number of modification:applied events + 1>,
  "promptVersions": [<extracted from modification events>],
  "protectedConfig": <contents of .claude/path-kernel/config.json>,
  "internalModels": {
    "world": [
      { "filename": "environment.md", "content": "<file contents>" },
      { "filename": "self-model.md", "content": "<file contents>" }
    ],
    "valence": [
      { "filename": "priorities.md", "content": "<file contents>" },
      { "filename": "tradeoffs.md", "content": "<file contents>" }
    ],
    "skill": [
      { "filename": "tool-patterns.md", "content": "<file contents>" },
      { "filename": "domain-expertise.md", "content": "<file contents>" }
    ]
  }
}
```

### Step 3: Write the Snapshot

1. Ensure `.claude/path-kernel/exports/` directory exists (create if needed).
2. Write the snapshot to `.claude/path-kernel/exports/snapshot-<timestamp>.json` where `<timestamp>` is the current ISO date-time with colons replaced by dashes (e.g., `snapshot-2026-01-15T10-30-00.json`).
3. Pretty-print the JSON (2-space indent) for human readability.

### Step 4: Log the Export

Use bash to run:
```bash
bash .claude/hooks/append-event.sh "system:export" '{"file":".claude/path-kernel/exports/snapshot-<timestamp>.json"}' <version>
```

### Step 5: Report

Tell the user:
1. The snapshot file path
2. Summary stats: number of events, number of rule files, current version
3. How to use the snapshot:
   - For another Claude Code project: Copy the snapshot into the target project's `.claude/path-kernel/exports/` directory

## Constraints

- This skill is **read-only** with respect to kernel state — it only creates a new file in `.claude/path-kernel/exports/`.
- Include ALL events — don't filter or summarize. The full history is the moat.
- Strip the YAML frontmatter from rules files when including in `internalModels` (the frontmatter is Claude Code-specific metadata).
