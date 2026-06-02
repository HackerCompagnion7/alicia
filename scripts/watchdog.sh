#!/bin/bash
# ============================================================================
# watchdog.sh - Alicia Desktop Environment Watchdog/Recovery Daemon
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
# Version:      2.0.0
# Description:  Watchdog daemon for the Alicia Desktop Environment. Monitors
#               VNC, proot, Xvfb, and desktop processes, auto-restarts crashed
#               services, detects memory leaks and disk issues, and provides
#               configurable health checks with alert notifications.
# Usage:        watchdog.sh [--daemonize] [--oneshot] [--interval SECS]
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
log_init "${ALICIA_LOG_DIR}" "${ALICIA_LOG_DIR}/watchdog.log" 2>/dev/null || true
log_set_module "watchdog"

# ============================================================================
# Configuration Defaults
# ============================================================================
DAEMONIZE=false
ONESHOT=false
CHECK_INTERVAL=30           # seconds between checks
MEMORY_THRESHOLD=85         # percent - restart if exceeded
DISK_THRESHOLD=90           # percent - alert if exceeded
LOG_SIZE_THRESHOLD=50       # MB - rotate if exceeded
ZOMBIE_CHECK=true
MAX_RESTART_ATTEMPTS=3      # per service, per cycle
RESTART_BACKOFF=60          # seconds between restart attempts for same service
WATCHDOG_PID_FILE="${ALICIA_STATE_DIR}/watchdog.pid"
WATCHDOG_STATE_FILE="${ALICIA_STATE_DIR}/watchdog.state"

# Track restart attempts per service
declare -gA _RESTART_ATTEMPTS=()
declare -gA _LAST_RESTART_TIME=()

# ============================================================================
# Parse Arguments
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --daemonize|-d)
                DAEMONIZE=true
                shift
                ;;
            --oneshot|-o)
                ONESHOT=true
                shift
                ;;
            --interval|-i)
                if [[ -z "${2:-}" ]]; then
                    log_error "--interval requires a value in seconds"
                    exit 1
                fi
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            --memory-threshold)
                MEMORY_THRESHOLD="${2:-85}"
                shift 2
                ;;
            --disk-threshold)
                DISK_THRESHOLD="${2:-90}"
                shift 2
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
    echo "Usage: watchdog.sh [OPTIONS]"
    echo ""
    echo "Monitor and auto-recover Alicia Desktop Environment services."
    echo ""
    echo "Options:"
    echo "  --daemonize,        -d   Run as background daemon"
    echo "  --oneshot,          -o   Run a single check and exit"
    echo "  --interval,         -i   Check interval in seconds (default: 30)"
    echo "  --memory-threshold N     Memory usage % to trigger restart (default: 85)"
    echo "  --disk-threshold N       Disk usage % to trigger alert (default: 90)"
    echo "  --help,             -h   Show this help"
    echo ""
    echo "Examples:"
    echo "  watchdog.sh --oneshot              Single health check"
    echo "  watchdog.sh --daemonize            Run as daemon with defaults"
    echo "  watchdog.sh -d -i 60               Daemon with 60s interval"
}

# ============================================================================
# Watchdog State Persistence
# ============================================================================
save_watchdog_state() {
    local state_file="${WATCHDOG_STATE_FILE}"
    cat > "${state_file}" <<STATE
pid=$$
started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
interval=${CHECK_INTERVAL}
memory_threshold=${MEMORY_THRESHOLD}
disk_threshold=${DISK_THRESHOLD}
checks_performed=0
last_check=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
STATE
}

update_check_count() {
    local state_file="${WATCHDOG_STATE_FILE}"
    if [[ -f "${state_file}" ]]; then
        local current
        current=$(grep '^checks_performed=' "${state_file}" | cut -d= -f2 || echo 0)
        local new_count=$((current + 1))
        sed -i "s/^checks_performed=.*/checks_performed=${new_count}/" "${state_file}" 2>/dev/null || true
        sed -i "s/^last_check=.*/last_check=$(date -u '+%Y-%m-%dT%H:%M:%SZ')/" "${state_file}" 2>/dev/null || true
    fi
}

