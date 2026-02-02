# Shared helpers for bats tests.
# Load with: load test_helper

PROJECT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
INSTALL_SH="$PROJECT_DIR/install.sh"
LOCAL_REPO_URL="file://$PROJECT_DIR"

# --- Sandbox ---

setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  cd "$SANDBOX"
  git init -q
}

teardown_sandbox() {
  cd "$PROJECT_DIR"
  if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ]; then
    rm -rf "$SANDBOX"
  fi
}

# --- Install helper ---

# Runs install.sh in the current directory with --yes and local repo URL.
# Additional args are forwarded.
run_install() {
  run bash "$INSTALL_SH" --yes --repo-url "$LOCAL_REPO_URL" "$@"
}

# --- Merge helpers ---

# Source install.sh functions without executing main.
# Use in a subshell to avoid polluting global state.
source_install() {
  PATH_INSTALL_SOURCED=1 source "$INSTALL_SH"
}

# --- Custom assertions ---

assert_file_exists() {
  [ -f "$1" ] || { echo "expected file to exist: $1"; return 1; }
}

assert_dir_exists() {
  [ -d "$1" ] || { echo "expected directory to exist: $1"; return 1; }
}

assert_file_executable() {
  [ -x "$1" ] || { echo "expected file to be executable: $1"; return 1; }
}

assert_json_valid() {
  jq empty "$1" 2>/dev/null || { echo "expected valid JSON: $1"; return 1; }
}
