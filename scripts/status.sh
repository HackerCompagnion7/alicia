#!/bin/bash
# ============================================================================
# status.sh - Alicia Desktop Environment Status Reporting Script
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
# Description:  Comprehensive status reporting for the Alicia Desktop
#               Environment. Shows system state, service status, resource
#               usage, and connectivity information with color-coded output.
# Usage:        status.sh [--json] [--short]
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

if ! declare -f alicia_init_directories &>/dev/null; then
    echo "ERROR: Failed to load alicia core libraries" >&2
    exit 1
fi

# ============================================================================
# Initialize
# ============================================================================
alicia_init_directories || true
log_init "${ALICIA_LOG_DIR}" "${ALICIA_LOG_DIR}/status.log" 2>/dev/null || true
log_set_module "status"

# ============================================================================
# Variables
# ============================================================================
JSON_OUTPUT=false
SHORT_OUTPUT=false

# ============================================================================
# Parse Arguments
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json|-j)
                JSON_OUTPUT=true
                shift
                ;;
            --short|-s)
                SHORT_OUTPUT=true
                shift
                ;;
            --help|-h)
                echo "Usage: status.sh [--json] [--short] [--help]"
                echo ""
                echo "  --json,  -j   Output in JSON format"
                echo "  --short, -s   One-line summary"
                echo "  --help,  -h   Show this help"
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# Color-Coded Status Helpers
# ============================================================================

# Print a status value with appropriate color
# Arguments: $1 = status (running/stopped/warning), $2 = text
status_color() {
    local status="$1"
    local text="$2"

    case "${status}" in
        running|ok|up|healthy|connected|yes|true|passed)
            printf "${COLOR_BOLD_GREEN}%s${COLOR_RESET}" "${text}"
            ;;
        stopped|down|unhealthy|disconnected|no|false|failed|error)
            printf "${COLOR_BOLD_RED}%s${COLOR_RESET}" "${text}"
            ;;
        warning|partial|degraded|slow)
            printf "${COLOR_BOLD_YELLOW}%s${COLOR_RESET}" "${text}"
            ;;
        *)
            printf "%s" "${text}"
            ;;
    esac
}

# Print a labeled status line
# Arguments: $1 = label, $2 = status, $3 = detail
status_line() {
    local label="$1"
    local status="$2"
    local detail="$3"

    printf "  %-22s " "${label}:"
    status_color "${status}" "${detail}"
    printf "\n"
}

# ============================================================================
# Status Gathering Functions
# ============================================================================

