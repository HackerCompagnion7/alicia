#!/bin/bash
# ============================================================================
# install.sh - Alicia Desktop Environment Installation Script
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
# Description:  Main installation script for the Alicia Desktop Environment.
#               This is the entry point users run after cloning the repo.
#               Validates prerequisites, runs all setup scripts in sequence,
#               tracks progress, handles failures with rollback, and validates
#               the final installation.
# Usage:        install.sh [--unattended] [--verbose] [--skip-step STEP]
# ============================================================================

set -uo pipefail
# Note: 'set -e' (errexit) is intentionally NOT set here because it causes
# fragile behavior during library sourcing. Errors are handled explicitly
# with || and if checks instead.

# ============================================================================
# Script Directory Resolution
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
SETUP_DIR="${SCRIPT_DIR}/../setup"
ALICIA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ============================================================================
# Source Alicia Libraries
# ============================================================================
# We source each library in a subshell first to test if it loads cleanly,
# then source it in the current shell. This prevents partial-loading issues
# where a library fails mid-way, leaving readonly variables behind that
# prevent the fallback from working.
_ALICIA_LIBS_LOADED=true
for lib_file in "${LIB_DIR}"/alicia-*.sh; do
    if [[ -f "${lib_file}" ]]; then
        # Test if the library can be sourced without errors (in a subshell)
        if ! (source "${lib_file}") 2>/dev/null; then
            echo "[WARN] Failed to source library: ${lib_file} (continuing with fallbacks)" >&2
            _ALICIA_LIBS_LOADED=false
            continue
        fi
        # Source for real in the current shell
        source "${lib_file}" 2>/dev/null || {
            echo "[WARN] Error sourcing library: ${lib_file} (continuing with fallbacks)" >&2
            _ALICIA_LIBS_LOADED=false
        }
    fi
done

