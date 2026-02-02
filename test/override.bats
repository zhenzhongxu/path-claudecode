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
