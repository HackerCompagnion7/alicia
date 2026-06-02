#!/bin/bash
# ============================================================================
# alicia-ui.sh - Alicia Desktop Environment UI Helper Library
# ============================================================================
# Copyright (C) 2005-2025 Proyecto Tomorrow
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# ============================================================================
# Author:       Proyecto Tomorrow
# Version:      2.0.0
# Description:  UI helper library providing dialog functions, VNC display
#               configuration, desktop notification, wallpaper/theme management,
#               launcher creation, and accessibility configuration.
# ============================================================================

set -euo pipefail

if [[ -n "${_ALICIA_UI_LOADED:-}" ]]; then
    return 0
fi
_ALICIA_UI_LOADED=1

_ALICIA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ALICIA_LIB_DIR}/alicia-core.sh" 2>/dev/null || true
source "${_ALICIA_LIB_DIR}/alicia-log.sh" 2>/dev/null || true
source "${_ALICIA_LIB_DIR}/alicia-system.sh" 2>/dev/null || true

# ============================================================================
# Dialog Backend Detection
# ============================================================================
_ALICIA_DIALOG_BACKEND=""
_detect_dialog_backend() {
    if command -v dialog &>/dev/null; then
        _ALICIA_DIALOG_BACKEND="dialog"
    elif command -v whiptail &>/dev/null; then
        _ALICIA_DIALOG_BACKEND="whiptail"
    elif command -v zenity &>/dev/null; then
        _ALICIA_DIALOG_BACKEND="zenity"
    else
        _ALICIA_DIALOG_BACKEND="basic"
    fi
}
_detect_dialog_backend

# ============================================================================
# Terminal Dialog Functions
# ============================================================================

# ui_show_message - Show an informational message
ui_show_message() {
    local title="${1:-Alicia}"
    local message="${2:-}"

    case "$_ALICIA_DIALOG_BACKEND" in
        dialog)
            dialog --title "$title" --msgbox "$message" 15 60 2>/dev/null
            ;;
        whiptail)
            whiptail --title "$title" --msgbox "$message" 15 60 2>/dev/null
            ;;
        zenity)
            zenity --info --title="$title" --text="$message" 2>/dev/null
            ;;
        *)
            echo "============================================"
            echo "  $title"
            echo "============================================"
            echo "$message"
            echo "============================================"
            echo "Press Enter to continue..."
            read -r
            ;;
    esac
}

# ui_show_error - Show an error message
ui_show_error() {
    local title="${1:-Error}"
    local message="${2:-An error occurred}"

    case "$_ALICIA_DIALOG_BACKEND" in
        dialog)
            dialog --title "$title" --colors --msgbox "\\Z1$message\\Zn" 15 60 2>/dev/null
            ;;
        whiptail)
            whiptail --title "$title" --msgbox "$message" 15 60 2>/dev/null
            ;;
        zenity)
            zenity --error --title="$title" --text="$message" 2>/dev/null
            ;;
        *)
            echo "ERROR: $title" >&2
            echo "$message" >&2
            ;;
    esac
}

# ui_show_warning - Show a warning message
ui_show_warning() {
    local title="${1:-Warning}"
    local message="${2:-}"

    case "$_ALICIA_DIALOG_BACKEND" in
        dialog)
            dialog --title "$title" --colors --msgbox "\\Z3$message\\Zn" 12 50 2>/dev/null
            ;;
        whiptail)
            whiptail --title "$title" --msgbox "$message" 12 50 2>/dev/null
            ;;
        zenity)
            zenity --warning --title="$title" --text="$message" 2>/dev/null
            ;;
        *)
            echo "WARNING: $title"
            echo "$message"
            ;;
    esac
}

# ui_show_question - Show a yes/no question
ui_show_question() {
    local title="${1:-Question}"
    local message="${2:-Do you want to continue?}"

    case "$_ALICIA_DIALOG_BACKEND" in
        dialog)
            dialog --title "$title" --yesno "$message" 10 50 2>/dev/null
            return $?
            ;;
        whiptail)
            whiptail --title "$title" --yesno "$message" 10 50 2>/dev/null
            return $?
            ;;
        zenity)
            zenity --question --title="$title" --text="$message" 2>/dev/null
            return $?
            ;;
        *)
            echo "$title"
            echo "$message"
            echo -n "[y/N]: "
            local answer
            read -r answer
            [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
            return $?
            ;;
    esac
}

