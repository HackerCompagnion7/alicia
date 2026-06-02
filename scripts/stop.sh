#!/bin/bash
# ============================================================================
# stop.sh - Alicia Desktop Environment Stop Script
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
# Description:  Main stop script for the Alicia Desktop Environment.
#               Gracefully stops desktop, VNC, and proot, then cleans up
#               all state, PID files, and temporary resources.
# Usage:        stop.sh [--force] [--clean]
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
        source "${lib_file}" 2>/dev/null || {
            echo "ERROR: Failed to source library: ${lib_file}" >&2
            exit 1
        }
    fi
done

if ! declare -f alicia_init_directories &>/dev/null; then
    echo "ERROR: Failed to load alicia core libraries" >&2
    exit 1
fi

# ============================================================================
# Initialize
# ============================================================================
alicia_init_directories || true
log_init "${ALICIA_LOG_DIR}" "${ALICIA_LOG_DIR}/stop.log"
log_set_module "stop"

# ============================================================================
# Script-Level Variables
# ============================================================================
FORCE_STOP=false
CLEAN_MODE=false
PID_FILE="${ALICIA_STATE_DIR}/alicia.pid"
SHUTDOWN_TIMEOUT=30

# ============================================================================
# Parse Command-Line Arguments
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                FORCE_STOP=true
                shift
                ;;
            --clean|-c)
                CLEAN_MODE=true
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
    echo "Usage: stop.sh [OPTIONS]"
    echo ""
    echo "Stop the Alicia Desktop Environment."
    echo ""
    echo "Options:"
    echo "  --force, -f    Force immediate kill (no graceful shutdown)"
    echo "  --clean, -c    Also clean cache and temporary files"
    echo "  --help, -h     Show this help message"
}

# ============================================================================
# Check If Running
# ============================================================================
check_if_running() {
    log_info "Checking if Alicia is running..."

    # Check PID file
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid=$(cat "${PID_FILE}" 2>/dev/null || echo "")
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            log_info "Alicia is running (PID: ${pid})"
            return 0
        else
            log_warn "Stale PID file found (PID: ${pid:-empty}) -- cleaning up"
            rm -f "${PID_FILE}" 2>/dev/null || true
        fi
    fi

    # Check state
    local running_state
    running_state=$(alicia_get_state "alicia_running" 2>/dev/null || echo "")
    if [[ "${running_state}" == "true" ]]; then
        log_warn "State indicates running but no valid PID found"
        return 0
    fi

    # Check for actual processes as a last resort
    if pgrep -f "Xvnc" &>/dev/null || pgrep -f "xfce4-session" &>/dev/null || pgrep -f "Xvfb" &>/dev/null; then
        log_warn "Alicia-related processes found despite no PID file"
        return 0
    fi

    if [[ "${FORCE_STOP}" == "true" ]]; then
        log_info "Force mode -- proceeding even though Alicia does not appear to be running"
        return 0
    fi

    log_info "Alicia does not appear to be running"
    return 1
}

# ============================================================================
# Graceful Stop Functions
# ============================================================================

# Stop the desktop environment
stop_desktop() {
    log_subsection "Stopping desktop environment"

    if ! de_is_running 2>/dev/null; then
        log_info "Desktop environment is not running"
        return 0
    fi

    if [[ "${FORCE_STOP}" == "true" ]]; then
        log_info "Force-stopping desktop environment..."
        proot_exec "${ALICIA_DISTRO_NAME:-debian}" \
            "pkill -9 -f 'xfce4-session\|fluxbox\|lxsession' 2>/dev/null || true" 2>/dev/null || true
    else
        log_info "Gracefully stopping desktop environment..."
        de_stop 2>/dev/null || {
            log_warn "Graceful desktop stop failed -- forcing..."
            proot_exec "${ALICIA_DISTRO_NAME:-debian}" \
                "pkill -f 'xfce4-session\|fluxbox\|lxsession' 2>/dev/null || true" 2>/dev/null || true
        }
    fi

    # Wait for processes to exit
    local retries=0
    while de_is_running 2>/dev/null && [[ ${retries} -lt 10 ]]; do
        sleep 1
        ((retries++)) || true
    done

    if de_is_running 2>/dev/null; then
        log_warn "Desktop environment did not stop cleanly -- killing remaining processes"
        proot_exec "${ALICIA_DISTRO_NAME:-debian}" \
            "pkill -9 -f 'xfce4-session\|fluxbox\|lxsession' 2>/dev/null || true" 2>/dev/null || true
    fi

    log_info "Desktop environment stopped"
    return 0
}

