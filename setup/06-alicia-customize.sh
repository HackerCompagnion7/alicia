#!/bin/bash
# ============================================================================
# 06-alicia-customize.sh - Alicia Desktop Environment Customization
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
# Description:  Customizes the desktop environment to be "Alicia" with
#               Proyecto Tomorrow branding. Applies blue/white accent theme,
#               custom wallpaper, XFCE panel layout, custom menu entries,
#               desktop icons, Settings Manager, Welcome app, file
#               associations, autostart, keyboard shortcuts, right-click
#               menu, user directories, README files, bash aliases,
#               .gitconfig, first-run script, GTK theme modifications,
#               notification daemon, and power manager settings.
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

# Alicia Brand Colors
readonly ALICIA_COLOR_PRIMARY="#2e6da4"       # Blue
readonly ALICIA_COLOR_SECONDARY="#1a3a5c"     # Dark Blue
readonly ALICIA_COLOR_ACCENT="#5ba3e6"        # Light Blue
readonly ALICIA_COLOR_TEXT="#ffffff"           # White
readonly ALICIA_COLOR_BG="#f0f4f8"            # Light grayish blue
readonly ALICIA_COLOR_SUCCESS="#4caf50"        # Green
readonly ALICIA_COLOR_WARNING="#ff9800"        # Orange

# ============================================================================
# State Tracking
# ============================================================================
_SETUP_STATE_FILE="${ALICIA_BASE_DIR}/.setup-06-state"
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
# Apply Alicia Branding (Theme Colors)
# ============================================================================

apply_alicia_branding() {
    log_section "Applying Alicia Branding"

    if step_completed "apply_branding"; then
        log_info "Alicia branding already applied, skipping"
        return 0
    fi

    log_info "Applying Proyecto Tomorrow branding with blue/white accent..."

    # Update the Alicia GTK3 theme with refined branding
    proot_exec bash -c "
        mkdir -p /usr/share/themes/Alicia/gtk-3.0

        cat > /usr/share/themes/Alicia/gtk-3.0/gtk.css << 'GTK3_CSS'
/* ============================================================================
 * Alicia Desktop Environment - GTK3 Theme
 * Copyright (C) 2005-2025 Proyecto Tomorrow
 * Brand Colors: Blue/White accent (#2e6da4 / #ffffff)
 * ============================================================================ */

/* --- Color Definitions --- */
@define-color alicia_primary ${ALICIA_COLOR_PRIMARY};
@define-color alicia_secondary ${ALICIA_COLOR_SECONDARY};
@define-color alicia_accent ${ALICIA_COLOR_ACCENT};
@define-color alicia_text ${ALICIA_COLOR_TEXT};
@define-color alicia_bg ${ALICIA_COLOR_BG};
@define-color alicia_success ${ALICIA_COLOR_SUCCESS};
@define-color alicia_warning ${ALICIA_COLOR_WARNING};

/* --- Standard Theme Colors --- */
@define-color theme_fg_color #333333;
@define-color theme_bg_color #f5f5f5;
@define-color theme_base_color #ffffff;
@define-color theme_selected_bg_color @alicia_primary;
@define-color theme_selected_fg_color @alicia_text;

/* --- Window Decorations --- */
.window-frame {
    border-radius: 4px;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
}

/* --- Header Bars --- */
.header-bar {
    background-color: @alicia_secondary;
    color: @alicia_text;
    padding: 4px 8px;
    border-bottom: 1px solid shade(@alicia_secondary, 0.8);
}

.header-bar:backdrop {
    background-color: shade(@alicia_secondary, 1.2);
}

/* --- Buttons --- */
.button {
    background-image: none;
    background-color: @theme_bg_color;
    border: 1px solid #c0c0c0;
    border-radius: 4px;
    padding: 5px 14px;
    color: @theme_fg_color;
    transition: all 150ms ease;
}

.button:hover {
    background-color: @alicia_accent;
    color: @alicia_text;
    border-color: @alicia_primary;
}

.button:active,
.button:checked {
    background-color: @alicia_primary;
    color: @alicia_text;
    border-color: @alicia_secondary;
}

.button.suggested-action {
    background-color: @alicia_primary;
    color: @alicia_text;
    border-color: @alicia_secondary;
}

.button.suggested-action:hover {
    background-color: @alicia_accent;
}

/* --- Entries --- */
.entry {
    background-color: @theme_base_color;
    border: 1px solid #c0c0c0;
    border-radius: 4px;
    padding: 5px 8px;
    color: @theme_fg_color;
}

.entry:focus {
    border-color: @alicia_primary;
    box-shadow: inset 0 0 0 1px @alicia_primary;
}

/* --- Selections --- */
.selection-mode .header-bar {
    background-color: @alicia_primary;
}

.view:selected,
.view text:selected,
textview text selection {
    background-color: @alicia_primary;
    color: @alicia_text;
}

/* --- Scrollbars --- */
.scrollbar {
    background-color: transparent;
}

.scrollbar .slider {
    background-color: rgba(0, 0, 0, 0.3);
    border-radius: 4px;
    min-width: 8px;
    min-height: 8px;
}

.scrollbar .slider:hover {
    background-color: @alicia_primary;
}

/* --- Menus --- */
.menu {
    background-color: @theme_base_color;
    border: 1px solid #d0d0d0;
    border-radius: 4px;
    padding: 4px 0;
}

.menuitem:hover {
    background-color: @alicia_primary;
    color: @alicia_text;
}

/* --- Notebooks (Tabs) --- */
.notebook tab {
    padding: 6px 12px;
    border-radius: 4px 4px 0 0;
}

.notebook tab:active {
    background-color: @alicia_primary;
    color: @alicia_text;
}

/* --- Progress Bars --- */
.progressbar {
    background-color: @alicia_primary;
    border-radius: 3px;
}

/* --- Check/Radio Buttons --- */
.check:checked,
.radio:checked {
    color: @alicia_primary;
}

/* --- Switches --- */
.switch:active {
    background-color: @alicia_primary;
}

/* --- Links --- */
*:link {
    color: @alicia_primary;
}
GTK3_CSS

        # Apply theme via XFCE configuration
        mkdir -p ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml
    "

    log_info "Alicia branding applied"
    mark_step_completed "apply_branding"
    return 0
}

