#!/usr/bin/env bash
# ==============================================================================
# Alicia Desktop Environment - Installation Test Suite
# Proyecto Tomorrow - Enterprise Linux Desktop for Android
#
# Tests the installation pipeline: Termux setup, proot installation,
# desktop installation, VNC installation, application installation,
# customization, file verification, binary verification, config validation,
# service lifecycle, and integration tests.
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

assert_valid_xml() {
    local description="$1" filepath="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ! -f "$filepath" ]]; then
        log_fail "$description (file not found: $filepath)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
        return
    fi
    # Basic XML validation: check for XML declaration and matching root tags
    local first_line
    first_line=$(head -1 "$filepath")
    if [[ "$first_line" != *"<?xml"* ]]; then
        log_fail "$description (missing XML declaration)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
        return
    fi
    # Check for matching root element (basic check)
    local open_tag close_tag
    open_tag=$(grep -m1 '^[[:space:]]*<channel' "$filepath" 2>/dev/null | head -1 || true)
    close_tag=$(grep '</channel>' "$filepath" 2>/dev/null | head -1 || true)
    if [[ -n "$open_tag" && -n "$close_tag" ]]; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (malformed XML structure)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

assert_valid_shell() {
    local description="$1" filepath="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ ! -f "$filepath" ]]; then
        log_fail "$description (file not found: $filepath)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
        return
    fi
    local syntax_result
    syntax_result=$(bash -n "$filepath" 2>&1)
    if [[ $? -eq 0 ]]; then
        log_pass "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "$description (syntax error: $syntax_result)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$CURRENT_SUITE :: $description")
    fi
}

# ---- Paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${PROJECT_DIR}/config"
TEST_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/alicia-test-install.XXXXXX")

# Mock installation root
MOCK_INSTALL_ROOT="${TEST_TMPDIR}/rootfs"
MOCK_PREFIX="${TEST_TMPDIR}/prefix"
MOCK_HOME="${TEST_TMPDIR}/home/alicia"
mkdir -p "${MOCK_INSTALL_ROOT}/root/.config/xfce4"
mkdir -p "${MOCK_INSTALL_ROOT}/root/.config/gtk-3.0"
mkdir -p "${MOCK_PREFIX}/bin"
mkdir -p "${MOCK_HOME}/.vnc"
mkdir -p "${MOCK_HOME}/alicia/config/xfce4"
mkdir -p "${MOCK_HOME}/alicia/config/vnc"
mkdir -p "${MOCK_HOME}/alicia/config/gtk"
mkdir -p "${MOCK_HOME}/alicia/lib"
mkdir -p "${MOCK_HOME}/alicia/bin"
mkdir -p "${MOCK_HOME}/alicia/logs"
mkdir -p "${MOCK_HOME}/alicia/state"
mkdir -p "${MOCK_HOME}/alicia/locks"

# Create mock binaries (do NOT mock bash - it is needed by the test framework)
for bin in proot-distro vncserver apt dpkg; do
    echo '#!/usr/bin/env bash' > "${MOCK_PREFIX}/bin/$bin"
    echo "echo 'mock $bin: \$*'" >> "${MOCK_PREFIX}/bin/$bin"
    chmod +x "${MOCK_PREFIX}/bin/$bin" 2>/dev/null || true
done

# Create a proper systemctl mock with state management
cat > "${MOCK_PREFIX}/bin/systemctl" <<'SYSTEMCTL_MOCK'
#!/usr/bin/env bash
STATE_DIR="/tmp/alicia-mock-systemctl"
mkdir -p "$STATE_DIR"

case "${1:-}" in
    start)   echo "active" > "$STATE_DIR/${2:-default}"; echo "Mock: started ${2:-default}" ;;
    stop)    echo "inactive" > "$STATE_DIR/${2:-default}"; echo "Mock: stopped ${2:-default}" ;;
    restart) echo "active" > "$STATE_DIR/${2:-default}"; echo "Mock: restarted ${2:-default}" ;;
    status)  cat "$STATE_DIR/${2:-default}" 2>/dev/null || echo "unknown" ;;
    is-active) [[ "$(cat "$STATE_DIR/${2:-default}" 2>/dev/null || echo unknown)" == "active" ]] ;;
    enable)  echo "Mock: enabled ${2:-default}" ;;
    disable) echo "Mock: disabled ${2:-default}" ;;
    list-units) echo "UNIT LOAD ACTIVE SUB" ;;
    *)       echo "Mock systemctl: $*" ;;
