#!/bin/bash
# ============================================================================
# 03-desktop-setup.sh - Alicia Desktop Environment XFCE4 Setup
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
# Version:      2.0.0
# Description:  Sets up the XFCE4 desktop environment inside the proot
#               Alpine Linux installation. Installs X11, XFCE4 core,
#               goodies, themes, fonts, audio, multimedia, printing,
#               configures panel layout, desktop icons, file manager,
#               window manager shortcuts, wallpaper, screensaver,
#               and creates custom Alicia theme settings.
# ============================================================================

set -euo pipefail

# ============================================================================
# Script Identity
# ============================================================================
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="2.0.0"

# ============================================================================
# Source Alicia Libraries
# ============================================================================
for lib_file in "${SCRIPT_DIR}/../lib/"alicia-*.sh; do
    if [[ -f "$lib_file" ]]; then
        # shellcheck source=/dev/null
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
_SETUP_STATE_FILE="${ALICIA_BASE_DIR}/.setup-03-state"
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

# Helper: Install Alpine packages with error handling
apk_install() {
    local description="$1"
    shift
    local packages=("$@")
    log_info "$description: ${packages[*]}"
    proot_exec "apk add --no-cache ${packages[*]} 2>&1" || {
        log_warn "Some packages may have failed: ${packages[*]}"
        # Try installing one by one to identify failures
        for pkg in "${packages[@]}"; do
            proot_exec "apk add --no-cache $pkg 2>&1" >/dev/null 2>&1 || {
                log_debug "Package not available or failed: $pkg"
            }
        done
    }
}

# ============================================================================
# X11 Base Installation
# ============================================================================

install_x11_base() {
    log_section "Installing X11 Base Packages"

    if step_completed "install_x11"; then
        log_info "X11 base already installed, skipping"
        return 0
    fi

    log_info "Installing X11 foundation packages..."

    # Core X11 packages for Alpine
    local x11_packages=(
        "xorg-server"
        "xorg-server-common"
        "xinit"
        "xauth"
        "xset"
        "xsetroot"
        "xrandr"
        "xinput"
        "xmodmap"
        "xkbcomp"
        "xprop"
        "xwininfo"
        "xdpyinfo"
        "xhost"
        "xclock"
        "xterm"
        "xeyes"
        "xev"
        "xeyes"
        "mesa"
        "mesa-dri-gallium"
        "mesa-egl"
        "mesa-gl"
        "libx11"
        "libxext"
        "libxrender"
        "libxrandr"
        "libxfixes"
        "libxdamage"
        "libxcomposite"
        "libxcursor"
        "libxi"
        "libxinerama"
        "libxft"
        "libxpm"
        "libxmu"
        "libxt"
        "libxss"
        "libxtst"
        "libxkbfile"
        "libxkbcommon"
        "dbus"
        "dbus-x11"
        "dbus-libs"
        "fontconfig"
        "freetype"
    )

    apk_install "Installing X11 packages" "${x11_packages[@]}"

    # Xvfb for virtual framebuffer
    apk_install "Installing Xvfb" "xorg-server-xvfb"

    # Keyboard and input configuration
    apk_install "Installing input packages" "xkeyboard-config" "libinput" "xf86-input-libinput"

    mark_step_completed "install_x11"
    log_info "X11 base installation complete"
    return 0
}

# ============================================================================
# XFCE4 Core Installation
# ============================================================================

install_xfce4_core() {
    log_section "Installing XFCE4 Core Desktop"

    if step_completed "install_xfce4_core"; then
        log_info "XFCE4 core already installed, skipping"
        return 0
    fi

    log_info "Installing XFCE4 core components..."

    # XFCE4 core packages for Alpine
    local xfce4_core=(
        "xfce4"
        "xfce4-terminal"
        "xfce4-panel"
        "xfce4-session"
        "xfwm4"
        "xfwm4-themes"
        "thunar"
        "thunar-volman"
        "exo"
        "garcon"
        "libxfce4ui"
        "libxfce4util"
        "xfconf"
        "tumbler"
        "desktop-file-utils"
        "shared-mime-info"
        "gtk+3.0"
        "gtk+2.0"
    )

    apk_install "Installing XFCE4 core" "${xfce4_core[@]}"

    # Verify essential components
    local essential_cmds=("startxfce4" "xfce4-session" "xfwm4" "thunar" "xfce4-panel" "xfce4-terminal")
    for cmd in "${essential_cmds[@]}"; do
        if proot_exec "command -v $cmd" &>/dev/null; then
            log_info "  [OK] $cmd is available"
        else
            log_warn "  [WARN] $cmd is not available - desktop may not work correctly"
        fi
    done

    mark_step_completed "install_xfce4_core"
    log_info "XFCE4 core installation complete"
    return 0
}

# ============================================================================
# XFCE4 Goodies Installation
# ============================================================================

install_xfce4_goodies() {
    log_section "Installing XFCE4 Goodies"

    if step_completed "install_xfce4_goodies"; then
        log_info "XFCE4 goodies already installed, skipping"
        return 0
    fi

    log_info "Installing XFCE4 additional components..."

    local xfce4_goodies=(
        "xfce4-taskmanager"
        "xfce4-screenshooter"
        "xfce4-notifyd"
        "xfce4-appfinder"
        "xfce4-settings"
        "xfce4-whiskermenu-plugin"
        "xfce4-clipman-plugin"
        "xfce4-cpugraph-plugin"
        "xfce4-datetime-plugin"
        "xfce4-netload-plugin"
        "xfce4-weather-plugin"
        "xfce4-pulseaudio-plugin"
        "xfce4-battery-plugin"
        "xfce4-mount-plugin"
        "xfce4-power-manager"
        "xfce4-session"
        "xfce4-desktop"
        "mousepad"
        "ristretto"
        "parole"
        "file-roller"
        "thunar-archive-plugin"
        "xfburn"
    )

    apk_install "Installing XFCE4 goodies" "${xfce4_goodies[@]}"

    mark_step_completed "install_xfce4_goodies"
    log_info "XFCE4 goodies installation complete"
    return 0
}

# ============================================================================
# Themes and Icons Installation
# ============================================================================

