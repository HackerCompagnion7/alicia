#!/bin/bash
# ============================================================================
# alicia-core.sh - Alicia Desktop Environment Core Library
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
# Description:  Core library providing version management, path constants,
#               state management, action/command dispatch, process management,
#               dependency checking, configuration parsing, lock management,
#               signal handling, atomic operations, checksums, archives,
#               template engine, and environment validation.
# ============================================================================

# set -euo pipefail removed for library sourcing safety

# ============================================================================
# Guard against double-sourcing
# ============================================================================
if [[ -n "${_ALICIA_CORE_LOADED:-}" && -z "${_ALICIA_FORCE_RELOAD:-}" ]]; then
    return 0
fi
_ALICIA_CORE_LOADED=1

# ============================================================================
# Safe readonly helper - avoids errors if variable already declared readonly
# (e.g. by install.sh fallback or a previous partial source)
# ============================================================================
_alicia_safe_readonly() {
    local varname="$1" varval="$2"
    if [[ -z "${!varname+_}" ]]; then
        readonly "$varname=$varval"
    fi
}

# ============================================================================
# Version Constants
# ============================================================================
_alicia_safe_readonly ALICIA_VERSION "3.1.0"
_alicia_safe_readonly ALICIA_CODENAME "Tomorrow"
_alicia_safe_readonly ALICIA_VERSION_MAJOR 3
_alicia_safe_readonly ALICIA_VERSION_MINOR 1
_alicia_safe_readonly ALICIA_VERSION_PATCH 0
_alicia_safe_readonly ALICIA_BUILD_DATE "$(date -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo 'unknown')"
_alicia_safe_readonly ALICIA_LICENSE "GPL-3.0-or-later"
_alicia_safe_readonly ALICIA_VENDOR "Proyecto Tomorrow"

# ============================================================================
# Path Constants
# ============================================================================
_alicia_safe_readonly ALICIA_HOME "${ALICIA_HOME:-$HOME/.alicia}"
_alicia_safe_readonly ALICIA_LIB_DIR "${ALICIA_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
_alicia_safe_readonly ALICIA_BIN_DIR "${ALICIA_HOME}/bin"
_alicia_safe_readonly ALICIA_CONFIG_DIR "${ALICIA_CONFIG_DIR:-${ALICIA_HOME}/config}"
_alicia_safe_readonly ALICIA_DATA_DIR "${ALICIA_DATA_DIR:-${ALICIA_HOME}/data}"
_alicia_safe_readonly ALICIA_CACHE_DIR "${ALICIA_CACHE_DIR:-${ALICIA_HOME}/cache}"
_alicia_safe_readonly ALICIA_PROOT_DIR "${ALICIA_PROOT_DIR:-${ALICIA_HOME}/proot}"
_alicia_safe_readonly ALICIA_ROOTFS_DIR "${ALICIA_ROOTFS_DIR:-${ALICIA_HOME}/rootfs}"
_alicia_safe_readonly ALICIA_LOG_DIR "${ALICIA_LOG_DIR:-${ALICIA_HOME}/logs}"
_alicia_safe_readonly ALICIA_TMP_DIR "${ALICIA_TMP_DIR:-${ALICIA_HOME}/tmp}"
_alicia_safe_readonly ALICIA_LOCK_DIR "${ALICIA_LOCK_DIR:-${ALICIA_HOME}/locks}"
_alicia_safe_readonly ALICIA_STATE_DIR "${ALICIA_STATE_DIR:-${ALICIA_HOME}/state}"
_alicia_safe_readonly ALICIA_BACKUP_DIR "${ALICIA_BACKUP_DIR:-${ALICIA_HOME}/backups}"
_alicia_safe_readonly ALICIA_DOWNLOAD_DIR "${ALICIA_DOWNLOAD_DIR:-${ALICIA_HOME}/downloads}"
_alicia_safe_readonly ALICIA_WALLPAPER_DIR "${ALICIA_WALLPAPER_DIR:-${ALICIA_HOME}/wallpapers}"
_alicia_safe_readonly ALICIA_THEME_DIR "${ALICIA_THEME_DIR:-${ALICIA_HOME}/themes}"
_alicia_safe_readonly ALICIA_ICON_DIR "${ALICIA_ICON_DIR:-${ALICIA_HOME}/icons}"
_alicia_safe_readonly ALICIA_FONT_DIR "${ALICIA_FONT_DIR:-${ALICIA_HOME}/fonts}"
_alicia_safe_readonly ALICIA_PLUGIN_DIR "${ALICIA_PLUGIN_DIR:-${ALICIA_HOME}/plugins}"
_alicia_safe_readonly ALICIA_LOCALE_DIR "${ALICIA_LOCALE_DIR:-${ALICIA_HOME}/locale}"
_alicia_safe_readonly ALICIA_CERT_DIR "${ALICIA_CERT_DIR:-${ALICIA_HOME}/certs}"

# ============================================================================
# Default Configuration Constants
# ============================================================================
_alicia_safe_readonly ALICIA_DEFAULT_VNC_PORT 5901
_alicia_safe_readonly ALICIA_DEFAULT_VNC_RESOLUTION "1280x720"
_alicia_safe_readonly ALICIA_DEFAULT_DESKTOP_ENV "xfce4"
_alicia_safe_readonly ALICIA_DEFAULT_PROOT_DISTRO "alpine"
_alicia_safe_readonly ALICIA_DEFAULT_PROOT_RELEASE "bookworm"
_alicia_safe_readonly ALICIA_DEFAULT_PROOT_ARCH "arm64"
_alicia_safe_readonly ALICIA_DEFAULT_DISPLAY ":1"
_alicia_safe_readonly ALICIA_DEFAULT_SHELL "/bin/bash"
_alicia_safe_readonly ALICIA_DEFAULT_USER "alicia"
_alicia_safe_readonly ALICIA_DEFAULT_LANG "en_US.UTF-8"
_alicia_safe_readonly ALICIA_DEFAULT_TIMEZONE "UTC"
_alicia_safe_readonly ALICIA_DEFAULT_KEYBOARD "us"
_alicia_safe_readonly ALICIA_MIN_RAM_MB 2048
_alicia_safe_readonly ALICIA_MIN_STORAGE_MB 4096
_alicia_safe_readonly ALICIA_MAX_LOG_SIZE $((10 * 1024 * 1024))  # 10 MB
_alicia_safe_readonly ALICIA_MAX_LOG_FILES 5
_alicia_safe_readonly ALICIA_LOCK_TIMEOUT 300  # 5 minutes
_alicia_safe_readonly ALICIA_DOWNLOAD_RETRIES 3
_alicia_safe_readonly ALICIA_DOWNLOAD_TIMEOUT 300  # 5 minutes
_alicia_safe_readonly ALICIA_CONNECTIVITY_TEST_URL "https://www.google.com"
_alicia_safe_readonly ALICIA_GITHUB_API "https://api.github.com"
_alicia_safe_readonly ALICIA_GITHUB_REPO "proyecto-tomorrow/alicia"
unset -f _alicia_safe_readonly

