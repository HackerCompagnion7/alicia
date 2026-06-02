#!/bin/bash
# ============================================================================
# config.sh - Alicia Desktop Environment Configuration Management Script
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
# Description:  Interactive and command-line configuration management for
#               the Alicia Desktop Environment. Supports dialog/whiptail UI,
#               configuration export/import, validation, and backup.
# Usage:        config.sh [OPTIONS] [SECTION]
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
log_init "${ALICIA_LOG_DIR}" "${ALICIA_LOG_DIR}/config.log" 2>/dev/null || true
log_set_module "config"

# ============================================================================
# Constants
# ============================================================================
CONFIG_FILE="${ALICIA_CONFIG_DIR}/alicia.conf"
CONFIG_BACKUP_DIR="${ALICIA_BACKUP_DIR}/config"
VALID_SECTIONS=("vnc" "desktop" "user" "network" "performance" "apps" "accessibility" "audio")

# ============================================================================
# Variables
# ============================================================================
INTERACTIVE=true
SECTION=""
SET_KEY=""
SET_VALUE=""
EXPORT_FILE=""
IMPORT_FILE=""
RESET_ALL=false

# ============================================================================
# Parse Arguments
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive|-n)
                INTERACTIVE=false
                shift
                ;;
            --set|-s)
                if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                    log_error "--set requires KEY and VALUE arguments"
                    exit 1
                fi
                SET_KEY="$2"
                SET_VALUE="$3"
                shift 3
                ;;
            --get|-g)
                if [[ -z "${2:-}" ]]; then
                    log_error "--get requires a KEY argument"
                    exit 1
                fi
                SET_KEY="$2"
                shift 2
                ;;
            --export|-e)
                if [[ -z "${2:-}" ]]; then
                    log_error "--export requires a FILE argument"
                    exit 1
                fi
                EXPORT_FILE="$2"
                shift 2
                ;;
            --import|-i)
                if [[ -z "${2:-}" ]]; then
                    log_error "--import requires a FILE argument"
                    exit 1
                fi
                IMPORT_FILE="$2"
                shift 2
                ;;
            --reset)
                RESET_ALL=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                # Might be a section name
                if [[ " ${VALID_SECTIONS[*]} " == *" $1 "* ]]; then
                    SECTION="$1"
                else
                    log_error "Unknown argument or section: $1"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

show_usage() {
    echo "Usage: config.sh [OPTIONS] [SECTION]"
    echo ""
    echo "Manage Alicia Desktop Environment configuration."
    echo ""
    echo "Sections: vnc, desktop, user, network, performance, apps, accessibility, audio"
    echo ""
    echo "Options:"
    echo "  --non-interactive, -n     Non-interactive mode"
    echo "  --set KEY VALUE           Set a configuration value"
    echo "  --get KEY                 Get a configuration value"
    echo "  --export FILE             Export configuration to file"
    echo "  --import FILE             Import configuration from file"
    echo "  --reset                   Reset to default configuration"
    echo "  --help, -h                Show this help"
    echo ""
    echo "Examples:"
    echo "  config.sh                         Interactive menu"
    echo "  config.sh vnc                     Configure VNC settings"
    echo "  config.sh --set vnc.resolution 1920x1080"
    echo "  config.sh --get vnc.port"
    echo "  config.sh --export ~/alicia-config-backup.conf"
}

# ============================================================================
# Configuration Backup
# ============================================================================
backup_config() {
    log_info "Backing up current configuration..."
    mkdir -p "${CONFIG_BACKUP_DIR}"

    local timestamp
    timestamp=$(date "+%Y%m%d_%H%M%S")
    local backup_file="${CONFIG_BACKUP_DIR}/alicia_conf_${timestamp}.backup"

    if [[ -f "${CONFIG_FILE}" ]]; then
        cp "${CONFIG_FILE}" "${backup_file}"
        chmod 600 "${backup_file}"
        log_info "Configuration backed up to: ${backup_file}"
    else
        log_info "No existing configuration to backup"
    fi
}

