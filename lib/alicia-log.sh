#!/bin/bash
# ============================================================================
# alicia-log.sh - Alicia Desktop Environment Logging Library
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
# Description:  Comprehensive logging library with multiple output targets,
#               log rotation, color-coded console output, structured logging,
#               performance timing, and log analysis capabilities.
# ============================================================================

# set -euo pipefail removed for library sourcing safety

if [[ -n "${_ALICIA_LOG_LOADED:-}" ]]; then
    return 0
fi
_ALICIA_LOG_LOADED=1

# ============================================================================
# Log Level Constants
# ============================================================================
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_CRITICAL=4
readonly LOG_LEVEL_SILENT=5

# ============================================================================
# Color Constants for Console Output
# ============================================================================
readonly COLOR_RESET='\033[0m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_DIM='\033[2m'
readonly COLOR_UNDERLINE='\033[4m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_MAGENTA='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[0;37m'
readonly COLOR_BOLD_RED='\033[1;31m'
readonly COLOR_BOLD_GREEN='\033[1;32m'
readonly COLOR_BOLD_YELLOW='\033[1;33m'
readonly COLOR_BOLD_BLUE='\033[1;34m'
readonly COLOR_BOLD_MAGENTA='\033[1;35m'
readonly COLOR_BOLD_CYAN='\033[1;36m'
readonly COLOR_BG_RED='\033[41m'
readonly COLOR_BG_YELLOW='\033[43m'

# ============================================================================
# Default Log Configuration
# ============================================================================
: "${ALICIA_LOG_DIR:="${ALICIA_HOME:-$HOME/alicia}/logs"}"
: "${ALICIA_LOG_FILE:="${ALICIA_LOG_DIR}/alicia.log"}"
: "${ALICIA_LOG_LEVEL:=$LOG_LEVEL_INFO}"
: "${ALICIA_LOG_MAX_SIZE:=10485760}"           # 10MB
: "${ALICIA_LOG_MAX_FILES:=5}"
: "${ALICIA_LOG_BUFFER_SIZE:=0}"
: "${ALICIA_LOG_CONSOLE:=1}"
: "${ALICIA_LOG_FILE_OUTPUT:=1}"
: "${ALICIA_LOG_TIMESTAMP_FORMAT:="%Y-%m-%d %H:%M:%S"}"
: "${ALICIA_LOG_SHOW_MODULE:=1}"
: "${ALICIA_LOG_SHOW_FUNCTION:=1}"
: "${ALICIA_LOG_SHOW_LINE:=0}"
: "${ALICIA_LOG_COLOR:=1}"

# ============================================================================
# Internal State
# ============================================================================
_ALICIA_LOG_BUFFER=()
_ALICIA_LOG_CURRENT_MODULE="main"
_ALICIA_LOG_TIMERS=()
_ALICIA_LOG_INITIALIZED=0
_ALICIA_LOG_SECTIONS=()

# ============================================================================
# log_init - Initialize the logging system
# ============================================================================
log_init() {
    local log_dir="${1:-$ALICIA_LOG_DIR}"
    local log_file="${2:-$ALICIA_LOG_FILE}"

    # Create log directory
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            echo "ERROR: Cannot create log directory: $log_dir" >&2
            return 1
        }
    fi

    ALICIA_LOG_DIR="$log_dir"
    ALICIA_LOG_FILE="$log_file"

    # Initialize log file
    if [[ ! -f "$ALICIA_LOG_FILE" ]]; then
        {
            echo "#============================================================================"
            echo "# Alicia Desktop Environment Log File"
            echo "# Created: $(date "+$ALICIA_LOG_TIMESTAMP_FORMAT")"
            echo "# Version: ${ALICIA_VERSION:-3.1.0}"
            echo "#============================================================================"
            echo ""
        } > "$ALICIA_LOG_FILE"
    fi

    _ALICIA_LOG_INITIALIZED=1

    # Perform log rotation check on init
    _log_rotate_check

    return 0
}

# ============================================================================
# log_set_module - Set the current module name for logging context
# ============================================================================
log_set_module() {
    local module="${1:-main}"
    _ALICIA_LOG_CURRENT_MODULE="$module"
}

# ============================================================================
# log_get_module - Get the current module name
# ============================================================================
log_get_module() {
    echo "$_ALICIA_LOG_CURRENT_MODULE"
}

# ============================================================================
# _log_level_to_string - Convert numeric level to string
# ============================================================================
_log_level_to_string() {
    local level="$1"
    case "$level" in
        $LOG_LEVEL_DEBUG)   echo "DEBUG"    ;;
        $LOG_LEVEL_INFO)    echo "INFO"     ;;
        $LOG_LEVEL_WARN)    echo "WARN"     ;;
        $LOG_LEVEL_ERROR)   echo "ERROR"    ;;
        $LOG_LEVEL_CRITICAL) echo "CRITICAL" ;;
        $LOG_LEVEL_SILENT)  echo "SILENT"   ;;
        *)                   echo "UNKNOWN" ;;
    esac
}

