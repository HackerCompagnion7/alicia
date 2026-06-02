#!/bin/bash
# ============================================================================
# start.sh - Alicia Desktop Environment Startup Script
# ============================================================================
# Copyright (C) 2005-2025 Proyecto Tomorrow
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# ============================================================================
# Author:       Proyecto Tomorrow
# Version:      3.1.0
# Description:  Main startup script for the Alicia Desktop Environment.
#               Validates environment, starts proot, VNC, and desktop,
#               performs health checks, and displays connection info.
# Usage:        start.sh [--force] [--resolution WxH] [--port PORT] [--quiet]
# ============================================================================

set -euo pipefail

# ============================================================================
# Script Directory Resolution
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# ============================================================================
# Source Alicia Libraries
# ============================================================================
for lib_file in "${LIB_DIR}"/alicia-*.sh; do
    if [[ -f "${lib_file}" ]]; then
        # shellcheck source=/dev/null
        source "${lib_file}" 2>&1 || {
            echo "ERROR: Failed to source library: ${lib_file}" >&2
            exit 1
        }
    fi
done

# Verify core library loaded
if ! declare -f alicia_init_directories &>/dev/null; then
    echo "ERROR: Failed to load alicia core libraries" >&2
    exit 1
fi

# ============================================================================
# Initialize Directories and Logging
# ============================================================================
alicia_init_directories || {
    echo "ERROR: Failed to initialize alicia directories" >&2
    exit 1
}

log_init "${ALICIA_LOG_DIR}" "${ALICIA_LOG_DIR}/start.log"
log_set_module "start"

# ============================================================================
# Script-Level Variables
# ============================================================================
FORCE_START=false
QUIET_MODE=false
CUSTOM_RESOLUTION=""
CUSTOM_PORT=""
STARTUP_PID_FILE="${ALICIA_STATE_DIR}/alicia.pid"
STARTUP_LOCK_FILE="${ALICIA_LOCK_DIR}/alicia-startup.lock"
STARTUP_FAILED=false

# Override defaults from config
VNC_PORT="${ALICIA_DEFAULT_VNC_PORT}"
VNC_RESOLUTION="${ALICIA_DEFAULT_VNC_RESOLUTION}"
VNC_DEPTH="${ALICIA_VNC_DEPTH:-24}"
VNC_PASSWORD="${ALICIA_VNC_PASSWORD:-alicia}"
DESKTOP_ENV="${ALICIA_DEFAULT_DESKTOP_ENV}"
PROOT_DISTRO="${ALICIA_DEFAULT_PROOT_DISTRO}"
DISPLAY_NUM="${ALICIA_DEFAULT_DISPLAY#:}"

# ============================================================================
# Parse Command-Line Arguments
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                FORCE_START=true
                shift
                ;;
            --resolution|-r)
                if [[ -z "${2:-}" ]]; then
                    log_error "--resolution requires a value (e.g., 1920x1080)"
                    exit 1
                fi
                CUSTOM_RESOLUTION="$2"
                shift 2
                ;;
            --port|-p)
                if [[ -z "${2:-}" ]]; then
                    log_error "--port requires a value (e.g., 5901)"
                    exit 1
                fi
                CUSTOM_PORT="$2"
                shift 2
                ;;
            --quiet|-q)
                QUIET_MODE=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

show_usage() {
    echo "Usage: start.sh [OPTIONS]"
    echo ""
    echo "Start the Alicia Desktop Environment."
    echo ""
    echo "Options:"
    echo "  --force, -f          Kill existing instance and restart"
    echo "  --resolution, -r WxH Set VNC resolution (default: ${VNC_RESOLUTION})"
    echo "  --port, -p PORT      Set VNC port (default: ${VNC_PORT})"
    echo "  --quiet, -q          Minimal output mode"
    echo "  --help, -h           Show this help message"
    echo ""
    echo "Examples:"
    echo "  start.sh                          Start with defaults"
    echo "  start.sh --resolution 1920x1080   Start with Full HD resolution"
    echo "  start.sh --force --port 5902      Force restart on port 5902"
}

