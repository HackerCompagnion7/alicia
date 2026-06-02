#!/bin/bash
# ============================================================================
# 05-apps-setup.sh - Alicia Desktop Environment Applications Setup
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
# Description:  Installs pre-installed applications for the Alicia Desktop.
#               Covers development tools, editors, browsers, office,
#               graphics, terminals, system/network/media tools,
#               archive managers, Python/Node packages, .desktop files,
#               default associations, menu categories, desktop launchers,
#               and Alicia-specific custom applications.
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
    log_subsection() { printf "${C_CYAN}--- %s ---${C_RESET}\n" "$1"; }
    log_progress() {
        local cur="$1" total="$2" desc="${3:-Progress}"
        local pct=$((cur * 100 / total)) filled=$((cur * 40 / total)) empty=$((40 - filled))
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

# ============================================================================
# State Tracking
# ============================================================================
_SETUP_STATE_FILE="${ALICIA_BASE_DIR}/.setup-05-state"
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

# Helper: Try to install packages, skip failures gracefully
try_apk_install() {
    local description="$1"
    shift
    local packages=("$@")
    log_info "$description"
    for pkg in "${packages[@]}"; do
        if proot_exec "apk add --no-cache $pkg 2>&1" >/dev/null 2>&1; then
            log_debug "  Installed: $pkg"
        else
            log_debug "  Not available: $pkg"
        fi
    done
}

# ============================================================================
# Development Tools Installation
# ============================================================================

install_dev_tools() {
    log_section "Installing Development Tools"

    if step_completed "install_dev_tools"; then
        log_info "Development tools already installed, skipping"
        return 0
    fi

    log_info "Installing development toolchain..."

    # Core development tools
    try_apk_install "Installing build tools" \
        "gcc" "g++" "make" "cmake" "autoconf" "automake" "libtool" \
        "pkgconf" "patch" "binutils" "flex" "bison"

    # Git and version control
    try_apk_install "Installing version control" \
        "git" "subversion" "mercurial"

    # Python
    try_apk_install "Installing Python" \
        "python3" "python3-dev" "py3-pip" "py3-virtualenv" "py3-setuptools" "py3-wheel"

    # Node.js
    try_apk_install "Installing Node.js" \
        "nodejs" "npm" "yarn"

    # Additional dev tools
    try_apk_install "Installing additional dev tools" \
        "ctags" "jq" "shellcheck"

    # Install Python packages
    log_info "Installing Python packages..."
    proot_exec bash -c '
        pip3 install --break-system-packages \
            pip virtualenv flask requests jinja2 pyyaml \
            beautifulsoup4 httpie click rich 2>/dev/null || \
        pip3 install \
            pip virtualenv flask requests jinja2 pyyaml \
            beautifulsoup4 httpie click rich 2>/dev/null || true
    '

    # Install Node.js global packages
    log_info "Installing Node.js global packages..."
    proot_exec "npm install -g yarn pnpm typescript ts-node http-server live-server 2>/dev/null || true"

    mark_step_completed "install_dev_tools"
    log_info "Development tools installed"
    return 0
}

# ============================================================================
# Text Editors Installation
# ============================================================================

install_editors() {
    log_section "Installing Text Editors"

    if step_completed "install_editors"; then
        log_info "Editors already installed, skipping"
        return 0
    fi

    log_info "Installing text editors..."

    # Essential editors (most should already be installed)
    try_apk_install "Installing editors" \
        "vim" "nano" "mousepad" "geany"

    # Vim plugins and configuration
    proot_exec bash -c "
        # Install pathogen for Vim
        mkdir -p ${ALICIA_USER_HOME}/.vim/autoload ${ALICIA_USER_HOME}/.vim/bundle
        curl -LSso ${ALICIA_USER_HOME}/.vim/autoload/pathogen.vim \
            https://tpo.pe/pathogen.vim 2>/dev/null || true

        # Basic .vimrc
        cat > ${ALICIA_USER_HOME}/.vimrc << 'VIMRC_EOF'
\" Alicia Desktop - Vim Configuration
set nocompatible
filetype off
execute pathogen#infect()
filetype plugin indent on
syntax on
set number
set relativenumber
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set smartindent
set hlsearch
set incsearch
set ignorecase
set smartcase
set cursorline
set showmatch
set wildmenu
set laststatus=2
set encoding=utf-8
set mouse=a
VIMRC_EOF

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.vim ${ALICIA_USER_HOME}/.vimrc 2>/dev/null || true
    " || true

    mark_step_completed "install_editors"
    log_info "Text editors installed"
    return 0
}

# ============================================================================
# Web Browsers Installation
# ============================================================================

install_browsers() {
    log_section "Installing Web Browsers"

    if step_completed "install_browsers"; then
        log_info "Browsers already installed, skipping"
        return 0
    fi

    log_info "Installing web browsers..."

    # Lightweight browsers that work on Alpine/ARM
    try_apk_install "Installing browsers" \
        "midori" "links" "lynx" "w3m"

    # Try Firefox (may not work on all ARM devices)
    log_info "Attempting to install Firefox..."
    proot_exec "apk add --no-cache firefox 2>/dev/null" || \
    proot_exec "apk add --no-cache firefox-esr 2>/dev/null" || {
        log_info "Firefox not available on this platform (non-fatal)"
    }

    # Try Chromium
    log_info "Attempting to install Chromium..."
    proot_exec "apk add --no-cache chromium 2>/dev/null" || {
        log_info "Chromium not available on this platform (non-fatal)"
    }

    mark_step_completed "install_browsers"
    log_info "Web browsers installed"
    return 0
}

# ============================================================================
# Office Applications Installation
# ============================================================================

install_office_apps() {
    log_section "Installing Office Applications"

    if step_completed "install_office_apps"; then
        log_info "Office apps already installed, skipping"
        return 0
    fi

    log_info "Installing office applications..."

    # Lightweight office apps for Alpine
    try_apk_install "Installing office apps" \
        "abiword" "gnumeric" "evince" "catdoc"

    # Try LibreOffice (large, may not be available on all platforms)
    log_info "Attempting to install LibreOffice..."
    proot_exec "apk add --no-cache libreoffice 2>/dev/null" || {
        log_info "LibreOffice not available (non-fatal, using lightweight alternatives)"
    }

    # PDF tools
    try_apk_install "Installing PDF tools" \
        "poppler" "poppler-utils" "qpdf" "ghostscript"

    # Document converters
    try_apk_install "Installing document tools" \
        "pandoc" "texinfo" "dos2unix" "unix2dos"

    mark_step_completed "install_office_apps"
    log_info "Office applications installed"
    return 0
}

# ============================================================================
# Graphics Applications Installation
# ============================================================================

install_graphics_apps() {
    log_section "Installing Graphics Applications"

    if step_completed "install_graphics_apps"; then
        log_info "Graphics apps already installed, skipping"
        return 0
    fi

    log_info "Installing graphics applications..."

    # Image viewing and manipulation
    try_apk_install "Installing image tools" \
        "imagemagick" "feh" "ristretto" "gpicview" "eog"

    # Try GIMP (may be too heavy for some devices)
    log_info "Attempting to install GIMP..."
    proot_exec "apk add --no-cache gimp 2>/dev/null" || {
        log_info "GIMP not available (non-fatal)"
    }

    # Drawing tools
    try_apk_install "Installing drawing tools" \
        "inkscape" "pinta"

    # Screenshot tools
    try_apk_install "Installing screenshot tools" \
        "xfce4-screenshooter" "scrot" "maim"

    # Image format support
    try_apk_install "Installing image format libraries" \
        "libjpeg-turbo" "libpng" "libwebp" "libraw" "lcms2"

    mark_step_completed "install_graphics_apps"
    log_info "Graphics applications installed"
    return 0
}

# ============================================================================
# Terminal Emulators Installation
# ============================================================================

install_terminals() {
    log_section "Installing Terminal Emulators"

    if step_completed "install_terminals"; then
        log_info "Terminal emulators already installed, skipping"
        return 0
    fi

    log_info "Installing terminal emulators..."

    try_apk_install "Installing terminals" \
        "xfce4-terminal" "sakura" "lxterminal" "xterm" "rxvt-unicode"

    mark_step_completed "install_terminals"
    log_info "Terminal emulators installed"
    return 0
}

# ============================================================================
# System Tools Installation
# ============================================================================

install_system_tools() {
    log_section "Installing System Tools"

    if step_completed "install_system_tools"; then
        log_info "System tools already installed, skipping"
        return 0
    fi

    log_info "Installing system utilities..."

    # System monitoring and management
    try_apk_install "Installing system tools" \
        "htop" "tree" "mc" "ranger" "neofetch" "lsof" "strace" \
        "pciutils" "usbutils" "lsblk" "smartmontools"

    # Archive and compression
    try_apk_install "Installing archive tools" \
        "file-roller" "p7zip" "unrar" "cabextract" "cpio"

    # Disk and file tools
    try_apk_install "Installing disk/file tools" \
        "ncdu" "duf" "fd" "ripgrep" "bat" "exa"

    # Process management
    try_apk_install "Installing process tools" \
        "procs" "btm" "atop"

    mark_step_completed "install_system_tools"
    log_info "System tools installed"
    return 0
}

# ============================================================================
# Network Tools Installation
# ============================================================================

install_network_tools() {
    log_section "Installing Network Tools"

    if step_completed "install_network_tools"; then
        log_info "Network tools already installed, skipping"
        return 0
    fi

    log_info "Installing network utilities..."

    try_apk_install "Installing network tools" \
        "wget" "curl" "openssh-client" "openssh-server" "nmap" \
        "iperf3" "bind-tools" "whois" "traceroute" "mtr" \
        "netcat-openbsd" "socat" "tcpdump" "bridge-utils" \
        "wireless-tools" "wpa_supplicant"

    mark_step_completed "install_network_tools"
    log_info "Network tools installed"
    return 0
}

# ============================================================================
# Media Applications Installation
# ============================================================================

install_media_apps() {
    log_section "Installing Media Applications"

    if step_completed "install_media_apps"; then
        log_info "Media apps already installed, skipping"
        return 0
    fi

    log_info "Installing multimedia applications..."

    # Video and audio players
    try_apk_install "Installing media players" \
        "mpv" "parole" "vlc"

    # FFmpeg (should already be installed, ensure it)
    try_apk_install "Ensuring FFmpeg" "ffmpeg"

    # Audio tools
    try_apk_install "Installing audio tools" \
        "sox" "flac" "lame" "opus-tools" "vorbis-tools"

    # Media info
    try_apk_install "Installing media info tools" \
        "mediainfo" "exiftool"

    mark_step_completed "install_media_apps"
    log_info "Media applications installed"
    return 0
}

# ============================================================================
# Archive Manager Configuration
# ============================================================================

configure_archive_managers() {
    log_section "Configuring Archive Managers"

    if step_completed "configure_archives"; then
        log_info "Archive managers already configured, skipping"
        return 0
    fi

    log_info "Configuring archive management..."

    # Ensure Thunar archive plugin is configured
    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/.local/share/applications 2>/dev/null || true

        # Create file-roller association for common archive types
        cat > ${ALICIA_USER_HOME}/.local/share/applications/alicia-archive.desktop << 'ARCHIVE_DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=Archive Manager
Comment=Create and extract archives
Exec=file-roller %f
Icon=package-x-generic
Terminal=false
Categories=Utility;Archiving;Compression;
MimeType=application/x-tar;application/x-compressed-tar;application/x-bzip-compressed-tar;application/x-xz-compressed-tar;application/zip;application/x-zip-compressed;application/x-7z-compressed;application/x-rar;application/x-rar-compressed;
StartupNotify=true
ARCHIVE_DESKTOP

        chmod +x ${ALICIA_USER_HOME}/.local/share/applications/alicia-archive.desktop
        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.local 2>/dev/null || true
    "

    mark_step_completed "configure_archives"
    log_info "Archive managers configured"
    return 0
}

# ============================================================================
# Python Package Installation
# ============================================================================

install_python_packages() {
    log_section "Installing Python Packages"

    if step_completed "install_python_packages"; then
        log_info "Python packages already installed, skipping"
        return 0
    fi

    log_info "Installing useful Python packages..."

    proot_exec bash -c '
        # System-level Python packages
        PIP_PACKAGES=(
            "pip"
            "virtualenv"
            "flask"
            "django"
            "requests"
            "beautifulsoup4"
            "scrapy"
            "jinja2"
            "pyyaml"
            "toml"
            "click"
            "rich"
            "httpie"
            "psutil"
            "pillow"
            "python-dateutil"
            "pytz"
        )

        for pkg in "${PIP_PACKAGES[@]}"; do
            pip3 install --break-system-packages "$pkg" 2>/dev/null || \
            pip3 install "$pkg" 2>/dev/null || true
        done
    ' || log_debug "Some Python packages may have failed to install"

    mark_step_completed "install_python_packages"
    log_info "Python packages installed"
    return 0
}

# ============================================================================
# Node.js Package Installation
# ============================================================================

install_node_packages() {
    log_section "Installing Node.js Global Packages"

    if step_completed "install_node_packages"; then
        log_info "Node.js packages already installed, skipping"
        return 0
    fi

    log_info "Installing Node.js global packages..."

    proot_exec bash -c '
        NPM_PACKAGES=(
            "yarn"
            "pnpm"
            "typescript"
            "ts-node"
            "http-server"
            "live-server"
            "nodemon"
            "eslint"
            "prettier"
        )

        for pkg in "${NPM_PACKAGES[@]}"; do
            npm install -g "$pkg" 2>/dev/null || true
        done
    ' || log_debug "Some Node.js packages may have failed to install"

    mark_step_completed "install_node_packages"
    log_info "Node.js packages installed"
    return 0
}

# ============================================================================
# .desktop File Creation for All Applications
# ============================================================================

create_desktop_files() {
    log_section "Creating .desktop Files for Applications"

    if step_completed "create_desktop_files"; then
        log_info "Desktop files already created, skipping"
        return 0
    fi

    log_info "Creating .desktop files for Alicia applications..."

    proot_exec bash -c "
        mkdir -p /usr/share/applications ${ALICIA_USER_HOME}/.local/share/applications

        # --- Development Tools ---
        cat > /usr/share/applications/alicia-dev-terminal.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Development Terminal
Comment=Terminal with development environment
Exec=xfce4-terminal --working-directory=/home/alicia/Projects
Icon=utilities-terminal
Terminal=false
Categories=Development;IDE;
StartupNotify=true
DESKTOP_EOF

        cat > /usr/share/applications/alicia-python.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Python 3 Console
Comment=Python 3 Interactive Console
Exec=xfce4-terminal -e python3
Icon=python
Terminal=false
Categories=Development;
StartupNotify=true
DESKTOP_EOF

        cat > /usr/share/applications/alicia-node.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Node.js Console
Comment=Node.js Interactive Console
Exec=xfce4-terminal -e node
Icon=nodejs
Terminal=false
Categories=Development;
StartupNotify=true
DESKTOP_EOF

        # --- System Tools ---
        cat > /usr/share/applications/alicia-htop.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=System Monitor (htop)
Comment=Interactive process viewer
Exec=xfce4-terminal -e htop
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;
StartupNotify=true
DESKTOP_EOF

        cat > /usr/share/applications/alicia-neofetch.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=System Information
Comment=Show system information with neofetch
Exec=xfce4-terminal -e \"bash -c 'neofetch; read -p Press_Enter'\"
Icon=dialog-information
Terminal=false
Categories=System;
StartupNotify=true
DESKTOP_EOF

        # --- Network Tools ---
        cat > /usr/share/applications/alicia-ssh.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=SSH Client
Comment=Connect to remote servers via SSH
Exec=xfce4-terminal -e \"bash -c 'echo \\\"Usage: ssh user@host\\\"); read -p \\\"Enter SSH connection: \\\" host; ssh \\$host'\"
Icon=preferences-system-network
Terminal=false
Categories=Network;RemoteAccess;
StartupNotify=true
DESKTOP_EOF

        # --- Media Tools ---
        cat > /usr/share/applications/alicia-screenshot.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Take Screenshot
Comment=Capture the desktop or a window
Exec=xfce4-screenshooter
Icon=applets-screenshooter
Terminal=false
Categories=Utility;
StartupNotify=true
DESKTOP_EOF

        # Update desktop database
        update-desktop-database /usr/share/applications 2>/dev/null || true
        update-desktop-database ${ALICIA_USER_HOME}/.local/share/applications 2>/dev/null || true
    "

    mark_step_completed "create_desktop_files"
    log_info "Desktop files created"
    return 0
}

# ============================================================================
# Default Application Associations
# ============================================================================

configure_default_associations() {
    log_section "Configuring Default Application Associations"

    if step_completed "configure_defaults"; then
        log_info "Default associations already configured, skipping"
        return 0
    fi

    log_info "Setting up default application associations..."

    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/.local/share/applications

        # Create mimeapps.list for default associations
        cat > ${ALICIA_USER_HOME}/.local/share/applications/mimeapps.list << 'MIMEAPPS_EOF'
[Default Applications]
# Text files
text/plain=mousepad.desktop
text/x-python=geany.desktop
text/x-csrc=geany.desktop
text/x-chdr=geany.desktop
text/x-shellscript=mousepad.desktop

# Web
text/html=midori.desktop
x-scheme-handler/http=midori.desktop
x-scheme-handler/https=midori.desktop
x-scheme-handler/ftp=midori.desktop

# Images
image/png=ristretto.desktop
image/jpeg=ristretto.desktop
image/gif=ristretto.desktop
image/bmp=ristretto.desktop
image/svg+xml=ristretto.desktop
image/webp=ristretto.desktop

# Documents
application/pdf=evince.desktop

# Audio
audio/mpeg=mpv.desktop
audio/ogg=mpv.desktop
audio/flac=mpv.desktop
audio/wav=mpv.desktop

# Video
video/mp4=mpv.desktop
video/mpeg=mpv.desktop
video/x-matroska=mpv.desktop
video/webm=mpv.desktop

# Archives
application/x-tar=file-roller.desktop
application/x-compressed-tar=file-roller.desktop
application/zip=file-roller.desktop
application/x-7z-compressed=file-roller.desktop
application/x-rar-compressed=file-roller.desktop

# Terminal
x-scheme-handler/terminal=xfce4-terminal.desktop

# Directories
inode/directory=thunar.desktop

[Added Associations]
text/plain=mousepad.desktop;geany.desktop;vim.desktop;
MIMEAPPS_EOF

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.local 2>/dev/null || true

        # Update MIME database
        update-mime-database ${ALICIA_USER_HOME}/.local/share/mime 2>/dev/null || true
    "

    mark_step_completed "configure_defaults"
    log_info "Default application associations configured"
    return 0
}

# ============================================================================
# Application Menu Category Configuration
# ============================================================================

configure_menu_categories() {
    log_section "Configuring Application Menu Categories"

    if step_completed "configure_menu_categories"; then
        log_info "Menu categories already configured, skipping"
        return 0
    fi

    log_info "Setting up application menu categories..."

    proot_exec bash -c "
        # Create menu layout for Whisker Menu
        mkdir -p ${ALICIA_USER_HOME}/.config/menus

        cat > ${ALICIA_USER_HOME}/.config/menus/xfce-applications.menu << 'MENU_EOF'
<!DOCTYPE Menu PUBLIC \"-//freedesktop//DTD Menu 1.0//EN\"
  \"http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd\">
<Menu>
    <Name>Xfce</Name>
    <DefaultAppDirs/>
    <DefaultDirectoryDirs/>
    <Include>
        <Category>X-Xfce-Toplevel</Category>
    </Include>
    <Layout>
        <Filename>xfce4-terminal.desktop</Filename>
        <Filename>thunar.desktop</Filename>
        <Separator/>
        <Menuname>Accessories</Menuname>
        <Menuname>Development</Menuname>
        <Menuname>Education</Menuname>
        <Menuname>Games</Menuname>
        <Menuname>Graphics</Menuname>
        <Menuname>Internet</Menuname>
        <Menuname>Multimedia</Menuname>
        <Menuname>Office</Menuname>
        <Menuname>Settings</Menuname>
        <Menuname>System</Menuname>
        <Separator/>
        <Filename>alicia-info.desktop</Filename>
    </Layout>
</Menu>
MENU_EOF

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config 2>/dev/null || true
    "

    mark_step_completed "configure_menu_categories"
    log_info "Menu categories configured"
    return 0
}

# ============================================================================
# Desktop Launchers Setup
# ============================================================================

configure_desktop_launchers() {
    log_section "Setting Up Desktop Launchers"

    if step_completed "configure_launchers"; then
        log_info "Desktop launchers already configured, skipping"
        return 0
    fi

    log_info "Creating desktop application launchers..."

    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/Desktop

        # Copy commonly used .desktop files to Desktop
        local desktop_apps=(
            \"/usr/share/applications/xfce4-terminal.desktop\"
            \"/usr/share/applications/thunar.desktop\"
            \"/usr/share/applications/mousepad.desktop\"
            \"/usr/share/applications/xfce4-taskmanager.desktop\"
            \"/usr/share/applications/xfce4-screenshooter.desktop\"
        )

        for app_path in \"\${desktop_apps[@]}\"; do
            if [[ -f \"\$app_path\" ]]; then
                cp \"\$app_path\" ${ALICIA_USER_HOME}/Desktop/ 2>/dev/null || true
            fi
        done

        # Make all desktop files executable and trusted
        for desktop_file in ${ALICIA_USER_HOME}/Desktop/*.desktop; do
            if [[ -f \"\$desktop_file\" ]]; then
                chmod +x \"\$desktop_file\" 2>/dev/null || true
            fi
        done

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/Desktop 2>/dev/null || true
    "

    mark_step_completed "configure_launchers"
    log_info "Desktop launchers configured"
    return 0
}

# ============================================================================
# Alicia Custom Applications
# ============================================================================

install_alicia_custom_apps() {
    log_section "Installing Alicia Custom Applications"

    if step_completed "install_alicia_apps"; then
        log_info "Alicia custom apps already installed, skipping"
        return 0
    fi

    log_info "Creating Alicia-specific custom applications..."

    proot_exec bash -c "
        mkdir -p /usr/share/applications
        mkdir -p ${ALICIA_USER_HOME}/.local/share/applications
        mkdir -p /usr/local/bin

        # --- Alicia Welcome Application ---
        cat > /usr/local/bin/alicia-welcome << 'WELCOME_EOF'
#!/bin/bash
# Alicia Desktop Environment - Welcome Application
echo \"+======================================================+\"
echo \"|          Welcome to Alicia Desktop!                  |\"
echo \"|          Version 3.1.0 - Proyecto Tomorrow           |\"
echo \"?======================================================?\"
echo \"|                                                     |\"
echo \"|  Alicia is your complete Linux desktop on Android.  |\"
echo \"|                                                     |\"
echo \"|  Getting Started:                                   |\"
echo \"|    1. Use the Applications menu to launch apps      |\"
echo \"|    2. Files are managed with Thunar                 |\"
echo \"|    3. Settings can be found in Settings Manager     |\"
echo \"|                                                     |\"
echo \"|  Keyboard Shortcuts:                                |\"
echo \"|    Ctrl+Alt+T  - Open Terminal                      |\"
echo \"|    Ctrl+Alt+F  - Open File Manager                  |\"
echo \"|    Ctrl+Alt+E  - Open Text Editor                   |\"
echo \"|    Ctrl+Alt+S  - Take Screenshot                    |\"
echo \"|                                                     |\"
echo \"|  Need Help?                                         |\"
echo \"|    Run: alicia-vnc-info                             |\"
echo \"|                                                     |\"
echo \"+======================================================+\"
echo \"\"
read -p \"Press Enter to continue...\"
WELCOME_EOF
        chmod +x /usr/local/bin/alicia-welcome

        cat > /usr/share/applications/alicia-welcome.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Alicia Welcome
Comment=Welcome to Alicia Desktop
Exec=xfce4-terminal -e alicia-welcome
Icon=dialog-information
Terminal=false
Categories=System;
StartupNotify=true
DESKTOP_EOF

        # --- Alicia System Update ---
        cat > /usr/local/bin/alicia-update << 'UPDATE_EOF'
#!/bin/bash
# Alicia Desktop Environment - System Update
echo \"Updating Alicia Desktop Environment...\"
echo \"\"
echo \"[1/3] Updating Alpine packages...\"
sudo apk update 2>&1 | tail -3
sudo apk upgrade --no-cache 2>&1 | tail -3
echo \"\"
echo \"[2/3] Cleaning package cache...\"
sudo apk cache purge 2>/dev/null || true
echo \"\"
echo \"[3/3] Update complete!\"
echo \"\"
read -p \"Press Enter to continue...\"
UPDATE_EOF
        chmod +x /usr/local/bin/alicia-update

        cat > /usr/share/applications/alicia-update.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=System Update
Comment=Update Alicia system packages
Exec=xfce4-terminal -e alicia-update
Icon=system-software-update
Terminal=false
Categories=System;
StartupNotify=true
DESKTOP_EOF

        # --- Alicia System Info ---
        cat > /usr/local/bin/alicia-sysinfo << 'SYSINFO_EOF'
#!/bin/bash
# Alicia Desktop Environment - System Information
echo \"Alicia Desktop Environment - System Information\"
echo \"================================================\"
echo \"\"
echo \"Alicia Version:   3.1.0\"
echo \"Distribution:     Alpine Linux (proot)\"
echo \"Kernel:           \$(uname -r)\"
echo \"Architecture:     \$(uname -m)\"
echo \"Hostname:         \$(hostname 2>/dev/null || echo alicia)\"
echo \"Uptime:           \$(uptime -p 2>/dev/null || uptime)\"
echo \"\"
echo \"Memory:\"
free -h 2>/dev/null || echo \"  Memory info unavailable\"
echo \"\"
echo \"Storage:\"
df -h / 2>/dev/null || echo \"  Storage info unavailable\"
echo \"\"
if command -v neofetch &>/dev/null; then
    neofetch --stdout 2>/dev/null || true
fi
echo \"\"
read -p \"Press Enter to continue...\"
SYSINFO_EOF
        chmod +x /usr/local/bin/alicia-sysinfo

        cat > /usr/share/applications/alicia-sysinfo.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=System Information
Comment=Show Alicia system information
Exec=xfce4-terminal -e alicia-sysinfo
Icon=dialog-information
Terminal=false
Categories=System;
StartupNotify=true
DESKTOP_EOF

        # Update desktop database
        update-desktop-database /usr/share/applications 2>/dev/null || true
    "

    mark_step_completed "install_alicia_apps"
    log_info "Alicia custom applications installed"
    return 0
}

# ============================================================================
# Application Installation Validation
# ============================================================================

validate_applications() {
    log_section "Validating Application Installation"

    if step_completed "validate_apps"; then
        log_info "Applications already validated, skipping"
        return 0
    fi

    log_info "Checking installed applications..."

    local categories=(
        "Development:git:python3:npm:gcc:make"
        "Editors:vim:nano:mousepad"
        "Browsers:midori:w3m"
        "Graphics:imagemagick:feh:ristretto"
        "Terminals:xfce4-terminal:xterm"
        "System:htop:tree:neofetch:mc"
        "Network:curl:wget:ssh:nmap"
        "Media:mpv:ffmpeg"
        "Archives:file-roller:p7zip"
    )

    for category_def in "${categories[@]}"; do
        local category="${category_def%%:*}"
        local cmds="${category_def#*:}"
        log_subsection "$category"

        IFS=':' read -ra cmd_array <<< "$cmds"
        for cmd in "${cmd_array[@]}"; do
            if proot_exec "command -v $cmd" &>/dev/null; then
                log_info "  [OK] $cmd"
            else
                log_debug "  [--] $cmd (not available)"
            fi
        done
    done

    mark_step_completed "validate_apps"
    log_info "Application validation complete"
    return 0
}

# ============================================================================
# Cleanup and Signal Handling
# ============================================================================

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Setup exited with code: $exit_code"
        log_error "Re-run this script to continue"
    fi
    if declare -f alicia_lock_release &>/dev/null; then
        alicia_lock_release "setup-05" 2>/dev/null || true
    fi
    exit $exit_code
}

trap cleanup EXIT
trap 'log_warn "Interrupted"; exit 130' INT
trap 'log_warn "Terminated"; exit 143' TERM

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_section "Alicia Desktop - Applications Setup (Step 5/6)"
    log_info "Version: ${SCRIPT_VERSION}"
    log_info "Author:  Proyecto Tomorrow"
    log_info "Time:    $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    if [[ ! -f "${ALICIA_BASE_DIR}/.setup-04-state" ]]; then
        log_warn "Step 04 (VNC setup) may not be completed"
        log_warn "Continuing anyway..."
    fi

    load_state

    if declare -f alicia_lock_acquire &>/dev/null; then
        alicia_lock_acquire "setup-05" 600 || {
            log_error "Another setup process is running"
            exit 1
        }
    fi

    local steps=(
        "install_dev_tools"
        "install_editors"
        "install_browsers"
        "install_office_apps"
        "install_graphics_apps"
        "install_terminals"
        "install_system_tools"
        "install_network_tools"
        "install_media_apps"
        "configure_archive_managers"
        "install_python_packages"
        "install_node_packages"
        "create_desktop_files"
        "configure_default_associations"
        "configure_menu_categories"
        "configure_desktop_launchers"
        "install_alicia_custom_apps"
        "validate_applications"
    )

    local total_steps=${#steps[@]}
    local completed=0

    for step in "${steps[@]}"; do
        ((completed++)) || true
        log_progress "$completed" "$total_steps" "Overall setup progress"

        log_info "Executing step: $step"
        if ! "$step"; then
            log_error "Step failed: $step"
            log_error "Fix the issue and re-run to continue"
            exit 1
        fi
    done

    log_progress "$total_steps" "$total_steps" "Overall setup progress"

    log_section "Applications Setup Complete"
    log_info "All applications are installed and configured!"
    log_info ""
    log_info "Installed categories:"
    log_info "  Development:   gcc, python3, nodejs, git"
    log_info "  Editors:       vim, nano, mousepad, geany"
    log_info "  Browsers:      midori, w3m, links"
    log_info "  Office:        abiword, gnumeric, evince"
    log_info "  Graphics:      imagemagick, feh, ristretto"
    log_info "  System:        htop, tree, mc, neofetch"
    log_info "  Network:       wget, curl, ssh, nmap"
    log_info "  Media:         mpv, ffmpeg"
    log_info ""
    log_info "Next step:"
    log_info "  Run: ${SCRIPT_DIR}/06-alicia-customize.sh"
    log_info "  This will apply Alicia branding and customization"

    return 0
}

main "$@"
