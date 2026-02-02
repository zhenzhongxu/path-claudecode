#!/bin/bash
# PreToolUse hook: validates edits to mutable surfaces.
# Blocks edits to protected files as a defense-in-depth measure
# (settings.json deny rules are the primary enforcement).
#
# Protected paths are read from .claude/path-kernel/config.json (agentCannotModify).
# Exit 0 = allow, Exit 2 = block

SCRIPT_DIR=$(dirname "$0")
CONFIG_FILE="$SCRIPT_DIR/../path-kernel/config.json"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  # No file_path in input (e.g., Bash tool) — allow
  exit 0
fi

# Read protected patterns from config.json
if [ ! -f "$CONFIG_FILE" ]; then
  # If config is missing, fall through (settings.json deny rules are primary enforcement)
  exit 0
fi

PATTERNS=$(jq -r '.agentCannotModify[]' "$CONFIG_FILE" 2>/dev/null) || exit 0

while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue
  # Patterns are relative (e.g., ".claude/rules/kernel/*").
  # FILE_PATH is absolute. Match as a suffix using [[ ]] glob.
  if [[ "$FILE_PATH" == */$pattern ]] || [[ "$FILE_PATH" == $pattern ]]; then
    echo "{\"decision\":\"block\",\"reason\":\"Cannot modify protected path ($pattern)\"}"
    exit 2
  fi
done <<< "$PATTERNS"

# Allow everything else
exit 0
