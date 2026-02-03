# Path — Self-evolving agent kernel for Claude Code

A Claude Code extension that learns from feedback by modifying its own operating rules. Principled safety guarantees via human-in-the-loop enforcement.

## Install

Intall in local project folder:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zhenzhongxu/path-claudecode/HEAD/install.sh)"
```

Or clone and run locally:

```bash
git clone https://github.com/zhenzhongxu/path-claudecode.git
cd your-project
bash /path/to/install.sh
```

## How It Works

After completing a task in ClaudeCode, the agent follows the self-evolution cycle:

```
complete task → summarize → ask for feedback → /evolve → modify rules → next task uses evolved rules
```

Your feedback accumulates as evolved rules in `.claude/rules/{world,valence,skill}/`, persisting personalized agent expertise, domain knowledge, and agent self-model across sessions.

## Skills

| Skill           | What it does                                                                        |
| --------------- | ----------------------------------------------------------------------------------- |
| `/evolve`       | Analyze feedback, classify the domain, edit the relevant rules file, log the change |
| `/reflect`      | Read-only analysis of event log patterns and evolution trajectory                   |
| `/export-state` | Export all state as a portable KernelSnapshot JSON                                  |

### Example

```
You: "Refactor the auth module"
Agent: [does the work, summarizes, asks for feedback]
You: "You over-engineered it — I wanted minimal changes"
You: /evolve
Agent: → classifies as valence issue
       → edits .claude/rules/valence/priorities.md
       → adds "Prefer minimal, focused changes over comprehensive refactors"
       → next task uses the evolved rule
```

## Internal Models

The agent's knowledge is split into three domains that evolve independently:

| Domain      | Directory                | Question                                          |
| ----------- | ------------------------ | ------------------------------------------------- |
| **World**   | `.claude/rules/world/`   | "What is?" — context, environment, self-knowledge |
| **Valence** | `.claude/rules/valence/` | "What matters?" — priorities, evaluation criteria |
| **Skill**   | `.claude/rules/skill/`   | "How to do?" — techniques, tool patterns          |

At step 0, these start mostly empty. They fill in as you give feedback and run `/evolve`.

## Event Log Sinks

Events are written to the local JSONL file by default. You can configure additional sinks (webhook, shell command) in `.claude/path-kernel/config.json`:

```json
{
  "sinks": [
    { "type": "jsonl", "path": ".claude/path-kernel/event-log.jsonl", "enabled": true },
    { "type": "webhook", "url": "https://example.com/events", "enabled": true },
    { "type": "command", "command": "cat >> /tmp/events.jsonl", "enabled": true }
  ]
}
```

See `ARCHITECTURE.md` for full sink type reference.

## The Three Invariants

1. **The loop is protected** — the perceive-act-feedback-reflect-modify cycle cannot be disabled or bypassed
2. **All changes are logged** — every self-modification is recorded in the append-only event log
3. **The principal stays in control** — the human can halt, inspect, and roll back at any time

These are enforced by four defense-in-depth layers. See `ARCHITECTURE.md` for the full enforcement mapping.

## Project Structure

```
install.sh                             # One-command installer
CLAUDE.md                              # Composed mutable surface
test/                                  # bats-core test suite
.claude/
  settings.json                        # Deny rules + hook config
  rules/
    kernel/                            # Immutable — agent cannot modify
      invariants.md
      cycle-protocol.md
    world/                             # "What is?"
      environment.md
      self-model.md
    valence/                           # "What matters?"
      priorities.md
      tradeoffs.md
    skill/                             # "How to do?"
      tool-patterns.md
      domain-expertise.md
  skills/
    evolve/SKILL.md
    reflect/SKILL.md
    export-state/SKILL.md
  hooks/
    pre-edit-guard.sh                  # PreToolUse: block protected file edits
    post-edit-logger.sh                # PostToolUse: log mutable surface edits
    session-start-init.sh              # SessionStart: init event + state restore
    user-prompt-logger.sh              # UserPromptSubmit: log external perception
    session-end-logger.sh              # SessionEnd: bookend for system:init
    append-event.sh                    # Utility for structured event logging
  path-kernel/                         # Runtime state
    config.json                        # Protected file lists (agentCanModify/agentCannotModify)
    event-log.jsonl                    # Append-only event log
    state.json                         # Cross-session cycle state
    exports/                           # Migration snapshots
```

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

**Prerequisites:** `bats`, `jq`, `git`

```bash
# Run all tests
bats test/