# Provide fallback functions if libraries failed to load
if ! declare -f log_info &>/dev/null; then
    # Minimal fallback logging - use 'declare -r' only if not already set
    # to avoid conflicts with partially-loaded alicia-log.sh
    _safe_readonly() {
        local varname="$1" varval="$2"
        if [[ -z "${!varname:-}" ]]; then
            declare -rg "$varname=$varval" 2>/dev/null || true
        fi
    }
    _safe_readonly COLOR_RESET '\033[0m'
    _safe_readonly COLOR_RED '\033[0;31m'
    _safe_readonly COLOR_GREEN '\033[0;32m'
    _safe_readonly COLOR_YELLOW '\033[0;33m'
    _safe_readonly COLOR_CYAN '\033[0;36m'
    _safe_readonly COLOR_BOLD '\033[1m'
    _safe_readonly COLOR_BOLD_CYAN '\033[1;36m'
    _safe_readonly COLOR_BOLD_WHITE '\033[1;37m'
    _safe_readonly COLOR_BOLD_GREEN '\033[1;32m'
    _safe_readonly COLOR_DIM '\033[2m'
    _safe_readonly COLOR_BOLD_BLUE '\033[1;34m'
    unset -f _safe_readonly
    log_debug()   { :; }
    log_info()    { printf "${COLOR_GREEN}[INFO]${COLOR_RESET}  %s\n" "$*"; }
    log_warn()    { printf "${COLOR_YELLOW}[WARN]${COLOR_RESET}  %s\n" "$*" >&2; }
    log_error()   { printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$*" >&2; }
    log_section() { printf "\n${COLOR_BOLD_BLUE}======== %s ========${COLOR_RESET}\n" "$1"; }
    log_separator() { local ch="${1:--}"; local w="${2:-55}"; local l=""; for ((i=0;i<w;i++)); do l+="$ch"; done; printf "%s\n" "$l"; }
    log_timer_start() { :; }
    log_timer_end() { :; }
    log_init() { :; }
    log_set_module() { :; }
fi

if ! declare -f alicia_init_directories &>/dev/null; then
    # Minimal fallback core
    ALICIA_VERSION="3.1.0"
    ALICIA_CODENAME="Tomorrow"
    ALICIA_HOME="${HOME}/.alicia"
    ALICIA_LOG_DIR="${ALICIA_HOME}/logs"
    ALICIA_STATE_DIR="${ALICIA_HOME}/state"
    ALICIA_CONFIG_DIR="${ALICIA_HOME}/config"
    ALICIA_DEFAULT_VNC_PORT=5901
    ALICIA_DEFAULT_VNC_RESOLUTION="1280x720"
    ALICIA_DEFAULT_DESKTOP_ENV="xfce4"
    ALICIA_DEFAULT_PROOT_DISTRO="alpine"
    ALICIA_MIN_RAM_MB=2048
    ALICIA_MIN_STORAGE_MB=4096
    ALICIA_GITHUB_REPO="HackerCompagnion7/alicia"

    alicia_init_directories() {
        mkdir -p "${ALICIA_HOME}" "${ALICIA_LOG_DIR}" "${ALICIA_STATE_DIR}" "${ALICIA_CONFIG_DIR}" 2>/dev/null || true
    }
    alicia_set_state() {
        local key="$1" val="$2"
        mkdir -p "${ALICIA_STATE_DIR}" 2>/dev/null || true
        echo "$val" > "${ALICIA_STATE_DIR}/${key}.state" 2>/dev/null || true
    }
    alicia_get_state() {
        cat "${ALICIA_STATE_DIR}/${1}.state" 2>/dev/null || echo ""
    }
fi

if ! declare -f network_is_available &>/dev/null; then
    network_is_available() {
        ping -c 1 -W 5 8.8.8.8 &>/dev/null || curl -s --connect-timeout 5 -o /dev/null https://www.google.com 2>/dev/null
    }
fi

if ! declare -f storage_get_available_space &>/dev/null; then
    storage_get_available_space() {
        df -m "${2:-$HOME}" 2>/dev/null | tail -1 | awk '{print $4}' || echo 0
    }
fi

if ! declare -f proot_is_installed &>/dev/null; then
    proot_is_installed() { command -v proot-distro &>/dev/null; }
fi

if ! declare -f proot_is_distro_installed &>/dev/null; then
    proot_is_distro_installed() { proot-distro list 2>/dev/null | grep -q "$1"; }
fi

# ============================================================================
# Initialize
# ============================================================================
alicia_init_directories || true
log_init "${ALICIA_LOG_DIR}" "${ALICIA_LOG_DIR}/install.log" 2>/dev/null || true
log_set_module "install"

# ============================================================================
# Variables
# ============================================================================
UNATTENDED=false
VERBOSE=false
SKIP_STEPS=()
COMPLETED_STEPS=()
FAILED_STEP=""
INSTALL_START_TIME=""
TOTAL_STEPS=7
LOG_FILE="${ALICIA_LOG_DIR}/install.log"

# Setup scripts in order
declare -ga SETUP_SCRIPTS=(
    "01-termux-setup.sh:Termux Environment Setup"
    "02-proot-setup.sh:Linux Distribution Setup"
    "03-desktop-setup.sh:Desktop Environment Setup"
    "04-vnc-setup.sh:VNC Server Setup"
    "05-apps-setup.sh:Application Installation"
    "06-alicia-customize.sh:Alicia Customization"
    "07-alicia-commands.sh:Alicia Commands & Overlay"
)

# ============================================================================
# Parse Arguments
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --unattended|-u)
                UNATTENDED=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --skip-step|-s)
                if [[ -z "${2:-}" ]]; then
                    log_error "--skip-step requires a step number (01-06)"
                    exit 1
                fi
                SKIP_STEPS+=("$2")
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
    echo "Usage: install.sh [OPTIONS]"
    echo ""
    echo "Install the Alicia Desktop Environment."
    echo ""
    echo "Options:"
    echo "  --unattended, -u       Automated installation (no prompts)"
    echo "  --verbose, -v          Verbose output"
    echo "  --skip-step, -s STEP   Skip a setup step (01-07)"
    echo "  --help, -h             Show this help"
    echo ""
    echo "Setup Steps:"
    echo "  01 - Termux environment setup"
    echo "  02 - Linux distribution (proot) setup"
    echo "  03 - Desktop environment setup"
    echo "  04 - VNC server setup"
    echo "  05 - Application installation"
    echo "  06 - Alicia customization"
    echo "  07 - Alicia commands & overlay installation"
    echo ""
    echo "Examples:"
    echo "  install.sh                       Interactive installation"
    echo "  install.sh --unattended          Fully automated installation"
    echo "  install.sh --skip-step 05        Skip app installation"
    echo "  install.sh -u -v                 Unattended with verbose output"
}

