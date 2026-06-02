#!/usr/bin/env python3
"""
Alicia Settings Manager - Main configuration application for the Alicia desktop environment.

Copyright (C) 2024 Proyecto Tomorrow

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

Author: Proyecto Tomorrow
Version: 3.1.0
"""

import os
import sys
import configparser
import subprocess
import shutil
import json
import getpass
import hashlib
from pathlib import Path

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, Gio, GLib, Pango
except (ImportError, ValueError) as e:
    print(f"Error importing GTK3: {e}")
    print("Please install PyGObject: pip install PyGObject")
    sys.exit(1)

# Constants
APP_NAME = "Alicia Settings"
APP_ID = "com.proyectoTomorrow.alicia.settings"
VERSION = "3.1.0"
CONFIG_DIR = os.path.expanduser("~/.config/alicia")
CONFIG_FILE = os.path.join(CONFIG_DIR, "settings.conf")
WALLPAPER_DIR = os.path.join(CONFIG_DIR, "wallpapers")

# Category definitions with icons
CATEGORIES = [
    ("display", "video-display", "Display"),
    ("network", "network-wired", "Network"),
    ("sound", "audio-volume-high", "Sound"),
    ("users", "system-users", "Users"),
    ("applications", "applications-other", "Applications"),
    ("system", "system-run", "System"),
    ("about", "help-about", "About"),
]


class SettingsManager:
    """Core settings management class handling configuration persistence."""

    def __init__(self):
        self.config = configparser.ConfigParser()
        self._ensure_config_dir()
        self.load()

    def _ensure_config_dir(self):
        """Ensure configuration directory exists."""
        os.makedirs(CONFIG_DIR, exist_ok=True)
        os.makedirs(WALLPAPER_DIR, exist_ok=True)

    def load(self):
        """Load settings from the configuration file."""
        if os.path.exists(CONFIG_FILE):
            try:
                self.config.read(CONFIG_FILE)
            except configparser.Error as e:
                print(f"Warning: Could not read config file: {e}")
                self.config = configparser.ConfigParser()
        self._ensure_defaults()

    def _ensure_defaults(self):
        """Ensure all default sections and keys exist."""
        defaults = {
            'Display': {
                'resolution': '1280x720',
                'vnc_port': '5900',
                'vnc_password': '',
                'wallpaper': '',
                'theme': 'Adwaita',
                'font': 'Sans 10',
                'icon_theme': 'Adwaita',
                'scaling': '1.0',
            },
            'Network': {
                'dns_primary': '8.8.8.8',
                'dns_secondary': '8.8.4.4',
                'proxy_enabled': 'false',
                'proxy_host': '',
                'proxy_port': '8080',
                'ssh_enabled': 'true',
                'ssh_port': '22',
                'hostname': 'alicia',
            },
            'Sound': {
                'volume': '80',
                'muted': 'false',
                'device': 'default',
            },
            'Users': {
                'default_user': getpass.getuser(),
            },
            'Applications': {
                'default_browser': 'firefox',
                'default_terminal': 'alicia-terminal',
                'default_editor': 'alicia-text-editor',
                'default_filemanager': 'alicia-filemanager',
            },
            'System': {
                'auto_backup': 'false',
                'backup_location': os.path.expanduser("~/alicia-backup"),
                'swap_size': '512',
            },
        }
        for section, keys in defaults.items():
            if not self.config.has_section(section):
                self.config.add_section(section)
            for key, value in keys.items():
                if not self.config.has_option(section, key):
                    self.config.set(section, key, value)

    def save(self):
        """Save current settings to the configuration file."""
        try:
            with open(CONFIG_FILE, 'w') as f:
                self.config.write(f)
            return True
        except (IOError, OSError) as e:
            print(f"Error saving config: {e}")
            return False

    def get(self, section, key, fallback=''):
        """Get a configuration value."""
        return self.config.get(section, key, fallback=fallback)

    def set(self, section, key, value):
        """Set a configuration value."""
        if not self.config.has_section(section):
            self.config.add_section(section)
        self.config.set(section, key, str(value))

    def get_section(self, section):
        """Get all key-value pairs in a section."""
        if self.config.has_section(section):
            return dict(self.config.items(section))
        return {}