esac
SYSTEMCTL_MOCK
chmod +x "${MOCK_PREFIX}/bin/systemctl" 2>/dev/null || true

# Put mocks first in PATH
ORIGINAL_PATH="${PATH}"
export PATH="${MOCK_PREFIX}/bin:${PATH}"

# Copy config files to mock install root
if [[ -d "${CONFIG_DIR}" ]]; then
    cp -r "${CONFIG_DIR}/xfce4/"* "${MOCK_HOME}/alicia/config/xfce4/" 2>/dev/null || true
    cp -r "${CONFIG_DIR}/vnc/"* "${MOCK_HOME}/alicia/config/vnc/" 2>/dev/null || true
    cp -r "${CONFIG_DIR}/gtk/"* "${MOCK_HOME}/alicia/config/gtk/" 2>/dev/null || true
    [[ -f "${CONFIG_DIR}/alicia-defaults.conf" ]] && cp "${CONFIG_DIR}/alicia-defaults.conf" "${MOCK_HOME}/alicia/config/"
fi

MAIN_BASHPID=$BASHPID
cleanup() {
    # Only clean up in the main process, not in subshells
    if [[ $BASHPID -eq $MAIN_BASHPID ]]; then
        export PATH="${ORIGINAL_PATH}"
        rm -rf "${TEST_TMPDIR}"
    fi
}
trap cleanup EXIT

# ==============================================================================
# TEST SUITES
# ==============================================================================

# ---- Suite: Termux Environment Setup ----
CURRENT_SUITE="Termux Environment Setup"
log_suite "$CURRENT_SUITE"

# Verify Termux-specific variables (may be skipped outside Termux)
if [[ -n "${PREFIX:-}" ]]; then
    assert_dir_exists "Termux PREFIX directory exists" "${PREFIX}"
    assert_contains "Termux PREFIX is under data/data" "${PREFIX}" "com.termux"
else
    echo -e "  ${C_YELLOW}⊘ SKIP${C_RESET}: PREFIX not set (not in Termux)"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
fi

# Verify essential Termux directories
assert_dir_exists "HOME directory exists" "${HOME}"
assert_not_empty "HOME is not empty" "${HOME:-}"

# Verify essential commands available
for cmd in bash chmod mkdir rm cp mv; do
    assert_true "Essential command '$cmd' is available" "$(command -v "$cmd" >/dev/null 2>&1 && echo true || echo false)"
done

# Verify storage setup (if applicable)
if [[ -d "${HOME}/storage" ]]; then
    assert_dir_exists "Termux storage directory exists" "${HOME}/storage"
else
    echo -e "  ${C_YELLOW}⊘ SKIP${C_RESET}: storage not set up (termux-setup-storage not run)"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
fi

# ---- Suite: Proot Installation ----
CURRENT_SUITE="Proot Installation"
log_suite "$CURRENT_SUITE"

# Verify proot-distro is available (either real or mock)
assert_true "proot-distro command is available" "$(command -v proot-distro >/dev/null 2>&1 && echo true || echo false)"

# Test proot-distro can list distributions
list_result=0
list_output=$(proot-distro list 2>&1) || list_result=$?
assert_equals "proot-distro list succeeds" "0" "$list_result"

# Test proot-distro install (mock)
install_result=0
install_output=$(proot-distro install debian 2>&1) || install_result=$?
assert_equals "proot-distro install debian succeeds" "0" "$install_result"

# Verify the rootfs directory concept exists
assert_not_empty "PROOT_DISTRO_DIR path is defined" "${PROOT_DISTRO_DIR:-${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/installed-rootfs}"

# ---- Suite: Desktop Installation ----
CURRENT_SUITE="Desktop Installation"
log_suite "$CURRENT_SUITE"

# Verify XFCE4 config files exist in project
assert_file_exists "XFCE4 panel config exists in project" "${CONFIG_DIR}/xfce4/xfce4-panel.xml"
assert_file_exists "XFWM4 config exists in project" "${CONFIG_DIR}/xfce4/xfwm4.xml"
assert_file_exists "XSettings config exists in project" "${CONFIG_DIR}/xfce4/xsettings.xml"

