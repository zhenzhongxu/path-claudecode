#!/bin/bash
# SessionStart hook: initializes the self-evolution cycle state.
# Logs a system:init event and checks for pending feedback.

SCRIPT_DIR="$(dirname "$0")"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Read current prompt version from state.json
STATE_FILE="$PROJECT_DIR/.claude/path-kernel/state.json"
PROMPT_VERSION=0
if [ -f "$STATE_FILE" ]; then
  PROMPT_VERSION=$(jq '.cycleCount // 0' "$STATE_FILE" 2>/dev/null) || PROMPT_VERSION=0
fi

# Log session start
bash "$PROJECT_DIR/.claude/hooks/append-event.sh" \
  "system:init" \
  '{"source":"claude-code","event":"session-start"}' \
  "$PROMPT_VERSION" 2>/dev/null

# Check if there's a pending cycle state
if [ -f "$PROJECT_DIR/.claude/path-kernel/state.json" ]; then
  AWAITING=$(jq -r '.awaitingFeedback // false' "$PROJECT_DIR/.claude/path-kernel/state.json" 2>/dev/null)
  if [ "$AWAITING" = "true" ]; then
    LAST_TASK=$(jq -r '.lastTask // "unknown"' "$PROJECT_DIR/.claude/path-kernel/state.json" 2>/dev/null)
    echo "{\"additionalContext\":\"CYCLE IN PROGRESS: A task was completed in a previous session (task: $LAST_TASK). Ask the user for feedback before starting new work.\"}"
  fi
fi

exit 0