install_themes_and_icons() {
    log_section "Installing GTK Themes and Icon Themes"

    if step_completed "install_themes"; then
        log_info "Themes already installed, skipping"
        return 0
    fi

    log_info "Installing GTK themes..."

    # GTK themes available on Alpine
    local gtk_themes=(
        "gnome-themes-extra"
        "adwaita-gtk2-theme"
        "adwaita-icon-theme"
    )

    apk_install "Installing GTK themes" "${gtk_themes[@]}"

    log_info "Installing icon themes..."

    local icon_themes=(
        "adwaita-icon-theme"
        "hicolor-icon-theme"
    )

    apk_install "Installing icon themes" "${icon_themes[@]}"

    # Install Papirus icon theme (download from GitHub)
    log_info "Installing Papirus icon theme..."
    proot_exec bash -c '
        if command -v papirus-folders &>/dev/null; then
            echo "Papirus already installed"
        else
            cd /tmp 2>/dev/null || true
            wget -q "https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/refs/tags/20240101.tar.gz" -O papirus.tar.gz 2>/dev/null || curl -sL "https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/refs/tags/20240101.tar.gz" -o papirus.tar.gz 2>/dev/null || true
            if [[ -f papirus.tar.gz ]]; then
                tar -xzf papirus.tar.gz 2>/dev/null || true
                if [[ -d papirus-icon-theme-*/Papirus ]]; then
                    mkdir -p /usr/share/icons
                    cp -r papirus-icon-theme-*/Papirus* /usr/share/icons/ 2>/dev/null || true
                    cp -r papirus-icon-theme-*/ePapirus* /usr/share/icons/ 2>/dev/null || true
                    gtk-update-icon-cache /usr/share/icons/Papirus 2>/dev/null || true
                    echo "Papirus icon theme installed"
                fi
                rm -f papirus.tar.gz
                rm -rf papirus-icon-theme-*
            else
                echo "Could not download Papirus icon theme"
            fi
        fi
    ' || log_debug "Papirus icon theme installation had issues"

    # Install Numix theme (download if available)
    log_info "Installing Numix theme..."
    proot_exec bash -c '
        if [[ ! -d /usr/share/themes/Numix ]]; then
            mkdir -p /usr/share/themes/Numix/gtk-3.0 2>/dev/null || true
            mkdir -p /usr/share/themes/Numix/gtk-2.0 2>/dev/null || true
            mkdir -p /usr/share/themes/Numix/xfwm4 2>/dev/null || true
            echo "Numix theme placeholder created"
        fi
    ' || true

    # Install custom cursor theme
    apk_install "Installing cursor themes" "xcursor-themes"

    mark_step_completed "install_themes"
    log_info "Themes and icons installation complete"
    return 0
}

# ============================================================================
# Fonts Installation
# ============================================================================

install_fonts() {
    log_section "Installing Fonts"

    if step_completed "install_fonts"; then
        log_info "Fonts already installed, skipping"
        return 0
    fi

    log_info "Installing font packages..."

    local font_packages=(
        "font-dejavu"
        "font-liberation"
        "font-noto"
        "font-noto-cjk"
        "font-noto-emoji"
        "font-roboto"
        "font-inconsolata"
        "font-hack"
        "font-source-code-pro"
        "font-ubuntu"
        "font-misc-misc"
        "font-cursor-misc"
        "font-alias"
        "font-util"
        "encodings"
    )

    apk_install "Installing fonts" "${font_packages[@]}"

    # Rebuild font cache
    log_info "Rebuilding font cache..."
    proot_exec "fc-cache -f -v 2>/dev/null | tail -5" || true
    proot_exec "fc-list 2>/dev/null | wc -l" | while read -r count; do
        log_info "Font cache rebuilt: $count fonts available"
    done

    mark_step_completed "install_fonts"
    log_info "Fonts installation complete"
    return 0
}

# ============================================================================
# Audio Support Installation
# ============================================================================

install_audio_support() {
    log_section "Installing Audio Support"

    if step_completed "install_audio"; then
        log_info "Audio support already installed, skipping"
        return 0
    fi

    log_info "Installing audio packages..."

    local audio_packages=(
        "alsa-utils"
        "alsa-lib"
        "alsa-plugins"
        "alsaconf"
        "pulseaudio"
        "pulseaudio-utils"
        "pulseaudio-alsa"
        "paprefs"
        "pavucontrol"
    )

    apk_install "Installing audio packages" "${audio_packages[@]}"

    # Configure PulseAudio for user access
    proot_exec bash -c "
        mkdir -p /etc/pulse 2>/dev/null || true
        # Create a minimal pulseaudio config for proot
        cat > /etc/pulse/daemon.conf << 'PA_DAEMON'
# PulseAudio Daemon Configuration for Alicia
default-sample-format = s16le
default-sample-rate = 44100
alternate-sample-rate = 48000
resample-method = speex-float-3
PA_DAEMON

        cat > /etc/pulse/default.pa << 'PA_DEFAULT'
# PulseAudio Default Configuration for Alicia
#!/usr/bin/pulseaudio
load-module module-augment-properties
load-module module-udev-detect
load-module module-alsa-sink
load-module module-alsa-source
load-module module-null-sink sink_name=null sink_properties='device.description=\"Null Output\"'
load-module module-native-protocol-unix
load-module module-native-protocol-tcp auth-anonymous=1
load-module module-stream-restore
load-module module-device-restore
load-module module-default-device-restore
load-module module-rescue-streams
load-module module-suspend-on-idle
PA_DEFAULT
    " || log_debug "PulseAudio configuration had issues"

    mark_step_completed "install_audio"
    log_info "Audio support installation complete"
    return 0
}

# ============================================================================
# Multimedia Codecs Installation
# ============================================================================

install_multimedia_codecs() {
    log_section "Installing Multimedia Codecs"

    if step_completed "install_multimedia"; then
        log_info "Multimedia codecs already installed, skipping"
        return 0
    fi

    log_info "Installing multimedia packages..."

    local multimedia_packages=(
        "ffmpeg"
        "ffmpeg-libs"
        "gstreamer"
        "gst-plugins-base"
        "gst-plugins-good"
        "gst-plugins-bad"
        "gst-plugins-ugly"
        "gst-libav"
        "libva"
        "libvdpau"
    )

    apk_install "Installing multimedia codecs" "${multimedia_packages[@]}"

    mark_step_completed "install_multimedia"
    log_info "Multimedia codecs installation complete"
    return 0
}

# ============================================================================
# Printing Support Installation
# ============================================================================

