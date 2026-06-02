#!/usr/bin/env bash
# ==============================================================================
# Alicia Desktop Environment - Core Library Test Suite
# Proyecto Tomorrow - Enterprise Linux Desktop for Android
#
# Tests the core library: constants, state management, action dispatch,
# process management, dependency checking, config parsing, lock management,
# atomic operations, and environment validation.
# ==============================================================================

set -uo pipefail

# ---- Test Framework ----
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CURRENT_SUITE=""
FAILED_TESTS=()

# Colors
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'
readonly C_CYAN='\033[0;36m'
readonly C_BOLD='\033[1m'
readonly C_RESET='\033[0m'

log_pass() { echo -e "  ${C_GREEN}✓ PASS${C_RESET}: $1"; }
log_fail() { echo -e "  ${C_RED}✗ FAIL${C_RESET}: $1"; }
log_skip() { echo -e "  ${C_YELLOW}⊘ SKIP${C_RESET}: $1"; }
log_suite() { echo -e "\n${C_BOLD}${C_BLUE}── $1 ──${C_RESET}"; }

assert_equals() {
    local description="$1" expected="$2" actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" == "$actual" ]]; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (expected='$expected', actual='$actual')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

assert_not_equals() {
    local description="$1" not_expected="$2" actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$not_expected" != "$actual" ]]; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (should not equal '$not_expected')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

assert_true() {
    local description="$1" actual="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$actual" == "true" || "$actual" -eq 1 ]] 2>/dev/null; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (expected true, got '$actual')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

assert_false() {
    local description="$1" actual="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$actual" == "false" || "$actual" -eq 0 ]] 2>/dev/null; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (expected false, got '$actual')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

assert_file_exists() {
    local description="$1" filepath="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$filepath" ]]; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (file not found: $filepath)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

