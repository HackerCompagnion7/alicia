#!/bin/bash
# ============================================================================
# 01-termux-setup.sh - Alicia Desktop Environment Termux Setup
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
# Description:  Sets up the Termux environment for Alicia Desktop.
#               Updates packages, installs essentials, configures storage,
#               creates directory structure, sets environment variables,
#               configures Termux properties, and validates compatibility.
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

# If libraries didn't load (standalone mode), define minimal helpers
if ! declare -f log_info &>/dev/null; then
    # Minimal color constants
    readonly C_RESET='\033[0m'
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[0;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_CYAN='\033[0;36m'
    readonly C_BOLD='\033[1m'
    readonly C_BOLD_RED='\033[1;31m'
    readonly C_BOLD_GREEN='\033[1;32m'
    readonly C_BOLD_BLUE='\033[1;34m'
    readonly C_BOLD_CYAN='\033[1;36m'
    readonly C_BOLD_WHITE='\033[1;37m'
    readonly C_DIM='\033[2m'

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
readonly ALICIA_SUBDIRS=(
    "bin"
    "lib"
    "config"
    "cache"
    "logs"
    "backups"
    "downloads"
    "tmp"
    "rootfs"
    "proot"
)
readonly TERMUX_MIN_VERSION="0.118"
readonly ANDROID_MIN_API="21"

# Packages required for Termux environment
readonly TERMUX_ESSENTIAL_PACKAGES=(
    "proot-distro"
    "wget"
    "curl"
    "openssh"
    "git"
    "python"
    "nano"
    "vim"
    "tar"
    "gzip"
)

# Optional but recommended packages
readonly TERMUX_RECOMMENDED_PACKAGES=(
    "unzip"
    "zip"
    "htop"
    "tree"
    "ncurses-utils"
    "termux-api"
    "termux-exec"
    "cronie"
    "rsync"
    "p7zip"
)

# ============================================================================
# State Tracking
# ============================================================================
_SETUP_STATE_FILE="${ALICIA_BASE_DIR}/.setup-01-state"
declare -gA _COMPLETED_STEPS=()

# ============================================================================
# State Management Functions
# ============================================================================

# step_completed - Check if a setup step was already completed
step_completed() {
    local step="$1"
    [[ -n "${_COMPLETED_STEPS[$step]:-}" ]]
}

# mark_step_completed - Mark a setup step as completed
mark_step_completed() {
    local step="$1"
    _COMPLETED_STEPS["$step"]="1"
    echo "$step" >> "$_SETUP_STATE_FILE"
}

# load_state - Load previously completed steps
load_state() {
    if [[ -f "$_SETUP_STATE_FILE" ]]; then
        while IFS= read -r step; do
            _COMPLETED_STEPS["$step"]="1"
        done < "$_SETUP_STATE_FILE"
        log_info "Loaded previous setup state: ${#_COMPLETED_STEPS[@]} steps already completed"
    fi
}

# ============================================================================
# Safe Package Install with Retry
# ============================================================================

# safe_pkg_install - Install a Termux package with retry logic
# Arguments: $1 - package name, $2 - max retries (default: 3)
# Returns: 0 on success, 1 on failure after all retries.
safe_pkg_install() {
    local package="$1"
    local max_retries="${2:-3}"
    local attempt=0

    # Check if already installed
    if pkg list-installed 2>/dev/null | grep -q "^${package}/"; then
        log_debug "Package already installed: $package"
        return 0
    fi

    while [[ $attempt -lt $max_retries ]]; do
        attempt=$((attempt + 1))
        log_info "Installing: $package (attempt $attempt/$max_retries)"

        if pkg install -y "$package" 2>&1 | while IFS= read -r line; do
            log_debug "  pkg: $line"
        done; then
            # Verify installation
            if pkg list-installed 2>/dev/null | grep -q "^${package}/"; then
                log_info "Successfully installed: $package"
                return 0
            fi
        fi

        if [[ $attempt -lt $max_retries ]]; then
            log_warn "Retrying $package in 5 seconds... (attempt $attempt/$max_retries failed)"
            sleep 5
        fi
    done

    log_error "Failed to install $package after $max_retries attempts"
    return 1
}

# ============================================================================
# Validation Functions
# ============================================================================

# validate_termux_environment - Verify we are running in Termux
validate_termux_environment() {
    log_section "Validating Termux Environment"

    if step_completed "validate_termux"; then
        log_info "Termux validation already completed, skipping"
        return 0
    fi

    # Check if running in Termux
    if [[ -z "${TERMUX_VERSION:-}" && ! -d "/data/data/com.termux" ]]; then
        log_error "This script must be run inside Termux"
        log_error "Current environment does not appear to be Termux"
        log_error "Please install Termux from F-Droid or GitHub releases"
        return 1
    fi
    log_info "Termux environment detected (version: ${TERMUX_VERSION:-unknown})"

    # Check if pkg command is available
    if ! command -v pkg &>/dev/null; then
        log_error "Termux package manager (pkg) not found"
        log_error "This may indicate a broken Termux installation"
        return 1
    fi
    log_info "Termux package manager (pkg) is available"

    # Validate Termux version (minimum version check)
    local termux_ver="${TERMUX_VERSION:-0.0.0}"
    termux_ver="${termux_ver%%-*}"  # Strip any suffix like -fdroid
    local ver_major ver_minor
    IFS='.' read -r ver_major ver_minor _ <<< "$termux_ver"
    local min_major min_minor
    IFS='.' read -r min_major min_minor _ <<< "$TERMUX_MIN_VERSION"

    local ver_num=$((10#${ver_major:-0} * 1000 + 10#${ver_minor:-0}))
    local min_num=$((10#${min_major:-0} * 1000 + 10#${min_minor:-0}))

    if [[ $ver_num -lt $min_num ]]; then
        log_warn "Termux version $termux_ver is below minimum recommended $TERMUX_MIN_VERSION"
        log_warn "Some features may not work correctly"
        log_warn "Please update Termux from F-Droid"
    else
        log_info "Termux version $termux_ver meets minimum requirement ($TERMUX_MIN_VERSION)"
    fi

    # Check Android API level
    local android_api
    android_api=$(getprop ro.build.version.sdk 2>/dev/null || echo "0")
    if [[ $android_api -ne 0 ]]; then
        if [[ $android_api -lt $ANDROID_MIN_API ]]; then
            log_error "Android API level $android_api is below minimum ($ANDROID_MIN_API)"
            log_error "Alicia requires Android 5.0 (Lollipop) or later"
            return 1
        fi
        log_info "Android API level: $android_api (meets minimum: $ANDROID_MIN_API)"
    else
        log_warn "Could not determine Android API level (may not be running on Android)"
    fi

    # Check device architecture
    local arch
    arch=$(uname -m 2>/dev/null || echo "unknown")
    log_info "Device architecture: $arch"
    case "$arch" in
        aarch64|arm64)  log_info "Architecture: ARM64 (recommended)" ;;
        armv7l|armv8l)  log_warn "Architecture: ARM32 (64-bit recommended for best performance)" ;;
        x86_64)         log_info "Architecture: x86_64 (emulator or Chrome OS)" ;;
        i686|i386)      log_warn "Architecture: x86 (32-bit, limited support)" ;;
        *)              log_warn "Architecture: $arch (untested)" ;;
    esac

    # Check available memory
    local mem_total
    if [[ -f /proc/meminfo ]]; then
        mem_total=$(awk '/^MemTotal:/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
        if [[ $mem_total -gt 0 ]]; then
            log_info "Total RAM: ${mem_total}MB"
            if [[ $mem_total -lt 2048 ]]; then
                log_warn "Low RAM detected (${mem_total}MB). Minimum recommended: 2048MB"
                log_warn "Desktop environment may be slow or unstable"
            fi
        fi
    fi

    # Check available storage
    local storage_avail
    storage_avail=$(df -k "$HOME" 2>/dev/null | tail -1 | awk '{print int($4/1024)}')
    if [[ -n "${storage_avail:-}" && $storage_avail -gt 0 ]]; then
        log_info "Available storage: ${storage_avail}MB"
        if [[ $storage_avail -lt 4096 ]]; then
            log_warn "Low storage (${storage_avail}MB). Alicia needs at least 4GB free space"
        fi
    fi

    mark_step_completed "validate_termux"
    log_info "Termux environment validation passed"
    return 0
}

# ============================================================================
# Package Management Functions
# ============================================================================

# update_termux_packages - Update and upgrade all Termux packages
update_termux_packages() {
    log_section "Updating Termux Packages"

    if step_completed "update_packages"; then
        log_info "Package update already completed, skipping"
        return 0
    fi

    log_info "Updating package lists..."
    if ! pkg update -y 2>&1 | while IFS= read -r line; do
        log_debug "  pkg update: $line"
    done; then
        log_warn "Package update encountered issues, attempting to continue"
    fi
    log_info "Package lists updated"

    log_info "Upgrading installed packages..."
    if ! pkg upgrade -y 2>&1 | while IFS= read -r line; do
        log_debug "  pkg upgrade: $line"
    done; then
        log_warn "Package upgrade encountered issues, attempting to continue"
    fi
    log_info "Packages upgraded"

    # Clean up package cache to save space
    pkg clean -y 2>/dev/null || true
    log_info "Package cache cleaned"

    mark_step_completed "update_packages"
    log_info "Termux package update complete"
    return 0
}

# install_essential_packages - Install required Termux packages
install_essential_packages() {
    log_section "Installing Essential Termux Packages"

    if step_completed "install_essentials"; then
        log_info "Essential packages already installed, skipping"
        return 0
    fi

    local total=${#TERMUX_ESSENTIAL_PACKAGES[@]}
    local current=0
    local failed=0

    for package in "${TERMUX_ESSENTIAL_PACKAGES[@]}"; do
        ((current++)) || true
        log_progress "$current" "$total" "Installing essential packages"

        if ! safe_pkg_install "$package" 3; then
            log_warn "Failed to install: $package (will attempt to continue)"
            ((failed++)) || true
        fi
    done

    log_progress "$total" "$total" "Installing essential packages"

    if [[ $failed -gt 0 ]]; then
        log_warn "$failed essential package(s) failed to install"
    fi

    log_info "Essential packages installation complete"

    # Install recommended packages (non-fatal)
    log_subsection "Installing Recommended Packages"
    local rec_total=${#TERMUX_RECOMMENDED_PACKAGES[@]}
    local rec_current=0
    local rec_failed=0

    for package in "${TERMUX_RECOMMENDED_PACKAGES[@]}"; do
        ((rec_current++)) || true
        log_progress "$rec_current" "$rec_total" "Installing recommended packages"

        if ! safe_pkg_install "$package" 2; then
            log_debug "Failed to install recommended package: $package (non-fatal)"
            ((rec_failed++)) || true
        fi
    done

    log_progress "$rec_total" "$rec_total" "Installing recommended packages"

    if [[ $rec_failed -gt 0 ]]; then
        log_debug "$rec_failed recommended package(s) could not be installed"
    fi

    mark_step_completed "install_essentials"
    log_info "Package installation phase complete"
    return 0
}

# ============================================================================
# Storage and Directory Setup
# ============================================================================

# configure_storage_access - Set up Termux storage access
configure_storage_access() {
    log_section "Configuring Termux Storage Access"

    if step_completed "configure_storage"; then
        log_info "Storage access already configured, skipping"
        return 0
    fi

    # Check if storage is already set up
    if [[ -d "$HOME/storage" ]]; then
        log_info "Termux storage access is already configured"
        log_info "Storage directory exists: $HOME/storage"
    else
        log_info "Setting up Termux storage access..."
        log_info "NOTE: A permission dialog may appear - please grant access"

        # Run termux-setup-storage (this will prompt the user)
        if ! termux-setup-storage 2>&1; then
            log_warn "termux-setup-storage failed or was denied"
            log_warn "Alicia will work but cannot access shared Android storage"
            log_warn "You can run 'termux-setup-storage' manually later"
        else
            log_info "Termux storage access configured successfully"
        fi
    fi

    # Verify storage symlinks
    local storage_dir="$HOME/storage"
    if [[ -d "$storage_dir" ]]; then
        local links=("shared" "downloads" "dcim" "music" "pictures" "movies")
        for link in "${links[@]}"; do
            if [[ -L "$storage_dir/$link" || -d "$storage_dir/$link" ]]; then
                log_debug "Storage link exists: $link"
            else
                log_debug "Storage link missing: $link"
            fi
        done
    fi

    mark_step_completed "configure_storage"
    log_info "Storage configuration complete"
    return 0
}

# create_alicia_directories - Create the Alicia directory structure
create_alicia_directories() {
    log_section "Creating Alicia Directory Structure"

    if step_completed "create_directories"; then
        log_info "Alicia directories already created, skipping"
        return 0
    fi

    log_info "Creating base directory: $ALICIA_BASE_DIR"
    mkdir -p "$ALICIA_BASE_DIR"

    local total=${#ALICIA_SUBDIRS[@]}
    local current=0

    for subdir in "${ALICIA_SUBDIRS[@]}"; do
        ((current++)) || true
        log_progress "$current" "$total" "Creating directories"

        local dir_path="${ALICIA_BASE_DIR}/${subdir}"
        if [[ ! -d "$dir_path" ]]; then
            mkdir -p "$dir_path"
            log_debug "Created: $dir_path"
        else
            log_debug "Already exists: $dir_path"
        fi
    done

    log_progress "$total" "$total" "Creating directories"

    # Create additional useful subdirectories
    local extra_dirs=(
        "${ALICIA_BASE_DIR}/config/xfce4"
        "${ALICIA_BASE_DIR}/config/vnc"
        "${ALICIA_BASE_DIR}/config/themes"
        "${ALICIA_BASE_DIR}/lib/scripts"
        "${ALICIA_BASE_DIR}/lib/modules"
        "${ALICIA_BASE_DIR}/cache/apt"
        "${ALICIA_BASE_DIR}/cache/pip"
        "${ALICIA_BASE_DIR}/cache/npm"
        "${ALICIA_BASE_DIR}/state"
        "${ALICIA_BASE_DIR}/locks"
    )

    for dir_path in "${extra_dirs[@]}"; do
        mkdir -p "$dir_path" 2>/dev/null || true
    done

    # Create .gitignore to avoid tracking generated files
    cat > "${ALICIA_BASE_DIR}/.gitignore" << 'GITIGNORE_EOF'
# Alicia Directory - Generated Files
cache/
logs/*.log
tmp/
backups/*.tar.gz
downloads/*.deb
downloads/*.apk
rootfs/
proot/
state/
locks/
*.pid
*.lock
GITIGNORE_EOF

    # Create a marker file with version info
    cat > "${ALICIA_BASE_DIR}/.alicia-info" << INFO_EOF
ALICIA_VERSION=${SCRIPT_VERSION}
ALICIA_HOME=${ALICIA_BASE_DIR}
CREATED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
CREATED_BY=${SCRIPT_NAME}
VENDOR=Proyecto Tomorrow
INFO_EOF

    mark_step_completed "create_directories"
    log_info "Alicia directory structure created"
    return 0
}

# ============================================================================
# Environment Configuration
# ============================================================================

# setup_environment_variables - Configure .bashrc and .profile
setup_environment_variables() {
    log_section "Setting Up Environment Variables"

    if step_completed "setup_env_vars"; then
        log_info "Environment variables already configured, skipping"
        return 0
    fi

    # --- .bashrc configuration ---
    local bashrc_file="$HOME/.bashrc"
    local bashrc_marker="# >>> ALICIA ENVIRONMENT >>>"
    local bashrc_end_marker="# <<< ALICIA ENVIRONMENT <<<"

    # Remove existing Alicia block if present
    if [[ -f "$bashrc_file" ]] && grep -q "$bashrc_marker" "$bashrc_file" 2>/dev/null; then
        log_info "Updating existing Alicia environment block in .bashrc"
        sed -i "/$bashrc_marker/,/$bashrc_end_marker/d" "$bashrc_file" 2>/dev/null || true
    fi

    # Append Alicia environment block
    {
        echo ""
        echo "$bashrc_marker"
        echo "# Alicia Desktop Environment - Environment Variables"
        echo "# Auto-configured by ${SCRIPT_NAME} v${SCRIPT_VERSION}"
        echo "# Do not modify this block - changes will be overwritten"
        echo ""
        echo "# Alicia Home Directory"
        echo "export ALICIA_HOME=\"\${HOME}/alicia\""
        echo ""
        echo "# Alicia PATH additions"
        echo "export PATH=\"\${ALICIA_HOME}/bin:\${ALICIA_HOME}/lib/scripts:\$PATH\""
        echo ""
        echo "# Alicia Directory Paths"
        echo "export ALICIA_BIN_DIR=\"\${ALICIA_HOME}/bin\""
        echo "export ALICIA_LIB_DIR=\"\${ALICIA_HOME}/lib\""
        echo "export ALICIA_CONFIG_DIR=\"\${ALICIA_HOME}/config\""
        echo "export ALICIA_CACHE_DIR=\"\${ALICIA_HOME}/cache\""
        echo "export ALICIA_LOG_DIR=\"\${ALICIA_HOME}/logs\""
        echo "export ALICIA_BACKUP_DIR=\"\${ALICIA_HOME}/backups\""
        echo "export ALICIA_DOWNLOAD_DIR=\"\${ALICIA_HOME}/downloads\""
        echo "export ALICIA_TMP_DIR=\"\${ALICIA_HOME}/tmp\""
        echo "export ALICIA_ROOTFS_DIR=\"\${ALICIA_HOME}/rootfs\""
        echo "export ALICIA_PROOT_DIR=\"\${ALICIA_HOME}/proot\""
        echo ""
        echo "# Alicia Configuration"
        echo "export ALICIA_VERSION=\"${SCRIPT_VERSION}\""
        echo "export ALICIA_DISTRO_NAME=\"alpine\""
        echo "export ALICIA_VNC_PORT=5901"
        echo "export ALICIA_VNC_RESOLUTION=\"1280x720\""
        echo "export ALICIA_DISPLAY=\":1\""
        echo ""
        echo "# Termux-specific settings"
        echo "export TERM=xterm-256color"
        echo "export LANG=en_US.UTF-8"
        echo "export LC_ALL=en_US.UTF-8"
        echo "export EDITOR=nano"
        echo "export VISUAL=nano"
        echo "export PAGER=less"
        echo ""
        echo "# Android/Termux compatibility"
        echo "export ANDROID_ROOT=/system"
        echo "export ANDROID_DATA=/data"
        echo ""
        echo "# Alias shortcuts for Alicia"
        echo "alias alicia='alicia-cli'"
        echo "alias alicia-start='alicia-cli start'"
        echo "alias alicia-stop='alicia-cli stop'"
        echo "alias alicia-status='alicia-cli status'"
        echo "alias alicia-vnc='alicia-cli vnc'"
        echo ""
        echo "$bashrc_end_marker"
    } >> "$bashrc_file"

    log_info "Environment variables added to .bashrc"

    # --- .profile configuration ---
    local profile_file="$HOME/.profile"
    local profile_marker="# >>> ALICIA PROFILE >>>"
    local profile_end_marker="# <<< ALICIA PROFILE <<<"

    # Remove existing block if present
    if [[ -f "$profile_file" ]] && grep -q "$profile_marker" "$profile_file" 2>/dev/null; then
        sed -i "/$profile_marker/,/$profile_end_marker/d" "$profile_file" 2>/dev/null || true
    fi

    {
        echo ""
        echo "$profile_marker"
        echo "# Alicia Desktop Environment - Login Profile"
        echo "# Source .bashrc if running in an interactive shell"
        echo "if [[ -n \"\$PS1\" ]] && [[ -f \"\$HOME/.bashrc\" ]]; then"
        echo "    source \"\$HOME/.bashrc\""
        echo "fi"
        echo "$profile_end_marker"
    } >> "$profile_file"

    log_info "Profile configuration added to .profile"

    mark_step_completed "setup_env_vars"
    log_info "Environment variables configured"
    return 0
}

# ============================================================================
# Command-Line Tool Setup
# ============================================================================

# create_alicia_cli - Create the alicia command-line tool
create_alicia_cli() {
    log_section "Creating Alicia CLI Tool"

    if step_completed "create_cli"; then
        log_info "Alicia CLI already created, skipping"
        return 0
    fi

    local cli_script="${ALICIA_BASE_DIR}/bin/alicia-cli"

    mkdir -p "${ALICIA_BASE_DIR}/bin"

    cat > "$cli_script" << 'CLI_SCRIPT'
#!/bin/bash
# ============================================================================
# alicia-cli - Alicia Desktop Environment Command-Line Interface
# ============================================================================
# Copyright (C) 2005-2025 Proyecto Tomorrow
# Version: 3.1.0
# ============================================================================

set -uo pipefail

ALICIA_HOME="${ALICIA_HOME:-$HOME/alicia}"
ALICIA_VERSION="${ALICIA_VERSION:-3.1.0}"
ALICIA_DISTRO_NAME="${ALICIA_DISTRO_NAME:-alpine}"

# Color output
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

info()  { printf "${C_GREEN}[Alicia]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}[Alicia]${C_RESET} %s\n" "$*" >&2; }
error() { printf "${C_RED}[Alicia]${C_RESET} %s\n" "$*" >&2; }

usage() {
    echo "Alicia Desktop Environment CLI v${ALICIA_VERSION}"
    echo ""
    echo "Usage: alicia-cli <command> [options]"
    echo ""
    echo "Commands:"
    echo "  start       Start the Alicia desktop (VNC + proot + XFCE)"
    echo "  stop        Stop the Alicia desktop"
    echo "  restart     Restart the Alicia desktop"
    echo "  status      Show Alicia status information"
    echo "  vnc         Manage VNC server (start|stop|restart|info)"
    echo "  shell       Open a shell inside the proot environment"
    echo "  install     Run the Alicia setup scripts"
    echo "  update      Check for and apply updates"
    echo "  config      Manage Alicia configuration"
    echo "  help        Show this help message"
    echo "  version     Show version information"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show help"
    echo "  -v, --verbose  Verbose output"
    echo "  -q, --quiet    Quiet mode"
}

cmd_start() {
    info "Starting Alicia Desktop Environment..."
    if command -v proot-distro &>/dev/null; then
        proot-distro login "$ALICIA_DISTRO_NAME" -- bash -c "
            export DISPLAY=${ALICIA_DISPLAY:-:1}
            if command -v vncserver &>/dev/null; then
                vncserver \${ALICIA_DISPLAY:-:1} -geometry \${ALICIA_VNC_RESOLUTION:-1280x720} -depth 24 -localhost no 2>/dev/null || true
            fi
            if command -v startxfce4 &>/dev/null; then
                startxfce4 &
            fi
        " 2>/dev/null || warn "proot login encountered issues"
    else
        error "proot-distro is not installed. Run the setup scripts first."
        return 1
    fi
    info "Alicia Desktop started"
    info "Connect VNC client to localhost:${ALICIA_VNC_PORT:-5901}"
}

cmd_stop() {
    info "Stopping Alicia Desktop Environment..."
    if command -v proot-distro &>/dev/null; then
        proot-distro login "$ALICIA_DISTRO_NAME" -- bash -c "
            vncserver -kill ${ALICIA_DISPLAY:-:1} 2>/dev/null || true
            pkill -f xfce4-session 2>/dev/null || true
        " 2>/dev/null || true
    fi
    info "Alicia Desktop stopped"
}

cmd_status() {
    info "Alicia Desktop Environment v${ALICIA_VERSION}"
    info "  Home:     ${ALICIA_HOME}"
    info "  Distro:   ${ALICIA_DISTRO_NAME}"
    info "  VNC Port: ${ALICIA_VNC_PORT:-5901}"
    info "  Display:  ${ALICIA_DISPLAY:-:1}"
    if command -v proot-distro &>/dev/null; then
        if proot-distro list 2>/dev/null | grep -q "$ALICIA_DISTRO_NAME"; then
            info "  proot:    Installed"
        else
            warn "  proot:    Not installed"
        fi
    else
        warn "  proot-distro: Not found"
    fi
}

cmd_shell() {
    if command -v proot-distro &>/dev/null; then
        exec proot-distro login "$ALICIA_DISTRO_NAME" -- bash
    else
        error "proot-distro is not installed"
        return 1
    fi
}

cmd_vnc() {
    local action="${1:-info}"
    case "$action" in
        start)
            info "Starting VNC server..."
            proot-distro login "$ALICIA_DISTRO_NAME" -- bash -c "
                export DISPLAY=${ALICIA_DISPLAY:-:1}
                vncserver \$DISPLAY -geometry ${ALICIA_VNC_RESOLUTION:-1280x720} -depth 24 -localhost no
            " 2>/dev/null || error "Failed to start VNC server"
            ;;
        stop)
            info "Stopping VNC server..."
            proot-distro login "$ALICIA_DISTRO_NAME" -- bash -c "
                vncserver -kill ${ALICIA_DISPLAY:-:1} 2>/dev/null || true
            " 2>/dev/null
            ;;
        info)
            info "VNC Configuration:"
            info "  Display:     ${ALICIA_DISPLAY:-:1}"
            info "  Port:        ${ALICIA_VNC_PORT:-5901}"
            info "  Resolution:  ${ALICIA_VNC_RESOLUTION:-1280x720}"
            ;;
        *)
            error "Unknown VNC action: $action"
            ;;
    esac
}

cmd_version() {
    echo "Alicia Desktop Environment v${ALICIA_VERSION}"
    echo "Copyright (C) 2005-2025 Proyecto Tomorrow"
    echo "Licensed under GNU General Public License v3.0"
}

# Main dispatch
case "${1:-help}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    restart) cmd_stop; sleep 2; cmd_start ;;
    status)  cmd_status ;;
    vnc)     cmd_vnc "${2:-info}" ;;
    shell)   cmd_shell ;;
    help|-h|--help) usage ;;
    version|-V|--version) cmd_version ;;
    *)
        error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
CLI_SCRIPT

    chmod +x "$cli_script"
    log_info "Alicia CLI script created: $cli_script"

    # Create symlink in Termux bin directory if possible
    local symlink_path="$HOME/bin/alicia-cli"
    mkdir -p "$HOME/bin" 2>/dev/null || true
    if [[ ! -L "$symlink_path" && ! -f "$symlink_path" ]]; then
        ln -sf "$cli_script" "$symlink_path" 2>/dev/null && \
            log_info "Symlink created: $symlink_path -> $cli_script" || \
            log_debug "Could not create symlink at $symlink_path"
    fi

    # Also create a short 'alicia' alias
    local alias_path="$HOME/bin/alicia"
    if [[ ! -L "$alias_path" && ! -f "$alias_path" ]]; then
        ln -sf "$cli_script" "$alias_path" 2>/dev/null || true
    fi

    mark_step_completed "create_cli"
    log_info "Alicia CLI tool created"
    return 0
}

# ============================================================================
# Termux Integration Setup
# ============================================================================

# setup_termux_boot - Set up Termux:Boot integration
setup_termux_boot() {
    log_section "Setting Up Termux:Boot Integration"

    if step_completed "setup_boot"; then
        log_info "Termux:Boot integration already set up, skipping"
        return 0
    fi

    local boot_dir="$HOME/.termux/boot"
    mkdir -p "$boot_dir" 2>/dev/null || {
        log_warn "Cannot create Termux:Boot directory (Termux:Boot may not be installed)"
        log_warn "Boot integration will be skipped"
        return 0
    }

    # Create boot script that starts Alicia services on device boot
    local boot_script="$boot_dir/alicia-boot.sh"
    cat > "$boot_script" << 'BOOT_SCRIPT'
#!/bin/bash
# Alicia Desktop Environment - Boot Script
# This script runs when the device boots (requires Termux:Boot)
# It starts the Alicia services in the background

ALICIA_HOME="${ALICIA_HOME:-$HOME/alicia}"

# Wait for network to become available
sleep 10

# Start Alicia services if auto-start is enabled
if [[ -f "${ALICIA_HOME}/config/auto-start" ]]; then
    source "${ALICIA_HOME}/bin/alicia-cli" start 2>/dev/null || true
fi
BOOT_SCRIPT

    chmod +x "$boot_script"
    log_info "Boot script created: $boot_script"

    mark_step_completed "setup_boot"
    log_info "Termux:Boot integration configured"
    return 0
}

# setup_termux_widget - Set up Termux:Widget shortcuts
setup_termux_widget() {
    log_section "Setting Up Termux:Widget Shortcuts"

    if step_completed "setup_widget"; then
        log_info "Termux:Widget already set up, skipping"
        return 0
    fi

    local widget_dir="$HOME/.termux/shortcuts"
    mkdir -p "$widget_dir" 2>/dev/null || {
        log_warn "Cannot create Termux:Widget directory (Termux:Widget may not be installed)"
        log_warn "Widget shortcuts will be skipped"
        return 0
    }

    # Create widget shortcuts
    local shortcuts=(
        "Alicia Start:${ALICIA_BASE_DIR}/bin/alicia-cli start"
        "Alicia Stop:${ALICIA_BASE_DIR}/bin/alicia-cli stop"
        "Alicia Status:${ALICIA_BASE_DIR}/bin/alicia-cli status"
        "Alicia VNC Info:${ALICIA_BASE_DIR}/bin/alicia-cli vnc info"
        "Alicia Shell:${ALICIA_BASE_DIR}/bin/alicia-cli shell"
    )

    for shortcut_def in "${shortcuts[@]}"; do
        local name="${shortcut_def%%:*}"
        local cmd="${shortcut_def#*:}"
        local shortcut_file="${widget_dir}/${name}.sh"

        cat > "$shortcut_file" << SHORTCUT_EOF
#!/bin/bash
# Alicia Widget Shortcut: $name
$cmd
echo ""
echo "Press Enter to close..."
read -r
SHORTCUT_EOF
        chmod +x "$shortcut_file"
        log_debug "Widget shortcut created: $name"
    done

    mark_step_completed "setup_widget"
    log_info "Termux:Widget shortcuts created"
    return 0
}

# ============================================================================
# Termux Properties Configuration
# ============================================================================

# configure_termux_properties - Set up termux.properties
configure_termux_properties() {
    log_section "Configuring Termux Properties"

    if step_completed "configure_properties"; then
        log_info "Termux properties already configured, skipping"
        return 0
    fi

    local termux_dir="$HOME/.termux"
    local props_file="$termux_dir/termux.properties"

    mkdir -p "$termux_dir"

    # Backup existing properties if present
    if [[ -f "$props_file" ]]; then
        local backup_file="$termux_dir/termux.properties.bak.$(date +%Y%m%d%H%M%S)"
        cp "$props_file" "$backup_file"
        log_info "Existing termux.properties backed up"
    fi

    # Write Alicia-optimized termux.properties
    cat > "$props_file" << 'PROPS_EOF'
# ============================================================================
# Alicia Desktop Environment - Termux Properties
# ============================================================================
# Optimized configuration for running a Linux desktop via proot + VNC
# ============================================================================

# --- Bell Configuration ---
# Disable terminal bell (prevents annoying beeps during desktop use)
bell-character=ignore

# --- Extra Keys Configuration ---
# Custom extra keys row for Alicia shortcuts
extra-keys = [[ \
  {key: ESC, popup: {macro: "CTRL d", display: "exit"}}, \
  {key: CTRL, popup: {macro: "CTRL c", display: "cancel"}}, \
  {key: ALT, popup: {macro: "CTRL z", display: "undo"}}, \
  {key: TAB, popup: {macro: "CTRL a", display: "all"}}, \
  {key: '/', popup: '~'}, \
  {key: '-', popup: '_'}, \
  {key: HOME, popup: END}, \
  {key: UP, popup: PGUP}, \
  {key: DOWN, popup: PGDN}, \
  {key: LEFT, popup: HOME}, \
  {key: RIGHT, popup: END} \
]]

# Second extra keys row with special characters for desktop use
extra-keys-style = default

# --- Cursor Configuration ---
cursor-style = block

# --- Terminal Configuration ---
# Use UTF-8 encoding
terminal-cursor-blink = true

# --- Keyboard Configuration ---
# Enable virtual keyboard shortcuts
keyboard-character-map = utf-8

# --- Session Configuration ---
# Increase scrollback buffer for desktop work
terminal-scrollbar-right = true

# --- Display Configuration ---
# Fullscreen mode for better desktop experience
fullscreen = false

# --- Application Configuration ---
# Allow external applications to access Termux
allow-external-apps = true

# --- Shell Configuration ---
shell = /data/data/com.termux/files/usr/bin/bash

# --- Shortcut Configuration ---
# Create session shortcuts
shortcut.create = ctrl + shift + c
shortcut.next-session = ctrl + shift + down
shortcut.previous-session = ctrl + shift + up
shortcut.rename-session = ctrl + shift + r
PROPS_EOF

    # Apply the new properties
    termux-reload-settings 2>/dev/null || {
        log_debug "termux-reload-settings not available (non-fatal)"
    }

    mark_step_completed "configure_properties"
    log_info "Termux properties configured"
    return 0
}

# ============================================================================
# Welcome Message Setup
# ============================================================================

# setup_welcome_message - Add Alicia welcome message to .bashrc
setup_welcome_message() {
    log_section "Setting Up Alicia Welcome Message"

    if step_completed "setup_welcome"; then
        log_info "Welcome message already configured, skipping"
        return 0
    fi

    local bashrc_file="$HOME/.bashrc"
    local welcome_marker="# >>> ALICIA WELCOME >>>"
    local welcome_end_marker="# <<< ALICIA WELCOME <<<"

    # Remove existing block if present
    if [[ -f "$bashrc_file" ]] && grep -q "$welcome_marker" "$bashrc_file" 2>/dev/null; then
        sed -i "/$welcome_marker/,/$welcome_end_marker/d" "$bashrc_file" 2>/dev/null || true
    fi

    # Append welcome message block
    {
        echo ""
        echo "$welcome_marker"
        echo "# Alicia Desktop Environment - Welcome Message"
        echo "if [[ -n \"\$PS1\" ]]; then"
        echo "    echo ''"
        echo "    echo '  +===================================================+'"
        echo "    echo '  |          Alicia Desktop Environment               |'"
        echo "    echo '  |          Version ${SCRIPT_VERSION} - Proyecto Tomorrow            |'"
        echo "    echo '  ?===================================================?'"
        echo "    echo '  |                                                   |'"
        echo "    echo '  |  Commands:                                        |'"
        echo "    echo '  |    alicia start   - Start desktop                 |'"
        echo "    echo '  |    alicia stop    - Stop desktop                  |'"
        echo "    echo '  |    alicia status  - Show status                   |'"
        echo "    echo '  |    alicia shell   - Enter proot shell             |'"
        echo "    echo '  |    alicia help    - Show all commands             |'"
        echo "    echo '  |                                                   |'"
        echo "    echo '  |  Connect VNC client to: localhost:\${ALICIA_VNC_PORT:-5901}     |'"
        echo "    echo '  |                                                   |'"
        echo "    echo '  +===================================================+'"
        echo "    echo ''"
        echo "fi"
        echo "$welcome_end_marker"
    } >> "$bashrc_file"

    mark_step_completed "setup_welcome"
    log_info "Welcome message configured"
    return 0
}

# ============================================================================
# Post-Setup Validation
# ============================================================================

# validate_setup - Validate that the setup completed successfully
validate_setup() {
    log_section "Validating Setup"

    local errors=0

    # Check essential directories
    for subdir in "${ALICIA_SUBDIRS[@]}"; do
        if [[ ! -d "${ALICIA_BASE_DIR}/${subdir}" ]]; then
            log_error "Missing directory: ${ALICIA_BASE_DIR}/${subdir}"
            ((errors++)) || true
        fi
    done

    # Check essential packages
    for package in "${TERMUX_ESSENTIAL_PACKAGES[@]}"; do
        if ! command -v "$package" &>/dev/null; then
            # Some packages install commands with different names
            case "$package" in
                proot-distro) command -v proot-distro &>/dev/null || { log_warn "Package not found in PATH: $package"; } ;;
                openssh) command -v ssh &>/dev/null || { log_warn "Package not found in PATH: $package"; } ;;
                *) log_warn "Package not found in PATH: $package" ;;
            esac
        fi
    done

    # Check CLI tool
    if [[ ! -x "${ALICIA_BASE_DIR}/bin/alicia-cli" ]]; then
        log_error "Alicia CLI tool not found or not executable"
        ((errors++)) || true
    fi

    # Check .bashrc has Alicia configuration
    if ! grep -q "ALICIA_HOME" "$HOME/.bashrc" 2>/dev/null; then
        log_warn "Alicia environment variables not found in .bashrc"
    fi

    # Check storage access
    if [[ ! -d "$HOME/storage" ]]; then
        log_warn "Termux storage access not configured"
    fi

    if [[ $errors -eq 0 ]]; then
        log_info "All validation checks passed"
    else
        log_warn "$errors validation error(s) found"
        log_warn "Some features may not work correctly"
    fi

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
    # Release any locks
    if declare -f alicia_lock_release &>/dev/null; then
        alicia_lock_release "setup-01" 2>/dev/null || true
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
    log_section "Alicia Desktop - Termux Setup (Step 1/6)"
    log_info "Version: ${SCRIPT_VERSION}"
    log_info "Author:  Proyecto Tomorrow"
    log_info "Time:    $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Load previous state for resumability
    load_state

    # Acquire lock to prevent concurrent execution
    if declare -f alicia_lock_acquire &>/dev/null; then
        alicia_lock_acquire "setup-01" 300 || {
            log_error "Another setup process is already running"
            exit 1
        }
    fi

    # Execute setup steps in order
    local steps=(
        "validate_termux_environment"
        "update_termux_packages"
        "install_essential_packages"
        "configure_storage_access"
        "create_alicia_directories"
        "setup_environment_variables"
        "create_alicia_cli"
        "setup_termux_boot"
        "setup_termux_widget"
        "configure_termux_properties"
        "setup_welcome_message"
        "validate_setup"
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
    log_section "Termux Setup Complete"
    log_info "All Termux setup steps completed successfully!"
    echo ""
    log_info "Next steps:"
    log_info "  1. Run: ${SCRIPT_DIR}/02-proot-setup.sh"
    log_info "  2. This will install Alpine Linux via proot-distro"
    log_info "  3. Then continue with remaining setup scripts"
    echo ""
    log_info "Quick commands:"
    log_info "  alicia status  - Check current status"
    log_info "  alicia help    - Show all available commands"
    echo ""

    return 0
}

# Execute main function
main "$@"