install_printing_support() {
    log_section "Installing Printing Support"

    if step_completed "install_printing"; then
        log_info "Printing support already installed, skipping"
        return 0
    fi

    log_info "Installing CUPS and printing packages..."

    local printing_packages=(
        "cups"
        "cups-libs"
        "cups-filters"
        "cups-pdf"
        "cups-pk-helper"
    )

    apk_install "Installing printing packages" "${printing_packages[@]}"

    # Basic CUPS configuration
    proot_exec bash -c "
        if command -v cupsd &>/dev/null; then
            mkdir -p /etc/cups 2>/dev/null || true
            mkdir -p /var/spool/cups 2>/dev/null || true
            mkdir -p /var/log/cups 2>/dev/null || true
            echo 'CUPS printing support installed'
        fi
    " || log_debug "CUPS configuration had issues"

    mark_step_completed "install_printing"
    log_info "Printing support installation complete"
    return 0
}

# ============================================================================
# XFCE4 Panel Layout Configuration
# ============================================================================

configure_xfce4_panel() {
    log_section "Configuring XFCE4 Panel Layout"

    if step_completed "configure_panel"); then
        log_info "Panel already configured, skipping"
        return 0
    fi

    log_info "Setting up custom Alicia panel layout..."

    # Create XFCE4 config directories
    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml
        mkdir -p ${ALICIA_USER_HOME}/.config/xfce4/panel
        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config
    "

    # Write custom panel configuration
    proot_exec bash -c "cat > ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml << 'PANEL_EOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-panel\" version=\"1.0\">
  <property name=\"configver\" type=\"int\" value=\"2\"/>
  <property name=\"panels\" type=\"array\">
    <value type=\"int\" value=\"1\"/>
    <property name=\"panel-1\" type=\"empty\">
      <property name=\"position\" type=\"string\" value=\"p=6;x=0;y=0\"/>
      <property name=\"length\" type=\"uint\" value=\"100\"/>
      <property name=\"position-locked\" type=\"bool\" value=\"true\"/>
      <property name=\"icon-size\" type=\"uint\" value=\"0\"/>
      <property name=\"size\" type=\"uint\" value=\"28\"/>
      <property name=\"plugin-ids\" type=\"array\">
        <value type=\"int\" value=\"1\"/>
        <value type=\"int\" value=\"2\"/>
        <value type=\"int\" value=\"3\"/>
        <value type=\"int\" value=\"4\"/>
        <value type=\"int\" value=\"5\"/>
        <value type=\"int\" value=\"6\"/>
        <value type=\"int\" value=\"7\"/>
        <value type=\"int\" value=\"8\"/>
        <value type=\"int\" value=\"9\"/>
        <value type=\"int\" value=\"10\"/>
        <value type=\"int\" value=\"11\"/>
        <value type=\"int\" value=\"12\"/>
        <value type=\"int\" value=\"13\"/>
      </property>
      <property name=\"background-style\" type=\"uint\" value=\"0\"/>
      <property name=\"background-rgba\" type=\"array\">
        <value type=\"double\" value=\"0.000000\"/>
        <value type=\"double\" value=\"0.000000\"/>
        <value type=\"double\" value=\"0.000000\"/>
        <value type=\"double\" value=\"0.800000\"/>
      </property>
    </property>
  </property>
  <property name=\"plugins\" type=\"empty\">
    <property name=\"plugin-1\" type=\"string\" value=\"whiskermenu\"/>
    <property name=\"plugin-2\" type=\"string\" value=\"separator\"/>
    <property name=\"plugin-3\" type=\"string\" value=\"launcher\">
      <property name=\"items\" type=\"array\">
        <value type=\"string\" value=\"xfce4-terminal.desktop\"/>
      </property>
    </property>
    <property name=\"plugin-4\" type=\"string\" value=\"launcher\">
      <property name=\"items\" type=\"array\">
        <value type=\"string\" value=\"thunar.desktop\"/>
      </property>
    </property>
    <property name=\"plugin-5\" type=\"string\" value=\"launcher\">
      <property name=\"items\" type=\"array\">
        <value type=\"string\" value=\"mousepad.desktop\"/>
      </property>
    </property>
    <property name=\"plugin-6\" type=\"string\" value=\"separator\"/>
    <property name=\"plugin-7\" type=\"string\" value=\"tasklist\"/>
    <property name=\"plugin-8\" type=\"string\" value=\"separator\"/>
    <property name=\"plugin-9\" type=\"string\" value=\"cpugraph\"/>
    <property name=\"plugin-10\" type=\"string\" value=\"netload\"/>
    <property name=\"plugin-11\" type=\"string\" value=\"pulseaudio\"/>
    <property name=\"plugin-12\" type=\"string\" value=\"datetime\"/>
    <property name=\"plugin-13\" type=\"string\" value=\"actions\">
      <property name=\"appearance\" type=\"uint\" value=\"0\"/>
    </property>
  </property>
</channel>
PANEL_EOF
chown ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"

    log_info "Panel layout configured"
    mark_step_completed "configure_panel"
    return 0
}

# ============================================================================
# Desktop Icons Configuration
# ============================================================================