# ============================================================================
# Configuration Validation
# ============================================================================
validate_config_value() {
    local key="$1"
    local value="$2"

    case "${key}" in
        vnc.port)
            if ! [[ "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" -lt 5900 ]] || [[ "${value}" -gt 5999 ]]; then
                log_error "Invalid VNC port: ${value} (must be 5900-5999)"
                return 1
            fi
            ;;
        vnc.resolution)
            if ! [[ "${value}" =~ ^[0-9]+x[0-9]+$ ]]; then
                log_error "Invalid resolution: ${value} (expected WxH format)"
                return 1
            fi
            ;;
        vnc.depth)
            if ! [[ "${value}" =~ ^(8|16|24|32)$ ]]; then
                log_error "Invalid color depth: ${value} (must be 8, 16, 24, or 32)"
                return 1
            fi
            ;;
        user.locale)
            if ! [[ "${value}" =~ ^[a-z]{2}_[A-Z]{2}\.[A-Za-z0-9-]+$ ]]; then
                log_warn "Locale format may be invalid: ${value} (expected format: en_US.UTF-8)"
            fi
            ;;
        user.timezone)
            if ! timedatectl list-timezones 2>/dev/null | grep -q "^${value}$" && \
               ! [[ -f "/usr/share/zoneinfo/${value}" ]] 2>/dev/null; then
                log_warn "Timezone may be invalid: ${value}"
            fi
            ;;
        network.dns1|network.dns2)
            if ! [[ "${value}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                log_error "Invalid DNS address: ${value}"
                return 1
            fi
            ;;
        network.proxy_port|network.ssh_port)
            if ! [[ "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" -lt 1 ]] || [[ "${value}" -gt 65535 ]]; then
                log_error "Invalid port: ${value} (must be 1-65535)"
                return 1
            fi
            ;;
        performance.swap_size)
            if ! [[ "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" -lt 0 ]]; then
                log_error "Invalid swap size: ${value}"
                return 1
            fi
            ;;
        accessibility.font_size)
            if ! [[ "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" -lt 6 ]] || [[ "${value}" -gt 32 ]]; then
                log_error "Invalid font size: ${value} (must be 6-32)"
                return 1
            fi
            ;;
        audio.volume)
            if ! [[ "${value}" =~ ^[0-9]+$ ]] || [[ "${value}" -lt 0 ]] || [[ "${value}" -gt 100 ]]; then
                log_error "Invalid volume: ${value} (must be 0-100)"
                return 1
            fi
            ;;
    esac

    return 0
}

# ============================================================================
# Default Configuration
# ============================================================================
get_default_config() {
    cat <<DEFAULTS
# Alicia Desktop Environment Configuration
# Generated by config.sh v${ALICIA_VERSION}
# $(date -u '+%Y-%m-%d %H:%M:%S UTC')

[vnc]
resolution = ${ALICIA_DEFAULT_VNC_RESOLUTION}
port = ${ALICIA_DEFAULT_VNC_PORT}
depth = 24
password = alicia

[desktop]
environment = ${ALICIA_DEFAULT_DESKTOP_ENV}
theme = Adwaita
icon_theme = Adwaita
font_name = Sans
font_size = 10
wallpaper = /usr/share/backgrounds/alicia-default.png

[user]
username = alicia
locale = ${ALICIA_DEFAULT_LANG}
timezone = ${ALICIA_DEFAULT_TIMEZONE}
keyboard = ${ALICIA_DEFAULT_KEYBOARD}

[network]
dns1 = 8.8.8.8
dns2 = 8.8.4.4
proxy_host =
proxy_port = 8080
ssh_port = 8022

[performance]
swap_size = 512
cache_size = 256
optimize_on_start = true
memory_limit = 0

[apps]
default_browser = firefox
default_editor = mousepad
default_terminal = xfce4-terminal
default_file_manager = thunar

[accessibility]
font_size = 10
high_contrast = false
large_cursor = false
screen_reader = false

[audio]
volume = 50
output_device = default
mute = false
DEFAULTS
}

