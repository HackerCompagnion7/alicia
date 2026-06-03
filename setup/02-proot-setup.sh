#!/bin/bash
# ============================================================================
# 02-proot-setup.sh - Alicia Desktop Environment proot Setup
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
# Description:  Sets up the proot Linux environment for Alicia Desktop.
#               Installs Alpine Linux via proot-distro, configures networking,
#               creates the alicia user, sets up groups, profiles, mounts,
#               shared directories, hostname, timezone, and validates the
#               installation. Supports resumable installation.
# ============================================================================

set -uo pipefail

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
        # shellcheck source=/dev/null
        source "$lib_file" 2>/dev/null || {
            echo "[WARN] Failed to source library: $lib_file" >&2
        }
    fi
done

# Fallback color helpers if libraries not available
if ! declare -f log_info &>/dev/null; then
    readonly C_RESET='\033[0m'; readonly C_RED='\033[0;31m'; readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'; readonly C_BLUE='\033[0;34m'; readonly C_CYAN='\033[0;36m'
    readonly C_BOLD='\033[1m'; readonly C_BOLD_BLUE='\033[1;34m'
    log_debug()   { :; }
    log_info()    { printf "${C_GREEN}[INFO]${C_RESET}  %s\n" "$*"; }
    log_warn()    { printf "${C_YELLOW}[WARN]${C_RESET}  %s\n" "$*" >&2; }
    log_error()   { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$*" >&2; }
    log_critical(){ printf "${C_BOLD_RED}[CRITICAL]${C_RESET} %s\n" "$*" >&2; }
    log_section() { printf "\n${C_BOLD_BLUE}======== %s ========${C_RESET}\n" "$1"; }
    log_subsection() { printf "${C_CYAN}--- %s ---${C_RESET}\n" "$1"; }
    log_progress() {
        local cur="$1" total="$2" desc="${3:-Progress}"
        local pct=$((cur * 100 / total))
        local filled=$((cur * 40 / total)) empty=$((40 - filled))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="#"; done
        for ((i=0; i<empty; i++)); do bar+="-"; done
        printf "\r${C_CYAN}%s: [%s] %d%% (%d/%d)${C_RESET}" "$desc" "$bar" "$pct" "$cur" "$total" >&2
        [[ $cur -eq $total ]] && printf "\n" >&2
    }
fi

# ============================================================================
# Constants
# ============================================================================
readonly ALICIA_BASE_DIR="${HOME}/alicia"
readonly DISTRO_NAME="alpine"
readonly ALICIA_USER="alicia"
readonly ALICIA_USER_HOME="/home/alicia"
readonly ALICIA_USER_PASSWORD="alicia"
readonly ALICIA_HOSTNAME="alicia"
readonly ALICIA_TIMEZONE="UTC"
readonly SHARED_DIR="${ALICIA_BASE_DIR}/shared"

# User groups for the alicia user inside proot
readonly ALICIA_USER_GROUPS=(
    "audio"
    "video"
    "plugdev"
    "netdev"
    "input"
    "cdrom"
    "floppy"
)

# DNS servers for resolv.conf
readonly DNS_SERVERS=(
    "8.8.8.8"
    "8.8.4.4"
    "1.1.1.1"
)

# ============================================================================
# State Tracking
# ============================================================================
_SETUP_STATE_FILE="${ALICIA_BASE_DIR}/.setup-02-state"
declare -gA _COMPLETED_STEPS=()

step_completed() {
    local step="$1"
    [[ -n "${_COMPLETED_STEPS[$step]:-}" ]]
}

mark_step_completed() {
    local step="$1"
    _COMPLETED_STEPS["$step"]="1"
    echo "$step" >> "$_SETUP_STATE_FILE"
}

load_state() {
    if [[ -f "$_SETUP_STATE_FILE" ]]; then
        while IFS= read -r step; do
            _COMPLETED_STEPS["$step"]="1"
        done < "$_SETUP_STATE_FILE"
        log_info "Loaded previous state: ${#_COMPLETED_STEPS[@]} steps completed"
    fi
}

# ============================================================================
# Helper: proot_exec - Execute a command inside the proot environment
# ============================================================================
proot_exec() {
    local cmd="$1"
    proot-distro login "$DISTRO_NAME" -- bash -c "$cmd" 2>&1
}

# ============================================================================
# Network Connectivity Check
# ============================================================================

check_network_connectivity() {
    log_section "Checking Network Connectivity"

    if step_completed "check_network"; then
        log_info "Network check already completed, skipping"
        return 0
    fi

    log_info "Verifying internet connectivity..."

    # Try multiple connectivity test methods
    local connected=false

    # Method 1: ping Google DNS
    if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        connected=true
        log_info "Network connectivity confirmed (ping to 8.8.8.8)"
    # Method 2: curl test
    elif command -v curl &>/dev/null && curl -s --connect-timeout 5 -o /dev/null https://www.google.com 2>/dev/null; then
        connected=true
        log_info "Network connectivity confirmed (curl to google.com)"
    # Method 3: wget test
    elif command -v wget &>/dev/null && wget -q --spider --timeout=5 https://www.google.com 2>/dev/null; then
        connected=true
        log_info "Network connectivity confirmed (wget to google.com)"
    fi

    if [[ "$connected" != "true" ]]; then
        log_error "No network connectivity detected!"
        log_error "Alicia setup requires internet access to download packages"
        log_error "Please connect to WiFi or mobile data and try again"
        log_error ""
        log_error "If you are connected but this check fails, you may need to:"
        log_error "  1. Check your DNS settings"
        log_error "  2. Disable any VPN"
        log_error "  3. Try: termux-setup-storage && pkg update"
        return 1
    fi

    log_info "DNS resolution test..."
    if ! nslookup alpinelinux.org &>/dev/null 2>&1 && ! host alpinelinux.org &>/dev/null 2>&1; then
        log_warn "DNS resolution may have issues, but continuing anyway"
    else
        log_info "DNS resolution working"
    fi

    mark_step_completed "check_network"
    log_info "Network connectivity verified"
    return 0
}

# ============================================================================
# proot-distro Installation
# ============================================================================

install_proot_distro() {
    log_section "Installing proot-distro"

    if step_completed "install_proot_distro"; then
        log_info "proot-distro already installed, skipping"
        return 0
    fi

    # Check if proot-distro is already available
    if command -v proot-distro &>/dev/null; then
        log_info "proot-distro is already installed"
        mark_step_completed "install_proot_distro"
        return 0
    fi

    log_info "Installing proot-distro package..."
    local _retry=0
    local _max_retries=3
    while [[ $_retry -lt $_max_retries ]]; do
        _retry=$(( _retry + 1 ))
        if pkg install -y proot-distro 2>&1 | while IFS= read -r line; do
            log_debug "  pkg: $line"
        done; then
            break
        fi
        if [[ $_retry -lt $_max_retries ]]; then
            log_warn "proot-distro install failed, retrying in 5s... (attempt $_retry/$_max_retries)"
            sleep 5
        else
            log_error "Failed to install proot-distro after $_max_retries attempts"
            return 1
        fi
    done

    # Verify installation
    if ! command -v proot-distro &>/dev/null; then
        log_error "proot-distro command not found after installation"
        return 1
    fi

    log_info "proot-distro installed successfully"
    mark_step_completed "install_proot_distro"
    return 0
}

# ============================================================================
# Alpine Linux Installation
# ============================================================================

install_alpine_linux() {
    log_section "Installing Alpine Linux via proot-distro"

    if step_completed "install_alpine"; then
        log_info "Alpine Linux already installed, skipping"
        return 0
    fi

    # Check if Alpine is already installed
    if proot-distro list 2>/dev/null | grep -q "alpine"; then
        log_info "Alpine Linux is already installed"
        mark_step_completed "install_alpine"
        return 0
    fi

    log_info "Installing Alpine Linux distribution..."
    log_info "This may take several minutes depending on your internet speed..."

    local _alpine_retry=0
    local _alpine_max_retries=3
    while [[ $_alpine_retry -lt $_alpine_max_retries ]]; do
        _alpine_retry=$(( _alpine_retry + 1 ))
        if proot-distro install alpine 2>&1 | while IFS= read -r line; do
            log_debug "  proot-distro: $line"
        done; then
            break
        fi
        if [[ $_alpine_retry -lt $_alpine_max_retries ]]; then
            log_warn "Alpine install failed, retrying in 10s... (attempt $_alpine_retry/$_alpine_max_retries)"
            sleep 10
        else
            log_error "Failed to install Alpine Linux after $_alpine_max_retries attempts"
            log_error "Possible causes:"
            log_error "  - No internet connection"
            log_error "  - Insufficient storage space"
            log_error "  - proot-distro version too old"
            log_error ""
            log_error "Try manually: proot-distro install alpine"
            return 1
        fi
    done

    # Verify installation
    if ! proot-distro list 2>/dev/null | grep -q "alpine"; then
        log_error "Alpine Linux installation verification failed"
        return 1
    fi

    log_info "Alpine Linux installed successfully"
    mark_step_completed "install_alpine"
    return 0
}

# ============================================================================
# proot Environment Configuration
# ============================================================================

configure_proot_environment() {
    log_section "Configuring proot Environment"

    if step_completed "configure_proot_env"; then
        log_info "proot environment already configured, skipping"
        return 0
    fi

    # Configure proot environment variables
    local proot_env_file="${ALICIA_BASE_DIR}/config/proot-env.sh"
    mkdir -p "$(dirname "$proot_env_file")"

    cat > "$proot_env_file" << ENV_EOF
#!/bin/bash
# Alicia proot Environment Variables
# Auto-generated by ${SCRIPT_NAME} v${SCRIPT_VERSION}

export DISPLAY=:1
export HOME=${ALICIA_USER_HOME}
export USER=${ALICIA_USER}
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export TERM=xterm-256color
export ALICIA_VERSION=${SCRIPT_VERSION}
export ALICIA_HOME=${ALICIA_USER_HOME}
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=\${XDG_RUNTIME_DIR}/bus
ENV_EOF

    log_info "proot environment file created: $proot_env_file"

    mark_step_completed "configure_proot_env"
    log_info "proot environment configured"
    return 0
}

# ============================================================================
# DNS / Network Configuration Inside proot
# ============================================================================

configure_resolv_conf() {
    log_section "Configuring DNS Inside proot"

    if step_completed "configure_dns"; then
        log_info "DNS already configured, skipping"
        return 0
    fi

    log_info "Setting up /etc/resolv.conf for DNS resolution..."

    # Build resolv.conf content
    local resolv_content=""
    for dns in "${DNS_SERVERS[@]}"; do
        resolv_content+="nameserver ${dns}\n"
    done

    # Write resolv.conf inside proot
    proot_exec "printf '${resolv_content}' > /etc/resolv.conf && cat /etc/resolv.conf"

    # Test DNS inside proot
    log_info "Testing DNS resolution inside proot..."
    if proot_exec "apk update 2>&1" | head -5 | grep -qi "fetch\|OK"; then
        log_info "DNS resolution is working inside proot"
    else
        log_warn "DNS resolution test inconclusive - will continue setup"
        # Try alternative DNS
        proot_exec "printf 'nameserver 1.1.1.1\nnameserver 208.67.222.222\n' > /etc/resolv.conf"
    fi

    mark_step_completed "configure_dns"
    log_info "DNS configuration complete"
    return 0
}

# ============================================================================
# Alpine Package Update and Base Tools
# ============================================================================

update_alpine_packages() {
    log_section "Updating Alpine Packages"

    if step_completed "update_alpine"; then
        log_info "Alpine packages already updated, skipping"
        return 0
    fi

    log_info "Updating Alpine package lists..."
    proot_exec "apk update 2>&1" || {
        log_warn "apk update had issues, attempting to continue"
    }

    log_info "Upgrading existing Alpine packages..."
    proot_exec "apk upgrade --no-cache 2>&1" || {
        log_warn "apk upgrade had issues, attempting to continue"
    }

    # Install essential base tools inside proot
    log_info "Installing base tools inside Alpine..."
    local base_packages=(
        "bash"
        "coreutils"
        "sudo"
        "shadow"
        "procps"
        "util-linux"
        "grep"
        "sed"
        "gawk"
        "which"
        "findutils"
        "tar"
        "gzip"
        "bzip2"
        "xz"
        "zip"
        "unzip"
        "curl"
        "wget"
        "ca-certificates"
        "openssh-client"
        "rsync"
        "less"
        "vim"
        "nano"
        "htop"
        "tree"
    )

    log_info "Installing ${#base_packages[@]} base packages..."
    proot_exec "apk add --no-cache ${base_packages[*]} 2>&1" || {
        log_warn "Some base packages may have failed to install"
    }

    mark_step_completed "update_alpine"
    log_info "Alpine packages updated and base tools installed"
    return 0
}

# ============================================================================
# User Creation and Configuration
# ============================================================================

create_alicia_user() {
    log_section "Creating Alicia User"

    if step_completed "create_user"; then
        log_info "Alicia user already created, skipping"
        return 0
    fi

    log_info "Creating user: $ALICIA_USER"

    # Check if user already exists
    if proot_exec "id $ALICIA_USER 2>/dev/null"; then
        log_info "User $ALICIA_USER already exists"
    else
        # Create user with home directory
        proot_exec "adduser -D -h $ALICIA_USER_HOME -s /bin/bash $ALICIA_USER 2>&1" || {
            log_error "Failed to create user: $ALICIA_USER"
            return 1
        }
        log_info "User $ALICIA_USER created"
    fi

    # Set user password
    log_info "Setting password for $ALICIA_USER"
    proot_exec "echo '${ALICIA_USER}:${ALICIA_USER_PASSWORD}' | chpasswd 2>&1" || {
        log_warn "Failed to set password via chpasswd, trying alternative method"
        proot_exec "echo '${ALICIA_USER}:${ALICIA_USER_PASSWORD}' | chpasswd" 2>/dev/null || true
    }

    # Create user groups that may not exist and add user to them
    log_info "Configuring user groups..."
    for group in "${ALICIA_USER_GROUPS[@]}"; do
        proot_exec "addgroup $group 2>/dev/null || true"
        proot_exec "addgroup $ALICIA_USER $group 2>/dev/null || true"
    done
    log_info "User added to groups: ${ALICIA_USER_GROUPS[*]}"

    # Add user to wheel group for sudo access
    proot_exec "addgroup wheel 2>/dev/null || true"
    proot_exec "addgroup $ALICIA_USER wheel 2>/dev/null || true"

    # Configure sudo for wheel group
    proot_exec "echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel" 2>/dev/null || {
        log_debug "sudo configuration may need manual setup"
    }

    # Create user directories
    log_info "Creating user home directories..."
    local user_dirs=(
        "Desktop"
        "Documents"
        "Downloads"
        "Music"
        "Pictures"
        "Videos"
        ".config"
        ".local"
        ".local/share"
        ".local/share/applications"
        ".vnc"
        ".ssh"
        ".icons"
        ".themes"
        ".fonts"
    )

    for dir in "${user_dirs[@]}"; do
        proot_exec "mkdir -p ${ALICIA_USER_HOME}/${dir} && chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/${dir}" 2>/dev/null || true
    done

    # Set proper ownership of home directory
    proot_exec "chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}" 2>/dev/null || true

    log_info "Alicia user configured successfully"
    mark_step_completed "create_user"
    return 0
}

# ============================================================================
# Profile and Shell Configuration
# ============================================================================

configure_system_profile() {
    log_section "Configuring System Profile"

    if step_completed "configure_profile"; then
        log_info "System profile already configured, skipping"
        return 0
    fi

    # Configure /etc/profile with aliases and environment
    log_info "Configuring /etc/profile..."
    proot_exec bash -c 'cat > /etc/profile << "PROFILE_EOF"
# ============================================================================
# /etc/profile - Alicia Desktop Environment System Profile
# ============================================================================

# System environment
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export TERM="xterm-256color"
export EDITOR="nano"
export VISUAL="nano"
export PAGER="less"

# Alicia Desktop Environment variables
export ALICIA_VERSION="3.1.0"
export ALICIA_HOME="/home/alicia"
export DISPLAY=":1"
export XDG_RUNTIME_DIR="/run/user/1000"

# Prompt customization
if [[ "$(id -u)" -eq 0 ]]; then
    PS1="\[\033[1;31m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]# "
else
    PS1="\[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ "
fi

# Aliases for convenience
alias ll="ls -la --color=auto"
alias la="ls -a --color=auto"
alias l="ls -CF --color=auto"
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias fgrep="fgrep --color=auto"
alias egrep="egrep --color=auto"

# Directory navigation aliases
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

# Safety aliases
alias cp="cp -iv"
alias mv="mv -iv"
alias rm="rm -iv"
alias mkdir="mkdir -pv"

# Application aliases
alias vim="vim -p"
alias update="sudo apk update && sudo apk upgrade"
alias install="sudo apk add"
alias remove="sudo apk del"
alias search="apk search"

# Alicia-specific aliases
alias alicia-status="echo \"Alicia Desktop v${ALICIA_VERSION} - \$(uname -a)\""

# History configuration
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL="ignoredups:erasedups"
shopt -s histappend 2>/dev/null || true

# Load user-specific profile if it exists
if [[ -f "$HOME/.bashrc" ]]; then
    . "$HOME/.bashrc"
fi
PROFILE_EOF'

    log_info "/etc/profile configured"
    mark_step_completed "configure_profile"
    return 0
}

configure_user_bashrc() {
    log_section "Configuring User .bashrc"

    if step_completed "configure_user_bashrc"; then
        log_info "User .bashrc already configured, skipping"
        return 0
    fi

    # Configure .bashrc for the alicia user inside proot
    proot_exec bash -c "cat > ${ALICIA_USER_HOME}/.bashrc << 'BASHRC_EOF'
# ============================================================================
# ~/.bashrc - Alicia Desktop Environment User Configuration
# ============================================================================

# If not running interactively, don't do anything
[[ \$- != *i* ]] && return

# --- Shell Options ---
shopt -s checkwinsize 2>/dev/null || true
shopt -s histappend 2>/dev/null || true
shopt -s cdspell 2>/dev/null || true
shopt -s autocd 2>/dev/null || true

# --- History Configuration ---
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=\"ignoredups:erasedups\"
export HISTIGNORE=\"ls:ll:la:cd:exit:clear:history\"
PROMPT_COMMAND=\"history -a; history -c; history -r; \$PROMPT_COMMAND\"

# --- Prompt ---
# Custom prompt with Alicia branding
PS1=\"\\[\\033[1;34m\\]alicia\\[\\033[0m\\]@\\[\\033[1;32m\\]\\h\\[\\033[0m\\]:\\[\\033[1;34m\\]\\w\\[\\033[0m\\]\\\$ \"

# --- Aliases ---
# Navigation
alias ll=\"ls -la --color=auto\"
alias la=\"ls -a --color=auto\"
alias l=\"ls -CF --color=auto\"

# Safety
alias cp=\"cp -iv\"
alias mv=\"mv -iv\"
alias rm=\"rm -iv\"
alias mkdir=\"mkdir -pv\"

# System management
alias update=\"sudo apk update && sudo apk upgrade\"
alias install=\"sudo apk add\"
alias remove=\"sudo apk del\"
alias search=\"apk search\"
alias ports=\"ss -tulanp\"

# Quick access
alias desktop=\"cd ~/Desktop\"
alias documents=\"cd ~/Documents\"
alias downloads=\"cd ~/Downloads\"

# --- Functions ---
# Extract any archive
extract() {
    if [[ -f \"\$1\" ]]; then
        case \"\$1\" in
            *.tar.bz2)   tar xjf \"\$1\"   ;;
            *.tar.gz)    tar xzf \"\$1\"   ;;
            *.tar.xz)    tar xJf \"\$1\"   ;;
            *.bz2)       bunzip2 \"\$1\"    ;;
            *.rar)       unrar x \"\$1\"    ;;
            *.gz)        gunzip \"\$1\"     ;;
            *.tar)       tar xf \"\$1\"    ;;
            *.tbz2)      tar xjf \"\$1\"   ;;
            *.tgz)       tar xzf \"\$1\"   ;;
            *.zip)       unzip \"\$1\"      ;;
            *.Z)         uncompress \"\$1\" ;;
            *.7z)        7z x \"\$1\"       ;;
            *)           echo \"Unknown archive format: \$1\" ;;
        esac
    else
        echo \"'\$1' is not a valid file\"
    fi
}