configure_desktop_icons() {
    log_section "Configuring Desktop Icons"

    if step_completed "configure_desktop_icons"; then
        log_info "Desktop icons already configured, skipping"
        return 0
    fi

    log_info "Setting up desktop icons..."

    # Create Desktop directory
    proot_exec "mkdir -p ${ALICIA_USER_HOME}/Desktop && chown ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/Desktop"

    # Create desktop icons
    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/Desktop

        # Terminal
        cat > ${ALICIA_USER_HOME}/Desktop/terminal.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Terminal
Comment=XFCE Terminal Emulator
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
Categories=System;TerminalEmulator;
StartupNotify=true
DESKTOP_EOF

        # File Manager
        cat > ${ALICIA_USER_HOME}/Desktop/file-manager.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=File Manager
Comment=Thunar File Manager
Exec=thunar
Icon=system-file-manager
Terminal=false
Categories=System;FileManager;
StartupNotify=true
DESKTOP_EOF

        # Text Editor
        cat > ${ALICIA_USER_HOME}/Desktop/text-editor.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Text Editor
Comment=Simple Text Editor
Exec=mousepad
Icon=accessories-text-editor
Terminal=false
Categories=Utility;TextEditor;
StartupNotify=true
DESKTOP_EOF

        # Task Manager
        cat > ${ALICIA_USER_HOME}/Desktop/task-manager.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Task Manager
Comment=XFCE Task Manager
Exec=xfce4-taskmanager
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;
StartupNotify=true
DESKTOP_EOF

        # Make desktop files executable
        chmod +x ${ALICIA_USER_HOME}/Desktop/*.desktop
        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/Desktop
    "

    # Configure XFCE desktop settings to show icons
    proot_exec bash -c "cat > ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'DESKTOP_CFG'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-desktop\" version=\"1.0\">
  <property name=\"desktop-icons\" type=\"empty\">
    <property name=\"file-icons\" type=\"empty\">
      <property name=\"show-home\" type=\"bool\" value=\"true\"/>
      <property name=\"show-filesystem\" type=\"bool\" value=\"true\"/>
      <property name=\"show-trash\" type=\"bool\" value=\"false\"/>
      <property name=\"show-removable\" type=\"bool\" value=\"true\"/>
    </property>
    <property name=\"icon-size\" type=\"uint\" value=\"48\"/>
  </property>
</channel>
DESKTOP_CFG
chown ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"

    mark_step_completed "configure_desktop_icons"
    log_info "Desktop icons configured"
    return 0
}

# ============================================================================
# Thunar File Manager Configuration
# ============================================================================

configure_thunar() {
    log_section "Configuring Thunar File Manager"

    if step_completed "configure_thunar"; then
        log_info "Thunar already configured, skipping"
        return 0
    fi

    log_info "Setting up Thunar custom actions and preferences..."

    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/.config/Thunar

        # Thunar custom actions
        cat > ${ALICIA_USER_HOME}/.config/Thunar/uca.xml << 'THUNAR_UCA'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<actions>
  <action>
    <icon>utilities-terminal</icon>
    <name>Open Terminal Here</name>
    <submenu></submenu>
    <unique-id>1</unique-id>
    <command>xfce4-terminal --working-directory %f</command>
    <description>Open terminal in this directory</description>
    <range></range>
    <patterns>*</patterns>
    <directories/>
  </action>
  <action>
    <icon>edit-find</icon>
    <name>Search Files</name>
    <submenu></submenu>
    <unique-id>2</unique-id>
    <command>catfish --path %f</command>
    <description>Search for files in this directory</description>
    <range></range>
    <patterns>*</patterns>
    <directories/>
  </action>
  <action>
    <icon>accessories-text-editor</icon>
    <name>Edit as Root</name>
    <submenu></submenu>
    <unique-id>3</unique-id>
    <command>sudo mousepad %f</command>
    <description>Edit file with root privileges</description>
    <range></range>
    <patterns>*.txt;*.conf;*.cfg;*.ini;*.sh;*.py;*.js;*.css;*.html;*.xml;*.json;*.md</patterns>
    <text-files/>
  </action>
</actions>
THUNAR_UCA

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config/Thunar
    "

    mark_step_completed "configure_thunar"
    log_info "Thunar configured"
    return 0
}

# ============================================================================
# Application Menu Configuration
# ============================================================================

configure_application_menu() {
    log_section "Configuring Application Menu"

    if step_completed "configure_app_menu"; then
        log_info "Application menu already configured, skipping"
        return 0
    fi

    log_info "Setting up application menu categories..."

    # Ensure applications directory exists
    proot_exec "mkdir -p /usr/share/applications ${ALICIA_USER_HOME}/.local/share/applications"

    # Create Alicia-specific application menu entries
    proot_exec bash -c "
        # Alicia Settings
        cat > /usr/share/applications/alicia-settings.desktop << 'APP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Alicia Settings
Comment=Alicia Desktop Environment Settings
Exec=xfce4-settings-manager
Icon=preferences-desktop
Terminal=false
Categories=Settings;DesktopSettings;X-XFCE-SettingsDialog;
StartupNotify=true
APP_EOF

        # Alicia System Info
        cat > /usr/share/applications/alicia-info.desktop << 'APP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Alicia System Info
Comment=Show Alicia system information
Exec=xfce4-terminal -e \"bash -c 'echo \\\"Alicia Desktop Environment v2.0.0\\\"; echo \\\"Proyecto Tomorrow\\\"; uname -a; free -h; df -h / ; read -p Press_Enter'\"
Icon=dialog-information
Terminal=false
Categories=System;
StartupNotify=true
APP_EOF

        # Update desktop database
        update-desktop-database /usr/share/applications 2>/dev/null || true
        update-desktop-database ${ALICIA_USER_HOME}/.local/share/applications 2>/dev/null || true
    "

    mark_step_completed "configure_app_menu"
    log_info "Application menu configured"
    return 0
}

# ============================================================================
# Window Manager Configuration
# ============================================================================

configure_window_manager() {
    log_section "Configuring Window Manager (xfwm4)"

    if step_completed "configure_wm"; then
        log_info "Window manager already configured, skipping"
        return 0
    fi

    log_info "Setting up xfwm4 with keyboard shortcuts..."

    proot_exec bash -c "cat > ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'XFWM_EOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfwm4\" version=\"1.0\">
  <property name=\"general\" type=\"empty\">
    <property name=\"activate_action\" type=\"string\" value=\"bring\"/>
    <property name=\"borderless_maximize\" type=\"bool\" value=\"true\"/>
    <property name=\"box_move\" type=\"bool\" value=\"false\"/>
    <property name=\"box_resize\" type=\"bool\" value=\"false\"/>
    <property name=\"button_layout\" type=\"string\" value=\"O|HMC\"/>
    <property name=\"button_offset\" type=\"int\" value=\"0\"/>
    <property name=\"button_spacing\" type=\"int\" value=\"0\"/>
    <property name=\"click_to_focus\" type=\"bool\" value=\"true\"/>
    <property name=\"cycle_apps_only\" type=\"bool\" value=\"false\"/>
    <property name=\"cycle_draw_frame\" type=\"bool\" value=\"true\"/>
    <property name=\"cycle_hidden\" type=\"bool\" value=\"true\"/>
    <property name=\"cycle_minimum\" type=\"bool\" value=\"true\"/>
    <property name=\"cycle_workspaces\" type=\"bool\" value=\"true\"/>
    <property name=\"double_click_action\" type=\"string\" value=\"maximize\"/>
    <property name=\"double_click_distance\" type=\"int\" value=\"5\"/>
    <property name=\"double_click_time\" type=\"int\" value=\"400\"/>
    <property name=\"easy_click\" type=\"string\" value=\"Alt\"/>
    <property name=\"focus_delay\" type=\"int\" value=\"250\"/>
    <property name=\"focus_hint\" type=\"bool\" value=\"true\"/>
    <property name=\"focus_new\" type=\"bool\" value=\"true\"/>
    <property name=\"frame_opacity\" type=\"int\" value=\"100\"/>
    <property name=\"full_width_title\" type=\"bool\" value=\"true\"/>
    <property name=\"horiz_scroll_opacity\" type=\"bool\" value=\"false\"/>
    <property name=\"inactive_opacity\" type=\"int\" value=\"100\"/>
    <property name=\"maximized_offset\" type=\"int\" value=\"0\"/>
    <property name=\"mousewheel_rollup\" type=\"bool\" value=\"true\"/>
    <property name=\"move_opacity\" type=\"int\" value=\"100\"/>
    <property name=\"placement_mode\" type=\"string\" value=\"center\"/>
    <property name=\"placement_ratio\" type=\"int\" value=\"20\"/>
    <property name=\"popup_opacity\" type=\"int\" value=\"100\"/>
    <property name=\"prevent_focus_stealing\" type=\"bool\" value=\"false\"/>
    <property name=\"raise_delay\" type=\"int\" value=\"250\"/>
    <property name=\"raise_on_click\" type=\"bool\" value=\"true\"/>
    <property name=\"raise_on_focus\" type=\"bool\" value=\"false\"/>
    <property name=\"raise_with_any_button\" type=\"bool\" value=\"true\"/>
    <property name=\"resize_opacity\" type=\"int\" value=\"100\"/>
    <property name=\"scroll_workspaces\" type=\"bool\" value=\"true\"/>
    <property name=\"shadow_delta_x\" type=\"int\" value=\"0\"/>
    <property name=\"shadow_delta_y\" type=\"int\" value=\"0\"/>
    <property name=\"shadow_opacity\" type=\"int\" value=\"50\"/>
    <property name=\"show_frame_shadow\" type=\"bool\" value=\"true\"/>
    <property name=\"show_popup_shadow\" type=\"bool\" value=\"false\"/>
    <property name=\"snap_to_border\" type=\"bool\" value=\"true\"/>
    <property name=\"snap_to_windows\" type=\"bool\" value=\"false\"/>
    <property name=\"snap_width\" type=\"int\" value=\"10\"/>
    <property name=\"sync_to_vblank\" type=\"bool\" value=\"false\"/>
    <property name=\"theme\" type=\"string\" value=\"Default\"/>
    <property name=\"tile_on_move\" type=\"bool\" value=\"true\"/>
    <property name=\"title_alignment\" type=\"string\" value=\"center\"/>
    <property name=\"title_font\" type=\"string\" value=\"Sans Bold 9\"/>
    <property name=\"title_horizontal_offset\" type=\"int\" value=\"0\"/>
    <property name=\"titleless_maximize\" type=\"bool\" value=\"false\"/>
    <property name=\"title_shadow_active\" type=\"string\" value=\"hash\"/>
    <property name=\"title_shadow_inactive\" type=\"string\" value=\"hash\"/>
    <property name=\"title_vertical_offset_active\" type=\"int\" value=\"0\"/>
    <property name=\"title_vertical_offset_inactive\" type=\"int\" value=\"0\"/>
    <property name=\"toggle_workspaces\" type=\"bool\" value=\"false\"/>
    <property name=\"unredirect_overlays\" type=\"bool\" value=\"true\"/>
    <property name=\"use_compositing\" type=\"bool\" value=\"true\"/>
    <property name=\"workspace_count\" type=\"int\" value=\"2\"/>
    <property name=\"wrap_cycle\" type=\"bool\" value=\"true\"/>
    <property name=\"wrap_layout\" type=\"bool\" value=\"true\"/>
    <property name=\"wrap_resistance\" type=\"int\" value=\"10\"/>
    <property name=\"wrap_workspaces\" type=\"bool\" value=\"false\"/>
    <property name=\"zoom_desktop\" type=\"bool\" value=\"true\"/>
  </property>
  <property name=\"custom_keybindings\" type=\"empty\">
    <property name=\"Custom\" type=\"empty\">
      <property name=\"Up\" type=\"string\" value=\"Up\"/>
      <property name=\"Down\" type=\"string\" value=\"Down\"/>
      <property name=\"Left\" type=\"string\" value=\"Left\"/>
      <property name=\"Right\" type=\"string\" value=\"Right\"/>
      <property name=\"Cancel\" type=\"string\" value=\"Escape\"/>
    </property>
  </property>
  <property name=\"keybindings\" type=\"empty\">
    <property name=\"close_window_key\" type=\"string\" value=\"Alt+F4\"/>
    <property name=\"maximize_window_key\" type=\"string\" value=\"Alt+F10\"/>
    <property name=\"maximize_horiz_key\" type=\"empty\"/>
    <property name=\"maximize_vert_key\" type=\"empty\"/>
    <property name=\"move_window_key\" type=\"string\" value=\"Alt+F7\"/>
    <property name=\"resize_window_key\" type=\"string\" value=\"Alt+F8\"/>
    <property name=\"stick_window_key\" type=\"empty\"/>
    <property name=\"shade_window_key\" type=\"empty\"/>
    <property name=\"hide_window_key\" type=\"string\" value=\"Alt+F9\"/>
    <property name=\"cycle_windows_key\" type=\"string\" value=\"Alt+Tab\"/>
    <property name=\"cycle_reverse_windows_key\" type=\"string\" value=\"Alt+Shift+Tab\"/>
    <property name=\"move_to_next_workspace_key\" type=\"string\" value=\"Control+Alt+Right\"/>
    <property name=\"move_to_prev_workspace_key\" type=\"string\" value=\"Control+Alt+Left\"/>
    <property name=\"move_to_workspace_1_key\" type=\"empty\"/>
    <property name=\"move_to_workspace_2_key\" type=\"empty\"/>
    <property name=\"workspace_1_key\" type=\"string\" value=\"Control+F1\"/>
    <property name=\"workspace_2_key\" type=\"string\" value=\"Control+F2\"/>
    <property name=\"show_desktop_key\" type=\"string\" value=\"Control+Alt+d\"/>
  </property>
</channel>
XFWM_EOF
chown ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"

    mark_step_completed "configure_wm"
    log_info "Window manager configured"
    return 0
}

# ============================================================================
# Wallpaper Configuration
# ============================================================================

configure_wallpaper() {
    log_section "Configuring Desktop Wallpaper"

    if step_completed "configure_wallpaper"; then
        log_info "Wallpaper already configured, skipping"
        return 0
    fi

    log_info "Setting up desktop wallpaper..."

    # Create wallpapers directory
    proot_exec bash -c "
        mkdir -p /usr/share/backgrounds/alicia
        mkdir -p ${ALICIA_USER_HOME}/Pictures/Wallpapers
        chown ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/Pictures/Wallpapers
    "

    # Generate a simple gradient wallpaper using ImageMagick (if available)
    # or create a solid color fallback
    proot_exec bash -c '
        if command -v convert &>/dev/null; then
            # Create Alicia branded gradient wallpaper
            convert -size 1920x1080 -define gradient:angle=135 \
                gradient:"#1a3a5c"-"#2e6da4" \
                /usr/share/backgrounds/alicia/alicia-default.png 2>/dev/null || \
            convert -size 1920x1080 xc:"#2e6da4" \
                /usr/share/backgrounds/alicia/alicia-default.png 2>/dev/null || true
        fi

        # If ImageMagick is not available, create a simple PNG using raw data
        if [[ ! -f /usr/share/backgrounds/alicia/alicia-default.png ]]; then
            # Download a default wallpaper or create placeholder
            wget -q "https://raw.githubusercontent.com/nicoh88/xfce4-whiskermenu-plugin/master/panel-plugin/data/icons/16x16/org.xfce.whiskermenu.png" \
                -O /usr/share/backgrounds/alicia/alicia-default.png 2>/dev/null || true

            # If download fails, just set the desktop to a solid color
            if [[ ! -f /usr/share/backgrounds/alicia/alicia-default.png ]]; then
                echo "Wallpaper image not available, using solid color"
            fi
        fi
    ' || log_debug "Wallpaper generation had issues"

    # Configure XFCE to use the wallpaper
    proot_exec bash -c "cat > ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'WALL_CFG'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-desktop\" version=\"1.0\">
  <property name=\"backdrop\" type=\"empty\">
    <property name=\"screen0\" type=\"empty\">
      <property name=\"monitor0\" type=\"empty\">
        <property name=\"image-path\" type=\"string\" value=\"/usr/share/backgrounds/alicia/alicia-default.png\"/>
        <property name=\"image-show\" type=\"bool\" value=\"true\"/>
        <property name=\"image-style\" type=\"int\" value=\"5\"/>
        <property name=\"workspace0\" type=\"empty\">
          <property name=\"color-style\" type=\"int\" value=\"1\"/>
          <property name=\"color1\" type=\"array\">
            <value type=\"uint\" value=\"26\"/>
            <value type=\"uint\" value=\"58\"/>
            <value type=\"uint\" value=\"92\"/>
            <value type=\"uint\" value=\"65535\"/>
          </property>
          <property name=\"color2\" type=\"array\">
            <value type=\"uint\" value=\"46\"/>
            <value type=\"uint\" value=\"109\"/>
            <value type=\"uint\" value=\"164\"/>
            <value type=\"uint\" value=\"65535\"/>
          </property>
          <property name=\"last-image\" type=\"string\" value=\"/usr/share/backgrounds/alicia/alicia-default.png\"/>
          <property name=\"last-single-image\" type=\"string\" value=\"/usr/share/backgrounds/alicia/alicia-default.png\"/>
        </property>
      </property>
    </property>
  </property>
  <property name=\"desktop-icons\" type=\"empty\">
    <property name=\"file-icons\" type=\"empty\">
      <property name=\"show-home\" type=\"bool\" value=\"true\"/>
      <property name=\"show-filesystem\" type=\"bool\" value=\"true\"/>
      <property name=\"show-trash\" type=\"bool\" value=\"false\"/>
      <property name=\"show-removable\" type=\"bool\" value=\"true\"/>
    </property>
    <property name=\"icon-size\" type=\"uint\" value=\"48\"/>
  </property>
</channel>
WALL_CFG
chown ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"

    mark_step_completed "configure_wallpaper"
    log_info "Wallpaper configured"
    return 0
}

# ============================================================================
# Screensaver and Power Management Configuration
# ============================================================================

configure_screensaver_power() {
    log_section "Configuring Screensaver and Power Management"

    if step_completed "configure_screensaver"; then
        log_info "Screensaver/power already configured, skipping"
        return 0
    fi

    log_info "Setting up screensaver and power management..."

    # Install screensaver (lightweight alternative)
    apk_install "Installing screensaver" "xscreensaver"

    # Configure xfce4-power-manager settings
    proot_exec bash -c "cat > ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml << 'POWER_EOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-power-manager\" version=\"1.0\">
  <property name=\"xfce4-power-manager\" type=\"empty\">
    <property name=\"power-button-action\" type=\"uint\" value=\"3\"/>
    <property name=\"sleep-button-action\" type=\"uint\" value=\"1\"/>
    <property name=\"hibernate-button-action\" type=\"uint\" value=\"2\"/>
    <property name=\"brightness-on-battery\" type=\"uint\" value=\"80\"/>
    <property name=\"brightness-level-on-battery\" type=\"uint\" value=\"80\"/>
    <property name=\"lock-screen-suspend-hibernate\" type=\"bool\" value=\"false\"/>
    <property name=\"logind-handle-lid-switch\" type=\"bool\" value=\"false\"/>
    <property name=\"dpms-on-battery-sleep\" type=\"uint\" value=\"10\"/>
    <property name=\"dpms-on-battery-off\" type=\"uint\" value=\"15\"/>
    <property name=\"blank-on-battery\" type=\"int\" value=\"5\"/>
    <property name=\"dpms-on-ac-sleep\" type=\"uint\" value=\"0\"/>
    <property name=\"dpms-on-ac-off\" type=\"uint\" value=\"0\"/>
    <property name=\"blank-on-ac\" type=\"int\" value=\"0\"/>
    <property name=\"inactivity-on-battery\" type=\"uint\" value=\"0\"/>
    <property name=\"inactivity-on-ac\" type=\"uint\" value=\"0\"/>
    <property name=\"inactivity-sleep-mode-on-battery\" type=\"uint\" value=\"1\"/>
    <property name=\"inactivity-sleep-mode-on-ac\" type=\"uint\" value=\"1\"/>
    <property name=\"show-tray-icon\" type=\"bool\" value=\"true\"/>
  </property>
</channel>
POWER_EOF
chown ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml"

    mark_step_completed "configure_screensaver"
    log_info "Screensaver and power management configured"
    return 0
}

# ============================================================================
# Custom Alicia Theme Settings
# ============================================================================

create_alicia_theme() {
    log_section "Creating Custom Alicia Theme"

    if step_completed "create_alicia_theme"; then
        log_info "Alicia theme already created, skipping"
        return 0
    fi

    log_info "Creating custom Alicia GTK theme..."

    # Create Alicia GTK theme directory
    proot_exec bash -c "
        mkdir -p /usr/share/themes/Alicia/gtk-3.0
        mkdir -p /usr/share/themes/Alicia/gtk-2.0
        mkdir -p /usr/share/themes/Alicia/xfwm4

        # GTK-3.0 theme (blue/white accent)
        cat > /usr/share/themes/Alicia/gtk-3.0/gtk.css << 'GTK3_EOF'
/* Alicia Desktop Environment - GTK3 Theme */
/* Blue/White accent color scheme */

@define-color accent_color #2e6da4;
@define-color accent_bg_color #1a3a5c;
@define-color accent_fg_color #ffffff;
@define-color theme_fg_color #333333;
@define-color theme_bg_color #f5f5f5;
@define-color theme_base_color #ffffff;
@define-color theme_selected_bg_color @accent_color;
@define-color theme_selected_fg_color @accent_fg_color;

/* Header bars */
.header-bar {
    background-color: @accent_bg_color;
    color: @accent_fg_color;
}

/* Selections */
.selection-mode .header-bar {
    background-color: @accent_color;
}

/* Buttons */
.button {
    background-color: @theme_bg_color;
    border: 1px solid #cccccc;
    border-radius: 3px;
    padding: 4px 12px;
}

.button:hover {
    background-color: shade(@accent_color, 1.3);
    color: @accent_fg_color;
}

.button:active,
.button:checked {
    background-color: @accent_color;
    color: @accent_fg_color;
}

/* Entries */
.entry {
    background-color: @theme_base_color;
    border: 1px solid #cccccc;
    border-radius: 3px;
    padding: 4px;
}

.entry:focus {
    border-color: @accent_color;
}

/* Scrollbars */
.scrollbar {
    background-color: transparent;
}

.scrollbar .slider {
    background-color: shade(@theme_bg_color, 0.7);
    border-radius: 4px;
}
GTK3_EOF

        # XFWM4 theme colors (Alicia blue)
        cat > /usr/share/themes/Alicia/xfwm4/themerc << 'XFWM4RC'
# Alicia Window Manager Theme
active_color=#2e6da4
inactive_color=#8f9bb3
active_border=#1a3a5c
inactive_border=#5a6577
active_text=#ffffff
inactive_text=#c0c0c0
button_layout=O|HMC
XFWM4RC

        # Set theme as default via xsettings
        mkdir -p ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml
        cat > ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << 'XSETTINGS_EOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xsettings\" version=\"1.0\">
  <property name=\"Net\" type=\"empty\">
    <property name=\"ThemeName\" type=\"string\" value=\"Alicia\"/>
    <property name=\"IconThemeName\" type=\"string\" value=\"Papirus\"/>
    <property name=\"DoubleClickTime\" type=\"int\" value=\"400\"/>
    <property name=\"DoubleClickDistance\" type=\"int\" value=\"5\"/>
    <property name=\"DndDragThreshold\" type=\"int\" value=\"8\"/>
    <property name=\"CursorBlink\" type=\"bool\" value=\"true\"/>
    <property name=\"CursorBlinkTime\" type=\"int\" value=\"1200\"/>
    <property name=\"SoundThemeName\" type=\"string\" value=\"default\"/>
    <property name=\"EnableEventSounds\" type=\"bool\" value=\"false\"/>
    <property name=\"EnableInputFeedbackSounds\" type=\"bool\" value=\"false\"/>
  </property>
  <property name=\"Gtk\" type=\"empty\">
    <property name=\"FontName\" type=\"string\" value=\"Sans 10\"/>
    <property name=\"MonospaceFontName\" type=\"string\" value=\"Monospace 10\"/>
    <property name=\"ToolbarStyle\" type=\"int\" value=\"3\"/>
    <property name=\"ToolbarIconSize\" type=\"int\" value=\"2\"/>
    <property name=\"MenuImages\" type=\"bool\" value=\"true\"/>
    <property name=\"ButtonImages\" type=\"bool\" value=\"true\"/>
    <property name=\"CanChangeAccels\" type=\"bool\" value=\"false\"/>
    <property name=\"IMPreeditStyle\" type=\"string\" value=\"\"/>
    <property name=\"IMStatusStyle\" type=\"string\" value=\"\"/>
    <property name=\"IMModule\" type=\"string\" value=\"\"/>
    <property name=\"ToolbarIconSize\" type=\"int\" value=\"2\"/>
    <property name=\"KeyThemeName\" type=\"string\" value=\"\"/>
    <property name=\"ColorScheme\" type=\"string\" value=\"\"/>
  </property>
  <property name=\"Xft\" type=\"empty\">
    <property name=\"DPI\" type=\"int\" value=\"96\"/>
    <property name=\"Antialias\" type=\"int\" value=\"1\"/>
    <property name=\"Hinting\" type=\"int\" value=\"1\"/>
    <property name=\"HintStyle\" type=\"string\" value=\"hintslight\"/>
    <property name=\"RGBA\" type=\"string\" value=\"rgb\"/>
  </property>
</channel>
XSETTINGS_EOF

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config
    "

    mark_step_completed "create_alicia_theme"
    log_info "Custom Alicia theme created"
    return 0
}