# ============================================================================
# Internal State Variables
# ============================================================================
declare -gA _ALICIA_ACTION_HANDLERS=()
declare -gA _ALICIA_STATE_CACHE=()
declare -gA _ALICIA_CONFIG_CACHE=()
declare -ga _ALICIA_CLEANUP_HANDLERS=()
declare -g  _ALICIA_CURRENT_LOCK=""
declare -g  _ALICIA_INITIALIZED=0
declare -g  _ALICIA_CONFIG_FILE="${ALICIA_CONFIG_DIR}/alicia.conf"
declare -gA _ALICIA_DEPS_REQUIRED=()

# ============================================================================
# Directory Initialization
# ============================================================================

# Initialize all required directories with proper permissions.
# Returns: 0 on success, 1 on failure.
alicia_init_directories() {
    local dirs=(
        "${ALICIA_HOME}"
        "${ALICIA_BIN_DIR}"
        "${ALICIA_CONFIG_DIR}"
        "${ALICIA_DATA_DIR}"
        "${ALICIA_CACHE_DIR}"
        "${ALICIA_PROOT_DIR}"
        "${ALICIA_ROOTFS_DIR}"
        "${ALICIA_LOG_DIR}"
        "${ALICIA_TMP_DIR}"
        "${ALICIA_LOCK_DIR}"
        "${ALICIA_STATE_DIR}"
        "${ALICIA_BACKUP_DIR}"
        "${ALICIA_DOWNLOAD_DIR}"
        "${ALICIA_WALLPAPER_DIR}"
        "${ALICIA_THEME_DIR}"
        "${ALICIA_ICON_DIR}"
        "${ALICIA_FONT_DIR}"
        "${ALICIA_PLUGIN_DIR}"
        "${ALICIA_LOCALE_DIR}"
        "${ALICIA_CERT_DIR}"
    )

    local dir
    for dir in "${dirs[@]}"; do
        if [[ ! -d "${dir}" ]]; then
            if ! mkdir -p "${dir}" 2>/dev/null; then
                echo "ERROR: Failed to create directory: ${dir}" >&2
                return 1
            fi
            chmod 700 "${dir}" 2>/dev/null || true
        fi
    done

    _ALICIA_INITIALIZED=1
    return 0
}

# ============================================================================
# Version Comparison Utilities
# ============================================================================

# Compare two semver version strings.
# Arguments: $1 - version_a, $2 - operator (eq, ne, lt, le, gt, ge), $3 - version_b
# Returns: 0 if comparison is true, 1 if false.
alicia_version_compare() {
    local ver_a="$1"
    local op="$2"
    local ver_b="$3"

    if [[ -z "${ver_a}" || -z "${ver_b}" || -z "${op}" ]]; then
        echo "ERROR: version_compare requires three arguments: version_a operator version_b" >&2
        return 2
    fi

    # Strip leading 'v' if present
    ver_a="${ver_a#v}"
    ver_b="${ver_b#v}"

    # Parse version components
    IFS='.' read -ra parts_a <<< "${ver_a%%-*}"
    IFS='.' read -ra parts_b <<< "${ver_b%%-*}"

    local major_a="${parts_a[0]:-0}" minor_a="${parts_a[1]:-0}" patch_a="${parts_a[2]:-0}"
    local major_b="${parts_b[0]:-0}" minor_b="${parts_b[1]:-0}" patch_b="${parts_b[2]:-0}"

    # Numeric comparison using arithmetic
    local num_a=$(( major_a * 1000000 + minor_a * 1000 + patch_a ))
    local num_b=$(( major_b * 1000000 + minor_b * 1000 + patch_b ))

    case "${op}" in
        eq|==|=)  [[ ${num_a} -eq ${num_b} ]] ;;
        ne|!=)    [[ ${num_a} -ne ${num_b} ]] ;;
        lt|'<')   [[ ${num_a} -lt ${num_b} ]] ;;
        le|'<=')  [[ ${num_a} -le ${num_b} ]] ;;
        gt|'>')   [[ ${num_a} -gt ${num_b} ]] ;;
        ge|'>=')  [[ ${num_a} -ge ${num_b} ]] ;;
        *)
            echo "ERROR: Unknown comparison operator: ${op}" >&2
            return 2
            ;;
    esac
}

# Get the full version string with codename.
# Output: "3.1.0 (Tomorrow)"
alicia_get_version() {
    echo "${ALICIA_VERSION} (${ALICIA_CODENAME})"
}

# ============================================================================
# State Management
# ============================================================================

# Get a state value by key.
# Arguments: $1 - state key
# Output: state value (empty string if not found)
alicia_get_state() {
    local key="$1"

    if [[ -z "${key}" ]]; then
        echo "ERROR: get_state requires a key argument" >&2
        return 1
    fi

    # Check memory cache first
    if [[ -n "${_ALICIA_STATE_CACHE[${key}]+_}" ]]; then
        echo "${_ALICIA_STATE_CACHE[${key}]}"
        return 0
    fi

    # Fall back to file-based state
    local state_file="${ALICIA_STATE_DIR}/${key}.state"
    if [[ -f "${state_file}" ]]; then
        local value
        value=$(cat "${state_file}" 2>/dev/null || echo "")
        _ALICIA_STATE_CACHE["${key}"]="${value}"
        echo "${value}"
        return 0
    fi

    echo ""
    return 1
}

