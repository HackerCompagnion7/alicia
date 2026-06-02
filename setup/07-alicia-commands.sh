#!/bin/bash
# ============================================================================
# 07-alicia-commands.sh - Alicia Internal Commands & Overlay Installation
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
# ============================================================================
# Author:       Proyecto Tomorrow
# Version:      3.1.0
# Description:  Creates ALL internal Alicia commands inside the proot
#               environment and copies the overlay to ensure executables
#               exist in the final Debian/Alpine system. Also installs
#               missing dependencies required by alicia-health, alicia-repair.
# ============================================================================

set -euo pipefail

# ============================================================================
# Script Identity
# ============================================================================
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="3.1.0"

# ============================================================================
# Source Alicia Libraries
# ============================================================================
for lib_file in "${SCRIPT_DIR}/../lib/"alicia-*.sh; do
    if [[ -f "$lib_file" ]]; then
        source "$lib_file" 2>/dev/null || true
    fi
done

# Fallback helpers
if ! declare -f log_info &>/dev/null; then
    readonly C_RESET='\033[0m'; readonly C_RED='\033[0;31m'; readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'; readonly C_BLUE='\033[0;34m'; readonly C_CYAN='\033[0;36m'
    readonly C_BOLD='\033[1m'; readonly C_BOLD_BLUE='\033[1;34m'
    log_debug()   { :; }
    log_info()    { printf "${C_GREEN}[INFO]${C_RESET}  %s\n" "$*"; }
    log_warn()    { printf "${C_YELLOW}[WARN]${C_RESET}  %s\n" "$*" >&2; }
    log_error()   { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$*" >&2; }
    log_section() { printf "\n${C_BOLD_BLUE}======== %s ========${C_RESET}\n" "$1"; }
fi

# ============================================================================
# Constants - MUST be defined globally before any function calls
# ============================================================================
readonly ALICIA_DIR="${HOME}/alicia"
readonly DISTRO_NAME="alpine"
readonly ALICIA_USER="alicia"
readonly ALICIA_USER_HOME="/home/alicia"
readonly ALICIA_BIN="/usr/bin"
readonly ALICIA_SHARE="/usr/share/alicia"
readonly ALICIA_VERSION_NUM="3.1.0"

# ============================================================================
# State Tracking
# ============================================================================
_SETUP_STATE_FILE="${ALICIA_DIR}/.setup-07-state"
declare -gA _COMPLETED_STEPS=()

step_completed() { [[ -n "${_COMPLETED_STEPS[${1:-}]:-}" ]]; }
mark_step_completed() { _COMPLETED_STEPS["$1"]="1"; echo "$1" >> "$_SETUP_STATE_FILE"; }
load_state() {
    if [[ -f "$_SETUP_STATE_FILE" ]]; then
        while IFS= read -r step; do _COMPLETED_STEPS["$step"]="1"; done < "$_SETUP_STATE_FILE"
        log_info "Loaded previous state: ${#_COMPLETED_STEPS[@]} steps completed"
    fi
}

# Helper: Execute command inside proot
proot_exec() {
    local cmd="$1"
    proot-distro login "$DISTRO_NAME" -- bash -c "$cmd" 2>&1
}

# ============================================================================
# PUNTO 9: Install Missing Dependencies
# ============================================================================
install_missing_dependencies() {
    log_section "Installing Missing Dependencies"

    if step_completed "install_deps"; then
        log_info "Dependencies already installed, skipping"
        return 0
    fi

    log_info "Installing required system packages for alicia commands..."

    proot_exec bash -c '
        # Update package lists
        apk update 2>/dev/null || apt-get update 2>/dev/null || true

        # Install packages needed by alicia-health (nslookup, ss, pgrep)
        apk add --no-cache \
            bind-tools \
            iproute2 \
            procps \
            2>/dev/null || \
        apt-get install -y \
            dnsutils \
            iproute2 \
            procps \
            2>/dev/null || true

        # Install packages needed by alicia-repair (gtk-update-icon-cache, update-desktop-database)
        apk add --no-cache \
            gtk+3.0 \
            desktop-file-utils \
            2>/dev/null || \
        apt-get install -y \
            gtk-update-icon-cache \
            desktop-file-utils \
            2>/dev/null || true

        # Install other useful tools
        apk add --no-cache \
            coreutils \
            findutils \
            sed \
            gawk \
            grep \
            curl \
            wget \
            2>/dev/null || true

        echo "Dependencies installation complete"
    '

    mark_step_completed "install_deps"
    log_info "Missing dependencies installed"
    return 0
}

# ============================================================================
# PUNTO 1+5: Create directories and internal scripts with logging
# ============================================================================
create_internal_scripts() {
    log_section "Creating Alicia Internal Scripts"
    log_info "Entering create_internal_scripts"

    if step_completed "create_internal_scripts"; then
        log_info "Internal scripts already created, skipping"
        return 0
    fi

    # PUNTO 1: Create directories INSIDE proot BEFORE writing files
    log_info "Creating directories: ${ALICIA_BIN} and ${ALICIA_SHARE}"
    proot_exec bash -c "
        mkdir -p ${ALICIA_BIN}
        mkdir -p ${ALICIA_SHARE}
        echo 'Directories created: ${ALICIA_BIN} ${ALICIA_SHARE}'
    "

    # --- alicia-install ---
    log_info "Creating alicia-install..."
    proot_exec bash -c 'cat > /usr/bin/alicia-install << "INSTALLEOF"
#!/bin/bash
# alicia-install - Install packages inside Alicia
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "Usage: alicia-install <package> [package2 ...]"
    echo "Example: alicia-install vim git python3"
    exit 1
fi

echo "[Alicia] Installing: $*"
if command -v apk &>/dev/null; then
    sudo apk add --no-cache "$@"
elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y "$@"
else
    echo "[Alicia] Error: No supported package manager found"
    exit 1
fi
echo "[Alicia] Installation complete: $*"
INSTALLEOF
chmod +x /usr/bin/alicia-install'

    # --- alicia-remove ---
    log_info "Creating alicia-remove..."
    proot_exec bash -c 'cat > /usr/bin/alicia-remove << "REMOVEEOF"
#!/bin/bash
# alicia-remove - Remove packages inside Alicia
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "Usage: alicia-remove <package> [package2 ...]"
    exit 1
fi

echo "[Alicia] Removing: $*"
if command -v apk &>/dev/null; then
    sudo apk del "$@"
elif command -v apt-get &>/dev/null; then
    sudo apt-get remove -y "$@"
else
    echo "[Alicia] Error: No supported package manager found"
    exit 1
fi
echo "[Alicia] Removal complete: $*"
REMOVEEOF
chmod +x /usr/bin/alicia-remove'

    # --- alicia-health (PUNTO 8: uses nslookup, ss, pgrep - deps installed above) ---
    log_info "Creating alicia-health..."
    proot_exec bash -c 'cat > /usr/bin/alicia-health << "HEALTHEOF"
#!/bin/bash
# alicia-health - System health check for Alicia
set -euo pipefail

echo "========================================="
echo "  Alicia Desktop Environment - Health Check"
echo "  Version: 3.1.0"
echo "========================================="
echo ""

PASS=0
FAIL=0
WARN=0

check_item() {
    local name="$1"
    local result="$2"
    if [[ "$result" == "OK" ]]; then
        printf "  [PASS] %s\n" "$name"
        ((PASS++))
    elif [[ "$result" == "WARN" ]]; then
        printf "  [WARN] %s\n" "$name"
        ((WARN++))
    else
        printf "  [FAIL] %s\n" "$name"
        ((FAIL++))
    fi
}

# Check VNC server
if pgrep -x Xvnc >/dev/null 2>&1 || pgrep -f vnc >/dev/null 2>&1; then
    check_item "VNC Server" "OK"
else
    check_item "VNC Server (not running)" "WARN"
fi

# Check X display
if [[ -e /tmp/.X1-lock ]] || [[ -e /tmp/.X11-unix/X1 ]]; then
    check_item "X Display" "OK"
else
    check_item "X Display (not available)" "WARN"
fi

# Check network (nslookup or host)
if nslookup google.com >/dev/null 2>&1 || host google.com >/dev/null 2>&1 || ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
    check_item "Network" "OK"
else
    check_item "Network (offline)" "WARN"
fi

# Check DNS
if nslookup google.com >/dev/null 2>&1 || host google.com >/dev/null 2>&1; then
    check_item "DNS Resolution" "OK"
else
    check_item "DNS Resolution (failed)" "FAIL"
fi

# Check listening ports (ss or netstat)
if command -v ss &>/dev/null; then
    LISTENING=$(ss -tlnp 2>/dev/null | grep -c LISTEN || echo 0)
    check_item "Listening Ports ($LISTENING)" "OK"
elif command -v netstat &>/dev/null; then
    LISTENING=$(netstat -tlnp 2>/dev/null | grep -c LISTEN || echo 0)
    check_item "Listening Ports ($LISTENING)" "OK"
else
    check_item "Port Scanner (ss/netstat not found)" "WARN"
fi

# Check disk space
AVAIL=$(df -m / 2>/dev/null | tail -1 | awk "{print \$4}")
if [[ -n "$AVAIL" ]] && [[ "$AVAIL" -gt 500 ]]; then
    check_item "Disk Space (${AVAIL}MB free)" "OK"
elif [[ -n "$AVAIL" ]] && [[ "$AVAIL" -gt 100 ]]; then
    check_item "Disk Space (${AVAIL}MB free - low)" "WARN"
else
    check_item "Disk Space (critical)" "FAIL"
fi

# Check memory
if command -v free &>/dev/null; then
    MEM_AVAIL=$(free -m 2>/dev/null | awk "/^Mem:/{print \$7}")
    if [[ -n "$MEM_AVAIL" ]] && [[ "$MEM_AVAIL" -gt 256 ]]; then
        check_item "Memory (${MEM_AVAIL}MB available)" "OK"
    else
        check_item "Memory (low: ${MEM_AVAIL}MB)" "WARN"
    fi
else
    check_item "Memory check (free not available)" "WARN"
fi

# Check desktop environment
if pgrep -f xfce4-session >/dev/null 2>&1; then
    check_item "XFCE Desktop" "OK"
elif pgrep -f fluxbox >/dev/null 2>&1; then
    check_item "Fluxbox Desktop" "OK"
else
    check_item "Desktop Environment (not running)" "WARN"
fi

# Check D-Bus
if pgrep -f dbus-daemon >/dev/null 2>&1; then
    check_item "D-Bus" "OK"
else
    check_item "D-Bus (not running)" "WARN"
fi

# Check PulseAudio
if pgrep -f pulseaudio >/dev/null 2>&1; then
    check_item "PulseAudio" "OK"
else
    check_item "PulseAudio (not running)" "WARN"
fi

echo ""
echo "========================================="
echo "  Results: $PASS passed, $WARN warnings, $FAIL failed"
echo "========================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
elif [[ $WARN -gt 0 ]]; then
    exit 2
else
    exit 0
fi
HEALTHEOF
chmod +x /usr/bin/alicia-health'

    # --- alicia-backup ---
    log_info "Creating alicia-backup..."
    proot_exec bash -c 'cat > /usr/bin/alicia-backup << "BACKUPEOF"
#!/bin/bash
# alicia-backup - Create/restore backups for Alicia
set -euo pipefail

BACKUP_DIR="/home/alicia/.alicia/backups"
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")

usage() {
    echo "Usage: alicia-backup <command> [options]"
    echo ""
    echo "Commands:"
    echo "  create [name]     Create a backup (default name: auto)"
    echo "  restore <file>    Restore from backup file"
    echo "  list              List available backups"
    echo "  delete <file>     Delete a backup"
    echo "  verify <file>     Verify backup integrity"
    echo ""
    echo "Examples:"
    echo "  alicia-backup create mybackup"
    echo "  alicia-backup list"
    echo "  alicia-backup restore mybackup_20250101.tar.gz"
}

backup_create() {
    local name="${1:-auto}"
    mkdir -p "$BACKUP_DIR"
    local backup_file="${BACKUP_DIR}/${name}_${TIMESTAMP}.tar.gz"

    echo "[Alicia] Creating backup: $name"
    echo "[Alicia] Saving to: $backup_file"

    tar -czf "$backup_file" \
        -C /home/alicia \
        .config \
        .bashrc \
        .bash_aliases \
        .gitconfig \
        Desktop \
        Documents \
        Projects \
        2>/dev/null || {
        echo "[Alicia] Warning: Some files could not be backed up"
    }

    local size
    size=$(du -h "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")
    echo "[Alicia] Backup created: $backup_file ($size)"
}

backup_restore() {
    local backup_file="$1"
    if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
        echo "[Alicia] Error: Backup file not found"
        exit 1
    fi

    echo "[Alicia] Restoring from: $backup_file"
    tar -xzf "$backup_file" -C /home/alicia/
    echo "[Alicia] Restore complete"
}

backup_list() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        echo "[Alicia] No backups found"
        return 0
    fi

    echo "[Alicia] Available Backups:"
    echo "=========================================="
    for f in "${BACKUP_DIR}"/*.tar.gz; do
        if [[ -f "$f" ]]; then
            local size
            size=$(du -h "$f" | cut -f1)
            local mtime
            mtime=$(stat -c %y "$f" 2>/dev/null | cut -d. -f1 || echo "unknown")
            printf "  %-40s %s  %s\n" "$(basename "$f")" "$size" "$mtime"
        fi
    done
}

backup_delete() {
    local backup_file="$1"
    if [[ -f "$backup_file" ]]; then
        rm -f "$backup_file"
        echo "[Alicia] Deleted: $(basename "$backup_file")"
    else
        echo "[Alicia] File not found: $backup_file"
    fi
}

backup_verify() {
    local backup_file="$1"
    if [[ ! -f "$backup_file" ]]; then
        echo "[Alicia] File not found: $backup_file"
        exit 1
    fi

    echo "[Alicia] Verifying: $(basename "$backup_file")"
    if tar -tzf "$backup_file" &>/dev/null; then
        echo "[Alicia] Integrity: OK"
    else
        echo "[Alicia] Integrity: FAILED (corrupt archive)"
        exit 1
    fi
}

# Main
case "${1:-}" in
    create)  backup_create "${2:-auto}" ;;
    restore) backup_restore "$2" ;;
    list)    backup_list ;;
    delete)  backup_delete "$2" ;;
    verify)  backup_verify "$2" ;;
    *)       usage ;;
esac
BACKUPEOF
chmod +x /usr/bin/alicia-backup'

    # --- alicia-repair ---
    log_info "Creating alicia-repair..."
    proot_exec bash -c 'cat > /usr/bin/alicia-repair << "REPAIREF"
#!/bin/bash
# alicia-repair - Repair common Alicia desktop issues
set -euo pipefail

echo "[Alicia] Running desktop repair..."
echo ""

# 1. Fix icon cache
echo "[Alicia] Rebuilding icon cache..."
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -f /usr/share/icons/Papirus 2>/dev/null || true
    gtk-update-icon-cache -f /usr/share/icons/Adwaita 2>/dev/null || true
    for theme in /usr/share/icons/*; do
        gtk-update-icon-cache -f "$theme" 2>/dev/null || true
    done
    echo "  Icon cache rebuilt"
else
    echo "  gtk-update-icon-cache not available - skipping"
fi

# 2. Fix desktop database
echo "[Alicia] Updating desktop database..."
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
    update-desktop-database /home/alicia/.local/share/applications 2>/dev/null || true
    echo "  Desktop database updated"
else
    echo "  update-desktop-database not available - skipping"
fi

# 3. Fix D-Bus
echo "[Alicia] Restarting D-Bus..."
if command -v dbus-launch &>/dev/null; then
    pkill -f dbus-daemon 2>/dev/null || true
    sleep 1
    eval "$(dbus-launch --sh-syntax 2>/dev/null)" || true
    echo "  D-Bus restarted"
fi

# 4. Fix MIME defaults
echo "[Alicia] Updating MIME database..."
if command -v update-mime-database &>/dev/null; then
    update-mime-database /usr/share/mime 2>/dev/null || true
    echo "  MIME database updated"
fi

# 5. Fix font cache
echo "[Alicia] Rebuilding font cache..."
if command -v fc-cache &>/dev/null; then
    fc-cache -f 2>/dev/null || true
    echo "  Font cache rebuilt"
fi

# 6. Fix GTK modules
echo "[Alicia] Updating GTK modules..."
if command -v gtk-query-modules &>/dev/null; then
    gtk-query-modules --update-cache 2>/dev/null || true
fi
if command -v gdk-pixbuf-query-loaders &>/dev/null; then
    gdk-pixbuf-query-loaders --update-cache 2>/dev/null || true
fi
echo "  GTK modules updated"

# 7. Fix GSettings schemas
echo "[Alicia] Compiling GSettings schemas..."
if command -v glib-compile-schemas &>/dev/null; then
    glib-compile-schemas /usr/share/glib-2.0/schemas 2>/dev/null || true
    echo "  GSettings schemas compiled"
fi

# 8. Fix permissions
echo "[Alicia] Fixing permissions..."
chown -R alicia:alicia /home/alicia/.config 2>/dev/null || true
chown -R alicia:alicia /home/alicia/.local 2>/dev/null || true
chmod +x /home/alicia/Desktop/*.desktop 2>/dev/null || true
echo "  Permissions fixed"

# 9. Restart desktop if running
echo "[Alicia] Checking desktop session..."
if pgrep -f xfce4-session &>/dev/null; then
    echo "  Desktop is running - restart to apply changes"
    echo "  Use: pkill xfce4-session && DISPLAY=:1 startxfce4 &"
else
    echo "  Desktop not running"
fi

echo ""
echo "[Alicia] Repair complete!"
REPAIREF
chmod +x /usr/bin/alicia-repair'

    # --- alicia-about ---
    log_info "Creating alicia-about..."
    proot_exec bash -c "cat > /usr/bin/alicia-about << 'ABOUTEOF'
#!/bin/bash
# alicia-about - Show Alicia Desktop Environment information
set -euo pipefail

echo '========================================='
echo '  Alicia Desktop Environment'
echo '  Version: ${ALICIA_VERSION_NUM}'
echo '  Codename: Tomorrow'
echo '========================================='
echo ''
echo '  Copyright (C) 2005-2025 Proyecto Tomorrow'
echo ''
echo '  A complete Linux desktop for Android,'
echo '  powered by Termux, proot, and XFCE4.'
echo ''
echo '  Licensed under GNU GPL v3.0+'
echo ''
echo '  System Information:'
echo '    Kernel:    '\$(uname -r)
echo '    Arch:      '\$(uname -m)
echo '    User:      '\$(whoami)
echo '    Hostname:  '\$(hostname 2>/dev/null || echo alicia)
echo '    Uptime:    '\$(uptime -p 2>/dev/null || uptime)
echo '    Shell:     '\$SHELL
echo ''
echo '  VNC Access:'
echo '    Port:      5901'
echo '    Password:  alicia'
echo '    Display:   :1'
echo ''
echo '  Quick Commands:'
echo '    alicia-health    - Check system health'
echo '    alicia-repair    - Repair common issues'
echo '    alicia-backup    - Manage backups'
echo '    alicia-install   - Install packages'
echo '    alicia-remove    - Remove packages'
echo '========================================='
ABOUTEOF
chmod +x /usr/bin/alicia-about"

    # --- PUNTO 8: alicia-tool-store.sh in /usr/share/alicia ---
    log_info "Creating alicia-tool-store.sh in ${ALICIA_SHARE}..."
    proot_exec bash -c 'cat > /usr/share/alicia/tool-store.sh << "STOREEOF"
#!/bin/bash
# alicia-tool-store - Alicia tool management utility
# Called by /usr/bin/alicia-tool-store wrapper
set -euo pipefail

ALICIA_SHARE_DIR="/usr/share/alicia"
TOOL_STORE_DIR="/home/alicia/.alicia/tools"

usage() {
    echo "Alicia Tool Store - Manage desktop tools and utilities"
    echo ""
    echo "Usage: alicia-tool-store <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list              List available tools"
    echo "  install <tool>    Install a tool"
    echo "  remove <tool>     Remove a tool"
    echo "  update <tool>     Update a tool"
    echo "  info <tool>       Show tool information"
    echo "  search <term>     Search for tools"
    echo "  categories        List tool categories"
}

list_tools() {
    echo "Alicia Tool Store - Available Tools"
    echo "===================================="
    echo ""
    echo "  Development:"
    echo "    gcc, g++, make, cmake, python3, nodejs, npm, go, rust"
    echo ""
    echo "  Editors:"
    echo "    vim, nano, mousepad, geany, code (VS Code OSS)"
    echo ""
    echo "  Graphics:"
    echo "    gimp, inkscape, imagemagick, feh, ristretto"
    echo ""
    echo "  Internet:"
    echo "    firefox, midori, wget, curl, openssh"
    echo ""
    echo "  Office:"
    echo "    abiword, gnumeric, evince"
    echo ""
    echo "  Media:"
    echo "    mpv, ffmpeg, vlc, audacity"
    echo ""
    echo "  System:"
    echo "    htop, mc, ranger, neofetch, tree"
    echo ""
    echo "  Use: alicia-tool-store install <tool>"
}

install_tool() {
    local tool="${1:-}"
    if [[ -z "$tool" ]]; then
        echo "Error: Specify a tool to install"
        return 1
    fi

    echo "[Alicia] Installing tool: $tool"
    if command -v apk &>/dev/null; then
        sudo apk add --no-cache "$tool" 2>&1 || {
            echo "[Alicia] Failed to install: $tool"
            return 1
        }
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y "$tool" 2>&1 || {
            echo "[Alicia] Failed to install: $tool"
            return 1
        }
    else
        echo "[Alicia] No package manager available"
        return 1
    fi
    echo "[Alicia] Tool installed: $tool"
}

remove_tool() {
    local tool="${1:-}"
    if [[ -z "$tool" ]]; then
        echo "Error: Specify a tool to remove"
        return 1
    fi

    echo "[Alicia] Removing tool: $tool"
    if command -v apk &>/dev/null; then
        sudo apk del "$tool" 2>&1 || true
    elif command -v apt-get &>/dev/null; then
        sudo apt-get remove -y "$tool" 2>&1 || true
    fi
    echo "[Alicia] Tool removed: $tool"
}

search_tool() {
    local term="${1:-}"
    if [[ -z "$term" ]]; then
        echo "Error: Specify a search term"
        return 1
    fi
    echo "[Alicia] Searching for: $term"
    if command -v apk &>/dev/null; then
        apk search "$term" 2>/dev/null | head -20
    elif command -v apt-cache &>/dev/null; then
        apt-cache search "$term" 2>/dev/null | head -20
    fi
}

show_categories() {
    echo "Alicia Tool Categories"
    echo "======================"
    echo "  development  - Programming languages and tools"
    echo "  editors      - Text and code editors"
    echo "  graphics     - Image editing and viewing"
    echo "  internet     - Web browsers and network tools"
    echo "  office       - Document and spreadsheet tools"
    echo "  media        - Audio and video players"
    echo "  system       - System utilities and monitors"
    echo "  security     - Security and encryption tools"
}

case "${1:-}" in
    list)        list_tools ;;
    install)     install_tool "${2:-}" ;;
    remove)      remove_tool "${2:-}" ;;
    update)      echo "Update not yet implemented for ${2:-}" ;;
    info)        echo "Tool info not yet available for ${2:-}" ;;
    search)      search_tool "${2:-}" ;;
    categories)  show_categories ;;
    *)           usage ;;
esac
STOREEOF
chmod +x /usr/share/alicia/tool-store.sh"

    # --- PUNTO 7+8: system-info.sh in /usr/share/alicia (FIXED: local inside function) ---
    log_info "Creating system-info.sh in ${ALICIA_SHARE}..."
    proot_exec bash -c 'cat > /usr/share/alicia/system-info.sh << "INFOEOF"
#!/bin/bash
# alicia-system-info - Gather and display system information
# Called by /usr/bin/alicia-system-info wrapper
set -euo pipefail

show_system_info() {
    local cpu_model
    local cpu_cores
    local mem_total
    local mem_avail
    local mem_used
    local disk_total
    local disk_avail
    local disk_used
    local hostname_val
    local kernel_val
    local arch_val
    local uptime_val

    cpu_model=$(cat /proc/cpuinfo 2>/dev/null | grep "model name" | head -1 | cut -d: -f2 | xargs || echo "Unknown")
    cpu_cores=$(nproc 2>/dev/null || echo 1)
    mem_total=$(free -m 2>/dev/null | awk "/^Mem:/{print \$2}" || echo 0)
    mem_avail=$(free -m 2>/dev/null | awk "/^Mem:/{print \$7}" || echo 0)
    mem_used=$((mem_total - mem_avail))
    disk_total=$(df -m / 2>/dev/null | tail -1 | awk "{print \$2}" || echo 0)
    disk_avail=$(df -m / 2>/dev/null | tail -1 | awk "{print \$4}" || echo 0)
    disk_used=$((disk_total - disk_avail))
    hostname_val=$(hostname 2>/dev/null || echo "alicia")
    kernel_val=$(uname -r)
    arch_val=$(uname -m)
    uptime_val=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "unknown")

    echo "========================================="
    echo "  Alicia System Information"
    echo "========================================="
    echo ""
    echo "  Hostname:    $hostname_val"
    echo "  Kernel:      $kernel_val"
    echo "  Architecture: $arch_val"
    echo "  Uptime:      $uptime_val"
    echo ""
    echo "  CPU:         $cpu_model"
    echo "  Cores:       $cpu_cores"
    echo ""
    echo "  Memory:"
    echo "    Total:     ${mem_total}MB"
    echo "    Used:      ${mem_used}MB"
    echo "    Available: ${mem_avail}MB"
    echo ""
    echo "  Storage (/):"
    echo "    Total:     ${disk_total}MB"
    echo "    Used:      ${disk_used}MB"
    echo "    Available: ${disk_avail}MB"
    echo ""
    echo "  Network:"
    echo "    IP:        $(ip route get 8.8.8.8 2>/dev/null | awk "{print \$7; exit}" || echo "N/A")"
    echo ""
    echo "  Services:"
    echo "    VNC:       $(pgrep -x Xvnc >/dev/null 2>&1 && echo "Running" || echo "Stopped")"
    echo "    D-Bus:     $(pgrep -f dbus-daemon >/dev/null 2>&1 && echo "Running" || echo "Stopped")"
    echo "    PulseAudio: $(pgrep -f pulseaudio >/dev/null 2>&1 && echo "Running" || echo "Stopped")"
    echo "========================================="
}

show_system_info
INFOEOF
chmod +x /usr/share/alicia/system-info.sh"

    # --- PUNTO 8: Create WRAPPERS in /usr/bin that call /usr/share/alicia/ scripts ---
    log_info "Creating wrapper: alicia-tool-store..."
    proot_exec bash -c 'cat > /usr/bin/alicia-tool-store << "WRAPPEREOF"
#!/bin/bash
# alicia-tool-store - Wrapper for tool store utility
exec /usr/share/alicia/tool-store.sh "$@"
WRAPPEREOF
chmod +x /usr/bin/alicia-tool-store'

    log_info "Creating wrapper: alicia-system-info..."
    proot_exec bash -c 'cat > /usr/bin/alicia-system-info << "WRAPPEREOF"
#!/bin/bash
# alicia-system-info - Wrapper for system info utility
exec /usr/share/alicia/system-info.sh "$@"
WRAPPEREOF
chmod +x /usr/bin/alicia-system-info'

    # --- alicia-vnc-info ---
    log_info "Creating alicia-vnc-info..."
    proot_exec bash -c 'cat > /usr/bin/alicia-vnc-info << "VNCINFOEOF"
#!/bin/bash
# alicia-vnc-info - Display VNC connection information
set -euo pipefail

LOCAL_IP=$(ip route get 8.8.8.8 2>/dev/null | awk "{print \$7; exit}" || echo "127.0.0.1")

echo "========================================="
echo "  Alicia VNC Connection Information"
echo "========================================="
echo ""
echo "  VNC Address:  ${LOCAL_IP}:5901"
echo "  Password:     alicia"
echo "  Display:      :1"
echo ""
echo "  noVNC (Browser):"
echo "  http://${LOCAL_IP}:6080/vnc.html"
echo ""
echo "  Connect from Android:"
echo "  1. Install a VNC Viewer (e.g., RealVNC, TigerVNC)"
echo "  2. Enter address: ${LOCAL_IP}:5901"
echo "  3. Enter password: alicia"
echo "========================================="
VNCINFOEOF
chmod +x /usr/bin/alicia-vnc-info'

    # --- alicia-vnc-start ---
    log_info "Creating alicia-vnc-start..."
    proot_exec bash -c 'cat > /usr/bin/alicia-vnc-start << "VNCSTARTEOF"
#!/bin/bash
# alicia-vnc-start - Start VNC server inside proot
set -euo pipefail

DISPLAY_NUM="${1:-1}"
RESOLUTION="${2:-1280x720}"

echo "[Alicia] Starting VNC server on display :${DISPLAY_NUM}..."

# Create VNC directory
mkdir -p /home/alicia/.vnc 2>/dev/null || true

# Create xstartup if not exists
if [[ ! -f /home/alicia/.vnc/xstartup ]]; then
    cat > /home/alicia/.vnc/xstartup << XSTARTUP
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
export XDG_CURRENT_DESKTOP="XFCE"

if command -v dbus-launch &>/dev/null; then
    eval \\\$(dbus-launch --sh-syntax)
fi

if command -v startxfce4 &>/dev/null; then
    exec startxfce4
elif command -v xfce4-session &>/dev/null; then
    exec xfce4-session
else
    exec xterm
fi
XSTARTUP
    chmod +x /home/alicia/.vnc/xstartup
fi

# Set VNC password if not set
if [[ ! -f /home/alicia/.vnc/passwd ]]; then
    echo "alicia" | vncpasswd -f > /home/alicia/.vnc/passwd 2>/dev/null
    chmod 600 /home/alicia/.vnc/passwd 2>/dev/null
fi

# Start VNC
vncserver :${DISPLAY_NUM} -geometry ${RESOLUTION} -depth 24 -localhost no 2>&1 || {
    echo "[Alicia] Error: Failed to start VNC server"
    exit 1
}

echo "[Alicia] VNC server started on :${DISPLAY_NUM}"
echo "[Alicia] Connect to: localhost:$((5900 + DISPLAY_NUM))"
VNCSTARTEOF
chmod +x /usr/bin/alicia-vnc-start'

    # --- alicia-vnc-stop ---
    log_info "Creating alicia-vnc-stop..."
    proot_exec bash -c 'cat > /usr/bin/alicia-vnc-stop << "VNCSTOPEOF"
#!/bin/bash
# alicia-vnc-stop - Stop VNC server inside proot
set -euo pipefail

DISPLAY_NUM="${1:-1}"

echo "[Alicia] Stopping VNC server on display :${DISPLAY_NUM}..."
vncserver -kill :${DISPLAY_NUM} 2>/dev/null || {
    pkill -f "Xvnc :${DISPLAY_NUM}" 2>/dev/null || {
        echo "[Alicia] No VNC server found on :${DISPLAY_NUM}"
        exit 0
    }
}
echo "[Alicia] VNC server stopped"
VNCSTOPEOF
chmod +x /usr/bin/alicia-vnc-stop'

    # --- alicia-update ---
    log_info "Creating alicia-update..."
    proot_exec bash -c 'cat > /usr/bin/alicia-update << "UPDATEEOF"
#!/bin/bash
# alicia-update - Update system packages
set -euo pipefail

echo "[Alicia] Updating system packages..."
if command -v apk &>/dev/null; then
    sudo apk update 2>&1
    sudo apk upgrade --no-cache 2>&1
elif command -v apt-get &>/dev/null; then
    sudo apt-get update 2>&1
    sudo apt-get upgrade -y 2>&1
else
    echo "[Alicia] No supported package manager"
    exit 1
fi
echo "[Alicia] System updated successfully"
UPDATEEOF
chmod +x /usr/bin/alicia-update'

    # --- Verify all scripts were created ---
    log_info "Verifying created scripts..."
    local missing=()
    for cmd in alicia-install alicia-remove alicia-health alicia-backup alicia-repair alicia-about alicia-tool-store alicia-system-info alicia-vnc-info alicia-vnc-start alicia-vnc-stop alicia-update; do
        if proot_exec "test -x /usr/bin/${cmd}" 2>/dev/null; then
            log_info "  OK: /usr/bin/${cmd}"
        else
            log_error "  MISSING: /usr/bin/${cmd}"
            missing+=("$cmd")
        fi
    done

    for share_file in tool-store.sh system-info.sh; do
        if proot_exec "test -x /usr/share/alicia/${share_file}" 2>/dev/null; then
            log_info "  OK: /usr/share/alicia/${share_file}"
        else
            log_error "  MISSING: /usr/share/alicia/${share_file}"
            missing+=("$share_file")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing scripts: ${missing[*]}"
        return 1
    fi

    mark_step_completed "create_internal_scripts"
    log_info "Exiting create_internal_scripts - all scripts created successfully"
    return 0
}

# ============================================================================
# PUNTO 2: Copy overlay to proot (ensure overlay files exist in final system)
# ============================================================================
copy_overlay_to_proot() {
    log_section "Copying Overlay to Proot Environment"

    if step_completed "copy_overlay"; then
        log_info "Overlay already copied, skipping"
        return 0
    fi

    local overlay_dir="${SCRIPT_DIR}/../rootfs-overlay"

    # If rootfs-overlay directory exists in the project, copy it
    if [[ -d "$overlay_dir" ]]; then
        log_info "Found rootfs-overlay directory, copying to proot..."
        # Copy each file preserving structure
        if [[ -d "${overlay_dir}/usr/bin" ]]; then
            for file in "${overlay_dir}/usr/bin/"*; do
                if [[ -f "$file" ]]; then
                    local basename
                    basename=$(basename "$file")
                    log_info "  Copying: /usr/bin/${basename}"
                    proot_exec "cat > /usr/bin/${basename}" < "$file" 2>/dev/null || true
                    proot_exec "chmod +x /usr/bin/${basename}" 2>/dev/null || true
                fi
            done
        fi
        if [[ -d "${overlay_dir}/usr/share/alicia" ]]; then
            proot_exec "mkdir -p /usr/share/alicia"
            for file in "${overlay_dir}/usr/share/alicia/"*; do
                if [[ -f "$file" ]]; then
                    local basename
                    basename=$(basename "$file")
                    log_info "  Copying: /usr/share/alicia/${basename}"
                    proot_exec "cat > /usr/share/alicia/${basename}" < "$file" 2>/dev/null || true
                    proot_exec "chmod +x /usr/share/alicia/${basename}" 2>/dev/null || true
                fi
            done
        fi
    else
        log_info "No rootfs-overlay directory found - scripts were created directly in proot"
    fi

    mark_step_completed "copy_overlay"
    log_info "Overlay copy complete"
    return 0
}

# ============================================================================
# PUNTO 3: Ensure .bashrc is sourced with alicia aliases + Termux-side aliases
# ============================================================================
configure_termux_aliases() {
    log_section "Configuring Termux-Side Aliases"

    if step_completed "termux_aliases"; then
        log_info "Termux aliases already configured, skipping"
        return 0
    fi

    log_info "Adding alicia commands to Termux .bashrc..."

    # Add aliases to Termux .bashrc (NOT inside proot)
    local bashrc="${HOME}/.bashrc"
    local marker="# >>> alicia-commands >>>"

    if ! grep -q "$marker" "$bashrc" 2>/dev/null; then
        cat >> "$bashrc" << 'TERMUX_ALIASES'

# >>> alicia-commands >>>
# Alicia Desktop Environment - Termux-side commands
alias alicia-start='${HOME}/alicia/scripts/start.sh'
alias alicia-stop='${HOME}/alicia/scripts/stop.sh'
alias alicia-shell='proot-distro login alpine'
alias alicia-status='${HOME}/alicia/scripts/status.sh'
alias alicia-config='${HOME}/alicia/scripts/config.sh'
alias alicia-update='${HOME}/alicia/scripts/update.sh'
alias alicia-backup='${HOME}/alicia/scripts/backup.sh'
alias alicia-watchdog='${HOME}/alicia/scripts/watchdog.sh'
alias alicia-install='${HOME}/alicia/scripts/install.sh'
# <<< alicia-commands <<<

# Auto-source after first install
if [[ -f "${HOME}/.bashrc" ]]; then
    source "${HOME}/.bashrc" 2>/dev/null || true
fi
TERMUX_ALIASES
        log_info "Termux aliases added to .bashrc"
    else
        log_info "Termux aliases already present in .bashrc"
    fi

    # Also source it now so current session has the aliases
    source "$bashrc" 2>/dev/null || true

    mark_step_completed "termux_aliases"
    log_info "Termux aliases configured - run 'source ~/.bashrc' or open new session"
    return 0
}

# ============================================================================
# PUNTO 6: Verify no corrupt characters in created scripts
# ============================================================================
verify_script_integrity() {
    log_section "Verifying Script Integrity (UTF-8)"

    if step_completed "verify_integrity"; then
        log_info "Integrity already verified, skipping"
        return 0
    fi

    log_info "Checking for corrupt UTF-8 characters..."

    local corrupt_found=false
    local alicia_scripts
    alicia_scripts=$(find "${SCRIPT_DIR}/.." -name "*.sh" -type f 2>/dev/null)

    while IFS= read -r script; do
        if [[ -f "$script" ]]; then
            # Check for common corrupt CJK characters that indicate bad encoding
            if grep -P '[\x{9888}\x{6672}\x{6128}\x{8DEF}\x{4E00}-\x{9FFF}]' "$script" 2>/dev/null | head -1 | grep -q .; then
                log_warn "  Corrupt characters found in: $script"
                corrupt_found=true
            fi
        fi
    done <<< "$alicia_scripts"

    if [[ "$corrupt_found" == "true" ]]; then
        log_warn "Some files contain non-ASCII characters that may be corrupt"
        log_warn "This is usually caused by bad heredoc closures"
    else
        log_info "No corrupt characters detected"
    fi

    mark_step_completed "verify_integrity"
    return 0
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    load_state

    log_section "Alicia Commands Installation (Step 07)"

    # PUNTO 9: Install missing dependencies first
    install_missing_dependencies

    # PUNTO 1+5: Create directories and all internal scripts
    create_internal_scripts

    # PUNTO 2: Copy overlay if it exists
    copy_overlay_to_proot

    # PUNTO 3: Configure Termux-side aliases
    configure_termux_aliases

    # PUNTO 6: Verify script integrity
    verify_script_integrity

    log_section "Step 07 Complete"
    log_info "All Alicia commands installed successfully"
    return 0
}

main "$@"
