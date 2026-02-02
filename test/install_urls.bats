#!/usr/bin/env bats
# Tests that URLs in README.md and install.sh are consistent and well-formed.

load test_helper

REPO_SLUG="zhenzhongxu/path-claudecode"
RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/HEAD"
GITHUB_BASE="https://github.com/${REPO_SLUG}"

@test "README curl command references correct install.sh URL" {
  run grep -o 'https://raw.githubusercontent.com/[^")*]*install.sh' "$PROJECT_DIR/README.md"
  [ "$status" -eq 0 ]
  [ "$output" = "${RAW_BASE}/install.sh" ]
}

@test "README git clone references correct repo URL" {
  run grep -o 'https://github.com/[^"]*\.git' "$PROJECT_DIR/README.md"
  [ "$status" -eq 0 ]
  [ "$output" = "${GITHUB_BASE}.git" ]
}

@test "install.sh DEFAULT_REPO_URL matches expected base" {
  run grep -o 'DEFAULT_REPO_URL="[^"]*"' "$PROJECT_DIR/install.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "DEFAULT_REPO_URL=\"${RAW_BASE}\"" ]
}

@test "install.sh help text curl URL matches README" {
  readme_url=$(grep -o 'https://raw.githubusercontent.com/[^")*]*install.sh' "$PROJECT_DIR/README.md")
  install_help_url=$(grep -o 'https://raw.githubusercontent.com/[^")*]*install.sh' "$PROJECT_DIR/install.sh" | head -1)
  [ "$readme_url" = "$install_help_url" ]
}