# ============================================================================
# ASCII Art Banner
# ============================================================================
show_welcome_banner() {
    printf "\n"
    printf "${COLOR_BOLD_CYAN}%s${COLOR_RESET}\n" \
"     ___    _ _      _     ___ _    ___ "
    printf "${COLOR_BOLD_CYAN}%s${COLOR_RESET}\n" \
"    /   |  (_) |____| |__ / __| |  |_ _|"
    printf "${COLOR_BOLD_CYAN}%s${COLOR_RESET}\n" \
"   / /| |__| | '_ \\ _ \\ '_ \\ (__| |__ | | "
    printf "${COLOR_BOLD_CYAN}%s${COLOR_RESET}\n" \
"  /_/ |____|_|_.__\\___/_| |_|\\___|____|___|"
    printf "${COLOR_BOLD_CYAN}%s${COLOR_RESET}\n" \
"                                   |___| "
    echo ""
    printf "${COLOR_BOLD_WHITE}  Alicia Desktop Environment -- Installer${COLOR_RESET}\n"
    printf "${COLOR_DIM}  Version ${ALICIA_VERSION} (${ALICIA_CODENAME})${COLOR_RESET}\n"
    printf "${COLOR_DIM}  Copyright (C) 2005-2025 Proyecto Tomorrow${COLOR_RESET}\n"
    echo ""
    log_separator "=" 55
    echo ""
}

# ============================================================================
# License Agreement
# ============================================================================
show_license() {
    if [[ "${UNATTENDED}" == "true" ]]; then
        log_info "Unattended mode -- accepting license automatically"
        return 0
    fi

    local license_text="
Alicia Desktop Environment is free software: you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
"

    ui_show_message "License Agreement" "${license_text}"

    if ! ui_show_question "License Agreement" "Do you accept the GNU General Public License v3.0?"; then
        log_info "License not accepted -- installation aborted"
        exit 1
    fi

    log_info "License accepted"
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

# Check Termux environment
check_prerequisite_termux() {
    log_info "Checking Termux environment..."

    if [[ -z "${TERMUX_VERSION:-}" && ! -d "/data/data/com.termux" ]]; then
        log_warn "Not running inside Termux"
        if [[ "${UNATTENDED}" != "true" ]]; then
            if ! ui_show_question "Environment Warning" \
                "Alicia is designed for Termux on Android. Continue anyway?"; then
                return 1
            fi
        fi
    else
        log_info "Termux detected (version: ${TERMUX_VERSION:-unknown})"
    fi
    return 0
}

# Check storage access
check_prerequisite_storage() {
    log_info "Checking storage access..."

    if [[ -n "${TERMUX_VERSION:-}" && ! -d "${HOME}/storage" ]]; then
        log_warn "Termux storage not set up"
        if [[ "${UNATTENDED}" == "true" ]]; then
            log_info "Running termux-setup-storage..."
            termux-setup-storage 2>/dev/null || {
                log_warn "termux-setup-storage failed -- storage may be limited"
            }
        else
            if ui_show_question "Storage Access" \
                "Storage access is required. Run 'termux-setup-storage' now?"; then
                termux-setup-storage 2>/dev/null || {
                    log_warn "termux-setup-storage failed"
                }
            fi
        fi
    fi

    # Check minimum space
    local avail
    avail=$(storage_get_available_space "${HOME}" 2>/dev/null || echo 0)
    if [[ ${avail} -lt ${ALICIA_MIN_STORAGE_MB} ]]; then
        log_error "Insufficient storage: ${avail}MB available (need ${ALICIA_MIN_STORAGE_MB}MB)"
        if [[ "${UNATTENDED}" != "true" ]]; then
            ui_show_error "Storage Error" \
                "Not enough storage space.\nAvailable: ${avail}MB\nRequired: ${ALICIA_MIN_STORAGE_MB}MB"
        fi
        return 1
    fi

    log_info "Storage OK (${avail}MB available)"
    return 0
}

# Check network connectivity
check_prerequisite_network() {
    log_info "Checking network connectivity..."

    if network_is_available 2>/dev/null; then
        log_info "Network connectivity: OK"
        return 0
    fi

    log_warn "No network connectivity detected"
    if [[ "${UNATTENDED}" == "true" ]]; then
        log_error "Network is required for installation"
        return 1
    fi

    if ! ui_show_question "Network Warning" \
        "No internet connection detected. Installation requires network access.\nContinue anyway?"; then
        return 1
    fi

    return 0
}

# Check RAM
check_prerequisite_ram() {
    log_info "Checking available RAM..."

    local mem_total
    mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")

    if [[ ${mem_total} -gt 0 && ${mem_total} -lt ${ALICIA_MIN_RAM_MB} ]]; then
        log_warn "Low RAM: ${mem_total}MB (recommended: ${ALICIA_MIN_RAM_MB}MB)"
        if [[ "${UNATTENDED}" != "true" ]]; then
            ui_show_warning "RAM Warning" \
                "Your device has ${mem_total}MB RAM.\nRecommended: ${ALICIA_MIN_RAM_MB}MB.\nAlicia may run slowly or crash."
        fi
    else
        log_info "RAM: ${mem_total}MB (OK)"
    fi
    return 0
}

# Check essential tools
check_prerequisite_tools() {
    log_info "Checking essential tools..."

    local missing=()
    local tools=("bash" "curl" "tar")

    for tool in "${tools[@]}"; do
        if ! command -v "${tool}" &>/dev/null; then
            missing+=("${tool}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing essential tools: ${missing[*]}"
        return 1
    fi

    log_info "Essential tools: OK"
    return 0
}

# Run all prerequisite checks
run_prerequisite_checks() {
    log_section "Prerequisite Checks"

    local failures=0

    check_prerequisite_termux   || ((failures++)) || true
    check_prerequisite_storage  || ((failures++)) || true
    check_prerequisite_network  || ((failures++)) || true
    check_prerequisite_ram      || true
    check_prerequisite_tools    || ((failures++)) || true

    if [[ ${failures} -gt 0 ]]; then
        log_error "Prerequisite checks failed (${failures} critical issue(s))"
        return 1
    fi

    log_info "All prerequisite checks passed"
    return 0
}

# ============================================================================
# Setup Script Execution
# ============================================================================

# Check if a step should be skipped
should_skip_step() {
    local step_num="$1"
    local skip
    for skip in "${SKIP_STEPS[@]}"; do
        if [[ "${skip}" == "${step_num}" ]]; then
            return 0
        fi
    done
    return 1
}

# ============================================================================
# PUNTO 10: Visual feedback - Spinner and progress bar
# ============================================================================

# Global spinner variables
_SPINNER_PID=""
_SPINNER_MSG=""

_start_spinner() {
    local msg="${1:-Working}"
    _SPINNER_MSG="$msg"
    local chars=('|' '/' '-' '\\')
    local i=0
    while true; do
        printf "\r  %s... %s" "$msg" "${chars[$((i % 4))]}" >&2
        i=$((i + 1))
        sleep 0.3
    done &
    _SPINNER_PID=$!
}

_stop_spinner() {
    if [[ -n "${_SPINNER_PID:-}" ]] && kill -0 "$_SPINNER_PID" 2>/dev/null; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
        printf "\r  %s... Done!    \n" "${_SPINNER_MSG:-}" >&2
    fi
}

# Show step progress with visual bar
show_step_progress() {
    local current="$1"
    local total="$2"
    local desc="$3"
    local width=30
    local pct=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=0; i<empty; i++)); do bar+="-"; done
    printf "\n${COLOR_BOLD_CYAN}[%d/%d] %s${COLOR_RESET}\n" "$current" "$total" "$desc"
    printf "${COLOR_CYAN}%s${COLOR_RESET} %d%%\n" "$bar" "$pct"
}