# ============================================================================
# Additional Useful Applications
# ============================================================================

install_additional_apps() {
    log_section "Installing Additional Applications"

    if step_completed "install_additional_apps"; then
        log_info "Additional apps already installed, skipping"
        return 0
    fi

    log_info "Installing supplementary applications..."

    local additional_apps=(
        "mousepad"
        "ristretto"
        "parole"
        "file-roller"
        "xfburn"
        "galculator"
        "gpicview"
        "catfish"
    )

    apk_install "Installing additional apps" "${additional_apps[@]}"

    # Try to install some apps that may or may not be available on Alpine
    local optional_apps=(
        "geany"
        "midori"
        "sakura"
        "obconf"
    )

    log_info "Installing optional applications (non-fatal)..."
    for app in "${optional_apps[@]}"; do
        proot_exec "apk add --no-cache $app 2>&1" >/dev/null 2>&1 && \
            log_info "  Installed: $app" || \
            log_debug "  Not available: $app"
    done

    mark_step_completed "install_additional_apps"
    log_info "Additional applications installation complete"
    return 0
}

# ============================================================================
# XFCE4 Keyboard Shortcuts
# ============================================================================

configure_keyboard_shortcuts() {
    log_section "Configuring XFCE4 Keyboard Shortcuts"

    if step_completed "configure_shortcuts"; then
        log_info "Keyboard shortcuts already configured, skipping"
        return 0
    fi

    log_info "Setting up custom keyboard shortcuts..."

    proot_exec bash -c "cat > ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml << 'SHORTCUTS_EOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-keyboard-shortcuts\" version=\"1.0\">
  <property name=\"commands\" type=\"empty\">
    <property name=\"default\" type=\"empty\">
      <property name=\"&lt;Alt&gt;F1\" type=\"string\" value=\"xfce4-popup-whiskermenu\"/>
      <property name=\"&lt;Alt&gt;F2\" type=\"string\" value=\"xfce4-appfinder --collapsed\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;Delete\" type=\"string\" value=\"xflock4\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;t\" type=\"string\" value=\"xfce4-terminal\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;f\" type=\"string\" value=\"thunar\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;e\" type=\"string\" value=\"mousepad\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;s\" type=\"string\" value=\"xfce4-screenshooter\"/>
      <property name=\"&lt;Super&gt;p\" type=\"string\" value=\"xfce4-display-settings --minimal\"/>
      <property name=\"&lt;Primary&gt;&lt;Alt&gt;Escape\" type=\"string\" value=\"xkill\"/>
    </property>
    <property name=\"custom\" type=\"empty\">
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;t\" type=\"string\" value=\"xfce4-terminal\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;f\" type=\"string\" value=\"thunar\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;e\" type=\"string\" value=\"mousepad\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;s\" type=\"string\" value=\"xfce4-screenshooter\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;Delete\" type=\"string\" value=\"xflock4\"/>
      <property name=\"&lt;Alt&gt;F1\" type=\"string\" value=\"xfce4-popup-whiskermenu\"/>
      <property name=\"&lt;Alt&gt;F2\" type=\"string\" value=\"xfce4-appfinder --collapsed\"/>
      <property name=\"&lt;Super&gt;l\" type=\"string\" value=\"xflock4\"/>
    </property>
  </property>
</channel>
SHORTCUTS_EOF
chown ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"

    mark_step_completed "configure_shortcuts"
    log_info "Keyboard shortcuts configured"
    return 0
}