# ui_show_input - Show an input dialog
ui_show_input() {
    local title="${1:-Input}"
    local prompt="${2:-Enter value:}"
    local default="${3:-}"

    case "$_ALICIA_DIALOG_BACKEND" in
        dialog)
            local result
            result=$(dialog --title "$title" --inputbox "$prompt" 10 50 "$default" 3>&1 1>&2 2>&3) && echo "$result"
            ;;
        whiptail)
            local result
            result=$(whiptail --title "$title" --inputbox "$prompt" 10 50 "$default" 3>&1 1>&2 2>&3) && echo "$result"
            ;;
        zenity)
            zenity --entry --title="$title" --text="$prompt" --entry-text="$default" 2>/dev/null
            ;;
        *)
            echo -n "$prompt [$default]: "
            read -r answer
            echo "${answer:-$default}"
            ;;
    esac
}

# ui_show_password - Show a password input dialog
ui_show_password() {
    local title="${1:-Password}"
    local prompt="${2:-Enter password:}"

    case "$_ALICIA_DIALOG_BACKEND" in
        dialog)
            local result
            result=$(dialog --title "$title" --insecure --passwordbox "$prompt" 10 50 3>&1 1>&2 2>&3) && echo "$result"
            ;;
        whiptail)
            local result
            result=$(whiptail --title "$title" --passwordbox "$prompt" 10 50 3>&1 1>&2 2>&3) && echo "$result"
            ;;
        zenity)
            zenity --entry --title="$title" --text="$prompt" --hide-text 2>/dev/null
            ;;
        *)
            echo -n "$prompt: "
            read -rs answer
            echo ""
            echo "$answer"
            ;;
    esac
}

# ui_show_progress - Show a progress dialog
ui_show_progress() {
    local title="${1:-Progress}"
    local message="${2:-Please wait...}"
    local percentage="${3:-0}"

    case "$_ALICIA_DIALOG_BACKEND" in
        dialog)
            echo "$percentage" | dialog --title "$title" --gauge "$message" 10 60 "$percentage" 2>/dev/null
            ;;
        whiptail)
            echo "$percentage" | whiptail --title "$title" --gauge "$message" 10 60 "$percentage" 2>/dev/null
            ;;
        zenity)
            echo "$percentage" | zenity --progress --title="$title" --text="$message" --percentage="$percentage" 2>/dev/null
            ;;
        *)
            echo "[$title] $message - ${percentage}%"
            ;;
    esac
}

# ui_show_file_select - Show a file selection dialog
ui_show_file_select() {
    local title="${1:-Select File}"
    local start_dir="${2:-$HOME}"

    case "$_ALICIA_DIALOG_BACKEND" in
        zenity)
            zenity --file-selection --title="$title" --filename="$start_dir/" 2>/dev/null
            ;;
        dialog)
            local result
            result=$(dialog --title "$title" --fselect "$start_dir/" 15 60 3>&1 1>&2 2>&3) && echo "$result"
            ;;
        *)
            echo -n "Enter file path: "
            read -r filepath
            echo "$filepath"
            ;;
    esac
}

# ui_show_list_select - Show a selection list
ui_show_list_select() {
    local title="${1:-Select}"
    local description="${2:-Choose an option:}"
    shift 2
    local items=("$@")

    local dialog_items=()
    for i in "${!items[@]}"; do
        dialog_items+=("$((i+1))" "${items[$i]}")
    done

    case "$_ALICIA_DIALOG_BACKEND" in
        dialog)
            local result
            result=$(dialog --title "$title" --menu "$description" 20 60 15 "${dialog_items[@]}" 3>&1 1>&2 2>&3) && echo "$result"
            ;;
        whiptail)
            local result
            result=$(whiptail --title "$title" --menu "$description" 20 60 15 "${dialog_items[@]}" 3>&1 1>&2 2>&3) && echo "$result"
            ;;
        zenity)
            zenity --list --title="$title" --text="$description" --column="#" --column="Option" "${dialog_items[@]}" 2>/dev/null
            ;;
        *)
            echo "$title"
            echo "$description"
            for i in "${!items[@]}"; do
                echo "  $((i+1)). ${items[$i]}"
            done
            echo -n "Select [1-${#items[@]}]: "
            read -r choice
            echo "$choice"
            ;;
    esac
}