class DisplayPage(Gtk.Box):
    """Display settings page."""

    def __init__(self, settings_mgr):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.settings = settings_mgr
        self.set_margin_top(18)
        self.set_margin_bottom(18)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._build_ui()

    def _build_ui(self):
        """Build the display settings UI."""
        lbl = Gtk.Label(label="Display Settings")
        lbl.set_halign(Gtk.Align.START)
        lbl.get_style_context().add_class("title-2")
        self.pack_start(lbl, False, False, 0)

        grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        grid.set_margin_top(12)
        row = 0

        # Resolution
        res_label = Gtk.Label(label="Resolution:", halign=Gtk.Align.END)
        self.res_combo = Gtk.ComboBoxText()
        for res in ["640x480", "800x600", "1024x768", "1280x720",
                     "1280x800", "1366x768", "1600x900", "1920x1080"]:
            self.res_combo.append_text(res)
        current_res = self.settings.get('Display', 'resolution')
        self._set_combo_text(self.res_combo, current_res)
        grid.attach(res_label, 0, row, 1, 1)
        grid.attach(self.res_combo, 1, row, 2, 1)
        row += 1

        # VNC Port
        vnc_port_label = Gtk.Label(label="VNC Port:", halign=Gtk.Align.END)
        self.vnc_port_spin = Gtk.SpinButton.new_with_range(5900, 5999, 1)
        self.vnc_port_spin.set_value(int(self.settings.get('Display', 'vnc_port', '5900')))
        grid.attach(vnc_port_label, 0, row, 1, 1)
        grid.attach(self.vnc_port_spin, 1, row, 2, 1)
        row += 1

        # VNC Password
        vnc_pw_label = Gtk.Label(label="VNC Password:", halign=Gtk.Align.END)
        self.vnc_pw_entry = Gtk.Entry()
        self.vnc_pw_entry.set_visibility(False)
        self.vnc_pw_entry.set_text(self.settings.get('Display', 'vnc_password'))
        self.vnc_pw_entry.set_placeholder_text("Enter VNC password")
        grid.attach(vnc_pw_label, 0, row, 1, 1)
        grid.attach(self.vnc_pw_entry, 1, row, 2, 1)
        row += 1

        # Wallpaper
        wp_label = Gtk.Label(label="Wallpaper:", halign=Gtk.Align.END)
        wp_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.wp_entry = Gtk.Entry()
        self.wp_entry.set_text(self.settings.get('Display', 'wallpaper'))
        self.wp_entry.set_placeholder_text("Select wallpaper image")
        wp_btn = Gtk.Button(label="Browse...")
        wp_btn.connect("clicked", self._on_browse_wallpaper)
        wp_box.pack_start(self.wp_entry, True, True, 0)
        wp_box.pack_start(wp_btn, False, False, 0)
        grid.attach(wp_label, 0, row, 1, 1)
        grid.attach(wp_box, 1, row, 2, 1)
        row += 1

        # Theme
        theme_label = Gtk.Label(label="GTK Theme:", halign=Gtk.Align.END)
        self.theme_combo = Gtk.ComboBoxText()
        themes = self._get_available_themes()
        for theme in themes:
            self.theme_combo.append_text(theme)
        self._set_combo_text(self.theme_combo, self.settings.get('Display', 'theme'))
        grid.attach(theme_label, 0, row, 1, 1)
        grid.attach(self.theme_combo, 1, row, 2, 1)
        row += 1

        # Font
        font_label = Gtk.Label(label="Font:", halign=Gtk.Align.END)
        self.font_btn = Gtk.FontButton()
        current_font = self.settings.get('Display', 'font', 'Sans 10')
        try:
            self.font_btn.set_font(current_font)
        except Exception:
            self.font_btn.set_font("Sans 10")
        grid.attach(font_label, 0, row, 1, 1)
        grid.attach(self.font_btn, 1, row, 2, 1)
        row += 1

        # Icon Theme
        icon_label = Gtk.Label(label="Icon Theme:", halign=Gtk.Align.END)
        self.icon_combo = Gtk.ComboBoxText()
        icon_themes = self._get_available_icon_themes()
        for itheme in icon_themes:
            self.icon_combo.append_text(itheme)
        self._set_combo_text(self.icon_combo, self.settings.get('Display', 'icon_theme'))
        grid.attach(icon_label, 0, row, 1, 1)
        grid.attach(self.icon_combo, 1, row, 2, 1)
        row += 1

        # Scaling
        scale_label = Gtk.Label(label="UI Scaling:", halign=Gtk.Align.END)
        self.scale_combo = Gtk.ComboBoxText()
        for scale in ["0.5", "0.75", "1.0", "1.25", "1.5", "2.0"]:
            self.scale_combo.append_text(scale)
        self._set_combo_text(self.scale_combo, self.settings.get('Display', 'scaling', '1.0'))
        grid.attach(scale_label, 0, row, 1, 1)
        grid.attach(self.scale_combo, 1, row, 2, 1)
        row += 1

        self.pack_start(grid, False, False, 0)

    def _set_combo_text(self, combo, text):
        """Set the active item in a ComboBoxText by text value."""
        model = combo.get_model()
        for i, row in enumerate(model):
            if row[0] == text:
                combo.set_active(i)
                return
        if len(model) > 0:
            combo.set_active(0)

    def _get_available_themes(self):
        """Get list of available GTK themes."""
        themes = ["Adwaita", "Adwaita-dark"]
        theme_dirs = [
            os.path.expanduser("~/.themes"),
            "/usr/share/themes",
            "/usr/local/share/themes",
        ]
        for d in theme_dirs:
            if os.path.isdir(d):
                for name in os.listdir(d):
                    gtk_dir = os.path.join(d, name, "gtk-3.0")
                    if os.path.isdir(gtk_dir) and name not in themes:
                        themes.append(name)
        return sorted(themes)

    def _get_available_icon_themes(self):
        """Get list of available icon themes."""
        themes = ["Adwaita", "hicolor"]
        icon_dirs = [
            os.path.expanduser("~/.icons"),
            "/usr/share/icons",
            "/usr/local/share/icons",
        ]
        for d in icon_dirs:
            if os.path.isdir(d):
                for name in os.listdir(d):
                    theme_file = os.path.join(d, name, "index.theme")
                    if os.path.isfile(theme_file) and name not in themes:
                        themes.append(name)
        return sorted(themes)

    def _on_browse_wallpaper(self, _btn):
        """Handle wallpaper browse button click."""
        dialog = Gtk.FileChooserDialog(
            title="Select Wallpaper",
            parent=self.get_toplevel(),
            action=Gtk.FileChooserAction.OPEN,
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN, Gtk.ResponseType.OK,
        )
        file_filter = Gtk.FileFilter()
        file_filter.set_name("Images")
        for ext in ["png", "jpg", "jpeg", "bmp", "svg", "webp"]:
            file_filter.add_pattern(f"*.{ext}")
        dialog.add_filter(file_filter)
        if dialog.run() == Gtk.ResponseType.OK:
            self.wp_entry.set_text(dialog.get_filename())
        dialog.destroy()

    def apply_settings(self):
        """Apply display settings to the system."""
        res = self.res_combo.get_active_text() or "1280x720"
        self.settings.set('Display', 'resolution', res)
        self.settings.set('Display', 'vnc_port', str(int(self.vnc_port_spin.get_value())))
        self.settings.set('Display', 'vnc_password', self.vnc_pw_entry.get_text())
        self.settings.set('Display', 'wallpaper', self.wp_entry.get_text())

        theme = self.theme_combo.get_active_text() or "Adwaita"
        self.settings.set('Display', 'theme', theme)
        try:
            subprocess.run(
                ["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", theme],
                capture_output=True, timeout=5
            )
        except Exception:
            pass

        self.settings.set('Display', 'font', self.font_btn.get_font_name())
        try:
            subprocess.run(
                ["gsettings", "set", "org.gnome.desktop.interface", "font-name",
                 self.font_btn.get_font_name()],
                capture_output=True, timeout=5
            )
        except Exception:
            pass

        icon_theme = self.icon_combo.get_active_text() or "Adwaita"
        self.settings.set('Display', 'icon_theme', icon_theme)
        try:
            subprocess.run(
                ["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", icon_theme],
                capture_output=True, timeout=5
            )
        except Exception:
            pass

        scale = self.scale_combo.get_active_text() or "1.0"
        self.settings.set('Display', 'scaling', scale)

        # Apply wallpaper if set
        wallpaper = self.wp_entry.get_text()
        if wallpaper and os.path.isfile(wallpaper):
            try:
                subprocess.run(
                    ["xfconf-query", "-c", "xfce4-desktop", "-p",
                     "/backdrop/screen0/monitor0/workspace0/last-image", "-s", wallpaper],
                    capture_output=True, timeout=5
                )
            except Exception:
                pass