# Set a state value by key.
# Arguments: $1 - state key, $2 - state value
# Returns: 0 on success, 1 on failure.
alicia_set_state() {
    local key="$1"
    local value="$2"

    if [[ -z "${key}" ]]; then
        echo "ERROR: set_state requires a key argument" >&2
        return 1
    fi

    # Validate key format (alphanumeric, underscore, hyphen only)
    if ! [[ "${key}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "ERROR: Invalid state key format: ${key}" >&2
        return 1
    fi

    # Update memory cache
    _ALICIA_STATE_CACHE["${key}"]="${value}"

    # Persist to file
    local state_file="${ALICIA_STATE_DIR}/${key}.state"
    if ! alicia_atomic_write "${state_file}" "${value}"; then
        echo "ERROR: Failed to persist state: ${key}" >&2
        return 1
    fi

    return 0
}

# Check if a service/component is currently running.
# Arguments: $1 - component name
# Returns: 0 if running, 1 if not running.
alicia_is_running() {
    local component="$1"

    if [[ -z "${component}" ]]; then
        echo "ERROR: is_running requires a component argument" >&2
        return 1
    fi

    local pid_file="${ALICIA_STATE_DIR}/${component}.pid"
    if [[ -f "${pid_file}" ]]; then
        local pid
        pid=$(cat "${pid_file}" 2>/dev/null || echo "")
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            return 0
        fi
        # Stale PID file; clean it up
        rm -f "${pid_file}" 2>/dev/null || true
    fi

    return 1
}

# Check if a component is installed.
# Arguments: $1 - component name
# Returns: 0 if installed, 1 if not installed.
alicia_is_installed() {
    local component="$1"

    if [[ -z "${component}" ]]; then
        echo "ERROR: is_installed requires a component argument" >&2
        return 1
    fi

    local marker="${ALICIA_STATE_DIR}/${component}.installed"
    [[ -f "${marker}" ]]
}

# Mark a component as installed.
# Arguments: $1 - component name, $2 - version (optional)
alicia_mark_installed() {
    local component="$1"
    local version="${2:-unknown}"

    if [[ -z "${component}" ]]; then
        echo "ERROR: mark_installed requires a component argument" >&2
        return 1
    fi

    local marker="${ALICIA_STATE_DIR}/${component}.installed"
    alicia_atomic_write "${marker}" "version=${version}"$'\n'"installed_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

# Check if a component is configured.
# Arguments: $1 - component name
# Returns: 0 if configured, 1 if not configured.
alicia_is_configured() {
    local component="$1"

    if [[ -z "${component}" ]]; then
        return 1
    fi

    local marker="${ALICIA_STATE_DIR}/${component}.configured"
    [[ -f "${marker}" ]]
}

# Mark a component as configured.
# Arguments: $1 - component name
alicia_mark_configured() {
    local component="$1"

    if [[ -z "${component}" ]]; then
        return 1
    fi

    local marker="${ALICIA_STATE_DIR}/${component}.configured"
    alicia_atomic_write "${marker}" "configured_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

# ============================================================================
# Action / Command Pattern
# ============================================================================

# Register an action handler for a named action.
# Arguments: $1 - action name, $2 - handler function name
# Returns: 0 on success, 1 on failure.
alicia_register_action_handler() {
    local action="$1"
    local handler="$2"

    if [[ -z "${action}" || -z "${handler}" ]]; then
        echo "ERROR: register_action_handler requires action and handler arguments" >&2
        return 1
    fi

    # Validate the handler is a callable function
    if ! declare -f "${handler}" >/dev/null 2>&1; then
        echo "ERROR: Handler function '${handler}' is not defined" >&2
        return 1
    fi

    _ALICIA_ACTION_HANDLERS["${action}"]="${handler}"
    return 0
}

# Dispatch an action by name with optional arguments.
# Arguments: $1 - action name, $@ remaining args passed to handler
# Returns: handler return code, or 1 if no handler registered.
alicia_dispatch_action() {
    local action="$1"
    shift

    if [[ -z "${action}" ]]; then
        echo "ERROR: dispatch_action requires an action argument" >&2
        return 1
    fi

    local handler="${_ALICIA_ACTION_HANDLERS[${action}]:-}"
    if [[ -z "${handler}" ]]; then
        echo "ERROR: No handler registered for action: ${action}" >&2
        return 1
    fi

    "${handler}" "$@"
}

# List all registered action handlers.
# Output: one "action:handler" pair per line.
alicia_list_actions() {
    local action
    for action in "${!_ALICIA_ACTION_HANDLERS[@]}"; do
        echo "${action}:${_ALICIA_ACTION_HANDLERS[${action}]}"
    done
}

# Execute a command inside the proot environment (engine command).
# Arguments: $@ - command and arguments to execute
# Returns: command exit code, or 1 if proot not available.
alicia_execute_engine_command() {
    if [[ $# -eq 0 ]]; then
        echo "ERROR: execute_engine_command requires at least one argument" >&2
        return 1
    fi

    # Source system library if available
    if [[ -f "${ALICIA_LIB_DIR}/alicia-system.sh" ]]; then
        # shellcheck source=alicia-system.sh
        source "${ALICIA_LIB_DIR}/alicia-system.sh"
        if alicia_proot_is_running; then
            alicia_proot_exec "$@"
            return $?
        fi
    fi

    echo "ERROR: proot environment is not running" >&2
    return 1
}

# ============================================================================
# Process Management
# ============================================================================

# Start a background process and record its PID.
# Arguments: $1 - process name, $2... - command and arguments
# Returns: 0 on success, 1 on failure.
alicia_start_process() {
    local name="$1"
    shift

    if [[ -z "${name}" || $# -eq 0 ]]; then
        echo "ERROR: start_process requires a name and command" >&2
        return 1
    fi

    # Check if already running
    if alicia_is_running "${name}"; then
        echo "WARN: Process '${name}' is already running" >&2
        return 0
    fi

    # Launch the process in the background
    "$@" &
    local pid=$!
    local pid_file="${ALICIA_STATE_DIR}/${name}.pid"

    # Brief sleep to detect immediate failures
    sleep 0.5
    if ! kill -0 "${pid}" 2>/dev/null; then
        echo "ERROR: Process '${name}' failed to start" >&2
        rm -f "${pid_file}" 2>/dev/null || true
        return 1
    fi

    echo "${pid}" > "${pid_file}"
    alicia_set_state "${name}_pid" "${pid}"
    alicia_set_state "${name}_started" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    return 0
}

# Stop a managed process by name.
# Arguments: $1 - process name, $2 - signal (default: TERM), $3 - timeout (default: 30)
# Returns: 0 on success, 1 on failure.
alicia_stop_process() {
    local name="$1"
    local signal="${2:-TERM}"
    local timeout="${3:-30}"

    if [[ -z "${name}" ]]; then
        echo "ERROR: stop_process requires a process name" >&2
        return 1
    fi

    local pid_file="${ALICIA_STATE_DIR}/${name}.pid"
    if [[ ! -f "${pid_file}" ]]; then
        return 0  # Not running is not an error
    fi

    local pid
    pid=$(cat "${pid_file}" 2>/dev/null || echo "")
    if [[ -z "${pid}" ]]; then
        rm -f "${pid_file}" 2>/dev/null || true
        return 0
    fi

    # Send the initial signal
    if ! kill -s "${signal}" "${pid}" 2>/dev/null; then
        rm -f "${pid_file}" 2>/dev/null || true
        return 0  # Process already dead
    fi

    # Wait for the process to exit
    local elapsed=0
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if ! kill -0 "${pid}" 2>/dev/null; then
            rm -f "${pid_file}" 2>/dev/null || true
            alicia_set_state "${name}_stopped" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    # Force kill if still running
    if kill -0 "${pid}" 2>/dev/null; then
        kill -9 "${pid}" 2>/dev/null || true
        sleep 0.5
    fi

    rm -f "${pid_file}" 2>/dev/null || true
    alicia_set_state "${name}_stopped" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    return 0
}

# Restart a managed process.
# Arguments: $1 - process name, $2... - command and arguments
alicia_restart_process() {
    local name="$1"
    shift

    alicia_stop_process "${name}" "TERM" 15
    sleep 1
    alicia_start_process "${name}" "$@"
}

# Check if a managed process is alive.
# Arguments: $1 - process name
# Returns: 0 if alive, 1 if not.
alicia_check_process() {
    alicia_is_running "$1"
}

# Get the PID of a managed process.
# Arguments: $1 - process name
# Output: PID number or empty string.
alicia_get_pid() {
    local name="$1"

    if [[ -z "${name}" ]]; then
        return 1
    fi

    local pid_file="${ALICIA_STATE_DIR}/${name}.pid"
    if [[ -f "${pid_file}" ]]; then
        cat "${pid_file}" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# ============================================================================
# Dependency Checking
# ============================================================================

# Register a required dependency.
# Arguments: $1 - dependency name, $2 - package name (optional, defaults to $1)
alicia_require_dependency() {
    local name="$1"
    local package="${2:-$1}"

    if [[ -z "${name}" ]]; then
        echo "ERROR: require_dependency requires a name argument" >&2
        return 1
    fi

    _ALICIA_DEPS_REQUIRED["${name}"]="${package}"
}

# Check if a single dependency is available.
# Arguments: $1 - command/dependency name
# Returns: 0 if available, 1 if not.
alicia_check_dependency() {
    local dep="$1"

    if [[ -z "${dep}" ]]; then
        return 1
    fi

    # Try command -v first (works for executables, functions, aliases, builtins)
    if command -v "${dep}" >/dev/null 2>&1; then
        return 0
    fi

    # Try type as fallback
    if type "${dep}" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Check all registered dependencies.
# Output: lists missing dependencies.
# Returns: 0 if all present, 1 if any missing.
alicia_check_all_dependencies() {
    local missing=0
    local dep package

    for dep in "${!_ALICIA_DEPS_REQUIRED[@]}"; do
        package="${_ALICIA_DEPS_REQUIRED[${dep}]}"
        if ! alicia_check_dependency "${dep}"; then
            echo "MISSING: ${dep} (package: ${package})"
            ((missing++))
        fi
    done

    if [[ ${missing} -gt 0 ]]; then
        echo "Total missing dependencies: ${missing}"
        return 1
    fi

    return 0
}

# Install a dependency via available package manager.
# Arguments: $1 - package name
# Returns: 0 on success, 1 on failure.
alicia_install_dependency() {
    local package="$1"

    if [[ -z "${package}" ]]; then
        echo "ERROR: install_dependency requires a package name" >&2
        return 1
    fi

    # Try Termux pkg first
    if command -v pkg >/dev/null 2>&1; then
        pkg install -y "${package}" && return 0
    fi

    # Try apt inside proot
    if command -v apt >/dev/null 2>&1; then
        apt install -y "${package}" && return 0
    fi

    # Try dnf
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y "${package}" && return 0
    fi

    # Try pacman
    if command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm "${package}" && return 0
    fi

    echo "ERROR: No supported package manager found to install: ${package}" >&2
    return 1
}

# ============================================================================
# Configuration File Parser
# ============================================================================

# Parse a configuration file into the config cache.
# The format supports: key=value, key = value, # comments, blank lines.
# Sections are supported as [section_name] which prefixes keys as section.key.
# Arguments: $1 - config file path (optional, defaults to $_ALICIA_CONFIG_FILE)
# Returns: 0 on success, 1 on failure.
alicia_parse_config() {
    local config_file="${1:-${_ALICIA_CONFIG_FILE}}"

    if [[ ! -f "${config_file}" ]]; then
        echo "ERROR: Configuration file not found: ${config_file}" >&2
        return 1
    fi

    local current_section=""
    local line_num=0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_num++)) || true

        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty lines and comments
        [[ -z "${line}" || "${line}" == \#* ]] && continue

        # Section header
        if [[ "${line}" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        # Key = Value parsing
        if [[ "${line}" =~ ^([a-zA-Z0-9_.-]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Remove trailing comments from value
            value="${value%%#*}"
            value="${value%"${value##*[![:space:]]}"}"

            # Remove surrounding quotes if present
            if [[ "${value}" =~ ^\"(.*)\"$ ]] || [[ "${value}" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            # Prefix with section if inside one
            if [[ -n "${current_section}" ]]; then
                key="${current_section}.${key}"
            fi

            _ALICIA_CONFIG_CACHE["${key}"]="${value}"
        else
            echo "WARN: Invalid config line ${line_num}: ${line}" >&2
        fi
    done < "${config_file}"

    return 0
}

# Get a configuration value.
# Arguments: $1 - key, $2 - default value (optional)
# Output: configuration value or default.
alicia_get_config_value() {
    local key="$1"
    local default="${2:-}"

    if [[ -z "${key}" ]]; then
        echo "${default}"
        return 1
    fi

    # Check environment variable override first (ALICIA_CFG_<KEY>)
    local env_key="ALICIA_CFG_$(echo "${key}" | tr '[:lower:].' '[:upper:]__')"
    if [[ -n "${!env_key:-}" ]]; then
        echo "${!env_key}"
        return 0
    fi

    # Check cache
    if [[ -n "${_ALICIA_CONFIG_CACHE[${key}]+_}" ]]; then
        echo "${_ALICIA_CONFIG_CACHE[${key}]}"
        return 0
    fi

    echo "${default}"
    return 1
}

# Set a configuration value in the cache (and optionally persist).
# Arguments: $1 - key, $2 - value, $3 - persist (true/false, default false)
alicia_set_config_value() {
    local key="$1"
    local value="$2"
    local persist="${3:-false}"

    if [[ -z "${key}" ]]; then
        echo "ERROR: set_config_value requires a key argument" >&2
        return 1
    fi

    _ALICIA_CONFIG_CACHE["${key}"]="${value}"

    if [[ "${persist}" == "true" ]]; then
        local config_file="${_ALICIA_CONFIG_FILE}"
        if [[ ! -f "${config_file}" ]]; then
            mkdir -p "$(dirname "${config_file}")" 2>/dev/null || true
            touch "${config_file}" 2>/dev/null || true
        fi

        # Use sed to replace or append
        if rg -q "^${key}=" "${config_file}" 2>/dev/null; then
            local escaped_value
            escaped_value=$(printf '%s\n' "${value}" | sed 's/[&/\]/\\&/g')
            sed -i "s|^${key}=.*|${key}=${escaped_value}|" "${config_file}"
        else
            echo "${key}=${value}" >> "${config_file}"
        fi
    fi

    return 0
}

# Validate configuration against required keys.
# Arguments: $@ - required key names
# Returns: 0 if all present, 1 if any missing.
alicia_validate_config() {
    local missing=0
    local key

    for key in "$@"; do
        if [[ -z "${_ALICIA_CONFIG_CACHE[${key}]+_}" ]]; then
            echo "MISSING CONFIG: ${key}"
            ((missing++))
        fi
    done

    [[ ${missing} -eq 0 ]]
}

# ============================================================================
# Lock File Management
# ============================================================================

# Acquire an exclusive lock.
# Arguments: $1 - lock name, $2 - timeout in seconds (default: ALICIA_LOCK_TIMEOUT)
# Returns: 0 on success, 1 on failure/timeout.
alicia_lock_acquire() {
    local name="$1"
    local timeout="${2:-${ALICIA_LOCK_TIMEOUT}}"

    if [[ -z "${name}" ]]; then
        echo "ERROR: lock_acquire requires a name argument" >&2
        return 1
    fi

    local lock_file="${ALICIA_LOCK_DIR}/${name}.lock"
    local elapsed=0

    while [[ ${elapsed} -lt ${timeout} ]]; do
        # Attempt to create lock file atomically
        if (set -o noclobber; echo "$$" > "${lock_file}") 2>/dev/null; then
            _ALICIA_CURRENT_LOCK="${name}"
            # Write lock metadata
            printf 'pid=%s\ntime=%s\nhost=%s\n' "$$" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(hostname 2>/dev/null || echo 'unknown')" > "${lock_file}"
            return 0
        fi

        # Check if the lock is stale (older than timeout)
        if [[ -f "${lock_file}" ]]; then
            local lock_age
            lock_age=$(( $(date +%s) - $(stat -c %Y "${lock_file}" 2>/dev/null || echo 0) ))
            if [[ ${lock_age} -gt ${timeout} ]]; then
                rm -f "${lock_file}" 2>/dev/null || true
                continue
            fi
        fi

        sleep 1
        ((elapsed++))
    done

    echo "ERROR: Failed to acquire lock '${name}' within ${timeout}s" >&2
    return 1
}

# Release a held lock.
# Arguments: $1 - lock name
alicia_lock_release() {
    local name="$1"

    if [[ -z "${name}" ]]; then
        return 1
    fi

    local lock_file="${ALICIA_LOCK_DIR}/${name}.lock"
    if [[ -f "${lock_file}" ]]; then
        # Verify we own the lock
        local lock_pid
        lock_pid=$(head -1 "${lock_file}" 2>/dev/null | cut -d= -f2 || echo "")
        if [[ -z "${lock_pid}" || "${lock_pid}" == "$$" ]]; then
            rm -f "${lock_file}" 2>/dev/null || true
        fi
    fi

    if [[ "${_ALICIA_CURRENT_LOCK}" == "${name}" ]]; then
        _ALICIA_CURRENT_LOCK=""
    fi
}

# Check if a lock is currently held.
# Arguments: $1 - lock name
# Returns: 0 if locked, 1 if not.
alicia_lock_is_held() {
    local name="$1"
    local lock_file="${ALICIA_LOCK_DIR}/${name}.lock"
    [[ -f "${lock_file}" ]]
}

# ============================================================================
# Signal Handling and Cleanup
# ============================================================================

# Register a cleanup handler to be called on exit.
# Arguments: $1 - cleanup function name
alicia_register_cleanup() {
    local handler="$1"

    if [[ -z "${handler}" ]]; then
        return 1
    fi

    _ALICIA_CLEANUP_HANDLERS+=("${handler}")
}

# Execute all registered cleanup handlers (called on EXIT trap).
alicia_run_cleanup() {
    local handler
    for handler in "${_ALICIA_CLEANUP_HANDLERS[@]}"; do
        if declare -f "${handler}" >/dev/null 2>&1; then
            "${handler}" 2>/dev/null || true
        fi
    done

    # Release any held locks
    if [[ -n "${_ALICIA_CURRENT_LOCK}" ]]; then
        alicia_lock_release "${_ALICIA_CURRENT_LOCK}"
    fi
}

# Set up standard signal handlers.
alicia_setup_signal_handlers() {
    trap 'alicia_run_cleanup' EXIT
    trap 'alicia_handle_signal INT' INT
    trap 'alicia_handle_signal TERM' TERM
    trap 'alicia_handle_signal HUP' HUP
}

# Handle a caught signal gracefully.
# Arguments: $1 - signal name
alicia_handle_signal() {
    local sig="$1"
    echo "Received SIG${sig}, performing graceful shutdown..." >&2
    alicia_run_cleanup
    exit $((128 + $(kill -l "${sig}" 2>/dev/null || echo 1) ))
}

# ============================================================================
# Atomic File Operations
# ============================================================================

# Write content to a file atomically using a temp file + rename.
# Arguments: $1 - target file path, $2 - content to write
# Returns: 0 on success, 1 on failure.
alicia_atomic_write() {
    local target="$1"
    local content="$2"

    if [[ -z "${target}" ]]; then
        echo "ERROR: atomic_write requires a target path" >&2
        return 1
    fi

    local target_dir
    target_dir=$(dirname "${target}")

    # Ensure directory exists
    if [[ ! -d "${target_dir}" ]]; then
        mkdir -p "${target_dir}" 2>/dev/null || {
            echo "ERROR: Cannot create directory: ${target_dir}" >&2
            return 1
        }
    fi

    # Write to a temporary file on the same filesystem
    local tmp_file
    tmp_file=$(mktemp "${target_dir}/.alicia_atomic_XXXXXX" 2>/dev/null) || {
        echo "ERROR: Failed to create temp file in: ${target_dir}" >&2
        return 1
    }

    # Write content and sync
    if ! printf '%s' "${content}" > "${tmp_file}"; then
        rm -f "${tmp_file}" 2>/dev/null || true
        echo "ERROR: Failed to write content to temp file" >&2
        return 1
    fi

    # Set permissions before moving
    chmod 600 "${tmp_file}" 2>/dev/null || true

    # Atomic move (rename)
    if ! mv -f "${tmp_file}" "${target}" 2>/dev/null; then
        rm -f "${tmp_file}" 2>/dev/null || true
        echo "ERROR: Failed to move temp file to target: ${target}" >&2
        return 1
    fi

    return 0
}

# Move/rename a file atomically.
# Arguments: $1 - source path, $2 - destination path
# Returns: 0 on success, 1 on failure.
alicia_atomic_move() {
    local source="$1"
    local dest="$2"

    if [[ -z "${source}" || -z "${dest}" ]]; then
        echo "ERROR: atomic_move requires source and destination" >&2
        return 1
    fi

    if [[ ! -f "${source}" ]]; then
        echo "ERROR: Source file does not exist: ${source}" >&2
        return 1
    fi

    local dest_dir
    dest_dir=$(dirname "${dest}")
    [[ -d "${dest_dir}" ]] || mkdir -p "${dest_dir}" 2>/dev/null || {
        echo "ERROR: Cannot create destination directory: ${dest_dir}" >&2
        return 1
    }

    mv -f "${source}" "${dest}"
}

# Delete a file atomically (rename to temp then delete).
# Arguments: $1 - file path
# Returns: 0 on success, 1 on failure.
alicia_atomic_delete() {
    local target="$1"

    if [[ -z "${target}" ]]; then
        return 1
    fi

    if [[ ! -f "${target}" ]]; then
        return 0  # Already gone is not an error
    fi

    local target_dir
    target_dir=$(dirname "${target}")

    # Rename first so readers lose reference
    local tmp_file
    tmp_file=$(mktemp -u "${target_dir}/.alicia_delete_XXXXXX" 2>/dev/null) || {
        # Fall back to direct delete
        rm -f "${target}"
        return $?
    }

    mv -f "${target}" "${tmp_file}" 2>/dev/null && rm -f "${tmp_file}" 2>/dev/null
}

# ============================================================================
# Checksum Verification
# ============================================================================

# Compute a checksum for a file.
# Arguments: $1 - file path, $2 - algorithm (sha256, sha512, md5; default: sha256)
# Output: checksum string.
alicia_compute_checksum() {
    local file="$1"
    local algorithm="${2:-sha256}"

    if [[ ! -f "${file}" ]]; then
        echo "ERROR: File not found: ${file}" >&2
        return 1
    fi

    case "${algorithm}" in
        sha256)
            sha256sum "${file}" 2>/dev/null | awk '{print $1}'
            ;;
        sha512)
            sha512sum "${file}" 2>/dev/null | awk '{print $1}'
            ;;
        md5)
            md5sum "${file}" 2>/dev/null | awk '{print $1}'
            ;;
        *)
            echo "ERROR: Unsupported checksum algorithm: ${algorithm}" >&2
            return 1
            ;;
    esac
}

# Verify a file against an expected checksum.
# Arguments: $1 - file path, $2 - expected checksum, $3 - algorithm (default: sha256)
# Returns: 0 if match, 1 if mismatch.
alicia_verify_checksum() {
    local file="$1"
    local expected="$2"
    local algorithm="${3:-sha256}"

    if [[ -z "${expected}" ]]; then
        echo "ERROR: Expected checksum not provided" >&2
        return 1
    fi

    local actual
    actual=$(alicia_compute_checksum "${file}" "${algorithm}") || return 1

    if [[ "${actual}" == "${expected}" ]]; then
        return 0
    fi

    echo "ERROR: Checksum mismatch for ${file}" >&2
    echo "  Expected: ${expected}" >&2
    echo "  Actual:   ${actual}" >&2
    return 1
}

# ============================================================================
# Archive Extraction with Progress
# ============================================================================

# Extract an archive, detecting type by extension.
# Supports: .tar.gz, .tar.bz2, .tar.xz, .tar.zst, .tar, .zip, .gz, .7z
# Arguments: $1 - archive path, $2 - destination directory (default: .)
# Returns: 0 on success, 1 on failure.
alicia_extract_archive() {
    local archive="$1"
    local dest="${2:-.}"

    if [[ ! -f "${archive}" ]]; then
        echo "ERROR: Archive not found: ${archive}" >&2
        return 1
    fi

    # Create destination if it doesn't exist
    mkdir -p "${dest}" 2>/dev/null || {
        echo "ERROR: Cannot create destination: ${dest}" >&2
        return 1
    }

    local archive_size
    archive_size=$(stat -c %s "${archive}" 2>/dev/null || echo "0")
    echo "Extracting: ${archive} ($(( archive_size / 1024 / 1024 )) MB) -> ${dest}"

    case "${archive,,}" in
        *.tar.gz|*.tgz)
            tar -xzf "${archive}" -C "${dest}" --checkpoint=.1000 2>&1 || {
                echo "ERROR: Failed to extract tar.gz archive" >&2
                return 1
            }
            ;;
        *.tar.bz2|*.tbz2)
            tar -xjf "${archive}" -C "${dest}" --checkpoint=.1000 2>&1 || {
                echo "ERROR: Failed to extract tar.bz2 archive" >&2
                return 1
            }
            ;;
        *.tar.xz|*.txz)
            tar -xJf "${archive}" -C "${dest}" --checkpoint=.1000 2>&1 || {
                echo "ERROR: Failed to extract tar.xz archive" >&2
                return 1
            }
            ;;
        *.tar.zst)
            tar --zstd -xf "${archive}" -C "${dest}" --checkpoint=.1000 2>&1 || {
                echo "ERROR: Failed to extract tar.zst archive" >&2
                return 1
            }
            ;;
        *.tar)
            tar -xf "${archive}" -C "${dest}" --checkpoint=.1000 2>&1 || {
                echo "ERROR: Failed to extract tar archive" >&2
                return 1
            }
            ;;
        *.zip)
            if command -v unzip >/dev/null 2>&1; then
                unzip -qo "${archive}" -d "${dest}" || {
                    echo "ERROR: Failed to extract zip archive" >&2
                    return 1
                }
            else
                echo "ERROR: unzip is not installed" >&2
                return 1
            fi
            ;;
        *.gz)
            local filename
            filename=$(basename "${archive}" .gz)
            gunzip -c "${archive}" > "${dest}/${filename}" || {
                echo "ERROR: Failed to extract gz file" >&2
                return 1
            }
            ;;
        *.7z)
            if command -v 7z >/dev/null 2>&1; then
                7z x "${archive}" -o"${dest}" -y || {
                    echo "ERROR: Failed to extract 7z archive" >&2
                    return 1
                }
            else
                echo "ERROR: 7z is not installed" >&2
                return 1
            fi
            ;;
        *)
            echo "ERROR: Unsupported archive format: ${archive}" >&2
            return 1
            ;;
    esac

    echo "Extraction complete: ${archive}"
    return 0
}

# ============================================================================
# Template Engine
# ============================================================================

# Render a template file, replacing {{VARIABLE}} placeholders with values.
# Arguments: $1 - template file path, $2 - output file path
# Environment variables and _ALICIA_CONFIG_CACHE are used for substitution.
# Returns: 0 on success, 1 on failure.
alicia_render_template() {
    local template_file="$1"
    local output_file="$2"

    if [[ ! -f "${template_file}" ]]; then
        echo "ERROR: Template file not found: ${template_file}" >&2
        return 1
    fi

    if [[ -z "${output_file}" ]]; then
        echo "ERROR: Output file path required" >&2
        return 1
    fi

    local content
    content=$(cat "${template_file}") || return 1

    # Replace environment variable placeholders: {{VAR_NAME}}
    local var_name var_value
    while [[ "${content}" =~ \{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\} ]]; do
        var_name="${BASH_REMATCH[1]}"
        # Check environment first, then config cache
        var_value="${!var_name:-}"
        if [[ -z "${var_value}" && -n "${_ALICIA_CONFIG_CACHE[${var_name}]+_}" ]]; then
            var_value="${_ALICIA_CONFIG_CACHE[${var_name}]}"
        fi
        # Replace all occurrences of this placeholder
        content="${content//\{\{${var_name}\}\}/${var_value}}"
    done

    # Also support {{section.key}} syntax from config cache
    while [[ "${content}" =~ \{\{([a-zA-Z0-9_]+\.[a-zA-Z0-9_]+)\}\} ]]; do
        var_name="${BASH_REMATCH[1]}"
        var_value="${_ALICIA_CONFIG_CACHE[${var_name}]:-}"
        content="${content//\{\{${var_name}\}\}/${var_value}}"
    done

    # Write output atomically
    alicia_atomic_write "${output_file}" "${content}"
}

# Render a template string (not from a file).
# Arguments: $1 - template string
# Output: rendered string.
alicia_render_template_string() {
    local content="$1"

    # Replace environment variable placeholders
    local var_name var_value
    while [[ "${content}" =~ \{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\} ]]; do
        var_name="${BASH_REMATCH[1]}"
        var_value="${!var_name:-}"
        if [[ -z "${var_value}" && -n "${_ALICIA_CONFIG_CACHE[${var_name}]+_}" ]]; then
            var_value="${_ALICIA_CONFIG_CACHE[${var_name}]}"
        fi
        content="${content//\{\{${var_name}\}\}/${var_value}}"
    done

    echo "${content}"
}

# ============================================================================
# Environment Validation
# ============================================================================

# Check if running inside Termux.
# Returns: 0 if Termux, 1 if not.
alicia_check_termux() {
    [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]] || [[ -n "${TERMUX_APK_RELEASE:-}" ]]
}

# Check Android version information.
# Output: Android version string or "unknown".
alicia_check_android_version() {
    if [[ -f "/system/build.prop" ]]; then
        local version
        version=$(grep -m1 "^ro.build.version.release=" /system/build.prop 2>/dev/null | cut -d= -f2 || echo "unknown")
        echo "${version}"
    elif command -v getprop >/dev/null 2>&1; then
        getprop ro.build.version.release 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Check if storage permission is granted (Termux-specific).
# Returns: 0 if storage is accessible, 1 if not.
alicia_check_storage() {
    # Check if the shared storage directory is accessible
    if [[ -d "${HOME}/storage" ]]; then
        return 0
    fi

    # Check if we can write to the primary storage
    local storage_path="/storage/emulated/0"
    if [[ -d "${storage_path}" ]] && [[ -w "${storage_path}" ]]; then
        return 0
    fi

    return 1
}

# Check available RAM.
# Output: available RAM in MB.
alicia_check_ram() {
    local ram_mb=0

    if [[ -f "/proc/meminfo" ]]; then
        local mem_available
        mem_available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo "0")
        ram_mb=$((mem_available / 1024))
    elif command -v free >/dev/null 2>&1; then
        ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}' || echo "0")
    fi

    echo "${ram_mb}"
}

# Check if minimum RAM requirements are met.
# Arguments: $1 - minimum RAM in MB (default: ALICIA_MIN_RAM_MB)
# Returns: 0 if sufficient, 1 if insufficient.
alicia_check_min_ram() {
    local min_ram="${1:-${ALICIA_MIN_RAM_MB}}"
    local available_ram
    available_ram=$(alicia_check_ram)

    if [[ ${available_ram} -ge ${min_ram} ]]; then
        return 0
    fi

    echo "ERROR: Insufficient RAM. Required: ${min_ram}MB, Available: ${available_ram}MB" >&2
    return 1
}

# Check available disk space.
# Arguments: $1 - path to check (default: ALICIA_HOME)
# Output: available space in MB.
alicia_check_disk_space() {
    local path="${1:-${ALICIA_HOME}}"

    if [[ ! -d "${path}" ]]; then
        mkdir -p "${path}" 2>/dev/null || path="${HOME}"
    fi

    df -m "${path}" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0"
}

# Check if minimum disk space requirements are met.
# Arguments: $1 - minimum space in MB (default: ALICIA_MIN_STORAGE_MB)
# Returns: 0 if sufficient, 1 if insufficient.
alicia_check_min_disk() {
    local min_space="${1:-${ALICIA_MIN_STORAGE_MB}}"
    local available
    available=$(alicia_check_disk_space)

    if [[ ${available} -ge ${min_space} ]]; then
        return 0
    fi

    echo "ERROR: Insufficient disk space. Required: ${min_space}MB, Available: ${available}MB" >&2
    return 1
}

# Run full environment validation.
# Output: validation report.
# Returns: 0 if all checks pass, 1 if any fail.
alicia_validate_environment() {
    local passed=0
    local failed=0

    echo "=== Alicia Environment Validation ==="
    echo ""

    # Termux check
    if alicia_check_termux; then
        echo "[PASS] Running in Termux"
        ((passed++)) || true
    else
        echo "[WARN] Not running in Termux (some features may be unavailable)"
        ((passed++)) || true
    fi

    # Android version
    local android_ver
    android_ver=$(alicia_check_android_version)
    echo "[INFO] Android version: ${android_ver}"
    ((passed++)) || true

    # Storage
    if alicia_check_storage; then
        echo "[PASS] Storage access granted"
        ((passed++)) || true
    else
        echo "[FAIL] Storage access not granted (run 'termux-setup-storage')"
        ((failed++)) || true
    fi

    # RAM
    local ram
    ram=$(alicia_check_ram)
    if [[ ${ram} -ge ${ALICIA_MIN_RAM_MB} ]]; then
        echo "[PASS] RAM: ${ram}MB (minimum: ${ALICIA_MIN_RAM_MB}MB)"
        ((passed++)) || true
    else
        echo "[FAIL] RAM: ${ram}MB (minimum: ${ALICIA_MIN_RAM_MB}MB)"
        ((failed++)) || true
    fi

    # Disk space
    local disk
    disk=$(alicia_check_disk_space)
    if [[ ${disk} -ge ${ALICIA_MIN_STORAGE_MB} ]]; then
        echo "[PASS] Disk space: ${disk}MB (minimum: ${ALICIA_MIN_STORAGE_MB}MB)"
        ((passed++)) || true
    else
        echo "[FAIL] Disk space: ${disk}MB (minimum: ${ALICIA_MIN_STORAGE_MB}MB)"
        ((failed++)) || true
    fi

    # Core dependencies
    local dep
    for dep in proot proot-distro; do
        if alicia_check_dependency "${dep}"; then
            echo "[PASS] Dependency: ${dep}"
            ((passed++)) || true
        else
            echo "[FAIL] Dependency: ${dep} (not found)"
            ((failed++)) || true
        fi
    done

    echo ""
    echo "=== Results: ${passed} passed, ${failed} failed ==="

    [[ ${failed} -eq 0 ]]
}

# ============================================================================
# Utility Functions
# ============================================================================

# Generate a random alphanumeric string.
# Arguments: $1 - length (default: 16)
# Output: random string.
alicia_random_string() {
    local length="${1:-16}"
    tr -dc 'a-zA-Z0-9' < /dev/urandom 2>/dev/null | head -c "${length}" || echo ""
}

# Check if a function exists.
# Arguments: $1 - function name
# Returns: 0 if exists, 1 if not.
alicia_function_exists() {
    declare -f "$1" >/dev/null 2>&1
}

# Ensure the script runs as root (inside proot) or show an error.
# Returns: 0 if root, 1 if not.
alicia_require_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        return 0
    fi
    echo "ERROR: This operation requires root privileges" >&2
    return 1
}

# Prompt for user confirmation.
# Arguments: $1 - prompt message
# Returns: 0 if confirmed, 1 if declined.
alicia_confirm() {
    local message="${1:-Are you sure?}"
    local response

    read -r -p "${message} [y/N]: " response
    case "${response,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

# ============================================================================
# Library Initialization
# ============================================================================

# Initialize the core library: set up directories, signal handlers, and
# optionally parse the default configuration file.
alicia_core_init() {
    # Create directories
    alicia_init_directories || return 1

    # Set up signal handlers
    alicia_setup_signal_handlers

    # Parse default config if it exists
    if [[ -f "${_ALICIA_CONFIG_FILE}" ]]; then
        alicia_parse_config "${_ALICIA_CONFIG_FILE}" || true
    fi

    return 0
}

# Auto-initialize if not in a sourced-interactive context
if [[ -z "${ALICIA_NO_AUTO_INIT:-}" ]]; then
    alicia_core_init || true
fi