# ============================================================================
# Health Check Functions
# ============================================================================

# Check VNC server
check_vnc() {
    local service="vnc"
    log_debug "Checking VNC server..."

    if vnc_is_running 2>/dev/null; then
        # Verify VNC is accepting connections
        local port
        port=$(alicia_get_state "vnc_port" 2>/dev/null || echo "${ALICIA_DEFAULT_VNC_PORT}")
        if (echo >/dev/tcp/localhost/"${port}") 2>/dev/null; then
            log_debug "VNC health: OK (port ${port} accepting connections)"
            return 0
        else
            log_warn "VNC process running but not accepting connections on port ${port}"
            return 1
        fi
    else
        log_warn "VNC server is not running"
        return 1
    fi
}

# Check proot session
check_proot() {
    log_debug "Checking proot session..."

    if proot_is_running 2>/dev/null; then
        log_debug "proot health: OK"
        return 0
    else
        log_warn "proot session is not running"
        return 1
    fi
}

# Check desktop environment
check_desktop() {
    log_debug "Checking desktop environment..."

    if de_is_running 2>/dev/null; then
        log_debug "Desktop health: OK"
        return 0
    else
        log_warn "Desktop environment is not running"
        return 1
    fi
}

# Check Xvfb
check_xvfb() {
    log_debug "Checking Xvfb..."

    if xvfb_is_running 2>/dev/null; then
        log_debug "Xvfb health: OK"
        return 0
    else
        log_warn "Xvfb is not running"
        return 1
    fi
}

# Check memory usage
check_memory() {
    log_debug "Checking memory usage..."

    local mem_info mem_total mem_used mem_pct
    mem_info=$(free 2>/dev/null | grep "^Mem:" || echo "")
    if [[ -z "${mem_info}" ]]; then
        log_debug "Cannot read memory info"
        return 0
    fi

    mem_total=$(echo "${mem_info}" | awk '{print $2}')
    mem_used=$(echo "${mem_info}" | awk '{print $3}')

    if [[ ${mem_total} -gt 0 ]]; then
        mem_pct=$((mem_used * 100 / mem_total))
    else
        mem_pct=0
    fi

    if [[ ${mem_pct} -ge ${MEMORY_THRESHOLD} ]]; then
        log_warn "High memory usage: ${mem_pct}% (threshold: ${MEMORY_THRESHOLD}%)"
        return 1
    fi

    log_debug "Memory usage: ${mem_pct}% (OK)"
    return 0
}

# Check disk space
check_disk() {
    log_debug "Checking disk space..."

    local disk_pct
    disk_pct=$(df "${ALICIA_HOME}" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo 0)

    if [[ ${disk_pct} -ge ${DISK_THRESHOLD} ]]; then
        log_warn "High disk usage: ${disk_pct}% (threshold: ${DISK_THRESHOLD}%)"
        send_alert "Low Disk Space" "Disk usage is at ${disk_pct}%. Consider running backup.sh delete or storage_optimize."
        return 1
    fi

    log_debug "Disk usage: ${disk_pct}% (OK)"
    return 0
}

# Check for zombie processes
check_zombies() {
    if [[ "${ZOMBIE_CHECK}" != "true" ]]; then
        return 0
    fi

    log_debug "Checking for zombie processes..."

    local zombie_count
    zombie_count=$(ps aux 2>/dev/null | awk '{if($8=="Z") print}' | wc -l || echo 0)

    if [[ ${zombie_count} -gt 5 ]]; then
        log_warn "Detected ${zombie_count} zombie processes"
        return 1
    fi

    log_debug "Zombie processes: ${zombie_count} (OK)"
    return 0
}

# Check log file sizes
check_log_sizes() {
    log_debug "Checking log file sizes..."

    if [[ ! -d "${ALICIA_LOG_DIR}" ]]; then
        return 0
    fi

    local oversized=0
    while IFS= read -r -d '' logfile; do
        local size_mb
        size_mb=$(du -m "${logfile}" 2>/dev/null | cut -f1 || echo 0)
        if [[ ${size_mb} -gt ${LOG_SIZE_THRESHOLD} ]]; then
            log_warn "Log file oversized: $(basename "${logfile}") (${size_mb}MB)"
            # Truncate the oversized log
            : > "${logfile}" 2>/dev/null || true
            log_info "Truncated oversized log: $(basename "${logfile}")"
            ((oversized++)) || true
        fi
    done < <(find "${ALICIA_LOG_DIR}" -name "*.log" -type f -print0 2>/dev/null)

    if [[ ${oversized} -gt 0 ]]; then
        return 1
    fi

    return 0
}

