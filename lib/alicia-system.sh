#!/bin/bash
# ============================================================================
# alicia-system.sh - Alicia Desktop Environment System Management Library
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
# Description:  System management library providing proot management, rootfs
#               operations, package management, VNC/display management, service
#               management, user management, and system information gathering.
# ============================================================================

# set -euo pipefail removed for library sourcing safety

if [[ -n "${_ALICIA_SYSTEM_LOADED:-}" ]]; then
    return 0
fi
_ALICIA_SYSTEM_LOADED=1

# Source dependencies (safe - won't fail if already loaded)
_ALICIA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ALICIA_LIB_DIR}/alicia-core.sh" 2>/dev/null || true
source "${_ALICIA_LIB_DIR}/alicia-log.sh" 2>/dev/null || true

# ============================================================================
# Default Paths and Constants
# ============================================================================
: "${ALICIA_PROOT_DIR:="${ALICIA_HOME:-$HOME/alicia}/proot"}"
: "${ALICIA_ROOTFS_DIR:="${ALICIA_HOME:-$HOME/alicia}/rootfs"}"
: "${ALICIA_DISTRO_NAME:="alpine"}"
: "${ALICIA_DISTRO_VERSION:="3.19"}"
: "${ALICIA_VNC_PORT:=5901}"
: "${ALICIA_VNC_RESOLUTION:="1280x720"}"
: "${ALICIA_VNC_DEPTH:=24}"
: "${ALICIA_VNC_PASSWORD:="alicia"}"
: "${ALICIA_DISPLAY:=:1}"
: "${ALICIA_DESKTOP_ENV:="xfce4"}"
: "${ALICIA_PROOT_CMD:="proot-distro"}"

# ============================================================================
# proot Management
# ============================================================================

# proot_is_installed - Check if proot-distro is installed
proot_is_installed() {
    command -v proot-distro &>/dev/null || command -v proot &>/dev/null
}

# proot_install - Install proot-distro in Termux
proot_install() {
    log_info "Installing proot-distro..."
    if command -v pkg &>/dev/null; then
        pkg install proot-distro -y 2>&1 | while IFS= read -r line; do
            log_debug "  pkg: $line"
        done
    elif command -v apt &>/dev/null; then
        apt install proot-distro -y 2>&1 | while IFS= read -r line; do
            log_debug "  apt: $line"
        done
    else
        log_error "No package manager found for proot installation"
        return 1
    fi

    if proot_is_installed; then
        log_info "proot-distro installed successfully"
        return 0
    else
        log_error "Failed to install proot-distro"
        return 1
    fi
}

# proot_is_distro_installed - Check if a distro is installed
proot_is_distro_installed() {
    local distro="${1:-$ALICIA_DISTRO_NAME}"
    proot-distro list 2>/dev/null | grep -q "$distro" && return 0 || return 1
}

# proot_distro_install - Install a Linux distribution via proot-distro
proot_distro_install() {
    local distro="${1:-$ALICIA_DISTRO_NAME}"
    log_section "Installing $distro via proot-distro"

    if proot_is_distro_installed "$distro"; then
        log_info "Distribution '$distro' is already installed"
        return 0
    fi

    log_info "Installing distribution: $distro"
    if proot-distro install "$distro" 2>&1 | while IFS= read -r line; do
        log_debug "  proot: $line"
    done; then
        log_info "Distribution '$distro' installed successfully"
        alicia_set_state "DISTRO_${distro^^}_INSTALLED" "true"
        return 0
    else
        log_error "Failed to install distribution: $distro"
        return 1
    fi
}