# ui_show_checklist - Show a multi-selection checklist
ui_show_checklist() {
    local title="${1:-Select Options}"
    local description="${2:-Choose options:}"
    shift 2
    local items=("$@")

    local dialog_items=()
    for i in "${!items[@]}"; do
        dialog_items+=("$((i+1))" "${items[$i]}" "OFF")
    done

    case "$_ALICIA_DIALOG_BACKEND" in
        dialog)
            local result
            result=$(dialog --title "$title" --checklist "$description" 20 60 15 "${dialog_items[@]}" 3>&1 1>&2 2>&3) && echo "$result"
            ;;
        whiptail)
            local result
            result=$(whiptail --title "$title" --checklist "$description" 20 60 15 "${dialog_items[@]}" 3>&1 1>&2 2>&3) && echo "$result"
            ;;
        *)
            echo "$title"
            echo "$description"
            for i in "${!items[@]}"; do
                echo "  [ ] ${items[$i]}"
            done
            ;;
    esac
}

# ============================================================================
# VNC Display Configuration
# ============================================================================

# ui_configure_vnc - Interactive VNC configuration
ui_configure_vnc() {
    log_info "Starting VNC configuration wizard"

    local resolution password port

    resolution=$(ui_show_list_select "VNC Resolution" "Select display resolution:" \
        "720x480 (Low)" "1280x720 (HD)" "1366x768 (WXGA)" "1920x1080 (Full HD)") || resolution="2"

    case "$resolution" in
        1) ALICIA_VNC_RESOLUTION="720x480" ;;
        2) ALICIA_VNC_RESOLUTION="1280x720" ;;
        3) ALICIA_VNC_RESOLUTION="1366x768" ;;
        4) ALICIA_VNC_RESOLUTION="1920x1080" ;;
        *) ALICIA_VNC_RESOLUTION="1280x720" ;;
    esac

    password=$(ui_show_password "VNC Password" "Set VNC connection password (empty for default 'alicia'):")
    if [[ -n "$password" ]]; then
        ALICIA_VNC_PASSWORD="$password"
    fi

    port=$(ui_show_input "VNC Port" "VNC port number:" "${ALICIA_VNC_PORT}")
    if [[ -n "$port" ]]; then
        ALICIA_VNC_PORT="$port"
    fi

    set_config_value "VNC_RESOLUTION" "$ALICIA_VNC_RESOLUTION"
    set_config_value "VNC_PORT" "$ALICIA_VNC_PORT"
    set_config_value "VNC_PASSWORD" "$ALICIA_VNC_PASSWORD"

    log_info "VNC configured: Resolution=$ALICIA_VNC_RESOLUTION, Port=$ALICIA_VNC_PORT"
    ui_show_message "VNC Configuration" "VNC Settings:\n\nResolution: $ALICIA_VNC_RESOLUTION\nPort: $ALICIA_VNC_PORT\n\nConfiguration saved."
}

# ============================================================================
# Desktop Notification Functions
# ============================================================================

# ui_notify - Send a desktop notification inside proot
ui_notify() {
    local title="${1:-Alicia}"
    local message="${2:-}"
    local urgency="${3:-normal}"
    local timeout="${4:-5000}"

    proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; notify-send -u $urgency -t $timeout '$title' '$message' 2>/dev/null" || true
}

# ui_notify_info - Send an info notification
ui_notify_info() {
    ui_notify "${1:-Alicia}" "${2:-}" "low" "${3:-5000}"
}

# ui_notify_warning - Send a warning notification
ui_notify_warning() {
    ui_notify "${1:-Warning}" "${2:-}" "normal" "${3:-8000}"
}

# ui_notify_error - Send an error notification
ui_notify_error() {
    ui_notify "${1:-Error}" "${2:-}" "critical" "${3:-10000}"
}

# ============================================================================
# Wallpaper Management
# ============================================================================

# ui_set_wallpaper - Set the desktop wallpaper
ui_set_wallpaper() {
    local wallpaper_path="$1"
    if [[ -z "$wallpaper_path" ]]; then
        log_error "No wallpaper path specified"
        return 1
    fi

    log_info "Setting wallpaper: $wallpaper_path"

    # For XFCE
    proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path -s '$wallpaper_path' 2>/dev/null" || \
    proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s '$wallpaper_path' 2>/dev/null" || {
        log_warn "Could not set wallpaper via xfconf-query"
    }

    set_config_value "WALLPAPER" "$wallpaper_path"
    log_info "Wallpaper set successfully"
}