# ============================================================================
# ASCII Art Banner
# ============================================================================
show_banner() {
    if [[ "${QUIET_MODE}" == "true" ]]; then
        return 0
    fi

    printf "${COLOR_BOLD_CYAN}%s${COLOR_RESET}\n" \
"    ___    _ _      _     ___ _    ___ "
    printf "${COLOR_BOLD_CYAN}%s${COLOR_RESET}\n" \
"   /   |  (_) |____| |__ / __| |  |_ _|"
    printf "${COLOR_BOLD_CYAN}%s${COLOR_RESET}\n" \
"  / /| |__| | '_ \\ _ \\ '_ \\ (__| |__ | | "
    printf "${COLOR_BOLD_CYAN}%s${COLOR_RESET}\n" \
" /_/ |____|_|_.__\\___/_| |_|\\___|____|___|"
    printf "${COLOR_BOLD_CYAN}%s${COLOR_RESET}\n" \
"                                  |___| "
    echo ""
    printf "${COLOR_BOLD_WHITE}  Alicia Desktop Environment v${ALICIA_VERSION}${COLOR_RESET}\n"
    printf "${COLOR_DIM}  Copyright (C) 2005-2025 Proyecto Tomorrow${COLOR_RESET}\n"
    printf "${COLOR_DIM}  Licensed under GNU GPL v3.0+${COLOR_RESET}\n"
    echo ""
    log_separator "=" 50
}

# ============================================================================
# Environment Validation
# ============================================================================

# Check if running inside Termux
check_termux() {
    log_info "Checking Termux environment..."
    if [[ -z "${TERMUX_VERSION:-}" && ! -d "/data/data/com.termux" ]]; then
        log_warn "Not running inside Termux (some features may not work)"
        return 0  # Soft requirement -- allow running on desktop Linux for dev
    fi
    log_info "Termux environment detected (version: ${TERMUX_VERSION:-unknown})"
    return 0
}

# Check if proot is installed
check_proot() {
    log_info "Checking proot installation..."
    if ! proot_is_installed; then
        log_error "proot-distro is not installed"
        log_info "Install it with: pkg install proot-distro"
        return 1
    fi
    log_info "proot-distro is installed"
    return 0
}

# Check if Linux distribution is installed inside proot
check_distro() {
    log_info "Checking Linux distribution (${PROOT_DISTRO})..."
    if ! proot_is_distro_installed "${PROOT_DISTRO}"; then
        log_error "Distribution '${PROOT_DISTRO}' is not installed via proot-distro"
        log_info "Install it with: proot-distro install ${PROOT_DISTRO}"
        log_info "Or run the Alicia installer: ./scripts/install.sh"
        return 1
    fi
    log_info "Distribution '${PROOT_DISTRO}' is installed"
    return 0
}

# Check storage access
check_storage() {
    log_info "Checking storage access..."
    local storage_dir="${HOME}/storage"
    if [[ ! -d "${storage_dir}" && -n "${TERMUX_VERSION:-}" ]]; then
        log_warn "Termux storage not set up -- run 'termux-setup-storage' first"
        # Not a hard failure; some setups work without it
    fi

    # Check minimum available space
    local avail
    avail=$(storage_get_available_space "${ALICIA_HOME}" 2>/dev/null || echo "0")
    if [[ ${avail} -lt ${ALICIA_MIN_STORAGE_MB} ]]; then
        log_error "Insufficient storage: ${avail}MB available (need ${ALICIA_MIN_STORAGE_MB}MB)"
        return 1
    fi
    log_info "Storage OK (${avail}MB available)"
    return 0
}

# Check minimum RAM
check_memory() {
    log_info "Checking available memory..."
    local mem_total
    mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
    if [[ ${mem_total} -gt 0 && ${mem_total} -lt ${ALICIA_MIN_RAM_MB} ]]; then
        log_warn "Low memory: ${mem_total}MB total (recommended: ${ALICIA_MIN_RAM_MB}MB)"
        log_warn "Alicia may run slowly or crash under memory pressure"
    else
        log_info "Memory OK (${mem_total}MB total)"
    fi
    return 0
}

# Check network connectivity
check_network() {
    log_info "Checking network connectivity..."
    if network_is_available 2>/dev/null; then
        log_info "Network connectivity: OK"
    else
        log_warn "No network connectivity -- offline mode"
    fi
    return 0  # Non-fatal
}