# proot_start - Start proot session with the configured distro
proot_start() {
    local distro="${1:-$ALICIA_DISTRO_NAME}"
    log_info "Starting proot session for: $distro"

    if ! proot_is_distro_installed "$distro"; then
        log_error "Distribution '$distro' is not installed"
        return 1
    fi

    # Set environment variables for proot
    local proot_env=(
        "DISPLAY=${ALICIA_DISPLAY}"
        "HOME=/home/alicia"
        "USER=alicia"
        "LANG=en_US.UTF-8"
        "LC_ALL=en_US.UTF-8"
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        "TERM=xterm-256color"
        "ALICIA_VERSION=${ALICIA_VERSION:-3.1.0}"
        "ALICIA_HOME=/home/alicia"
    )

    local env_args=""
    for env_var in "${proot_env[@]}"; do
        env_args+=" --env $env_var"
    done

    # Start proot in background for service-like behavior
    proot-distro login "$distro" $env_args -- bash -c "
        source /etc/profile 2>/dev/null || true
        source /home/alicia/.bashrc 2>/dev/null || true
        exec \"\$@\"
    " -- "$@" &

    local pid=$!
    alicia_set_state "PROOT_PID" "$pid"
    log_info "proot session started with PID: $pid"
    return 0
}

# proot_exec - Execute a command inside the proot environment
proot_exec() {
    local distro="${1:-$ALICIA_DISTRO_NAME}"
    shift
    local cmd="$*"

    if [[ -z "$cmd" ]]; then
        log_error "No command specified for proot_exec"
        return 1
    fi

    log_debug "Executing in proot: $cmd"

    local proot_env=(
        "DISPLAY=${ALICIA_DISPLAY}"
        "HOME=/home/alicia"
        "USER=alicia"
        "LANG=en_US.UTF-8"
        "LC_ALL=en_US.UTF-8"
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        "TERM=xterm-256color"
    )

    local env_args=""
    for env_var in "${proot_env[@]}"; do
        env_args+=" --env $env_var"
    done

    proot-distro login "$distro" $env_args -- bash -c "$cmd" 2>&1
}

# proot_stop - Stop the proot session
proot_stop() {
    local pid
    pid=$(alicia_get_state "PROOT_PID" "0")
    if [[ "$pid" != "0" ]] && kill -0 "$pid" 2>/dev/null; then
        log_info "Stopping proot session (PID: $pid)"
        kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        kill -9 "$pid" 2>/dev/null || true
        alicia_set_state "PROOT_PID" "0"
        log_info "proot session stopped"
    else
        log_debug "No active proot session to stop"
    fi
}

# proot_is_running - Check if proot session is running
proot_is_running() {
    local pid
    pid=$(alicia_get_state "PROOT_PID" "0")
    [[ "$pid" != "0" ]] && kill -0 "$pid" 2>/dev/null
}

# ============================================================================
# Package Management Inside proot
# ============================================================================

# pkg_install - Install packages inside proot
pkg_install() {
    local packages=("$@")
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_error "No packages specified for installation"
        return 1
    fi

    local pkg_list="${packages[*]}"
    log_info "Installing packages: $pkg_list"

    proot_exec "$ALICIA_DISTRO_NAME" "apk add --no-cache ${packages[*]} 2>&1" || \
    proot_exec "$ALICIA_DISTRO_NAME" "apt-get install -y ${packages[*]} 2>&1" || \
    proot_exec "$ALICIA_DISTRO_NAME" "dnf install -y ${packages[*]} 2>&1" || {
        log_error "Failed to install packages: $pkg_list"
        return 1
    }

    log_info "Packages installed successfully: $pkg_list"
    return 0
}

# pkg_remove - Remove packages inside proot
pkg_remove() {
    local packages=("$@")
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_error "No packages specified for removal"
        return 1
    fi

    log_info "Removing packages: ${packages[*]}"
    proot_exec "$ALICIA_DISTRO_NAME" "apk del ${packages[*]} 2>&1" || \
    proot_exec "$ALICIA_DISTRO_NAME" "apt-get remove -y ${packages[*]} 2>&1" || {
        log_error "Failed to remove packages"
        return 1
    }

    log_info "Packages removed successfully"
    return 0
}

# pkg_update - Update package lists inside proot
pkg_update() {
    log_info "Updating package lists..."
    proot_exec "$ALICIA_DISTRO_NAME" "apk update 2>&1" || \
    proot_exec "$ALICIA_DISTRO_NAME" "apt-get update 2>&1" || {
        log_error "Failed to update package lists"
        return 1
    }
    log_info "Package lists updated"
    return 0
}