# Run a single setup script with live output
run_setup_script() {
    local script_name="$1"
    local description="$2"
    local step_num="${script_name:0:2}"
    local current_step=0

    # Calculate current step number
    for entry in "${SETUP_SCRIPTS[@]}"; do
        ((current_step++)) || true
        if [[ "${entry%%:*}" == "${script_name}" ]]; then
            break
        fi
    done

    if should_skip_step "${step_num}"; then
        log_info "Skipping step ${step_num}: ${description}"
        COMPLETED_STEPS+=("${step_num}:SKIPPED")
        return 0
    fi

    # PUNTO 10: Show progress with step counter and progress bar
    show_step_progress "${current_step}" "${TOTAL_STEPS}" "${description}"

    local script_path="${SETUP_DIR}/${script_name}"
    if [[ ! -f "${script_path}" ]]; then
        log_error "Setup script not found: ${script_path}"
        return 1
    fi

    if [[ ! -x "${script_path}" ]]; then
        chmod +x "${script_path}"
    fi

    local step_start
    step_start=$(date +%s)

    # PUNTO 10: Run with live output (NOT silenced to file)
    local exit_code=0
    if [[ "${VERBOSE}" == "true" ]]; then
        bash -x "${script_path}" 2>&1 | while IFS= read -r line; do
            printf "  %s\n" "$line"
        done || exit_code=$?
    else
        # Show output LIVE - pipe through tee so user sees progress
        _start_spinner "${description}"
        bash "${script_path}" 2>&1 | while IFS= read -r line; do
            # Show key lines: errors, section headers, completion messages
            case "$line" in
                *"[ERROR]"*|*"FAILED"*|*"FAIL"*)
                    _stop_spinner
                    printf "  ${COLOR_RED}%s${COLOR_RESET}\n" "$line"
                    _start_spinner "${description}"
                    ;;
                *"========"*|*"[SECTION]"*|*"Section"*)
                    _stop_spinner
                    printf "  ${COLOR_BOLD_BLUE}%s${COLOR_RESET}\n" "$line"
                    _start_spinner "${description}"
                    ;;
                *"complete"*|*"Complete"*|*"OK"*|*"installed"*|*"created"*)
                    _stop_spinner
                    printf "  ${COLOR_GREEN}%s${COLOR_RESET}\n" "$line"
                    _start_spinner "${description}"
                    ;;
                *"[WARN]"*|*"Warning"*|*"skipping"*)
                    _stop_spinner
                    printf "  ${COLOR_YELLOW}%s${COLOR_RESET}\n" "$line"
                    _start_spinner "${description}"
                    ;;
                *"Installing"*|*"Downloading"*|*"Configuring"*|*"Creating"*|*"Setting"*|*"Applying"*)
                    _stop_spinner
                    printf "  ${COLOR_CYAN}%s${COLOR_RESET}\n" "$line"
                    _start_spinner "${description}"
                    ;;
                *)
                    # Silently log to file
                    echo "$line" >> "${LOG_FILE}" 2>/dev/null || true
                    ;;
            esac
        done || exit_code=$?
        _stop_spinner
    fi

    local step_end
    step_end=$(date +%s)
    local duration=$((step_end - step_start))

    if [[ ${exit_code} -ne 0 ]]; then
        printf "  ${COLOR_RED}[FAIL]${COLOR_RESET} Step %s failed (exit: %d, time: %ds)\n" "${step_num}" "${exit_code}" "${duration}"
        FAILED_STEP="${step_num}"
        return 1
    fi

    printf "  ${COLOR_GREEN}[OK]${COLOR_RESET} Step %s completed (%ds)\n" "${step_num}" "${duration}"
    COMPLETED_STEPS+=("${step_num}:OK")
    return 0
}