# Stop the VNC server
stop_vnc() {
    log_subsection "Stopping VNC server"

    if ! vnc_is_running 2>/dev/null; then
        log_info "VNC server is not running"
        return 0
    fi

    if [[ "${FORCE_STOP}" == "true" ]]; then
        log_info "Force-stopping VNC server..."
        proot_exec "${ALICIA_DISTRO_NAME:-debian}" \
            "pkill -9 Xvnc 2>/dev/null; pkill -9 Xvfb 2>/dev/null; pkill -9 x11vnc 2>/dev/null" 2>/dev/null || true
    else
        log_info "Gracefully stopping VNC server..."
        vnc_stop 2>/dev/null || {
            log_warn "Graceful VNC stop failed -- forcing..."
            proot_exec "${ALICIA_DISTRO_NAME:-debian}" \
                "pkill -9 Xvnc 2>/dev/null; pkill -9 Xvfb 2>/dev/null" 2>/dev/null || true
        }
    fi

    # Wait for VNC to fully stop
    local retries=0
    while vnc_is_running 2>/dev/null && [[ ${retries} -lt 10 ]]; do
        sleep 1
        ((retries++)) || true
    done

    if vnc_is_running 2>/dev/null; then
        log_warn "VNC server did not stop cleanly"
        # Nuclear option -- kill at Termux level
        pkill -9 -f "Xvnc" 2>/dev/null || true
        pkill -9 -f "Xvfb" 2>/dev/null || true
    fi

    log_info "VNC server stopped"
    return 0
}

# Stop the proot session
stop_proot() {
    log_subsection "Stopping proot session"

    if ! proot_is_running 2>/dev/null; then
        log_info "proot session is not running"
        return 0
    fi

    if [[ "${FORCE_STOP}" == "true" ]]; then
        log_info "Force-stopping proot session..."
        local proot_pid
        proot_pid=$(alicia_get_state "PROOT_PID" 2>/dev/null || echo "")
        if [[ -n "${proot_pid}" ]] && kill -0 "${proot_pid}" 2>/dev/null; then
            kill -9 "${proot_pid}" 2>/dev/null || true
        fi
        # Also kill any proot-distro login processes
        pkill -9 -f "proot-distro login" 2>/dev/null || true
    else
        log_info "Gracefully stopping proot session..."
        proot_stop 2>/dev/null || {
            log_warn "Graceful proot stop failed -- forcing..."
            pkill -f "proot-distro login" 2>/dev/null || true
        }
    fi

    # Wait for proot to fully exit
    local retries=0
    while proot_is_running 2>/dev/null && [[ ${retries} -lt ${SHUTDOWN_TIMEOUT} ]]; do
        sleep 1
        ((retries++)) || true
    done

    if proot_is_running 2>/dev/null; then
        log_warn "proot session did not stop cleanly -- killing remaining processes"
        pkill -9 -f "proot-distro" 2>/dev/null || true
    fi

    log_info "proot session stopped"
    return 0
}

# ============================================================================
# Kill Remaining Processes
# ============================================================================
kill_remaining_processes() {
    log_info "Checking for remaining Alicia-related processes..."

    local processes=(
        "Xvnc"
        "Xvfb"
        "x11vnc"
        "xfce4-session"
        "fluxbox"
        "lxsession"
        "dbus-daemon"
        "pulseaudio"
        "xfce4-panel"
        "xfwm4"
        "Thunar"
        "xfdesktop"
    )

    local killed=0
    for proc in "${processes[@]}"; do
        if pgrep -f "${proc}" &>/dev/null; then
            log_info "  Killing remaining process: ${proc}"
            pkill -9 -f "${proc}" 2>/dev/null || true
            ((killed++)) || true
        fi
    done

    if [[ ${killed} -gt 0 ]]; then
        log_info "Killed ${killed} remaining process(es)"
    else
        log_info "No remaining processes found"
    fi
}