# ============================================================================
# _log_level_to_color - Get color code for a log level
# ============================================================================
_log_level_to_color() {
    local level="$1"
    case "$level" in
        $LOG_LEVEL_DEBUG)   echo "$COLOR_DIM"        ;;
        $LOG_LEVEL_INFO)    echo "$COLOR_GREEN"       ;;
        $LOG_LEVEL_WARN)    echo "$COLOR_YELLOW"      ;;
        $LOG_LEVEL_ERROR)   echo "$COLOR_RED"         ;;
        $LOG_LEVEL_CRITICAL) echo "$COLOR_BOLD_RED"   ;;
        *)                   echo "$COLOR_RESET"      ;;
    esac
}

# ============================================================================
# _log_format_message - Format a log message with timestamp, level, etc.
# ============================================================================
_log_format_message() {
    local level="$1"
    local message="$2"
    local caller_func="${3:-unknown}"
    local caller_line="${4:-0}"
    local timestamp
    timestamp=$(date "+$ALICIA_LOG_TIMESTAMP_FORMAT")
    local level_str
    level_str=$(_log_level_to_string "$level")

    local formatted="[$timestamp] [$level_str]"

    if [[ "$ALICIA_LOG_SHOW_MODULE" == "1" ]]; then
        formatted+=" [$_ALICIA_LOG_CURRENT_MODULE]"
    fi

    if [[ "$ALICIA_LOG_SHOW_FUNCTION" == "1" ]]; then
        formatted+=" [$caller_func"
        if [[ "$ALICIA_LOG_SHOW_LINE" == "1" ]]; then
            formatted+=":$caller_line"
        fi
        formatted+="]"
    fi

    formatted+=" $message"
    echo "$formatted"
}

