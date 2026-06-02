#!/usr/bin/env python3
"""
Alicia Welcome - Welcome screen and getting started guide for the Alicia desktop environment.

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
import subprocess
import shutil
import json

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, Gio, GLib, Pango
except (ImportError, ValueError) as e:
    print(f"Error importing GTK3: {e}")
    sys.exit(1)

# Constants
APP_NAME = "Alicia Welcome"
APP_ID = "com.proyectoTomorrow.alicia.welcome"
VERSION = "3.1.0"
CONFIG_DIR = os.path.expanduser("~/.config/alicia")
WELCOME_PREF_FILE = os.path.join(CONFIG_DIR, "welcome-prefs.json")

# Tips that rotate in the Tips section
TIPS = [
    "You can access the terminal quickly with Ctrl+Alt+T — try customizing the shortcut in Settings!",
    "Right-click on the desktop to change wallpaper, create files, or launch applications.",
    "Use the Package Manager to install new software and keep your system up to date.",
    "Press Ctrl+H in the File Manager to toggle hidden files visibility.",
    "The System Monitor shows real-time CPU, memory, and network usage — great for tracking performance.",
    "You can change the VNC resolution in Settings → Display for a better remote desktop experience.",
    "SSH is enabled by default — connect from another device with: ssh user@hostname",
    "Use Alicia Settings to configure DNS, proxy, and other network options for your environment.",
    "The Text Editor supports syntax highlighting for over 20 programming languages.",
    "Back up your Alicia configuration regularly using Settings → System → Create Backup.",
    "You can drag and drop files between directories in the File Manager.",
    "Double-click a file to open it with its default application, or right-click for more options.",
    "Use the screenshot tool to capture your screen — set a timer for capturing menus or dialogs.",
    "Terminal supports tabs — use Ctrl+Shift+T to open a new terminal tab.",
    "Customize your terminal with different color schemes and fonts in Terminal → Preferences.",
]

# Keyboard shortcuts reference
SHORTCUTS = [
    ("General", [
        ("Ctrl+Alt+T", "Open Terminal"),
        ("Ctrl+Alt+F", "Open File Manager"),
        ("Ctrl+Alt+S", "Open Settings"),
        ("Ctrl+Q", "Quit Application"),
        ("Alt+F4", "Close Window"),
        ("Alt+Tab", "Switch Windows"),
        ("F11", "Toggle Fullscreen"),
    ]),
    ("File Manager", [
        ("Ctrl+N", "New Window"),
        ("Ctrl+H", "Toggle Hidden Files"),
        ("Ctrl+C / X / V", "Copy / Cut / Paste"),
        ("Delete", "Move to Trash"),
        ("F2", "Rename"),
        ("Alt+Left", "Go Back"),
        ("Alt+Up", "Go Up"),
    ]),
    ("Text Editor", [
        ("Ctrl+N", "New File"),
        ("Ctrl+O", "Open File"),
        ("Ctrl+S", "Save File"),
        ("Ctrl+F", "Find and Replace"),
        ("Ctrl+G", "Go to Line"),
        ("Ctrl+Z / Y", "Undo / Redo"),
    ]),
    ("Terminal", [
        ("Ctrl+Shift+T", "New Tab"),
        ("Ctrl+Shift+W", "Close Tab"),
        ("Ctrl+Shift+C", "Copy"),
        ("Ctrl+Shift+V", "Paste"),
        ("Ctrl+Shift+F", "Search"),
    ]),
]

# Getting started steps
GETTING_STARTED = [
    ("1. Configure Display", "Set your preferred resolution and VNC settings in the Display settings.",
     "video-display"),
    ("2. Connect to Network", "Configure DNS, proxy, or SSH access in the Network settings.",
     "network-wired"),
    ("3. Install Software", "Use the Package Manager to install the applications you need.",
     "system-software-install"),
    ("4. Personalize", "Choose a theme, wallpaper, and fonts to make Alicia yours.",
     "preferences-desktop-wallpaper"),
    ("5. Back Up", "Create a backup of your configuration for easy recovery.",
     "drive-harddisk"),
]

# Quick actions: (label, icon, command)
QUICK_ACTIONS = [
    ("Open File Manager", "system-file-manager", "alicia-filemanager"),
    ("Open Terminal", "utilities-terminal", "alicia-terminal"),
    ("Open Settings", "preferences-system", "alicia-settings"),
    ("Open Package Manager", "system-software-install", "alicia-package-manager"),
    ("Open Text Editor", "accessories-text-editor", "alicia-text-editor"),
    ("Open System Monitor", "utilities-system-monitor", "alicia-system-monitor"),
]


def format_size(bytes_val):
    """Format bytes to human-readable string."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_val < 1024:
            return f"{bytes_val:.1f} {unit}"
        bytes_val /= 1024
    return f"{bytes_val:.1f} PB"