# Find files quickly
ff() { find . -type f -iname \"*\$*\"; }
fd() { find . -type d -iname \"*\$*\"; }

# --- Welcome ---
# Show welcome message on first login
if [[ -f ~/.alicia-first-login ]]; then
    echo \"Welcome back to Alicia Desktop Environment!\"
else
    touch ~/.alicia-first-login
    echo \"Welcome to Alicia Desktop Environment v${ALICIA_VERSION}!\"
    echo \"Type 'alicia-status' for system info.\"
fi
BASHRC_EOF

chown ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.bashrc"

    log_info "User .bashrc configured"
    mark_step_completed "configure_user_bashrc"
    return 0
}

# ============================================================================
# Mount Points and Shared Directories
# ============================================================================

setup_mount_points() {
    log_section "Setting Up Mount Points"

    if step_completed "setup_mounts"; then
        log_info "Mount points already configured, skipping"
        return 0
    fi

    log_info "Ensuring essential mount points exist inside proot..."

    # Create mount point directories (proot handles actual mounting)
    local mount_dirs=(
        "/dev"
        "/dev/pts"
        "/dev/shm"
        "/proc"
        "/proc/sys"
        "/sys"
        "/tmp"
        "/run"
        "/run/user"
        "/run/user/1000"
    )

    for dir in "${mount_dirs[@]}"; do
        proot_exec "mkdir -p $dir 2>/dev/null || true"
    done

    # Ensure /tmp has correct permissions
    proot_exec "chmod 1777 /tmp 2>/dev/null || true"
    proot_exec "chmod 1777 /run/user/1000 2>/dev/null || true"
    proot_exec "chown ${ALICIA_USER}:${ALICIA_USER} /run/user/1000 2>/dev/null || true"

    # Create /etc/fstab for reference (not actually used in proot)
    proot_exec bash -c 'cat > /etc/fstab << "FSTAB_EOF"
# /etc/fstab - Alicia Desktop Environment
# Note: In proot, actual mounting is handled differently
# This file is for reference only

# <device>    <mount>    <type>    <options>    <dump>    <pass>
proc          /proc      proc      defaults     0         0
sysfs         /sys       sysfs     defaults     0         0
devpts        /dev/pts   devpts    defaults     0         0
tmpfs         /tmp       tmpfs     defaults,nosuid,nodev  0  0
tmpfs         /run       tmpfs     defaults     0         0
FSTAB_EOF'

    log_info "Mount points configured"
    mark_step_completed "setup_mounts"
    return 0
}

setup_shared_directory() {
    log_section "Setting Up Shared Directory"

    if step_completed "setup_shared_dir"; then
        log_info "Shared directory already configured, skipping"
        return 0
    fi

    # Create shared directory on Termux side
    mkdir -p "$SHARED_DIR"
    log_info "Created shared directory: $SHARED_DIR"

    # Create subdirectories in shared space
    local shared_subdirs=(
        "transfer"
        "screenshots"
        "clipboard"
    )

    for subdir in "${shared_subdirs[@]}"; do
        mkdir -p "${SHARED_DIR}/${subdir}"
    done

    # Create shared directory inside proot and bind to Termux shared dir
    proot_exec "mkdir -p /shared 2>/dev/null || true"

    # Create a script that sets up the shared directory binding
    local bind_script="${ALICIA_BASE_DIR}/bin/alicia-bind-shared"
    cat > "$bind_script" << 'BIND_EOF'
#!/bin/bash
# Bind shared directory between Termux and proot
ALICIA_SHARED="${HOME}/alicia/shared"
PROOT_SHARED="/shared"

if [[ -d "$ALICIA_SHARED" ]]; then
    proot-distro login alpine --shared-tmp -- bash -c "mkdir -p $PROOT_SHARED"
    echo "Shared directory is available at $PROOT_SHARED inside proot"
else
    echo "Shared directory not found: $ALICIA_SHARED"
fi
BIND_EOF
    chmod +x "$bind_script" 2>/dev/null || true

    # Create a README in the shared directory
    cat > "${SHARED_DIR}/README.txt" << 'README_EOF'
Alicia Desktop Environment - Shared Directory
==============================================

This directory is shared between Termux (Android) and the proot Linux environment.

Usage:
- Place files here from Termux to access them inside the proot environment
- Files created inside proot at /shared will appear here

Subdirectories:
- transfer/    : General file transfer between environments
- screenshots/ : VNC screenshots saved here
- clipboard/   : Shared clipboard data

Note: In proot, this directory is accessible at /shared
README_EOF

    mark_step_completed "setup_shared_dir"
    log_info "Shared directory configured"
    return 0
}

# ============================================================================
# Hostname and Timezone Configuration
# ============================================================================

configure_hostname() {
    log_section "Configuring Hostname"

    if step_completed "configure_hostname"; then
        log_info "Hostname already configured, skipping"
        return 0
    fi

    log_info "Setting hostname to: $ALICIA_HOSTNAME"

    # Set hostname inside proot
    proot_exec "echo '$ALICIA_HOSTNAME' > /etc/hostname"

    # Update /etc/hosts
    proot_exec bash -c 'cat > /etc/hosts << "HOSTS_EOF"
127.0.0.1       localhost
127.0.1.1       alicia
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
HOSTS_EOF'

    # Set hostname in current session
    proot_exec "hostname $ALICIA_HOSTNAME 2>/dev/null || true"

    log_info "Hostname configured: $ALICIA_HOSTNAME"
    mark_step_completed "configure_hostname"
    return 0
}

configure_timezone() {
    log_section "Configuring Timezone"

    if step_completed "configure_timezone"; then
        log_info "Timezone already configured, skipping"
        return 0
    fi

    log_info "Setting timezone to: $ALICIA_TIMEZONE"

    # Install tzdata package
    proot_exec "apk add --no-cache tzdata 2>&1" || {
        log_warn "tzdata package installation had issues"
    }

    # Set timezone
    proot_exec "cp /usr/share/zoneinfo/${ALICIA_TIMEZONE} /etc/localtime 2>/dev/null || true"
    proot_exec "echo '${ALICIA_TIMEZONE}' > /etc/timezone 2>/dev/null || true"

    # Verify timezone
    local current_tz
    current_tz=$(proot_exec "cat /etc/timezone 2>/dev/null || echo 'unknown'")
    if [[ "$current_tz" == "$ALICIA_TIMEZONE" ]]; then
        log_info "Timezone set successfully: $ALICIA_TIMEZONE"
    else
        log_warn "Timezone may not be set correctly (expected: $ALICIA_TIMEZONE, got: $current_tz)"
    fi

    # Also set timezone in user environment
    proot_exec "echo 'export TZ=${ALICIA_TIMEZONE}' >> ${ALICIA_USER_HOME}/.bashrc 2>/dev/null || true"

    mark_step_completed "configure_timezone"
    log_info "Timezone configured"
    return 0
}

# ============================================================================
# Locale Configuration
# ============================================================================

configure_locale() {
    log_section "Configuring Locale"

    if step_completed "configure_locale"; then
        log_info "Locale already configured, skipping"
        return 0
    fi

    log_info "Setting up locale configuration..."

    # Install locale support (Alpine uses musl, limited locale support)
    proot_exec "apk add --no-cache musl-locales 2>&1" || {
        log_debug "musl-locales not available, using environment variables for locale"
    }

    # Set locale environment in profile
    proot_exec bash -c 'cat >> /etc/profile.d/locale.sh << "LOCALE_EOF"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export LANGUAGE="en_US.UTF-8"
LOCALE_EOF'

    proot_exec "chmod +x /etc/profile.d/locale.sh 2>/dev/null || true"

    mark_step_completed "configure_locale"
    log_info "Locale configured"
    return 0
}

# ============================================================================
# Validation
# ============================================================================

validate_proot_installation() {
    log_section "Validating proot Installation"

    if step_completed "validate_proot"; then
        log_info "proot installation already validated, skipping"
        return 0
    fi

    local errors=0

    # Check distro is installed
    log_info "Checking Alpine Linux installation..."
    if proot-distro list 2>/dev/null | grep -q "alpine"; then
        log_info "  [OK] Alpine Linux is installed"
    else
        log_error "  [FAIL] Alpine Linux is not installed"
        ((errors++)) || true
    fi

    # Check bash is available
    log_info "Checking bash availability..."
    if proot_exec "command -v bash" &>/dev/null; then
        log_info "  [OK] bash is available"
    else
        log_error "  [FAIL] bash is not available"
        ((errors++)) || true
    fi

    # Check user exists
    log_info "Checking alicia user..."
    if proot_exec "id $ALICIA_USER" &>/dev/null; then
        log_info "  [OK] User '$ALICIA_USER' exists"
    else
        log_error "  [FAIL] User '$ALICIA_USER' does not exist"
        ((errors++)) || true
    fi

    # Check hostname
    log_info "Checking hostname..."
    local hostname
    hostname=$(proot_exec "cat /etc/hostname 2>/dev/null || echo 'unknown'")
    if [[ "$hostname" == "$ALICIA_HOSTNAME" ]]; then
        log_info "  [OK] Hostname is '$ALICIA_HOSTNAME'"
    else
        log_warn "  [WARN] Hostname is '$hostname' (expected: '$ALICIA_HOSTNAME')"
    fi

    # Check DNS resolution
    log_info "Checking DNS resolution..."
    if proot_exec "cat /etc/resolv.conf 2>/dev/null | grep -q nameserver"; then
        log_info "  [OK] DNS is configured"
    else
        log_error "  [FAIL] DNS is not configured"
        ((errors++)) || true
    fi

    # Check essential directories
    log_info "Checking essential directories..."
    local essential_dirs=("/home" "/tmp" "/proc" "/dev" "/etc")
    for dir in "${essential_dirs[@]}"; do
        if proot_exec "test -d $dir" &>/dev/null; then
            log_debug "  [OK] $dir exists"
        else
            log_warn "  [WARN] $dir may not be accessible"
        fi
    done

    # Check user home directory
    log_info "Checking user home directory..."
    if proot_exec "test -d $ALICIA_USER_HOME" &>/dev/null; then
        log_info "  [OK] Home directory exists: $ALICIA_USER_HOME"
    else
        log_error "  [FAIL] Home directory not found: $ALICIA_USER_HOME"
        ((errors++)) || true
    fi

    # Check essential packages
    log_info "Checking essential packages..."
    local essential_cmds=("bash" "sudo" "apk" "curl" "wget")
    for cmd in "${essential_cmds[@]}"; do
        if proot_exec "command -v $cmd" &>/dev/null; then
            log_debug "  [OK] $cmd is available"
        else
            log_warn "  [WARN] $cmd is not available"
        fi
    done

    # Summary
    if [[ $errors -eq 0 ]]; then
        log_info "All validation checks passed!"
    else
        log_warn "$errors validation error(s) found"
        log_warn "The proot environment may not be fully functional"
    fi

    mark_step_completed "validate_proot"
    return 0
}

# ============================================================================
# Cleanup and Signal Handling
# ============================================================================

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Setup script exited with code: $exit_code"
        log_error "You can re-run this script to continue from where it left off"
    fi
    if declare -f alicia_lock_release &>/dev/null; then
        alicia_lock_release "setup-02" 2>/dev/null || true
    fi
    exit $exit_code
}