# Run all setup scripts
run_all_setup_scripts() {
    log_section "Installation Steps"

    echo ""
    printf "${COLOR_BOLD_WHITE}  Total steps: %d${COLOR_RESET}\n" "${TOTAL_STEPS}"
    echo ""

    local current_step=0
    for entry in "${SETUP_SCRIPTS[@]}"; do
        local script_name="${entry%%:*}"
        local description="${entry##*:}"
        ((current_step++)) || true

        if ! run_setup_script "${script_name}" "${description}"; then
            log_error "Installation failed at step: ${description}"
            return 1
        fi
    done

    echo ""
    printf "${COLOR_BOLD_GREEN}  All %d steps completed successfully!${COLOR_RESET}\n" "${TOTAL_STEPS}"
    echo ""

    log_info "All setup scripts completed successfully"
    return 0
}

# ============================================================================
# Rollback on Failure
# ============================================================================
perform_rollback() {
    log_section "Installation Rollback"

    log_error "Installation failed at step: ${FAILED_STEP:-unknown}"
    log_info "Performing rollback..."

    # Ask user for confirmation (unless unattended)
    if [[ "${UNATTENDED}" != "true" ]]; then
        if ! ui_show_question "Installation Failed" \
            "Installation failed at step ${FAILED_STEP:-unknown}.\nAttempt to roll back changes?"; then
            log_info "Rollback cancelled by user"
            return 0
        fi
    fi

    # Stop any services that might be running
    de_stop 2>/dev/null || true
    vnc_stop 2>/dev/null || true
    proot_stop 2>/dev/null || true

    # Reverse completed steps in reverse order
    local reversed=()
    for step in "${COMPLETED_STEPS[@]}"; do
        reversed=("${step}" "${reversed[@]}")
    done

    for step in "${reversed[@]}"; do
        local step_num="${step%%:*}"
        local status="${step##*:}"

        if [[ "${status}" == "SKIPPED" ]]; then
            continue
        fi

        log_info "Rolling back step ${step_num}..."
        # Each setup script may have a --uninstall mode
        local script_path="${SETUP_DIR}/${step_num}-*.sh"
        local found_script
        found_script=$(ls "${script_path}" 2>/dev/null | head -1 || true)

        if [[ -n "${found_script}" && -x "${found_script}" ]]; then
            bash "${found_script}" --uninstall 2>/dev/null || {
                log_warn "Rollback for step ${step_num} failed or not supported"
            }
        fi
    done

    # Clean up state
    alicia_set_state "alicia_installed" "false" 2>/dev/null || true
    alicia_set_state "install_failed" "true" 2>/dev/null || true
    alicia_set_state "install_failed_step" "${FAILED_STEP}" 2>/dev/null || true

    log_info "Rollback completed"
    ui_show_error "Installation Failed" \
        "The installation failed and was rolled back.\nCheck the log for details:\n${LOG_FILE}"
}

