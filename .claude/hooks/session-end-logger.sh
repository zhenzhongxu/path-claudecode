#!/bin/bash
# SessionEnd hook: bookend for system:init.

SCRIPT_DIR="$(dirname "$0")"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

INPUT=$(cat)
REASON=$(echo "$INPUT" | jq -r '.reason // "unknown"' 2>/dev/null)

STATE_FILE="$PROJECT_DIR/.claude/path-kernel/state.json"
PROMPT_VERSION=0
[ -f "$STATE_FILE" ] && PROMPT_VERSION=$(jq '.cycleCount // 0' "$STATE_FILE" 2>/dev/null) || true

DATA=$(jq -n -c --arg reason "$REASON" \
  '{source:"claude-code","event":"session-end",reason:$reason}')

bash "$SCRIPT_DIR/append-event.sh" "system:session-end" "$DATA" "$PROMPT_VERSION" 2>/dev/null
exit 0