def read_proc_file(path):
    """Read a /proc file safely."""
    try:
        with open(path, 'r') as f:
            return f.read()
    except (IOError, OSError):
        return ""


class WelcomePreferences:
    """Manages welcome screen preferences."""

    def __init__(self):
        self.show_on_startup = True
        self.current_tip_index = 0
        self._load()

    def _load(self):
        """Load preferences from file."""
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            if os.path.exists(WELCOME_PREF_FILE):
                with open(WELCOME_PREF_FILE, 'r') as f:
                    data = json.load(f)
                    self.show_on_startup = data.get("show_on_startup", True)
                    self.current_tip_index = data.get("tip_index", 0)
        except (IOError, json.JSONDecodeError):
            pass

    def save(self):
        """Save preferences to file."""
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            with open(WELCOME_PREF_FILE, 'w') as f:
                json.dump({
                    "show_on_startup": self.show_on_startup,
                    "tip_index": self.current_tip_index,
                }, f, indent=2)
        except IOError:
            pass


class SystemStatusWidget(Gtk.Frame):
    """Widget showing system status overview."""

    def __init__(self):
        super().__init__(label="System Status")
        self.set_margin_top(8)
        self.set_margin_bottom(8)

        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.box.set_margin_top(8)
        self.box.set_margin_bottom(8)
        self.box.set_margin_start(12)
        self.box.set_margin_end(12)

        self.status_labels = {}
        for key in ["Disk Space", "Memory", "Running Services"]:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)

            icon_names = {
                "Disk Space": "drive-harddisk",
                "Memory": "memory",
                "Running Services": "system-run",
            }
            icon = Gtk.Image.new_from_icon_name(
                icon_names.get(key, "dialog-information"), Gtk.IconSize.MENU
            )
            row.pack_start(icon, False, False, 0)

            label = Gtk.Label(label=f"{key}: Checking...", halign=Gtk.Align.START)
            row.pack_start(label, True, True, 0)
            self.status_labels[key] = label
            self.box.pack_start(row, False, False, 0)

        self.add(self.box)
        self._update_status()

    def _update_status(self):
        """Update system status information."""
        # Disk space
        try:
            usage = shutil.disk_usage("/")
            pct = (usage.used / usage.total * 100) if usage.total > 0 else 0
            self.status_labels["Disk Space"].set_text(
                f"Disk Space: {format_size(usage.used)} / {format_size(usage.total)} ({pct:.0f}%)"
            )
        except Exception:
            self.status_labels["Disk Space"].set_text("Disk Space: Unable to read")

        # Memory
        content = read_proc_file("/proc/meminfo")
        if content:
            mem_total = mem_available = 0
            for line in content.splitlines():
                parts = line.split()
                if len(parts) < 2:
                    continue
                key = parts[0].rstrip(':')
                try:
                    value = int(parts[1])
                except ValueError:
                    continue
                if key == "MemTotal":
                    mem_total = value
                elif key == "MemAvailable":
                    mem_available = value

            mem_used = mem_total - mem_available
            pct = (mem_used / mem_total * 100) if mem_total > 0 else 0
            self.status_labels["Memory"].set_text(
                f"Memory: {format_size(mem_used * 1024)} / {format_size(mem_total * 1024)} ({pct:.0f}%)"
            )
        else:
            self.status_labels["Memory"].set_text("Memory: Unable to read")

        # Running services (count processes)
        try:
            pids = [p for p in os.listdir("/proc") if p.isdigit()]
            self.status_labels["Running Services"].set_text(
                f"Running Services: {len(pids)} processes"
            )
        except OSError:
            self.status_labels["Running Services"].set_text("Running Services: Unable to count")