# Run a single test file
bats test/install_fresh.bats

# Verbose output
bats --verbose-run test/
```

The devcontainer (`.devcontainer/`) installs all dependencies automatically including bats v1.11.1.

**Test files:**

| File                       | What it covers                                      |
| -------------------------- | --------------------------------------------------- |
| `install_fresh.bats`       | Fresh install into an empty project                 |
| `install_flags.bats`       | Installer CLI flags (`--yes`, `--help`)             |
| `install_urls.bats`        | URL consistency between README and install.sh       |
| `merge_settings.bats`      | Merging with existing settings.json                 |
| `merge_claude_md.bats`     | Merging with existing CLAUDE.md                     |
| `hooks.bats`               | Hook scripts (guard, logger, init)                  |
| `override.bats`            | Override/conflict handling                           |
| `kernel_enforcement.bats`  | Structural consistency of enforcement layers        |
| `agent_enforcement.bats`   | Claude Code deny rules + preflight format checks    |
| `cycle_protocol.bats`      | End-to-end self-evolution cycle behavior             |
| `sinks_integration.bats`   | Streaming sink delivery (Redis, NATS, Redpanda)      |

Each test runs in an isolated sandbox (temp dir with `git init`) that is cleaned up automatically.

### Live agent tests

The `agent_enforcement.bats` and `cycle_protocol.bats` files include tests that run the actual `claude` CLI to verify enforcement and behavior at runtime. These are skipped by default and require opting in:

```bash
# Run all tests (agent tests skip without the flag)
bats test/

# Run with live agent tests enabled
PATH_AGENT_TESTS=1 bats test/

# Run just the cycle protocol tests with verbose output
PATH_AGENT_TESTS=1 bats --verbose-run test/cycle_protocol.bats
```

**Requirements:** `claude` CLI installed with valid API authentication.

### Streaming sink integration tests

The `sinks_integration.bats` file tests end-to-end delivery of events through the `command` sink type to real streaming services. These require the devcontainer docker-compose services (Redis, NATS, Redpanda) to be running.

```bash
# Run with streaming sink tests enabled
PATH_SINK_TESTS=1 bats test/sinks_integration.bats

# Run full suite including sink tests
PATH_SINK_TESTS=1 bats test/
```

**Requirements:** Devcontainer running with docker-compose services (Redis, NATS, Redpanda). The `redis-cli`, `nats`, and `rpk` CLI tools are installed automatically by `.devcontainer/setup.sh`.

**What the sink tests cover:**

- **Redis Streams** — event delivered via `redis-cli -x XADD` and verified with `XREVRANGE`
- **NATS JetStream** — event published via `nats pub` and verified with `nats stream get`
- **Redpanda (Kafka API)** — event produced via `rpk topic produce` and consumed with `rpk topic consume`
- **Fan-out** — single event reaches all three streaming sinks plus jsonl simultaneously

**What the agent tests cover:**

- **Deny rule enforcement** — the agent cannot modify any of the 5 protected files (`invariants.md`, `cycle-protocol.md`, `settings.json`, `event-log.jsonl`, `config.json`), even with `--dangerously-skip-permissions`
- **Positive control** — the agent can modify mutable rule files (confirms enforcement is targeted)
- **Evolve cycle (pass@3)** — a multi-turn test gives the agent a task, then provides feedback. The agent auto-invokes the evolve skill and modifies rules, without any mention of `/evolve` in the prompt. Uses outcome-based grading per [Anthropic's agent eval methodology](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents): rule file modified, events logged, kernel files intact
- **Adversarial boundary** — feedback explicitly asking to modify kernel files is blocked by deny rules

## Migration

State is portable between projects via KernelSnapshot:

```
/export-state    → .claude/path-kernel/exports/snapshot-<timestamp>.json
```

## The Incremental Path

| Step | What It Adds             | Autonomy             | Status          |
| ---- | ------------------------ | -------------------- | --------------- |
| 0    | Self-evolution kernel    | Human evaluates      | **Implemented** |
| 1    | Event log                | Human teaches        | **Implemented** |
| 2    | Structured memory        | Human teaches        | Future          |
| 3    | Self-model + calibration | Human audits         | Future          |
| 4    | Internal evaluation      | Agent self-evaluates | Future          |

The kernel is step 0 of a longer arc toward composable, self-evolving agent architectures. More on this soon.

## Reference

- `ARCHITECTURE.md` — Implementation architecture and design reference