# Run all environment checks
validate_environment() {
    log_section "Environment Validation"

    local failures=0

    check_termux   || ((failures++))
    check_proot    || ((failures++))
    check_distro   || ((failures++))
    check_storage  || ((failures++))
    check_memory   || true
    check_network  || true

    if [[ ${failures} -gt 0 ]]; then
        log_error "Environment validation failed (${failures} critical issue(s))"
        return 1
    fi

    log_info "Environment validation passed"
    return 0
}

# ============================================================================
# Already-Running Check
# ============================================================================
check_already_running() {
    log_info "Checking if Alicia is already running..."

    if [[ -f "${STARTUP_PID_FILE}" ]]; then
        local existing_pid
        existing_pid=$(cat "${STARTUP_PID_FILE}" 2>/dev/null || echo "")

        if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
            if [[ "${FORCE_START}" == "true" ]]; then
                log_warn "Alicia is already running (PID: ${existing_pid}) -- forcing restart"
                force_stop_existing
                return 0
            else
                log_error "Alicia is already running (PID: ${existing_pid})"
                log_info "Use --force to kill the existing instance and restart"
                return 1
            fi
        else
            log_warn "Stale PID file found (PID: ${existing_pid}) -- cleaning up"
            rm -f "${STARTUP_PID_FILE}" 2>/dev/null || true
        fi
    fi

    # Check lock file as a secondary mechanism
    if alicia_lock_is_held "alicia-startup"; then
        if [[ "${FORCE_START}" == "true" ]]; then
            log_warn "Startup lock is held -- forcing removal"
            rm -f "${ALICIA_LOCK_DIR}/alicia-startup.lock" 2>/dev/null || true
        else
            log_error "Another startup process is running"
            return 1
        fi
    fi

    log_info "No existing instance detected"
    return 0
}

# Force-stop an existing Alicia instance
force_stop_existing() {
    log_info "Force-stopping existing Alicia instance..."

    # Try the stop script first
    if [[ -x "${SCRIPT_DIR}/stop.sh" ]]; then
        log_info "Calling stop.sh --force..."
        bash "${SCRIPT_DIR}/stop.sh" --force 2>/dev/null || true
    else
        # Manual cleanup
        log_info "Performing manual cleanup..."

        # Stop desktop
        if declare -f de_stop &>/dev/null; then
            de_stop 2>/dev/null || true
        fi

        # Stop VNC
        if declare -f vnc_stop &>/dev/null; then
            vnc_stop 2>/dev/null || true
        fi

        # Stop proot
        if declare -f proot_stop &>/dev/null; then
            proot_stop 2>/dev/null || true
        fi

        # Kill remaining processes
        pkill -f "Xvnc" 2>/dev/null || true
        pkill -f "Xvfb" 2>/dev/null || true
        pkill -f "xfce4-session" 2>/dev/null || true

        # Clean PID/lock files
        rm -f "${STARTUP_PID_FILE}" 2>/dev/null || true
        rm -f "${ALICIA_LOCK_DIR}/alicia-startup.lock" 2>/dev/null || true
    fi

    sleep 2
    log_info "Existing instance stopped"
}