# ui_get_wallpaper - Get current wallpaper path
ui_get_wallpaper() {
    proot_exec "$ALICIA_DISTRO_NAME" "xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/image-path 2>/dev/null" || \
    get_config_value "WALLPAPER" "/usr/share/backgrounds/alicia-default.png"
}

# ui_list_wallpapers - List available wallpapers
ui_list_wallpapers() {
    local wallpaper_dirs=(
        "/home/alicia/Pictures/Wallpapers"
        "/usr/share/backgrounds"
        "/usr/share/wallpapers"
    )

    for dir in "${wallpaper_dirs[@]}"; do
        proot_exec "$ALICIA_DISTRO_NAME" "find $dir -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.svg' \) 2>/dev/null" || true
    done
}

# ============================================================================
# Theme Management
# ============================================================================

# ui_set_theme - Set the GTK/theme
ui_set_theme() {
    local theme_name="$1"
    if [[ -z "$theme_name" ]]; then
        log_error "No theme name specified"
        return 1
    fi

    log_info "Setting theme: $theme_name"

    # Set GTK theme
    proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xfconf-query -c xsettings -p /Net/ThemeName -s '$theme_name' 2>/dev/null" || true

    # Set XFWM theme
    proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xfconf-query -c xfwm4 -p /general/theme -s '$theme_name' 2>/dev/null" || true

    # Update GTK-3.0 settings
    proot_exec "$ALICIA_DISTRO_NAME" "mkdir -p /home/alicia/.config/gtk-3.0 && echo '[Settings]
gtk-theme-name=$theme_name' > /home/alicia/.config/gtk-3.0/settings.ini" 2>/dev/null || true

    set_config_value "GTK_THEME" "$theme_name"
    log_info "Theme set to: $theme_name"
}

# ui_get_theme - Get current theme name
ui_get_theme() {
    proot_exec "$ALICIA_DISTRO_NAME" "xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null" || echo "Default"
}

# ui_list_themes - List available GTK themes
ui_list_themes() {
    proot_exec "$ALICIA_DISTRO_NAME" "ls -1 /usr/share/themes/ 2>/dev/null; ls -1 /home/alicia/.themes/ 2>/dev/null" || echo "No themes found"
}

# ============================================================================
# Icon Theme Management
# ============================================================================

# ui_set_icon_theme - Set the icon theme
ui_set_icon_theme() {
    local theme_name="$1"
    if [[ -z "$theme_name" ]]; then
        log_error "No icon theme name specified"
        return 1
    fi

    log_info "Setting icon theme: $theme_name"
    proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xfconf-query -c xsettings -p /Net/IconThemeName -s '$theme_name' 2>/dev/null" || true
    set_config_value "ICON_THEME" "$theme_name"
}

# ui_list_icon_themes - List available icon themes
ui_list_icon_themes() {
    proot_exec "$ALICIA_DISTRO_NAME" "ls -1 /usr/share/icons/ 2>/dev/null; ls -1 /home/alicia/.icons/ 2>/dev/null" || echo "No icon themes found"
}

# ============================================================================
# Font Management
# ============================================================================

# ui_set_font - Set the desktop font
ui_set_font() {
    local font_name="$1"
    local font_size="${2:-10}"

    log_info "Setting font: $font_name $font_size"

    proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xfconf-query -c xsettings -p /Gtk/FontName -s '$font_name $font_size' 2>/dev/null" || true
    set_config_value "FONT_NAME" "$font_name"
    set_config_value "FONT_SIZE" "$font_size"
}

# ui_list_fonts - List available fonts
ui_list_fonts() {
    proot_exec "$ALICIA_DISTRO_NAME" "fc-list 2>/dev/null | cut -d: -f2 | sort -u | head -50" || echo "No fonts found"
}

# ============================================================================
# Desktop Launcher Creation
# ============================================================================

