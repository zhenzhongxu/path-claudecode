#!/usr/bin/env bats
# Tests for fresh install into an empty project.

load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

EXPECTED_FILES=(
  "CLAUDE.md"
  ".claude/settings.json"
  ".claude/hooks/append-event.sh"
  ".claude/hooks/pre-edit-guard.sh"
  ".claude/hooks/post-edit-logger.sh"
  ".claude/hooks/session-start-init.sh"
  ".claude/hooks/user-prompt-logger.sh"
  ".claude/hooks/session-end-logger.sh"
  ".claude/rules/kernel/invariants.md"
  ".claude/rules/kernel/cycle-protocol.md"
  ".claude/rules/world/environment.md"
  ".claude/rules/world/self-model.md"
  ".claude/rules/valence/priorities.md"
  ".claude/rules/valence/tradeoffs.md"
  ".claude/rules/skill/tool-patterns.md"
  ".claude/rules/skill/domain-expertise.md"
  ".claude/skills/evolve/SKILL.md"
  ".claude/skills/reflect/SKILL.md"
  ".claude/skills/export-state/SKILL.md"
  ".claude/path-kernel/config.json"
  ".claude/path-kernel/state.json"
  ".claude/path-kernel/event-log.jsonl"
)

@test "fresh install creates all expected files" {
  run_install
  [ "$status" -eq 0 ]
  for f in "${EXPECTED_FILES[@]}"; do
    assert_file_exists "$f"
  done
}

@test "fresh install creates all expected directories" {
  run_install
  local expected_dirs=(
    ".claude/hooks"
    ".claude/rules/kernel"
    ".claude/rules/world"
    ".claude/rules/valence"
    ".claude/rules/skill"
    ".claude/skills/evolve"
    ".claude/skills/reflect"
    ".claude/skills/export-state"
    ".claude/path-kernel"
    ".claude/path-kernel/exports"
  )
  for d in "${expected_dirs[@]}"; do
    assert_dir_exists "$d"
  done
}

@test "hooks are executable" {
  run_install
  assert_file_executable ".claude/hooks/append-event.sh"
  assert_file_executable ".claude/hooks/pre-edit-guard.sh"
  assert_file_executable ".claude/hooks/post-edit-logger.sh"
  assert_file_executable ".claude/hooks/session-start-init.sh"
  assert_file_executable ".claude/hooks/user-prompt-logger.sh"
  assert_file_executable ".claude/hooks/session-end-logger.sh"
}

@test "settings.json is valid with correct deny rules and hooks" {
  run_install
  assert_json_valid ".claude/settings.json"

  [ "$(jq '.permissions.deny | length' .claude/settings.json)" -eq 8 ]
  [ "$(jq '.hooks.PreToolUse | length' .claude/settings.json)" -eq 1 ]
  [ "$(jq '.hooks.PostToolUse | length' .claude/settings.json)" -eq 1 ]
  [ "$(jq '.hooks.SessionStart | length' .claude/settings.json)" -eq 1 ]
  [ "$(jq '.hooks.UserPromptSubmit | length' .claude/settings.json)" -eq 1 ]
  [ "$(jq '.hooks.SessionEnd | length' .claude/settings.json)" -eq 1 ]
}

@test "state.json has default values" {
  run_install
  assert_json_valid ".claude/path-kernel/state.json"

  [ "$(jq '.cycleCount' .claude/path-kernel/state.json)" -eq 0 ]
  [ "$(jq '.awaitingFeedback' .claude/path-kernel/state.json)" = "false" ]
}

@test "event-log.jsonl is empty" {
  run_install
  assert_file_exists ".claude/path-kernel/event-log.jsonl"
  [ "$(wc -l < .claude/path-kernel/event-log.jsonl | tr -d ' ')" -eq 0 ]
}

@test "config.json has agentCanModify and agentCannotModify" {
  run_install
  assert_json_valid ".claude/path-kernel/config.json"
  [ "$(jq '.agentCanModify | length' .claude/path-kernel/config.json)" -gt 0 ]
  [ "$(jq '.agentCannotModify | length' .claude/path-kernel/config.json)" -gt 0 ]
}

@test "install reports 22 files installed" {
  run_install
  [[ "$output" == *"Files installed: 22"* ]]
}

# --- Consistency guards ---

@test "EXPECTED_FILES count matches reported install count" {
  run_install
  # Extract the reported count from installer output
  local reported
  reported=$(echo "$output" | grep -o 'Files installed: [0-9]*' | grep -o '[0-9]*')
  [ "${#EXPECTED_FILES[@]}" -eq "$reported" ] \
    || { echo "EXPECTED_FILES has ${#EXPECTED_FILES[@]} entries but installer reported $reported"; return 1; }
}

@test "HOOK_FILES in install.sh covers all source hook scripts" {
  # Get basenames of actual .sh files in the source hooks directory
  local source_hooks
  source_hooks=$(ls "$PROJECT_DIR/.claude/hooks/"*.sh 2>/dev/null | xargs -n1 basename | sort)

  # Get basenames from install.sh's HOOK_FILES array
  local install_hooks
  install_hooks=$(
    source_install
    printf '%s\n' "${HOOK_FILES[@]}" | xargs -n1 basename | sort
  )

  [ "$source_hooks" = "$install_hooks" ] \
    || { echo "source hooks: $source_hooks"; echo "HOOK_FILES:   $install_hooks"; return 1; }
}

@test "every settings.json hook type has entries after fresh install" {
  run_install
  local hook_types
  hook_types=$(jq -r '.hooks | keys[]' .claude/settings.json)

  while IFS= read -r type; do
    [ -z "$type" ] && continue
    local count
    count=$(jq --arg t "$type" '.hooks[$t] | length' .claude/settings.json)
    [ "$count" -gt 0 ] || { echo "Hook type $type has 0 entries after install"; return 1; }
  done <<< "$hook_types"
}