# ============================================================================
# Apply Runtime Overrides
# ============================================================================
apply_overrides() {
    log_info "Applying runtime configuration overrides..."

    # Resolution override
    if [[ -n "${CUSTOM_RESOLUTION}" ]]; then
        if [[ "${CUSTOM_RESOLUTION}" =~ ^[0-9]+x[0-9]+$ ]]; then
            VNC_RESOLUTION="${CUSTOM_RESOLUTION}"
            log_info "Resolution override: ${VNC_RESOLUTION}"
        else
            log_error "Invalid resolution format: ${CUSTOM_RESOLUTION} (expected WxH)"
            return 1
        fi
    fi

    # Port override
    if [[ -n "${CUSTOM_PORT}" ]]; then
        if [[ "${CUSTOM_PORT}" =~ ^[0-9]+$ ]] && [[ "${CUSTOM_PORT}" -ge 5900 ]] && [[ "${CUSTOM_PORT}" -le 5999 ]]; then
            VNC_PORT="${CUSTOM_PORT}"
            log_info "Port override: ${VNC_PORT}"
        else
            log_error "Invalid VNC port: ${CUSTOM_PORT} (must be 5900-5999)"
            return 1
        fi
    fi

    # Load saved config if present
    if [[ -f "${ALICIA_CONFIG_DIR}/alicia.conf" ]]; then
        alicia_parse_config "${ALICIA_CONFIG_DIR}/alicia.conf" 2>/dev/null || true
        local cfg_val

        cfg_val=$(alicia_get_config_value "vnc.resolution" "") 2>/dev/null || true
        [[ -n "${cfg_val}" && -z "${CUSTOM_RESOLUTION}" ]] && VNC_RESOLUTION="${cfg_val}"

        cfg_val=$(alicia_get_config_value "vnc.port" "") 2>/dev/null || true
        [[ -n "${cfg_val}" && -z "${CUSTOM_PORT}" ]] && VNC_PORT="${cfg_val}"

        cfg_val=$(alicia_get_config_value "vnc.password" "") 2>/dev/null || true
        [[ -n "${cfg_val}" ]] && VNC_PASSWORD="${cfg_val}"

        cfg_val=$(alicia_get_config_value "desktop.environment" "") 2>/dev/null || true
        [[ -n "${cfg_val}" ]] && DESKTOP_ENV="${cfg_val}"

        cfg_val=$(alicia_get_config_value "proot.distro" "") 2>/dev/null || true
        [[ -n "${cfg_val}" ]] && PROOT_DISTRO="${cfg_val}"
    fi

    # Export for proot session
    export ALICIA_VNC_PORT="${VNC_PORT}"
    export ALICIA_VNC_RESOLUTION="${VNC_RESOLUTION}"
    export ALICIA_VNC_DEPTH="${VNC_DEPTH}"
    export ALICIA_VNC_PASSWORD="${VNC_PASSWORD}"
    export ALICIA_DESKTOP_ENV="${DESKTOP_ENV}"
    export ALICIA_DISTRO_NAME="${PROOT_DISTRO}"
    export ALICIA_DISPLAY=":${DISPLAY_NUM}"

    log_info "Configuration: Resolution=${VNC_RESOLUTION}, Port=${VNC_PORT}, DE=${DESKTOP_ENV}"
    return 0
}

# ============================================================================
# Service Startup Functions
# ============================================================================

# Start the proot session
start_proot() {
    log_subsection "Starting proot session"

    if proot_is_running 2>/dev/null; then
        log_info "proot session is already running"
        return 0
    fi

    if ! proot_start "${PROOT_DISTRO}"; then
        log_error "Failed to start proot session"
        return 1
    fi

    log_info "proot session started for '${PROOT_DISTRO}'"
    return 0
}

# Start the VNC server
start_vnc() {
    log_subsection "Starting VNC server"

    if vnc_is_running 2>/dev/null; then
        log_info "VNC server is already running"
        return 0
    fi

    if ! vnc_start "${VNC_PORT}" "${VNC_RESOLUTION}" "${VNC_DEPTH}" "${VNC_PASSWORD}"; then
        log_error "Failed to start VNC server"
        return 1
    fi

    log_info "VNC server started on port ${VNC_PORT}"
    return 0
}

# Start the desktop environment
start_desktop() {
    log_subsection "Starting desktop environment"

    if de_is_running 2>/dev/null; then
        log_info "Desktop environment is already running"
        return 0
    fi

    if ! de_start "${DESKTOP_ENV}"; then
        log_error "Failed to start desktop environment: ${DESKTOP_ENV}"
        return 1
    fi

    log_info "Desktop environment '${DESKTOP_ENV}' started"
    return 0
}

# ============================================================================
# Health Check with Retries
# ============================================================================