# pkg_upgrade - Upgrade all installed packages
pkg_upgrade() {
    log_info "Upgrading all packages..."
    proot_exec "$ALICIA_DISTRO_NAME" "apk upgrade --no-cache 2>&1" || \
    proot_exec "$ALICIA_DISTRO_NAME" "apt-get upgrade -y 2>&1" || {
        log_error "Failed to upgrade packages"
        return 1
    }
    log_info "All packages upgraded"
    return 0
}

# pkg_search - Search for packages
pkg_search() {
    local pattern="$1"
    if [[ -z "$pattern" ]]; then
        log_error "No search pattern specified"
        return 1
    fi
    log_info "Searching for packages: $pattern"
    proot_exec "$ALICIA_DISTRO_NAME" "apk search $pattern 2>&1" || \
    proot_exec "$ALICIA_DISTRO_NAME" "apt-cache search $pattern 2>&1"
}

# pkg_list_installed - List installed packages
pkg_list_installed() {
    proot_exec "$ALICIA_DISTRO_NAME" "apk info 2>&1" || \
    proot_exec "$ALICIA_DISTRO_NAME" "dpkg -l 2>&1"
}

# ============================================================================
# VNC Server Management
# ============================================================================

# vnc_start - Start VNC server
vnc_start() {
    local port="${1:-$ALICIA_VNC_PORT}"
    local resolution="${2:-$ALICIA_VNC_RESOLUTION}"
    local depth="${3:-$ALICIA_VNC_DEPTH}"
    local password="${4:-$ALICIA_VNC_PASSWORD}"

    log_section "Starting VNC Server"
    log_info "Port: $port, Resolution: $resolution, Depth: $depth"

    if vnc_is_running; then
        log_warn "VNC server is already running"
        return 0
    fi

    # Create VNC password file
    local vnc_password_file="/home/alicia/.vnc/passwd"
    proot_exec "$ALICIA_DISTRO_NAME" "mkdir -p /home/alicia/.vnc && echo '$password' | vncpasswd -f > $vnc_password_file && chmod 600 $vnc_password_file"

    # Create xstartup script
    _vnc_create_xstartup

    # Start VNC server inside proot
    proot_exec "$ALICIA_DISTRO_NAME" "vncserver ${ALICIA_DISPLAY} -geometry ${resolution} -depth ${depth} -localhost no 2>&1" || {
        log_error "Failed to start VNC server"
        return 1
    }

    alicia_set_state "VNC_RUNNING" "true"
    alicia_set_state "VNC_PORT" "$port"
    log_info "VNC server started on port $port"
    return 0
}

# vnc_stop - Stop VNC server
vnc_stop() {
    log_info "Stopping VNC server..."
    if ! vnc_is_running; then
        log_warn "VNC server is not running"
        return 0
    fi

    proot_exec "$ALICIA_DISTRO_NAME" "vncserver -kill ${ALICIA_DISPLAY} 2>&1" || {
        log_warn "Failed to stop VNC server gracefully, forcing..."
        proot_exec "$ALICIA_DISTRO_NAME" "pkill -9 Xvnc 2>/dev/null || pkill -9 Xvfb 2>/dev/null || true"
    }

    alicia_set_state "VNC_RUNNING" "false"
    log_info "VNC server stopped"
    return 0
}

# vnc_restart - Restart VNC server
vnc_restart() {
    log_info "Restarting VNC server..."
    vnc_stop
    sleep 2
    vnc_start
}

# vnc_is_running - Check if VNC server is running
vnc_is_running() {
    local result
    result=$(proot_exec "$ALICIA_DISTRO_NAME" "pgrep -x Xvnc >/dev/null 2>&1 && echo 'yes' || echo 'no'" 2>/dev/null)
    [[ "$result" == "yes" ]]
}

# vnc_change_password - Change VNC password
vnc_change_password() {
    local new_password="$1"
    if [[ -z "$new_password" ]]; then
        log_error "No password provided"
        return 1
    fi

    log_info "Changing VNC password..."
    local vnc_password_file="/home/alicia/.vnc/passwd"
    proot_exec "$ALICIA_DISTRO_NAME" "echo '$new_password' | vncpasswd -f > $vnc_password_file && chmod 600 $vnc_password_file"
    ALICIA_VNC_PASSWORD="$new_password"
    log_info "VNC password changed"
    return 0
}