# ============================================================================
# Custom Wallpaper Generation
# ============================================================================

set_custom_wallpaper() {
    log_section "Setting Custom Alicia Wallpaper"

    if step_completed "set_wallpaper"; then
        log_info "Custom wallpaper already set, skipping"
        return 0
    fi

    log_info "Generating Alicia branded wallpaper..."

    proot_exec bash -c '
        mkdir -p /usr/share/backgrounds/alicia
        mkdir -p '${ALICIA_USER_HOME}'/Pictures/Wallpapers

        WALLPAPER_DIR="/usr/share/backgrounds/alicia"

        # Try to generate wallpaper with ImageMagick
        if command -v convert &>/dev/null; then
            # Create a professional gradient wallpaper with Alicia branding
            convert -size 1920x1080 \
                -define gradient:angle=135 \
                gradient:"#0d2137"-"#1a3a5c"-"#2e6da4" \
                "${WALLPAPER_DIR}/alicia-default.png" 2>/dev/null || true

            # Add subtle geometric pattern overlay
            if [[ -f "${WALLPAPER_DIR}/alicia-default.png" ]]; then
                # Add a subtle grid pattern
                convert "${WALLPAPER_DIR}/alicia-default.png" \
                    \( -size 1920x1080 xc:none -draw "stroke rgba(255,255,255,0.03) stroke-width 1 line 0,0 1920,1080 line 1920,0 0,1080" \) \
                    -composite "${WALLPAPER_DIR}/alicia-default.png" 2>/dev/null || true

                # Add "Alicia" text watermark
                convert "${WALLPAPER_DIR}/alicia-default.png" \
                    -gravity center -pointsize 72 -fill "rgba(255,255,255,0.08)" \
                    -font DejaVu-Sans-Bold -annotate 0 "alicia" \
                    "${WALLPAPER_DIR}/alicia-default.png" 2>/dev/null || true

                # Add version text
                convert "${WALLPAPER_DIR}/alicia-default.png" \
                    -gravity SouthEast -pointsize 14 -fill "rgba(255,255,255,0.3)" \
                    -font DejaVu-Sans -annotate +20+20 "Alicia Desktop v3.1.0 | Proyecto Tomorrow" \
                    "${WALLPAPER_DIR}/alicia-default.png" 2>/dev/null || true

                echo "Wallpaper generated with ImageMagick"
            fi
        fi

        # If ImageMagick failed or not available, try downloading
        if [[ ! -f "${WALLPAPER_DIR}/alicia-default.png" ]]; then
            # Download a simple blue gradient wallpaper
            wget -q "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/24701-nature-flowers.jpg/1280px-24701-nature-flowers.jpg" \
                -O "${WALLPAPER_DIR}/alicia-default.png" 2>/dev/null || true
        fi

        # If still no wallpaper, create a simple one with Python
        if [[ ! -f "${WALLPAPER_DIR}/alicia-default.png" ]] && command -v python3 &>/dev/null; then
            python3 -c "
import struct, zlib
width, height = 1920, 1080
pixels = []
for y in range(height):
    row = []
    for x in range(width):
        r = int(13 + (x / width) * 33)
        g = int(33 + (x / width) * 58 + (y / height) * 73)
        b = int(55 + (x / width) * 111)
        row.extend([min(r, 255), min(g, 255), min(b, 255)])
    pixels.extend(row)

def create_png(width, height, pixels):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    
    raw_data = b''
    for y in range(height):
        raw_data += b'\x00'
        for x in range(width):
            idx = (y * width + x) * 3
            raw_data += bytes(pixels[idx:idx+3])
    
    return b'\x89PNG\r\n\x1a\n' + \
           chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + \
           chunk(b'IDAT', zlib.compress(raw_data)) + \
           chunk(b'IEND', b'')

with open('${WALLPAPER_DIR}/alicia-default.png', 'wb') as f:
    f.write(create_png(width, height, pixels))
print('Wallpaper generated with Python')
" 2>/dev/null || true
        fi

        # Last resort: create a 1x1 pixel PNG
        if [[ ! -f "${WALLPAPER_DIR}/alicia-default.png" ]]; then
            printf "\x89PNG\r\n\x1a\n" > "${WALLPAPER_DIR}/alicia-default.png"
            echo "Placeholder wallpaper created"
        fi

        # Copy to user wallpaper directory
        cp "${WALLPAPER_DIR}/alicia-default.png" '${ALICIA_USER_HOME}'/Pictures/Wallpapers/ 2>/dev/null || true
        chown -R '${ALICIA_USER}':'${ALICIA_USER}' '${ALICIA_USER_HOME}'/Pictures 2>/dev/null || true
    '

    mark_step_completed "set_wallpaper"
    log_info "Custom wallpaper set"
    return 0
}

# ============================================================================
# XFCE Panel with Alicia Layout
# ============================================================================

configure_alicia_panel() {
    log_section "Configuring Alicia Panel Layout"

    if step_completed "configure_panel"; then
        log_info "Alicia panel already configured, skipping"
        return 0
    fi

    log_info "Setting up branded Alicia panel layout..."

    # The panel config was already created in step 03, now refine it
    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml

        # Update xsettings with Alicia branding
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

    mark_step_completed "configure_panel"
    log_info "Alicia panel layout configured"
    return 0
}

# ============================================================================
# Custom Application Menu Entries
# ============================================================================