# Check if VNC is accepting connections
check_vnc_health() {
    local retries=0
    local max_retries=15
    local wait_interval=2

    log_info "Performing VNC health check (max ${max_retries} retries)..."

    while [[ ${retries} -lt ${max_retries} ]]; do
        if vnc_is_running 2>/dev/null; then
            # Try a TCP connection to the VNC port
            if (echo >/dev/tcp/localhost/"${VNC_PORT}") 2>/dev/null; then
                log_info "VNC health check PASSED (port ${VNC_PORT} accepting connections)"
                return 0
            fi
        fi

        ((retries++)) || true
        if [[ "${QUIET_MODE}" != "true" ]]; then
            printf "${COLOR_YELLOW}  Waiting for VNC... (%d/%d)${COLOR_RESET}\n" "${retries}" "${max_retries}"
        fi
        sleep "${wait_interval}"
    done

    log_error "VNC health check FAILED after ${max_retries} attempts"
    return 1
}

# Check if proot session is healthy
check_proot_health() {
    local retries=0
    local max_retries=10
    local wait_interval=1

    log_info "Performing proot health check..."

    while [[ ${retries} -lt ${max_retries} ]]; do
        if proot_is_running 2>/dev/null; then
            log_info "proot health check PASSED"
            return 0
        fi

        ((retries++)) || true
        sleep "${wait_interval}"
    done

    log_error "proot health check FAILED"
    return 1
}

# Check if the desktop environment is healthy
check_desktop_health() {
    local retries=0
    local max_retries=20
    local wait_interval=2

    log_info "Performing desktop environment health check..."

    while [[ ${retries} -lt ${max_retries} ]]; do
        if de_is_running 2>/dev/null; then
            log_info "Desktop environment health check PASSED"
            return 0
        fi

        ((retries++)) || true
        if [[ "${QUIET_MODE}" != "true" ]]; then
            printf "${COLOR_YELLOW}  Waiting for desktop... (%d/%d)${COLOR_RESET}\n" "${retries}" "${max_retries}"
        fi
        sleep "${wait_interval}"
    done

    log_warn "Desktop environment health check: not confirmed (may still be starting)"
    return 0  # Non-fatal -- desktop can be slow to start
}

# Run all health checks
run_health_checks() {
    log_section "Health Checks"

    if ! check_proot_health; then
        return 1
    fi

    if ! check_vnc_health; then
        return 1
    fi

    check_desktop_health || true

    log_info "All critical health checks passed"
    return 0
}

# ============================================================================
# Display Connection Information
# ============================================================================
show_connection_info() {
    local local_ip
    local_ip=$(network_get_local_ip 2>/dev/null || echo "127.0.0.1")

    echo ""
    log_separator "=" 50
    printf "${COLOR_BOLD_GREEN}%s${COLOR_RESET}\n" "  Alicia Desktop Environment is RUNNING"
    log_separator "=" 50
    echo ""
    printf "${COLOR_BOLD_WHITE}  Connection Information:${COLOR_RESET}\n"
    echo ""
    printf "  ${COLOR_CYAN}VNC:${COLOR_RESET}\n"
    printf "    Address:    ${COLOR_BOLD_WHITE}%s:%s${COLOR_RESET}\n" "${local_ip}" "${VNC_PORT}"
    printf "    Port:       %s\n" "${VNC_PORT}"
    printf "    Resolution: %s\n" "${VNC_RESOLUTION}"
    printf "    Password:   %s\n" "${VNC_PASSWORD}"
    printf "    Display:    %s\n" "${ALICIA_DISPLAY}"
    echo ""
    printf "  ${COLOR_CYAN}System:${COLOR_RESET}\n"
    printf "    Desktop:    %s\n" "${DESKTOP_ENV}"
    printf "    Distro:     %s\n" "${PROOT_DISTRO}"
    printf "    PID:        %s\n" "$$"
    printf "    Version:    %s\n" "$(alicia_get_version)"
    echo ""

    if [[ "${local_ip}" != "127.0.0.1" ]]; then
        printf "  ${COLOR_CYAN}VNC Client URL:${COLOR_RESET}\n"
        printf "    ${COLOR_BOLD_WHITE}vnc://%s:%s${COLOR_RESET}\n" "${local_ip}" "${VNC_PORT}"
        echo ""
    fi

    printf "  ${COLOR_DIM}Connect with any VNC client (e.g., RealVNC Viewer, TigerVNC)${COLOR_RESET}\n"
    printf "  ${COLOR_DIM}For noVNC (browser): http://%s:6080/vnc.html${COLOR_RESET}\n" "${local_ip}"
    echo ""
    log_separator "=" 50
}