# ============================================================================
# VNC Configuration Menu
# ============================================================================
configure_vnc() {
    log_info "Configuring VNC settings..."

    local current_res current_port current_depth current_pass
    current_res=$(alicia_get_config_value "vnc.resolution" "${ALICIA_DEFAULT_VNC_RESOLUTION}")
    current_port=$(alicia_get_config_value "vnc.port" "${ALICIA_DEFAULT_VNC_PORT}")
    current_depth=$(alicia_get_config_value "vnc.depth" "24")
    current_pass=$(alicia_get_config_value "vnc.password" "alicia")

    if [[ "${INTERACTIVE}" == "true" ]]; then
        local choice
        choice=$(ui_show_list_select "VNC Configuration" "Select setting to change:" \
            "Resolution (current: ${current_res})" \
            "Port (current: ${current_port})" \
            "Depth (current: ${current_depth})" \
            "Password" \
            "Back") || return 0

        case "${choice}" in
            1)
                local res
                res=$(ui_show_list_select "VNC Resolution" "Select resolution:" \
                    "720x480" "1280x720" "1366x768" "1920x1080" "Custom") || return 0
                if [[ "${res}" == "5" ]]; then
                    res=$(ui_show_input "Custom Resolution" "Enter resolution (WxH):" "${current_res}")
                else
                    case "${res}" in
                        1) res="720x480" ;;
                        2) res="1280x720" ;;
                        3) res="1366x768" ;;
                        4) res="1920x1080" ;;
                    esac
                fi
                validate_config_value "vnc.resolution" "${res}" && \
                    alicia_set_config_value "vnc.resolution" "${res}" "true"
                ;;
            2)
                local port
                port=$(ui_show_input "VNC Port" "Enter VNC port (5900-5999):" "${current_port}")
                validate_config_value "vnc.port" "${port}" && \
                    alicia_set_config_value "vnc.port" "${port}" "true"
                ;;
            3)
                local depth
                depth=$(ui_show_list_select "Color Depth" "Select color depth:" \
                    "8-bit" "16-bit" "24-bit" "32-bit") || return 0
                case "${depth}" in
                    1) depth="8" ;; 2) depth="16" ;; 3) depth="24" ;; 4) depth="32" ;;
                esac
                validate_config_value "vnc.depth" "${depth}" && \
                    alicia_set_config_value "vnc.depth" "${depth}" "true"
                ;;
            4)
                local pass
                pass=$(ui_show_password "VNC Password" "Enter new VNC password:")
                [[ -n "${pass}" ]] && alicia_set_config_value "vnc.password" "${pass}" "true"
                ;;
            *) return 0 ;;
        esac
    fi

    log_info "VNC configuration updated"
}

# ============================================================================
# Desktop Configuration Menu
# ============================================================================
configure_desktop() {
    log_info "Configuring desktop settings..."

    if [[ "${INTERACTIVE}" != "true" ]]; then
        return 0
    fi

    local choice
    choice=$(ui_show_list_select "Desktop Configuration" "Select setting to change:" \
        "Theme" "Icon Theme" "Font" "Wallpaper" "Back") || return 0

    case "${choice}" in
        1)
            local theme
            theme=$(ui_show_input "GTK Theme" "Enter theme name:" \
                "$(alicia_get_config_value "desktop.theme" "Adwaita")")
            alicia_set_config_value "desktop.theme" "${theme}" "true"
            ;;
        2)
            local icons
            icons=$(ui_show_input "Icon Theme" "Enter icon theme name:" \
                "$(alicia_get_config_value "desktop.icon_theme" "Adwaita")")
            alicia_set_config_value "desktop.icon_theme" "${icons}" "true"
            ;;
        3)
            local fname fsize
            fname=$(ui_show_input "Font Name" "Enter font name:" \
                "$(alicia_get_config_value "desktop.font_name" "Sans")")
            fsize=$(ui_show_input "Font Size" "Enter font size:" \
                "$(alicia_get_config_value "desktop.font_size" "10")")
            validate_config_value "accessibility.font_size" "${fsize}" || return 1
            alicia_set_config_value "desktop.font_name" "${fname}" "true"
            alicia_set_config_value "desktop.font_size" "${fsize}" "true"
            ;;
        4)
            local wp
            wp=$(ui_show_input "Wallpaper" "Enter wallpaper path:" \
                "$(alicia_get_config_value "desktop.wallpaper" "")")
            alicia_set_config_value "desktop.wallpaper" "${wp}" "true"
            ;;
    esac

    log_info "Desktop configuration updated"
}

