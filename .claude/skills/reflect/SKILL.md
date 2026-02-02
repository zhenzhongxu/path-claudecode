---
name: reflect
description: "Deep reflection on patterns in the event log — analysis only, no modifications"
---

# /reflect — Deep Reflection

You are performing a deep reflection on accumulated experience. This is a read-only analysis — you will NOT modify any files.

## Purpose

Analyze the event log and current rules to identify patterns, recurring issues, and opportunities for improvement. This gives the user (and the agent) insight into the evolution trajectory.

## Procedure

### Step 1: Read the Event Log

Read `.claude/path-kernel/event-log.jsonl` in full. Parse each line as JSON. Group events by type. Common types include:

- `system:init` — Session initialization (hook-produced)
- `modification:applied` — Rule file changes (hook-produced)
- `system:export` — State snapshots (agent-produced)

Not all types may be present in early logs. Report what you find rather than expecting specific types.

### Step 2: Read Current Rules

Read `.claude/path-kernel/config.json` for the authoritative list of mutable rule files (`agentCanModify`). Read each file listed there. These span three domains under `.claude/rules/`: world, valence, and skill.

### Step 3: Analyze Patterns

Identify and report on:

1. **Feedback themes**: Are there recurring types of feedback? What keeps coming up?
2. **Modification trajectory**: How have the rules evolved? Is there a direction?
3. **Domain distribution**: Are modifications concentrated in one domain (world/valence/skill) or spread evenly? What does this suggest?
4. **Gaps**: Are there feedback items that haven't been addressed? Rules that seem stale or contradictory?
5. **Self-model accuracy**: Does the self-model (`.claude/rules/world/self-model.md`) match the actual performance patterns visible in the log?
6. **Version progression**: How many evolution cycles have occurred? What's the rate?

### Step 4: Recommendations

Based on the analysis, suggest (but do NOT apply):

- Specific rule changes that might help
- Rules that could be consolidated or removed
- Domains that need more attention
- Whether the agent might be ready for the next step in capability progression

### Step 5: Report

Present the analysis in a structured format:

```
## Reflection Summary

### Event Log Stats
- Total events: N
- Feedback events: N
- Modifications applied: N
- Modifications rejected: N
- Evolution cycles completed: N

### Feedback Themes
- [theme]: [frequency] — [example]

### Modification Trajectory
- [domain]: [count] changes — [direction/trend]

### Recommendations
1. [recommendation]
2. [recommendation]
```

## Constraints

- This skill is **read-only**. Do NOT modify any files.
- Do NOT invoke `/evolve` — present recommendations for the user to decide.
- Be honest about limitations: if there's insufficient data, say so.
- If the event log is empty or very small, note that the agent is too early in its evolution to identify meaningful patterns.
