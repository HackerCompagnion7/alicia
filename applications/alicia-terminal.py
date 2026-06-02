#!/usr/bin/env python3
"""
Alicia Terminal - Enhanced terminal emulator for the Alicia desktop environment.

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
import json
import subprocess
import time

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, Gio, GLib, Pango
except (ImportError, ValueError) as e:
    print(f"Error importing GTK3: {e}")
    sys.exit(1)

# Try to import VTE for terminal widget
HAS_VTE = False
try:
    gi.require_version('Vte', '2.91')
    from gi.repository import Vte
    HAS_VTE = True
except (ImportError, ValueError):
    print("Warning: VTE library not available. Falling back to xterm wrapper.")

# Constants
APP_NAME = "Alicia Terminal"
APP_ID = "com.proyectoTomorrow.alicia.terminal"
VERSION = "3.1.0"
CONFIG_DIR = os.path.expanduser("~/.config/alicia")
PROFILES_FILE = os.path.join(CONFIG_DIR, "terminal-profiles.json")

# Default terminal colors (Tango dark)
DEFAULT_COLORS = {
    "foreground": "#d3d7cf",
    "background": "#2e3436",
    "palette": [
        "#2e3436", "#cc0000", "#4e9a06", "#c4a000",
        "#3465a4", "#75507b", "#06989a", "#d3d7cf",
        "#555753", "#ef2929", "#8ae234", "#fce94f",
        "#729fcf", "#ad7fa8", "#34e2e2", "#eeeeec",
    ],
}

DEFAULT_PROFILE = {
    "name": "Default",
    "font": "Monospace 12",
    "scrollback": 10000,
    "cursor_shape": "block",
    "cursor_blink": True,
    "colors": DEFAULT_COLORS,
    "shell": os.environ.get("SHELL", "/bin/bash"),
    "working_dir": os.path.expanduser("~"),
    "custom_command": "",
    "audible_bell": False,
}


def parse_color(hex_str):
    """Parse a hex color string to Gdk.RGBA."""
    color = Gdk.RGBA()
    color.parse(hex_str)
    return color


class TerminalProfile:
    """Manages terminal profiles for saving/loading configurations."""

    def __init__(self):
        self.profiles = {}
        self.active_profile = "Default"
        self._load()

    def _load(self):
        """Load profiles from file."""
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            if os.path.exists(PROFILES_FILE):
                with open(PROFILES_FILE, 'r') as f:
                    data = json.load(f)
                    self.profiles = data.get("profiles", {})
                    self.active_profile = data.get("active", "Default")
        except (IOError, json.JSONDecodeError):
            pass

        if "Default" not in self.profiles:
            self.profiles["Default"] = DEFAULT_PROFILE.copy()

    def save(self):
        """Save profiles to file."""
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            with open(PROFILES_FILE, 'w') as f:
                json.dump({
                    "profiles": self.profiles,
                    "active": self.active_profile,
                }, f, indent=2)
        except IOError as e:
            print(f"Error saving profiles: {e}")

    def get_profile(self, name=None):
        """Get a profile by name."""
        name = name or self.active_profile
        return self.profiles.get(name, DEFAULT_PROFILE.copy())

    def set_profile(self, name, profile):
        """Set a profile."""
        self.profiles[name] = profile
        self.save()

    def delete_profile(self, name):
        """Delete a profile."""
        if name != "Default" and name in self.profiles:
            del self.profiles[name]
            self.save()

    def get_profile_names(self):
        """Get list of profile names."""
        return list(self.profiles.keys())


class TerminalTab:
    """Represents a single terminal tab."""

    def __init__(self, profile, on_title_changed=None):
        self.profile = profile
        self.on_title_changed = on_title_changed
        self.terminal = None
        self.pid = -1
        self.label_text = "Terminal"
        self._build()

    def _build(self):
        """Build the terminal widget."""
        if HAS_VTE:
            self.terminal = Vte.Terminal()
            self._configure_vte()
            self._spawn_shell()
            self.terminal.connect("child-exited", self._on_child_exited)
            self.terminal.connect("window-title-changed", self._on_title_changed)
        else:
            # Fallback: text view that launches xterm
            self.terminal = Gtk.Label(label="VTE not available. Using xterm fallback.")
            self._spawn_xterm()

    def _configure_vte(self):
        """Configure VTE terminal with profile settings."""
        profile = self.profile

        # Font
        try:
            font_desc = Pango.FontDescription(profile.get("font", "Monospace 12"))
            self.terminal.set_font(font_desc)
        except Exception:
            pass

        # Scrollback
        self.terminal.set_scrollback_lines(profile.get("scrollback", 10000))

        # Cursor
        cursor_shape = profile.get("cursor_shape", "block")
        shape_map = {
            "block": Vte.CursorShape.BLOCK,
            "ibeam": Vte.CursorShape.IBEAM,
            "underline": Vte.CursorShape.UNDERLINE,
        }
        self.terminal.set_cursor_shape(shape_map.get(cursor_shape, Vte.CursorShape.BLOCK))
        self.terminal.set_cursor_blink_mode(
            Vte.CursorBlinkMode.ON if profile.get("cursor_blink", True)
            else Vte.CursorBlinkMode.OFF
        )

        # Colors
        colors = profile.get("colors", DEFAULT_COLORS)
        fg = parse_color(colors.get("foreground", "#d3d7cf"))
        bg = parse_color(colors.get("background", "#2e3436"))
        palette = [parse_color(c) for c in colors.get("palette", DEFAULT_COLORS["palette"])]
        if len(palette) >= 16:
            self.terminal.set_colors(fg, bg, palette)

        # Audible bell
        self.terminal.set_audible_bell(profile.get("audible_bell", False))

        # Allow hyperlink
        try:
            self.terminal.set_allow_hyperlink(True)
        except Exception:
            pass

    def _spawn_shell(self):
        """Spawn a shell in the terminal."""
        shell = self.profile.get("shell", "/bin/bash")
        working_dir = self.profile.get("working_dir", os.path.expanduser("~"))
        custom_command = self.profile.get("custom_command", "")

        if not os.path.exists(working_dir):
            working_dir = os.path.expanduser("~")

        env = []
        for key, value in os.environ.items():
            env.append(f"{key}={value}")

        try:
            if custom_command:
                self.pid = self.terminal.spawn_sync(
                    Vte.PtyFlags.DEFAULT,
                    working_dir,
                    [shell, "-c", custom_command],
                    env,
                    GLib.SpawnFlags.SEARCH_PATH_FROM_ENVP,
                    None,
                    None,
                )
            else:
                self.pid = self.terminal.spawn_sync(
                    Vte.PtyFlags.DEFAULT,
                    working_dir,
                    [shell],
                    env,
                    GLib.SpawnFlags.SEARCH_PATH_FROM_ENVP,
                    None,
                    None,
                )
        except Exception as e:
            print(f"Error spawning shell: {e}")
            self.pid = -1

    def _spawn_xterm(self):
        """Fallback: launch xterm as external process."""
        shell = self.profile.get("shell", "/bin/bash")
        working_dir = self.profile.get("working_dir", os.path.expanduser("~"))
        try:
            subprocess.Popen(
                ["xterm", "-e", shell],
                cwd=working_dir,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception as e:
            print(f"Error launching xterm: {e}")

    def _on_child_exited(self, _terminal, _status):
        """Handle terminal child process exit."""
        # Respawn the shell
        self._spawn_shell()

    def _on_title_changed(self, _terminal):
        """Handle terminal title change."""
        try:
            title = self.terminal.get_window_title()
            if title:
                self.label_text = title
                if self.on_title_changed:
                    self.on_title_changed(self, title)
        except Exception:
            pass

    def feed_text(self, text):
        """Send text to the terminal."""
        if HAS_VTE and self.terminal:
            self.terminal.feed_child(text.encode())

    def copy_clipboard(self):
        """Copy selection to clipboard."""
        if HAS_VTE and self.terminal:
            self.terminal.copy_clipboard_format(Vte.Format.TEXT)

    def paste_clipboard(self):
        """Paste from clipboard."""
        if HAS_VTE and self.terminal:
            self.terminal.paste_clipboard()

    def get_widget(self):
        """Get the terminal widget."""
        return self.terminal


class SearchBar(Gtk.Box):
    """Search bar for terminal content."""

    def __init__(self, terminal_tab):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.tab = terminal_tab
        self.set_margin_top(4)
        self.set_margin_bottom(4)
        self.set_margin_start(8)
        self.set_margin_end(8)

        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search in terminal...")
        self.search_entry.connect("search-changed", self._on_search)
        self.pack_start(self.search_entry, True, True, 0)

        prev_btn = Gtk.Button()
        prev_btn.set_image(Gtk.Image.new_from_icon_name("go-up", Gtk.IconSize.BUTTON))
        prev_btn.set_tooltip_text("Previous match")
        prev_btn.connect("clicked", self._on_prev)
        self.pack_start(prev_btn, False, False, 0)

        next_btn = Gtk.Button()
        next_btn.set_image(Gtk.Image.new_from_icon_name("go-down", Gtk.IconSize.BUTTON))
        next_btn.set_tooltip_text("Next match")
        next_btn.connect("clicked", self._on_next)
        self.pack_start(next_btn, False, False, 0)

        close_btn = Gtk.Button()
        close_btn.set_image(Gtk.Image.new_from_icon_name("window-close", Gtk.IconSize.BUTTON))
        close_btn.connect("clicked", self._on_close)
        self.pack_start(close_btn, False, False, 0)

    def _on_search(self, entry):
        """Handle search text change."""
        if HAS_VTE and self.tab.terminal:
            query = entry.get_text()
            if query:
                self.tab.terminal.search_set_gregex(
                    GLib.Regex(query, GLib.RegexCompileFlags.CASELESS, 0),
                    False
                )
                self.tab.terminal.search_find_next()

    def _on_prev(self, _btn):
        """Search previous match."""
        if HAS_VTE and self.tab.terminal:
            self.tab.terminal.search_find_previous()

    def _on_next(self, _btn):
        """Search next match."""
        if HAS_VTE and self.tab.terminal:
            self.tab.terminal.search_find_next()

    def _on_close(self, _btn):
        """Close the search bar."""
        self.hide()
        if HAS_VTE and self.tab.terminal:
            self.tab.terminal.search_set_gregex(None, False)


class PreferencesDialog(Gtk.Dialog):
    """Terminal preferences dialog."""

    def __init__(self, parent, profile_mgr):
        super().__init__(title="Terminal Preferences", parent=parent,
                         modal=True, destroy_with_parent=True)
        self.profile_mgr = profile_mgr
        self.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                         Gtk.STOCK_APPLY, Gtk.ResponseType.OK)
        self.set_default_size(450, 500)

        self._build_ui()

    def _build_ui(self):
        """Build the preferences UI."""
        notebook = Gtk.Notebook()
        notebook.set_margin_top(8)
        notebook.set_margin_bottom(8)
        notebook.set_margin_start(8)
        notebook.set_margin_end(8)

        profile = self.profile_mgr.get_profile()

        # General tab
        general_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        general_box.set_margin_top(12)
        general_box.set_margin_bottom(12)
        general_box.set_margin_start(12)
        general_box.set_margin_end(12)

        # Profile selector
        prof_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        prof_box.pack_start(Gtk.Label(label="Profile:"), False, False, 0)
        self.profile_combo = Gtk.ComboBoxText()
        for name in self.profile_mgr.get_profile_names():
            self.profile_combo.append_text(name)
        self.profile_combo.set_active(0)
        self.profile_combo.connect("changed", self._on_profile_changed)
        prof_box.pack_start(self.profile_combo, True, True, 0)

        new_prof_btn = Gtk.Button(label="New")
        new_prof_btn.connect("clicked", self._on_new_profile)
        prof_box.pack_start(new_prof_btn, False, False, 0)

        del_prof_btn = Gtk.Button(label="Delete")
        del_prof_btn.connect("clicked", self._on_delete_profile)
        prof_box.pack_start(del_prof_btn, False, False, 0)

        general_box.pack_start(prof_box, False, False, 0)

        # Shell
        shell_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        shell_box.pack_start(Gtk.Label(label="Shell:"), False, False, 0)
        self.shell_entry = Gtk.Entry()
        self.shell_entry.set_text(profile.get("shell", "/bin/bash"))
        shell_box.pack_start(self.shell_entry, True, True, 0)
        general_box.pack_start(shell_box, False, False, 0)

        # Working directory
        wd_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        wd_box.pack_start(Gtk.Label(label="Working Dir:"), False, False, 0)
        self.wd_entry = Gtk.Entry()
        self.wd_entry.set_text(profile.get("working_dir", os.path.expanduser("~")))
        wd_box.pack_start(self.wd_entry, True, True, 0)
        general_box.pack_start(wd_box, False, False, 0)

        # Custom command
        cmd_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        cmd_box.pack_start(Gtk.Label(label="Custom Command:"), False, False, 0)
        self.cmd_entry = Gtk.Entry()
        self.cmd_entry.set_text(profile.get("custom_command", ""))
        self.cmd_entry.set_placeholder_text("Leave empty for default shell")
        cmd_box.pack_start(self.cmd_entry, True, True, 0)
        general_box.pack_start(cmd_box, False, False, 0)

        # Scrollback
        sb_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        sb_box.pack_start(Gtk.Label(label="Scrollback Lines:"), False, False, 0)
        self.scrollback_spin = Gtk.SpinButton.new_with_range(100, 100000, 1000)
        self.scrollback_spin.set_value(profile.get("scrollback", 10000))
        sb_box.pack_start(self.scrollback_spin, True, True, 0)
        general_box.pack_start(sb_box, False, False, 0)

        notebook.append_page(general_box, Gtk.Label(label="General"))

        # Appearance tab
        appearance_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        appearance_box.set_margin_top(12)
        appearance_box.set_margin_bottom(12)
        appearance_box.set_margin_start(12)
        appearance_box.set_margin_end(12)

        # Font
        font_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        font_box.pack_start(Gtk.Label(label="Font:"), False, False, 0)
        self.font_btn = Gtk.FontButton()
        self.font_btn.set_font(profile.get("font", "Monospace 12"))
        font_box.pack_start(self.font_btn, True, True, 0)
        appearance_box.pack_start(font_box, False, False, 0)

        # Cursor shape
        cursor_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        cursor_box.pack_start(Gtk.Label(label="Cursor:"), False, False, 0)
        self.cursor_combo = Gtk.ComboBoxText()
        for shape in ["block", "ibeam", "underline"]:
            self.cursor_combo.append_text(shape)
        current_cursor = profile.get("cursor_shape", "block")
        for i, item in enumerate(self.cursor_combo.get_model()):
            if item[0] == current_cursor:
                self.cursor_combo.set_active(i)
        if self.cursor_combo.get_active() == -1:
            self.cursor_combo.set_active(0)
        cursor_box.pack_start(self.cursor_combo, True, True, 0)
        appearance_box.pack_start(cursor_box, False, False, 0)

        # Cursor blink
        self.blink_check = Gtk.CheckButton(label="Cursor Blink")
        self.blink_check.set_active(profile.get("cursor_blink", True))
        appearance_box.pack_start(self.blink_check, False, False, 0)

        # Audible bell
        self.bell_check = Gtk.CheckButton(label="Audible Bell")
        self.bell_check.set_active(profile.get("audible_bell", False))
        appearance_box.pack_start(self.bell_check, False, False, 0)

        # Foreground color
        fg_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        fg_box.pack_start(Gtk.Label(label="Text Color:"), False, False, 0)
        self.fg_color_btn = Gtk.ColorButton()
        colors = profile.get("colors", DEFAULT_COLORS)
        self.fg_color_btn.set_rgba(parse_color(colors.get("foreground", "#d3d7cf")))
        fg_box.pack_start(self.fg_color_btn, True, True, 0)
        appearance_box.pack_start(fg_box, False, False, 0)

        # Background color
        bg_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        bg_box.pack_start(Gtk.Label(label="Background Color:"), False, False, 0)
        self.bg_color_btn = Gtk.ColorButton()
        self.bg_color_btn.set_rgba(parse_color(colors.get("background", "#2e3436")))
        bg_box.pack_start(self.bg_color_btn, True, True, 0)
        appearance_box.pack_start(bg_box, False, False, 0)

        notebook.append_page(appearance_box, Gtk.Label(label="Appearance"))

        self.get_content_area().pack_start(notebook, True, True, 0)
        self.show_all()

    def _on_profile_changed(self, combo):
        """Handle profile combo change."""
        name = combo.get_active_text()
        if name:
            profile = self.profile_mgr.get_profile(name)
            self.shell_entry.set_text(profile.get("shell", "/bin/bash"))
            self.wd_entry.set_text(profile.get("working_dir", os.path.expanduser("~")))
            self.cmd_entry.set_text(profile.get("custom_command", ""))
            self.scrollback_spin.set_value(profile.get("scrollback", 10000))
            self.font_btn.set_font(profile.get("font", "Monospace 12"))
            self.blink_check.set_active(profile.get("cursor_blink", True))
            self.bell_check.set_active(profile.get("audible_bell", False))

    def _on_new_profile(self, _btn):
        """Create a new profile."""
        dialog = Gtk.Dialog(title="New Profile", parent=self, modal=True)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OK, Gtk.ResponseType.OK)
        entry = Gtk.Entry()
        entry.set_text("New Profile")
        entry.set_margin_top(12)
        entry.set_margin_bottom(12)
        entry.set_margin_start(12)
        entry.set_margin_end(12)
        dialog.get_content_area().pack_start(entry, True, True, 0)
        dialog.show_all()

        if dialog.run() == Gtk.ResponseType.OK:
            name = entry.get_text().strip()
            if name:
                self.profile_mgr.set_profile(name, DEFAULT_PROFILE.copy())
                self.profile_combo.append_text(name)
                self.profile_combo.set_active(self.profile_combo.get_model().iter_n_children(None) - 1)
        dialog.destroy()

    def _on_delete_profile(self, _btn):
        """Delete the selected profile."""
        name = self.profile_combo.get_active_text()
        if name and name != "Default":
            self.profile_mgr.delete_profile(name)
            self.profile_combo.remove(self.profile_combo.get_active())

    def get_profile_data(self):
        """Get the configured profile data from the dialog."""
        fg_rgba = self.fg_color_btn.get_rgba()
        bg_rgba = self.bg_color_btn.get_rgba()
        colors = {
            "foreground": fg_rgba.to_string(),
            "background": bg_rgba.to_string(),
            "palette": DEFAULT_COLORS["palette"],
        }

        return {
            "name": self.profile_combo.get_active_text() or "Default",
            "shell": self.shell_entry.get_text().strip() or "/bin/bash",
            "working_dir": self.wd_entry.get_text().strip() or os.path.expanduser("~"),
            "custom_command": self.cmd_entry.get_text().strip(),
            "scrollback": int(self.scrollback_spin.get_value()),
            "font": self.font_btn.get_font_name(),
            "cursor_shape": self.cursor_combo.get_active_text() or "block",
            "cursor_blink": self.blink_check.get_active(),
            "audible_bell": self.bell_check.get_active(),
            "colors": colors,
        }


class AliciaTerminalApp(Gtk.Application):
    """Main Terminal application class."""

    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.profile_mgr = TerminalProfile()
        self.tabs = []
        self.notebook = None

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
        win.set_default_size(800, 500)
        win.set_position(Gtk.WindowPosition.CENTER)

        # Header bar
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title(APP_NAME)
        win.set_titlebar(header)

        # New tab button
        new_tab_btn = Gtk.Button()
        new_tab_btn.set_image(Gtk.Image.new_from_icon_name("tab-new", Gtk.IconSize.BUTTON))
        new_tab_btn.set_tooltip_text("New Tab")
        new_tab_btn.connect("clicked", self._on_new_tab)
        header.pack_start(new_tab_btn)

        # Split button
        if HAS_VTE:
            split_h_btn = Gtk.Button()
            split_h_btn.set_image(Gtk.Image.new_from_icon_name("format-justify-fill", Gtk.IconSize.BUTTON))
            split_h_btn.set_tooltip_text("Split Horizontal")
            split_h_btn.connect("clicked", self._on_split_horizontal)
            header.pack_start(split_h_btn)

        # Menu button
        menu_btn = Gtk.MenuButton()
        menu = Gio.Menu()
        menu.append("Preferences", "app.preferences")
        menu.append("Copy", "app.copy")
        menu.append("Paste", "app.paste")
        menu.append("Search", "app.search")
        menu.append("Close Tab", "app.close_tab")
        menu_btn.set_menu_model(menu)
        menu_btn.set_image(Gtk.Image.new_from_icon_name("open-menu", Gtk.IconSize.BUTTON))
        header.pack_end(menu_btn)

        # App actions
        prefs_action = Gio.SimpleAction.new("preferences", None)
        prefs_action.connect("activate", self._on_preferences)
        self.add_action(prefs_action)

        copy_action = Gio.SimpleAction.new("copy", None)
        copy_action.connect("activate", self._on_copy)
        self.add_action(copy_action)

        paste_action = Gio.SimpleAction.new("paste", None)
        paste_action.connect("activate", self._on_paste)
        self.add_action(paste_action)

        search_action = Gio.SimpleAction.new("search", None)
        search_action.connect("activate", self._on_search_toggle)
        self.add_action(search_action)

        close_tab_action = Gio.SimpleAction.new("close_tab", None)
        close_tab_action.connect("activate", self._on_close_tab)
        self.add_action(close_tab_action)

        # Main vertical box
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Notebook for tabs
        self.notebook = Gtk.Notebook()
        self.notebook.set_scrollable(True)
        self.notebook.set_show_border(True)
        self.notebook.connect("switch-page", self._on_switch_page)

        main_box.pack_start(self.notebook, True, True, 0)

        # Search bar (hidden by default)
        self.search_bar = None
        self.search_bar_visible = False

        win.add(main_box)

        # Keyboard shortcuts
        self._setup_shortcuts(win)

        # Create initial tab
        self._add_new_tab()

        win.show_all()
        return win

    def _setup_shortcuts(self, win):
        """Set up keyboard shortcuts."""
        accel = Gtk.AccelGroup()
        accel.connect(Gdk.keyval_from_name("t"), Gdk.ModifierType.CONTROL_MASK,
                      Gtk.AccelFlags.VISIBLE, self._accel_new_tab)
        accel.connect(Gdk.keyval_from_name("w"), Gdk.ModifierType.CONTROL_MASK,
                      Gtk.AccelFlags.VISIBLE, self._accel_close_tab)
        accel.connect(Gdk.keyval_from_name("c"), Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK,
                      Gtk.AccelFlags.VISIBLE, self._accel_copy)
        accel.connect(Gdk.keyval_from_name("v"), Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK,
                      Gtk.AccelFlags.VISIBLE, self._accel_paste)
        accel.connect(Gdk.keyval_from_name("f"), Gdk.ModifierType.CONTROL_MASK,
                      Gtk.AccelFlags.VISIBLE, self._accel_search)
        win.add_accel_group(accel)

    def _accel_new_tab(self, *_):
        self._add_new_tab()

    def _accel_close_tab(self, *_):
        self._close_current_tab()

    def _accel_copy(self, *_):
        self._copy_current()

    def _accel_paste(self, *_):
        self._paste_current()

    def _accel_search(self, *_):
        self._toggle_search()

    def _add_new_tab(self, profile=None):
        """Add a new terminal tab."""
        if profile is None:
            profile = self.profile_mgr.get_profile()

        tab = TerminalTab(profile, on_title_changed=self._on_tab_title_changed)
        self.tabs.append(tab)

        # Create tab label with close button
        tab_label_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        tab_label = Gtk.Label(label=tab.label_text)
        tab_label.set_max_width_chars(20)
        tab_label.set_ellipsize(Pango.EllipsizeMode.END)

        close_btn = Gtk.Button()
        close_btn.set_image(Gtk.Image.new_from_icon_name("window-close", Gtk.IconSize.MENU))
        close_btn.set_relief(Gtk.ReliefStyle.NONE)
        close_btn.set_tooltip_text("Close Tab")
        idx = len(self.tabs) - 1
        close_btn.connect("clicked", self._on_close_tab_btn, idx)

        tab_label_box.pack_start(tab_label, True, True, 0)
        tab_label_box.pack_start(close_btn, False, False, 0)
        tab_label_box.show_all()

        # Terminal wrapper with search bar
        term_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        terminal_widget = tab.get_widget()
        if HAS_VTE and terminal_widget:
            terminal_widget.set_vexpand(True)
            term_box.pack_start(terminal_widget, True, True, 0)

            # Add search bar (hidden)
            search_bar = SearchBar(tab)
            search_bar.set_no_show_all(True)
            term_box.pack_start(search_bar, False, False, 0)
            tab.search_bar = search_bar

        page_num = self.notebook.append_page(term_box, tab_label_box)
        self.notebook.set_current_page(page_num)
        self.notebook.show_all()

        # Focus the terminal
        if HAS_VTE and terminal_widget:
            terminal_widget.grab_focus()

    def _on_tab_title_changed(self, tab, title):
        """Handle terminal title change."""
        for i, t in enumerate(self.tabs):
            if t is tab:
                page = self.notebook.get_nth_page(i)
                if page:
                    label_box = self.notebook.get_tab_label(page)
                    if label_box:
                        for child in label_box.get_children():
                            if isinstance(child, Gtk.Label):
                                child.set_text(title[:20])
                                break
                break

    def _on_switch_page(self, _notebook, _page, page_num):
        """Handle tab switch."""
        if page_num < len(self.tabs):
            tab = self.tabs[page_num]
            if HAS_VTE and tab.terminal:
                tab.terminal.grab_focus()

    def _on_close_tab_btn(self, _btn, idx):
        """Close a tab by index."""
        if idx < len(self.tabs):
            self._close_tab(idx)

    def _close_tab(self, idx):
        """Close a specific tab."""
        if len(self.tabs) <= 1:
            # Don't close the last tab, just reset it
            return
        if idx < len(self.tabs):
            self.tabs.pop(idx)
            self.notebook.remove_page(idx)

    def _close_current_tab(self):
        """Close the current tab."""
        idx = self.notebook.get_current_page()
        self._close_tab(idx)

    def _on_new_tab(self, _btn):
        """Handle new tab button click."""
        self._add_new_tab()

    def _on_split_horizontal(self, _btn):
        """Split the terminal horizontally (adds a new tab as a simple split)."""
        self._add_new_tab()

    def _on_preferences(self, _action, _param):
        """Show preferences dialog."""
        win = self.props.active_window
        dialog = PreferencesDialog(win, self.profile_mgr)
        if dialog.run() == Gtk.ResponseType.OK:
            profile_data = dialog.get_profile_data()
            self.profile_mgr.set_profile(profile_data["name"], profile_data)
            self.profile_mgr.active_profile = profile_data["name"]
            self.profile_mgr.save()

            # Apply to current tab
            idx = self.notebook.get_current_page()
            if idx < len(self.tabs) and HAS_VTE:
                tab = self.tabs[idx]
                tab.profile = profile_data
                tab._configure_vte()
        dialog.destroy()

    def _on_copy(self, _action, _param):
        """Copy from terminal."""
        self._copy_current()

    def _on_paste(self, _action, _param):
        """Paste to terminal."""
        self._paste_current()

    def _copy_current(self):
        """Copy from the current terminal tab."""
        idx = self.notebook.get_current_page()
        if idx < len(self.tabs):
            self.tabs[idx].copy_clipboard()

    def _paste_current(self):
        """Paste to the current terminal tab."""
        idx = self.notebook.get_current_page()
        if idx < len(self.tabs):
            self.tabs[idx].paste_clipboard()

    def _on_search_toggle(self, _action, _param):
        """Toggle the search bar."""
        self._toggle_search()

    def _toggle_search(self):
        """Toggle search bar visibility."""
        idx = self.notebook.get_current_page()
        if idx < len(self.tabs) and hasattr(self.tabs[idx], 'search_bar'):
            search_bar = self.tabs[idx].search_bar
            if search_bar.get_visible():
                search_bar.hide()
            else:
                search_bar.show()
                search_bar.search_entry.grab_focus()


def main():
    """Application entry point."""
    try:
        app = AliciaTerminalApp()
        app.run(sys.argv)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