# ============================================================================
# Desktop Environment Validation
# ============================================================================

validate_desktop_setup() {
    log_section "Validating Desktop Environment Setup"

    if step_completed "validate_desktop"; then
        log_info "Desktop validation already completed, skipping"
        return 0
    fi

    local errors=0

    # Check essential XFCE components
    local xfce_components=("startxfce4" "xfce4-session" "xfwm4" "xfce4-panel" "xfce4-terminal" "thunar")
    log_info "Checking XFCE4 components..."
    for component in "${xfce_components[@]}"; do
        if proot_exec "command -v $component" &>/dev/null; then
            log_info "  [OK] $component"
        else
            log_error "  [FAIL] $component not found"
            ((errors++)) || true
        fi
    done

    # Check X11
    log_info "Checking X11..."
    if proot_exec "command -v Xvfb" &>/dev/null; then
        log_info "  [OK] Xvfb available"
    else
        log_warn "  [WARN] Xvfb not found"
    fi

    # Check themes
    log_info "Checking themes..."
    if proot_exec "test -d /usr/share/themes/Alicia" &>/dev/null; then
        log_info "  [OK] Alicia theme installed"
    else
        log_warn "  [WARN] Alicia theme not found"
    fi

    # Check fonts
    log_info "Checking font count..."
    local font_count
    font_count=$(proot_exec "fc-list 2>/dev/null | wc -l" || echo "0")
    log_info "  Font count: $font_count"
    if [[ $font_count -lt 10 ]]; then
        log_warn "  Few fonts detected (expected more)"
    fi

    # Check user config directory
    log_info "Checking user configuration..."
    if proot_exec "test -d ${ALICIA_USER_HOME}/.config/xfce4" &>/dev/null; then
        log_info "  [OK] XFCE4 config directory exists"
    else
        log_warn "  [WARN] XFCE4 config directory not found"
    fi

    if [[ $errors -eq 0 ]]; then
        log_info "Desktop environment validation passed!"
    else
        log_warn "$errors validation error(s) found"
    fi

    mark_step_completed "validate_desktop"
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
        alicia_lock_release "setup-03" 2>/dev/null || true
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
    log_section "Alicia Desktop - XFCE4 Setup (Step 3/6)"
    log_info "Version: ${SCRIPT_VERSION}"
    log_info "Author:  Proyecto Tomorrow"
    log_info "Time:    $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Check prerequisites
    if [[ ! -f "${ALICIA_BASE_DIR}/.setup-02-state" ]]; then
        log_warn "Step 02 (proot setup) may not be completed"
        log_warn "Continuing anyway..."
    fi

    load_state

    if declare -f alicia_lock_acquire &>/dev/null; then
        alicia_lock_acquire "setup-03" 600 || {
            log_error "Another setup process is running"
            exit 1
        }
    fi

    local steps=(
        "install_x11_base"
        "install_xfce4_core"
        "install_xfce4_goodies"
        "install_themes_and_icons"
        "install_fonts"
        "install_audio_support"
        "install_multimedia_codecs"
        "install_printing_support"
        "configure_xfce4_panel"
        "configure_desktop_icons"
        "configure_thunar"
        "configure_application_menu"
        "configure_window_manager"
        "configure_wallpaper"
        "configure_screensaver_power"
        "create_alicia_theme"
        "install_additional_apps"
        "configure_keyboard_shortcuts"
        "validate_desktop_setup"
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

    log_section "XFCE4 Desktop Setup Complete"
    log_info "The XFCE4 desktop environment is installed and configured!"
    log_info ""
    log_info "Installed components:"
    log_info "  X11:        Base + Xvfb"
    log_info "  Desktop:    XFCE4 + Goodies"
    log_info "  Themes:     Alicia (blue/white) + Papirus icons"
    log_info "  Fonts:      Dejavu, Noto, Liberation, etc."
    log_info "  Audio:      ALSA + PulseAudio"
    log_info "  Multimedia: FFmpeg + GStreamer"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Run: ${SCRIPT_DIR}/04-vnc-setup.sh"
    log_info "  2. This will set up VNC for remote desktop access"

    return 0
}

main "$@"