class NetworkPage(Gtk.Box):
    """Network settings page."""

    def __init__(self, settings_mgr):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.settings = settings_mgr
        self.set_margin_top(18)
        self.set_margin_bottom(18)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._build_ui()

    def _build_ui(self):
        """Build the network settings UI."""
        lbl = Gtk.Label(label="Network Settings")
        lbl.set_halign(Gtk.Align.START)
        lbl.get_style_context().add_class("title-2")
        self.pack_start(lbl, False, False, 0)

        grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        grid.set_margin_top(12)
        row = 0

        # DNS Primary
        dns1_label = Gtk.Label(label="Primary DNS:", halign=Gtk.Align.END)
        self.dns1_entry = Gtk.Entry()
        self.dns1_entry.set_text(self.settings.get('Network', 'dns_primary'))
        self.dns1_entry.set_placeholder_text("e.g., 8.8.8.8")
        grid.attach(dns1_label, 0, row, 1, 1)
        grid.attach(self.dns1_entry, 1, row, 2, 1)
        row += 1

        # DNS Secondary
        dns2_label = Gtk.Label(label="Secondary DNS:", halign=Gtk.Align.END)
        self.dns2_entry = Gtk.Entry()
        self.dns2_entry.set_text(self.settings.get('Network', 'dns_secondary'))
        self.dns2_entry.set_placeholder_text("e.g., 8.8.4.4")
        grid.attach(dns2_label, 0, row, 1, 1)
        grid.attach(self.dns2_entry, 1, row, 2, 1)
        row += 1

        # Proxy
        proxy_label = Gtk.Label(label="Enable Proxy:", halign=Gtk.Align.END)
        self.proxy_switch = Gtk.Switch()
        proxy_on = self.settings.get('Network', 'proxy_enabled', 'false') == 'true'
        self.proxy_switch.set_active(proxy_on)
        grid.attach(proxy_label, 0, row, 1, 1)
        grid.attach(self.proxy_switch, 1, row, 1, 1)
        row += 1

        # Proxy Host
        ph_label = Gtk.Label(label="Proxy Host:", halign=Gtk.Align.END)
        self.proxy_host_entry = Gtk.Entry()
        self.proxy_host_entry.set_text(self.settings.get('Network', 'proxy_host'))
        grid.attach(ph_label, 0, row, 1, 1)
        grid.attach(self.proxy_host_entry, 1, row, 2, 1)
        row += 1

        # Proxy Port
        pp_label = Gtk.Label(label="Proxy Port:", halign=Gtk.Align.END)
        self.proxy_port_spin = Gtk.SpinButton.new_with_range(1, 65535, 1)
        self.proxy_port_spin.set_value(int(self.settings.get('Network', 'proxy_port', '8080')))
        grid.attach(pp_label, 0, row, 1, 1)
        grid.attach(self.proxy_port_spin, 1, row, 2, 1)
        row += 1

        # SSH
        ssh_label = Gtk.Label(label="Enable SSH:", halign=Gtk.Align.END)
        self.ssh_switch = Gtk.Switch()
        ssh_on = self.settings.get('Network', 'ssh_enabled', 'true') == 'true'
        self.ssh_switch.set_active(ssh_on)
        grid.attach(ssh_label, 0, row, 1, 1)
        grid.attach(self.ssh_switch, 1, row, 1, 1)
        row += 1

        # SSH Port
        sp_label = Gtk.Label(label="SSH Port:", halign=Gtk.Align.END)
        self.ssh_port_spin = Gtk.SpinButton.new_with_range(1, 65535, 1)
        self.ssh_port_spin.set_value(int(self.settings.get('Network', 'ssh_port', '22')))
        grid.attach(sp_label, 0, row, 1, 1)
        grid.attach(self.ssh_port_spin, 1, row, 2, 1)
        row += 1

        # Hostname
        hn_label = Gtk.Label(label="Hostname:", halign=Gtk.Align.END)
        self.hostname_entry = Gtk.Entry()
        self.hostname_entry.set_text(self.settings.get('Network', 'hostname'))
        grid.attach(hn_label, 0, row, 1, 1)
        grid.attach(self.hostname_entry, 1, row, 2, 1)
        row += 1

        # Connection test
        test_btn = Gtk.Button(label="Test Connection")
        test_btn.connect("clicked", self._on_test_connection)
        grid.attach(test_btn, 1, row, 1, 1)
        row += 1

        self.test_result = Gtk.Label(label="")
        grid.attach(self.test_result, 1, row, 2, 1)
        row += 1

        self.pack_start(grid, False, False, 0)

    def _on_test_connection(self, _btn):
        """Test internet connectivity."""
        self.test_result.set_text("Testing...")
        try:
            result = subprocess.run(
                ["ping", "-c", "3", "-W", "5", "8.8.8.8"],
                capture_output=True, text=True, timeout=15
            )
            if result.returncode == 0:
                self.test_result.set_text("✓ Connection successful")
            else:
                self.test_result.set_text("✗ Connection failed")
        except subprocess.TimeoutExpired:
            self.test_result.set_text("✗ Connection timed out")
        except Exception as e:
            self.test_result.set_text(f"✗ Error: {e}")

    def apply_settings(self):
        """Apply network settings to the system."""
        dns1 = self.dns1_entry.get_text().strip()
        dns2 = self.dns2_entry.get_text().strip()
        self.settings.set('Network', 'dns_primary', dns1)
        self.settings.set('Network', 'dns_secondary', dns2)

        # Write resolv.conf if writable
        resolv_path = "/etc/resolv.conf"
        try:
            dns_content = ""
            if dns1:
                dns_content += f"nameserver {dns1}\n"
            if dns2:
                dns_content += f"nameserver {dns2}\n"
            if dns_content:
                with open(resolv_path, 'w') as f:
                    f.write(dns_content)
        except (IOError, OSError):
            pass

        proxy_on = self.proxy_switch.get_active()
        self.settings.set('Network', 'proxy_enabled', 'true' if proxy_on else 'false')
        self.settings.set('Network', 'proxy_host', self.proxy_host_entry.get_text())
        self.settings.set('Network', 'proxy_port', str(int(self.proxy_port_spin.get_value())))

        ssh_on = self.ssh_switch.get_active()
        self.settings.set('Network', 'ssh_enabled', 'true' if ssh_on else 'false')
        self.settings.set('Network', 'ssh_port', str(int(self.ssh_port_spin.get_value())))
        self.settings.set('Network', 'hostname', self.hostname_entry.get_text().strip())


