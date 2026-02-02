#!/usr/bin/env bats
# Tests for hook scripts.
#
# Claude Code passes absolute file paths to hooks.
# Hook glob patterns like */.claude/rules/kernel/* expect a path prefix.
# We use $SANDBOX as the prefix to simulate real behavior.

load test_helper

setup() {
  setup_sandbox
  run_install
}
teardown() { teardown_sandbox; }

# --- pre-edit-guard.sh ---

@test "pre-edit-guard blocks kernel rules" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/rules/kernel/invariants.md\"}}' | bash .claude/hooks/pre-edit-guard.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"block"* ]]
}

@test "pre-edit-guard blocks settings.json" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/settings.json\"}}' | bash .claude/hooks/pre-edit-guard.sh"
  [ "$status" -eq 2 ]
}

@test "pre-edit-guard blocks event-log.jsonl" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/path-kernel/event-log.jsonl\"}}' | bash .claude/hooks/pre-edit-guard.sh"
  [ "$status" -eq 2 ]
}

@test "pre-edit-guard blocks config.json" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/path-kernel/config.json\"}}' | bash .claude/hooks/pre-edit-guard.sh"
  [ "$status" -eq 2 ]
}

@test "pre-edit-guard allows world rules" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/rules/world/environment.md\"}}' | bash .claude/hooks/pre-edit-guard.sh"
  [ "$status" -eq 0 ]
}

@test "pre-edit-guard allows CLAUDE.md" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/CLAUDE.md\"}}' | bash .claude/hooks/pre-edit-guard.sh"
  [ "$status" -eq 0 ]
}

@test "pre-edit-guard allows when no file_path" {
  run bash -c 'echo '"'"'{"tool_input":{"command":"ls"}}'"'"' | bash .claude/hooks/pre-edit-guard.sh'
  [ "$status" -eq 0 ]
}

# --- append-event.sh ---

@test "append-event creates valid JSONL" {
  bash .claude/hooks/append-event.sh "test:event" '{"key":"value"}' 0 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 1 ]
  head -1 .claude/path-kernel/event-log.jsonl | jq empty
}

@test "append-event entry has all required fields" {
  bash .claude/hooks/append-event.sh "test:event" '{"key":"value"}' 42 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq 'has("id")')" = "true" ]
  [ "$(echo "$line" | jq 'has("timestamp")')" = "true" ]
  [ "$(echo "$line" | jq 'has("type")')" = "true" ]
  [ "$(echo "$line" | jq 'has("data")')" = "true" ]
  [ "$(echo "$line" | jq 'has("promptVersion")')" = "true" ]
}

@test "append-event stores correct type, data, and promptVersion" {
  bash .claude/hooks/append-event.sh "modification:applied" '{"file":"CLAUDE.md"}' 3 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq -r '.type')" = "modification:applied" ]
  [ "$(echo "$line" | jq -r '.data.file')" = "CLAUDE.md" ]
  [ "$(echo "$line" | jq '.promptVersion')" -eq 3 ]
}

# --- session-start-init.sh ---

@test "session-start-init logs system:init event" {
  bash .claude/hooks/session-start-init.sh 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 1 ]
  [ "$(head -1 .claude/path-kernel/event-log.jsonl | jq -r '.type')" = "system:init" ]
}

@test "session-start-init detects pending feedback" {
  echo '{"lastTask":"refactor auth","lastFeedback":null,"lastModification":null,"lastModificationRationale":null,"awaitingFeedback":true,"cycleCount":1}' \
    > .claude/path-kernel/state.json

  run bash .claude/hooks/session-start-init.sh
  [[ "$output" == *"CYCLE IN PROGRESS"* ]]
  [[ "$output" == *"refactor auth"* ]]
}

@test "session-start-init is silent when no pending feedback" {
  run bash .claude/hooks/session-start-init.sh
  [[ "$output" != *"CYCLE IN PROGRESS"* ]]
}

# --- post-edit-logger.sh ---

@test "post-edit-logger logs edit to mutable surface" {
  echo "{\"tool_input\":{\"file_path\":\"$SANDBOX/CLAUDE.md\",\"old_string\":\"foo\",\"new_string\":\"bar\"}}" \
    | bash .claude/hooks/post-edit-logger.sh 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 1 ]
}

@test "post-edit-logger ignores non-mutable files" {
  echo '{"tool_input":{"file_path":"src/main.ts","old_string":"foo","new_string":"bar"}}' \
    | bash .claude/hooks/post-edit-logger.sh 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 0 ]
}

@test "post-edit-logger logs world rule edits" {
  echo "{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/rules/world/environment.md\",\"old_string\":\"old\",\"new_string\":\"new\"}}" \
    | bash .claude/hooks/post-edit-logger.sh 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 1 ]
}

@test "post-edit-logger captures edit diff context" {
  echo "{\"tool_input\":{\"file_path\":\"$SANDBOX/CLAUDE.md\",\"old_string\":\"hello\",\"new_string\":\"world\"}}" \
    | bash .claude/hooks/post-edit-logger.sh 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq -r '.data.old_string')" = "hello" ]
  [ "$(echo "$line" | jq -r '.data.new_string')" = "world" ]
}

@test "post-edit-logger handles Write tool input" {
  echo "{\"tool_input\":{\"file_path\":\"$SANDBOX/CLAUDE.md\",\"content\":\"new file content here\"}}" \
    | bash .claude/hooks/post-edit-logger.sh 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 1 ]
  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq -r '.data.tool')" = "Write" ]
  [[ "$(echo "$line" | jq -r '.data.preview')" == *"new file content"* ]]
}

@test "post-edit-logger fallback when no old_string/new_string/content" {
  echo "{\"tool_input\":{\"file_path\":\"$SANDBOX/CLAUDE.md\"}}" \
    | bash .claude/hooks/post-edit-logger.sh 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 1 ]
  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq -r '.data.file')" = "$SANDBOX/CLAUDE.md" ]
}

@test "post-edit-logger reads promptVersion from state.json" {
  echo '{"lastTask":"test","lastFeedback":null,"lastModification":null,"lastModificationRationale":null,"awaitingFeedback":false,"cycleCount":7}' \
    > .claude/path-kernel/state.json

  echo "{\"tool_input\":{\"file_path\":\"$SANDBOX/CLAUDE.md\",\"old_string\":\"a\",\"new_string\":\"b\"}}" \
    | bash .claude/hooks/post-edit-logger.sh 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq '.promptVersion')" -eq 7 ]
}

@test "session-start-init reads promptVersion from state.json" {
  echo '{"lastTask":"test","lastFeedback":null,"lastModification":null,"lastModificationRationale":null,"awaitingFeedback":false,"cycleCount":5}' \
    > .claude/path-kernel/state.json

  bash .claude/hooks/session-start-init.sh 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq '.promptVersion')" -eq 5 ]
}

# --- append-event.sh edge cases ---

@test "append-event with no arguments exits 1" {
  run bash .claude/hooks/append-event.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "append-event with invalid JSON data wraps as raw" {
  bash .claude/hooks/append-event.sh "test:event" 'not valid json' 0 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq -r '.data.raw')" = "not valid json" ]
}