# vnc_change_resolution - Change VNC resolution
vnc_change_resolution() {
    local new_resolution="${1:-1280x720}"
    log_info "Changing VNC resolution to: $new_resolution"
    ALICIA_VNC_RESOLUTION="$new_resolution"
    if vnc_is_running; then
        vnc_restart
    fi
    log_info "VNC resolution changed to $new_resolution"
    return 0
}

# _vnc_create_xstartup - Create the VNC xstartup script
_vnc_create_xstartup() {
    log_debug "Creating VNC xstartup script"
    proot_exec "$ALICIA_DISTRO_NAME" bash -c 'cat > /home/alicia/.vnc/xstartup << "XSTARTUP_EOF"
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
export XDG_CURRENT_DESKTOP="XFCE"
export XDG_SESSION_DESKTOP="xfce4"
export DISPLAY='"${ALICIA_DISPLAY}"'

# Start dbus
if command -v dbus-launch &>/dev/null; then
    eval \$(dbus-launch --sh-syntax)
fi

# Start pulseaudio if available
if command -v pulseaudio &>/dev/null; then
    pulseaudio --start --fail=false --daemonize=true 2>/dev/null || true
fi

# Start XFCE desktop
if command -v startxfce4 &>/dev/null; then
    exec startxfce4
elif command -v xfce4-session &>/dev/null; then
    exec xfce4-session
elif command -v fluxbox &>/dev/null; then
    exec fluxbox
else
    exec xterm
fi
XSTARTUP_EOF
chmod +x /home/alicia/.vnc/xstartup'
}

# ============================================================================
# Display Server Management (Xvfb)
# ============================================================================

# xvfb_start - Start Xvfb virtual framebuffer
xvfb_start() {
    local display="${1:-$ALICIA_DISPLAY}"
    local resolution="${2:-$ALICIA_VNC_RESOLUTION}"

    log_info "Starting Xvfb on display $display at $resolution"

    if xvfb_is_running; then
        log_warn "Xvfb is already running"
        return 0
    fi

    proot_exec "$ALICIA_DISTRO_NAME" "Xvfb $display -screen 0 ${resolution}x${ALICIA_VNC_DEPTH} -ac +extension GLX +render -noreset &" 2>/dev/null

    sleep 2
    if xvfb_is_running; then
        alicia_set_state "XVFB_RUNNING" "true"
        log_info "Xvfb started successfully"
        return 0
    else
        log_error "Failed to start Xvfb"
        return 1
    fi
}

# xvfb_stop - Stop Xvfb
xvfb_stop() {
    log_info "Stopping Xvfb..."
    proot_exec "$ALICIA_DISTRO_NAME" "pkill Xvfb 2>/dev/null || true"
    alicia_set_state "XVFB_RUNNING" "false"
    log_info "Xvfb stopped"
}

# xvfb_is_running - Check if Xvfb is running
xvfb_is_running() {
    local result
    result=$(proot_exec "$ALICIA_DISTRO_NAME" "pgrep -x Xvfb >/dev/null 2>&1 && echo 'yes' || echo 'no'" 2>/dev/null)
    [[ "$result" == "yes" ]]
}

# ============================================================================
# Desktop Environment Management
# ============================================================================

# de_start - Start the desktop environment
de_start() {
    local desktop_env="${1:-$ALICIA_DESKTOP_ENV}"
    log_info "Starting desktop environment: $desktop_env"

    case "$desktop_env" in
        xfce4|xfce)
            proot_exec "$ALICIA_DISTRO_NAME" "DISPLAY=${ALICIA_DISPLAY} startxfce4 &" 2>/dev/null
            ;;
        fluxbox)
            proot_exec "$ALICIA_DISTRO_NAME" "DISPLAY=${ALICIA_DISPLAY} fluxbox &" 2>/dev/null
            ;;
        lxde)
            proot_exec "$ALICIA_DISTRO_NAME" "DISPLAY=${ALICIA_DISPLAY} startlxde &" 2>/dev/null
            ;;
        *)
            log_error "Unknown desktop environment: $desktop_env"
            return 1
            ;;
    esac

    alicia_set_state "DE_RUNNING" "true"
    log_info "Desktop environment started: $desktop_env"
    return 0
}