class SoundPage(Gtk.Box):
    """Sound settings page."""

    def __init__(self, settings_mgr):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.settings = settings_mgr
        self.set_margin_top(18)
        self.set_margin_bottom(18)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._build_ui()

    def _build_ui(self):
        """Build the sound settings UI."""
        lbl = Gtk.Label(label="Sound Settings")
        lbl.set_halign(Gtk.Align.START)
        lbl.get_style_context().add_class("title-2")
        self.pack_start(lbl, False, False, 0)

        grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        grid.set_margin_top(12)
        row = 0

        # Volume
        vol_label = Gtk.Label(label="Volume:", halign=Gtk.Align.END)
        self.volume_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, 0, 100, 1
        )
        vol = int(self.settings.get('Sound', 'volume', '80'))
        self.volume_scale.set_value(vol)
        self.volume_scale.set_hexpand(True)
        self.volume_scale.connect("value-changed", self._on_volume_changed)
        grid.attach(vol_label, 0, row, 1, 1)
        grid.attach(self.volume_scale, 1, row, 2, 1)
        row += 1

        # Mute
        mute_label = Gtk.Label(label="Mute:", halign=Gtk.Align.END)
        self.mute_switch = Gtk.Switch()
        muted = self.settings.get('Sound', 'muted', 'false') == 'true'
        self.mute_switch.set_active(muted)
        grid.attach(mute_label, 0, row, 1, 1)
        grid.attach(self.mute_switch, 1, row, 1, 1)
        row += 1

        # Device selection
        dev_label = Gtk.Label(label="Audio Device:", halign=Gtk.Align.END)
        self.device_combo = Gtk.ComboBoxText()
        devices = self._get_audio_devices()
        for dev in devices:
            self.device_combo.append_text(dev)
        current_dev = self.settings.get('Sound', 'device', 'default')
        for i, item in enumerate(self.device_combo.get_model()):
            if item[0] == current_dev:
                self.device_combo.set_active(i)
                break
        if self.device_combo.get_active() == -1 and len(devices) > 0:
            self.device_combo.set_active(0)
        grid.attach(dev_label, 0, row, 1, 1)
        grid.attach(self.device_combo, 1, row, 2, 1)
        row += 1

        self.pack_start(grid, False, False, 0)

    def _get_audio_devices(self):
        """Get list of available audio devices."""
        devices = ["default"]
        try:
            result = subprocess.run(
                ["aplay", "-l"], capture_output=True, text=True, timeout=5
            )
            for line in result.stdout.splitlines():
                if "card" in line.lower():
                    parts = line.strip()
                    if parts not in devices:
                        devices.append(parts)
        except Exception:
            pass
        try:
            result = subprocess.run(
                ["pactl", "list", "short", "sinks"],
                capture_output=True, text=True, timeout=5
            )
            for line in result.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 2 and parts[1] not in devices:
                    devices.append(parts[1])
        except Exception:
            pass
        return devices

    def _on_volume_changed(self, scale):
        """Handle volume slider change."""
        vol = int(scale.get_value())
        try:
            subprocess.run(
                ["amixer", "set", "Master", f"{vol}%"],
                capture_output=True, timeout=5
            )
        except Exception:
            pass
        try:
            subprocess.run(
                ["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{vol}%"],
                capture_output=True, timeout=5
            )
        except Exception:
            pass

    def apply_settings(self):
        """Apply sound settings."""
        vol = int(self.volume_scale.get_value())
        self.settings.set('Sound', 'volume', str(vol))
        muted = self.mute_switch.get_active()
        self.settings.set('Sound', 'muted', 'true' if muted else 'false')
        device = self.device_combo.get_active_text() or 'default'
        self.settings.set('Sound', 'device', device)

        if muted:
            try:
                subprocess.run(["amixer", "set", "Master", "mute"],
                               capture_output=True, timeout=5)
            except Exception:
                pass
        else:
            try:
                subprocess.run(["amixer", "set", "Master", "unmute"],
                               capture_output=True, timeout=5)
            except Exception:
                pass


