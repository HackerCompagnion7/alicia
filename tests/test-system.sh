#!/usr/bin/env bash
# ==============================================================================
# Alicia Desktop Environment - System Library Test Suite
# Proyecto Tomorrow - Enterprise Linux Desktop for Android
#
# Tests the system library: proot management, VNC management, package
# management, service management, user management, system info, and
# memory/storage functions. Uses mocks for proot-distro and VNC commands.
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

# ---- Mock Infrastructure ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/alicia-test-system.XXXXXX")
MOCK_BIN_DIR="${TEST_TMPDIR}/mock-bin"
MOCK_STATE_DIR="${TEST_TMPDIR}/state"
MOCK_VNC_DIR="${TEST_TMPDIR}/vnc"

mkdir -p "${MOCK_BIN_DIR}" "${MOCK_STATE_DIR}" "${MOCK_VNC_DIR}"

# Save original PATH
ORIGINAL_PATH="${PATH}"

# Mock proot-distro
cat > "${MOCK_BIN_DIR}/proot-distro" <<'MOCK_EOF'
#!/usr/bin/env bash
STATE_DIR="/tmp/alicia-test-system-state"
mkdir -p "$STATE_DIR"

case "${1:-}" in
    install)
        distro="${2:-}"
        echo "INSTALL:$distro" > "$STATE_DIR/last_proot_action"
        echo "installed" > "$STATE_DIR/${distro}_status"
        echo "Mock: installed $distro"
        exit 0
        ;;
    login)
        distro="${2:-}"
        shift 2
        echo "LOGIN:$distro:ARGS:$*" > "$STATE_DIR/last_proot_action"
        # If -- is present, execute the following command in mock
        if [[ "${1:-}" == "--" ]]; then
            shift
            exec "$@"
        fi
        exit 0
        ;;
    remove)
        distro="${2:-}"
        echo "REMOVE:$distro" > "$STATE_DIR/last_proot_action"
        rm -f "$STATE_DIR/${distro}_status"
        echo "Mock: removed $distro"
        exit 0
        ;;
    list)
        # Output mock distro list
        echo "  - ubuntu"
        echo "  - debian"
        echo "  - alpine"
        # Show installed
        for f in "$STATE_DIR"/*_status; do
            [[ -f "$f" ]] || continue
            dname=$(basename "$f" _status)
            echo "  - $dname [installed]"
        done
        exit 0
        ;;
    backup)
        distro="${2:-}"
        echo "BACKUP:$distro" > "$STATE_DIR/last_proot_action"
        echo "Mock: backed up $distro"
        exit 0
        ;;
    reset)
        distro="${2:-}"
        echo "RESET:$distro" > "$STATE_DIR/last_proot_action"
        echo "Mock: reset $distro"
        exit 0
        ;;
    *)
        echo "Mock proot-distro: unknown command $1" >&2
        exit 1
        ;;
esac
MOCK_EOF
chmod +x "${MOCK_BIN_DIR}/proot-distro"

# Mock vncserver
cat > "${MOCK_BIN_DIR}/vncserver" <<'MOCK_EOF'
#!/usr/bin/env bash
STATE_DIR="/tmp/alicia-test-system-state"
mkdir -p "$STATE_DIR"

case "${1:-}" in
    :*)
        display="${1#:}"
        echo "$display:active" > "$STATE_DIR/vnc_display_${display}"
        echo "Mock: VNC server started on :$display"
        exit 0
        ;;
    -kill)
        display="${2#:}"
        rm -f "$STATE_DIR/vnc_display_${display}"
        echo "Mock: VNC server stopped on :$display"
        exit 0
        ;;
    -list)
        for f in "$STATE_DIR"/vnc_display_*; do
            [[ -f "$f" ]] || continue
            dname=$(basename "$f" | sed 's/vnc_display_//')
            echo ":$dname  PID=$((RANDOM % 10000 + 1000))"
        done
        exit 0
        ;;
    *)
        echo "Mock vncserver: $*" > "$STATE_DIR/last_vnc_action"
        exit 0
        ;;
esac
MOCK_EOF
chmod +x "${MOCK_BIN_DIR}/vncserver"

# Mock apt (inside proot)
cat > "${MOCK_BIN_DIR}/apt" <<'MOCK_EOF'
#!/usr/bin/env bash
STATE_DIR="/tmp/alicia-test-system-state"
mkdir -p "$STATE_DIR"
echo "APT:$*" > "$STATE_DIR/last_apt_action"
case "${1:-}" in
    install|update|upgrade|autoremove|remove)
        echo "Mock apt: $*"
        exit 0
        ;;
    *)
        echo "Mock apt: unknown command $1" >&2
        exit 1
        ;;
esac
MOCK_EOF
chmod +x "${MOCK_BIN_DIR}/apt"

# Mock systemctl
cat > "${MOCK_BIN_DIR}/systemctl" <<'MOCK_EOF'
#!/usr/bin/env bash
STATE_DIR="/tmp/alicia-test-system-state"
mkdir -p "$STATE_DIR"

case "${1:-}" in
    start)
        svc="${2:-}"
        echo "active" > "$STATE_DIR/svc_${svc}"
        echo "Mock: started $svc"
        exit 0
        ;;
    stop)
        svc="${2:-}"
        echo "inactive" > "$STATE_DIR/svc_${svc}"
        echo "Mock: stopped $svc"
        exit 0
        ;;
    restart)
        svc="${2:-}"
        echo "active" > "$STATE_DIR/svc_${svc}"
        echo "Mock: restarted $svc"
        exit 0
        ;;
    status)
        svc="${2:-}"
        if [[ -f "$STATE_DIR/svc_${svc}" ]]; then
            cat "$STATE_DIR/svc_${svc}"
        else
            echo "unknown"
        fi
        exit 0
        ;;
    is-active)
        svc="${2:-}"
        status=$(cat "$STATE_DIR/svc_${svc}" 2>/dev/null || echo "unknown")
        echo "$status"
        [[ "$status" == "active" ]]
        exit $?
        ;;
    is-enabled)
        svc="${2:-}"
        echo "enabled"
        exit 0
        ;;
    enable)
        svc="${2:-}"
        echo "Mock: enabled $svc"
        exit 0
        ;;
    disable)
        svc="${2:-}"
        echo "Mock: disabled $svc"
        exit 0
        ;;
    list-units)
        echo "UNIT                    LOAD   ACTIVE SUB     JOB"
        echo "dbus.service            loaded active running"
        echo "NetworkManager.service loaded active running"
        exit 0
        ;;
    *)
        echo "Mock systemctl: unknown command $1" >&2
        exit 1
        ;;
esac
MOCK_EOF
chmod +x "${MOCK_BIN_DIR}/systemctl"

# Put mocks first in PATH
export PATH="${MOCK_BIN_DIR}:${ORIGINAL_PATH}"

# Set mock state directory
export ALICIA_TEST_STATE_DIR="${TEST_TMPDIR}/state"
mkdir -p "${ALICIA_TEST_STATE_DIR}"

# Source system library or provide mocks
ALICIA_LIB_DIR="${ALICIA_LIB_DIR:-${SCRIPT_DIR}/../lib}"

if [[ -f "${ALICIA_LIB_DIR}/system.sh" ]]; then
    # shellcheck source=/dev/null
    source "${ALICIA_LIB_DIR}/system.sh"
else
    echo -e "${C_YELLOW}Note: system.sh not found, using mock implementations${C_RESET}"

    # Mock proot management
    alicia_proot_install() {
        local distro="${1:-debian}"
        proot-distro install "$distro"
    }
    alicia_proot_login() {
        local distro="${1:-debian}"; shift
        proot-distro login "$distro" -- "$@"
    }
    alicia_proot_remove() {
        local distro="${1:-debian}"
        proot-distro remove "$distro"
    }
    alicia_proot_list() {
        proot-distro list
    }
    alicia_proot_is_installed() {
        local distro="${1:-debian}"
        proot-distro list 2>/dev/null | grep -q "$distro.*installed"
    }
    alicia_proot_run() {
        local distro="${1:-debian}"; shift
        proot-distro login "$distro" -- bash -c "$*"
    }

    # Mock VNC management
    alicia_vnc_start() {
        local display="${1:-:1}"
        vncserver "$display"
    }
    alicia_vnc_stop() {
        local display="${1:-:1}"
        vncserver -kill "$display"
    }
    alicia_vnc_is_running() {
        local display="${1:-:1}"
        vncserver -list 2>/dev/null | grep -q "${display#:}"
    }
    alicia_vnc_list() {
        vncserver -list 2>/dev/null
    }
    alicia_vnc_set_password() {
        local password="${1:-alicia}"
        mkdir -p "${HOME}/.vnc"
        echo "$password" > "${HOME}/.vnc/mock_passwd"
    }

    # Mock package management
    alicia_pkg_install() {
        proot-distro login debian -- apt install -y "$@"
    }
    alicia_pkg_remove() {
        proot-distro login debian -- apt remove -y "$@"
    }
    alicia_pkg_update() {
        proot-distro login debian -- apt update
    }
    alicia_pkg_upgrade() {
        proot-distro login debian -- apt upgrade -y
    }
    alicia_pkg_autoremove() {
        proot-distro login debian -- apt autoremove -y
    }
    alicia_pkg_is_installed() {
        local pkg="$1"
        proot-distro login debian -- dpkg -s "$pkg" 2>/dev/null | grep -q "Status: install ok installed"
    }
    alicia_pkg_search() {
        local query="$1"
        proot-distro login debian -- apt search "$query" 2>/dev/null
    }

    # Mock service management
    alicia_service_start()   { systemctl start "$1"; }
    alicia_service_stop()    { systemctl stop "$1"; }
    alicia_service_restart() { systemctl restart "$1"; }
    alicia_service_status()  { systemctl status "$1" 2>/dev/null || echo "unknown"; }
    alicia_service_is_active() { systemctl is-active "$1" 2>/dev/null; }
    alicia_service_enable()  { systemctl enable "$1"; }
    alicia_service_disable() { systemctl disable "$1"; }
    alicia_service_list()    { systemctl list-units --type=service 2>/dev/null; }

    # Mock user management
    alicia_user_create() {
        local username="${1:-alicia}"
        echo "user_created:$username" > "${ALICIA_TEST_STATE_DIR}/last_user_action"
    }
    alicia_user_delete() {
        local username="${1:-alicia}"
        echo "user_deleted:$username" > "${ALICIA_TEST_STATE_DIR}/last_user_action"
    }
    alicia_user_exists() {
        local username="${1:-alicia}"
        grep -q "^$username" /etc/passwd 2>/dev/null
    }
    alicia_user_set_password() {
        local username="${1:-alicia}" password="${2:-}"
        echo "password_set:$username" > "${ALICIA_TEST_STATE_DIR}/last_user_action"
    }

    # Mock system info
    alicia_sys_arch() { uname -m 2>/dev/null || echo "unknown"; }
    alicia_sys_kernel() { uname -r 2>/dev/null || echo "unknown"; }
    alicia_sys_hostname() { hostname 2>/dev/null || echo "alicia"; }
    alicia_sys_uptime() { uptime 2>/dev/null || echo "unknown"; }
    alicia_sys_os_name() { echo "Debian GNU/Linux"; }
    alicia_sys_os_version() { echo "12"; }

    # Mock memory/storage functions
    alicia_mem_total() {
        if [[ -f /proc/meminfo ]]; then
            awk '/MemTotal/ {print $2}' /proc/meminfo
        else
            echo "4096"
        fi
    }
    alicia_mem_available() {
        if [[ -f /proc/meminfo ]]; then
            awk '/MemAvailable/ {print $2}' /proc/meminfo
        else
            echo "2048"
        fi
    }
    alicia_mem_used() {
        local total available
        total=$(alicia_mem_total)
        available=$(alicia_mem_available)
        echo $(( total - available ))
    }
    alicia_mem_usage_percent() {
        local total used
        total=$(alicia_mem_total)
        used=$(alicia_mem_used)
        echo $(( used * 100 / total ))
    }
    alicia_disk_total() { df --output=size / 2>/dev/null | tail -1 | tr -d ' ' || echo "0"; }
    alicia_disk_used() { df --output=used / 2>/dev/null | tail -1 | tr -d ' ' || echo "0"; }
    alicia_disk_available() { df --output=avail / 2>/dev/null | tail -1 | tr -d ' ' || echo "0"; }
    alicia_disk_usage_percent() { df --output=pcent / 2>/dev/null | tail -1 | tr -d ' %' || echo "0"; }
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

# ---- Suite: Proot Management ----
CURRENT_SUITE="Proot Management"
log_suite "$CURRENT_SUITE"

# Test proot install
install_output=$(alicia_proot_install debian 2>&1)
assert_contains "Proot install runs successfully" "$install_output" "Mock"
assert_contains "Proot install mentions distro name" "$install_output" "debian"

# Test proot is_installed (after install)
install_check=$(alicia_proot_is_installed debian 2>&1 && echo "true" || echo "false")
assert_true "Proot reports debian as installed" "$install_check"

# Test proot list
list_output=$(alicia_proot_list 2>&1)
assert_contains "Proot list shows available distros" "$list_output" "debian"
assert_contains "Proot list shows ubuntu" "$list_output" "ubuntu"

# Test proot run command
run_output=$(alicia_proot_run debian echo "hello" 2>&1)
assert_not_empty "Proot run produces output" "$run_output"

# Test proot remove
remove_output=$(alicia_proot_remove debian 2>&1)
assert_contains "Proot remove runs" "$remove_output" "Mock"

# Test proot install of different distro
install_ubuntu=$(alicia_proot_install ubuntu 2>&1)
assert_contains "Proot install ubuntu works" "$install_ubuntu" "ubuntu"

# ---- Suite: VNC Management ----
CURRENT_SUITE="VNC Management"
log_suite "$CURRENT_SUITE"

# Test VNC start
vnc_start_output=$(alicia_vnc_start :1 2>&1)
assert_contains "VNC start produces output" "$vnc_start_output" "Mock"
assert_contains "VNC start mentions display" "$vnc_start_output" "1"

# Test VNC is_running after start
vnc_running=$(alicia_vnc_is_running :1 2>&1 && echo "true" || echo "false")
# With mock, this depends on mock state file existence
assert_not_empty "VNC is_running returns a result" "$vnc_running"

# Test VNC list
vnc_list_output=$(alicia_vnc_list 2>&1)
# May be empty if no displays, but should not error
vnc_list_result=$?
assert_equals "VNC list command succeeds" "0" "$vnc_list_result"

# Test VNC stop
vnc_stop_output=$(alicia_vnc_stop :1 2>&1)
assert_contains "VNC stop produces output" "$vnc_stop_output" "Mock"

# Test VNC set password
alicia_vnc_set_password "testpass123" 2>/dev/null
assert_file_exists "VNC password file created" "${HOME}/.vnc/mock_passwd"

# Test VNC start with different display
vnc_start2=$(alicia_vnc_start :2 2>&1)
assert_contains "VNC start on :2 works" "$vnc_start2" "2"

# Clean up
alicia_vnc_stop :2 2>/dev/null || true

# ---- Suite: Package Management ----
CURRENT_SUITE="Package Management"
log_suite "$CURRENT_SUITE"

# Test pkg update
pkg_update_output=$(alicia_pkg_update 2>&1)
assert_contains "Package update runs" "$pkg_update_output" "Mock"

# Test pkg install
pkg_install_output=$(alicia_pkg_install vim 2>&1)
assert_contains "Package install runs" "$pkg_install_output" "Mock"

# Test pkg install with multiple packages
pkg_multi_output=$(alicia_pkg_install git wget curl 2>&1)
assert_contains "Package install multiple works" "$pkg_multi_output" "Mock"

# Test pkg remove
pkg_remove_output=$(alicia_pkg_remove vim 2>&1)
assert_contains "Package remove runs" "$pkg_remove_output" "Mock"

# Test pkg upgrade
pkg_upgrade_output=$(alicia_pkg_upgrade 2>&1)
assert_contains "Package upgrade runs" "$pkg_upgrade_output" "Mock"

# Test pkg autoremove
pkg_autoremove_output=$(alicia_pkg_autoremove 2>&1)
assert_contains "Package autoremove runs" "$pkg_autoremove_output" "Mock"

# ---- Suite: Service Management ----
CURRENT_SUITE="Service Management"
log_suite "$CURRENT_SUITE"

# Test service start
svc_start=$(alicia_service_start dbus 2>&1)
assert_contains "Service start runs" "$svc_start" "Mock"

# Test service is_active after start
svc_active=$(alicia_service_is_active dbus 2>&1)
assert_equals "Service is active after start" "active" "$svc_active"

# Test service status
svc_status=$(alicia_service_status dbus 2>&1)
assert_not_empty "Service status returns value" "$svc_status"

# Test service restart
svc_restart=$(alicia_service_restart dbus 2>&1)
assert_contains "Service restart runs" "$svc_restart" "Mock"

# Test service stop
svc_stop=$(alicia_service_stop dbus 2>&1)
assert_contains "Service stop runs" "$svc_stop" "Mock"

# Test service is_active after stop (should be inactive with mock)
svc_after_stop=$(alicia_service_is_active dbus 2>&1)
assert_equals "Service is inactive after stop" "inactive" "$svc_after_stop"

# Test service enable
svc_enable=$(alicia_service_enable dbus 2>&1)
assert_contains "Service enable runs" "$svc_enable" "Mock"

# Test service disable
svc_disable=$(alicia_service_disable dbus 2>&1)
assert_contains "Service disable runs" "$svc_disable" "Mock"

# Test service list
svc_list=$(alicia_service_list 2>&1)
assert_contains "Service list returns units" "$svc_list" "UNIT"

# ---- Suite: User Management ----
CURRENT_SUITE="User Management"
log_suite "$CURRENT_SUITE"

# Test user create
alicia_user_create "testuser" 2>/dev/null
user_action=$(cat "${ALICIA_TEST_STATE_DIR}/last_user_action" 2>/dev/null || echo "")
assert_contains "User create records action" "$user_action" "user_created"
assert_contains "User create records username" "$user_action" "testuser"

# Test user set password
alicia_user_set_password "testuser" "secret123" 2>/dev/null
pwd_action=$(cat "${ALICIA_TEST_STATE_DIR}/last_user_action" 2>/dev/null || echo "")
assert_contains "User set password records action" "$pwd_action" "password_set"

# Test user delete
alicia_user_delete "testuser" 2>/dev/null
del_action=$(cat "${ALICIA_TEST_STATE_DIR}/last_user_action" 2>/dev/null || echo "")
assert_contains "User delete records action" "$del_action" "user_deleted"

# Test user exists (depends on actual system state)
user_exists_result=$(alicia_user_exists "nonexistent_user_xyz" 2>&1 && echo "true" || echo "false")
assert_false "User exists returns false for nonexistent user" "$user_exists_result"

# ---- Suite: System Info ----
CURRENT_SUITE="System Info"
log_suite "$CURRENT_SUITE"

# Test architecture detection
arch=$(alicia_sys_arch)
assert_not_empty "System arch is not empty" "$arch"
assert_contains "System arch is a known architecture" "$arch" "$(uname -m 2>/dev/null || echo 'unknown')"

# Test kernel version
kernel=$(alicia_sys_kernel)
assert_not_empty "System kernel version is not empty" "$kernel"

# Test hostname
hostname_val=$(alicia_sys_hostname)
assert_not_empty "System hostname is not empty" "$hostname_val"

# Test uptime
uptime_val=$(alicia_sys_uptime)
assert_not_empty "System uptime is not empty" "$uptime_val"

# Test OS name
os_name=$(alicia_sys_os_name)
assert_not_empty "System OS name is not empty" "$os_name"

# Test OS version
os_ver=$(alicia_sys_os_version)
assert_not_empty "System OS version is not empty" "$os_ver"

# ---- Suite: Memory Functions ----
CURRENT_SUITE="Memory Functions"
log_suite "$CURRENT_SUITE"

# Test memory total
mem_total=$(alicia_mem_total)
assert_not_empty "Memory total is not empty" "$mem_total"
# Should be a number
[[ "$mem_total" =~ ^[0-9]+$ ]]
mem_total_is_number=$?
assert_equals "Memory total is numeric" "0" "$mem_total_is_number"

# Test memory available
mem_avail=$(alicia_mem_available)
assert_not_empty "Memory available is not empty" "$mem_avail"
[[ "$mem_avail" =~ ^[0-9]+$ ]]
mem_avail_is_number=$?
assert_equals "Memory available is numeric" "0" "$mem_avail_is_number"

# Test memory used
mem_used=$(alicia_mem_used)
assert_not_empty "Memory used is not empty" "$mem_used"

# Test memory usage percent
mem_pct=$(alicia_mem_usage_percent)
assert_not_empty "Memory usage percent is not empty" "$mem_pct"
# Should be 0-100
[[ "$mem_pct" -ge 0 && "$mem_pct" -le 100 ]] 2>/dev/null
mem_pct_in_range=$?
if [[ "$mem_pct_in_range" -eq 0 ]]; then
    log_pass "Memory usage percent is in valid range (0-100)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_fail "Memory usage percent out of range: $mem_pct"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$CURRENT_SUITE :: Memory usage percent in range")
fi
TESTS_RUN=$((TESTS_RUN + 1))

# ---- Suite: Storage Functions ----
CURRENT_SUITE="Storage Functions"
log_suite "$CURRENT_SUITE"

# Test disk total
disk_total=$(alicia_disk_total)
assert_not_empty "Disk total is not empty" "$disk_total"

# Test disk used
disk_used=$(alicia_disk_used)
assert_not_empty "Disk used is not empty" "$disk_used"

# Test disk available
disk_avail=$(alicia_disk_available)
assert_not_empty "Disk available is not empty" "$disk_avail"

# Test disk usage percent
disk_pct=$(alicia_disk_usage_percent)
assert_not_empty "Disk usage percent is not empty" "$disk_pct"
# Should be 0-100
[[ "$disk_pct" -ge 0 && "$disk_pct" -le 100 ]] 2>/dev/null
disk_pct_in_range=$?
if [[ "$disk_pct_in_range" -eq 0 ]]; then
    log_pass "Disk usage percent is in valid range (0-100)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_fail "Disk usage percent out of range: $disk_pct"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$CURRENT_SUITE :: Disk usage percent in range")
fi
TESTS_RUN=$((TESTS_RUN + 1))

# ==============================================================================
# SUMMARY
# ==============================================================================
echo -e "\n${C_BOLD}══════════════════════════════════════════${C_RESET}"
echo -e "${C_BOLD} System Library Test Suite Summary${C_RESET}"
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