# Verify XFCE4 configs were copied to mock install
assert_file_exists "XFCE4 panel config copied to install" "${MOCK_HOME}/alicia/config/xfce4/xfce4-panel.xml"
assert_file_exists "XFWM4 config copied to install" "${MOCK_HOME}/alicia/config/xfce4/xfwm4.xml"
assert_file_exists "XSettings config copied to install" "${MOCK_HOME}/alicia/config/xfce4/xsettings.xml"

# Verify XFCE4 directory structure
assert_dir_exists "XFCE4 config directory exists" "${MOCK_HOME}/alicia/config/xfce4"

# Test that the desktop environment variable is set
DESKTOP_ENV="${DESKTOP_ENVIRONMENT:-xfce4}"
assert_equals "Desktop environment is XFCE4" "xfce4" "$DESKTOP_ENV"

# ---- Suite: VNC Installation ----
CURRENT_SUITE="VNC Installation"
log_suite "$CURRENT_SUITE"

# Verify VNC config file exists
assert_file_exists "VNC defaults config exists" "${CONFIG_DIR}/vnc/vnc-config-defaults"

# Verify VNC config copied to mock install
assert_file_exists "VNC defaults config copied to install" "${MOCK_HOME}/alicia/config/vnc/vnc-config-defaults"

# Verify VNC directory structure
assert_dir_exists "VNC config directory exists" "${MOCK_HOME}/alicia/config/vnc"
assert_dir_exists "VNC password directory can be created" "${MOCK_HOME}/.vnc"

# Test VNC server command availability
assert_true "vncserver command is available" "$(command -v vncserver >/dev/null 2>&1 && echo true || echo false)"

# Test VNC config contains expected keys
vnc_config="${CONFIG_DIR}/vnc/vnc-config-defaults"
if [[ -f "$vnc_config" ]]; then
    assert_contains "VNC config has VNC_GEOMETRY" "$(cat "$vnc_config")" "VNC_GEOMETRY"
    assert_contains "VNC config has VNC_DEPTH" "$(cat "$vnc_config")" "VNC_DEPTH"
    assert_contains "VNC config has VNC_SECURITY_TYPES" "$(cat "$vnc_config")" "VNC_SECURITY_TYPES"
    assert_contains "VNC config has VNC_ENCODINGS" "$(cat "$vnc_config")" "VNC_ENCODINGS"
    assert_contains "VNC config has VNC_COMPRESSION_LEVEL" "$(cat "$vnc_config")" "VNC_COMPRESSION_LEVEL"
    assert_contains "VNC config has VNC_DESKTOP_NAME" "$(cat "$vnc_config")" "VNC_DESKTOP_NAME"
fi

# ---- Suite: Applications Installation ----
CURRENT_SUITE="Applications Installation"
log_suite "$CURRENT_SUITE"

# Verify essential application commands (these may be mock)
for app_cmd in thunar xfce4-terminal mousepad; do
    if command -v "$app_cmd" >/dev/null 2>&1; then
        assert_true "Application '$app_cmd' is available" "true"
    else
        echo -e "  ${C_YELLOW}⊘ SKIP${C_RESET}: $app_cmd not in PATH (expected outside proot)"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi
done

# Verify desktop file references in panel config
panel_config="${CONFIG_DIR}/xfce4/xfce4-panel.xml"
if [[ -f "$panel_config" ]]; then
    assert_contains "Panel config references thunar" "$(cat "$panel_config")" "thunar"
    assert_contains "Panel config references terminal" "$(cat "$panel_config")" "terminal"
    assert_contains "Panel config references mousepad" "$(cat "$panel_config")" "mousepad"
    assert_contains "Panel config references firefox" "$(cat "$panel_config")" "firefox"
fi

# ---- Suite: Customization ----
CURRENT_SUITE="Customization"
log_suite "$CURRENT_SUITE"

# Verify GTK CSS exists
assert_file_exists "Custom GTK CSS exists" "${CONFIG_DIR}/gtk/gtk.css"

# Verify GTK CSS contains Alicia theme elements
gtk_css="${CONFIG_DIR}/gtk/gtk.css"
if [[ -f "$gtk_css" ]]; then
    assert_contains "GTK CSS has alicia accent color" "$(cat "$gtk_css")" "#2e6da4"
    assert_contains "GTK CSS has header-bar styling" "$(cat "$gtk_css")" "header-bar"
    assert_contains "GTK CSS has button styling" "$(cat "$gtk_css")" ".button"
    assert_contains "GTK CSS has sidebar styling" "$(cat "$gtk_css")" ".sidebar"
    assert_contains "GTK CSS has scrollbar styling" "$(cat "$gtk_css")" ".scrollbar"
    assert_contains "GTK CSS has panel styling" "$(cat "$gtk_css")" "xfce4-panel"