# ============================================================================
# Recovery Functions
# ============================================================================

# Determine if a restart attempt is allowed (respects backoff)
can_restart() {
    local service="$1"
    local now
    now=$(date +%s)

    # Check if we've exceeded max attempts
    local attempts=${_RESTART_ATTEMPTS[${service}]:-0}
    if [[ ${attempts} -ge ${MAX_RESTART_ATTEMPTS} ]]; then
        log_warn "Max restart attempts (${MAX_RESTART_ATTEMPTS}) reached for ${service}"
        return 1
    fi

    # Check backoff
    local last_restart=${_LAST_RESTART_TIME[${service}]:-0}
    local elapsed=$((now - last_restart))
    if [[ ${elapsed} -lt ${RESTART_BACKOFF} ]]; then
        log_debug "Restart backoff for ${service}: ${elapsed}s < ${RESTART_BACKOFF}s"
        return 1
    fi

    return 0
}

# Record a restart attempt
record_restart() {
    local service="$1"
    local attempts=${_RESTART_ATTEMPTS[${service}]:-0}
    _RESTART_ATTEMPTS[${service}]=$((attempts + 1))
    _LAST_RESTART_TIME[${service}]="$(date +%s)"
}

# Reset restart counters (called periodically)
reset_restart_counters() {
    _RESTART_ATTEMPTS=()
    log_debug "Restart attempt counters reset"
}

# Restart VNC server
restart_vnc() {
    log_info "Attempting VNC server restart..."
    if can_restart "vnc"; then
        record_restart "vnc"
        vnc_restart 2>/dev/null || {
            log_error "VNC restart failed"
            return 1
        }
        # Verify restart
        sleep 3
        if vnc_is_running 2>/dev/null; then
            log_info "VNC server restarted successfully"
            send_alert "VNC Recovered" "VNC server was restarted by the watchdog."
            return 0
        else
            log_error "VNC server failed to restart"
            return 1
        fi
    fi
    return 1
}

# Restart proot session
restart_proot() {
    log_info "Attempting proot session restart..."
    if can_restart "proot"; then
        record_restart "proot"
        # Need to stop everything first since proot is foundational
        de_stop 2>/dev/null || true
        vnc_stop 2>/dev/null || true
        proot_stop 2>/dev/null || true
        sleep 2

        proot_start "${ALICIA_DISTRO_NAME:-debian}" 2>/dev/null || {
            log_error "proot restart failed"
            return 1
        }

        # Restart dependent services
        sleep 2
        vnc_start 2>/dev/null || true
        sleep 2
        de_start 2>/dev/null || true

        if proot_is_running 2>/dev/null; then
            log_info "proot session restarted successfully"
            send_alert "proot Recovered" "proot session was restarted by the watchdog."
            return 0
        else
            log_error "proot session failed to restart"
            return 1
        fi
    fi
    return 1
}

# Restart desktop environment
restart_desktop() {
    log_info "Attempting desktop environment restart..."
    if can_restart "desktop"; then
        record_restart "desktop"
        de_stop 2>/dev/null || true
        sleep 2
        de_start "${ALICIA_DESKTOP_ENV:-xfce4}" 2>/dev/null || {
            log_error "Desktop restart failed"
            return 1
        }

        if de_is_running 2>/dev/null; then
            log_info "Desktop environment restarted successfully"
            send_alert "Desktop Recovered" "Desktop environment was restarted by the watchdog."
            return 0
        else
            log_error "Desktop environment failed to restart"
            return 1
        fi
    fi
    return 1
}