# Get Alicia running status
get_alicia_status() {
    local pid_file="${ALICIA_STATE_DIR}/alicia.pid"
    if [[ -f "${pid_file}" ]]; then
        local pid
        pid=$(cat "${pid_file}" 2>/dev/null || echo "")
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            echo "running"
            return 0
        fi
    fi

    local state
    state=$(alicia_get_state "alicia_running" 2>/dev/null || echo "")
    if [[ "${state}" == "true" ]]; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Get VNC status
get_vnc_status() {
    if vnc_is_running 2>/dev/null; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Get proot status
get_proot_status() {
    if proot_is_running 2>/dev/null; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Get desktop environment status
get_de_status() {
    if de_is_running 2>/dev/null; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Get VNC port
get_vnc_port() {
    local port
    port=$(alicia_get_state "vnc_port" 2>/dev/null || echo "")
    if [[ -z "${port}" ]]; then
        port="${ALICIA_DEFAULT_VNC_PORT}"
    fi
    echo "${port}"
}

# Get VNC resolution
get_vnc_resolution() {
    local res
    res=$(alicia_get_state "vnc_resolution" 2>/dev/null || echo "")
    if [[ -z "${res}" ]]; then
        res="${ALICIA_DEFAULT_VNC_RESOLUTION}"
    fi
    echo "${res}"
}

# Get memory usage info
get_memory_info() {
    local mem_info
    mem_info=$(free -m 2>/dev/null | grep "^Mem:" || echo "")
    if [[ -n "${mem_info}" ]]; then
        local total used avail
        total=$(echo "${mem_info}" | awk '{print $2}')
        used=$(echo "${mem_info}" | awk '{print $3}')
        avail=$(echo "${mem_info}" | awk '{print $7}')
        local pct=0
        if [[ ${total} -gt 0 ]]; then
            pct=$((used * 100 / total))
        fi
        echo "${used}MB / ${total}MB (${pct}%) -- Available: ${avail}MB"
    else
        echo "Information unavailable"
    fi
}

# Get memory usage percentage
get_memory_pct() {
    local mem_info
    mem_info=$(free 2>/dev/null | grep "^Mem:" || echo "")
    if [[ -n "${mem_info}" ]]; then
        local total used
        total=$(echo "${mem_info}" | awk '{print $2}')
        used=$(echo "${mem_info}" | awk '{print $3}')
        if [[ ${total} -gt 0 ]]; then
            echo "$((used * 100 / total))"
            return 0
        fi
    fi
    echo "0"
}

# Get storage usage info
get_storage_info() {
    local path="${ALICIA_HOME}"
    local info
    info=$(df -h "${path}" 2>/dev/null | tail -1 || echo "")
    if [[ -n "${info}" ]]; then
        local size used avail pct
        size=$(echo "${info}" | awk '{print $2}')
        used=$(echo "${info}" | awk '{print $3}')
        avail=$(echo "${info}" | awk '{print $4}')
        pct=$(echo "${info}" | awk '{print $5}')
        echo "${used} / ${size} (${pct} used) -- Available: ${avail}"
    else
        echo "Information unavailable"
    fi
}

# Get storage usage percentage
get_storage_pct() {
    local pct
    pct=$(df "${ALICIA_HOME}" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "0")
    echo "${pct:-0}"
}

# Get CPU usage (snapshot)
get_cpu_usage() {
    # Get load average as a proxy for CPU usage
    local load
    load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}' || echo "0")
    local cores
    cores=$(nproc 2>/dev/null || echo 1)
    echo "Load: ${load} (${cores} core(s))"
}

# Get network connectivity status
get_network_status() {
    if network_is_available 2>/dev/null; then
        echo "connected"
    else
        echo "disconnected"
    fi
}

# Get local IP address
get_local_ip() {
    network_get_local_ip 2>/dev/null || echo "127.0.0.1"
}

# Get installed package count inside proot
get_package_count() {
    local count
    count=$(proot_exec "${ALICIA_DISTRO_NAME:-debian}" \
        "dpkg -l 2>/dev/null | tail -n +6 | wc -l || apk info 2>/dev/null | wc -l || rpm -qa 2>/dev/null | wc -l" \
        2>/dev/null | tr -d '[:space:]' || echo "0")
    echo "${count:-0}"
}

# Get uptime (how long Alicia has been running)
get_alicia_uptime() {
    local started
    started=$(alicia_get_state "alicia_started" 2>/dev/null || echo "")
    if [[ -z "${started}" ]]; then
        echo "Not running"
        return 0
    fi

    # Calculate duration
    local started_epoch now_epoch
    started_epoch=$(date -d "${started}" +%s 2>/dev/null || echo "0")
    now_epoch=$(date +%s 2>/dev/null || echo "0")

    if [[ ${started_epoch} -eq 0 ]]; then
        echo "Unknown"
        return 0
    fi

    local diff_secs=$((now_epoch - started_epoch))
    local days=$((diff_secs / 86400))
    local hours=$(( (diff_secs % 86400) / 3600 ))
    local mins=$(( (diff_secs % 3600) / 60 ))

    if [[ ${days} -gt 0 ]]; then
        echo "${days}d ${hours}h ${mins}m"
    elif [[ ${hours} -gt 0 ]]; then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

# Get running processes inside proot
get_proot_processes() {
    proot_exec "${ALICIA_DISTRO_NAME:-debian}" \
        "ps aux 2>/dev/null | head -1; ps aux 2>/dev/null | grep -vE 'ps aux|grep' | head -15" \
        2>/dev/null || echo "Cannot retrieve process list"
}

# Get VNC connections
get_vnc_connections() {
    local port
    port=$(get_vnc_port)
    local conn_count
    conn_count=$(ss -tn 2>/dev/null | grep -c ":${port}" || echo "0")
    echo "${conn_count:-0}"
}

# ============================================================================
# Short Output (One-Line Summary)
# ============================================================================
show_short_status() {
    local alicia_st vnc_st proot_st de_st

    alicia_st=$(get_alicia_status)
    vnc_st=$(get_vnc_status)
    proot_st=$(get_proot_status)
    de_st=$(get_de_status)

    local status_text
    if [[ "${alicia_st}" == "running" ]]; then
        status_text="UP"
    else
        status_text="DOWN"
    fi

    local uptime_str
    uptime_str=$(get_alicia_uptime)
    local mem_pct
    mem_pct=$(get_memory_pct)
    local storage_pct
    storage_pct=$(get_storage_pct)

    printf "Alicia: %s | Uptime: %s | VNC: %s | proot: %s | DE: %s | Mem: %s%% | Disk: %s%%\n" \
        "${status_text}" "${uptime_str}" "${vnc_st}" "${proot_st}" "${de_st}" "${mem_pct}" "${storage_pct}"
}

# ============================================================================
# JSON Output
# ============================================================================
show_json_status() {
    local alicia_st vnc_st proot_st de_st net_st
    alicia_st=$(get_alicia_status)
    vnc_st=$(get_vnc_status)
    proot_st=$(get_proot_status)
    de_st=$(get_de_status)
    net_st=$(get_network_status)

    local vnc_port vnc_res local_ip uptime_str pkg_count vnc_conns
    vnc_port=$(get_vnc_port)
    vnc_res=$(get_vnc_resolution)
    local_ip=$(get_local_ip)
    uptime_str=$(get_alicia_uptime)
    pkg_count=$(get_package_count)
    vnc_conns=$(get_vnc_connections)

    local mem_pct storage_pct
    mem_pct=$(get_memory_pct)
    storage_pct=$(get_storage_pct)

    # Build JSON manually (no jq dependency required)
    cat <<JSONEOF
{
  "alicia": {
    "version": "${ALICIA_VERSION}",
    "status": "${alicia_st}",
    "uptime": "${uptime_str}",
    "pid": "$(cat "${ALICIA_STATE_DIR}/alicia.pid" 2>/dev/null || echo "")"
  },
  "vnc": {
    "status": "${vnc_st}",
    "port": ${vnc_port},
    "resolution": "${vnc_res}",
    "connections": ${vnc_conns}
  },
  "proot": {
    "status": "${proot_st}",
    "distro": "${ALICIA_DISTRO_NAME:-debian}"
  },
  "desktop": {
    "status": "${de_st}",
    "environment": "${ALICIA_DESKTOP_ENV:-xfce4}"
  },
  "system": {
    "memory_usage_pct": ${mem_pct},
    "storage_usage_pct": ${storage_pct},
    "cpu_load": "$(cat /proc/loadavg 2>/dev/null | awk '{print $1}' || echo "0")",
    "cpu_cores": $(nproc 2>/dev/null || echo 1),
    "network": "${net_st}",
    "local_ip": "${local_ip}",
    "packages": ${pkg_count}
  }
}
JSONEOF
}

# ============================================================================
# Full Interactive Output
# ============================================================================
show_full_status() {
    local alicia_st vnc_st proot_st de_st net_st

    alicia_st=$(get_alicia_status)
    vnc_st=$(get_vnc_status)
    proot_st=$(get_proot_status)
    de_st=$(get_de_status)
    net_st=$(get_network_status)

    # Header
    printf "\n"
    printf "${COLOR_BOLD_WHITE}  Alicia Desktop Environment -- System Status${COLOR_RESET}\n"
    printf "${COLOR_DIM}  Version %s | %s${COLOR_RESET}\n" "$(alicia_get_version)" "$(date '+%Y-%m-%d %H:%M:%S')"
    log_separator "=" 55

    # Alicia Overall
    printf "\n${COLOR_BOLD_CYAN}  Alicia${COLOR_RESET}\n"
    status_line "Status" "${alicia_st}" "$(status_color "${alicia_st}" "${alicia_st^^}")"
    status_line "Uptime" "${alicia_st}" "$(get_alicia_uptime)"
    status_line "PID" "${alicia_st}" "$(cat "${ALICIA_STATE_DIR}/alicia.pid" 2>/dev/null || echo "N/A")"
    status_line "Version" "ok" "${ALICIA_VERSION}"

    # VNC Server
    printf "\n${COLOR_BOLD_CYAN}  VNC Server${COLOR_RESET}\n"
    status_line "Status" "${vnc_st}" "$(status_color "${vnc_st}" "${vnc_st^^}")"
    status_line "Port" "${vnc_st}" "$(get_vnc_port)"
    status_line "Resolution" "${vnc_st}" "$(get_vnc_resolution)"
    status_line "Connections" "${vnc_st}" "$(get_vnc_connections)"
    status_line "Display" "${vnc_st}" "${ALICIA_DISPLAY:-:1}"

    # proot
    printf "\n${COLOR_BOLD_CYAN}  proot Session${COLOR_RESET}\n"
    status_line "Status" "${proot_st}" "$(status_color "${proot_st}" "${proot_st^^}")"
    status_line "Distribution" "${proot_st}" "${ALICIA_DISTRO_NAME:-debian}"

    # Desktop Environment
    printf "\n${COLOR_BOLD_CYAN}  Desktop Environment${COLOR_RESET}\n"
    status_line "Status" "${de_st}" "$(status_color "${de_st}" "${de_st^^}")"
    status_line "Environment" "${de_st}" "${ALICIA_DESKTOP_ENV:-xfce4}"

    # Memory
    local mem_pct
    mem_pct=$(get_memory_pct)
    local mem_status="ok"
    if [[ ${mem_pct} -gt 90 ]]; then mem_status="error"
    elif [[ ${mem_pct} -gt 75 ]]; then mem_status="warning"; fi

    printf "\n${COLOR_BOLD_CYAN}  Memory${COLOR_RESET}\n"
    status_line "Usage" "${mem_status}" "$(get_memory_info)"
    status_line "Usage %" "${mem_status}" "${mem_pct}%"

    # Storage
    local storage_pct
    storage_pct=$(get_storage_pct)
    local storage_status="ok"
    if [[ ${storage_pct} -gt 95 ]]; then storage_status="error"
    elif [[ ${storage_pct} -gt 85 ]]; then storage_status="warning"; fi

    printf "\n${COLOR_BOLD_CYAN}  Storage${COLOR_RESET}\n"
    status_line "Usage" "${storage_status}" "$(get_storage_info)"
    status_line "Usage %" "${storage_status}" "${storage_pct}%"

    # CPU
    printf "\n${COLOR_BOLD_CYAN}  CPU${COLOR_RESET}\n"
    status_line "Load" "ok" "$(get_cpu_usage)"

    # Network
    printf "\n${COLOR_BOLD_CYAN}  Network${COLOR_RESET}\n"
    status_line "Connectivity" "${net_st}" "$(status_color "${net_st}" "${net_st^^}")"
    status_line "Local IP" "${net_st}" "$(get_local_ip)"

    # Packages
    printf "\n${COLOR_BOLD_CYAN}  Packages${COLOR_RESET}\n"
    status_line "Installed" "ok" "$(get_package_count)"

    # Proot Processes (condensed)
    printf "\n${COLOR_BOLD_CYAN}  proot Processes (top 10)${COLOR_RESET}\n"
    proot_exec "${ALICIA_DISTRO_NAME:-debian}" \
        "ps aux 2>/dev/null | head -1; ps aux 2>/dev/null | grep -vE 'ps aux|grep' | head -10" \
        2>/dev/null | while IFS= read -r line; do
        printf "  ${COLOR_DIM}%s${COLOR_RESET}\n" "${line}"
    done || printf "  ${COLOR_DIM}Cannot retrieve process list${COLOR_RESET}\n"

    printf "\n"
    log_separator "=" 55
    printf "\n"
}

# ============================================================================
# Main
# ============================================================================
main() {
    parse_args "$@"

    if [[ "${JSON_OUTPUT}" == "true" ]]; then
        show_json_status
    elif [[ "${SHORT_OUTPUT}" == "true" ]]; then
        show_short_status
    else
        show_full_status
    fi

    return 0
}

# ============================================================================
# Execute Main
# ============================================================================
main "$@"