# ============================================================================
# User Configuration Menu
# ============================================================================
configure_user() {
    log_info "Configuring user settings..."

    if [[ "${INTERACTIVE}" != "true" ]]; then
        return 0
    fi

    local choice
    choice=$(ui_show_list_select "User Configuration" "Select setting to change:" \
        "Username" "Locale" "Timezone" "Keyboard Layout" "Password" "Back") || return 0

    case "${choice}" in
        1)
            local username
            username=$(ui_show_input "Username" "Enter username:" \
                "$(alicia_get_config_value "user.username" "alicia")")
            alicia_set_config_value "user.username" "${username}" "true"
            ;;
        2)
            local locale
            locale=$(ui_show_input "Locale" "Enter locale (e.g., en_US.UTF-8):" \
                "$(alicia_get_config_value "user.locale" "${ALICIA_DEFAULT_LANG}")")
            validate_config_value "user.locale" "${locale}" || true
            alicia_set_config_value "user.locale" "${locale}" "true"
            ;;
        3)
            local tz
            tz=$(ui_show_input "Timezone" "Enter timezone (e.g., America/New_York):" \
                "$(alicia_get_config_value "user.timezone" "${ALICIA_DEFAULT_TIMEZONE}")")
            validate_config_value "user.timezone" "${tz}" || true
            alicia_set_config_value "user.timezone" "${tz}" "true"
            ;;
        4)
            local kb
            kb=$(ui_show_input "Keyboard Layout" "Enter keyboard layout code:" \
                "$(alicia_get_config_value "user.keyboard" "${ALICIA_DEFAULT_KEYBOARD}")")
            alicia_set_config_value "user.keyboard" "${kb}" "true"
            ;;
        5)
            local pass
            pass=$(ui_show_password "User Password" "Enter new user password:")
            [[ -n "${pass}" ]] && alicia_set_config_value "user.password" "${pass}" "true"
            ;;
    esac

    log_info "User configuration updated"
}

# ============================================================================
# Network Configuration Menu
# ============================================================================
configure_network() {
    log_info "Configuring network settings..."

    if [[ "${INTERACTIVE}" != "true" ]]; then
        return 0
    fi

    local choice
    choice=$(ui_show_list_select "Network Configuration" "Select setting to change:" \
        "DNS Servers" "Proxy" "SSH Server" "Back") || return 0

    case "${choice}" in
        1)
            local dns1 dns2
            dns1=$(ui_show_input "Primary DNS" "Enter primary DNS:" \
                "$(alicia_get_config_value "network.dns1" "8.8.8.8")")
            dns2=$(ui_show_input "Secondary DNS" "Enter secondary DNS:" \
                "$(alicia_get_config_value "network.dns2" "8.8.4.4")")
            validate_config_value "network.dns1" "${dns1}" || return 1
            validate_config_value "network.dns2" "${dns2}" || return 1
            alicia_set_config_value "network.dns1" "${dns1}" "true"
            alicia_set_config_value "network.dns2" "${dns2}" "true"
            ;;
        2)
            local host port
            host=$(ui_show_input "Proxy Host" "Enter proxy host (empty to disable):" \
                "$(alicia_get_config_value "network.proxy_host" "")")
            port=$(ui_show_input "Proxy Port" "Enter proxy port:" \
                "$(alicia_get_config_value "network.proxy_port" "8080")")
            validate_config_value "network.proxy_port" "${port}" || return 1
            alicia_set_config_value "network.proxy_host" "${host}" "true"
            alicia_set_config_value "network.proxy_port" "${port}" "true"
            ;;
        3)
            local ssh_port
            ssh_port=$(ui_show_input "SSH Port" "Enter SSH port:" \
                "$(alicia_get_config_value "network.ssh_port" "8022")")
            validate_config_value "network.ssh_port" "${ssh_port}" || return 1
            alicia_set_config_value "network.ssh_port" "${ssh_port}" "true"
            ;;
    esac

    log_info "Network configuration updated"
}