# Restart Xvfb
restart_xvfb() {
    log_info "Attempting Xvfb restart..."
    if can_restart "xvfb"; then
        record_restart "xvfb"
        xvfb_stop 2>/dev/null || true
        sleep 1
        xvfb_start 2>/dev/null || {
            log_error "Xvfb restart failed"
            return 1
        }
        log_info "Xvfb restarted"
        return 0
    fi
    return 1
}

# Full clean restart
full_clean_restart() {
    log_warn "Performing full clean restart..."
    send_alert "Full Restart" "Watchdog is performing a full clean restart of Alicia."

    if [[ -x "${SCRIPT_DIR}/stop.sh" ]]; then
        bash "${SCRIPT_DIR}/stop.sh" --force --clean 2>/dev/null || true
    fi

    sleep 5

    if [[ -x "${SCRIPT_DIR}/start.sh" ]]; then
        bash "${SCRIPT_DIR}/start.sh" 2>/dev/null || {
            log_error "Full clean restart failed"
            return 1
        }
    fi

    log_info "Full clean restart completed"
}

# Memory recovery
recover_memory() {
    log_info "Performing memory recovery..."
    memory_optimize 2>/dev/null || true

    # If memory is still critical, restart services
    local mem_pct
    mem_pct=$(free 2>/dev/null | grep "^Mem:" | awk '{printf "%.0f", $3*100/$2}' || echo 0)

    if [[ ${mem_pct} -ge ${MEMORY_THRESHOLD} ]]; then
        log_warn "Memory still critical (${mem_pct}%) after optimization -- restarting services"
        # Restart the heaviest service first (desktop)
        restart_desktop 2>/dev/null || true
    fi
}

# ============================================================================
# Alert Notifications
# ============================================================================
send_alert() {
    local title="$1"
    local message="$2"

    log_warn "ALERT: ${title} -- ${message}"

    # Desktop notification (if DE is running)
    if de_is_running 2>/dev/null && declare -f ui_notify &>/dev/null; then
        ui_notify "${title}" "${message}" "critical" 10000 2>/dev/null || true
    fi

    # Write alert to file
    local alert_file="${ALICIA_LOG_DIR}/alerts.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ALERT] ${title}: ${message}" >> "${alert_file}" 2>/dev/null || true

    return 0
}

# ============================================================================
# Single Health Check Cycle
# ============================================================================
run_check_cycle() {
    local issues=0
    local recoveries=0

    # Only run checks if Alicia is supposed to be running
    local running_state
    running_state=$(alicia_get_state "alicia_running" 2>/dev/null || echo "")
    if [[ "${running_state}" != "true" ]]; then
        log_debug "Alicia is not in running state -- skipping checks"
        return 0
    fi

    log_debug "Starting check cycle..."

    # 1. Check proot (foundational -- check first)
    if ! check_proot; then
        ((issues++)) || true
        if restart_proot; then
            ((recoveries++)) || true
        fi
    fi

    # 2. Check VNC
    if ! check_vnc; then
        ((issues++)) || true
        if restart_vnc; then
            ((recoveries++)) || true
        fi
    fi

    # 3. Check Xvfb
    if ! check_xvfb; then
        ((issues++)) || true
        if restart_xvfb; then
            ((recoveries++)) || true
        fi
    fi

    # 4. Check desktop
    if ! check_desktop; then
        ((issues++)) || true
        if restart_desktop; then
            ((recoveries++)) || true
        fi
    fi

    # 5. Check memory
    if ! check_memory; then
        ((issues++)) || true
        recover_memory || true
    fi

    # 6. Check disk
    if ! check_disk; then
        ((issues++)) || true
        # Disk recovery: try to free space
        storage_optimize 2>/dev/null || true
    fi

    # 7. Check zombies
    check_zombies || ((issues++)) || true

    # 8. Check log sizes
    check_log_sizes || true

    # Summary
    if [[ ${issues} -eq 0 ]]; then
        log_debug "All health checks passed"
    else
        log_info "Check cycle: ${issues} issue(s) detected, ${recoveries} recovery/recoveries performed"
    fi

    update_check_count
    return 0
}