class UsersPage(Gtk.Box):
    """Users management page."""

    def __init__(self, settings_mgr):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.settings = settings_mgr
        self.set_margin_top(18)
        self.set_margin_bottom(18)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._build_ui()

    def _build_ui(self):
        """Build the users management UI."""
        lbl = Gtk.Label(label="User Management")
        lbl.set_halign(Gtk.Align.START)
        lbl.get_style_context().add_class("title-2")
        self.pack_start(lbl, False, False, 0)

        # User list
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_min_content_height(200)
        scrolled.set_vexpand(True)
        self.user_store = Gtk.ListStore(str, str, str)  # username, home, shell
        self.user_tree = Gtk.TreeView(model=self.user_store)

        for i, (title, width) in enumerate([("Username", 150), ("Home", 250), ("Shell", 200)]):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(title, renderer, text=i)
            col.set_min_width(width)
            self.user_tree.append_column(col)

        scrolled.add(self.user_tree)
        self.pack_start(scrolled, True, True, 0)

        self._refresh_users()

        # Buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        btn_box.set_margin_top(6)

        add_btn = Gtk.Button(label="Add User")
        add_btn.connect("clicked", self._on_add_user)
        btn_box.pack_start(add_btn, False, False, 0)

        del_btn = Gtk.Button(label="Delete User")
        del_btn.connect("clicked", self._on_delete_user)
        btn_box.pack_start(del_btn, False, False, 0)

        pw_btn = Gtk.Button(label="Change Password")
        pw_btn.connect("clicked", self._on_change_password)
        btn_box.pack_start(pw_btn, False, False, 0)

        refresh_btn = Gtk.Button(label="Refresh")
        refresh_btn.connect("clicked", lambda _: self._refresh_users())
        btn_box.pack_start(refresh_btn, False, False, 0)

        self.pack_start(btn_box, False, False, 0)

    def _refresh_users(self):
        """Refresh the user list from the system."""
        self.user_store.clear()
        try:
            with open("/etc/passwd", 'r') as f:
                for line in f:
                    parts = line.strip().split(':')
                    if len(parts) >= 7:
                        username = parts[0]
                        uid = int(parts[2])
                        home = parts[5]
                        shell = parts[6]
                        # Only show regular users (UID >= 1000) and not nobody
                        if uid >= 1000 and username != 'nobody':
                            self.user_store.append([username, home, shell])
        except (IOError, OSError) as e:
            print(f"Error reading /etc/passwd: {e}")

    def _get_selected_user(self):
        """Get the currently selected username."""
        selection = self.user_tree.get_selection()
        model, tree_iter = selection.get_selected()
        if tree_iter is not None:
            return model.get_value(tree_iter, 0)
        return None

    def _on_add_user(self, _btn):
        """Show dialog to add a new user."""
        dialog = Gtk.Dialog(title="Add User", parent=self.get_toplevel(),
                            modal=True, destroy_with_parent=True)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OK, Gtk.ResponseType.OK)
        dialog.set_default_size(350, 200)

        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        grid = Gtk.Grid(row_spacing=8, column_spacing=8)
        grid.attach(Gtk.Label(label="Username:"), 0, 0, 1, 1)
        username_entry = Gtk.Entry()
        grid.attach(username_entry, 1, 0, 1, 1)

        grid.attach(Gtk.Label(label="Full Name:"), 0, 1, 1, 1)
        fullname_entry = Gtk.Entry()
        grid.attach(fullname_entry, 1, 1, 1, 1)

        grid.attach(Gtk.Label(label="Password:"), 0, 2, 1, 1)
        password_entry = Gtk.Entry()
        password_entry.set_visibility(False)
        grid.attach(password_entry, 1, 2, 1, 1)

        box.pack_start(grid, True, True, 0)
        dialog.show_all()

        if dialog.run() == Gtk.ResponseType.OK:
            username = username_entry.get_text().strip()
            fullname = fullname_entry.get_text().strip()
            password = password_entry.get_text()
            if username and password:
                try:
                    subprocess.run(
                        ["useradd", "-m", "-c", fullname, username],
                        capture_output=True, text=True, timeout=10
                    )
                    proc = subprocess.Popen(
                        ["chpasswd"], stdin=subprocess.PIPE, text=True
                    )
                    proc.communicate(input=f"{username}:{password}", timeout=10)
                    self._refresh_users()
                except Exception as e:
                    self._show_error(f"Failed to add user: {e}")
        dialog.destroy()

    def _on_delete_user(self, _btn):
        """Delete the selected user."""
        username = self._get_selected_user()
        if not username:
            self._show_info("Please select a user to delete.")
            return
        if username == getpass.getuser():
            self._show_error("Cannot delete the current user.")
            return

        confirm = Gtk.MessageDialog(
            parent=self.get_toplevel(),
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f"Delete user '{username}' and their home directory?"
        )
        if confirm.run() == Gtk.ResponseType.YES:
            try:
                subprocess.run(
                    ["userdel", "-r", username],
                    capture_output=True, text=True, timeout=10
                )
                self._refresh_users()
            except Exception as e:
                self._show_error(f"Failed to delete user: {e}")
        confirm.destroy()

    def _on_change_password(self, _btn):
        """Change the selected user's password."""
        username = self._get_selected_user()
        if not username:
            self._show_info("Please select a user.")
            return

        dialog = Gtk.Dialog(title="Change Password", parent=self.get_toplevel(),
                            modal=True, destroy_with_parent=True)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OK, Gtk.ResponseType.OK)

        box = dialog.get_content_area()
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_spacing(8)

        box.pack_start(Gtk.Label(label=f"Change password for: {username}"), False, False, 0)
        grid = Gtk.Grid(row_spacing=8, column_spacing=8)

        grid.attach(Gtk.Label(label="New Password:"), 0, 0, 1, 1)
        pw_entry = Gtk.Entry()
        pw_entry.set_visibility(False)
        grid.attach(pw_entry, 1, 0, 1, 1)

        grid.attach(Gtk.Label(label="Confirm:"), 0, 1, 1, 1)
        pw_confirm = Gtk.Entry()
        pw_confirm.set_visibility(False)
        grid.attach(pw_confirm, 1, 1, 1, 1)

        box.pack_start(grid, True, True, 0)
        dialog.show_all()

        if dialog.run() == Gtk.ResponseType.OK:
            pw1 = pw_entry.get_text()
            pw2 = pw_confirm.get_text()
            if pw1 != pw2:
                self._show_error("Passwords do not match.")
            elif not pw1:
                self._show_error("Password cannot be empty.")
            else:
                try:
                    proc = subprocess.Popen(
                        ["chpasswd"], stdin=subprocess.PIPE, text=True
                    )
                    proc.communicate(input=f"{username}:{pw1}", timeout=10)
                except Exception as e:
                    self._show_error(f"Failed to change password: {e}")
        dialog.destroy()

    def _show_error(self, msg):
        """Show an error dialog."""
        dialog = Gtk.MessageDialog(
            parent=self.get_toplevel(),
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text=msg
        )
        dialog.run()
        dialog.destroy()

    def _show_info(self, msg):
        """Show an info dialog."""
        dialog = Gtk.MessageDialog(
            parent=self.get_toplevel(),
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.OK,
            text=msg
        )
        dialog.run()
        dialog.destroy()