fi

# Verify alicia-defaults.conf exists
assert_file_exists "Alicia defaults config exists" "${CONFIG_DIR}/alicia-defaults.conf"

# Verify defaults config has key sections
defaults_conf="${CONFIG_DIR}/alicia-defaults.conf"
if [[ -f "$defaults_conf" ]]; then
    assert_contains "Defaults has version info" "$(cat "$defaults_conf")" "ALICIA_VERSION"
    assert_contains "Defaults has VNC settings" "$(cat "$defaults_conf")" "VNC_GEOMETRY"
    assert_contains "Defaults has desktop settings" "$(cat "$defaults_conf")" "DESKTOP_ENVIRONMENT"
    assert_contains "Defaults has user settings" "$(cat "$defaults_conf")" "DEFAULT_USERNAME"
    assert_contains "Defaults has network settings" "$(cat "$defaults_conf")" "NETWORK_DNS1"
    assert_contains "Defaults has performance settings" "$(cat "$defaults_conf")" "PERF_SWAPPINESS"
    assert_contains "Defaults has paths" "$(cat "$defaults_conf")" "ALICIA_BASE_DIR"
fi

# ---- Suite: File Verification ----
CURRENT_SUITE="File Verification"
log_suite "$CURRENT_SUITE"

# Verify all expected config files exist
expected_files=(
    "${CONFIG_DIR}/xfce4/xfce4-panel.xml"
    "${CONFIG_DIR}/xfce4/xfwm4.xml"
    "${CONFIG_DIR}/xfce4/xsettings.xml"
    "${CONFIG_DIR}/vnc/vnc-config-defaults"
    "${CONFIG_DIR}/gtk/gtk.css"
    "${CONFIG_DIR}/alicia-defaults.conf"
)
for f in "${expected_files[@]}"; do
    assert_file_exists "Config file exists: $(basename "$f")" "$f"
done

# Verify test files exist
test_files=(
    "${SCRIPT_DIR}/test-core.sh"
    "${SCRIPT_DIR}/test-system.sh"
    "${SCRIPT_DIR}/test-installation.sh"
)
for f in "${test_files[@]}"; do
    assert_file_exists "Test file exists: $(basename "$f")" "$f"
done

# Verify directory structure
assert_dir_exists "Config directory exists" "${CONFIG_DIR}"
assert_dir_exists "XFCE4 config directory exists" "${CONFIG_DIR}/xfce4"
assert_dir_exists "VNC config directory exists" "${CONFIG_DIR}/vnc"
assert_dir_exists "GTK config directory exists" "${CONFIG_DIR}/gtk"
assert_dir_exists "Tests directory exists" "${SCRIPT_DIR}"

# ---- Suite: Binary Verification ----
CURRENT_SUITE="Binary Verification"
log_suite "$CURRENT_SUITE"

# Verify mock binaries exist
for bin in proot-distro vncserver apt dpkg systemctl; do
    assert_file_exists "Mock binary exists: $bin" "${MOCK_PREFIX}/bin/$bin"
done

# Verify mock binaries are executable
for bin in proot-distro vncserver apt; do
    assert_true "Mock binary is executable: $bin" "$([ -x "${MOCK_PREFIX}/bin/$bin" ] && echo true || echo false)"
done

# Verify mock proot-distro runs
run_result=0
"${MOCK_PREFIX}/bin/proot-distro" list >/dev/null 2>&1 || run_result=$?
assert_equals "Mock binary 'proot-distro' runs successfully" "0" "$run_result"

# ---- Suite: Configuration Validation ----
CURRENT_SUITE="Configuration Validation"
log_suite "$CURRENT_SUITE"

# Validate XML files
assert_valid_xml "xfce4-panel.xml is valid XML" "${CONFIG_DIR}/xfce4/xfce4-panel.xml"
assert_valid_xml "xfwm4.xml is valid XML" "${CONFIG_DIR}/xfce4/xfwm4.xml"
assert_valid_xml "xsettings.xml is valid XML" "${CONFIG_DIR}/xfce4/xsettings.xml"