# ============================================================================
# Daemon Mode
# ============================================================================
run_daemon() {
    log_section "Alicia Watchdog Daemon"
    log_info "Starting watchdog daemon (interval: ${CHECK_INTERVAL}s)"
    log_info "Memory threshold: ${MEMORY_THRESHOLD}%, Disk threshold: ${DISK_THRESHOLD}%"

    # Write PID file
    echo "$$" > "${WATCHDOG_PID_FILE}"

    # Save initial state
    save_watchdog_state

    # Setup signal handlers for daemon
    trap 'log_info "Watchdog received SIGTERM -- shutting down"; rm -f "${WATCHDOG_PID_FILE}"; exit 0' TERM
    trap 'log_info "Watchdog received SIGINT -- shutting down"; rm -f "${WATCHDOG_PID_FILE}"; exit 0' INT
    trap 'log_info "Watchdog received SIGHUP -- reloading config"' HUP

    local cycle_count=0

    while true; do
        ((cycle_count++)) || true

        run_check_cycle

        # Reset restart counters every 10 cycles (5-10 minutes)
        if [[ $((cycle_count % 10)) -eq 0 ]]; then
            reset_restart_counters
        fi

        sleep "${CHECK_INTERVAL}"
    done
}

# ============================================================================
# Check for Existing Daemon
# ============================================================================
check_existing_daemon() {
    if [[ -f "${WATCHDOG_PID_FILE}" ]]; then
        local pid
        pid=$(cat "${WATCHDOG_PID_FILE}" 2>/dev/null || echo "")
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            log_warn "Watchdog daemon is already running (PID: ${pid})"
            return 1
        else
            log_warn "Stale watchdog PID file -- cleaning up"
            rm -f "${WATCHDOG_PID_FILE}" 2>/dev/null || true
        fi
    fi
    return 0
}

# ============================================================================
# Stop Existing Daemon
# ============================================================================
stop_daemon() {
    if [[ -f "${WATCHDOG_PID_FILE}" ]]; then
        local pid
        pid=$(cat "${WATCHDOG_PID_FILE}" 2>/dev/null || echo "")
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            log_info "Stopping watchdog daemon (PID: ${pid})..."
            kill -TERM "${pid}" 2>/dev/null || true
            sleep 2
            # Force kill if still running
            if kill -0 "${pid}" 2>/dev/null; then
                kill -9 "${pid}" 2>/dev/null || true
            fi
            rm -f "${WATCHDOG_PID_FILE}" 2>/dev/null || true
            log_info "Watchdog daemon stopped"
        else
            rm -f "${WATCHDOG_PID_FILE}" 2>/dev/null || true
            log_info "No running watchdog daemon found"
        fi
    else
        log_info "No watchdog PID file found"
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    parse_args "$@"

    if [[ "${ONESHOT}" == "true" ]]; then
        log_section "Watchdog One-Shot Check"
        run_check_cycle
        exit $?
    fi

    if [[ "${DAEMONIZE}" == "true" ]]; then
        # Check if already running
        if ! check_existing_daemon; then
            log_error "Watchdog daemon is already running. Stop it first or use --oneshot."
            exit 1
        fi

        # Double-fork to fully detach
        (
            # First fork exits
            (
                run_daemon
            ) &
            # Parent exits immediately
        )
        log_info "Watchdog daemon started in background"
        sleep 1

        # Verify it started
        if [[ -f "${WATCHDOG_PID_FILE}" ]]; then
            local pid
            pid=$(cat "${WATCHDOG_PID_FILE}" 2>/dev/null || echo "")
            if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
                printf "${COLOR_BOLD_GREEN}  Watchdog daemon started (PID: %s)${COLOR_RESET}\n" "${pid}"
                printf "  Interval: %ss | Memory threshold: %s%% | Disk threshold: %s%%\n" \
                    "${CHECK_INTERVAL}" "${MEMORY_THRESHOLD}" "${DISK_THRESHOLD}"
                exit 0
            fi
        fi

        log_error "Watchdog daemon may have failed to start"
        exit 1
    fi

    # Default: run in foreground
    if ! check_existing_daemon; then
        log_error "Watchdog daemon is already running. Use --oneshot for a single check."
        exit 1
    fi

    run_daemon
}

# ============================================================================
# Execute Main
# ============================================================================
main "$@"