# ui_create_launcher - Create a desktop application launcher
ui_create_launcher() {
    local name="$1"
    local exec_cmd="$2"
    local icon="${3:-applications-other}"
    local category="${4:-Application}"
    local comment="${5:-$name}"
    local terminal="${6:-false}"

    if [[ -z "$name" || -z "$exec_cmd" ]]; then
        log_error "Launcher name and exec command are required"
        return 1
    fi

    local safe_name
    safe_name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    local desktop_file="/home/alicia/.local/share/applications/alicia-${safe_name}.desktop"

    log_info "Creating launcher: $name"

    proot_exec "$ALICIA_DISTRO_NAME" bash -c "mkdir -p /home/alicia/.local/share/applications && cat > '$desktop_file' << DESKTOP_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$comment
Icon=$icon
Exec=$exec_cmd
Terminal=$terminal
Categories=$category;
StartupNotify=true
DESKTOP_EOF
chmod +x '$desktop_file'"

    # Also create desktop icon
    proot_exec "$ALICIA_DISTRO_NAME" "cp '$desktop_file' '/home/alicia/Desktop/${name}.desktop' && chmod +x '/home/alicia/Desktop/${name}.desktop'" 2>/dev/null || true

    # Update desktop database
    proot_exec "$ALICIA_DISTRO_NAME" "update-desktop-database /home/alicia/.local/share/applications/ 2>/dev/null" || true

    log_info "Launcher created: $name"
    return 0
}

# ui_remove_launcher - Remove a desktop launcher
ui_remove_launcher() {
    local name="$1"
    local safe_name
    safe_name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

    log_info "Removing launcher: $name"
    proot_exec "$ALICIA_DISTRO_NAME" "rm -f /home/alicia/.local/share/applications/alicia-${safe_name}.desktop /home/alicia/Desktop/${name}.desktop" 2>/dev/null || true
    proot_exec "$ALICIA_DISTRO_NAME" "update-desktop-database /home/alicia/.local/share/applications/ 2>/dev/null" || true
    log_info "Launcher removed: $name"
}

# ui_list_launchers - List all Alicia launchers
ui_list_launchers() {
    proot_exec "$ALICIA_DISTRO_NAME" "ls -1 /home/alicia/.local/share/applications/alicia-*.desktop 2>/dev/null | while read f; do basename \"\$f\" .desktop | sed 's/alicia-//'; done" || echo "No launchers found"
}

# ============================================================================
# Panel Configuration Helpers
# ============================================================================

# ui_configure_panel - Configure XFCE panel
ui_configure_panel() {
    local panel_id="${1:-1}"
    local position="${2:-top}"
    local size="${3:-28}"

    log_info "Configuring XFCE panel $panel_id (position: $position, size: $size)"

    proot_exec "$ALICIA_DISTRO_NAME" bash -c "export DISPLAY=${ALICIA_DISPLAY}
xfconf-query -c xfce4-panel -p /panels/panel-${panel_id}/position -s 'p=6;x=0;y=0' 2>/dev/null || true
xfconf-query -c xfce4-panel -p /panels/panel-${panel_id}/size -s $size 2>/dev/null || true"

    log_info "Panel configured"
}

# ui_reset_panel - Reset XFCE panel to default
ui_reset_panel() {
    log_info "Resetting XFCE panel to default configuration"
    proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xfce4-panel --quit 2>/dev/null; rm -rf /home/alicia/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml 2>/dev/null; xfce4-panel &" 2>/dev/null || true
}

# ============================================================================
# Screen Resolution Management
# ============================================================================

# ui_set_resolution - Set display resolution
ui_set_resolution() {
    local resolution="${1:-1280x720}"
    log_info "Changing resolution to: $resolution"

    vnc_change_resolution "$resolution"

    # Also update xrandr if available
    proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xrandr --screen 0 -s $resolution 2>/dev/null" || true

    ui_notify "Alicia" "Resolution changed to $resolution" "low" 3000
}

# ============================================================================
# Accessibility Options
# ============================================================================

# ui_set_font_size - Set system font size for accessibility
ui_set_font_size() {
    local size="${1:-10}"
    local dpi=$((96 * size / 10))

    log_info "Setting font size: $size (DPI: $dpi)"

    proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xfconf-query -c xsettings -p /Xft/DPI -s $dpi 2>/dev/null" || true

    set_config_value "FONT_SIZE" "$size"
    set_config_value "DPI" "$dpi"
}