# de_stop - Stop the desktop environment
de_stop() {
    log_info "Stopping desktop environment..."
    proot_exec "$ALICIA_DISTRO_NAME" "pkill -f xfce4-session 2>/dev/null; pkill -f fluxbox 2>/dev/null; pkill -f lxsession 2>/dev/null" || true
    alicia_set_state "DE_RUNNING" "false"
    log_info "Desktop environment stopped"
}

# de_is_running - Check if desktop environment is running
de_is_running() {
    local result
    result=$(proot_exec "$ALICIA_DISTRO_NAME" "pgrep -f 'xfce4-session\|fluxbox\|lxsession' >/dev/null 2>&1 && echo 'yes' || echo 'no'" 2>/dev/null)
    [[ "$result" == "yes" ]]
}

# ============================================================================
# Service Management
# ============================================================================

# service_start - Start a system service inside proot
service_start() {
    local service_name="$1"
    if [[ -z "$service_name" ]]; then
        log_error "No service name specified"
        return 1
    fi

    log_info "Starting service: $service_name"
    proot_exec "$ALICIA_DISTRO_NAME" "rc-service $service_name start 2>&1 || service $service_name start 2>&1" || {
        log_error "Failed to start service: $service_name"
        return 1
    }
    alicia_set_state "SERVICE_${service_name^^}" "running"
    log_info "Service started: $service_name"
    return 0
}

# service_stop - Stop a system service
service_stop() {
    local service_name="$1"
    if [[ -z "$service_name" ]]; then
        log_error "No service name specified"
        return 1
    fi

    log_info "Stopping service: $service_name"
    proot_exec "$ALICIA_DISTRO_NAME" "rc-service $service_name stop 2>&1 || service $service_name stop 2>&1" || {
        log_warn "Failed to stop service: $service_name"
        return 1
    }
    alicia_set_state "SERVICE_${service_name^^}" "stopped"
    log_info "Service stopped: $service_name"
    return 0
}

# service_restart - Restart a system service
service_restart() {
    local service_name="$1"
    log_info "Restarting service: $service_name"
    service_stop "$service_name" 2>/dev/null || true
    sleep 1
    service_start "$service_name"
}

# service_status - Get service status
service_status() {
    local service_name="$1"
    proot_exec "$ALICIA_DISTRO_NAME" "rc-service $service_name status 2>&1 || service $service_name status 2>&1"
}

# service_enable - Enable service at boot
service_enable() {
    local service_name="$1"
    log_info "Enabling service at boot: $service_name"
    proot_exec "$ALICIA_DISTRO_NAME" "rc-update add $service_name default 2>&1 || systemctl enable $service_name 2>&1" || {
        log_warn "Failed to enable service: $service_name"
        return 1
    }
    log_info "Service enabled: $service_name"
}

# service_disable - Disable service at boot
service_disable() {
    local service_name="$1"
    log_info "Disabling service at boot: $service_name"
    proot_exec "$ALICIA_DISTRO_NAME" "rc-update del $service_name default 2>&1 || systemctl disable $service_name 2>&1" || {
        log_warn "Failed to disable service: $service_name"
        return 1
    }
    log_info "Service disabled: $service_name"
}

# ============================================================================
# User Management Inside proot
# ============================================================================

