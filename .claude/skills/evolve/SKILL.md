---
name: evolve
description: "Full self-evolution cycle: analyze feedback, reflect, modify rules"
---

# /evolve — Self-Evolution Cycle

You are executing the self-evolution cycle. This is the core loop that enables learning from feedback.

## Input

The user has provided feedback about your recent performance. The feedback may be explicit ("you should have done X instead of Y") or implicit (a correction, a different approach, frustration).

## Procedure

### Step 1: Gather Context

Read the following files to understand current state:

1. **Recent events**: Read `.claude/path-kernel/event-log.jsonl` (last 20 lines) to understand recent actions and modifications.
2. **Current rules**: Read `.claude/path-kernel/config.json` for the authoritative list of mutable rule files (`agentCanModify`). Read each file listed there. These span three domains under `.claude/rules/`: world, valence, and skill.
3. **Cycle state**: Read `.claude/path-kernel/state.json` if it exists, for cross-session context.

### Step 1b: Log Feedback Event

After gathering context, emit a `feedback:human` event to the event log. This captures the feedback input for observability.

```bash
PROMPT_VERSION=$(jq '.cycleCount // 0' .claude/path-kernel/state.json 2>/dev/null || echo 0)
bash .claude/hooks/append-event.sh "feedback:human" \
  '{"summary":"<brief feedback summary>"}' "$PROMPT_VERSION"
```

Replace `<brief feedback summary>` with a 1-sentence summary of the user's feedback.

### Step 2: Analyze the Gap

Compare what happened (the feedback) against what should have happened. Identify:

- **What went wrong** (or what could be improved)
- **Root cause**: Was it a misunderstanding of the situation (world), wrong priorities (valence), or poor technique (skill)?
- **Specific change** that would prevent this gap in the future

### Step 2b: Log Analysis Event

After analyzing the gap, emit an `evolve:analysis` event capturing the analysis results.

```bash
PROMPT_VERSION=$(jq '.cycleCount // 0' .claude/path-kernel/state.json 2>/dev/null || echo 0)
bash .claude/hooks/append-event.sh "evolve:analysis" \
  '{"summary":"<gap identified>","domain":"<world|valence|skill>","proposed_change":"<brief>"}' "$PROMPT_VERSION"
```

Replace the placeholders with the actual analysis from Step 2.

### Step 3: Classify the Modification Domain

Route the change to the correct internal model:

| If the issue is... | Domain | Target file(s) |
|---------------------|--------|----------------|
| Misunderstood the task, context, or environment | **world** | `.claude/rules/world/environment.md` or `self-model.md` |
| Wrong priorities, misjudged importance | **valence** | `.claude/rules/valence/priorities.md` or `tradeoffs.md` |
| Bad technique, wrong tool, poor execution | **skill** | `.claude/rules/skill/tool-patterns.md` or `domain-expertise.md` |
| Ambiguous / multiple domains | **undifferentiated** | Edit the most relevant single file; don't over-spread |

### Step 4: Propose and Apply the Modification

1. **Draft the change**: Write the specific text to add, modify, or remove from the target rules file.
2. **State the rationale**: Explain why this change addresses the gap.
3. **Log the proposal**: Before applying the edit, emit a `modification:proposal` event:
   ```bash
   PROMPT_VERSION=$(jq '.cycleCount // 0' .claude/path-kernel/state.json 2>/dev/null || echo 0)
   bash .claude/hooks/append-event.sh "modification:proposal" \
     '{"domain":"<world|valence|skill>","target":"<file>","rationale":"<why>"}' "$PROMPT_VERSION"
   ```
   Replace placeholders with the actual domain, target file, and rationale.
4. **Apply the edit**: Use the Edit tool to modify the target `.claude/rules/{domain}/*.md` file.
   - Keep changes focused and incremental. Prefer adding a specific lesson over rewriting entire sections.
   - Preserve existing content unless it directly contradicts the new learning.
5. **The PostToolUse hook will automatically log this modification** to `.claude/path-kernel/event-log.jsonl`.

### Step 5: Recompose CLAUDE.md

After modifying rules, update `CLAUDE.md` to reflect the change:

1. Read the current `CLAUDE.md`.
2. Increment the version comment at the top.
3. The `@` import references in CLAUDE.md point to the rules files, so the content updates automatically. But if the structure of CLAUDE.md itself needs updating (new sections, reordering), apply those edits now.

### Step 6: Update Cycle State

Write to `.claude/path-kernel/state.json`:

```json
{
  "lastTask": "<brief description of the task>",
  "lastFeedback": "<brief summary of feedback>",
  "lastModification": "<domain>/<filename>",
  "lastModificationRationale": "<why>",
  "awaitingFeedback": false,
  "cycleCount": <increment from previous>
}
```

### Step 7: Report

Tell the user:
1. What you analyzed
2. What domain you classified the feedback into (world/valence/skill)
3. What specific change you made and to which file
4. Why this change should help in the future

## Constraints

See `.claude/rules/kernel/invariants.md` for immutable constraints and `.claude/path-kernel/config.json` (`agentCannotModify`) for the protected file list.

- If you're unsure whether a change is warranted, say so and ask for more feedback rather than making a speculative change.
- Keep rule files concise. Prefer specific, actionable lessons over vague principles.
- One evolution cycle = one focused change. Don't try to fix everything at once.
