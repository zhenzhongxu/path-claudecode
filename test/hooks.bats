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

# --- sink dispatch ---

@test "append-event dispatches to jsonl sink from config" {
  local custom_log="$SANDBOX/.claude/path-kernel/custom-events.jsonl"
  jq '.sinks = [{"type":"jsonl","path":".claude/path-kernel/custom-events.jsonl","enabled":true}]' \
    .claude/path-kernel/config.json > /tmp/cfg.json && mv /tmp/cfg.json .claude/path-kernel/config.json

  bash .claude/hooks/append-event.sh "test:sink" '{"key":"val"}' 0 2>/dev/null

  [ -f "$custom_log" ]
  [ "$(wc -l < "$custom_log" | tr -d ' ')" -eq 1 ]
  [ "$(head -1 "$custom_log" | jq -r '.type')" = "test:sink" ]
  # Default path should NOT have the event (sink replaced it)
  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 0 ]
}

@test "append-event dispatches to command sink" {
  local cmd_output="$SANDBOX/command-sink-output.jsonl"
  # Configure both default jsonl + a command sink
  jq --arg out "$cmd_output" \
    '.sinks = [
      {"type":"jsonl","path":".claude/path-kernel/event-log.jsonl","enabled":true},
      {"type":"command","command":("cat >> " + $out),"enabled":true}
    ]' .claude/path-kernel/config.json > /tmp/cfg.json && mv /tmp/cfg.json .claude/path-kernel/config.json

  bash .claude/hooks/append-event.sh "test:cmd" '{"via":"command"}' 0 2>/dev/null
  sleep 0.5  # wait for async background process

  [ -f "$cmd_output" ]
  [ "$(head -1 "$cmd_output" | jq -r '.type')" = "test:cmd" ]
}

@test "append-event dispatches to multiple sinks" {
  local sink_a="$SANDBOX/.claude/path-kernel/sink-a.jsonl"
  local sink_b="$SANDBOX/.claude/path-kernel/sink-b.jsonl"
  jq '.sinks = [
    {"type":"jsonl","path":".claude/path-kernel/sink-a.jsonl","enabled":true},
    {"type":"jsonl","path":".claude/path-kernel/sink-b.jsonl","enabled":true}
  ]' .claude/path-kernel/config.json > /tmp/cfg.json && mv /tmp/cfg.json .claude/path-kernel/config.json

  bash .claude/hooks/append-event.sh "test:multi" '{"n":2}' 0 2>/dev/null

  [ "$(wc -l < "$sink_a" | tr -d ' ')" -eq 1 ]
  [ "$(wc -l < "$sink_b" | tr -d ' ')" -eq 1 ]
  [ "$(head -1 "$sink_a" | jq -r '.type')" = "test:multi" ]
  [ "$(head -1 "$sink_b" | jq -r '.type')" = "test:multi" ]
}

@test "append-event skips disabled sinks" {
  local disabled_log="$SANDBOX/.claude/path-kernel/disabled.jsonl"
  jq '.sinks = [
    {"type":"jsonl","path":".claude/path-kernel/event-log.jsonl","enabled":true},
    {"type":"jsonl","path":".claude/path-kernel/disabled.jsonl","enabled":false}
  ]' .claude/path-kernel/config.json > /tmp/cfg.json && mv /tmp/cfg.json .claude/path-kernel/config.json

  bash .claude/hooks/append-event.sh "test:skip" '{}' 0 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 1 ]
  # Disabled sink should not exist or be empty
  if [ -f "$disabled_log" ]; then
    [ "$(wc -l < "$disabled_log" | tr -d ' ')" -eq 0 ]
  fi
}

@test "append-event falls back when no sinks key" {
  # Remove sinks key from config.json
  jq 'del(.sinks)' .claude/path-kernel/config.json > /tmp/cfg.json && mv /tmp/cfg.json .claude/path-kernel/config.json

  bash .claude/hooks/append-event.sh "test:fallback" '{"compat":true}' 0 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 1 ]
  [ "$(head -1 .claude/path-kernel/event-log.jsonl | jq -r '.type')" = "test:fallback" ]
}

