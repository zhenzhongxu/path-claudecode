#!/bin/bash
# CLI utility for appending events to the event log.
# Used by Claude Code hooks (which run as shell scripts).
# Pure bash + jq — no Node.js required.
#
# Usage: bash .claude/hooks/append-event.sh <event-type> '<json-data>' [prompt-version]
#
# Example:
#   bash .claude/hooks/append-event.sh modification:applied '{"file":"CLAUDE.md"}' 3

SCRIPT_DIR="$(dirname "$0")"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_PATH="$PROJECT_DIR/.claude/path-kernel/event-log.jsonl"

EVENT_TYPE="$1"
DATA_STR="${2:-'{}'}"
PROMPT_VERSION="${3:-0}"

if [ -z "$EVENT_TYPE" ]; then
  echo "Usage: bash .claude/hooks/append-event.sh <event-type> [json-data] [prompt-version]" >&2
  exit 1
fi

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_PATH")"

# Generate UUID
if command -v uuidgen >/dev/null 2>&1; then
  UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
elif [ -f /proc/sys/kernel/random/uuid ]; then
  UUID=$(cat /proc/sys/kernel/random/uuid)
else
  UUID=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n' | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)/\1-\2-\3-\4-/')
fi

# ISO timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Parse data JSON (validate or wrap as raw string)
DATA=$(echo "$DATA_STR" | jq -c '.' 2>/dev/null) || DATA=$(jq -n -c --arg raw "$DATA_STR" '{"raw":$raw}')

# Construct and append event
jq -n -c \
  --arg id "$UUID" \
  --arg ts "$TIMESTAMP" \
  --arg type "$EVENT_TYPE" \
  --argjson data "$DATA" \
  --argjson pv "$PROMPT_VERSION" \
  '{id:$id, timestamp:$ts, type:$type, data:$data, promptVersion:$pv}' >> "$LOG_PATH"