# ============================================================================
# PID File and State Management
# ============================================================================
create_pid_file() {
    log_info "Creating PID file: ${STARTUP_PID_FILE}"
    echo "$$" > "${STARTUP_PID_FILE}"
    chmod 600 "${STARTUP_PID_FILE}"
}

set_running_state() {
    alicia_set_state "alicia_running" "true"
    alicia_set_state "alicia_pid" "$$"
    alicia_set_state "alicia_started" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    alicia_set_state "vnc_port" "${VNC_PORT}"
    alicia_set_state "vnc_resolution" "${VNC_RESOLUTION}"
    alicia_set_state "desktop_env" "${DESKTOP_ENV}"
    alicia_set_state "proot_distro" "${PROOT_DISTRO}"
    log_info "State updated: Alicia is running"
}

# ============================================================================
# Cleanup on Failure
# ============================================================================
cleanup_on_failure() {
    if [[ "${STARTUP_FAILED}" != "true" ]]; then
        return 0
    fi

    log_error "Startup failed -- performing cleanup..."

    # Stop services in reverse order
    de_stop 2>/dev/null || true
    vnc_stop 2>/dev/null || true
    proot_stop 2>/dev/null || true

    # Remove PID file and state
    rm -f "${STARTUP_PID_FILE}" 2>/dev/null || true
    alicia_set_state "alicia_running" "false" 2>/dev/null || true
    alicia_lock_release "alicia-startup" 2>/dev/null || true

    log_error "Cleanup complete. Check logs at: ${ALICIA_LOG_DIR}/start.log"
}

# ============================================================================
# Signal Handler
# ============================================================================
handle_signal() {
    local sig="$1"
    log_warn "Received SIG${sig} during startup -- aborting..."
    STARTUP_FAILED=true
    cleanup_on_failure
    exit $((128 + $(kill -l "${sig}" 2>/dev/null || echo 1)))
}

trap 'handle_signal INT' INT
trap 'handle_signal TERM' TERM
trap 'handle_signal HUP' HUP

# ============================================================================
# Main Entry Point
# ============================================================================
main() {
    parse_args "$@"

    # Show banner (unless quiet)
    if [[ "${QUIET_MODE}" != "true" ]]; then
        show_banner
    fi

    log_section "Alicia Desktop Environment Startup"
    log_info "Starting Alicia v$(alicia_get_version)..."
    log_timer_start "startup"

    # Step 1: Check if already running
    if ! check_already_running; then
        exit 1
    fi

    # Step 2: Acquire startup lock
    if ! alicia_lock_acquire "alicia-startup" 30; then
        log_error "Could not acquire startup lock"
        exit 1
    fi

    # Step 3: Validate environment
    if ! validate_environment; then
        STARTUP_FAILED=true
        cleanup_on_failure
        exit 1
    fi

    # Step 4: Apply configuration overrides
    if ! apply_overrides; then
        STARTUP_FAILED=true
        cleanup_on_failure
        exit 1
    fi

    # Step 5: Start proot session
    if ! start_proot; then
        STARTUP_FAILED=true
        cleanup_on_failure
        exit 1
    fi

    # Step 6: Start VNC server
    if ! start_vnc; then
        STARTUP_FAILED=true
        cleanup_on_failure
        exit 1
    fi

    # Step 7: Start desktop environment
    if ! start_desktop; then
        STARTUP_FAILED=true
        cleanup_on_failure
        exit 1
    fi

    # Step 8: Health checks
    if ! run_health_checks; then
        STARTUP_FAILED=true
        cleanup_on_failure
        exit 1
    fi

    # Step 9: Create PID file and set state
    create_pid_file
    set_running_state

    # Step 10: Release startup lock
    alicia_lock_release "alicia-startup"

    # Step 11: Display connection info
    show_connection_info

    log_timer_end "startup"
    log_info "Alicia Desktop Environment started successfully"
    log_info "Logs: ${ALICIA_LOG_DIR}/start.log"

    return 0
}

# ============================================================================
# Execute Main
# ============================================================================
main "$@"