@test "append-event webhook builds correct curl args" {
  local curl_log="$SANDBOX/curl-args.log"
  # Create a mock curl that logs its arguments
  mkdir -p "$SANDBOX/bin"
  cat > "$SANDBOX/bin/curl" << 'MOCKCURL'
#!/bin/bash
echo "$@" >> "$CURL_LOG"
MOCKCURL
  chmod +x "$SANDBOX/bin/curl"

  jq '.sinks = [{"type":"webhook","url":"https://test.example.com/events","headers":{"X-Token":"abc123"},"enabled":true}]' \
    .claude/path-kernel/config.json > /tmp/cfg.json && mv /tmp/cfg.json .claude/path-kernel/config.json

  CURL_LOG="$curl_log" PATH="$SANDBOX/bin:$PATH" \
    bash .claude/hooks/append-event.sh "test:webhook" '{"wh":true}' 0 2>/dev/null
  sleep 0.5  # wait for async background process

  [ -f "$curl_log" ]
  # Verify Content-Type header present
  grep -q "Content-Type: application/json" "$curl_log"
  # Verify custom header present
  grep -q "X-Token: abc123" "$curl_log"
  # Verify URL present
  grep -q "https://test.example.com/events" "$curl_log"
}

# --- user-prompt-logger.sh ---

@test "user-prompt-logger logs perception:situation event" {
  echo '{"prompt":"hello"}' | bash .claude/hooks/user-prompt-logger.sh 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 1 ]
  [ "$(head -1 .claude/path-kernel/event-log.jsonl | jq -r '.type')" = "perception:situation" ]
}

@test "user-prompt-logger captures prompt text" {
  echo '{"prompt":"hello world"}' | bash .claude/hooks/user-prompt-logger.sh 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq -r '.data.prompt')" = "hello world" ]
  [ "$(echo "$line" | jq -r '.data.source')" = "user" ]
}

@test "user-prompt-logger truncates long prompts" {
  local long_prompt
  long_prompt=$(python3 -c "print('x' * 3000)")
  echo "{\"prompt\":\"$long_prompt\"}" | bash .claude/hooks/user-prompt-logger.sh 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  local prompt_len
  prompt_len=$(echo "$line" | jq -r '.data.prompt' | wc -c)
  [ "$prompt_len" -le 2001 ]  # wc -c includes trailing newline
}

@test "user-prompt-logger silent on empty prompt" {
  echo '{"prompt":""}' | bash .claude/hooks/user-prompt-logger.sh 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 0 ]
}

@test "user-prompt-logger reads promptVersion from state.json" {
  echo '{"lastTask":"test","lastFeedback":null,"lastModification":null,"lastModificationRationale":null,"awaitingFeedback":false,"cycleCount":4}' \
    > .claude/path-kernel/state.json

  echo '{"prompt":"hello"}' | bash .claude/hooks/user-prompt-logger.sh 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq '.promptVersion')" -eq 4 ]
}

# --- session-end-logger.sh ---

@test "session-end-logger logs system:session-end event" {
  echo '{"reason":"user_exit"}' | bash .claude/hooks/session-end-logger.sh 2>/dev/null

  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 1 ]
  [ "$(head -1 .claude/path-kernel/event-log.jsonl | jq -r '.type')" = "system:session-end" ]
}

@test "session-end-logger captures reason" {
  echo '{"reason":"user_exit"}' | bash .claude/hooks/session-end-logger.sh 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq -r '.data.reason')" = "user_exit" ]
  [ "$(echo "$line" | jq -r '.data.source')" = "claude-code" ]
  [ "$(echo "$line" | jq -r '.data.event')" = "session-end" ]
}

@test "session-end-logger defaults reason to unknown" {
  echo '{}' | bash .claude/hooks/session-end-logger.sh 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq -r '.data.reason')" = "unknown" ]
}

@test "session-end-logger reads promptVersion from state.json" {
  echo '{"lastTask":"test","lastFeedback":null,"lastModification":null,"lastModificationRationale":null,"awaitingFeedback":false,"cycleCount":9}' \
    > .claude/path-kernel/state.json

  echo '{"reason":"user_exit"}' | bash .claude/hooks/session-end-logger.sh 2>/dev/null

  local line
  line=$(head -1 .claude/path-kernel/event-log.jsonl)
  [ "$(echo "$line" | jq '.promptVersion')" -eq 9 ]
}
