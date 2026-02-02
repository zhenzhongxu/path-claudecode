#!/usr/bin/env bats
# Tests for kernel invariant enforcement layers.
#
# Validates that settings.json deny rules, config.json lists,
# and pre-edit-guard patterns are complete and consistent.

load test_helper

setup() {
  setup_sandbox
  run_install
}
teardown() { teardown_sandbox; }

# --- 1. Settings deny rules completeness ---

@test "every agentCannotModify pattern has Edit and Write deny rules in settings.json" {
  local patterns
  patterns=$(jq -r '.agentCannotModify[]' .claude/path-kernel/config.json)

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    jq -e --arg p "Edit($pattern)" '.permissions.deny | index($p) != null' .claude/settings.json >/dev/null \
      || { echo "missing Edit deny rule for: $pattern"; return 1; }
    jq -e --arg p "Write($pattern)" '.permissions.deny | index($p) != null' .claude/settings.json >/dev/null \
      || { echo "missing Write deny rule for: $pattern"; return 1; }
  done <<< "$patterns"
}

# --- 2. Config consistency ---

@test "agentCanModify and agentCannotModify have no overlap" {
  local overlap
  overlap=$(jq -r '[.agentCanModify[], .agentCannotModify[]] | group_by(.) | map(select(length > 1)) | flatten | .[]' .claude/path-kernel/config.json)
  [ -z "$overlap" ] || { echo "overlapping entries: $overlap"; return 1; }
}

@test "kernel rule files are in agentCannotModify" {
  jq -e '.agentCannotModify | index(".claude/rules/kernel/*") != null' .claude/path-kernel/config.json >/dev/null \
    || { echo "kernel rules pattern missing from agentCannotModify"; return 1; }
}

@test "settings.json is in agentCannotModify" {
  jq -e '.agentCannotModify | index(".claude/settings.json") != null' .claude/path-kernel/config.json >/dev/null \
    || { echo ".claude/settings.json missing from agentCannotModify"; return 1; }
}

@test "event-log.jsonl is in agentCannotModify" {
  jq -e '.agentCannotModify | index(".claude/path-kernel/event-log.jsonl") != null' .claude/path-kernel/config.json >/dev/null \
    || { echo "event-log.jsonl missing from agentCannotModify"; return 1; }
}

@test "config.json is in agentCannotModify" {
  jq -e '.agentCannotModify | index(".claude/path-kernel/config.json") != null' .claude/path-kernel/config.json >/dev/null \
    || { echo "config.json missing from agentCannotModify"; return 1; }
}

# --- 3. Pre-edit guard covers all protected paths ---

@test "pre-edit-guard blocks each agentCannotModify pattern" {
  # Map each pattern to a concrete test path
  declare -A concrete_paths
  concrete_paths[".claude/rules/kernel/*"]="$SANDBOX/.claude/rules/kernel/invariants.md"
  concrete_paths[".claude/settings.json"]="$SANDBOX/.claude/settings.json"
  concrete_paths[".claude/path-kernel/event-log.jsonl"]="$SANDBOX/.claude/path-kernel/event-log.jsonl"
  concrete_paths[".claude/path-kernel/config.json"]="$SANDBOX/.claude/path-kernel/config.json"

  local patterns
  patterns=$(jq -r '.agentCannotModify[]' .claude/path-kernel/config.json)

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    local path="${concrete_paths[$pattern]}"
    [ -n "$path" ] || { echo "no concrete path for pattern: $pattern"; return 1; }

    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$path\"}}' | bash .claude/hooks/pre-edit-guard.sh"
    [ "$status" -eq 2 ] || { echo "pre-edit-guard did not block: $path (pattern: $pattern), status=$status"; return 1; }
  done <<< "$patterns"
}

@test "pre-edit-guard allows each agentCanModify pattern" {
  declare -A concrete_paths
  concrete_paths[".claude/path-kernel/state.json"]="$SANDBOX/.claude/path-kernel/state.json"
  concrete_paths[".claude/rules/skill/*"]="$SANDBOX/.claude/rules/skill/tool-patterns.md"
  concrete_paths[".claude/rules/valence/*"]="$SANDBOX/.claude/rules/valence/priorities.md"
  concrete_paths[".claude/rules/world/*"]="$SANDBOX/.claude/rules/world/environment.md"
  concrete_paths["CLAUDE.md"]="$SANDBOX/CLAUDE.md"

  local patterns
  patterns=$(jq -r '.agentCanModify[]' .claude/path-kernel/config.json)

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    local path="${concrete_paths[$pattern]}"
    [ -n "$path" ] || { echo "no concrete path for pattern: $pattern"; return 1; }

    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$path\"}}' | bash .claude/hooks/pre-edit-guard.sh"
    [ "$status" -eq 0 ] || { echo "pre-edit-guard blocked allowed path: $path (pattern: $pattern), status=$status"; return 1; }
  done <<< "$patterns"
}

# --- 4. Hook wiring in settings.json ---

@test "PreToolUse hook is configured in settings.json" {
  jq -e '.hooks.PreToolUse | length > 0' .claude/settings.json >/dev/null \
    || { echo "PreToolUse hook missing"; return 1; }
}

@test "PostToolUse hook is configured in settings.json" {
  jq -e '.hooks.PostToolUse | length > 0' .claude/settings.json >/dev/null \
    || { echo "PostToolUse hook missing"; return 1; }
}

@test "SessionStart hook is configured in settings.json" {
  jq -e '.hooks.SessionStart | length > 0' .claude/settings.json >/dev/null \
    || { echo "SessionStart hook missing"; return 1; }
}

@test "hook commands reference scripts that exist" {
  local scripts
  scripts=$(jq -r '
    [.hooks[][].hooks[].command] | .[]
  ' .claude/settings.json | sed 's/^bash //')

  while IFS= read -r script; do
    [ -z "$script" ] && continue
    [ -f "$script" ] || { echo "hook script not found: $script"; return 1; }
  done <<< "$scripts"
}

# --- 5. Append-only event log contract ---

@test "multiple append-event calls produce strictly increasing line counts" {
  bash .claude/hooks/append-event.sh "test:one" '{"n":1}' 0 2>/dev/null
  local count1
  count1=$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')

  bash .claude/hooks/append-event.sh "test:two" '{"n":2}' 0 2>/dev/null
  local count2
  count2=$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')

  bash .claude/hooks/append-event.sh "test:three" '{"n":3}' 0 2>/dev/null
  local count3
  count3=$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')

  [ "$count1" -eq 1 ]
  [ "$count2" -eq 2 ]
  [ "$count3" -eq 3 ]
}

# --- 6. Kernel files immutable after install ---

@test "invariants.md exists after install" {
  assert_file_exists .claude/rules/kernel/invariants.md
}

@test "cycle-protocol.md exists after install" {
  assert_file_exists .claude/rules/kernel/cycle-protocol.md
}

@test "pre-edit-guard blocks edits to invariants.md" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/rules/kernel/invariants.md\"}}' | bash .claude/hooks/pre-edit-guard.sh"
  [ "$status" -eq 2 ]
}

@test "pre-edit-guard blocks edits to cycle-protocol.md" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/rules/kernel/cycle-protocol.md\"}}' | bash .claude/hooks/pre-edit-guard.sh"
  [ "$status" -eq 2 ]
}