# ============================================================================
# _log_write - Internal function to write a log message
# ============================================================================
_log_write() {
    local level="$1"
    local message="$2"
    local caller_func="${3:-${FUNCNAME[2]:-unknown}}"
    local caller_line="${4:-${BASH_LINENO[1]:-0}}"

    # Check if we should log at this level
    if [[ $level -lt $ALICIA_LOG_LEVEL ]]; then
        return 0
    fi

    local formatted
    formatted=$(_log_format_message "$level" "$message" "$caller_func" "$caller_line")

    # Buffer or write immediately
    if [[ $ALICIA_LOG_BUFFER_SIZE -gt 0 ]]; then
        _ALICIA_LOG_BUFFER+=("$formatted")
        if [[ ${#_ALICIA_LOG_BUFFER[@]} -ge $ALICIA_LOG_BUFFER_SIZE ]]; then
            log_flush
        fi
    else
        _log_write_targets "$formatted" "$level"
    fi
}

# ============================================================================
# _log_write_targets - Write formatted message to all configured targets
# ============================================================================
_log_write_targets() {
    local formatted="$1"
    local level="$2"

    # Console output
    if [[ "$ALICIA_LOG_CONSOLE" == "1" ]]; then
        if [[ "$ALICIA_LOG_COLOR" == "1" && -t 2 ]]; then
            local color
            color=$(_log_level_to_color "$level")
            local level_str
            level_str=$(_log_level_to_string "$level")

            # For CRITICAL, add background color
            if [[ $level -ge $LOG_LEVEL_CRITICAL ]]; then
                printf "${COLOR_BG_RED}${COLOR_BOLD}%s${COLOR_RESET}\n" "$formatted" >&2
            elif [[ $level -ge $LOG_LEVEL_ERROR ]]; then
                printf "${color}%s${COLOR_RESET}\n" "$formatted" >&2
            else
                printf "${color}%s${COLOR_RESET}\n" "$formatted" >&2
            fi
        else
            echo "$formatted" >&2
        fi
    fi

    # File output
    if [[ "$ALICIA_LOG_FILE_OUTPUT" == "1" && -n "${ALICIA_LOG_FILE:-}" ]]; then
        if [[ "$_ALICIA_LOG_INITIALIZED" == "1" ]]; then
            # Strip ANSI codes for file output
            local clean_formatted
            clean_formatted=$(echo "$formatted" | sed 's/\x1b\[[0-9;]*m//g')
            echo "$clean_formatted" >> "$ALICIA_LOG_FILE"

            # Check rotation after write
            _log_rotate_check
        fi
    fi
}

# ============================================================================
# Public Logging Functions
# ============================================================================

# log_debug - Log a debug message
log_debug() {
    local message="$*"
    _log_write $LOG_LEVEL_DEBUG "$message" "${FUNCNAME[1]:-unknown}" "${BASH_LINENO[0]:-0}"
}

# log_info - Log an info message
log_info() {
    local message="$*"
    _log_write $LOG_LEVEL_INFO "$message" "${FUNCNAME[1]:-unknown}" "${BASH_LINENO[0]:-0}"
}

# log_warn - Log a warning message
log_warn() {
    local message="$*"
    _log_write $LOG_LEVEL_WARN "$message" "${FUNCNAME[1]:-unknown}" "${BASH_LINENO[0]:-0}"
}

# log_error - Log an error message
log_error() {
    local message="$*"
    _log_write $LOG_LEVEL_ERROR "$message" "${FUNCNAME[1]:-unknown}" "${BASH_LINENO[0]:-0}"
}

# log_critical - Log a critical message
log_critical() {
    local message="$*"
    _log_write $LOG_LEVEL_CRITICAL "$message" "${FUNCNAME[1]:-unknown}" "${BASH_LINENO[0]:-0}"
}

# ============================================================================
# Structured Logging
# ============================================================================

# log_structured - Log with key-value pairs for structured analysis
log_structured() {
    local level="$1"
    shift
    local message="$1"
    shift
    local pairs=("$@")

    local kv_string=""
    for pair in "${pairs[@]}"; do
        if [[ "$pair" == *"="* ]]; then
            kv_string+=" [$pair]"
        fi
    done

    local full_message="${message}${kv_string}"
    _log_write "$level" "$full_message" "${FUNCNAME[1]:-unknown}" "${BASH_LINENO[0]:-0}"
}

# ============================================================================
# Progress Logging
# ============================================================================

# log_progress - Log a progress indicator
log_progress() {
    local current="$1"
    local total="$2"
    local description="${3:-Progress}"
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="#"; done
    for ((i = 0; i < empty; i++)); do bar+="-"; done

    local progress_line="${description}: [${bar}] ${percentage}% (${current}/${total})"

    if [[ "$ALICIA_LOG_CONSOLE" == "1" && -t 2 ]]; then
        printf "\r${COLOR_CYAN}%s${COLOR_RESET}" "$progress_line" >&2
        if [[ $current -eq $total ]]; then
            printf "\n" >&2
        fi
    fi
}

# ============================================================================
# Performance Timing
# ============================================================================

# log_timer_start - Start a named timer
log_timer_start() {
    local timer_name="${1:-default}"
    local description="${2:-}"
    _ALICIA_LOG_TIMERS[$timer_name]="$(date +%s%N)"
    if [[ -n "$description" ]]; then
        log_debug "Timer started: $timer_name - $description"
    fi
}

# log_timer_end - End a named timer and log the duration
log_timer_end() {
    local timer_name="${1:-default}"
    local end_time
    end_time=$(date +%s%N)

    if [[ -z "${_ALICIA_LOG_TIMERS[$timer_name]:-}" ]]; then
        log_warn "Timer not found: $timer_name"
        return 1
    fi

    local start_time="${_ALICIA_LOG_TIMERS[$timer_name]}"
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    local duration_s=$(echo "scale=3; $duration_ns / 1000000000" | bc 2>/dev/null || echo "0")

    local duration_display
    if [[ $duration_ms -lt 1000 ]]; then
        duration_display="${duration_ms}ms"
    else
        duration_display="${duration_s}s"
    fi

    log_info "Timer completed: $timer_name - Duration: $duration_display"
    unset '_ALICIA_LOG_TIMERS[$timer_name]'
    return 0
}

# ============================================================================
# Section and Subsection Logging
# ============================================================================

# log_section - Log a major section header
log_section() {
    local title="$1"
    _ALICIA_LOG_SECTIONS+=("$title")
    local separator="========================================================================"
    local padded_title="  $title  "
    local total_width=${#separator}
    local title_width=${#padded_title}
    local side_width=$(((total_width - title_width) / 2))

    local line=""
    for ((i = 0; i < side_width; i++)); do line+="="; done
    line+="$padded_title"
    for ((i = 0; i < side_width; i++)); do line+="="; done

    _log_write $LOG_LEVEL_INFO "$separator" "log_section" "0"
    _log_write $LOG_LEVEL_INFO "$line" "log_section" "0"
    _log_write $LOG_LEVEL_INFO "$separator" "log_section" "0"
}

# log_subsection - Log a subsection header
log_subsection() {
    local title="$1"
    local line="-------- $title --------"
    _log_write $LOG_LEVEL_INFO "$line" "log_subsection" "0"
}

# ============================================================================
# Log Buffer Management
# ============================================================================

# log_flush - Flush buffered log messages
log_flush() {
    if [[ ${#_ALICIA_LOG_BUFFER[@]} -eq 0 ]]; then
        return 0
    fi

    for message in "${_ALICIA_LOG_BUFFER[@]}"; do
        echo "$message" >> "$ALICIA_LOG_FILE"
    done

    _ALICIA_LOG_BUFFER=()
    return 0
}

# ============================================================================
# Log Rotation
# ============================================================================

# _log_rotate_check - Check if log rotation is needed
_log_rotate_check() {
    if [[ ! -f "${ALICIA_LOG_FILE:-}" ]]; then
        return 0
    fi

    local file_size
    file_size=$(stat -f%z "$ALICIA_LOG_FILE" 2>/dev/null || stat -c%s "$ALICIA_LOG_FILE" 2>/dev/null || echo 0)

    if [[ $file_size -ge $ALICIA_LOG_MAX_SIZE ]]; then
        _log_rotate
    fi
}

# _log_rotate - Perform log rotation
_log_rotate() {
    log_debug "Performing log rotation (max files: $ALICIA_LOG_MAX_FILES)"

    # Delete oldest log file
    if [[ -f "${ALICIA_LOG_FILE}.${ALICIA_LOG_MAX_FILES}.gz" ]]; then
        rm -f "${ALICIA_LOG_FILE}.${ALICIA_LOG_MAX_FILES}.gz"
    fi

    # Rotate existing log files
    for ((i = ALICIA_LOG_MAX_FILES - 1; i >= 1; i--)); do
        local next=$((i + 1))
        if [[ -f "${ALICIA_LOG_FILE}.${i}.gz" ]]; then
            mv "${ALICIA_LOG_FILE}.${i}.gz" "${ALICIA_LOG_FILE}.${next}.gz"
        fi
    done

    # Compress current log file
    if command -v gzip &>/dev/null; then
        gzip -c "$ALICIA_LOG_FILE" > "${ALICIA_LOG_FILE}.1.gz" 2>/dev/null
    else
        cp "$ALICIA_LOG_FILE" "${ALICIA_LOG_FILE}.1"
    fi

    # Truncate current log file (preserve inode)
    : > "$ALICIA_LOG_FILE"

    # Write rotation header
    {
        echo "#============================================================================"
        echo "# Log rotated at: $(date "+$ALICIA_LOG_TIMESTAMP_FORMAT")"
        echo "#============================================================================"
    } >> "$ALICIA_LOG_FILE"
}

# ============================================================================
# Log Analysis Functions
# ============================================================================

# log_count_errors - Count error and critical messages in current log
log_count_errors() {
    local log_file="${1:-$ALICIA_LOG_FILE}"
    if [[ ! -f "$log_file" ]]; then
        echo "0"
        return 0
    fi
    grep -cE '\[ERROR\]|\[CRITICAL\]' "$log_file" 2>/dev/null || echo "0"
}

# log_get_last_error - Get the last error message from log
log_get_last_error() {
    local log_file="${1:-$ALICIA_LOG_FILE}"
    local count="${2:-1}"
    if [[ ! -f "$log_file" ]]; then
        echo "No log file found"
        return 1
    fi
    grep -E '\[ERROR\]|\[CRITICAL\]' "$log_file" | tail -n "$count"
}

# log_search - Search log file for a pattern
log_search() {
    local pattern="$1"
    local log_file="${2:-$ALICIA_LOG_FILE}"
    if [[ ! -f "$log_file" ]]; then
        echo "No log file found"
        return 1
    fi
    grep -i "$pattern" "$log_file" | tail -n 50
}

# log_get_stats - Get log statistics
log_get_stats() {
    local log_file="${1:-$ALICIA_LOG_FILE}"
    if [[ ! -f "$log_file" ]]; then
        echo "No log file found"
        return 1
    fi

    local total_lines
    total_lines=$(wc -l < "$log_file")
    local debug_count
    debug_count=$(grep -c "\[DEBUG\]" "$log_file" 2>/dev/null || echo 0)
    local info_count
    info_count=$(grep -c "\[INFO\]" "$log_file" 2>/dev/null || echo 0)
    local warn_count
    warn_count=$(grep -c "\[WARN\]" "$log_file" 2>/dev/null || echo 0)
    local error_count
    error_count=$(grep -c "\[ERROR\]" "$log_file" 2>/dev/null || echo 0)
    local critical_count
    critical_count=$(grep -c "\[CRITICAL\]" "$log_file" 2>/dev/null || echo 0)

    echo "Log Statistics for: $log_file"
    echo "  Total lines:   $total_lines"
    echo "  DEBUG:         $debug_count"
    echo "  INFO:          $info_count"
    echo "  WARN:          $warn_count"
    echo "  ERROR:         $error_count"
    echo "  CRITICAL:      $critical_count"
    echo "  File size:     $(du -h "$log_file" | cut -f1)"
}

# log_clear - Clear the current log file
log_clear() {
    local log_file="${1:-$ALICIA_LOG_FILE}"
    if [[ -f "$log_file" ]]; then
        : > "$log_file"
        {
            echo "#============================================================================"
            echo "# Log cleared at: $(date "+$ALICIA_LOG_TIMESTAMP_FORMAT")"
            echo "#============================================================================"
        } >> "$log_file"
    fi
}

# ============================================================================
# Specialized Logging Helpers
# ============================================================================

# log_command_output - Log the output of a command
log_command_output() {
    local description="$1"
    shift
    local cmd=("$@")

    log_debug "Executing: $description"
    local output
    output=$("${cmd[@]}" 2>&1) || true
    while IFS= read -r line; do
        log_debug "  | $line"
    done <<< "$output"
}

# log_variable - Log a variable's name and value (for debugging)
log_variable() {
    local var_name="$1"
    local var_value="${!var_name:-<unset>}"
    log_debug "Variable: $var_name = '$var_value'"
}

# log_array - Log an array's contents (for debugging)
log_array() {
    local array_name="$1"
    shift
    local elements=("$@")
    log_debug "Array: $array_name (${#elements[@]} elements)"
    for i in "${!elements[@]}"; do
        log_debug "  [$i] = '${elements[$i]}'"
    done
}

# log_function_entry - Log function entry (for tracing)
log_function_entry() {
    local func_name="${1:-${FUNCNAME[1]:-unknown}}"
    local args="${*:2}"
    log_debug ">> ENTER: $func_name($args)"
}

# log_function_exit - Log function exit (for tracing)
log_function_exit() {
    local func_name="${1:-${FUNCNAME[1]:-unknown}}"
    local return_code="${2:-0}"
    log_debug "<< EXIT: $func_name (rc=$return_code)"
}

# log_separator - Log a visual separator line
log_separator() {
    local char="${1:--}"
    local width="${2:-72}"
    local line=""
    for ((i = 0; i < width; i++)); do line+="$char"; done
    _log_write $LOG_LEVEL_INFO "$line" "log_separator" "0"
}

# ============================================================================
# Log Level Configuration
# ============================================================================

# log_set_level - Set the logging verbosity level
log_set_level() {
    local level_name="$1"
    case "${level_name^^}" in
        DEBUG)    ALICIA_LOG_LEVEL=$LOG_LEVEL_DEBUG   ;;
        INFO)     ALICIA_LOG_LEVEL=$LOG_LEVEL_INFO     ;;
        WARN)     ALICIA_LOG_LEVEL=$LOG_LEVEL_WARN     ;;
        ERROR)    ALICIA_LOG_LEVEL=$LOG_LEVEL_ERROR    ;;
        CRITICAL) ALICIA_LOG_LEVEL=$LOG_LEVEL_CRITICAL ;;
        SILENT)   ALICIA_LOG_LEVEL=$LOG_LEVEL_SILENT   ;;
        *)
            log_warn "Unknown log level: $level_name (using INFO)"
            ALICIA_LOG_LEVEL=$LOG_LEVEL_INFO
            ;;
    esac
}

# log_set_verbosity - Set verbosity from a numeric value (0-4)
log_set_verbosity() {
    local verbosity="${1:-1}"
    case "$verbosity" in
        0) ALICIA_LOG_LEVEL=$LOG_LEVEL_DEBUG    ;;
        1) ALICIA_LOG_LEVEL=$LOG_LEVEL_INFO      ;;
        2) ALICIA_LOG_LEVEL=$LOG_LEVEL_WARN      ;;
        3) ALICIA_LOG_LEVEL=$LOG_LEVEL_ERROR     ;;
        4) ALICIA_LOG_LEVEL=$LOG_LEVEL_SILENT    ;;
        *) ALICIA_LOG_LEVEL=$LOG_LEVEL_INFO      ;;
    esac
}