# ============================================================================
# Performance Configuration Menu
# ============================================================================
configure_performance() {
    log_info "Configuring performance settings..."

    if [[ "${INTERACTIVE}" != "true" ]]; then
        return 0
    fi

    local choice
    choice=$(ui_show_list_select "Performance Configuration" "Select setting to change:" \
        "Swap Size (MB)" "Cache Size (MB)" "Memory Limit (MB)" \
        "Optimize on Start" "Back") || return 0

    case "${choice}" in
        1)
            local swap
            swap=$(ui_show_input "Swap Size" "Enter swap size in MB:" \
                "$(alicia_get_config_value "performance.swap_size" "512")")
            validate_config_value "performance.swap_size" "${swap}" || return 1
            alicia_set_config_value "performance.swap_size" "${swap}" "true"
            ;;
        2)
            local cache_sz
            cache_sz=$(ui_show_input "Cache Size" "Enter max cache size in MB:" \
                "$(alicia_get_config_value "performance.cache_size" "256")")
            alicia_set_config_value "performance.cache_size" "${cache_sz}" "true"
            ;;
        3)
            local mem_limit
            mem_limit=$(ui_show_input "Memory Limit" "Enter memory limit in MB (0=unlimited):" \
                "$(alicia_get_config_value "performance.memory_limit" "0")")
            alicia_set_config_value "performance.memory_limit" "${mem_limit}" "true"
            ;;
        4)
            local opt
            opt=$(ui_show_list_select "Optimize on Start" "Enable memory optimization on startup?" \
                "Yes" "No") || return 0
            alicia_set_config_value "performance.optimize_on_start" "$([[ "${opt}" == "1" ]] && echo true || echo false)" "true"
            ;;
    esac

    log_info "Performance configuration updated"
}

# ============================================================================
# Application Configuration Menu
# ============================================================================
configure_apps() {
    log_info "Configuring application settings..."

    if [[ "${INTERACTIVE}" != "true" ]]; then
        return 0
    fi

    local choice
    choice=$(ui_show_list_select "Application Configuration" "Select default app to change:" \
        "Web Browser" "Text Editor" "Terminal" "File Manager" "Back") || return 0

    case "${choice}" in
        1)
            local browser
            browser=$(ui_show_input "Default Browser" "Enter browser command:" \
                "$(alicia_get_config_value "apps.default_browser" "firefox")")
            alicia_set_config_value "apps.default_browser" "${browser}" "true"
            ;;
        2)
            local editor
            editor=$(ui_show_input "Default Editor" "Enter editor command:" \
                "$(alicia_get_config_value "apps.default_editor" "mousepad")")
            alicia_set_config_value "apps.default_editor" "${editor}" "true"
            ;;
        3)
            local term
            term=$(ui_show_input "Default Terminal" "Enter terminal command:" \
                "$(alicia_get_config_value "apps.default_terminal" "xfce4-terminal")")
            alicia_set_config_value "apps.default_terminal" "${term}" "true"
            ;;
        4)
            local fm
            fm=$(ui_show_input "Default File Manager" "Enter file manager command:" \
                "$(alicia_get_config_value "apps.default_file_manager" "thunar")")
            alicia_set_config_value "apps.default_file_manager" "${fm}" "true"
            ;;
    esac

    log_info "Application configuration updated"
}