# user_create - Create user inside proot
user_create() {
    local username="${1:-alicia}"
    local password="${2:-alicia}"
    local home_dir="${3:-/home/$username}"

    log_info "Creating user: $username"
    proot_exec "$ALICIA_DISTRO_NAME" "adduser -D -h $home_dir -s /bin/bash $username 2>&1" || \
    proot_exec "$ALICIA_DISTRO_NAME" "useradd -m -d $home_dir -s /bin/bash $username 2>&1" || {
        log_warn "User might already exist: $username"
    }

    proot_exec "$ALICIA_DISTRO_NAME" "echo '$username:$password' | chpasswd 2>&1" || true

    # Add to necessary groups
    proot_exec "$ALICIA_DISTRO_NAME" "addgroup $username audio 2>/dev/null; addgroup $username video 2>/dev/null; addgroup $username plugdev 2>/dev/null" 2>/dev/null || true

    # Create user directories
    proot_exec "$ALICIA_DISTRO_NAME" "su - $username -c 'mkdir -p Desktop Documents Downloads Music Pictures Videos .config .local .vnc' 2>/dev/null" || true

    log_info "User created: $username"
    return 0
}

# user_delete - Delete user inside proot
user_delete() {
    local username="$1"
    log_info "Deleting user: $username"
    proot_exec "$ALICIA_DISTRO_NAME" "deluser --remove-home $username 2>&1" || \
    proot_exec "$ALICIA_DISTRO_NAME" "userdel -r $username 2>&1" || {
        log_error "Failed to delete user: $username"
        return 1
    }
    log_info "User deleted: $username"
    return 0
}

# user_set_password - Set user password
user_set_password() {
    local username="${1:-alicia}"
    local password="${2:-alicia}"
    proot_exec "$ALICIA_DISTRO_NAME" "echo '$username:$password' | chpasswd 2>&1"
}

# ============================================================================
# System Information
# ============================================================================

# system_info - Gather comprehensive system information
system_info() {
    local info=""
    info+="Alicia Desktop Environment v${ALICIA_VERSION:-3.1.0}\n"
    info+="==========================================\n\n"

    # Android/Termux info
    info+="Host System:\n"
    info+="  OS: $(uname -o 2>/dev/null || echo "Unknown")\n"
    info+="  Kernel: $(uname -r)\n"
    info+="  Architecture: $(uname -m)\n"
    info+="  Termux: $([ -n "${TERMUX_VERSION:-}" ] && echo "Yes (${TERMUX_VERSION})" || echo "No")\n\n"

    # Memory info
    info+="Memory:\n"
    info+="  $(free -h 2>/dev/null | head -2 | tail -1 || echo "Information unavailable")\n\n"

    # Storage info
    info+="Storage:\n"
    info+="  $(df -h "$HOME" 2>/dev/null | tail -1 || echo "Information unavailable")\n\n"

    # proot info
    info+="proot Environment:\n"
    info+="  Distribution: $ALICIA_DISTRO_NAME\n"
    info+="  Installed: $(proot_is_distro_installed && echo 'Yes' || echo 'No')\n"
    info+="  Running: $(proot_is_running && echo 'Yes' || echo 'No')\n\n"

    # VNC info
    info+="VNC Server:\n"
    info+="  Running: $(vnc_is_running && echo 'Yes' || echo 'No')\n"
    info+="  Port: $ALICIA_VNC_PORT\n"
    info+="  Resolution: $ALICIA_VNC_RESOLUTION\n\n"

    # Desktop info
    info+="Desktop:\n"
    info+="  Environment: $ALICIA_DESKTOP_ENV\n"
    info+="  Running: $(de_is_running && echo 'Yes' || echo 'No')\n"

    echo -e "$info"
}

# system_uptime - Get system uptime
system_uptime() {
    uptime 2>/dev/null || echo "Unknown"
}

# cpu_get_info - Get CPU information
cpu_get_info() {
    proot_exec "$ALICIA_DISTRO_NAME" "cat /proc/cpuinfo 2>/dev/null | head -20" || \
    cat /proc/cpuinfo 2>/dev/null | head -20 || echo "CPU information unavailable"
}

# cpu_get_cores - Get number of CPU cores
cpu_get_cores() {
    nproc 2>/dev/null || echo 1
}

# memory_get_info - Get memory information
memory_get_info() {
    free -h 2>/dev/null || proot_exec "$ALICIA_DISTRO_NAME" "free -h 2>/dev/null" || echo "Memory information unavailable"
}