# ============================================================================
# Log File Management
# ============================================================================

# log_archive - Archive the current log file with a timestamp
log_archive() {
    local archive_dir="${1:-$ALICIA_LOG_DIR/archives}"
    local timestamp
    timestamp=$(date "+%Y%m%d_%H%M%S")

    if [[ ! -d "$archive_dir" ]]; then
        mkdir -p "$archive_dir"
    fi

    if [[ -f "$ALICIA_LOG_FILE" ]]; then
        local archive_name="alicia_${timestamp}.log.gz"
        gzip -c "$ALICIA_LOG_FILE" > "${archive_dir}/${archive_name}"
        log_info "Log archived to: ${archive_dir}/${archive_name}"
        : > "$ALICIA_LOG_FILE"
    fi
}

# log_cleanup - Clean up old archived logs
log_cleanup() {
    local max_days="${1:-30}"
    local archive_dir="${2:-$ALICIA_LOG_DIR/archives}"

    if [[ ! -d "$archive_dir" ]]; then
        return 0
    fi

    local deleted=0
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((deleted++))
    done < <(find "$archive_dir" -name "*.log.gz" -mtime +"$max_days" -print0 2>/dev/null)

    if [[ $deleted -gt 0 ]]; then
        log_info "Cleaned up $deleted archived log files older than $max_days days"
    fi
}

# ============================================================================
# Initialize logging on source (safe - won't fail if dirs don't exist yet)
# ============================================================================
if [[ -n "${ALICIA_HOME:-}" ]] && [[ -d "${ALICIA_LOG_DIR:-}" ]]; then
    log_init "${ALICIA_LOG_DIR}" "${ALICIA_LOG_FILE}" 2>/dev/null || true
fi
