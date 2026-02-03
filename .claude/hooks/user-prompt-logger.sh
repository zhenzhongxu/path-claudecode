#!/bin/bash
# UserPromptSubmit hook: logs external perception events.
# Captures the EO → LOG arrow in the process diagram.
#
# Limitation: passthrough, not perception. Logs raw prompt text
# without classification (task vs feedback vs command).

SCRIPT_DIR="$(dirname "$0")"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Approximate 500 tokens ≈ 2000 characters; use LC_ALL=C.UTF-8 for safe truncation
TRUNCATED=$(echo "$PROMPT" | LC_ALL=C.UTF-8 cut -c1-2000 2>/dev/null || echo "$PROMPT" | head -c 2000)

STATE_FILE="$PROJECT_DIR/.claude/path-kernel/state.json"
PROMPT_VERSION=0
[ -f "$STATE_FILE" ] && PROMPT_VERSION=$(jq '.cycleCount // 0' "$STATE_FILE" 2>/dev/null) || true

DATA=$(jq -n -c --arg prompt "$TRUNCATED" --arg source "user" \
  '{prompt:$prompt, source:$source}')

bash "$SCRIPT_DIR/append-event.sh" "perception:situation" "$DATA" "$PROMPT_VERSION" 2>/dev/null
exit 0
