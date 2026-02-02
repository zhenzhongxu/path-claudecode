#!/usr/bin/env bats
# Tests for CLI flag parsing.

load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "--help exits 0 and prints usage" {
  run bash "$INSTALL_SH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--yes"* ]]
}

@test "--version exits 0 and prints version" {
  run bash "$INSTALL_SH" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"Path installer v"* ]]
}

@test "unknown option exits 1" {
  run bash "$INSTALL_SH" --bogus
  [ "$status" -eq 1 ]
}

@test "--repo-url without value exits 1" {
  run bash "$INSTALL_SH" --repo-url
  [ "$status" -eq 1 ]
}

@test "-y short flag is accepted" {
  run bash "$INSTALL_SH" -y --repo-url "$LOCAL_REPO_URL"
  [ "$status" -eq 0 ]
}