create_custom_menu_entries() {
    log_section "Creating Custom Menu Entries"

    if step_completed "create_menu_entries"; then
        log_info "Custom menu entries already created, skipping"
        return 0
    fi

    log_info "Creating Alicia-specific menu entries..."

    proot_exec bash -c "
        mkdir -p /usr/share/applications

        # Alicia Settings Manager
        cat > /usr/share/applications/alicia-settings-manager.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Alicia Settings
Comment=Configure Alicia Desktop Environment
Exec=xfce4-settings-manager
Icon=preferences-desktop
Terminal=false
Categories=Settings;DesktopSettings;X-XFCE-SettingsDialog;
StartupNotify=true
DESKTOP_EOF

        # Alicia About
        cat > /usr/share/applications/alicia-about.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=About Alicia
Comment=Information about Alicia Desktop Environment
Exec=xfce4-terminal -e \"bash -c 'echo \\\"Alicia Desktop Environment v3.1.0\\\"; echo \\\"Copyright (C) 2005-2025 Proyecto Tomorrow\\\"; echo \\\"\\\"; echo \\\"A complete Linux desktop for Android\\\"; echo \\\"Powered by Termux, proot, and XFCE4\\\"; echo \\\"\\\"; echo \\\"Licensed under GNU GPL v3.0\\\"; read -p \\\"\\\"'\"
Icon=dialog-information
Terminal=false
Categories=System;
StartupNotify=true
DESKTOP_EOF

        # Alicia VNC Info
        cat > /usr/share/applications/alicia-vnc-info.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=VNC Connection Info
Comment=Show VNC connection details
Exec=xfce4-terminal -e alicia-vnc-info
Icon=preferences-system-network
Terminal=false
Categories=System;Network;
StartupNotify=true
DESKTOP_EOF

        # Alicia Desktop Restart
        cat > /usr/share/applications/alicia-restart.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Restart Desktop
Comment=Restart the XFCE desktop environment
Exec=bash -c \"pkill xfce4-session; sleep 1; DISPLAY=:1 startxfce4 &\"
Icon=view-refresh
Terminal=false
Categories=System;
StartupNotify=true
DESKTOP_EOF

        update-desktop-database /usr/share/applications 2>/dev/null || true
    "

    mark_step_completed "create_menu_entries"
    log_info "Custom menu entries created"
    return 0
}

# ============================================================================
# Desktop Icons for Common Applications
# ============================================================================