class AliciaWelcome(Gtk.Application):
    """Main Welcome application class."""

    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.prefs = WelcomePreferences()
        self.tip_index = self.prefs.current_tip_index
        self.tip_label = None

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
        win.set_default_size(750, 650)
        win.set_position(Gtk.WindowPosition.CENTER)

        # Header bar
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title("Welcome to Alicia")
        win.set_titlebar(header)

        # Help button
        help_btn = Gtk.Button()
        help_btn.set_image(Gtk.Image.new_from_icon_name("help-contents", Gtk.IconSize.BUTTON))
        help_btn.set_tooltip_text("Documentation")
        help_btn.connect("clicked", self._on_help)
        header.pack_end(help_btn)

        # Check updates button
        update_btn = Gtk.Button(label="Check for Updates")
        update_btn.connect("clicked", self._on_check_updates)
        header.pack_end(update_btn)

        # Main content with scrolling
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        main_box.set_margin_top(24)
        main_box.set_margin_bottom(24)
        main_box.set_margin_start(32)
        main_box.set_margin_end(32)

        # Welcome header
        main_box.pack_start(self._build_welcome_header(), False, False, 0)

        # Getting started
        main_box.pack_start(self._build_getting_started(), False, False, 0)

        # Quick actions
        main_box.pack_start(self._build_quick_actions(), False, False, 0)

        # Tips section
        main_box.pack_start(self._build_tips(), False, False, 0)

        # Keyboard shortcuts
        main_box.pack_start(self._build_shortcuts(), False, False, 0)

        # System status
        self.system_status = SystemStatusWidget()
        main_box.pack_start(self.system_status, False, False, 0)

        # Don't show again checkbox
        dont_show_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.dont_show_check = Gtk.CheckButton(label="Don't show this on startup")
        self.dont_show_check.set_active(not self.prefs.show_on_startup)
        self.dont_show_check.connect("toggled", self._on_dont_show_toggled)
        dont_show_box.pack_start(self.dont_show_check, False, False, 0)
        main_box.pack_start(dont_show_box, False, False, 0)

        scrolled.add(main_box)
        win.add(scrolled)

        # Periodically update system status
        GLib.timeout_add(10000, self._periodic_update)

        win.show_all()
        return win

    def _build_welcome_header(self):
        """Build the welcome header with logo and version info."""
        frame = Gtk.Frame()
        frame.get_style_context().add_class("background")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(20)
        box.set_margin_bottom(20)

        # Logo area
        logo_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        logo_box.set_halign(Gtk.Align.CENTER)

        # Try to load an icon, fall back to text
        try:
            logo_icon = Gtk.Image.new_from_icon_name("com.proyectoTomorrow.alicia",
                                                       Gtk.IconSize.DIALOG)
            logo_icon.set_pixel_size(64)
            logo_box.pack_start(logo_icon, False, False, 0)
        except Exception:
            pass

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        title = Gtk.Label()
        title.set_markup("<span size='xx-large' weight='bold'>Alicia Desktop</span>")
        text_box.pack_start(title, False, False, 0)

        subtitle = Gtk.Label()
        subtitle.set_markup("<span size='large' foreground='#888888'>Enterprise Linux Desktop for Android</span>")
        text_box.pack_start(subtitle, False, False, 0)

        version = Gtk.Label()
        version.set_markup(f"<span foreground='#aaaaaa'>Version {VERSION} — Proyecto Tomorrow</span>")
        text_box.pack_start(version, False, False, 0)

        logo_box.pack_start(text_box, False, False, 0)
        box.pack_start(logo_box, False, False, 0)

        # Description
        desc = Gtk.Label()
        desc.set_markup(
            "<i>A full Linux desktop environment running on your Android device via "
            "Termux + proot + VNC. Powered by XFCE4 and GTK3.</i>"
        )
        desc.set_line_wrap(True)
        desc.set_max_width_chars(60)
        desc.set_justify(Gtk.Justification.CENTER)
        box.pack_start(desc, False, False, 0)

        frame.add(box)
        return frame

    def _build_getting_started(self):
        """Build the Getting Started section."""
        frame = Gtk.Frame(label="Getting Started")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(12)
        box.set_margin_end(12)

        for title, description, icon_name in GETTING_STARTED:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)

            icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.DIALOG)
            row.pack_start(icon, False, False, 0)

            text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            title_label = Gtk.Label()
            title_label.set_markup(f"<b>{title}</b>")
            title_label.set_halign(Gtk.Align.START)
            text_box.pack_start(title_label, False, False, 0)

            desc_label = Gtk.Label(label=description)
            desc_label.set_halign(Gtk.Align.START)
            desc_label.set_line_wrap(True)
            desc_label.set_max_width_chars(50)
            desc_label.get_style_context().add_class("dim-label")
            text_box.pack_start(desc_label, False, False, 0)

            row.pack_start(text_box, True, True, 0)
            box.pack_start(row, False, False, 0)

        frame.add(box)
        return frame

    def _build_quick_actions(self):
        """Build the Quick Actions section."""
        frame = Gtk.Frame(label="Quick Actions")
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6, homogeneous=True)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(12)
        box.set_margin_end(12)

        for label_text, icon_name, command in QUICK_ACTIONS:
            btn = Gtk.Button()
            btn_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)

            icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.LARGE_TOOLBAR)
            btn_box.pack_start(icon, False, False, 0)

            btn_label = Gtk.Label(label=label_text)
            btn_label.set_line_wrap(True)
            btn_label.set_max_width_chars(14)
            btn_box.pack_start(btn_label, False, False, 0)

            btn.add(btn_box)
            btn.connect("clicked", self._on_quick_action, command)
            box.pack_start(btn, True, True, 0)

        frame.add(box)
        return frame

    def _build_tips(self):
        """Build the Tips section with rotating tips."""
        frame = Gtk.Frame(label="Tips & Tricks")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(12)
        box.set_margin_end(12)

        # Tip display
        tip_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)

        tip_icon = Gtk.Image.new_from_icon_name("dialog-information", Gtk.IconSize.DIALOG)
        tip_row.pack_start(tip_icon, False, False, 0)

        self.tip_label = Gtk.Label()
        self.tip_label.set_line_wrap(True)
        self.tip_label.set_max_width_chars(60)
        self.tip_label.set_halign(Gtk.Align.START)
        self.tip_label.set_valign(Gtk.Align.CENTER)
        self._update_tip()
        tip_row.pack_start(self.tip_label, True, True, 0)

        box.pack_start(tip_row, False, False, 0)

        # Navigation buttons
        nav_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        nav_box.set_halign(Gtk.Align.END)

        prev_btn = Gtk.Button(label="Previous Tip")
        prev_btn.connect("clicked", self._on_prev_tip)
        nav_box.pack_start(prev_btn, False, False, 0)

        next_btn = Gtk.Button(label="Next Tip")
        next_btn.connect("clicked", self._on_next_tip)
        nav_box.pack_start(next_btn, False, False, 0)

        box.pack_start(nav_box, False, False, 0)

        frame.add(box)
        return frame

    def _build_shortcuts(self):
        """Build the Keyboard Shortcuts reference section."""
        frame = Gtk.Frame(label="Keyboard Shortcuts")
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        main_box.set_margin_top(8)
        main_box.set_margin_bottom(8)
        main_box.set_margin_start(12)
        main_box.set_margin_end(12)

        for category, shortcuts in SHORTCUTS:
            # Category header
            cat_label = Gtk.Label()
            cat_label.set_markup(f"<b>{category}</b>")
            cat_label.set_halign(Gtk.Align.START)
            main_box.pack_start(cat_label, False, False, 0)

            grid = Gtk.Grid(row_spacing=2, column_spacing=12)
            grid.set_margin_start(16)
            row = 0

            for shortcut, description in shortcuts:
                key_label = Gtk.Label()
                key_label.set_markup(f"<tt>{shortcut}</tt>")
                key_label.set_halign(Gtk.Align.END)
                key_label.set_size_request(160, -1)

                desc_label = Gtk.Label(label=description)
                desc_label.set_halign(Gtk.Align.START)

                grid.attach(key_label, 0, row, 1, 1)
                grid.attach(desc_label, 1, row, 1, 1)
                row += 1

            main_box.pack_start(grid, False, False, 4)

            if category != SHORTCUTS[-1][0]:
                sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
                main_box.pack_start(sep, False, False, 4)

        frame.add(main_box)
        return frame

    def _update_tip(self):
        """Update the tip label with the current tip."""
        if self.tip_label and 0 <= self.tip_index < len(TIPS):
            tip_num = self.tip_index + 1
            self.tip_label.set_text(f"Tip {tip_num}/{len(TIPS)}: {TIPS[self.tip_index]}")

    def _on_prev_tip(self, _btn):
        """Show the previous tip."""
        self.tip_index = (self.tip_index - 1) % len(TIPS)
        self._update_tip()
        self._save_tip_index()

    def _on_next_tip(self, _btn):
        """Show the next tip."""
        self.tip_index = (self.tip_index + 1) % len(TIPS)
        self._update_tip()
        self._save_tip_index()

    def _save_tip_index(self):
        """Save the current tip index."""
        self.prefs.current_tip_index = self.tip_index
        self.prefs.save()

    def _on_quick_action(self, _btn, command):
        """Launch a quick action application."""
        try:
            subprocess.Popen([command],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            # Try with python3 prefix
            try:
                app_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), command)
                subprocess.Popen(["python3", app_path],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                self._show_error(f"Could not launch {command}: {e}")
        except Exception as e:
            self._show_error(f"Could not launch {command}: {e}")

    def _on_help(self, _btn):
        """Open help/documentation."""
        try:
            subprocess.Popen(["xdg-open", "https://proyectotomorrow.github.io/alicia"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            self._show_info(
                "Documentation is available at:\n"
                "https://proyectotomorrow.github.io/alicia\n\n"
                "You can also find help in the Settings application."
            )

    def _on_check_updates(self, _btn):
        """Check for system updates."""
        dialog = Gtk.MessageDialog(
            parent=self.props.active_window,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.NONE,
            text="Checking for updates..."
        )
        dialog.show_all()

        # Run update check in background
        def check_updates():
            try:
                if shutil.which("apt"):
                    result = subprocess.run(
                        ["apt", "list", "--upgradable"],
                        capture_output=True, text=True, timeout=60
                    )
                    lines = [l for l in result.stdout.splitlines() if l and not l.startswith("Listing")]
                    count = len(lines)
                elif shutil.which("apk"):
                    result = subprocess.run(
                        ["apk", "version", "-l", "<"],
                        capture_output=True, text=True, timeout=60
                    )
                    lines = [l for l in result.stdout.splitlines() if l.strip()]
                    count = len(lines)
                elif shutil.which("pkg"):
                    result = subprocess.run(
                        ["pkg", "upgrade"],
                        capture_output=True, text=True, input="\n",
                        timeout=60
                    )
                    count = 0  # pkg doesn't have a dry-run mode easily
                else:
                    count = -1

                GLib.idle_add(lambda: dialog.destroy())
                if count >= 0:
                    GLib.idle_add(lambda: self._show_info(
                        f"Updates available: {count} package(s).\n\n"
                        "Use the Package Manager to install updates."
                    ))
                else:
                    GLib.idle_add(lambda: self._show_info(
                        "Could not check for updates.\nNo supported package manager found."
                    ))
            except Exception as e:
                GLib.idle_add(lambda: dialog.destroy())
                GLib.idle_add(lambda: self._show_error(f"Update check failed: {e}"))

        import threading
        threading.Thread(target=check_updates, daemon=True).start()

    def _on_dont_show_toggled(self, check_btn):
        """Handle don't show again toggle."""
        self.prefs.show_on_startup = not check_btn.get_active()
        self.prefs.save()

    def _periodic_update(self):
        """Periodic update of system status."""
        self.system_status._update_status()
        return True  # Keep the timer running

    def _show_error(self, msg):
        """Show an error dialog."""
        dialog = Gtk.MessageDialog(
            parent=self.props.active_window,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK, text=str(msg)
        )
        dialog.run()
        dialog.destroy()

    def _show_info(self, msg):
        """Show an info dialog."""
        dialog = Gtk.MessageDialog(
            parent=self.props.active_window,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.OK, text=str(msg)
        )
        dialog.run()
        dialog.destroy()


def main():
    """Application entry point."""
    try:
        app = AliciaWelcome()
        app.run(sys.argv)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
