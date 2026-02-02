#!/usr/bin/env bats
# Tests for CLAUDE.md merge logic.

load test_helper

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

_do_merge_claude_md() {
  cat > CLAUDE.md << 'EOF'
# My Existing Project

These are my existing instructions.

## Rules
- Follow TDD
- Use TypeScript
EOF

  cat > "$BATS_TEST_TMPDIR/path_claude.md" << 'EOF'
# Path — Self-Evolution Kernel

This is the Path kernel content.
EOF

  (
    source_install
    merge_claude_md CLAUDE.md "$BATS_TEST_TMPDIR/path_claude.md" CLAUDE.md.merged
  )
  mv CLAUDE.md.merged CLAUDE.md
}

@test "merge prepends Path content" {
  _do_merge_claude_md
  [[ "$(head -1 CLAUDE.md)" == *"Path"* ]]
}

@test "merge inserts delimiter" {
  _do_merge_claude_md
  [ "$(grep -cF '<!-- End Path Kernel -->' CLAUDE.md)" -eq 1 ]
}

@test "merge preserves existing content" {
  _do_merge_claude_md
  [[ "$(cat CLAUDE.md)" == *"My Existing Project"* ]]
  [[ "$(cat CLAUDE.md)" == *"Follow TDD"* ]]
  [[ "$(cat CLAUDE.md)" == *"Use TypeScript"* ]]
}

@test "existing content appears after delimiter" {
  _do_merge_claude_md
  local after
  after=$(sed -n '/<!-- End Path Kernel -->/,$p' CLAUDE.md | tail -n +2)
  [[ "$after" == *"My Existing Project"* ]]
}

@test "fresh install has no merge delimiter" {
  run_install
  [ "$(grep -cF '<!-- End Path Kernel -->' CLAUDE.md || true)" -eq 0 ]
}
