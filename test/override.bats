#!/usr/bin/env bats
# Tests for override/backup behavior.

load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "reinstall creates a backup directory" {
  run_install
  run_install
  local count
  count=$(find .claude -maxdepth 1 -name '.path-backup-*' -type d | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "backup contains original file content" {
  run_install
  echo "custom content" > .claude/rules/world/environment.md

  run_install
  local backup_dir
  backup_dir=$(find .claude -maxdepth 1 -name '.path-backup-*' -type d | head -1)
  [ -f "$backup_dir/.claude__rules__world__environment.md" ]
  [[ "$(cat "$backup_dir/.claude__rules__world__environment.md")" == *"custom content"* ]]
}

@test "override replaces with Path version" {
  run_install
  echo "custom content" > .claude/rules/world/environment.md

  run_install
  [[ "$(cat .claude/rules/world/environment.md)" != *"custom content"* ]]
}

@test "reinstall preserves state.json" {
  run_install
  echo '{"lastTask":"test","lastFeedback":null,"lastModification":null,"lastModificationRationale":null,"awaitingFeedback":true,"cycleCount":5}' \
    > .claude/path-kernel/state.json

  run_install
  [ "$(jq '.cycleCount' .claude/path-kernel/state.json)" -eq 5 ]
}

@test "reinstall preserves event-log.jsonl" {
  run_install
  echo '{"id":"test","type":"test"}' > .claude/path-kernel/event-log.jsonl

  run_install
  [[ "$(cat .claude/path-kernel/event-log.jsonl)" == *'"id":"test"'* ]]
}

@test "reinstall output lists files that will be overridden" {
  run_install
  run_install
  [[ "$output" == *"Files that will be overridden"* ]]
  # Check at least one file from each category appears
  [[ "$output" == *".claude/hooks/"* ]]
  [[ "$output" == *".claude/rules/"* ]]
  [[ "$output" == *".claude/skills/"* ]]
  [[ "$output" == *".claude/path-kernel/config.json"* ]]
  [[ "$output" == *"CLAUDE.md"* ]]
  [[ "$output" == *".claude/settings.json"* ]]
}

@test "reinstall output mentions export-state suggestion" {
  run_install
  run_install
  [[ "$output" == *"/export-state"* ]]
}

@test "reinstall output mentions preserved files" {
  run_install
  run_install
  [[ "$output" == *"Preserved"* ]]
  [[ "$output" == *"state.json"* ]]
  [[ "$output" == *"event-log.jsonl"* ]]
}

@test "prompt_conflict shows (recommended) on Skip when files are identical" {
  run_install

  # Create a temp file identical to the installed file
  local incoming
  incoming="$(mktemp)"
  cp .claude/rules/world/environment.md "$incoming"

  # prompt_conflict prints the menu to stderr before blocking on read </dev/tty.
  # Use timeout to capture the menu output, then check for the label.
  local stderr_output
  stderr_output=$(
    PATH_INSTALL_SOURCED=1 source "$INSTALL_SH"
    AUTO_YES=false
    timeout 2 bash -c "
      PATH_INSTALL_SOURCED=1 source \"$INSTALL_SH\"
      AUTO_YES=false
      prompt_conflict \".claude/rules/world/environment.md\" \"$incoming\"
    " 2>&1 1>/dev/null || true
  )

  rm -f "$incoming"
  [[ "$stderr_output" == *"Skip (recommended)"* ]]
}

@test "prompt_conflict does not show (recommended) when files differ" {
  run_install

  # Create a temp file different from the installed file
  local incoming
  incoming="$(mktemp)"
  echo "different content" > "$incoming"

  local stderr_output
  stderr_output=$(
    timeout 2 bash -c "
      PATH_INSTALL_SOURCED=1 source \"$INSTALL_SH\"
      AUTO_YES=false
      prompt_conflict \".claude/rules/world/environment.md\" \"$incoming\"
    " 2>&1 1>/dev/null || true
  )

  rm -f "$incoming"
  # Should show plain "Skip" without "(recommended)"
  [[ "$stderr_output" == *"Skip"* ]]
  [[ "$stderr_output" != *"(recommended)"* ]]
}

@test "prompt_conflict shows plain Skip when no incoming file provided" {
  run_install

  local stderr_output
  stderr_output=$(
    timeout 2 bash -c "
      PATH_INSTALL_SOURCED=1 source \"$INSTALL_SH\"
      AUTO_YES=false
      prompt_conflict \".claude/rules/world/environment.md\"
    " 2>&1 1>/dev/null || true
  )

  [[ "$stderr_output" == *"Skip"* ]]
  [[ "$stderr_output" != *"(recommended)"* ]]
}

@test "rollback cleans up on fetch failure" {
  # First install succeeds
  run_install
  [ "$status" -eq 0 ]

  # Second install with a bogus URL should fail and roll back
  run bash "$INSTALL_SH" --yes --repo-url "file:///nonexistent/path"
  [ "$status" -ne 0 ]

  # Original files should still be intact (rollback restored them)
  [ -f ".claude/path-kernel/config.json" ]
  jq empty .claude/settings.json
}