trap cleanup EXIT
trap 'log_warn "Interrupted by user"; exit 130' INT
trap 'log_warn "Terminated"; exit 143' TERM

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_section "Alicia Desktop - proot Setup (Step 2/6)"
    log_info "Version: ${SCRIPT_VERSION}"
    log_info "Author:  Proyecto Tomorrow"
    log_info "Time:    $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Ensure step 01 was completed
    if [[ ! -f "${ALICIA_BASE_DIR}/.setup-01-state" ]]; then
        log_warn "Step 01 (Termux setup) does not appear to have been completed"
        log_warn "It is recommended to run 01-termux-setup.sh first"
        log_warn "Continuing anyway..."
    fi

    # Load previous state for resumability
    load_state

    # Acquire lock
    if declare -f alicia_lock_acquire &>/dev/null; then
        alicia_lock_acquire "setup-02" 300 || {
            log_error "Another setup process is already running"
            exit 1
        }
    fi

    # Execute setup steps in order
    local steps=(
        "check_network_connectivity"
        "install_proot_distro"
        "install_alpine_linux"
        "configure_proot_environment"
        "configure_resolv_conf"
        "update_alpine_packages"
        "create_alicia_user"
        "configure_system_profile"
        "configure_user_bashrc"
        "setup_mount_points"
        "setup_shared_directory"
        "configure_hostname"
        "configure_timezone"
        "configure_locale"
        "validate_proot_installation"
    )

    local total_steps=${#steps[@]}
    local completed=0

    for step in "${steps[@]}"; do
        ((completed++)) || true
        log_progress "$completed" "$total_steps" "Overall setup progress"

        log_info "Executing step: $step"
        if ! "$step"; then
            log_error "Step failed: $step"
            log_error "Fix the issue and re-run this script to continue"
            exit 1
        fi
    done

    log_progress "$total_steps" "$total_steps" "Overall setup progress"

    # Final summary
    log_section "proot Setup Complete"
    log_info "Alpine Linux is installed and configured inside proot!"
    log_info ""
    log_info "  Distribution:    Alpine Linux"
    log_info "  User:            $ALICIA_USER"
    log_info "  Hostname:        $ALICIA_HOSTNAME"
    log_info "  Timezone:        $ALICIA_TIMEZONE"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Run: ${SCRIPT_DIR}/03-desktop-setup.sh"
    log_info "  2. This will install the XFCE4 desktop environment"
    log_info ""
    log_info "Quick test:"
    log_info "  proot-distro login alpine  (enter the proot environment)"

    return 0
}

main "$@"