# ============================================================================
# Accessibility Configuration Menu
# ============================================================================
configure_accessibility() {
    log_info "Configuring accessibility settings..."

    if [[ "${INTERACTIVE}" != "true" ]]; then
        return 0
    fi

    local choice
    choice=$(ui_show_list_select "Accessibility Configuration" "Select setting to change:" \
        "Font Size" "High Contrast" "Large Cursor" "Screen Reader" "Back") || return 0

    case "${choice}" in
        1)
            local fs
            fs=$(ui_show_input "Font Size" "Enter font size (6-32):" \
                "$(alicia_get_config_value "accessibility.font_size" "10")")
            validate_config_value "accessibility.font_size" "${fs}" || return 1
            alicia_set_config_value "accessibility.font_size" "${fs}" "true"
            ;;
        2)
            local hc
            hc=$(ui_show_list_select "High Contrast" "Enable high contrast mode?" \
                "Yes" "No") || return 0
            alicia_set_config_value "accessibility.high_contrast" "$([[ "${hc}" == "1" ]] && echo true || echo false)" "true"
            ;;
        3)
            local lc
            lc=$(ui_show_list_select "Large Cursor" "Enable large cursor?" \
                "Yes" "No") || return 0
            alicia_set_config_value "accessibility.large_cursor" "$([[ "${lc}" == "1" ]] && echo true || echo false)" "true"
            ;;
        4)
            local sr
            sr=$(ui_show_list_select "Screen Reader" "Enable screen reader?" \
                "Yes" "No") || return 0
            alicia_set_config_value "accessibility.screen_reader" "$([[ "${sr}" == "1" ]] && echo true || echo false)" "true"
            ;;
    esac

    log_info "Accessibility configuration updated"
}

# ============================================================================
# Audio Configuration Menu
# ============================================================================
configure_audio() {
    log_info "Configuring audio settings..."

    if [[ "${INTERACTIVE}" != "true" ]]; then
        return 0
    fi

    local choice
    choice=$(ui_show_list_select "Audio Configuration" "Select setting to change:" \
        "Volume" "Output Device" "Mute" "Back") || return 0

    case "${choice}" in
        1)
            local vol
            vol=$(ui_show_input "Volume" "Enter volume (0-100):" \
                "$(alicia_get_config_value "audio.volume" "50")")
            validate_config_value "audio.volume" "${vol}" || return 1
            alicia_set_config_value "audio.volume" "${vol}" "true"
            ;;
        2)
            local dev
            dev=$(ui_show_input "Output Device" "Enter audio output device:" \
                "$(alicia_get_config_value "audio.output_device" "default")")
            alicia_set_config_value "audio.output_device" "${dev}" "true"
            ;;
        3)
            local mute
            mute=$(ui_show_list_select "Mute Audio" "Mute audio output?" \
                "Yes" "No") || return 0
            alicia_set_config_value "audio.mute" "$([[ "${mute}" == "1" ]] && echo true || echo false)" "true"
            ;;
    esac

    log_info "Audio configuration updated"
}

# ============================================================================
# Main Interactive Menu
# ============================================================================
show_main_menu() {
    while true; do
        local choice
        choice=$(ui_show_list_select "Alicia Configuration" "Select a configuration category:" \
            "VNC Settings" "Desktop Environment" "User Settings" \
            "Network Settings" "Performance" "Application Defaults" \
            "Accessibility" "Audio" \
            "Export Configuration" "Import Configuration" \
            "Reset to Defaults" "Exit") || break

        case "${choice}" in
            1)  backup_config; configure_vnc ;;
            2)  backup_config; configure_desktop ;;
            3)  backup_config; configure_user ;;
            4)  backup_config; configure_network ;;
            5)  backup_config; configure_performance ;;
            6)  backup_config; configure_apps ;;
            7)  backup_config; configure_accessibility ;;
            8)  backup_config; configure_audio ;;
            9)  export_config ;;
            10) import_config_interactive ;;
            11) reset_config ;;
            12) break ;;
        esac
    done
}

# ============================================================================
# Export Configuration
# ============================================================================
export_config() {
    local output_file="${EXPORT_FILE}"

    if [[ -z "${output_file}" ]]; then
        output_file=$(ui_show_input "Export Configuration" "Enter export file path:" \
            "${HOME}/alicia-config-$(date '+%Y%m%d').conf") || return 0
    fi

    log_info "Exporting configuration to: ${output_file}"

    if [[ -f "${CONFIG_FILE}" ]]; then
        cp "${CONFIG_FILE}" "${output_file}"
        log_info "Configuration exported to: ${output_file}"
        ui_show_message "Export Complete" "Configuration exported to:\n${output_file}"
    else
        log_warn "No configuration file to export"
        ui_show_message "Export" "No configuration file found at:\n${CONFIG_FILE}"
    fi
}