class ApplicationsPage(Gtk.Box):
    """Applications settings page."""

    def __init__(self, settings_mgr):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.settings = settings_mgr
        self.set_margin_top(18)
        self.set_margin_bottom(18)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._build_ui()

    def _build_ui(self):
        """Build the applications settings UI."""
        lbl = Gtk.Label(label="Application Settings")
        lbl.set_halign(Gtk.Align.START)
        lbl.get_style_context().add_class("title-2")
        self.pack_start(lbl, False, False, 0)

        # Default applications
        defaults_lbl = Gtk.Label(label="Default Applications")
        defaults_lbl.set_halign(Gtk.Align.START)
        defaults_lbl.get_style_context().add_class("heading")
        self.pack_start(defaults_lbl, False, False, 0)

        grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        grid.set_margin_top(6)
        row = 0

        app_types = [
            ("Web Browser:", 'default_browser'),
            ("Terminal:", 'default_terminal'),
            ("Text Editor:", 'default_editor'),
            ("File Manager:", 'default_filemanager'),
        ]
        self.default_entries = {}
        for label_text, key in app_types:
            label = Gtk.Label(label=label_text, halign=Gtk.Align.END)
            entry = Gtk.Entry()
            entry.set_text(self.settings.get('Applications', key))
            grid.attach(label, 0, row, 1, 1)
            grid.attach(entry, 1, row, 2, 1)
            self.default_entries[key] = entry
            row += 1

        self.pack_start(grid, False, False, 0)

        # Installed applications list
        installed_lbl = Gtk.Label(label="Installed Applications")
        installed_lbl.set_halign(Gtk.Align.START)
        installed_lbl.set_margin_top(12)
        installed_lbl.get_style_context().add_class("heading")
        self.pack_start(installed_lbl, False, False, 0)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_min_content_height(200)
        scrolled.set_vexpand(True)
        self.app_store = Gtk.ListStore(str, str)  # name, category
        self.app_tree = Gtk.TreeView(model=self.app_store)

        for i, (title, width) in enumerate([("Application", 250), ("Category", 150)]):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(title, renderer, text=i)
            col.set_min_width(width)
            self.app_tree.append_column(col)

        scrolled.add(self.app_tree)
        self.pack_start(scrolled, True, True, 0)

        # Buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        btn_box.set_margin_top(6)

        open_btn = Gtk.Button(label="Open Selected")
        open_btn.connect("clicked", self._on_open_app)
        btn_box.pack_start(open_btn, False, False, 0)

        uninstall_btn = Gtk.Button(label="Uninstall Selected")
        uninstall_btn.connect("clicked", self._on_uninstall_app)
        btn_box.pack_start(uninstall_btn, False, False, 0)

        refresh_btn = Gtk.Button(label="Refresh")
        refresh_btn.connect("clicked", lambda _: self._refresh_apps())
        btn_box.pack_start(refresh_btn, False, False, 0)

        self.pack_start(btn_box, False, False, 0)
        self._refresh_apps()

    def _refresh_apps(self):
        """Refresh the installed applications list."""
        self.app_store.clear()
        app_dirs = [
            "/usr/share/applications",
            os.path.expanduser("~/.local/share/applications"),
        ]
        seen = set()
        for app_dir in app_dirs:
            if not os.path.isdir(app_dir):
                continue
            for fname in os.listdir(app_dir):
                if fname.endswith('.desktop') and fname not in seen:
                    seen.add(fname)
                    name = fname.replace('.desktop', '')
                    category = "Application"
                    desktop_path = os.path.join(app_dir, fname)
                    try:
                        with open(desktop_path, 'r', errors='ignore') as f:
                            for line in f:
                                if line.startswith("Name="):
                                    name = line.strip().split("=", 1)[1]
                                elif line.startswith("Categories="):
                                    cats = line.strip().split("=", 1)[1]
                                    category = cats.split(";")[0] if cats else "Application"
                                    break
                    except (IOError, OSError):
                        pass
                    self.app_store.append([name, category])

    def _get_selected_app(self):
        """Get the currently selected application name."""
        selection = self.app_tree.get_selection()
        model, tree_iter = selection.get_selected()
        if tree_iter is not None:
            return model.get_value(tree_iter, 0)
        return None

    def _on_open_app(self, _btn):
        """Open the selected application."""
        app_name = self._get_selected_app()
        if app_name:
            try:
                subprocess.Popen(["gtk-launch", app_name],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                self._show_error(f"Could not launch: {e}")

    def _on_uninstall_app(self, _btn):
        """Attempt to uninstall the selected application."""
        app_name = self._get_selected_app()
        if not app_name:
            return
        confirm = Gtk.MessageDialog(
            parent=self.get_toplevel(),
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f"Uninstall '{app_name}'?"
        )
        if confirm.run() == Gtk.ResponseType.YES:
            try:
                pkg_name = app_name.lower().replace(" ", "-")
                # Try apt first, then apk
                result = subprocess.run(
                    ["apt-get", "remove", "-y", pkg_name],
                    capture_output=True, text=True, timeout=60
                )
                if result.returncode != 0:
                    result = subprocess.run(
                        ["apk", "del", pkg_name],
                        capture_output=True, text=True, timeout=60
                    )
                self._refresh_apps()
            except Exception as e:
                self._show_error(f"Uninstall failed: {e}")
        confirm.destroy()

    def apply_settings(self):
        """Save application default settings."""
        for key, entry in self.default_entries.items():
            self.settings.set('Applications', key, entry.get_text().strip())

    def _show_error(self, msg):
        """Show an error dialog."""
        dialog = Gtk.MessageDialog(
            parent=self.get_toplevel(),
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text=msg
        )
        dialog.run()
        dialog.destroy()


class SystemPage(Gtk.Box):
    """System information and management page."""

    def __init__(self, settings_mgr):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.settings = settings_mgr
        self.set_margin_top(18)
        self.set_margin_bottom(18)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._build_ui()

    def _build_ui(self):
        """Build the system settings UI."""
        lbl = Gtk.Label(label="System Settings")
        lbl.set_halign(Gtk.Align.START)
        lbl.get_style_context().add_class("title-2")
        self.pack_start(lbl, False, False, 0)

        # System info
        info_frame = Gtk.Frame(label="System Information")
        info_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        info_box.set_margin_top(8)
        info_box.set_margin_bottom(8)
        info_box.set_margin_start(12)
        info_box.set_margin_end(12)

        self.info_labels = {}
        for key in ["CPU", "Memory", "Storage"]:
            h_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            h_box.pack_start(Gtk.Label(label=f"{key}:", width_chars=10), False, False, 0)
            val_label = Gtk.Label(label="Detecting...")
            val_label.set_halign(Gtk.Align.START)
            h_box.pack_start(val_label, True, True, 0)
            info_box.pack_start(h_box, False, False, 0)
            self.info_labels[key] = val_label

        info_frame.add(info_box)
        self.pack_start(info_frame, False, False, 0)
        self._update_system_info()

        # Backup section
        backup_frame = Gtk.Frame(label="Backup & Restore")
        backup_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        backup_box.set_margin_top(8)
        backup_box.set_margin_bottom(8)
        backup_box.set_margin_start(12)
        backup_box.set_margin_end(12)

        loc_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        loc_box.pack_start(Gtk.Label(label="Backup Location:"), False, False, 0)
        self.backup_entry = Gtk.Entry()
        self.backup_entry.set_text(self.settings.get('System', 'backup_location'))
        self.backup_entry.set_hexpand(True)
        loc_box.pack_start(self.backup_entry, True, True, 0)
        browse_btn = Gtk.Button(label="Browse...")
        browse_btn.connect("clicked", self._on_browse_backup)
        loc_box.pack_start(browse_btn, False, False, 0)
        backup_box.pack_start(loc_box, False, False, 0)

        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        backup_btn = Gtk.Button(label="Create Backup")
        backup_btn.connect("clicked", self._on_backup)
        btn_row.pack_start(backup_btn, False, False, 0)

        restore_btn = Gtk.Button(label="Restore Backup")
        restore_btn.connect("clicked", self._on_restore)
        btn_row.pack_start(restore_btn, False, False, 0)

        backup_box.pack_start(btn_row, False, False, 0)
        backup_frame.add(backup_box)
        self.pack_start(backup_frame, False, False, 0)

        # Factory reset
        reset_frame = Gtk.Frame(label="Danger Zone")
        reset_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        reset_box.set_margin_top(8)
        reset_box.set_margin_bottom(8)
        reset_box.set_margin_start(12)
        reset_box.set_margin_end(12)

        reset_btn = Gtk.Button(label="Factory Reset")
        reset_btn.get_style_context().add_class("destructive-action")
        reset_btn.connect("clicked", self._on_factory_reset)
        reset_label = Gtk.Label(label="This will reset all Alicia settings to defaults.")
        reset_label.set_line_wrap(True)
        reset_box.pack_start(reset_label, False, False, 0)
        reset_box.pack_start(reset_btn, False, False, 0)
        reset_frame.add(reset_box)
        self.pack_start(reset_frame, False, False, 0)

    def _update_system_info(self):
        """Update system information labels."""
        # CPU
        try:
            with open("/proc/cpuinfo", 'r') as f:
                for line in f:
                    if line.startswith("model name") or line.startswith("Model"):
                        cpu = line.split(":", 1)[1].strip()
                        self.info_labels["CPU"].set_text(cpu)
                        break
                else:
                    self.info_labels["CPU"].set_text("Unknown")
        except (IOError, OSError):
            self.info_labels["CPU"].set_text("Unknown")

        # Memory
        try:
            with open("/proc/meminfo", 'r') as f:
                total = free = 0
                for line in f:
                    if line.startswith("MemTotal"):
                        total = int(line.split()[1])
                    elif line.startswith("MemAvailable"):
                        free = int(line.split()[1])
                        break
                used = total - free
                total_gb = total / 1024 / 1024
                used_gb = used / 1024 / 1024
                self.info_labels["Memory"].set_text(
                    f"{used_gb:.1f} GB / {total_gb:.1f} GB"
                )
        except (IOError, OSError, ValueError):
            self.info_labels["Memory"].set_text("Unknown")

        # Storage
        try:
            usage = shutil.disk_usage("/")
            total_gb = usage.total / (1024 ** 3)
            used_gb = usage.used / (1024 ** 3)
            self.info_labels["Storage"].set_text(
                f"{used_gb:.1f} GB / {total_gb:.1f} GB"
            )
        except Exception:
            self.info_labels["Storage"].set_text("Unknown")

    def _on_browse_backup(self, _btn):
        """Browse for backup location."""
        dialog = Gtk.FileChooserDialog(
            title="Select Backup Location",
            parent=self.get_toplevel(),
            action=Gtk.FileChooserAction.SELECT_FOLDER,
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN, Gtk.ResponseType.OK,
        )
        if dialog.run() == Gtk.ResponseType.OK:
            self.backup_entry.set_text(dialog.get_filename())
        dialog.destroy()

    def _on_backup(self, _btn):
        """Create a backup of settings and user data."""
        backup_loc = self.backup_entry.get_text().strip()
        if not backup_loc:
            self._show_error("Please specify a backup location.")
            return

        try:
            os.makedirs(backup_loc, exist_ok=True)
            timestamp = subprocess.run(
                ["date", "+%Y%m%d_%H%M%S"],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()
            backup_dir = os.path.join(backup_loc, f"alicia-backup-{timestamp}")
            os.makedirs(backup_dir, exist_ok=True)

            # Backup config
            if os.path.exists(CONFIG_DIR):
                dest = os.path.join(backup_dir, "config")
                shutil.copytree(CONFIG_DIR, dest, dirs_exist_ok=True)

            # Backup XFCE config
            xfce_dir = os.path.expanduser("~/.config/xfce4")
            if os.path.isdir(xfce_dir):
                dest = os.path.join(backup_dir, "xfce4")
                shutil.copytree(xfce_dir, dest, dirs_exist_ok=True)

            self._show_info(f"Backup created at: {backup_dir}")
        except Exception as e:
            self._show_error(f"Backup failed: {e}")

    def _on_restore(self, _btn):
        """Restore from a backup."""
        dialog = Gtk.FileChooserDialog(
            title="Select Backup to Restore",
            parent=self.get_toplevel(),
            action=Gtk.FileChooserAction.SELECT_FOLDER,
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN, Gtk.ResponseType.OK,
        )
        if dialog.run() == Gtk.ResponseType.OK:
            backup_path = dialog.get_filename()
            try:
                config_backup = os.path.join(backup_path, "config")
                if os.path.isdir(config_backup):
                    shutil.copytree(config_backup, CONFIG_DIR, dirs_exist_ok=True)
                self._show_info("Backup restored. Please restart Alicia.")
            except Exception as e:
                self._show_error(f"Restore failed: {e}")
        dialog.destroy()

    def _on_factory_reset(self, _btn):
        """Perform a factory reset of all Alicia settings."""
        confirm = Gtk.MessageDialog(
            parent=self.get_toplevel(),
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text="Are you sure you want to factory reset all Alicia settings?"
        )
        confirm.set_property("secondary-text",
                             "This will remove all custom configurations.")
        if confirm.run() == Gtk.ResponseType.YES:
            try:
                if os.path.exists(CONFIG_DIR):
                    shutil.rmtree(CONFIG_DIR)
                os.makedirs(CONFIG_DIR, exist_ok=True)
                self._show_info("Factory reset complete. Please restart Alicia.")
            except Exception as e:
                self._show_error(f"Factory reset failed: {e}")
        confirm.destroy()

    def _show_error(self, msg):
        """Show an error dialog."""
        dialog = Gtk.MessageDialog(
            parent=self.get_toplevel(),
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text=msg
        )
        dialog.run()
        dialog.destroy()

    def _show_info(self, msg):
        """Show an info dialog."""
        dialog = Gtk.MessageDialog(
            parent=self.get_toplevel(),
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.OK,
            text=msg
        )
        dialog.run()
        dialog.destroy()

    def apply_settings(self):
        """Apply system settings."""
        self.settings.set('System', 'backup_location', self.backup_entry.get_text().strip())


class AboutPage(Gtk.Box):
    """About page with version and license information."""

    def __init__(self, settings_mgr):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.settings = settings_mgr
        self.set_margin_top(18)
        self.set_margin_bottom(18)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._build_ui()

    def _build_ui(self):
        """Build the about page UI."""
        lbl = Gtk.Label(label="About Alicia")
        lbl.set_halign(Gtk.Align.START)
        lbl.get_style_context().add_class("title-2")
        self.pack_start(lbl, False, False, 0)

        # Logo area
        logo_frame = Gtk.Frame()
        logo_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        logo_box.set_margin_top(20)
        logo_box.set_margin_bottom(20)

        title = Gtk.Label()
        title.set_markup("<span size='x-large' weight='bold'>Alicia Desktop</span>")
        logo_box.pack_start(title, False, False, 0)

        version = Gtk.Label(label=f"Version {VERSION}")
        logo_box.pack_start(version, False, False, 0)

        org = Gtk.Label()
        org.set_markup("<span size='large'>Proyecto Tomorrow</span>")
        logo_box.pack_start(org, False, False, 0)

        logo_frame.add(logo_box)
        self.pack_start(logo_frame, False, False, 0)

        # Version info
        info_frame = Gtk.Frame(label="Version Information")
        info_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        info_box.set_margin_top(8)
        info_box.set_margin_bottom(8)
        info_box.set_margin_start(12)
        info_box.set_margin_end(12)

        version_items = [
            ("Alicia Desktop:", VERSION),
            ("Settings Manager:", VERSION),
            ("GTK Version:", f"{Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}"),
            ("Python Version:", f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"),
        ]
        for label_text, value in version_items:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            row.pack_start(Gtk.Label(label=label_text, width_chars=20), False, False, 0)
            row.pack_start(Gtk.Label(label=value), False, False, 0)
            info_box.pack_start(row, False, False, 0)

        info_frame.add(info_box)
        self.pack_start(info_frame, False, False, 0)

        # License
        license_frame = Gtk.Frame(label="License")
        license_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        license_box.set_margin_top(8)
        license_box.set_margin_bottom(8)
        license_box.set_margin_start(12)
        license_box.set_margin_end(12)

        license_text = (
            "This program is free software: you can redistribute it and/or modify "
            "it under the terms of the GNU General Public License as published by "
            "the Free Software Foundation, either version 3 of the License, or "
            "(at your option) any later version.\n\n"
            "This program is distributed in the hope that it will be useful, "
            "but WITHOUT ANY WARRANTY; without even the implied warranty of "
            "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE."
        )
        license_label = Gtk.Label(label=license_text)
        license_label.set_line_wrap(True)
        license_label.set_max_width_chars(60)
        license_box.pack_start(license_label, False, False, 0)

        license_frame.add(license_box)
        self.pack_start(license_frame, False, False, 0)

        # Credits
        credits_frame = Gtk.Frame(label="Credits")
        credits_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        credits_box.set_margin_top(8)
        credits_box.set_margin_bottom(8)
        credits_box.set_margin_start(12)
        credits_box.set_margin_end(12)

        credits_label = Gtk.Label(label="Developed by Proyecto Tomorrow\n"
                                        "Powered by GTK3, Python, and XFCE4\n"
                                        "Running on Termux + proot + VNC")
        credits_label.set_justify(Gtk.Justification.CENTER)
        credits_box.pack_start(credits_label, False, False, 0)

        credits_frame.add(credits_box)
        self.pack_start(credits_frame, False, False, 0)


class AliciaSettingsApp(Gtk.Application):
    """Main Settings application class."""

    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.settings_mgr = SettingsManager()
        self.pages = {}
        self.search_entry = None
        self.content_stack = None

    def do_activate(self):
        """Handle application activation."""
        win = self.props.active_window
        if not win:
            win = self._build_window()
        win.present()

    def _build_window(self):
        """Build the main application window."""
        win = Gtk.ApplicationWindow(application=self)
        win.set_title(APP_NAME)
        win.set_default_size(900, 650)
        win.set_position(Gtk.WindowPosition.CENTER)

        # Header bar
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title(APP_NAME)
        win.set_titlebar(header)

        # Search
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search settings...")
        self.search_entry.connect("search-changed", self._on_search)
        header.pack_end(self.search_entry)

        # Main layout: sidebar + content
        main_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)

        # Sidebar
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        sidebar.set_size_request(200, -1)
        sidebar.get_style_context().add_class("sidebar")

        self.sidebar_list = Gtk.ListBox()
        self.sidebar_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.sidebar_list.connect("row-selected", self._on_category_selected)

        for cat_id, icon_name, label_text in CATEGORIES:
            row = Gtk.ListBoxRow()
            row.cat_id = cat_id
            h_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            h_box.set_margin_top(8)
            h_box.set_margin_bottom(8)
            h_box.set_margin_start(12)
            h_box.set_margin_end(12)

            icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.MENU)
            label = Gtk.Label(label=label_text, halign=Gtk.Align.START)
            h_box.pack_start(icon, False, False, 0)
            h_box.pack_start(label, True, True, 0)
            row.add(h_box)
            self.sidebar_list.add(row)

        sidebar.pack_start(self.sidebar_list, True, True, 0)
        main_box.pack_start(sidebar, False, False, 0)

        # Separator
        main_box.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL),
                            False, False, 0)

        # Content area with stack
        self.content_stack = Gtk.Stack()
        self.content_stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.content_stack.set_transition_duration(200)

        # Create pages
        self.pages = {
            "display": DisplayPage(self.settings_mgr),
            "network": NetworkPage(self.settings_mgr),
            "sound": SoundPage(self.settings_mgr),
            "users": UsersPage(self.settings_mgr),
            "applications": ApplicationsPage(self.settings_mgr),
            "system": SystemPage(self.settings_mgr),
            "about": AboutPage(self.settings_mgr),
        }

        for cat_id, page in self.pages.items():
            scrolled = Gtk.ScrolledWindow()
            scrolled.add(page)
            self.content_stack.add_named(scrolled, cat_id)

        main_box.pack_start(self.content_stack, True, True, 0)
        win.add(main_box)

        # Select first category
        first_row = self.sidebar_list.get_row_at_index(0)
        self.sidebar_list.select_row(first_row)

        # Connect delete event
        win.connect("delete-event", self._on_window_close)

        win.show_all()
        return win

    def _on_category_selected(self, _listbox, row):
        """Handle sidebar category selection."""
        if row is not None:
            cat_id = row.cat_id
            self.content_stack.set_visible_child_name(cat_id)

    def _on_search(self, entry):
        """Handle search input to filter settings."""
        query = entry.get_text().strip().lower()
        if not query:
            # Show all pages normally
            return

        # Simple search: switch to the most relevant page
        search_map = {
            "resolution": "display", "vnc": "display", "wallpaper": "display",
            "theme": "display", "font": "display", "icon": "display",
            "scaling": "display", "display": "display",
            "dns": "network", "proxy": "network", "ssh": "network",
            "hostname": "network", "network": "network", "connection": "network",
            "volume": "sound", "mute": "sound", "audio": "sound",
            "sound": "sound", "speaker": "sound",
            "user": "users", "password": "users", "account": "users",
            "application": "applications", "browser": "applications",
            "default": "applications",
            "storage": "system", "memory": "system", "cpu": "system",
            "backup": "system", "restore": "system", "reset": "system",
            "system": "system",
            "about": "about", "version": "about", "license": "about",
        }
        for keyword, cat_id in search_map.items():
            if keyword in query:
                self.content_stack.set_visible_child_name(cat_id)
                # Select corresponding row
                for row in self.sidebar_list.get_children():
                    if row.cat_id == cat_id:
                        self.sidebar_list.select_row(row)
                        break
                break

    def _on_window_close(self, window, event):
        """Handle window close event."""
        # Auto-save on close
        self.settings_mgr.save()
        return False


def main():
    """Application entry point."""
    try:
        app = AliciaSettingsApp()
        app.run(sys.argv)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
