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

# Construct event
EVENT=$(jq -n -c \
  --arg id "$UUID" \
  --arg ts "$TIMESTAMP" \
  --arg type "$EVENT_TYPE" \
  --argjson data "$DATA" \
  --argjson pv "$PROMPT_VERSION" \
  '{id:$id, timestamp:$ts, type:$type, data:$data, promptVersion:$pv}')

# --- Dispatch to sinks ---
CONFIG_PATH="$PROJECT_DIR/.claude/path-kernel/config.json"
_SINK_LIST=$(jq -c '.sinks // []' "$CONFIG_PATH" 2>/dev/null) || _SINK_LIST='[]'

if [ "$_SINK_LIST" = "[]" ] || [ -z "$_SINK_LIST" ]; then
  # Fallback: no sinks configured → direct append (backward compat)
  mkdir -p "$(dirname "$LOG_PATH")"
  echo "$EVENT" >> "$LOG_PATH"
else
  while IFS= read -r _SINK_ENTRY; do
    [ -z "$_SINK_ENTRY" ] && continue
    _SINK_TYPE=$(echo "$_SINK_ENTRY" | jq -r '.type')
    _SINK_ENABLED=$(echo "$_SINK_ENTRY" | jq -r 'if .enabled == false then "false" else "true" end')
    [ "$_SINK_ENABLED" = "false" ] && continue

    case "$_SINK_TYPE" in
      jsonl)
        _SINK_PATH=$(echo "$_SINK_ENTRY" | jq -r '.path')
        [ "${_SINK_PATH:0:1}" != "/" ] && _SINK_PATH="$PROJECT_DIR/$_SINK_PATH"
        mkdir -p "$(dirname "$_SINK_PATH")"
        echo "$EVENT" >> "$_SINK_PATH"
        ;;
      webhook)
        _SINK_URL=$(echo "$_SINK_ENTRY" | jq -r '.url')
        _SINK_TMPFILE=$(mktemp)
        echo "$EVENT" > "$_SINK_TMPFILE"
        # Build header args array
        _SINK_CURL_ARGS=(-s -X POST -H "Content-Type: application/json")
        while IFS= read -r _SINK_HDR; do
          [ -z "$_SINK_HDR" ] && continue
          _SINK_CURL_ARGS+=(-H "$_SINK_HDR")
        done <<< "$(echo "$_SINK_ENTRY" | jq -r '.headers // {} | to_entries[] | "\(.key): \(.value)"' 2>/dev/null)"
        (curl "${_SINK_CURL_ARGS[@]}" --data-binary @"$_SINK_TMPFILE" "$_SINK_URL" &>/dev/null; rm -f "$_SINK_TMPFILE") &
        ;;
      command)
        _SINK_CMD=$(echo "$_SINK_ENTRY" | jq -r '.command')
        (echo "$EVENT" | bash -c "$_SINK_CMD" &>/dev/null) &
        ;;
    esac
  done <<< "$(echo "$_SINK_LIST" | jq -c '.[]')"
fi