# ============================================================================
# Import Configuration
# ============================================================================
import_config_interactive() {
    local input_file="${IMPORT_FILE}"

    if [[ -z "${input_file}" ]]; then
        input_file=$(ui_show_input "Import Configuration" "Enter config file path to import:" "") || return 0
    fi

    if [[ ! -f "${input_file}" ]]; then
        log_error "Configuration file not found: ${input_file}"
        ui_show_error "Import Error" "File not found:\n${input_file}"
        return 1
    fi

    # Validate before importing
    if ! alicia_parse_config "${input_file}" 2>/dev/null; then
        log_error "Invalid configuration file format"
        ui_show_error "Import Error" "Invalid configuration file format"
        return 1
    fi

    # Backup current config before import
    backup_config

    log_info "Importing configuration from: ${input_file}"
    cp "${input_file}" "${CONFIG_FILE}"
    alicia_parse_config "${CONFIG_FILE}"

    log_info "Configuration imported successfully"
    ui_show_message "Import Complete" "Configuration imported from:\n${input_file}"
}

# ============================================================================
# Reset Configuration
# ============================================================================
reset_config() {
    if [[ "${INTERACTIVE}" == "true" ]]; then
        if ! ui_show_question "Reset Configuration" "Are you sure you want to reset all settings to defaults?"; then
            return 0
        fi
    fi

    log_info "Resetting configuration to defaults..."
    backup_config
    get_default_config > "${CONFIG_FILE}"
    alicia_parse_config "${CONFIG_FILE}"
    log_info "Configuration reset to defaults"
}

# ============================================================================
# Non-Interactive Mode Handlers
# ============================================================================
handle_set() {
    log_info "Setting configuration: ${SET_KEY} = ${SET_VALUE}"

    # Validate
    if ! validate_config_value "${SET_KEY}" "${SET_VALUE}"; then
        exit 1
    fi

    backup_config
    alicia_set_config_value "${SET_KEY}" "${SET_VALUE}" "true"
    log_info "Configuration value set: ${SET_KEY} = ${SET_VALUE}"
}

handle_get() {
    local value
    value=$(alicia_get_config_value "${SET_KEY}" "") || true
    if [[ -n "${value}" ]]; then
        echo "${value}"
    else
        echo "(not set)"
        exit 1
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    parse_args "$@"

    # Ensure config file exists
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        mkdir -p "$(dirname "${CONFIG_FILE}")"
        get_default_config > "${CONFIG_FILE}"
        log_info "Default configuration created"
    fi

    # Parse current config
    alicia_parse_config "${CONFIG_FILE}" 2>/dev/null || true

    # Handle non-interactive operations
    if [[ -n "${SET_KEY}" && -n "${SET_VALUE}" ]]; then
        handle_set
        return 0
    fi

    if [[ -n "${SET_KEY}" && -z "${SET_VALUE}" && "${INTERACTIVE}" == "false" ]]; then
        handle_get
        return 0
    fi

    if [[ -n "${EXPORT_FILE}" ]]; then
        export_config
        return 0
    fi

    if [[ -n "${IMPORT_FILE}" ]]; then
        backup_config
        import_config_interactive
        return 0
    fi

    if [[ "${RESET_ALL}" == "true" ]]; then
        reset_config
        return 0
    fi

    # Interactive section or main menu
    if [[ -n "${SECTION}" ]]; then
        backup_config
        case "${SECTION}" in
            vnc)            configure_vnc ;;
            desktop)        configure_desktop ;;
            user)           configure_user ;;
            network)        configure_network ;;
            performance)    configure_performance ;;
            apps)           configure_apps ;;
            accessibility)  configure_accessibility ;;
            audio)          configure_audio ;;
        esac
    else
        if [[ "${INTERACTIVE}" == "true" ]]; then
            show_main_menu
        else
            # In non-interactive mode with no options, just show current config
            if [[ -f "${CONFIG_FILE}" ]]; then
                cat "${CONFIG_FILE}"
            else
                get_default_config
            fi
        fi
    fi

    return 0
}

# ============================================================================
# Execute Main
# ============================================================================
main "$@"