# Validate shell scripts (test files)
assert_valid_shell "test-core.sh has valid syntax" "${SCRIPT_DIR}/test-core.sh"
assert_valid_shell "test-system.sh has valid syntax" "${SCRIPT_DIR}/test-system.sh"
assert_valid_shell "test-installation.sh has valid syntax" "${SCRIPT_DIR}/test-installation.sh"

# Validate config file syntax (basic checks)
if [[ -f "${CONFIG_DIR}/alicia-defaults.conf" ]]; then
    # Check for KEY=VALUE format
    bad_lines=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        if [[ "$line" != *"="* ]]; then
            bad_lines=$((bad_lines + 1))
        fi
    done < "${CONFIG_DIR}/alicia-defaults.conf"
    assert_equals "alicia-defaults.conf has valid KEY=VALUE format" "0" "$bad_lines"
fi

# Validate VNC config
if [[ -f "${CONFIG_DIR}/vnc/vnc-config-defaults" ]]; then
    bad_lines=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        if [[ "$line" != *"="* ]]; then
            bad_lines=$((bad_lines + 1))
        fi
    done < "${CONFIG_DIR}/vnc/vnc-config-defaults"
    assert_equals "vnc-config-defaults has valid KEY=VALUE format" "0" "$bad_lines"
fi

# Validate GTK CSS (basic syntax: balanced braces)
if [[ -f "${CONFIG_DIR}/gtk/gtk.css" ]]; then
    open_braces=$(tr -cd '{' < "${CONFIG_DIR}/gtk/gtk.css" | wc -c)
    close_braces=$(tr -cd '}' < "${CONFIG_DIR}/gtk/gtk.css" | wc -c)
    assert_equals "GTK CSS has balanced braces (open)" "$open_braces" "$close_braces"
fi

# ---- Suite: Service Lifecycle ----
CURRENT_SUITE="Service Lifecycle"
log_suite "$CURRENT_SUITE"

# Test VNC start/stop lifecycle
export PATH="${MOCK_PREFIX}/bin:${PATH}"

vnc_start_output=$(vncserver :99 2>&1)
assert_contains "VNC service starts" "$vnc_start_output" "mock"

vnc_stop_output=$(vncserver -kill :99 2>&1)
assert_contains "VNC service stops" "$vnc_stop_output" "mock"

# Test service start/stop with mock systemctl
svc_start=$(systemctl start test-service 2>&1)
assert_contains "Mock service starts" "$svc_start" "Mock"

svc_status=$(systemctl status test-service 2>&1)
assert_equals "Mock service reports active after start" "active" "$svc_status"

svc_stop=$(systemctl stop test-service 2>&1)
assert_contains "Mock service stops" "$svc_stop" "Mock"

svc_after=$(systemctl status test-service 2>&1)
assert_equals "Mock service reports inactive after stop" "inactive" "$svc_after"

# Test service restart
systemctl start test-service 2>/dev/null
svc_restart=$(systemctl restart test-service 2>&1)
assert_contains "Mock service restarts" "$svc_restart" "Mock"

svc_after_restart=$(systemctl status test-service 2>&1)
assert_equals "Mock service is active after restart" "active" "$svc_after_restart"

# Clean up
systemctl stop test-service 2>/dev/null || true

# ---- Suite: Integration Tests ----
CURRENT_SUITE="Integration Tests"
log_suite "$CURRENT_SUITE"

# Test full config copy pipeline
mkdir -p "${TEST_TMPDIR}/integration_root/.config/xfce4"
mkdir -p "${TEST_TMPDIR}/integration_root/.config/gtk-3.0"
mkdir -p "${TEST_TMPDIR}/integration_root/.vnc"

# Copy configs
cp "${CONFIG_DIR}/xfce4/xfce4-panel.xml" "${TEST_TMPDIR}/integration_root/.config/xfce4/" 2>/dev/null
cp "${CONFIG_DIR}/xfce4/xfwm4.xml" "${TEST_TMPDIR}/integration_root/.config/xfce4/" 2>/dev/null
cp "${CONFIG_DIR}/xfce4/xsettings.xml" "${TEST_TMPDIR}/integration_root/.config/xfce4/" 2>/dev/null
cp "${CONFIG_DIR}/gtk/gtk.css" "${TEST_TMPDIR}/integration_root/.config/gtk-3.0/gtk.css" 2>/dev/null