# ============================================================================
# Cleanup Functions
# ============================================================================

# Clean PID files
clean_pid_files() {
    log_info "Cleaning PID files..."

    rm -f "${PID_FILE}" 2>/dev/null || true
    rm -f "${ALICIA_STATE_DIR}/proot.pid" 2>/dev/null || true
    rm -f "${ALICIA_STATE_DIR}/vnc.pid" 2>/dev/null || true
    rm -f "${ALICIA_STATE_DIR}/xvfb.pid" 2>/dev/null || true
    rm -f "${ALICIA_STATE_DIR}/desktop.pid" 2>/dev/null || true

    log_info "PID files cleaned"
}

# Clean lock files
clean_lock_files() {
    log_info "Cleaning lock files..."

    rm -f "${ALICIA_LOCK_DIR}/alicia-startup.lock" 2>/dev/null || true
    rm -f "${ALICIA_LOCK_DIR}/alicia-stop.lock" 2>/dev/null || true
    rm -f "${ALICIA_LOCK_DIR}/alicia-update.lock" 2>/dev/null || true

    log_info "Lock files cleaned"
}

# Clean temporary files
clean_temp_files() {
    log_info "Cleaning temporary files..."
    temp_cleanup 0 2>/dev/null || true

    # Clean VNC temp files
    rm -f "${ALICIA_TMP_DIR}"/.X*-lock 2>/dev/null || true
    rm -f "${ALICIA_TMP_DIR}"/.X11-unix 2>/dev/null || true

    log_info "Temporary files cleaned"
}

# Clean cache (if --clean flag)
clean_cache() {
    if [[ "${CLEAN_MODE}" != "true" ]]; then
        return 0
    fi

    log_section "Cache Cleanup"
    log_info "Cleaning cache files..."

    cache_clear 2>/dev/null || true

    # Clean package manager caches inside proot
    proot_exec "${ALICIA_DISTRO_NAME:-debian}" \
        "apk cache purge 2>/dev/null; apt-get clean 2>/dev/null; dnf clean all 2>/dev/null" \
        2>/dev/null || true

    log_info "Cache cleanup complete"
}

# Reset state
reset_state() {
    log_info "Resetting Alicia state..."

    alicia_set_state "alicia_running" "false"
    alicia_set_state "alicia_pid" ""
    alicia_set_state "alicia_stopped" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    alicia_set_state "PROOT_PID" "0"
    alicia_set_state "VNC_RUNNING" "false"
    alicia_set_state "XVFB_RUNNING" "false"
    alicia_set_state "DE_RUNNING" "false"

    log_info "State reset complete"
}

# ============================================================================
# Main Entry Point
# ============================================================================
main() {
    parse_args "$@"

    log_section "Alicia Desktop Environment Shutdown"
    log_info "Initiating stop sequence..."
    log_timer_start "shutdown"

    # Check if running
    if ! check_if_running; then
        if [[ "${FORCE_STOP}" != "true" ]]; then
            log_info "Nothing to stop -- Alicia is not running"
            # Still do cleanup
            clean_pid_files
            clean_lock_files
            reset_state
            return 0
        fi
    fi

    # Stop services in reverse order of startup
    stop_desktop
    stop_vnc
    stop_proot

    # Kill any remaining processes
    kill_remaining_processes

    # Cleanup
    clean_pid_files
    clean_lock_files
    clean_temp_files
    clean_cache
    reset_state

    log_timer_end "shutdown"
    log_info "Alicia Desktop Environment stopped successfully"

    printf "\n${COLOR_BOLD_GREEN}  Alicia Desktop Environment has been stopped.${COLOR_RESET}\n\n"

    return 0
}

# ============================================================================
# Execute Main
# ============================================================================
main "$@"