# ui_toggle_high_contrast - Toggle high contrast mode
ui_toggle_high_contrast() {
    local current
    current=$(get_config_value "HIGH_CONTRAST" "false")

    if [[ "$current" == "false" ]]; then
        log_info "Enabling high contrast mode"
        proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xfconf-query -c xsettings -p /Net/ThemeName -s 'HighContrast' 2>/dev/null" || true
        set_config_value "HIGH_CONTRAST" "true"
    else
        log_info "Disabling high contrast mode"
        local theme
        theme=$(get_config_value "GTK_THEME" "Adwaita")
        proot_exec "$ALICIA_DISTRO_NAME" "export DISPLAY=${ALICIA_DISPLAY}; xfconf-query -c xsettings -p /Net/ThemeName -s '$theme' 2>/dev/null" || true
        set_config_value "HIGH_CONTRAST" "false"
    fi
}

# ============================================================================
# Sound Volume Management
# ============================================================================

# ui_set_volume - Set audio volume level
ui_set_volume() {
    local level="${1:-50}"  # 0-100
    log_info "Setting volume to: $level%"

    proot_exec "$ALICIA_DISTRO_NAME" "amixer set Master ${level}% 2>/dev/null || pactl set-sink-volume 0 ${level}% 2>/dev/null" || {
        log_warn "Could not set volume - audio may not be available"
    }
    set_config_value "VOLUME" "$level"
}

# ui_get_volume - Get current volume level
ui_get_volume() {
    proot_exec "$ALICIA_DISTRO_NAME" "amixer get Master 2>/dev/null | grep -o '[0-9]*%' | head -1" || echo "0%"
}

# ui_toggle_mute - Toggle audio mute
ui_toggle_mute() {
    proot_exec "$ALICIA_DISTRO_NAME" "amixer set Master toggle 2>/dev/null || pactl set-sink-mute 0 toggle 2>/dev/null" || true
}

# ============================================================================
# Keyboard Layout Management
# ============================================================================

# ui_set_keyboard_layout - Set keyboard layout
ui_set_keyboard_layout() {
    local layout="${1:-us}"
    local variant="${2:-}"

    log_info "Setting keyboard layout: $layout ${variant:+variant: $variant}"

    proot_exec "$ALICIA_DISTRO_NAME" "setxkbmap $layout ${variant:+-variant $variant} 2>/dev/null" || true

    # Persist in XFCE config
    proot_exec "$ALICIA_DISTRO_NAME" bash -c "cat > /home/alicia/.config/alicia/keyboard.conf << KB_EOF
LAYOUT=$layout
VARIANT=$variant
KB_EOF"

    set_config_value "KEYBOARD_LAYOUT" "$layout"
    set_config_value "KEYBOARD_VARIANT" "$variant"
}

# ============================================================================
# Locale/Language Management
# ============================================================================

# ui_set_locale - Set system locale
ui_set_locale() {
    local locale="${1:-en_US.UTF-8}"

    log_info "Setting locale: $locale"
    proot_exec "$ALICIA_DISTRO_NAME" "sed -i 's/^# *\($locale\)/\1/' /etc/locale.gen 2>/dev/null; locale-gen $locale 2>/dev/null" || \
    proot_exec "$ALICIA_DISTRO_NAME" "echo 'export LANG=$locale' >> /home/alicia/.bashrc" 2>/dev/null || true

    set_config_value "LOCALE" "$locale"
}

# ============================================================================
# Welcome Screen Configuration
# ============================================================================

# ui_show_welcome - Show Alicia welcome screen
ui_show_welcome() {
    local welcome_text="Welcome to Alicia Desktop Environment v${ALICIA_VERSION:-2.0.0}

Proyecto Tomorrow presents Alicia - your complete Linux desktop on Android.

Getting Started:
1. Connect via VNC client to localhost:$ALICIA_VNC_PORT
2. Use the desktop as you would a normal PC
3. Access applications from the Applications menu
4. Configure settings through the Settings Manager

Keyboard Shortcuts:
- Ctrl+Alt+T: Open Terminal
- Ctrl+Alt+F: Open File Manager
- Ctrl+Alt+E: Open Text Editor

For help, visit: https://github.com/proyecto-tomorrow/alicia"

    ui_show_message "Welcome to Alicia" "$welcome_text"
}

# ui_show_about - Show about dialog
ui_show_about() {
    local about_text="Alicia Desktop Environment
Version ${ALICIA_VERSION:-2.0.0} '${ALICIA_CODENAME:-Tomorrow}'

Copyright (C) 2005-2025 Proyecto Tomorrow

A complete Linux desktop environment for Android,
powered by Termux, proot, and XFCE4.

This software is licensed under the GNU General
Public License v3.0 or later."

    ui_show_message "About Alicia" "$about_text"
}