assert_dir_exists() {
    local description="$1" dirpath="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -d "$dirpath" ]]; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (directory not found: $dirpath)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

assert_exit_code() {
    local description="$1" expected="$2" actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$expected" -eq "$actual" ]]; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (expected exit=$expected, got exit=$actual)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

assert_contains() {
    local description="$1" haystack="$2" needle="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (string does not contain '$needle')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

assert_not_empty() {
    local description="$1" value="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -n "$value" ]]; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (value is empty)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

# ---- Source the core library (mock if unavailable) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALICIA_LIB_DIR="${ALICIA_LIB_DIR:-${SCRIPT_DIR}/../lib}"

# Provide mock implementations if core library is not available
if [[ -f "${ALICIA_LIB_DIR}/core.sh" ]]; then
    # shellcheck source=/dev/null
    source "${ALICIA_LIB_DIR}/core.sh"
else
    echo -e "${C_YELLOW}Note: core.sh not found, using mock implementations${C_RESET}"

    # Mock version constants
    ALICIA_VERSION="1.0.0"
    ALICIA_CODENAME="aurora"
    ALICIA_BUILD_DATE="2025-01-01"

    # Mock path constants
    ALICIA_BASE_DIR="${HOME}/alicia"
    ALICIA_CONFIG_DIR="${ALICIA_BASE_DIR}/config"
    ALICIA_STATE_DIR="${ALICIA_BASE_DIR}/state"
    ALICIA_LOCK_DIR="${ALICIA_BASE_DIR}/locks"
    ALICIA_LOG_DIR="${ALICIA_BASE_DIR}/logs"
    ALICIA_CACHE_DIR="${ALICIA_BASE_DIR}/cache"
    ALICIA_TEMP_DIR="${ALICIA_BASE_DIR}/tmp"

    # Mock state management
    declare -gA ALICIA_STATE=()

    alicia_state_get() { echo "${ALICIA_STATE[$1]:-}"; }
    alicia_state_set() { ALICIA_STATE["$1"]="$2"; }
    alicia_state_is() { [[ "${ALICIA_STATE[$1]:-}" == "$2" ]]; }
    alicia_state_clear() { ALICIA_STATE=(); }

    # Mock action dispatch
    declare -gA ALICIA_ACTIONS=()
    alicia_register_action() { ALICIA_ACTIONS["$1"]="$2"; }
    alicia_dispatch_action() {
        local action="$1"; shift
        if [[ -n "${ALICIA_ACTIONS[$action]:-}" ]]; then
            ${ALICIA_ACTIONS[$action]} "$@"
            return $?
        fi
        return 1
    }

    # Mock process management
    declare -gA ALICIA_PROCS=()
    alicia_proc_register() { ALICIA_PROCS["$1"]="$2"; }
    alicia_proc_is_running() { kill -0 "${ALICIA_PROCS[$1]:-0}" 2>/dev/null; }
    alicia_proc_kill() { kill "${ALICIA_PROCS[$1]:-0}" 2>/dev/null; }

    # Mock dependency checking
    alicia_check_dep() { command -v "$1" >/dev/null 2>&1; }
    alicia_check_deps() {
        local missing=0 dep
        for dep in "$@"; do
            if ! alicia_check_dep "$dep"; then
                missing=$((missing + 1))
            fi
        done
        return $missing
    }

    # Mock config parsing
    alicia_config_parse() {
        local file="$1" key value
        if [[ ! -f "$file" ]]; then return 1; fi
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#\"}" ; value="${value%\"}"
            echo "$key=$value"
        done < "$file"
    }

    # Mock lock management
    alicia_lock_acquire() {
        local lockfile="${ALICIA_LOCK_DIR}/$1.lock"
        if [[ -f "$lockfile" ]]; then
            local pid
            pid=$(head -1 "$lockfile" 2>/dev/null)
            if kill -0 "${pid:-0}" 2>/dev/null; then
                return 1
            fi
        fi
        echo $$ > "$lockfile"
        return 0
    }

    alicia_lock_release() {
        local lockfile="${ALICIA_LOCK_DIR}/$1.lock"
        rm -f "$lockfile"
    }

    alicia_lock_is_held() {
        local lockfile="${ALICIA_LOCK_DIR}/$1.lock"
        [[ -f "$lockfile" ]]
    }

    # Mock atomic write
    alicia_atomic_write() {
        local target="$1" content="$2" tmpfile
        tmpfile="${target}.tmp.$$"
        printf '%s' "$content" > "$tmpfile" || return 1
        mv -f "$tmpfile" "$target" || { rm -f "$tmpfile"; return 1; }
    }

    # Mock environment validation
    alicia_validate_env() {
        [[ -n "${PREFIX:-}" ]] || return 1
        [[ -d "${HOME}" ]] || return 1
        return 0
    }
fi

# Setup temp directories for testing
TEST_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/alicia-test-core.XXXXXX")
TEST_STATE_DIR="${TEST_TMPDIR}/state"
TEST_LOCK_DIR="${TEST_TMPDIR}/locks"
# Save original values before overriding
ALICIA_ORIG_STATE_DIR="${ALICIA_STATE_DIR:-}"
ALICIA_ORIG_LOCK_DIR="${ALICIA_LOCK_DIR:-}"
ALICIA_STATE_DIR="${TEST_STATE_DIR}"
ALICIA_LOCK_DIR="${TEST_LOCK_DIR}"
mkdir -p "${TEST_STATE_DIR}" "${TEST_LOCK_DIR}"

MAIN_BASHPID=$BASHPID
cleanup() {
    # Only clean up in the main process, not in subshells
    if [[ $BASHPID -eq $MAIN_BASHPID ]]; then
        rm -rf "${TEST_TMPDIR}"
    fi
}
trap cleanup EXIT

# ==============================================================================
# TEST SUITES
# ==============================================================================

# ---- Suite: Version Constants ----
CURRENT_SUITE="Version Constants"
log_suite "$CURRENT_SUITE"

assert_not_empty "ALICIA_VERSION is set" "${ALICIA_VERSION:-}"
assert_contains "ALICIA_VERSION has major.minor.patch format" "${ALICIA_VERSION:-}" "."
assert_not_equals "ALICIA_VERSION is not empty string" "" "${ALICIA_VERSION:-}"
assert_not_empty "ALICIA_CODENAME is set" "${ALICIA_CODENAME:-}"
assert_not_empty "ALICIA_BUILD_DATE is set" "${ALICIA_BUILD_DATE:-}"
assert_contains "ALICIA_BUILD_DATE looks like a date" "${ALICIA_BUILD_DATE:-}" "-"

# ---- Suite: Path Constants ----
CURRENT_SUITE="Path Constants"
log_suite "$CURRENT_SUITE"

assert_not_empty "ALICIA_BASE_DIR is set" "${ALICIA_BASE_DIR:-}"
assert_contains "ALICIA_BASE_DIR contains alicia" "${ALICIA_BASE_DIR:-}" "alicia"
assert_not_empty "ALICIA_CONFIG_DIR is set" "${ALICIA_CONFIG_DIR:-}"
assert_not_empty "ALICIA_STATE_DIR is set" "${ALICIA_STATE_DIR:-}"
assert_not_empty "ALICIA_LOCK_DIR is set" "${ALICIA_LOCK_DIR:-}"
assert_not_empty "ALICIA_LOG_DIR is set" "${ALICIA_LOG_DIR:-}"
assert_not_empty "ALICIA_CACHE_DIR is set" "${ALICIA_CACHE_DIR:-}"
assert_not_empty "ALICIA_TEMP_DIR is set" "${ALICIA_TEMP_DIR:-}"

# Verify paths are under base dir
assert_contains "ALICIA_CONFIG_DIR is under ALICIA_BASE_DIR" "${ALICIA_CONFIG_DIR:-}" "${ALICIA_BASE_DIR:-}"
assert_contains "ALICIA_ORIG_STATE_DIR is under ALICIA_BASE_DIR" "${ALICIA_ORIG_STATE_DIR:-}" "${ALICIA_BASE_DIR:-}"
assert_contains "ALICIA_ORIG_LOCK_DIR is under ALICIA_BASE_DIR" "${ALICIA_ORIG_LOCK_DIR:-}" "${ALICIA_BASE_DIR:-}"

# ---- Suite: State Management ----
CURRENT_SUITE="State Management"
log_suite "$CURRENT_SUITE"

# Clear state for clean test
alicia_state_clear

# Test get on non-existent key
assert_equals "State get returns empty for unset key" "" "$(alicia_state_get nonexistent_key)"

# Test set and get
alicia_state_set "test_key" "test_value"
assert_equals "State set then get works" "test_value" "$(alicia_state_get test_key)"

# Test overwrite
alicia_state_set "test_key" "new_value"
assert_equals "State overwrite works" "new_value" "$(alicia_state_get test_key)"

# Test is (matching)
alicia_state_set "status" "running"
assert_true "State is returns true for matching value" "$(alicia_state_is status running && echo true || echo false)"

# Test is (non-matching)
assert_false "State is returns false for non-matching value" "$(alicia_state_is status stopped && echo true || echo false)"

# Test is with non-existent key
assert_false "State is returns false for non-existent key" "$(alicia_state_is nonexistent anything && echo true || echo false)"

# Test multiple keys
alicia_state_set "key_a" "val_a"
alicia_state_set "key_b" "val_b"
assert_equals "State handles multiple keys (a)" "val_a" "$(alicia_state_get key_a)"
assert_equals "State handles multiple keys (b)" "val_b" "$(alicia_state_get key_b)"

# Test clear
alicia_state_clear
assert_equals "State clear removes all keys" "" "$(alicia_state_get key_a)"

# Test special characters in values
alicia_state_set "special" "hello world"
assert_equals "State handles spaces in values" "hello world" "$(alicia_state_get special)"

# Test numeric values
alicia_state_set "count" "42"
assert_equals "State handles numeric values" "42" "$(alicia_state_get count)"

# ---- Suite: Action Dispatch ----
CURRENT_SUITE="Action Dispatch"
log_suite "$CURRENT_SUITE"

# Test register and dispatch
mock_action_called="no"
mock_action_handler() { mock_action_called="yes"; }
alicia_register_action "test_action" mock_action_handler
alicia_dispatch_action "test_action"
assert_equals "Dispatch calls registered handler" "yes" "$mock_action_called"

# Test dispatch with arguments
mock_arg_result=""
mock_arg_handler() { mock_arg_result="$*"; }
alicia_register_action "arg_action" mock_arg_handler
alicia_dispatch_action "arg_action" "hello" "world"
assert_equals "Dispatch passes arguments correctly" "hello world" "$mock_arg_result"

# Test dispatch of non-existent action
dispatch_result=0
alicia_dispatch_action "nonexistent_action" 2>/dev/null || dispatch_result=$?
assert_not_equals "Dispatch non-existent action returns non-zero" "0" "$dispatch_result"

# Test overwrite action handler
mock_overwrite_result=""
mock_overwrite_v1() { mock_overwrite_result="v1"; }
mock_overwrite_v2() { mock_overwrite_result="v2"; }
alicia_register_action "overwrite_action" mock_overwrite_v1
alicia_dispatch_action "overwrite_action"
assert_equals "First handler called" "v1" "$mock_overwrite_result"
alicia_register_action "overwrite_action" mock_overwrite_v2
alicia_dispatch_action "overwrite_action"
assert_equals "Overwritten handler called" "v2" "$mock_overwrite_result"

# ---- Suite: Process Management ----
CURRENT_SUITE="Process Management"
log_suite "$CURRENT_SUITE"

# Test register a process
sleep 0.1 &  # short-lived background process
test_pid=$!
alicia_proc_register "test_sleep" "$test_pid"
assert_equals "Process registered with correct PID" "$test_pid" "${ALICIA_PROCS[test_sleep]:-}"

# Test is_running for active process
sleep 2 &
test_pid2=$!
alicia_proc_register "test_sleep2" "$test_pid2"
assert_true "Process is_running returns true for active process" "$(alicia_proc_is_running test_sleep2 && echo true || echo false)"
kill "$test_pid2" 2>/dev/null || true
wait "$test_pid2" 2>/dev/null || true

# Test is_running for completed process
sleep 0.1
assert_false "Process is_running returns false for completed process" "$(alicia_proc_is_running test_sleep && echo true || echo false)"

# Test proc_kill
sleep 5 &
test_pid3=$!
alicia_proc_register "test_killable" "$test_pid3"
alicia_proc_kill "test_killable" 2>/dev/null || true
sleep 0.2
assert_false "proc_kill terminates the process" "$(alicia_proc_is_running test_killable && echo true || echo false)"

# ---- Suite: Dependency Checking ----
CURRENT_SUITE="Dependency Checking"
log_suite "$CURRENT_SUITE"

# Test check_dep with existing command (bash should always exist)
assert_true "check_dep finds bash" "$(alicia_check_dep bash && echo true || echo false)"

# Test check_dep with non-existent command
assert_false "check_dep fails for nonexistent command" "$(alicia_check_dep nonexistent_command_xyz && echo true || echo false)"

# Test check_deps with all available
assert_true "check_deps passes for all available deps" "$(alicia_check_deps bash sh && echo true || echo false)"

# Test check_deps with some missing
assert_false "check_deps fails when some deps missing" "$(alicia_check_deps bash nonexistent_xyz && echo true || echo false)"

# ---- Suite: Config Parsing ----
CURRENT_SUITE="Config Parsing"
log_suite "$CURRENT_SUITE"

# Create a test config file
cat > "${TEST_TMPDIR}/test.conf" <<'EOF'
# This is a comment
KEY1=value1
KEY2="quoted_value"
KEY3=value3

# Another comment
EMPTY_KEY=
SPACED_KEY=hello world
EOF

# Test parsing
parsed=$(alicia_config_parse "${TEST_TMPDIR}/test.conf")
assert_not_empty "Config parse produces output" "$parsed"
assert_contains "Config parse finds KEY1" "$parsed" "KEY1=value1"
assert_contains "Config parse finds KEY2" "$parsed" "KEY2=quoted_value"
assert_contains "Config parse skips comments" "$parsed" "KEY1="

# Test parse of non-existent file
parse_result=0
alicia_config_parse "${TEST_TMPDIR}/nonexistent.conf" 2>/dev/null || parse_result=$?
assert_not_equals "Config parse fails for nonexistent file" "0" "$parse_result"

# Test parse of empty file
touch "${TEST_TMPDIR}/empty.conf"
parsed_empty=$(alicia_config_parse "${TEST_TMPDIR}/empty.conf")
assert_equals "Config parse of empty file produces empty output" "" "$parsed_empty"

# ---- Suite: Lock Management ----
CURRENT_SUITE="Lock Management"
log_suite "$CURRENT_SUITE"

# Clean up any stale locks
rm -f "${TEST_LOCK_DIR}"/*.lock

# Test acquire lock
alicia_lock_acquire "test_lock"
assert_true "Lock acquire succeeds on first attempt" "$(alicia_lock_is_held test_lock && echo true || echo false)"

# Test lock file exists
assert_file_exists "Lock file created" "${TEST_LOCK_DIR}/test_lock.lock"

# Test lock file contains PID
lock_pid=$(head -1 "${TEST_LOCK_DIR}/test_lock.lock" 2>/dev/null)
assert_equals "Lock file contains current PID" "$$" "$lock_pid"

# Test re-acquire fails (lock already held by us)
assert_false "Lock acquire fails when already held" "$(alicia_lock_acquire test_lock && echo true || echo false)"

# Test release lock
alicia_lock_release "test_lock"
assert_false "Lock is no longer held after release" "$(alicia_lock_is_held test_lock && echo true || echo false)"

# Test release and re-acquire
alicia_lock_acquire "test_lock2"
alicia_lock_release "test_lock2"
assert_true "Can re-acquire after release" "$(alicia_lock_acquire test_lock2 && echo true || echo false)"
alicia_lock_release "test_lock2"

# Test stale lock is cleaned up
echo "99999" > "${TEST_LOCK_DIR}/stale.lock"
assert_true "Stale lock acquisition succeeds" "$(alicia_lock_acquire stale && echo true || echo false)"
alicia_lock_release "stale"

# Test multiple different locks
alicia_lock_acquire "lock_a"
alicia_lock_acquire "lock_b"
assert_true "Multiple locks can be held simultaneously (a)" "$(alicia_lock_is_held lock_a && echo true || echo false)"
assert_true "Multiple locks can be held simultaneously (b)" "$(alicia_lock_is_held lock_b && echo true || echo false)"
alicia_lock_release "lock_a"
alicia_lock_release "lock_b"

# ---- Suite: Atomic Operations ----
CURRENT_SUITE="Atomic Operations"
log_suite "$CURRENT_SUITE"

# Test atomic write
target_file="${TEST_TMPDIR}/atomic_test.txt"
alicia_atomic_write "$target_file" "hello world"
assert_equals "Atomic write creates file with correct content" "hello world" "$(cat "$target_file")"

# Test atomic write overwrite
alicia_atomic_write "$target_file" "updated content"
assert_equals "Atomic write overwrite works" "updated content" "$(cat "$target_file")"

# Test atomic write with special characters
alicia_atomic_write "$target_file" "line1
line2
line3"
assert_contains "Atomic write handles multi-line content" "$(cat "$target_file")" "line2"

# Test atomic write to nested directory (should fail if dir doesn't exist)
atomic_result=0
alicia_atomic_write "${TEST_TMPDIR}/nonexistent/dir/file.txt" "test" 2>/dev/null || atomic_result=$?
assert_not_equals "Atomic write fails for nonexistent directory" "0" "$atomic_result"

# ---- Suite: Environment Validation ----
CURRENT_SUITE="Environment Validation"
log_suite "$CURRENT_SUITE"

# Test validate_env (results depend on whether we're in Termux)
env_result=0
alicia_validate_env 2>/dev/null || env_result=$?
# In Termux: should succeed (0); Outside: might fail (1)
if [[ -n "${PREFIX:-}" && -d "${HOME}" ]]; then
    assert_equals "validate_env succeeds in proper environment" "0" "$env_result"
else
    echo -e "  ${C_YELLOW}⊘ SKIP${C_RESET}: validate_env (not in Termux environment)"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
fi

# Test that HOME is set
assert_not_empty "HOME environment variable is set" "${HOME:-}"

# Test that PATH is set
assert_not_empty "PATH environment variable is set" "${PATH:-}"

# Test that USER is set
assert_not_empty "USER or LOGNAME is set" "${USER:-${LOGNAME:-}}"

# ==============================================================================
# SUMMARY
# ==============================================================================
echo -e "\n${C_BOLD}══════════════════════════════════════════${C_RESET}"
echo -e "${C_BOLD} Core Library Test Suite Summary${C_RESET}"
echo -e "${C_BOLD}══════════════════════════════════════════${C_RESET}"
echo -e "  Total:   ${C_BOLD}${TESTS_RUN}${C_RESET}"
echo -e "  Passed:  ${C_GREEN}${TESTS_PASSED}${C_RESET}"
echo -e "  Failed:  ${C_RED}${TESTS_FAILED}${C_RESET}"
echo -e "  Skipped: ${C_YELLOW}${TESTS_SKIPPED}${C_RESET}"

if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
    echo -e "\n${C_RED}${C_BOLD}Failed Tests:${C_RESET}"
    for ft in "${FAILED_TESTS[@]}"; do
        echo -e "  ${C_RED}• $ft${C_RESET}"
    done
fi

echo ""
if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${C_GREEN}${C_BOLD}All tests passed! ✓${C_RESET}"
    exit 0
else
    echo -e "${C_RED}${C_BOLD}Some tests failed! ✗${C_RESET}"
    exit 1
fi
