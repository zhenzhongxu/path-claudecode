#!/bin/bash
# PostToolUse hook: logs modifications to mutable surfaces.
# Fires after every Edit/Write tool call.
# Appends a modification event to .claude/path-kernel/event-log.jsonl.
#
# Mutable surfaces are read from .claude/path-kernel/config.json (agentCanModify).

SCRIPT_DIR=$(dirname "$0")
CONFIG_FILE="$SCRIPT_DIR/../path-kernel/config.json"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Read mutable surface patterns from config.json
if [ ! -f "$CONFIG_FILE" ]; then
  exit 0
fi

MUTABLE_PATTERNS=$(jq -r '.agentCanModify[]' "$CONFIG_FILE" 2>/dev/null) || exit 0

IS_MUTABLE=false
while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue
  # Patterns are relative (e.g., "CLAUDE.md", ".claude/rules/world/*").
  # FILE_PATH is absolute. Match as a suffix using [[ ]] glob.
  if [[ "$FILE_PATH" == */$pattern ]] || [[ "$FILE_PATH" == $pattern ]]; then
    IS_MUTABLE=true
    break
  fi
done <<< "$MUTABLE_PATTERNS"

if [ "$IS_MUTABLE" != "true" ]; then
  exit 0
fi

# Extract edit context from tool input
OLD_STR=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
NEW_STR=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null)

# Build data payload with available context
if [ -n "$OLD_STR" ] && [ -n "$NEW_STR" ]; then
  # Edit tool — include diff
  DATA=$(jq -n -c \
    --arg file "$FILE_PATH" \
    --arg old "$OLD_STR" \
    --arg new "$NEW_STR" \
    '{file:$file, source:"claude-code-hook", tool:"Edit", old_string:$old, new_string:$new}')
elif [ -n "$CONTENT" ]; then
  # Write tool — include first 200 chars as preview
  PREVIEW=$(echo "$CONTENT" | head -c 200)
  DATA=$(jq -n -c \
    --arg file "$FILE_PATH" \
    --arg preview "$PREVIEW" \
    '{file:$file, source:"claude-code-hook", tool:"Write", preview:$preview}')
else
  # Fallback — file path only
  DATA=$(jq -n -c --arg file "$FILE_PATH" '{file:$file, source:"claude-code-hook"}')
fi

# Read current prompt version from state.json
STATE_FILE="$SCRIPT_DIR/../path-kernel/state.json"
PROMPT_VERSION=0
if [ -f "$STATE_FILE" ]; then
  PROMPT_VERSION=$(jq '.cycleCount // 0' "$STATE_FILE" 2>/dev/null) || PROMPT_VERSION=0
fi

bash "$SCRIPT_DIR/append-event.sh" \
  "modification:applied" \
  "$DATA" \
  "$PROMPT_VERSION" 2>/dev/null

exit 0