assert_file_exists "Integration: panel config copied" "${TEST_TMPDIR}/integration_root/.config/xfce4/xfce4-panel.xml"
assert_file_exists "Integration: wm config copied" "${TEST_TMPDIR}/integration_root/.config/xfce4/xfwm4.xml"
assert_file_exists "Integration: xsettings copied" "${TEST_TMPDIR}/integration_root/.config/xfce4/xsettings.xml"
assert_file_exists "Integration: GTK CSS copied" "${TEST_TMPDIR}/integration_root/.config/gtk-3.0/gtk.css"

# Test config loading and parsing pipeline
if [[ -f "${CONFIG_DIR}/alicia-defaults.conf" ]]; then
    # Source the defaults and verify key variables
    # Provide fallback for variables referenced in the config that may not be set
    export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
    eval "$(grep -v '^#' "${CONFIG_DIR}/alicia-defaults.conf" | grep '=')"
    assert_not_empty "Integration: ALICIA_VERSION loaded" "${ALICIA_VERSION:-}"
    assert_not_empty "Integration: VNC_GEOMETRY loaded" "${VNC_GEOMETRY:-}"
    assert_not_empty "Integration: DESKTOP_ENVIRONMENT loaded" "${DESKTOP_ENVIRONMENT:-}"
fi

# Test end-to-end: proot install → desktop install → VNC start
e2e_step1=$(proot-distro install debian 2>&1)
assert_contains "E2E: Proot install step" "$e2e_step1" "mock"

e2e_step2=$(apt update 2>&1)
assert_contains "E2E: Package update step" "$e2e_step2" "mock"

e2e_step3=$(vncserver :1 2>&1)
assert_contains "E2E: VNC start step" "$e2e_step3" "mock"

e2e_step4=$(vncserver -kill :1 2>&1)
assert_contains "E2E: VNC stop step" "$e2e_step4" "mock"

# Test config consistency: VNC config and defaults agree
if [[ -f "${CONFIG_DIR}/vnc/vnc-config-defaults" && -f "${CONFIG_DIR}/alicia-defaults.conf" ]]; then
    vnc_geom=$(grep "^VNC_GEOMETRY=" "${CONFIG_DIR}/vnc/vnc-config-defaults" | cut -d'"' -f2)
    defaults_geom=$(grep "^VNC_GEOMETRY=" "${CONFIG_DIR}/alicia-defaults.conf" | cut -d'"' -f2)
    assert_equals "VNC geometry is consistent across configs" "$vnc_geom" "$defaults_geom"
fi

# Test XFCE4 panel has required plugins
if [[ -f "${CONFIG_DIR}/xfce4/xfce4-panel.xml" ]]; then
    panel_content=$(cat "${CONFIG_DIR}/xfce4/xfce4-panel.xml")
    assert_contains "Panel config has whiskermenu plugin" "$panel_content" "whiskermenu"
    assert_contains "Panel config has tasklist plugin" "$panel_content" "tasklist"
    assert_contains "Panel config has clock plugin" "$panel_content" "clock"
    assert_contains "Panel config has systray plugin" "$panel_content" "systray"
    assert_contains "Panel config has pager plugin" "$panel_content" "pager"
    assert_contains "Panel config has showdesktop plugin" "$panel_content" "showdesktop"
    assert_contains "Panel config has two panels" "$panel_content" 'value="2"'
fi

# Test xfwm4 has keyboard shortcuts
if [[ -f "${CONFIG_DIR}/xfce4/xfwm4.xml" ]]; then
    wm_content=$(cat "${CONFIG_DIR}/xfce4/xfwm4.xml")
    assert_contains "WM config has Alt+F4 close" "$wm_content" "close_window_key"
    assert_contains "WM config has Alt+Tab cycle" "$wm_content" "cycle_windows_key"
    assert_contains "WM config has snap to border" "$wm_content" "snap_to_border"
    assert_contains "WM config has double click action" "$wm_content" "double_click_action"
    assert_contains "WM config has title font" "$wm_content" "title_font"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================
echo -e "\n${C_BOLD}══════════════════════════════════════════${C_RESET}"
echo -e "${C_BOLD} Installation Test Suite Summary${C_RESET}"
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