# ============================================================================
# Post-Installation Validation
# ============================================================================
validate_installation() {
    log_section "Post-Installation Validation"

    local failures=0

    # Check proot is installed
    log_info "Validating proot installation..."
    if proot_is_installed 2>/dev/null; then
        printf "  ${COLOR_GREEN}[OK]${COLOR_RESET} proot-distro\n"
    else
        printf "  ${COLOR_RED}[FAIL]${COLOR_RESET} proot-distro NOT INSTALLED\n"
        ((failures++)) || true
    fi

    # Check distro is installed
    log_info "Validating Linux distribution..."
    if proot_is_distro_installed "${ALICIA_DEFAULT_PROOT_DISTRO}" 2>/dev/null; then
        printf "  ${COLOR_GREEN}[OK]${COLOR_RESET} Distribution (${ALICIA_DEFAULT_PROOT_DISTRO})\n"
    else
        printf "  ${COLOR_RED}[FAIL]${COLOR_RESET} Distribution NOT INSTALLED\n"
        ((failures++)) || true
    fi

    # Check configuration exists
    log_info "Validating configuration..."
    if [[ -f "${ALICIA_CONFIG_DIR}/alicia.conf" ]]; then
        printf "  ${COLOR_GREEN}[OK]${COLOR_RESET} Configuration\n"
    else
        printf "  ${COLOR_YELLOW}[WARN]${COLOR_RESET} Configuration missing (using defaults)\n"
    fi

    # PUNTO 4: Check ALL alicia commands exist inside proot
    log_info "Validating alicia commands inside proot..."
    local alicia_cmds=(
        "alicia-install"
        "alicia-remove"
        "alicia-health"
        "alicia-backup"
        "alicia-repair"
        "alicia-about"
        "alicia-tool-store"
        "alicia-system-info"
        "alicia-vnc-info"
        "alicia-vnc-start"
        "alicia-vnc-stop"
        "alicia-update"
    )
    local cmd_failures=0
    for cmd in "${alicia_cmds[@]}"; do
        if proot-distro login "${ALICIA_DEFAULT_PROOT_DISTRO}" -- test -x "/usr/bin/${cmd}" 2>/dev/null; then
            printf "  ${COLOR_GREEN}[OK]${COLOR_RESET} /usr/bin/%s\n" "${cmd}"
        else
            printf "  ${COLOR_RED}[FAIL]${COLOR_RESET} /usr/bin/%s NOT FOUND\n" "${cmd}"
            ((cmd_failures++)) || true
        fi
    done

    # PUNTO 8: Check /usr/share/alicia scripts
    log_info "Validating alicia shared scripts..."
    local share_files=("tool-store.sh" "system-info.sh")
    for sfile in "${share_files[@]}"; do
        if proot-distro login "${ALICIA_DEFAULT_PROOT_DISTRO}" -- test -x "/usr/share/alicia/${sfile}" 2>/dev/null; then
            printf "  ${COLOR_GREEN}[OK]${COLOR_RESET} /usr/share/alicia/%s\n" "${sfile}"
        else
            printf "  ${COLOR_RED}[FAIL]${COLOR_RESET} /usr/share/alicia/%s NOT FOUND\n" "${sfile}"
            ((cmd_failures++)) || true
        fi
    done

    if [[ ${cmd_failures} -gt 0 ]]; then
        ((failures++)) || true
    fi

    # Check scripts are executable on Termux side
    log_info "Validating Termux-side scripts..."
    local script_failures=0
    for script in "${SCRIPT_DIR}"/*.sh; do
        if [[ ! -x "${script}" ]]; then
            chmod +x "${script}" 2>/dev/null || {
                ((script_failures++)) || true
            }
        fi
    done
    for script in "${SETUP_DIR}"/*.sh; do
        if [[ ! -x "${script}" ]]; then
            chmod +x "${script}" 2>/dev/null || {
                ((script_failures++)) || true
            }
        fi
    done

    if [[ ${script_failures} -eq 0 ]]; then
        printf "  ${COLOR_GREEN}[OK]${COLOR_RESET} Termux-side scripts\n"
    else
        printf "  ${COLOR_YELLOW}[WARN]${COLOR_RESET} %d script permission issue(s)\n" "${script_failures}"
    fi

    # Check Termux aliases were added
    if grep -q 'alicia-start' "${HOME}/.bashrc" 2>/dev/null; then
        printf "  ${COLOR_GREEN}[OK]${COLOR_RESET} Termux aliases in .bashrc\n"
    else
        printf "  ${COLOR_YELLOW}[WARN]${COLOR_RESET} Termux aliases not in .bashrc\n"
    fi

    # Mark as installed
    alicia_set_state "alicia_installed" "true"
    alicia_set_state "alicia_version" "${ALICIA_VERSION}"
    alicia_set_state "install_completed" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    echo ""
    if [[ ${failures} -gt 0 ]]; then
        printf "  ${COLOR_RED}Validation: %d issue(s) found${COLOR_RESET}\n" "${failures}"
        return 1
    fi

    printf "  ${COLOR_BOLD_GREEN}Validation: ALL CHECKS PASSED${COLOR_RESET}\n"
    return 0
}

# ============================================================================
# Installation Summary
# ============================================================================
show_installation_summary() {
    local end_time
    end_time=$(date +%s)
    local start_epoch
    start_epoch=$(date -d "${INSTALL_START_TIME}" +%s 2>/dev/null || echo 0)
    local duration=0
    if [[ ${start_epoch} -gt 0 ]]; then
        duration=$((end_time - start_epoch))
    fi

    local duration_str
    if [[ ${duration} -ge 60 ]]; then
        duration_str="$((duration / 60))m $((duration % 60))s"
    else
        duration_str="${duration}s"
    fi

    echo ""
    log_separator "=" 55
    printf "${COLOR_BOLD_GREEN}  Installation Complete!${COLOR_RESET}\n"
    log_separator "=" 55
    echo ""
    printf "  ${COLOR_BOLD_WHITE}Installation Summary:${COLOR_RESET}\n"
    printf "  %-25s %s\n" "Version:" "${ALICIA_VERSION} (${ALICIA_CODENAME})"
    printf "  %-25s %s\n" "Duration:" "${duration_str}"
    printf "  %-25s %s\n" "Distribution:" "${ALICIA_DEFAULT_PROOT_DISTRO}"
    printf "  %-25s %s\n" "Desktop:" "${ALICIA_DEFAULT_DESKTOP_ENV}"
    printf "  %-25s %s\n" "VNC Port:" "${ALICIA_DEFAULT_VNC_PORT}"
    printf "  %-25s %s\n" "Resolution:" "${ALICIA_DEFAULT_VNC_RESOLUTION}"
    printf "  %-25s %s\n" "Install Log:" "${LOG_FILE}"
    echo ""

    printf "  ${COLOR_BOLD_WHITE}Steps Completed:${COLOR_RESET}\n"
    for step in "${COMPLETED_STEPS[@]}"; do
        local num="${step%%:*}"
        local status="${step##*:}"
        case "${status}" in
            OK)     printf "    ${COLOR_GREEN}+${COLOR_RESET} Step %s: %s\n" "${num}" "${status}" ;;
            SKIPPED) printf "    ${COLOR_YELLOW}o${COLOR_RESET} Step %s: %s\n" "${num}" "${status}" ;;
            *)      printf "    ${COLOR_RED}x${COLOR_RESET} Step %s: %s\n" "${num}" "${status}" ;;
        esac
    done
    echo ""
}

# ============================================================================
# First-Run Instructions
# ============================================================================
show_first_run_instructions() {
    echo ""
    log_separator "=" 55
    printf "${COLOR_BOLD_CYAN}  Getting Started${COLOR_RESET}\n"
    log_separator "=" 55
    echo ""
    printf "  ${COLOR_BOLD_WHITE}1. Start Alicia:${COLOR_RESET}\n"
    printf "     ${COLOR_CYAN}./scripts/start.sh${COLOR_RESET}\n"
    echo ""
    printf "  ${COLOR_BOLD_WHITE}2. Connect via VNC:${COLOR_RESET}\n"
    printf "     ${COLOR_CYAN}Address:${COLOR_RESET}  localhost:${ALICIA_DEFAULT_VNC_PORT}\n"
    printf "     ${COLOR_CYAN}Password:${COLOR_RESET}  alicia\n"
    echo ""
    printf "  ${COLOR_BOLD_WHITE}3. Configure settings:${COLOR_RESET}\n"
    printf "     ${COLOR_CYAN}./scripts/config.sh${COLOR_RESET}\n"
    echo ""
    printf "  ${COLOR_BOLD_WHITE}4. Check status:${COLOR_RESET}\n"
    printf "     ${COLOR_CYAN}./scripts/status.sh${COLOR_RESET}\n"
    echo ""
    printf "  ${COLOR_BOLD_WHITE}5. Stop Alicia:${COLOR_RESET}\n"
    printf "     ${COLOR_CYAN}./scripts/stop.sh${COLOR_RESET}\n"
    echo ""
    printf "  ${COLOR_BOLD_WHITE}6. Enable watchdog (auto-recovery):${COLOR_RESET}\n"
    printf "     ${COLOR_CYAN}./scripts/watchdog.sh --daemonize${COLOR_RESET}\n"
    echo ""
    printf "  ${COLOR_DIM}Documentation: https://github.com/${ALICIA_GITHUB_REPO}${COLOR_RESET}\n"
    printf "  ${COLOR_DIM}Support:        https://github.com/${ALICIA_GITHUB_REPO}/issues${COLOR_RESET}\n"
    echo ""
    log_separator "=" 55
    printf "\n"
}

# ============================================================================
# Main Installation Flow
# ============================================================================
main() {
    parse_args "$@"

    # Record start time
    INSTALL_START_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    # Show welcome banner
    if [[ "${UNATTENDED}" != "true" ]]; then
        show_welcome_banner
    else
        log_info "Starting unattended installation of Alicia v${ALICIA_VERSION}"
    fi

    log_section "Alicia Desktop Environment Installation"
    log_info "Version: ${ALICIA_VERSION} (${ALICIA_CODENAME})"
    log_info "Mode: $([[ "${UNATTENDED}" == "true" ]] && echo "Unattended" || echo "Interactive")"
    log_timer_start "installation"

    # Step 0: License agreement
    show_license

    # Step 1: Prerequisite checks
    if ! run_prerequisite_checks; then
        log_error "Prerequisite checks failed -- cannot continue installation"
        if [[ "${UNATTENDED}" != "true" ]]; then
            ui_show_error "Installation Error" \
                "Prerequisite checks failed.\nCheck the log for details:\n${LOG_FILE}"
        fi
        exit 1
    fi

    # Step 2: Create installation log header
    {
        echo "============================================================================"
        echo "Alicia Desktop Environment Installation Log"
        echo "Version: ${ALICIA_VERSION}"
        echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "Mode: $([[ "${UNATTENDED}" == "true" ]] && echo "Unattended" || echo "Interactive")"
        echo "Skipped Steps: ${SKIP_STEPS[*]:-none}"
        echo "============================================================================"
        echo ""
    } >> "${LOG_FILE}" 2>/dev/null

    # Step 3: Run setup scripts
    if ! run_all_setup_scripts; then
        # Installation failed -- attempt rollback
        perform_rollback
        log_timer_end "installation"
        exit 1
    fi

    # Step 4: Post-installation validation
    validate_installation || true

    # Step 5: Make all scripts executable
    log_info "Setting script permissions..."
    chmod +x "${SCRIPT_DIR}"/*.sh 2>/dev/null || true
    chmod +x "${SETUP_DIR}"/*.sh 2>/dev/null || true

    # PUNTO 3: Source .bashrc to load alicia aliases
    log_info "Reloading shell aliases..."
    source "${HOME}/.bashrc" 2>/dev/null || true
    log_info "Alicia commands are now available. Run 'source ~/.bashrc' or open a new session."

    # Step 6: Show summary and instructions
    log_timer_end "installation"

    show_installation_summary

    if [[ "${UNATTENDED}" != "true" ]]; then
        show_first_run_instructions
    else
        log_info "Unattended installation complete"
        log_info "Run './scripts/start.sh' to start Alicia"
    fi

    return 0
}

# ============================================================================
# Execute Main
# ============================================================================
main "$@"
