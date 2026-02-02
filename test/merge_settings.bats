#!/usr/bin/env bats
# Tests for settings.json merge logic.

load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

# Helpers

_write_existing_settings() {
  mkdir -p .claude
  cat > .claude/settings.json << 'EOF'
{
  "permissions": {
    "allow": ["Bash(npm test:*)"],
    "deny": ["Edit(.env)", "Write(.env)"]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "echo 'existing hook'"}]
      }
    ]
  }
}
EOF
}

_write_path_settings() {
  cat > "$BATS_TEST_TMPDIR/path_settings.json" << 'EOF'
{
  "permissions": {
    "deny": [
      "Edit(.claude/rules/kernel/*)",
      "Write(.claude/rules/kernel/*)",
      "Edit(.claude/settings.json)",
      "Write(.claude/settings.json)",
      "Edit(.claude/path-kernel/event-log.jsonl)",
      "Write(.claude/path-kernel/event-log.jsonl)",
      "Edit(.claude/path-kernel/config.json)",
      "Write(.claude/path-kernel/config.json)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "bash .claude/hooks/pre-edit-guard.sh"}]}
    ],
    "PostToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "bash .claude/hooks/post-edit-logger.sh", "async": true}]}
    ],
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "bash .claude/hooks/session-start-init.sh", "once": true}]}
    ],
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "bash .claude/hooks/user-prompt-logger.sh", "async": true}]}
    ],
    "SessionEnd": [
      {"hooks": [{"type": "command", "command": "bash .claude/hooks/session-end-logger.sh"}]}
    ]
  }
}
EOF
}

_do_merge() {
  _write_existing_settings
  _write_path_settings
  (
    source_install
    merge_settings_json .claude/settings.json "$BATS_TEST_TMPDIR/path_settings.json" .claude/settings.json.merged
  )
  mv .claude/settings.json.merged .claude/settings.json
}

# Tests

@test "merge preserves permissions.allow" {
  _do_merge
  [ "$(jq -r '.permissions.allow[0]' .claude/settings.json)" = "Bash(npm test:*)" ]
}

@test "merge combines deny arrays (2 existing + 8 path = 10)" {
  _do_merge
  [ "$(jq '.permissions.deny | length' .claude/settings.json)" -eq 10 ]
  [ "$(jq '[.permissions.deny[] | select(. == "Edit(.env)")] | length' .claude/settings.json)" -eq 1 ]
  [ "$(jq '[.permissions.deny[] | select(. == "Edit(.claude/rules/kernel/*)")] | length' .claude/settings.json)" -eq 1 ]
}

@test "merge deduplicates deny entries" {
  _write_existing_settings
  # Add a Path deny rule to existing
  local tmp
  tmp=$(jq '.permissions.deny += ["Edit(.claude/rules/kernel/*)"]' .claude/settings.json)
  echo "$tmp" > .claude/settings.json

  _write_path_settings
  (
    source_install
    merge_settings_json .claude/settings.json "$BATS_TEST_TMPDIR/path_settings.json" .claude/settings.json.merged
  )
  mv .claude/settings.json.merged .claude/settings.json

  local total unique
  total=$(jq '.permissions.deny | length' .claude/settings.json)
  unique=$(jq '.permissions.deny | unique | length' .claude/settings.json)
  [ "$total" -eq "$unique" ]
}

@test "merge preserves existing hooks alongside Path hooks" {
  _do_merge
  [ "$(jq '.hooks.PreToolUse | length' .claude/settings.json)" -eq 2 ]
  [ "$(jq -r '.hooks.PreToolUse[0].matcher' .claude/settings.json)" = "Bash" ]
}

@test "merge adds all lifecycle hooks" {
  _do_merge
  [ "$(jq '.hooks.PostToolUse | length' .claude/settings.json)" -eq 1 ]
  [ "$(jq '.hooks.SessionStart | length' .claude/settings.json)" -eq 1 ]
  [ "$(jq '.hooks.UserPromptSubmit | length' .claude/settings.json)" -eq 1 ]
  [ "$(jq '.hooks.SessionEnd | length' .claude/settings.json)" -eq 1 ]
}

@test "merge produces valid JSON" {
  _do_merge
  assert_json_valid ".claude/settings.json"
}

@test "merge preserves every hook type from incoming settings" {
  _do_merge
  # Dynamically check all hook types in the Path fixture survive the merge
  local hook_types
  hook_types=$(jq -r '.hooks | keys[]' "$BATS_TEST_TMPDIR/path_settings.json")

  while IFS= read -r type; do
    [ -z "$type" ] && continue
    jq -e --arg t "$type" '.hooks[$t] | length > 0' .claude/settings.json >/dev/null \
      || { echo "Hook type $type missing after merge"; return 1; }
  done <<< "$hook_types"
}

@test "merge is idempotent for hooks (no duplicates on second merge)" {
  _do_merge
  # Merge again
  _write_path_settings
  (
    source_install
    merge_settings_json .claude/settings.json "$BATS_TEST_TMPDIR/path_settings.json" .claude/settings.json.merged
  )
  mv .claude/settings.json.merged .claude/settings.json

  [ "$(jq '.hooks.PreToolUse | length' .claude/settings.json)" -eq 2 ]
}
