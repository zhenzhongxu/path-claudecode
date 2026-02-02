#!/bin/bash
# shellcheck disable=SC2059
# Path Self-Evolution Kernel Installer
# https://github.com/zhenzhongxu/path-claudecode
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zhenzhongxu/path-claudecode/HEAD/install.sh)"
#
# Options:
#   -y, --yes          Non-interactive mode (auto-override conflicts)
#   -h, --help         Show help
#   --repo-url URL     Override repository base URL

# Only set strict mode when running directly (not when sourced for tests)
if [ "${PATH_INSTALL_SOURCED:-}" != "1" ]; then
  set -euo pipefail
fi

# =============================================================================
# Constants
# =============================================================================

INSTALLER_VERSION="1.0.0"
DEFAULT_REPO_URL="https://raw.githubusercontent.com/zhenzhongxu/path-claudecode/HEAD"
REPO_URL="${DEFAULT_REPO_URL}"
AUTO_YES=false
BACKUP_DIR=""
INSTALLED_FILES=()
CREATED_DIRS=()
FILE_COUNT=0

# Files to fetch from the repo (relative paths)
HOOK_FILES=(
  ".claude/hooks/append-event.sh"
  ".claude/hooks/pre-edit-guard.sh"
  ".claude/hooks/post-edit-logger.sh"
  ".claude/hooks/session-start-init.sh"
)

RULE_FILES=(
  ".claude/rules/kernel/invariants.md"
  ".claude/rules/kernel/cycle-protocol.md"
  ".claude/rules/world/environment.md"
  ".claude/rules/world/self-model.md"
  ".claude/rules/valence/priorities.md"
  ".claude/rules/valence/tradeoffs.md"
  ".claude/rules/skill/tool-patterns.md"
  ".claude/rules/skill/domain-expertise.md"
)

SKILL_FILES=(
  ".claude/skills/evolve/SKILL.md"
  ".claude/skills/reflect/SKILL.md"
  ".claude/skills/export-state/SKILL.md"
)

CONFIG_FILES=(
  ".claude/path-kernel/config.json"
)

# Directories to create
DIRECTORIES=(
  ".claude/hooks"
  ".claude/rules/kernel"
  ".claude/rules/world"
  ".claude/rules/valence"
  ".claude/rules/skill"
  ".claude/skills/evolve"
  ".claude/skills/reflect"
  ".claude/skills/export-state"
  ".claude/path-kernel/exports"
)

# =============================================================================
# Color & Output Utilities
# =============================================================================

if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' RESET=''
fi

log_info()    { printf "${BLUE}info${RESET}  %s\n" "$1"; }
log_success() { printf "${GREEN}  ok${RESET}  %s\n" "$1"; }
log_warn()    { printf "${YELLOW}warn${RESET}  %s\n" "$1"; }
log_error()   { printf "${RED} err${RESET}  %s\n" "$1" >&2; }
log_step()    { printf "\n${BOLD}%s${RESET}\n" "$1"; }

die() {
  log_error "$1"
  exit 1
}

# =============================================================================
# Cleanup & Rollback
# =============================================================================

cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ] && [ ${#INSTALLED_FILES[@]} -gt 0 ]; then
    echo ""
    log_error "Installation failed. Rolling back changes..."

    # Restore backups
    if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
      for backup_file in "$BACKUP_DIR"/*; do
        [ -f "$backup_file" ] || continue
        local base
        base="$(basename "$backup_file")"
        local original="${base//__//}"
        if cp "$backup_file" "$original" 2>/dev/null; then
          log_info "Restored $original"
        fi
      done
      rm -rf "$BACKUP_DIR"
    fi

    # Remove newly created files
    for file in "${INSTALLED_FILES[@]}"; do
      if [ -f "$file" ]; then
        rm -f "$file"
      fi
    done

    # Remove empty directories we created (reverse order)
    for ((i=${#CREATED_DIRS[@]}-1; i>=0; i--)); do
      local dir="${CREATED_DIRS[$i]}"
      if [ -d "$dir" ] && [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        rmdir "$dir" 2>/dev/null || true
      fi
    done

    log_error "Rollback complete. No changes were made."
  fi
}

# Only set trap when running directly (not when sourced for tests)
if [ "${PATH_INSTALL_SOURCED:-}" != "1" ]; then
  trap cleanup EXIT
fi

# =============================================================================
# Utility Functions
# =============================================================================

backup_file() {
  local file="$1"
  if [ -z "$BACKUP_DIR" ]; then
    BACKUP_DIR=".claude/.path-backup-$(date +%s)"
    mkdir -p "$BACKUP_DIR"
  fi
  # Encode path: replace / with __ for flat backup directory
  local encoded="${file//\//__}"
  cp "$file" "$BACKUP_DIR/$encoded"
}

fetch_file() {
  local url="$1"
  local dest="$2"
  local http_code
  local tmpfile

  tmpfile="$(mktemp)"

  http_code=$(curl -fsSL -w "%{http_code}" -o "$tmpfile" "$url" 2>/dev/null) || {
    rm -f "$tmpfile"
    return 1
  }

  if [ "$http_code" -ge 400 ] 2>/dev/null; then
    rm -f "$tmpfile"
    return 1
  fi

  mv "$tmpfile" "$dest"
  return 0
}

# Prompt user with choices. Returns the choice string.
# Usage: choice=$(prompt_conflict "filepath")
prompt_conflict() {
  local file="$1"

  if [ "$AUTO_YES" = true ]; then
    echo "override"
    return
  fi

  # All display output goes to stderr so it's not captured by $()
  # read uses /dev/tty so interactive input works in curl-pipe-to-bash
  echo "" >&2
  printf "  ${YELLOW}Conflict:${RESET} ${BOLD}%s${RESET} already exists.\n" "$file" >&2
  echo "" >&2
  echo "  Choose an action:" >&2
  echo "    1) Override  — back up existing file and replace with Path version" >&2

  # Only offer merge for files where it makes sense
  case "$file" in
    .claude/settings.json|CLAUDE.md)
      echo "    2) Merge     — intelligently combine both versions" >&2
      echo "    3) Cancel    — abort installation" >&2
      echo "" >&2
      while true; do
        printf "  Your choice [1-3]: " >&2
        read -r choice </dev/tty
        case "$choice" in
          1) echo "override"; return ;;
          2) echo "merge"; return ;;
          3) echo "cancel"; return ;;
          *) printf "  ${RED}Invalid choice. Please enter 1, 2, or 3.${RESET}\n" >&2 ;;
        esac
      done
      ;;
    *)
      echo "    2) Skip      — keep existing file unchanged" >&2
      echo "    3) Cancel    — abort installation" >&2
      echo "" >&2
      while true; do
        printf "  Your choice [1-3]: " >&2
        read -r choice </dev/tty
        case "$choice" in
          1) echo "override"; return ;;
          2) echo "skip"; return ;;
          3) echo "cancel"; return ;;
          *) printf "  ${RED}Invalid choice. Please enter 1, 2, or 3.${RESET}\n" >&2 ;;
        esac
      done
      ;;
  esac
}

# =============================================================================
# Reinstall File Listing
# =============================================================================

list_reinstall_files() {
  local found_any=false

  # --- Hooks ---
  local hook_found=()
  for file in "${HOOK_FILES[@]}"; do
    [ -f "$file" ] && hook_found+=("$file")
  done
  if [ ${#hook_found[@]} -gt 0 ]; then
    found_any=true
    printf "  ${BOLD}Hooks:${RESET}\n"
    for f in "${hook_found[@]}"; do
      printf "    ${DIM}•${RESET} %s\n" "$f"
    done
  fi

  # --- Rules ---
  local rule_found=()
  for file in "${RULE_FILES[@]}"; do
    [ -f "$file" ] && rule_found+=("$file")
  done
  if [ ${#rule_found[@]} -gt 0 ]; then
    found_any=true
    printf "  ${BOLD}Rules:${RESET}\n"
    for f in "${rule_found[@]}"; do
      printf "    ${DIM}•${RESET} %s\n" "$f"
    done
  fi

  # --- Skills ---
  local skill_found=()
  for file in "${SKILL_FILES[@]}"; do
    [ -f "$file" ] && skill_found+=("$file")
  done
  if [ ${#skill_found[@]} -gt 0 ]; then
    found_any=true
    printf "  ${BOLD}Skills:${RESET}\n"
    for f in "${skill_found[@]}"; do
      printf "    ${DIM}•${RESET} %s\n" "$f"
    done
  fi

  # --- Config ---
  local config_found=()
  for file in "${CONFIG_FILES[@]}"; do
    [ -f "$file" ] && config_found+=("$file")
  done
  if [ ${#config_found[@]} -gt 0 ]; then
    found_any=true
    printf "  ${BOLD}Config:${RESET}\n"
    for f in "${config_found[@]}"; do
      printf "    ${DIM}•${RESET} %s\n" "$f"
    done
  fi

  # --- Top-level files ---
  local toplevel_found=()
  [ -f ".claude/settings.json" ] && toplevel_found+=(".claude/settings.json")
  [ -f "CLAUDE.md" ] && toplevel_found+=("CLAUDE.md")
  if [ ${#toplevel_found[@]} -gt 0 ]; then
    found_any=true
    printf "  ${BOLD}Top-level:${RESET}\n"
    for f in "${toplevel_found[@]}"; do
      printf "    ${DIM}•${RESET} %s\n" "$f"
    done
  fi

  # --- Preserved files ---
  local preserved_found=()
  [ -f ".claude/path-kernel/state.json" ] && preserved_found+=(".claude/path-kernel/state.json")
  [ -f ".claude/path-kernel/event-log.jsonl" ] && preserved_found+=(".claude/path-kernel/event-log.jsonl")
  if [ ${#preserved_found[@]} -gt 0 ]; then
    echo ""
    printf "  ${GREEN}Preserved (will not be overwritten):${RESET}\n"
    for f in "${preserved_found[@]}"; do
      printf "    ${DIM}•${RESET} %s\n" "$f"
    done
  fi

  if [ "$found_any" = true ]; then
    return 0
  else
    return 1
  fi
}

# =============================================================================
# Merge Logic
# =============================================================================

merge_settings_json() {
  local existing="$1"
  local incoming="$2"
  local output="$3"

  # Use jq to merge:
  # - Union deny arrays (deduplicate)
  # - Concatenate hooks arrays (deduplicate by comparing .hooks array)
  # - Preserve all other existing keys
  jq -s '
    # Helper: deduplicate hooks by comparing .hooks[].command
    def dedup_hooks:
      reduce .[] as $item ([];
        if any(.[]; .hooks == $item.hooks) then . else . + [$item] end
      );

    (.[0] // {}) as $existing |
    (.[1] // {}) as $incoming |

    # Merge permissions.deny (unique)
    (($existing.permissions.deny // []) + ($incoming.permissions.deny // []) | unique) as $deny |

    # Merge each hook type
    (($existing.hooks.PreToolUse // []) + ($incoming.hooks.PreToolUse // []) | dedup_hooks) as $pre |
    (($existing.hooks.PostToolUse // []) + ($incoming.hooks.PostToolUse // []) | dedup_hooks) as $post |
    (($existing.hooks.SessionStart // []) + ($incoming.hooks.SessionStart // []) | dedup_hooks) as $session |

    # Start with existing, overlay merged fields
    $existing * {
      permissions: {
        deny: $deny
      },
      hooks: {
        PreToolUse: $pre,
        PostToolUse: $post,
        SessionStart: $session
      }
    }
  ' "$existing" "$incoming" > "$output"
}

merge_claude_md() {
  local existing="$1"
  local incoming="$2"
  local output="$3"

  {
    cat "$incoming"
    echo ""
    echo "<!-- End Path Kernel -->"
    echo ""
    cat "$existing"
  } > "$output"
}

# =============================================================================
# Install a single file with conflict resolution
# =============================================================================

install_single_file() {
  local relpath="$1"
  local source_type="${2:-fetch}"   # "fetch" or "generate"
  local content="${3:-}"            # content for "generate" type
  local make_exec="${4:-false}"     # chmod +x

  # Check for conflict
  if [ -f "$relpath" ]; then
    local action
    action=$(prompt_conflict "$relpath")

    case "$action" in
      override)
        backup_file "$relpath"
        log_info "Backed up $relpath"
        ;;
      merge)
        backup_file "$relpath"
        local tmpfile
        tmpfile="$(mktemp)"

        if [ "$source_type" = "fetch" ]; then
          fetch_file "${REPO_URL}/${relpath}" "$tmpfile" || die "Failed to fetch $relpath"
        else
          echo "$content" > "$tmpfile"
        fi

        local merged
        merged="$(mktemp)"

        case "$relpath" in
          .claude/settings.json)
            merge_settings_json "$relpath" "$tmpfile" "$merged"
            if ! jq empty "$merged" 2>/dev/null; then
              rm -f "$tmpfile" "$merged"
              die "Merge produced invalid JSON for $relpath"
            fi
            ;;
          CLAUDE.md)
            merge_claude_md "$relpath" "$tmpfile" "$merged"
            ;;
          *)
            die "Merge not supported for $relpath"
            ;;
        esac

        rm -f "$tmpfile"
        mv "$merged" "$relpath"
        INSTALLED_FILES+=("$relpath")
        FILE_COUNT=$((FILE_COUNT + 1))
        log_success "Merged $relpath"
        return 0
        ;;
      skip)
        log_info "Skipped $relpath"
        return 0
        ;;
      cancel)
        die "Installation cancelled by user."
        ;;
    esac
  fi

  # Write the file
  if [ "$source_type" = "fetch" ]; then
    fetch_file "${REPO_URL}/${relpath}" "$relpath" || die "Failed to fetch $relpath"
  else
    printf '%s\n' "$content" > "$relpath"
  fi

  INSTALLED_FILES+=("$relpath")
  FILE_COUNT=$((FILE_COUNT + 1))

  if [ "$make_exec" = true ]; then
    chmod +x "$relpath"
  fi

  log_success "$relpath"
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

preflight() {
  log_step "Pre-flight checks"

  local warnings=()

  # ── Required: bash ──────────────────────────────────────────────────────
  # All hooks use #!/bin/bash and rely on bash features (arrays, [[ ]], etc.)
  if ! command -v bash &>/dev/null; then
    die "bash is not installed. All Path hooks require bash."
  fi
  # Check bash version (need 3.2+ for arrays, parameter expansion, etc.)
  local bash_ver
  bash_ver="$(bash -c 'echo ${BASH_VERSINFO[0]}')"
  if [ "$bash_ver" -lt 3 ] 2>/dev/null; then
    die "bash 3.2+ is required (found version $bash_ver). Please upgrade bash."
  fi
  log_success "bash $bash_ver found"

  # ── Required: jq ────────────────────────────────────────────────────────
  # Used by all hook scripts (pre-edit-guard, post-edit-logger, session-start-init,
  # append-event) and by install.sh merge logic
  if ! command -v jq &>/dev/null; then
    log_error "jq is not installed."
    echo ""
    echo "  jq is required by Path's hooks for JSON manipulation."
    echo "  Every hook (pre-edit guard, post-edit logger, session init,"
    echo "  event logger) depends on it at runtime."
    echo ""
    echo "  To install:"
    echo "    macOS:    brew install jq"
    echo "    Ubuntu:   sudo apt-get install jq"
    echo "    Fedora:   sudo dnf install jq"
    echo "    Arch:     sudo pacman -S jq"
    echo ""
    die "Install jq and run this script again."
  fi
  log_success "jq found"

  # ── Required: curl ──────────────────────────────────────────────────────
  # Needed to fetch files from GitHub during installation
  if ! command -v curl &>/dev/null; then
    die "curl is not installed. It is required to fetch files from GitHub."
  fi
  log_success "curl found"

  # ── Runtime: UUID generation ────────────────────────────────────────────
  # append-event.sh tries: uuidgen → /proc/sys/kernel/random/uuid → od + /dev/urandom
  if command -v uuidgen &>/dev/null; then
    log_success "uuidgen found (used by event logger)"
  elif [ -f /proc/sys/kernel/random/uuid ]; then
    log_success "/proc/sys/kernel/random/uuid available (used by event logger)"
  elif [ -c /dev/urandom ] && command -v od &>/dev/null; then
    log_success "od + /dev/urandom available (used by event logger)"
  else
    warnings+=("No UUID source found (uuidgen, /proc/sys/kernel/random/uuid, or od + /dev/urandom). Event logging will fail.")
  fi

  # ── Runtime: date -u ────────────────────────────────────────────────────
  # append-event.sh uses: date -u +"%Y-%m-%dT%H:%M:%SZ"
  if ! date -u +"%Y-%m-%dT%H:%M:%SZ" &>/dev/null; then
    warnings+=("'date -u' not working. Event timestamps will fail.")
  fi

  # ── Runtime: head -c (GNU extension) ────────────────────────────────────
  # post-edit-logger.sh uses: head -c 200 for content preview
  if ! echo "test" | head -c 2 &>/dev/null; then
    warnings+=("'head -c' not supported. Post-edit logger preview will be empty (non-fatal).")
  fi

  # ── Runtime: standard POSIX utilities ───────────────────────────────────
  # Used across hooks: cat, dirname, mkdir, touch, tr, sed
  local missing_posix=()
  for cmd in cat dirname mkdir touch tr sed basename; do
    if ! command -v "$cmd" &>/dev/null; then
      missing_posix+=("$cmd")
    fi
  done
  if [ ${#missing_posix[@]} -gt 0 ]; then
    die "Missing required POSIX utilities: ${missing_posix[*]}"
  fi

  # ── Print accumulated warnings ──────────────────────────────────────────
  if [ ${#warnings[@]} -gt 0 ]; then
    for w in "${warnings[@]}"; do
      log_warn "$w"
    done
    if [ "$AUTO_YES" = false ]; then
      printf "\n  Continue despite warnings? [y/N]: "
      read -r yn </dev/tty
      case "$yn" in
        [Yy]*) ;;
        *) die "Aborted. Fix the warnings above and try again." ;;
      esac
    fi
  fi

  # ── Check project root ─────────────────────────────────────────────────
  local is_project=false
  for marker in .claude CLAUDE.md; do
    if [ -e "$marker" ]; then
      is_project=true
      break
    fi
  done

  if [ "$is_project" = false ]; then
    log_warn "No Claude Code project markers found in $(pwd)"
    echo "  Expected one of: .claude/, CLAUDE.md"
    if [ "$AUTO_YES" = false ]; then
      printf "\n  Continue anyway? [y/N]: "
      read -r yn </dev/tty
      case "$yn" in
        [Yy]*) ;;
        *) die "Aborted. cd to your project root and try again." ;;
      esac
    fi
  else
    log_success "Project root detected"
  fi

  # ── Check for existing Path installation ────────────────────────────────
  if [ -f ".claude/path-kernel/config.json" ]; then
    log_warn "Path kernel is already installed in this project."

    echo ""
    printf "  ${BOLD}Files that will be overridden:${RESET}\n"
    list_reinstall_files
    echo ""
    printf "  ${YELLOW}Tip:${RESET} Consider running ${BOLD}/export-state${RESET} in Claude Code first to save current kernel state.\n"

    if [ "$AUTO_YES" = true ]; then
      log_info "Auto-mode: will override existing installation"
      return 0
    fi

    echo ""
    echo "  Choose an action:"
    echo "    1) Reinstall — replace all Path files (state & event log preserved)"
    echo "    2) Cancel    — exit without changes"
    echo ""
    while true; do
      printf "  Your choice [1-2]: "
      read -r choice </dev/tty
      case "$choice" in
        1) log_info "Proceeding with reinstall"; return 0 ;;
        2) die "Installation cancelled." ;;
        *) printf "  ${RED}Invalid choice.${RESET}\n" ;;
      esac
    done
  fi

  # ── Check network connectivity ──────────────────────────────────────────
  if ! curl -fsSL --head --connect-timeout 5 "${REPO_URL}/CLAUDE.md" &>/dev/null; then
    die "Cannot reach ${REPO_URL}. Check your network connection."
  fi
  log_success "Repository reachable"
}

# =============================================================================
# Installation
# =============================================================================

install_path() {
  # --- Create directories ---
  log_step "Creating directories"

  for dir in "${DIRECTORIES[@]}"; do
    if [ ! -d "$dir" ]; then
      mkdir -p "$dir"
      CREATED_DIRS+=("$dir")
    fi
  done
  log_success "Directory structure ready"

  # --- Install hooks ---
  log_step "Installing hooks"

  for file in "${HOOK_FILES[@]}"; do
    install_single_file "$file" "fetch" "" true
  done

  # --- Install rules ---
  log_step "Installing rules"

  for file in "${RULE_FILES[@]}"; do
    install_single_file "$file" "fetch"
  done

  # --- Install skills ---
  log_step "Installing skills"

  for file in "${SKILL_FILES[@]}"; do
    install_single_file "$file" "fetch"
  done

  # --- Install config ---
  log_step "Installing configuration"

  for file in "${CONFIG_FILES[@]}"; do
    install_single_file "$file" "fetch"
  done

  # --- Install settings.json (may need merge) ---
  install_single_file ".claude/settings.json" "fetch"

  # --- Install CLAUDE.md (may need merge) ---
  log_step "Installing CLAUDE.md"

  install_single_file "CLAUDE.md" "fetch"

  # --- Initialize runtime state ---
  log_step "Initializing runtime state"

  # state.json — only create if it doesn't exist (preserve across reinstall)
  if [ ! -f ".claude/path-kernel/state.json" ]; then
    local state_content='{
  "lastTask": null,
  "lastFeedback": null,
  "lastModification": null,
  "lastModificationRationale": null,
  "awaitingFeedback": false,
  "cycleCount": 0
}'
    printf '%s\n' "$state_content" > ".claude/path-kernel/state.json"
    INSTALLED_FILES+=(".claude/path-kernel/state.json")
    FILE_COUNT=$((FILE_COUNT + 1))
    log_success "Initialized state.json"
  else
    log_info "state.json already exists, preserving"
  fi

  # event-log.jsonl — only create if it doesn't exist (append-only, never overwrite)
  if [ ! -f ".claude/path-kernel/event-log.jsonl" ]; then
    touch ".claude/path-kernel/event-log.jsonl"
    INSTALLED_FILES+=(".claude/path-kernel/event-log.jsonl")
    FILE_COUNT=$((FILE_COUNT + 1))
    log_success "Created event-log.jsonl"
  else
    log_info "event-log.jsonl already exists, preserving"
  fi
}

# =============================================================================
# Post-install Summary
# =============================================================================

print_summary() {
  echo ""
  printf "${BOLD}════════════════════════════════════════════════════════════════${RESET}\n"
  printf "${GREEN}${BOLD}  Path Self-Evolution Kernel — installed${RESET}\n"
  printf "${BOLD}════════════════════════════════════════════════════════════════${RESET}\n"
  echo ""
  printf "  ${DIM}Files installed:${RESET} %d\n" "$FILE_COUNT"
  echo ""
  printf "  ${BOLD}Skills available:${RESET}\n"
  echo "    /evolve        Analyze feedback and update rules"
  echo "    /reflect       Read-only analysis of evolution patterns"
  echo "    /export-state  Export kernel state for migration"
  echo ""
  printf "  ${BOLD}Get started:${RESET}\n"
  echo "    1. Open Claude Code in this directory"
  echo "    2. Complete a task and provide feedback"
  echo "    3. Use /evolve to start the self-evolution cycle"
  echo ""

  # Check if .gitignore needs updates
  local missing_entries=()
  if [ -f ".gitignore" ]; then
    grep -qF ".claude/path-kernel/event-log.jsonl" .gitignore 2>/dev/null || missing_entries+=(".claude/path-kernel/event-log.jsonl")
    grep -qF ".claude/path-kernel/state.json" .gitignore 2>/dev/null || missing_entries+=(".claude/path-kernel/state.json")
    grep -qF ".claude/path-kernel/exports/" .gitignore 2>/dev/null || missing_entries+=(".claude/path-kernel/exports/")
  else
    missing_entries=(
      ".claude/path-kernel/event-log.jsonl"
      ".claude/path-kernel/state.json"
      ".claude/path-kernel/exports/"
    )
  fi

  if [ ${#missing_entries[@]} -gt 0 ]; then
    printf "  ${YELLOW}Recommended:${RESET} Add these to your .gitignore:\n"
    echo ""
    echo "    cat >> .gitignore << 'GITIGNORE'"
    echo "    # Path kernel runtime state"
    for entry in "${missing_entries[@]}"; do
      echo "    $entry"
    done
    echo "    GITIGNORE"
    echo ""
  fi

  printf "  ${DIM}Docs: CLAUDE.md | ARCHITECTURE.md (if installed)${RESET}\n"
  printf "${BOLD}════════════════════════════════════════════════════════════════${RESET}\n"
  echo ""
}

# =============================================================================
# CLI Argument Parsing
# =============================================================================

print_help() {
  cat <<'HELP'
Path Self-Evolution Kernel Installer

Usage:
  install.sh [OPTIONS]

Options:
  -y, --yes          Non-interactive mode (auto-override on conflicts)
  -h, --help         Show this help message
  --version          Show installer version
  --repo-url URL     Use alternative repository URL (for forks/testing)

Examples:
  # Interactive installation
  bash install.sh

  # Non-interactive
  bash install.sh --yes

  # From GitHub
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zhenzhongxu/path-claudecode/HEAD/install.sh)"

  # From a fork
  bash install.sh --repo-url https://raw.githubusercontent.com/yourfork/path/HEAD
HELP
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes)
        AUTO_YES=true
        shift
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      --version)
        echo "Path installer v${INSTALLER_VERSION}"
        exit 0
        ;;
      --repo-url)
        if [ -z "${2:-}" ]; then
          die "--repo-url requires a URL argument"
        fi
        REPO_URL="$2"
        shift 2
        ;;
      *)
        die "Unknown option: $1 (use --help for usage)"
        ;;
    esac
  done
}

# =============================================================================
# Main
# =============================================================================

main() {
  parse_args "$@"

  echo ""
  printf "${BOLD}Path Self-Evolution Kernel${RESET} ${DIM}v${INSTALLER_VERSION}${RESET}\n"
  printf "${DIM}https://github.com/zhenzhongxu/path-claudecode${RESET}\n"

  preflight
  install_path
  print_summary
}

# Allow sourcing without executing (for tests)
if [ "${PATH_INSTALL_SOURCED:-}" != "1" ]; then
  main "$@"
fi