# memory_get_usage - Get memory usage percentage
memory_get_usage() {
    local mem_info
    mem_info=$(free 2>/dev/null | grep Mem)
    if [[ -n "$mem_info" ]]; then
        local total used
        total=$(echo "$mem_info" | awk '{print $2}')
        used=$(echo "$mem_info" | awk '{print $3}')
        if [[ $total -gt 0 ]]; then
            echo "$((used * 100 / total))%"
            return 0
        fi
    fi
    echo "0%"
}

# memory_optimize - Optimize memory usage
memory_optimize() {
    log_info "Optimizing memory usage..."
    # Clear caches inside proot
    proot_exec "$ALICIA_DISTRO_NAME" "sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true"
    # Clear Termux caches
    sync 2>/dev/null || true
    log_info "Memory optimization complete"
}

# storage_get_info - Get storage information
storage_get_info() {
    df -h "$HOME" 2>/dev/null || echo "Storage information unavailable"
}

# storage_get_usage - Get storage usage percentage
storage_get_usage() {
    local usage
    usage=$(df "$HOME" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    echo "${usage:-0}%"
}

# ============================================================================
# Network Management
# ============================================================================

# network_check - Check network connectivity
network_check() {
    local target="${1:-8.8.8.8}"
    local timeout="${2:-5}"

    if ping -c 1 -W "$timeout" "$target" &>/dev/null; then
        return 0
    else
        log_warn "Network check failed: cannot reach $target"
        return 1
    fi
}

# network_get_ip - Get local IP address
network_get_ip() {
    ip addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1 || \
    ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' || \
    echo "Unknown"
}

# network_test - Test network speed (basic)
network_test() {
    local url="${1:-https://speed.cloudflare.com/__down?bytes=10000000}"
    log_info "Testing network speed with: $url"
    local start_time end_time duration

    start_time=$(date +%s%N)
    curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || wget -q -O /dev/null "$url" 2>/dev/null || {
        log_error "Network speed test failed"
        return 1
    }
    end_time=$(date +%s%N)

    duration=$(( (end_time - start_time) / 1000000 ))
    log_info "Network test completed in ${duration}ms"
}

# ============================================================================
# Process Management Inside proot
# ============================================================================

# process_list - List processes inside proot
process_list() {
    proot_exec "$ALICIA_DISTRO_NAME" "ps aux 2>/dev/null || ps -ef 2>/dev/null" || echo "Cannot list processes"
}

# process_kill - Kill a process inside proot
process_kill() {
    local pid="$1"
    local signal="${2:-TERM}"
    if [[ -z "$pid" ]]; then
        log_error "No PID specified"
        return 1
    fi
    proot_exec "$ALICIA_DISTRO_NAME" "kill -$signal $pid 2>/dev/null"
}

# process_tree - Show process tree inside proot
process_tree() {
    proot_exec "$ALICIA_DISTRO_NAME" "pstree 2>/dev/null || ps auxf 2>/dev/null" || echo "Cannot show process tree"
}

# ============================================================================
# Environment Variable Management
# ============================================================================

# env_set_inside_proot - Set an environment variable inside proot
env_set_inside_proot() {
    local key="$1"
    local value="$2"
    if [[ -z "$key" ]]; then
        log_error "No environment variable key specified"
        return 1
    fi

    log_debug "Setting proot env: $key=$value"
    proot_exec "$ALICIA_DISTRO_NAME" "echo 'export $key=\"$value\"' >> /home/alicia/.bashrc"
}

# env_get_inside_proot - Get an environment variable inside proot
env_get_inside_proot() {
    local key="$1"
    proot_exec "$ALICIA_DISTRO_NAME" "source /home/alicia/.bashrc 2>/dev/null; echo \${$key:-}"
}

# ============================================================================
# RootFS Management
# ============================================================================

# rootfs_verify - Verify rootfs integrity
rootfs_verify() {
    local rootfs_dir="${1:-$ALICIA_ROOTFS_DIR}"
    log_info "Verifying rootfs at: $rootfs_dir"

    if [[ ! -d "$rootfs_dir" ]]; then
        log_error "Rootfs directory does not exist: $rootfs_dir"
        return 1
    fi

    # Check essential directories
    local essential_dirs=("bin" "etc" "lib" "proc" "sys" "usr" "var" "home" "tmp")
    local missing=()

    for dir in "${essential_dirs[@]}"; do
        if [[ ! -d "${rootfs_dir}/${dir}" ]]; then
            missing+=("$dir")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing essential directories: ${missing[*]}"
        return 1
    fi

    # Check essential binaries
    if [[ ! -f "${rootfs_dir}/bin/sh" ]] && [[ ! -L "${rootfs_dir}/bin/sh" ]]; then
        log_error "Essential binary missing: /bin/sh"
        return 1
    fi

    log_info "Rootfs verification passed"
    return 0
}

# rootfs_backup - Backup rootfs
rootfs_backup() {
    local backup_dir="${1:-${ALICIA_HOME:-$HOME/alicia}/backups}"
    local timestamp
    timestamp=$(date "+%Y%m%d_%H%M%S")

    log_section "Backing up rootfs"

    if [[ ! -d "$ALICIA_ROOTFS_DIR" ]]; then
        log_error "Rootfs directory not found: $ALICIA_ROOTFS_DIR"
        return 1
    fi

    mkdir -p "$backup_dir"
    local backup_file="${backup_dir}/alicia_rootfs_${timestamp}.tar.gz"

    log_info "Creating backup: $backup_file"
    tar -czf "$backup_file" -C "$(dirname "$ALICIA_ROOTFS_DIR")" "$(basename "$ALICIA_ROOTFS_DIR")" 2>&1 | while IFS= read -r line; do
        log_debug "  tar: $line"
    done

    if [[ -f "$backup_file" ]]; then
        local size
        size=$(du -h "$backup_file" | cut -f1)
        log_info "Backup created: $backup_file ($size)"
        return 0
    else
        log_error "Failed to create backup"
        return 1
    fi
}

# rootfs_restore - Restore rootfs from backup
rootfs_restore() {
    local backup_file="$1"
    if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_section "Restoring rootfs from backup"

    # Stop everything first
    vnc_stop 2>/dev/null || true
    de_stop 2>/dev/null || true
    proot_stop 2>/dev/null || true

    # Remove current rootfs
    if [[ -d "$ALICIA_ROOTFS_DIR" ]]; then
        log_info "Removing current rootfs..."
        rm -rf "$ALICIA_ROOTFS_DIR"
    fi

    # Extract backup
    log_info "Extracting backup: $backup_file"
    tar -xzf "$backup_file" -C "$(dirname "$ALICIA_ROOTFS_DIR")"

    if rootfs_verify; then
        log_info "Rootfs restored successfully"
        return 0
    else
        log_error "Rootfs verification failed after restore"
        return 1
    fi
}

# ============================================================================
# Full System Start/Stop
# ============================================================================

# alicia_full_start - Start the complete Alicia system
alicia_full_start() {
    log_section "Starting Alicia Desktop Environment"

    # Ensure proot is installed
    if ! proot_is_installed; then
        proot_install
    fi

    # Ensure distro is installed
    if ! proot_is_distro_installed; then
        proot_distro_install
    fi

    # Start VNC server
    vnc_start

    # Wait for VNC to be ready
    local retries=0
    while ! vnc_is_running && [[ $retries -lt 10 ]]; do
        sleep 1
        ((retries++))
    done

    if ! vnc_is_running; then
        log_error "VNC server failed to start"
        return 1
    fi

    alicia_set_state "ALICIA_RUNNING" "true"
    log_info "Alicia Desktop Environment is running"
    log_info "Connect your VNC client to: $(network_get_ip):$ALICIA_VNC_PORT"
    return 0
}

# alicia_full_stop - Stop the complete Alicia system
alicia_full_stop() {
    log_section "Stopping Alicia Desktop Environment"

    de_stop 2>/dev/null || true
    vnc_stop 2>/dev/null || true
    proot_stop 2>/dev/null || true

    alicia_set_state "ALICIA_RUNNING" "false"
    log_info "Alicia Desktop Environment stopped"
    return 0
}