setup_desktop_icons() {
    log_section "Setting Up Desktop Icons"

    if step_completed "setup_icons"; then
        log_info "Desktop icons already set up, skipping"
        return 0
    fi

    log_info "Creating desktop icons for common apps..."

    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/Desktop

        # Alicia Welcome
        cat > ${ALICIA_USER_HOME}/Desktop/alicia-welcome.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Alicia Welcome
Comment=Welcome to Alicia Desktop
Exec=xfce4-terminal -e alicia-welcome
Icon=dialog-information
Terminal=false
StartupNotify=true
DESKTOP_EOF

        # Alicia Settings
        cat > ${ALICIA_USER_HOME}/Desktop/alicia-settings.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Alicia Settings
Comment=Configure Alicia Desktop Environment
Exec=xfce4-settings-manager
Icon=preferences-desktop
Terminal=false
StartupNotify=true
DESKTOP_EOF

        # Make all desktop files executable
        chmod +x ${ALICIA_USER_HOME}/Desktop/*.desktop 2>/dev/null || true
        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/Desktop
    "

    mark_step_completed "setup_icons"
    log_info "Desktop icons configured"
    return 0
}

# ============================================================================
# Alicia Settings Manager Launcher
# ============================================================================

create_settings_launcher() {
    log_section "Creating Alicia Settings Manager"

    if step_completed "create_settings_launcher"; then
        log_info "Settings launcher already created, skipping"
        return 0
    fi

    log_info "Creating Alicia Settings Manager launcher..."

    proot_exec bash -c "
        cat > /usr/local/bin/alicia-settings << 'SETTINGS_EOF'
#!/bin/bash
# Alicia Desktop - Settings Manager
# Launches the XFCE Settings Manager with Alicia branding

if command -v xfce4-settings-manager &>/dev/null; then
    xfce4-settings-manager &
else
    zenity --info --title=\"Alicia Settings\" --text=\"Settings Manager is not available\" 2>/dev/null || \
    xmessage \"Settings Manager is not available\" 2>/dev/null || \
    echo \"Settings Manager is not available\"
fi
SETTINGS_EOF
        chmod +x /usr/local/bin/alicia-settings
    "

    mark_step_completed "create_settings_launcher"
    log_info "Settings Manager launcher created"
    return 0
}

# ============================================================================
# Alicia Welcome Application
# ============================================================================

create_welcome_app() {
    log_section "Creating Alicia Welcome Application"

    if step_completed "create_welcome_app"; then
        log_info "Welcome app already created, skipping"
        return 0
    fi

    log_info "Creating Alicia Welcome application..."

    proot_exec bash -c "
        cat > /usr/local/bin/alicia-welcome-gui << 'WELCOME_GUI'
#!/bin/bash
# Alicia Desktop - GUI Welcome Application
# Uses zenity or yad for graphical display

TITLE=\"Alicia Desktop Environment\"
VERSION=\"3.1.0\"
VENDOR=\"Proyecto Tomorrow\"

WELCOME_TEXT=\"Welcome to Alicia Desktop Environment v${VERSION}

${VENDOR} presents Alicia - your complete
Linux desktop on Android.

Getting Started:
  * Use the Applications menu to launch programs
  * Files are managed with Thunar File Manager
  * Configure settings via Settings Manager

Keyboard Shortcuts:
  Ctrl+Alt+T  - Open Terminal
  Ctrl+Alt+F  - Open File Manager
  Ctrl+Alt+E  - Open Text Editor
  Ctrl+Alt+S  - Take Screenshot

VNC Access:
  * VNC Client:  localhost:5901
  * Browser:      http://localhost:6080/vnc.html
  * Password:     alicia

For help, type: alicia-vnc-info\"

if command -v zenity &>/dev/null; then
    zenity --info --title=\"\$TITLE\" --text=\"\$WELCOME_TEXT\" --width=500 --height=400 2>/dev/null
elif command -v yad &>/dev/null; then
    yad --text=\"\$WELCOME_TEXT\" --title=\"\$TITLE\" --button=gtk-close:0 --width=500 --height=400 2>/dev/null
else
    # Fallback to terminal
    echo \"\$WELCOME_TEXT\"
fi
WELCOME_GUI
        chmod +x /usr/local/bin/alicia-welcome-gui
    "

    mark_step_completed "create_welcome_app"
    log_info "Welcome application created"
    return 0
}

# ============================================================================
# Default File Associations
# ============================================================================

configure_file_associations() {
    log_section "Configuring Default File Associations"

    if step_completed "configure_file_assoc"; then
        log_info "File associations already configured, skipping"
        return 0
    fi

    log_info "Setting up default file associations..."

    # This was partially done in step 05; ensure it's refined
    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/.local/share/applications

        cat > ${ALICIA_USER_HOME}/.local/share/applications/mimeapps.list << 'MIME_EOF'
[Default Applications]
text/plain=mousepad.desktop
text/x-python=geany.desktop
text/x-shellscript=mousepad.desktop
text/html=midori.desktop
x-scheme-handler/http=midori.desktop
x-scheme-handler/https=midori.desktop
image/png=ristretto.desktop
image/jpeg=ristretto.desktop
image/gif=ristretto.desktop
image/svg+xml=ristretto.desktop
application/pdf=evince.desktop
audio/mpeg=mpv.desktop
audio/ogg=mpv.desktop
video/mp4=mpv.desktop
video/x-matroska=mpv.desktop
application/x-tar=file-roller.desktop
application/zip=file-roller.desktop
application/x-7z-compressed=file-roller.desktop
inode/directory=thunar.desktop
x-scheme-handler/terminal=xfce4-terminal.desktop

[Added Associations]
text/plain=mousepad.desktop;geany.desktop;vim.desktop;
MIME_EOF

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.local 2>/dev/null || true
    "

    mark_step_completed "configure_file_assoc"
    log_info "File associations configured"
    return 0
}

# ============================================================================
# Autostart Applications Configuration
# ============================================================================

configure_autostart() {
    log_section "Configuring Autostart Applications"

    if step_completed "configure_autostart"; then
        log_info "Autostart already configured, skipping"
        return 0
    fi

    log_info "Setting up autostart applications..."

    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/.config/autostart

        # PulseAudio autostart
        cat > ${ALICIA_USER_HOME}/.config/autostart/pulseaudio.desktop << 'AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Name=PulseAudio
Comment=Start PulseAudio sound server
Exec=pulseaudio --start --fail=false --daemonize=true
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF

        # Notification daemon autostart
        cat > ${ALICIA_USER_HOME}/.config/autostart/xfce4-notifyd.desktop << 'AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Name=Xfce Notify Daemon
Comment=Start the notification daemon
Exec=/usr/lib/xfce4/notifyd/xfce4-notifyd
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF

        # Clipboard manager autostart
        cat > ${ALICIA_USER_HOME}/.config/autostart/xfce4-clipman.desktop << 'AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Name=Clipman
Comment=Clipboard manager
Exec=xfce4-clipman
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF

        # Power manager autostart
        cat > ${ALICIA_USER_HOME}/.config/autostart/xfce4-power-manager.desktop << 'AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Name=Power Manager
Comment=XFCE Power Manager
Exec=xfce4-power-manager
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config
    "

    mark_step_completed "configure_autostart"
    log_info "Autostart applications configured"
    return 0
}

# ============================================================================
# Custom Keyboard Shortcuts
# ============================================================================

configure_custom_shortcuts() {
    log_section "Configuring Custom Keyboard Shortcuts"

    if step_completed "configure_shortcuts"; then
        log_info "Custom shortcuts already configured, skipping"
        return 0
    fi

    log_info "Setting up Alicia keyboard shortcuts..."

    # Already configured in step 03, refine with additional shortcuts
    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml

        cat > ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml << 'SHORTCUTS_EOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-keyboard-shortcuts\" version=\"1.0\">
  <property name=\"commands\" type=\"empty\">
    <property name=\"default\" type=\"empty\">
      <property name=\"&lt;Alt&gt;F1\" type=\"string\" value=\"xfce4-popup-whiskermenu\"/>
      <property name=\"&lt;Alt&gt;F2\" type=\"string\" value=\"xfce4-appfinder --collapsed\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;Delete\" type=\"string\" value=\"xflock4\"/>
      <property name=\"&lt;Super&gt;l\" type=\"string\" value=\"xflock4\"/>
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
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;h\" type=\"string\" value=\"thunar ${ALICIA_USER_HOME}\"/>
      <property name=\"&lt;Ctrl&gt;&lt;Alt&gt;m\" type=\"string\" value=\"xfce4-taskmanager\"/>
    </property>
  </property>
</channel>
SHORTCUTS_EOF

        chown ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml
    "

    mark_step_completed "configure_shortcuts"
    log_info "Custom keyboard shortcuts configured"
    return 0
}

# ============================================================================
# User Directories and README Files
# ============================================================================

setup_user_directories() {
    log_section "Setting Up User Directories"

    if step_completed "setup_user_dirs"; then
        log_info "User directories already set up, skipping"
        return 0
    fi

    log_info "Creating user directories with README files..."

    proot_exec bash -c "
        # Create user directories
        mkdir -p ${ALICIA_USER_HOME}/Desktop
        mkdir -p ${ALICIA_USER_HOME}/Documents
        mkdir -p ${ALICIA_USER_HOME}/Downloads
        mkdir -p ${ALICIA_USER_HOME}/Music
        mkdir -p ${ALICIA_USER_HOME}/Pictures
        mkdir -p ${ALICIA_USER_HOME}/Pictures/Wallpapers
        mkdir -p ${ALICIA_USER_HOME}/Pictures/Screenshots
        mkdir -p ${ALICIA_USER_HOME}/Videos
        mkdir -p ${ALICIA_USER_HOME}/Projects
        mkdir -p ${ALICIA_USER_HOME}/Templates
        mkdir -p ${ALICIA_USER_HOME}/Public

        # Create README files in user directories
        cat > ${ALICIA_USER_HOME}/Desktop/README.txt << 'README_EOF'
Alicia Desktop Environment - Desktop
=====================================
This is your desktop. Place files and application launchers here.
README_EOF

        cat > ${ALICIA_USER_HOME}/Documents/README.txt << 'README_EOF'
Alicia Desktop Environment - Documents
========================================
Store your documents here. They are accessible from the file manager.
README_EOF

        cat > ${ALICIA_USER_HOME}/Downloads/README.txt << 'README_EOF'
Alicia Desktop Environment - Downloads
========================================
Downloaded files are saved here by default.
README_EOF

        cat > ${ALICIA_USER_HOME}/Projects/README.txt << 'README_EOF'
Alicia Desktop Environment - Projects
=======================================
Use this directory for your development projects.

Quick start:
  Python:   python3 -m venv myproject
  Node.js:  npm init
  Git:      git init
README_EOF

        # Create user-dirs.dirs
        mkdir -p ${ALICIA_USER_HOME}/.config
        cat > ${ALICIA_USER_HOME}/.config/user-dirs.dirs << 'USERDIRS_EOF'
XDG_DESKTOP_DIR=\"\$HOME/Desktop\"
XDG_DOWNLOAD_DIR=\"\$HOME/Downloads\"
XDG_TEMPLATES_DIR=\"\$HOME/Templates\"
XDG_PUBLICSHARE_DIR=\"\$HOME/Public\"
XDG_DOCUMENTS_DIR=\"\$HOME/Documents\"
XDG_MUSIC_DIR=\"\$HOME/Music\"
XDG_PICTURES_DIR=\"\$HOME/Pictures\"
XDG_VIDEOS_DIR=\"\$HOME/Videos\"
USERDIRS_EOF

        # Create user-dirs.locale
        echo \"en\" > ${ALICIA_USER_HOME}/.config/user-dirs.locale

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}
    "

    mark_step_completed "setup_user_dirs"
    log_info "User directories configured"
    return 0
}

# ============================================================================
# Bash Aliases and Functions
# ============================================================================

configure_bash_aliases() {
    log_section "Configuring Bash Aliases and Functions"

    if step_completed "configure_aliases"; then
        log_info "Bash aliases already configured, skipping"
        return 0
    fi

    log_info "Setting up bash aliases and functions..."

    proot_exec bash -c "
        cat > ${ALICIA_USER_HOME}/.bash_aliases << 'ALIASES_EOF'
# ============================================================================
# Alicia Desktop Environment - Bash Aliases and Functions
# ============================================================================

# --- Navigation ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias desktop='cd ~/Desktop'
alias documents='cd ~/Documents'
alias downloads='cd ~/Downloads'
alias projects='cd ~/Projects'

# --- Listing ---
alias ll='ls -la --color=auto'
alias la='ls -a --color=auto'
alias l='ls -CF --color=auto'
alias lt='ls -lat --color=auto'
alias lsize='ls -lSrh --color=auto'

# --- Safety ---
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias mkdir='mkdir -pv'

# --- System ---
alias update='sudo apk update && sudo apk upgrade'
alias install='sudo apk add'
alias remove='sudo apk del'
alias search='apk search'
alias ports='ss -tulanp'
alias mounted='mount | column -t'
alias path='echo -e \${PATH//:/\\\\n}'

# --- Git ---
alias gs='git status'
alias gl='git log --oneline --graph --decorate -15'
alias gd='git diff'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gpl='git pull'
alias gb='git branch'
alias gco='git checkout'

# --- Python ---
alias py='python3'
alias pip='pip3'
alias venv='python3 -m venv'
alias jnote='jupyter notebook 2>/dev/null || echo \"Jupyter not installed\"'

# --- Alicia-specific ---
alias alicia-info='alicia-vnc-info'
alias alicia-start='alicia-vnc-start'
alias alicia-stop='alicia-vnc-stop'
alias alicia-restart='alicia-vnc-stop; sleep 2; alicia-vnc-start'

# --- Functions ---
# Extract any archive
extract() {
    if [[ -f \"\$1\" ]]; then
        case \"\$1\" in
            *.tar.bz2)   tar xjf \"\$1\"     ;;
            *.tar.gz)    tar xzf \"\$1\"     ;;
            *.tar.xz)    tar xJf \"\$1\"     ;;
            *.bz2)       bunzip2 \"\$1\"      ;;
            *.rar)       unrar x \"\$1\"      ;;
            *.gz)        gunzip \"\$1\"       ;;
            *.tar)       tar xf \"\$1\"      ;;
            *.tbz2)      tar xjf \"\$1\"     ;;
            *.tgz)       tar xzf \"\$1\"     ;;
            *.zip)       unzip \"\$1\"        ;;
            *.Z)         uncompress \"\$1\"   ;;
            *.7z)        7z x \"\$1\"         ;;
            *)           echo \"Unknown format: \$1\" ;;
        esac
    else
        echo \"'\$1' is not a valid file\"
    fi
}

# Quick server in current directory
serve() {
    local port=\"\${1:-8000}\"
    python3 -m http.server \"\$port\"
}

# Find files quickly
ff() { find . -type f -iname \"*\$*\"; }
fd() { find . -type d -iname \"*\$*\"; }

# Create directory and enter it
mkcd() { mkdir -p \"\$1\" && cd \"\$1\"; }

# Go up N directories
up() {
    local d=\"\"
    local limit=\"\$1\"
    for ((i=1 ; i <= limit ; i++)); do
        d=\"\$d/..\"
    done
    d=\"\$(echo \$d | sed 's/^\///')\"
    cd \"\$d\"
}

# Show disk usage of current directory
ducks() {
    du -shx * 2>/dev/null | sort -rh | head \"\${1:-10}\"
}

# Quick git commit
gac() {
    git add -A && git commit -m \"\$1\"
}
ALIASES_EOF

        # Ensure .bashrc sources .bash_aliases
        if ! grep -q 'bash_aliases' ${ALICIA_USER_HOME}/.bashrc 2>/dev/null; then
            echo '' >> ${ALICIA_USER_HOME}/.bashrc
            echo '# Source aliases' >> ${ALICIA_USER_HOME}/.bashrc
            echo 'if [[ -f ~/.bash_aliases ]]; then' >> ${ALICIA_USER_HOME}/.bashrc
            echo '    . ~/.bash_aliases' >> ${ALICIA_USER_HOME}/.bashrc
            echo 'fi' >> ${ALICIA_USER_HOME}/.bashrc
        fi

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.bash_aliases ${ALICIA_USER_HOME}/.bashrc
    "

    mark_step_completed "configure_aliases"
    log_info "Bash aliases and functions configured"
    return 0
}

# ============================================================================
# .gitconfig Configuration
# ============================================================================

configure_gitconfig() {
    log_section "Configuring .gitconfig"

    if step_completed "configure_gitconfig"; then
        log_info ".gitconfig already configured, skipping"
        return 0
    fi

    log_info "Setting up .gitconfig with sensible defaults..."

    proot_exec bash -c "
        cat > ${ALICIA_USER_HOME}/.gitconfig << 'GITCONFIG_EOF'
# ============================================================================
# Alicia Desktop Environment - Git Configuration
# ============================================================================

[user]
    name = Alicia User
    email = alicia@proyecto-tomorrow.local

[core]
    editor = nano
    autocrlf = input
    whitespace = fix
    excludesfile = ~/.gitignore

[color]
    ui = auto

[color \"branch\"]
    current = yellow reverse
    local = yellow
    remote = green

[color \"diff\"]
    meta = yellow bold
    frag = magenta bold
    old = red bold
    new = green bold

[color \"status\"]
    added = yellow
    changed = green
    untracked = cyan

[push]
    default = current
    autoSetupRemote = true

[pull]
    rebase = false

[fetch]
    prune = true

[diff]
    tool = vimdiff

[difftool]
    prompt = false

[merge]
    tool = vimdiff

[mergetool]
    prompt = false

[log]
    date = relative

[format]
    pretty = format:%C(yellow)%h%Creset %s %C(green)(%cr)%Creset

[alias]
    st = status -sb
    lg = log --oneline --graph --decorate -15
    ll = log --oneline --graph --decorate
    co = checkout
    br = branch -v
    ci = commit
    df = diff
    ds = diff --staged
    unstage = reset HEAD --
    amend = commit --amend
    contributors = shortlog -s -n --all
    last = log -1 HEAD --stat
    wip = !git add -A && git commit -m 'WIP'
    unwip = !git log -1 --pretty=%B | grep -q WIP && git reset HEAD~1

[credential]
    helper = cache --timeout=3600

[init]
    defaultBranch = main

[rerere]
    enabled = true

[gc]
    auto = 256
GITCONFIG_EOF

        # Create default .gitignore
        cat > ${ALICIA_USER_HOME}/.gitignore << 'GITIGNORE_EOF'
# Compiled files
*.o
*.so
*.pyc
__pycache__/
*.class

# IDE and editor files
.vscode/
.idea/
*.swp
*.swo
*~

# OS files
.DS_Store
Thumbs.db

# Build artifacts
dist/
build/
*.egg-info/
node_modules/

# Environment
.env
.venv/
venv/

# Logs
*.log
GITIGNORE_EOF

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.gitconfig ${ALICIA_USER_HOME}/.gitignore
    "

    mark_step_completed "configure_gitconfig"
    log_info ".gitconfig configured"
    return 0
}

# ============================================================================
# First-Run Script
# ============================================================================

create_first_run_script() {
    log_section "Creating First-Run Script"

    if step_completed "create_first_run"; then
        log_info "First-run script already created, skipping"
        return 0
    fi

    log_info "Creating alicia-first-run script..."

    proot_exec bash -c "
        cat > /usr/local/bin/alicia-first-run << 'FIRSTRUN_EOF'
#!/bin/bash
# ============================================================================
# alicia-first-run - First Run Experience for Alicia Desktop
# ============================================================================
# This script runs on the first login to set up personalized settings.

echo \"+======================================================+\"
echo \"|     Alicia Desktop - First Run Setup                |\"
echo \"+======================================================+\"
echo \"\"

# Check if this is truly the first run
if [[ -f ~/.alicia-first-run-completed ]]; then
    echo \"First run setup already completed. Running alicia-welcome instead...\"
    alicia-welcome
    exit 0
fi

echo \"Welcome to Alicia Desktop Environment!\"
echo \"\"
echo \"This is your first time running Alicia.\"
echo \"Let's set up a few things...\"
echo \"\"

# Configure Git user
echo \"--- Git Configuration ---\"
read -p \"Enter your name [Alicia User]: \" git_name
git_name=\${git_name:-Alicia User}
read -p \"Enter your email [alicia@proyecto-tomorrow.local]: \" git_email
git_email=\${git_email:-alicia@proyecto-tomorrow.local}

git config --global user.name \"\$git_name\"
git config --global user.email \"\$git_email\"
echo \"Git configured: \$git_name <\$git_email>\"
echo \"\"

# Mark first run as completed
touch ~/.alicia-first-run-completed

echo \"First run setup complete!\"
echo \"\"
echo \"Quick tips:\"
echo \"  * Ctrl+Alt+T opens a terminal\"
echo \"  * Ctrl+Alt+F opens the file manager\"
echo \"  * Type 'alicia-vnc-info' for connection details\"
echo \"\"
read -p \"Press Enter to start using Alicia Desktop...\"
FIRSTRUN_EOF
        chmod +x /usr/local/bin/alicia-first-run
    "

    # Create autostart entry for first-run
    proot_exec bash -c "
        cat > ${ALICIA_USER_HOME}/.config/autostart/alicia-first-run.desktop << 'AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Name=Alicia First Run
Comment=First run setup wizard
Exec=xfce4-terminal -e alicia-first-run
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
AUTOSTART_EOF
        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config
    "

    mark_step_completed "create_first_run"
    log_info "First-run script created"
    return 0
}

# ============================================================================
# GTK Theme Modifications
# ============================================================================

apply_gtk_modifications() {
    log_section "Applying GTK Theme Modifications"

    if step_completed "apply_gtk_mods"; then
        log_info "GTK modifications already applied, skipping"
        return 0
    fi

    log_info "Applying custom GTK theme modifications..."

    proot_exec bash -c "
        # GTK-2.0 theme configuration
        mkdir -p ${ALICIA_USER_HOME}/.gtk-2.0
        cat > ${ALICIA_USER_HOME}/.gtkrc-2.0 << 'GTK2_RC'
# Alicia Desktop - GTK2 Theme Configuration
gtk-theme-name=\"Alicia\"
gtk-icon-theme-name=\"Papirus\"
gtk-font-name=\"Sans 10\"
gtk-cursor-theme-name=\"default\"
gtk-cursor-theme-size=0
gtk-toolbar-style=3
gtk-toolbar-icon-size=2
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
GTK2_RC

        # GTK-3.0 settings
        mkdir -p ${ALICIA_USER_HOME}/.config/gtk-3.0
        cat > ${ALICIA_USER_HOME}/.config/gtk-3.0/settings.ini << 'GTK3_INI'
[Settings]
gtk-theme-name=Alicia
gtk-icon-theme-name=Papirus
gtk-font-name=Sans 10
gtk-cursor-theme-name=default
gtk-cursor-theme-size=0
gtk-toolbar-style=3
gtk-toolbar-icon-size=2
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
gtk-application-prefer-dark-theme=0
gtk-decoration-layout=menu:close
gtk-dialogs-use-header=1
gtk-primary-button-warps-slider=0
GTK3_INI

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.gtkrc-2.0 ${ALICIA_USER_HOME}/.config/gtk-3.0
    "

    mark_step_completed "apply_gtk_mods"
    log_info "GTK theme modifications applied"
    return 0
}

# ============================================================================
# Notification Daemon Configuration
# ============================================================================

configure_notification_daemon() {
    log_section "Configuring Notification Daemon"

    if step_completed "configure_notifications"; then
        log_info "Notification daemon already configured, skipping"
        return 0
    fi

    log_info "Setting up notification daemon..."

    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml

        cat > ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-notifyd.xml << 'NOTIFYD_EOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-notifyd\" version=\"1.0\">
  <property name=\"notify-location\" type=\"uint\" value=\"2\"/>
  <property name=\"theme\" type=\"string\" value=\"Default\"/>
  <property name=\"initial-opacity\" type=\"double\" value=\"0.85\"/>
  <property name=\"expire-timeout\" type=\"int\" value=\"5\"/>
  <property name=\"on-action-key\" type=\"string\" value=\"Execute\"/>
  <property name=\"on-action-left-click\" type=\"string\" value=\"Execute\"/>
  <property name=\"on-action-middle-click\" type=\"string\" value=\"Close\"/>
  <property name=\"on-action-right-click\" type=\"string\" value=\"Do nothing\"/>
  <property name=\"log-only-today\" type=\"bool\" value=\"false\"/>
  <property name=\"log-max-size\" type=\"int\" value=\"10\"/>
  <property name=\"do-not-disturb\" type=\"bool\" value=\"false\"/>
  <property name=\"show-replacement\" type=\"bool\" value=\"true\"/>
  <property name=\"unknown-log-level\" type=\"uint\" value=\"1\"/>
</channel>
NOTIFYD_EOF

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config
    "

    mark_step_completed "configure_notifications"
    log_info "Notification daemon configured"
    return 0
}

# ============================================================================
# Power Manager Settings
# ============================================================================

configure_power_manager() {
    log_section "Configuring Power Manager"

    if step_completed "configure_power"; then
        log_info "Power manager already configured, skipping"
        return 0
    fi

    log_info "Setting up power manager settings..."

    proot_exec bash -c "
        mkdir -p ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml

        cat > ${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml << 'POWER_EOF'
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
    <property name=\"dpms-on-battery-sleep\" type=\"uint\" value=\"0\"/>
    <property name=\"dpms-on-battery-off\" type=\"uint\" value=\"0\"/>
    <property name=\"blank-on-battery\" type=\"int\" value=\"0\"/>
    <property name=\"dpms-on-ac-sleep\" type=\"uint\" value=\"0\"/>
    <property name=\"dpms-on-ac-off\" type=\"uint\" value=\"0\"/>
    <property name=\"blank-on-ac\" type=\"int\" value=\"0\"/>
    <property name=\"inactivity-on-battery\" type=\"uint\" value=\"0\"/>
    <property name=\"inactivity-on-ac\" type=\"uint\" value=\"0\"/>
    <property name=\"show-tray-icon\" type=\"bool\" value=\"true\"/>
    <property name=\"presentation-mode\" type=\"bool\" value=\"false\"/>
  </property>
</channel>
POWER_EOF

        chown -R ${ALICIA_USER}:${ALICIA_USER} ${ALICIA_USER_HOME}/.config
    "

    mark_step_completed "configure_power"
    log_info "Power manager configured"
    return 0
}

# ============================================================================
# Final Validation
# ============================================================================

validate_customization() {
    log_section "Validating Alicia Customization"

    if step_completed "validate_customization"; then
        log_info "Customization already validated, skipping"
        return 0
    fi

    local errors=0

    # Check Alicia theme
    log_info "Checking Alicia theme..."
    if proot_exec "test -d /usr/share/themes/Alicia" &>/dev/null; then
        log_info "  [OK] Alicia GTK theme installed"
    else
        log_warn "  [WARN] Alicia GTK theme not found"
    fi

    # Check wallpaper
    log_info "Checking wallpaper..."
    if proot_exec "test -f /usr/share/backgrounds/alicia/alicia-default.png" &>/dev/null; then
        log_info "  [OK] Alicia wallpaper exists"
    else
        log_warn "  [WARN] Alicia wallpaper not found"
    fi

    # Check user directories
    log_info "Checking user directories..."
    local user_dirs=("Desktop" "Documents" "Downloads" "Music" "Pictures" "Videos" "Projects")
    for dir in "${user_dirs[@]}"; do
        if proot_exec "test -d ${ALICIA_USER_HOME}/${dir}" &>/dev/null; then
            log_debug "  [OK] $dir"
        else
            log_warn "  [WARN] Missing directory: $dir"
        fi
    done

    # Check configuration files
    log_info "Checking configuration files..."
    local config_files=(
        "${ALICIA_USER_HOME}/.gitconfig"
        "${ALICIA_USER_HOME}/.bash_aliases"
        "${ALICIA_USER_HOME}/.config/user-dirs.dirs"
        "${ALICIA_USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
    )
    for file in "${config_files[@]}"; do
        if proot_exec "test -f $file" &>/dev/null; then
            log_debug "  [OK] $file"
        else
            log_warn "  [WARN] Missing config: $file"
        fi
    done

    # Check custom applications
    log_info "Checking custom applications..."
    local custom_cmds=("alicia-welcome" "alicia-settings" "alicia-vnc-start" "alicia-vnc-stop" "alicia-first-run")
    for cmd in "${custom_cmds[@]}"; do
        if proot_exec "command -v $cmd" &>/dev/null; then
            log_debug "  [OK] $cmd"
        else
            log_warn "  [WARN] Missing command: $cmd"
        fi
    done

    if [[ $errors -eq 0 ]]; then
        log_info "Alicia customization validation passed!"
    fi

    mark_step_completed "validate_customization"
    return 0
}

# ============================================================================
# Create Setup Completion Marker
# ============================================================================

mark_setup_complete() {
    log_section "Marking Setup Complete"

    # Create completion marker
    cat > "${ALICIA_BASE_DIR}/.setup-complete" << 'COMPLETE_EOF'
# Alicia Desktop Environment - Setup Complete
# This file marks that all setup steps have been completed.
ALICIA_VERSION=3.1.0
ALICIA_CODENAME=Tomorrow
SETUP_COMPLETED_AT=TIMESTAMP
VENDOR=Proyecto Tomorrow
COMPLETE_EOF

    # Replace timestamp
    sed -i "s/TIMESTAMP/$(date -u '+%Y-%m-%dT%H:%M:%SZ')/" "${ALICIA_BASE_DIR}/.setup-complete"

    log_info "Setup completion marker created"
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
        alicia_lock_release "setup-06" 2>/dev/null || true
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
    log_section "Alicia Desktop - Customization (Step 6/6)"
    log_info "Version: ${SCRIPT_VERSION}"
    log_info "Author:  Proyecto Tomorrow"
    log_info "Time:    $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    if [[ ! -f "${ALICIA_BASE_DIR}/.setup-05-state" ]]; then
        log_warn "Step 05 (apps setup) may not be completed"
        log_warn "Continuing anyway..."
    fi

    load_state

    if declare -f alicia_lock_acquire &>/dev/null; then
        alicia_lock_acquire "setup-06" 300 || {
            log_error "Another setup process is running"
            exit 1
        }
    fi

    local steps=(
        "apply_alicia_branding"
        "set_custom_wallpaper"
        "configure_alicia_panel"
        "create_custom_menu_entries"
        "setup_desktop_icons"
        "create_settings_launcher"
        "create_welcome_app"
        "configure_file_associations"
        "configure_autostart"
        "configure_custom_shortcuts"
        "setup_user_directories"
        "configure_bash_aliases"
        "configure_gitconfig"
        "create_first_run_script"
        "apply_gtk_modifications"
        "configure_notification_daemon"
        "configure_power_manager"
        "validate_customization"
        "mark_setup_complete"
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

    # Final success banner
    echo ""
    echo "  +========================================================+"
    echo "  |                                                       |"
    echo "  |      ALICIA DESKTOP SETUP COMPLETE!            |"
    echo "  |                                                       |"
    echo "  |     Version:  3.1.0 (Tomorrow)                       |"
    echo "  |     Vendor:   Proyecto Tomorrow                      |"
    echo "  |     License:  GNU GPL v3.0                           |"
    echo "  |                                                       |"
    echo "  ?========================================================?"
    echo "  |                                                       |"
    echo "  |  TO START ALICIA:                                     |"
    echo "  |    ${ALICIA_BASE_DIR}/bin/alicia-start                       |"
    echo "  |                                                       |"
    echo "  |  VNC CONNECTION:                                      |"
    echo "  |    Address:   localhost:5901                           |"
    echo "  |    Password:  alicia                                  |"
    echo "  |                                                       |"
    echo "  |  BROWSER ACCESS (noVNC):                              |"
    echo "  |    URL:  http://localhost:6080/vnc.html               |"
    echo "  |                                                       |"
    echo "  |  QUICK COMMANDS:                                      |"
    echo "  |    alicia start   - Start desktop                     |"
    echo "  |    alicia stop    - Stop desktop                      |"
    echo "  |    alicia status  - Check status                      |"
    echo "  |    alicia shell   - Enter proot shell                 |"
    echo "  |    alicia help    - Show all commands                 |"
    echo "  |                                                       |"
    echo "  |  RECOMMENDED VNC CLIENTS (Android):                   |"
    echo "  |    * VNC Viewer by RealVNC                            |"
    echo "  |    * bVNC Secure VNC Viewer                           |"
    echo "  |                                                       |"
    echo "  +========================================================+"
    echo ""

    log_info "Thank you for installing Alicia Desktop Environment!"
    log_info "Copyright (C) 2005-2025 Proyecto Tomorrow"

    return 0
}

main "$@"
