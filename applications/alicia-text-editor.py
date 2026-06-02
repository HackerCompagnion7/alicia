#!/usr/bin/env python3
"""
Alicia Text Editor - Feature-rich text editor for the Alicia desktop environment.

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
import mimetypes
import time

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, Gio, GLib, Pango
except (ImportError, ValueError) as e:
    print(f"Error importing GTK3: {e}")
    sys.exit(1)

# Try to import GtkSourceView for syntax highlighting
HAS_SOURCEVIEW = False
try:
    gi.require_version('GtkSource', '3.0')
    from gi.repository import GtkSource
    HAS_SOURCEVIEW = True
except (ImportError, ValueError):
    print("Warning: GtkSourceView not available. Using basic Gtk.TextView fallback.")

# Constants
APP_NAME = "Alicia Text Editor"
APP_ID = "com.proyectoTomorrow.alicia.texteditor"
VERSION = "3.1.0"
CONFIG_DIR = os.path.expanduser("~/.config/alicia")
RECENT_FILE = os.path.join(CONFIG_DIR, "editor-recent.json")
MAX_RECENT = 10

# Language mapping from file extensions
LANG_MAP = {
    ".py": "python3", ".js": "javascript", ".html": "html", ".css": "css",
    ".c": "c", ".cpp": "cpp", ".h": "c", ".hpp": "cpp", ".java": "java",
    ".sh": "sh", ".bash": "sh", ".xml": "xml", ".json": "json",
    ".yaml": "yaml", ".yml": "yaml", ".toml": "toml", ".rs": "rust",
    ".go": "go", ".rb": "ruby", ".php": "php", ".sql": "sql",
    ".md": "markdown", ".txt": "text", ".ini": "ini", ".csv": "csv",
    ".ts": "typescript", ".tsx": "typescript", ".jsx": "javascript",
    ".vala": "vala", ".lua": "lua", ".perl": "perl", ".pl": "perl",
    ".r": "r", ".R": "r", ".tex": "latex", ".cmake": "cmake",
    ".makefile": "makefile", ".dockerfile": "dockerfile",
}

# Color schemes
COLOR_SCHEMES = ["classic", "cobalt", "kate", "oblivion", "solarized-dark",
                 "solarized-light", "tango"]


class RecentFiles:
    """Manages the recent files list."""

    def __init__(self):
        self.files = []
        self._load()

    def _load(self):
        """Load recent files from disk."""
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            if os.path.exists(RECENT_FILE):
                with open(RECENT_FILE, 'r') as f:
                    self.files = json.load(f)
        except (IOError, json.JSONDecodeError):
            self.files = []

    def _save(self):
        """Save recent files to disk."""
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            with open(RECENT_FILE, 'w') as f:
                json.dump(self.files[:MAX_RECENT], f, indent=2)
        except IOError:
            pass

    def add(self, path):
        """Add a file to the recent files list."""
        path = os.path.abspath(path)
        if path in self.files:
            self.files.remove(path)
        self.files.insert(0, path)
        self.files = self.files[:MAX_RECENT]
        self._save()

    def get_list(self):
        """Return the list of recent files."""
        return [f for f in self.files if os.path.isfile(f)]


class EditorTab:
    """Represents a single editor tab with a file."""

    def __init__(self, filepath=None, source_manager=None):
        self.filepath = filepath
        self.modified = False
        self.source_manager = source_manager
        self.language_id = "text"

        if filepath:
            self.display_name = os.path.basename(filepath)
            self._detect_language(filepath)
        else:
            self.display_name = "Untitled"

        self._build_editor()
        if filepath and os.path.isfile(filepath):
            self._load_file(filepath)

    def _detect_language(self, filepath):
        """Detect the source language from file extension or name."""
        basename = os.path.basename(filepath).lower()

        # Special filenames
        special_names = {
            "makefile": "makefile", "dockerfile": "dockerfile",
            "cmakelists.txt": "cmake", "gemfile": "ruby",
            "vagrantfile": "ruby", "rakefile": "ruby",
        }
        if basename in special_names:
            self.language_id = special_names[basename]
            return

        ext = os.path.splitext(filepath)[1].lower()
        self.language_id = LANG_MAP.get(ext, "text")

    def _build_editor(self):
        """Build the text editor widget."""
        self.scrolled = Gtk.ScrolledWindow()
        self.scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)

        if HAS_SOURCEVIEW and self.source_manager:
            self.buffer = GtkSource.Buffer()
            self._set_language()

            self.view = GtkSource.View.new_with_buffer(self.buffer)
            self.view.set_show_line_numbers(True)
            self.view.set_auto_indent(True)
            self.view.set_indent_on_tab(True)
            self.view.set_tab_width(4)
            self.view.set_insert_spaces_instead_of_tabs(True)
            self.view.set_smart_backspace(True)
            self.view.set_highlight_current_line(True)
            self.view.set_show_right_margin(True)
            self.view.set_right_margin_position(80)

            # Bracket matching
            try:
                self.view.set_highlight_matching_brackets(True)
            except Exception:
                pass

            # Color scheme
            self._set_color_scheme("classic")
        else:
            self.buffer = Gtk.TextBuffer()
            self.view = Gtk.TextView.new_with_buffer(self.buffer)
            self.view.set_monospace(True)

        self.view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.view.set_vexpand(True)
        self.view.set_hexpand(True)
        self.view.set_left_margin(4)
        self.view.set_right_margin(4)
        self.view.set_top_margin(4)
        self.view.set_bottom_margin(4)

        # Font
        try:
            font_desc = Pango.FontDescription("Monospace 12")
            self.view.override_font(font_desc)
        except Exception:
            pass

        self.scrolled.add(self.view)

        # Connect modified signal
        self.buffer.connect("modified-changed", self._on_modified_changed)

    def _set_language(self):
        """Set the source language for syntax highlighting."""
        if not HAS_SOURCEVIEW or not self.source_manager:
            return

        lang = self.source_manager.get_language(self.language_id)
        if lang:
            self.buffer.set_language(lang)
        else:
            self.buffer.set_language(None)

    def _set_color_scheme(self, scheme_name):
        """Set the color scheme for the source view."""
        if not HAS_SOURCEVIEW or not self.source_manager:
            return

        scheme = self.source_manager.get_scheme(scheme_name)
        if scheme:
            self.buffer.set_style_scheme(scheme)
        else:
            # Try default
            scheme = self.source_manager.get_scheme("classic")
            if scheme:
                self.buffer.set_style_scheme(scheme)

    def _load_file(self, filepath):
        """Load a file into the editor buffer."""
        try:
            with open(filepath, 'r', errors='replace') as f:
                content = f.read()
            start = self.buffer.get_start_iter()
            end = self.buffer.get_end_iter()
            self.buffer.begin_not_undoable_action()
            self.buffer.set_text(content)
            self.buffer.end_not_undoable_action()
            self.buffer.set_modified(False)
            self.modified = False
        except (IOError, OSError) as e:
            print(f"Error loading file {filepath}: {e}")

    def save_file(self, filepath=None):
        """Save the buffer contents to a file."""
        if filepath:
            self.filepath = filepath
            self.display_name = os.path.basename(filepath)
            self._detect_language(filepath)
            self._set_language()

        if not self.filepath:
            return False

        try:
            start = self.buffer.get_start_iter()
            end = self.buffer.get_end_iter()
            content = self.buffer.get_text(start, end, True)

            # Create parent directory if needed
            parent_dir = os.path.dirname(self.filepath)
            if parent_dir and not os.path.exists(parent_dir):
                os.makedirs(parent_dir, exist_ok=True)

            with open(self.filepath, 'w') as f:
                f.write(content)

            self.buffer.set_modified(False)
            self.modified = False
            return True
        except (IOError, OSError) as e:
            print(f"Error saving file {self.filepath}: {e}")
            return False

    def _on_modified_changed(self, _buffer):
        """Handle buffer modified state change."""
        self.modified = self.buffer.get_modified()

    def get_cursor_position(self):
        """Get the current cursor line and column."""
        mark = self.buffer.get_insert()
        iterator = self.buffer.get_iter_at_mark(mark)
        line = iterator.get_line() + 1
        column = iterator.get_line_offset() + 1
        return line, column

    def get_widget(self):
        """Get the main widget for this tab."""
        return self.scrolled

    def grab_focus(self):
        """Focus the editor view."""
        self.view.grab_focus()

    def set_font(self, font_name):
        """Set the editor font."""
        try:
            font_desc = Pango.FontDescription(font_name)
            self.view.override_font(font_desc)
        except Exception:
            pass

    def set_word_wrap(self, enabled):
        """Toggle word wrap."""
        if enabled:
            self.view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        else:
            self.view.set_wrap_mode(Gtk.WrapMode.NONE)


class SearchReplaceBar(Gtk.Box):
    """Search and replace bar."""

    def __init__(self, editor_app):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.editor = editor_app
        self.set_margin_top(4)
        self.set_margin_bottom(4)
        self.set_margin_start(8)
        self.set_margin_end(8)

        # Search row
        search_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)

        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Find...")
        self.search_entry.connect("search-changed", self._on_search)
        self.search_entry.connect("key-press-event", self._on_search_key)
        search_row.pack_start(self.search_entry, True, True, 0)

        prev_btn = Gtk.Button()
        prev_btn.set_image(Gtk.Image.new_from_icon_name("go-up", Gtk.IconSize.BUTTON))
        prev_btn.set_tooltip_text("Previous (Shift+Enter)")
        prev_btn.connect("clicked", self._on_prev)
        search_row.pack_start(prev_btn, False, False, 0)

        next_btn = Gtk.Button()
        next_btn.set_image(Gtk.Image.new_from_icon_name("go-down", Gtk.IconSize.BUTTON))
        next_btn.set_tooltip_text("Next (Enter)")
        next_btn.connect("clicked", self._on_next)
        search_row.pack_start(next_btn, False, False, 0)

        close_btn = Gtk.Button()
        close_btn.set_image(Gtk.Image.new_from_icon_name("window-close", Gtk.IconSize.BUTTON))
        close_btn.connect("clicked", self._on_close)
        search_row.pack_start(close_btn, False, False, 0)

        self.pack_start(search_row, False, False, 0)

        # Replace row
        replace_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)

        self.replace_entry = Gtk.Entry()
        self.replace_entry.set_placeholder_text("Replace with...")
        replace_row.pack_start(self.replace_entry, True, True, 0)

        replace_btn = Gtk.Button(label="Replace")
        replace_btn.connect("clicked", self._on_replace)
        replace_row.pack_start(replace_btn, False, False, 0)

        replace_all_btn = Gtk.Button(label="Replace All")
        replace_all_btn.connect("clicked", self._on_replace_all)
        replace_row.pack_start(replace_all_btn, False, False, 0)

        self.pack_start(replace_row, False, False, 0)

        self.search_tag = None
        self._create_highlight_tag()

    def _create_highlight_tag(self):
        """Create a text tag for search highlighting."""
        # Will be applied per-tab
        pass

    def _highlight_search(self):
        """Highlight all occurrences of the search term."""
        tab = self.editor._get_current_tab()
        if not tab:
            return

        buf = tab.buffer
        # Remove existing highlights
        buf.remove_tag_by_name("search-highlight", buf.get_start_iter(), buf.get_end_iter())

        query = self.search_entry.get_text()
        if not query:
            return

        # Create tag if not exists
        try:
            tag_table = buf.get_tag_table()
            if not tag_table.lookup("search-highlight"):
                buf.create_tag("search-highlight",
                               background="yellow", foreground="black")
        except Exception:
            return

        text = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)
        idx = 0
        while True:
            idx = text.find(query, idx)
            if idx == -1:
                break
            start = buf.get_iter_at_offset(idx)
            end = buf.get_iter_at_offset(idx + len(query))
            buf.apply_tag_by_name("search-highlight", start, end)
            idx += 1

    def _on_search(self, entry):
        """Handle search text change."""
        self._highlight_search()

    def _on_search_key(self, _widget, event):
        """Handle key press in search entry."""
        if event.keyval == Gdk.KEY_Return:
            if event.state & Gdk.ModifierType.SHIFT_MASK:
                self._on_prev(None)
            else:
                self._on_next(None)
            return True
        return False

    def _on_prev(self, _btn):
        """Go to previous match."""
        tab = self.editor._get_current_tab()
        if not tab:
            return
        query = self.search_entry.get_text()
        if not query:
            return
        buf = tab.buffer
        cursor = buf.get_iter_at_mark(buf.get_insert())
        cursor.backward_char()
        text = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)
        cursor_offset = cursor.get_offset()
        idx = text.rfind(query, 0, cursor_offset)
        if idx >= 0:
            start = buf.get_iter_at_offset(idx)
            end = buf.get_iter_at_offset(idx + len(query))
            buf.select_range(start, end)
            tab.view.scroll_to_iter(start, 0, False, 0, 0)

    def _on_next(self, _btn):
        """Go to next match."""
        tab = self.editor._get_current_tab()
        if not tab:
            return
        query = self.search_entry.get_text()
        if not query:
            return
        buf = tab.buffer
        cursor = buf.get_iter_at_mark(buf.get_insert())
        text = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)
        cursor_offset = cursor.get_offset()
        idx = text.find(query, cursor_offset + 1)
        if idx >= 0:
            start = buf.get_iter_at_offset(idx)
            end = buf.get_iter_at_offset(idx + len(query))
            buf.select_range(start, end)
            tab.view.scroll_to_iter(start, 0, False, 0, 0)

    def _on_replace(self, _btn):
        """Replace the current selection."""
        tab = self.editor._get_current_tab()
        if not tab:
            return
        buf = tab.buffer
        query = self.search_entry.get_text()
        replacement = self.replace_entry.get_text()

        start = buf.get_start_iter()
        end = buf.get_end_iter()
        if buf.get_has_selection():
            start, end = buf.get_selection_bounds()
            selected = buf.get_text(start, end, True)
            if selected == query:
                buf.begin_user_action()
                buf.delete(start, end)
                buf.insert(start, replacement)
                buf.end_user_action()
                self._highlight_search()

    def _on_replace_all(self, _btn):
        """Replace all occurrences."""
        tab = self.editor._get_current_tab()
        if not tab:
            return
        buf = tab.buffer
        query = self.search_entry.get_text()
        replacement = self.replace_entry.get_text()
        if not query:
            return

        text = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), True)
        new_text = text.replace(query, replacement)
        buf.begin_user_action()
        buf.set_text(new_text)
        buf.end_user_action()
        self._highlight_search()

    def _on_close(self, _btn):
        """Close the search bar."""
        self.hide()
        # Remove highlights
        tab = self.editor._get_current_tab()
        if tab:
            tab.buffer.remove_tag_by_name("search-highlight",
                                           tab.buffer.get_start_iter(),
                                           tab.buffer.get_end_iter())
            tab.grab_focus()


class GoToLineDialog(Gtk.Dialog):
    """Dialog for jumping to a specific line number."""

    def __init__(self, parent, max_line):
        super().__init__(title="Go to Line", parent=parent,
                         modal=True, destroy_with_parent=True)
        self.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                         Gtk.STOCK_OK, Gtk.ResponseType.OK)
        self.set_default_size(250, 100)

        box = self.get_content_area()
        box.set_spacing(8)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        box.pack_start(Gtk.Label(label=f"Line number (1-{max_line}):"), False, False, 0)
        self.line_entry = Gtk.SpinButton.new_with_range(1, max_line, 1)
        self.line_entry.set_activates_default(True)
        box.pack_start(self.line_entry, True, True, 0)
        self.set_default_response(Gtk.ResponseType.OK)
        self.show_all()


class AliciaTextEditor(Gtk.Application):
    """Main Text Editor application class."""

    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.tabs = []
        self.notebook = None
        self.recent_files = RecentFiles()
        self.source_manager = None
        self.word_wrap = True
        self.search_bar = None

        if HAS_SOURCEVIEW:
            try:
                self.source_manager = GtkSource.LanguageManager.get_default()
                self.style_scheme_manager = GtkSource.StyleSchemeManager.get_default()
            except Exception:
                self.source_manager = None

    def do_activate(self):
        """Handle application activation."""
        win = self.props.active_window
        if not win:
            win = self._build_window()
        win.present()

    def do_open(self, files, _n_files, _hint):
        """Handle opening files from command line."""
        for gfile in files:
            path = gfile.get_path()
            if path:
                self._open_file(path)

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

        # Menu button
        menu_btn = Gtk.MenuButton()
        menu = Gio.Menu()
        menu.append("New", "app.new_file")
        menu.append("Open...", "app.open_file")
        menu.append("Save", "app.save_file")
        menu.append("Save As...", "app.save_as")
        menu.append(None, None)
        submenu = Gio.Menu()
        submenu.append("Undo", "app.undo")
        submenu.append("Redo", "app.redo")
        submenu.append("Cut", "app.cut")
        submenu.append("Copy", "app.copy")
        submenu.append("Paste", "app.paste")
        submenu.append("Select All", "app.select_all")
        menu.append_submenu("Edit", submenu)

        view_menu = Gio.Menu()
        view_menu.append("Word Wrap", "app.word_wrap")
        view_menu.append("Font...", "app.font_select")
        view_menu.append("Color Scheme...", "app.color_scheme")
        menu.append_submenu("View", view_menu)

        search_menu = Gio.Menu()
        search_menu.append("Find and Replace", "app.search")
        search_menu.append("Go to Line...", "app.goto_line")
        menu.append_submenu("Search", search_menu)

        menu.append("Close Tab", "app.close_tab")
        menu_btn.set_menu_model(menu)
        menu_btn.set_image(Gtk.Image.new_from_icon_name("open-menu", Gtk.IconSize.BUTTON))
        header.pack_end(menu_btn)

        # New/Open buttons in header
        new_btn = Gtk.Button()
        new_btn.set_image(Gtk.Image.new_from_icon_name("document-new", Gtk.IconSize.BUTTON))
        new_btn.set_tooltip_text("New File (Ctrl+N)")
        new_btn.set_action_name("app.new_file")
        header.pack_start(new_btn)

        open_btn = Gtk.Button()
        open_btn.set_image(Gtk.Image.new_from_icon_name("document-open", Gtk.IconSize.BUTTON))
        open_btn.set_tooltip_text("Open File (Ctrl+O)")
        open_btn.set_action_name("app.open_file")
        header.pack_start(open_btn)

        save_btn = Gtk.Button()
        save_btn.set_image(Gtk.Image.new_from_icon_name("document-save", Gtk.IconSize.BUTTON))
        save_btn.set_tooltip_text("Save (Ctrl+S)")
        save_btn.set_action_name("app.save_file")
        header.pack_start(save_btn)

        # Recent files button
        recent_btn = Gtk.MenuButton()
        recent_menu = Gio.Menu()
        for fpath in self.recent_files.get_list()[:5]:
            recent_menu.append(os.path.basename(fpath), f"app.recent::{fpath}")
        recent_btn.set_menu_model(recent_menu)
        recent_btn.set_image(Gtk.Image.new_from_icon_name("document-open-recent", Gtk.IconSize.BUTTON))
        recent_btn.set_tooltip_text("Recent Files")
        header.pack_start(recent_btn)

        # Register actions
        self._register_actions()

        # Main layout
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Notebook for tabs
        self.notebook = Gtk.Notebook()
        self.notebook.set_scrollable(True)
        self.notebook.set_show_border(True)
        self.notebook.connect("switch-page", self._on_switch_page)
        main_box.pack_start(self.notebook, True, True, 0)

        # Search bar (hidden by default)
        self.search_bar = SearchReplaceBar(self)
        self.search_bar.set_no_show_all(True)
        main_box.pack_start(self.search_bar, False, False, 0)

        # Status bar
        status_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        status_box.set_margin_top(2)
        status_box.set_margin_bottom(2)
        status_box.set_margin_start(8)
        status_box.set_margin_end(8)
        status_box.get_style_context().add_class("background")

        self.status_position = Gtk.Label(label="Ln 1, Col 1")
        self.status_position.set_halign(Gtk.Align.START)
        status_box.pack_start(self.status_position, False, False, 0)

        self.status_encoding = Gtk.Label(label="UTF-8")
        self.status_encoding.set_halign(Gtk.Align.CENTER)
        status_box.pack_start(self.status_encoding, True, True, 0)

        self.status_language = Gtk.Label(label="Plain Text")
        self.status_language.set_halign(Gtk.Align.END)
        status_box.pack_start(self.status_language, False, False, 0)

        main_box.pack_start(status_box, False, False, 0)

        win.add(main_box)

        # Keyboard shortcuts
        self._setup_shortcuts(win)

        # Create initial tab
        self._new_file()

        # Start cursor position update timer
        GLib.timeout_add(500, self._update_status_bar)

        win.show_all()
        return win

    def _register_actions(self):
        """Register all application actions."""
        actions = {
            "new_file": self._action_new_file,
            "open_file": self._action_open_file,
            "save_file": self._action_save_file,
            "save_as": self._action_save_as,
            "close_tab": self._action_close_tab,
            "undo": self._action_undo,
            "redo": self._action_redo,
            "cut": self._action_cut,
            "copy": self._action_copy,
            "paste": self._action_paste,
            "select_all": self._action_select_all,
            "search": self._action_search,
            "goto_line": self._action_goto_line,
            "word_wrap": self._action_word_wrap,
            "font_select": self._action_font_select,
            "color_scheme": self._action_color_scheme,
        }

        for name, callback in actions.items():
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", callback)
            self.add_action(action)

        # Recent files action with parameter
        recent_action = Gio.SimpleAction.new("recent", GLib.VariantType.new("s"))
        recent_action.connect("activate", self._action_recent)
        self.add_action(recent_action)

    def _setup_shortcuts(self, win):
        """Set up keyboard shortcuts."""
        accel = Gtk.AccelGroup()
        shortcuts = [
            (Gdk.KEY_n, Gdk.ModifierType.CONTROL_MASK, self._accel_new),
            (Gdk.KEY_o, Gdk.ModifierType.CONTROL_MASK, self._accel_open),
            (Gdk.KEY_s, Gdk.ModifierType.CONTROL_MASK, self._accel_save),
            (Gdk.KEY_s, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK, self._accel_save_as),
            (Gdk.KEY_w, Gdk.ModifierType.CONTROL_MASK, self._accel_close),
            (Gdk.KEY_f, Gdk.ModifierType.CONTROL_MASK, self._accel_search),
            (Gdk.KEY_z, Gdk.ModifierType.CONTROL_MASK, self._accel_undo),
            (Gdk.KEY_y, Gdk.ModifierType.CONTROL_MASK, self._accel_redo),
            (Gdk.KEY_g, Gdk.ModifierType.CONTROL_MASK, self._accel_goto),
        ]
        for key, mod, callback in shortcuts:
            accel.connect(key, mod, Gtk.AccelFlags.VISIBLE, callback)
        win.add_accel_group(accel)

    # Accelerator callbacks
    def _accel_new(self, *_): self._action_new_file(None, None)
    def _accel_open(self, *_): self._action_open_file(None, None)
    def _accel_save(self, *_): self._action_save_file(None, None)
    def _accel_save_as(self, *_): self._action_save_as(None, None)
    def _accel_close(self, *_): self._action_close_tab(None, None)
    def _accel_search(self, *_): self._action_search(None, None)
    def _accel_undo(self, *_): self._action_undo(None, None)
    def _accel_redo(self, *_): self._action_redo(None, None)
    def _accel_goto(self, *_): self._action_goto_line(None, None)

    def _get_current_tab(self):
        """Get the currently active editor tab."""
        idx = self.notebook.get_current_page()
        if 0 <= idx < len(self.tabs):
            return self.tabs[idx]
        return None

    def _new_file(self):
        """Create a new empty editor tab."""
        tab = EditorTab(source_manager=self.source_manager)
        tab.set_word_wrap(self.word_wrap)
        self._add_tab(tab)

    def _open_file(self, filepath):
        """Open a file in a new tab."""
        # Check if file is already open
        for i, existing_tab in enumerate(self.tabs):
            if existing_tab.filepath and os.path.abspath(existing_tab.filepath) == os.path.abspath(filepath):
                self.notebook.set_current_page(i)
                return

        tab = EditorTab(filepath=filepath, source_manager=self.source_manager)
        tab.set_word_wrap(self.word_wrap)
        self._add_tab(tab)
        self.recent_files.add(filepath)

    def _add_tab(self, tab):
        """Add an editor tab to the notebook."""
        self.tabs.append(tab)

        # Tab label
        tab_label_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        tab_label = Gtk.Label(label=tab.display_name)
        tab_label.set_max_width_chars(20)
        tab_label.set_ellipsize(Pango.EllipsizeMode.END)

        close_btn = Gtk.Button()
        close_btn.set_image(Gtk.Image.new_from_icon_name("window-close", Gtk.IconSize.MENU))
        close_btn.set_relief(Gtk.ReliefStyle.NONE)
        idx = len(self.tabs) - 1
        close_btn.connect("clicked", self._on_close_tab_btn, idx)

        tab_label_box.pack_start(tab_label, True, True, 0)
        tab_label_box.pack_start(close_btn, False, False, 0)
        tab_label_box.show_all()

        # Store reference to label for updating
        tab.tab_label = tab_label

        page_num = self.notebook.append_page(tab.get_widget(), tab_label_box)
        self.notebook.set_current_page(page_num)
        self.notebook.show_all()
        tab.grab_focus()

    def _on_switch_page(self, _notebook, _page, page_num):
        """Handle tab switch."""
        if page_num < len(self.tabs):
            self._update_status_bar()
            # Update title
            tab = self.tabs[page_num]
            title = tab.display_name
            if tab.modified:
                title = f"• {title}"
            self.props.active_window.set_title(f"{title} — {APP_NAME}")

    def _on_close_tab_btn(self, _btn, idx):
        """Handle tab close button."""
        self._close_tab(idx)

    def _close_tab(self, idx):
        """Close a specific tab."""
        if idx < 0 or idx >= len(self.tabs):
            return
        tab = self.tabs[idx]

        if tab.modified:
            # Ask to save
            response = self._confirm_save(tab)
            if response == Gtk.ResponseType.CANCEL:
                return
            elif response == Gtk.ResponseType.YES:
                if not tab.save_file():
                    return

        self.tabs.pop(idx)
        self.notebook.remove_page(idx)

        if len(self.tabs) == 0:
            self._new_file()

    def _confirm_save(self, tab):
        """Show a save confirmation dialog."""
        dialog = Gtk.MessageDialog(
            parent=self.props.active_window,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.NONE,
            text=f"Save changes to '{tab.display_name}'?"
        )
        dialog.add_button("Don't Save", Gtk.ResponseType.NO)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Save", Gtk.ResponseType.YES)
        dialog.set_default_response(Gtk.ResponseType.YES)
        response = dialog.run()
        dialog.destroy()
        return response

    # Action handlers
    def _action_new_file(self, _action, _param):
        self._new_file()

    def _action_open_file(self, _action, _param):
        dialog = Gtk.FileChooserDialog(
            title="Open File", parent=self.props.active_window,
            action=Gtk.FileChooserAction.OPEN,
        )
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        dialog.set_select_multiple(True)

        # File filters
        text_filter = Gtk.FileFilter()
        text_filter.set_name("Text Files")
        text_filter.add_mime_type("text/*")
        dialog.add_filter(text_filter)

        all_filter = Gtk.FileFilter()
        all_filter.set_name("All Files")
        all_filter.add_pattern("*")
        dialog.add_filter(all_filter)

        if dialog.run() == Gtk.ResponseType.OK:
            for filepath in dialog.get_filenames():
                self._open_file(filepath)
        dialog.destroy()

    def _action_save_file(self, _action, _param):
        tab = self._get_current_tab()
        if not tab:
            return
        if not tab.filepath:
            self._action_save_as(None, None)
            return
        if tab.save_file():
            self.recent_files.add(tab.filepath)
        else:
            self._show_error(f"Could not save file: {tab.filepath}")

    def _action_save_as(self, _action, _param):
        tab = self._get_current_tab()
        if not tab:
            return
        dialog = Gtk.FileChooserDialog(
            title="Save File As", parent=self.props.active_window,
            action=Gtk.FileChooserAction.SAVE,
        )
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_SAVE, Gtk.ResponseType.OK)
        dialog.set_do_overwrite_confirmation(True)
        if tab.filepath:
            dialog.set_filename(tab.filepath)
        if dialog.run() == Gtk.ResponseType.OK:
            filepath = dialog.get_filename()
            if tab.save_file(filepath):
                self.recent_files.add(filepath)
                tab.tab_label.set_text(tab.display_name)
        dialog.destroy()

    def _action_close_tab(self, _action, _param):
        idx = self.notebook.get_current_page()
        self._close_tab(idx)

    def _action_undo(self, _action, _param):
        tab = self._get_current_tab()
        if tab and tab.buffer.can_undo():
            tab.buffer.undo()

    def _action_redo(self, _action, _param):
        tab = self._get_current_tab()
        if tab and tab.buffer.can_redo():
            tab.buffer.redo()

    def _action_cut(self, _action, _param):
        tab = self._get_current_tab()
        if tab:
            clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
            tab.view.emit("cut-clipboard")

    def _action_copy(self, _action, _param):
        tab = self._get_current_tab()
        if tab:
            tab.view.emit("copy-clipboard")

    def _action_paste(self, _action, _param):
        tab = self._get_current_tab()
        if tab:
            tab.view.emit("paste-clipboard")

    def _action_select_all(self, _action, _param):
        tab = self._get_current_tab()
        if tab:
            tab.view.emit("select-all")

    def _action_search(self, _action, _param):
        if self.search_bar.get_visible():
            self.search_bar.hide()
            tab = self._get_current_tab()
            if tab:
                tab.grab_focus()
        else:
            self.search_bar.show()
            self.search_bar.search_entry.grab_focus()

    def _action_goto_line(self, _action, _param):
        tab = self._get_current_tab()
        if not tab:
            return
        line_count = tab.buffer.get_line_count()
        dialog = GoToLineDialog(self.props.active_window, line_count)
        if dialog.run() == Gtk.ResponseType.OK:
            line = int(dialog.line_entry.get_value()) - 1
            iterator = tab.buffer.get_iter_at_line(line)
            tab.buffer.place_cursor(iterator)
            tab.view.scroll_to_iter(iterator, 0.2, True, 0, 0.5)
            tab.grab_focus()
        dialog.destroy()

    def _action_word_wrap(self, _action, _param):
        self.word_wrap = not self.word_wrap
        for tab in self.tabs:
            tab.set_word_wrap(self.word_wrap)

    def _action_font_select(self, _action, _param):
        dialog = Gtk.FontChooserDialog(
            title="Select Font", parent=self.props.active_window
        )
        dialog.set_font("Monospace 12")
        if dialog.run() == Gtk.ResponseType.OK:
            font_name = dialog.get_font()
            for tab in self.tabs:
                tab.set_font(font_name)
        dialog.destroy()

    def _action_color_scheme(self, _action, _param):
        if not HAS_SOURCEVIEW:
            self._show_info("Color schemes require GtkSourceView.")
            return

        dialog = Gtk.Dialog(title="Color Scheme", parent=self.props.active_window,
                            modal=True, destroy_with_parent=True)
        dialog.add_button(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        dialog.set_default_size(350, 300)

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)

        schemes = self.style_scheme_manager.get_scheme_ids()
        for scheme_id in schemes:
            try:
                scheme = self.style_scheme_manager.get_scheme(scheme_id)
                row = Gtk.ListBoxRow()
                label = Gtk.Label(label=scheme.get_name())
                label.set_margin_top(6)
                label.set_margin_bottom(6)
                label.set_margin_start(12)
                row.add(label)
                row.scheme_id = scheme_id
                listbox.add(row)
            except Exception:
                continue

        listbox.connect("row-activated", self._on_scheme_selected)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add(listbox)
        dialog.get_content_area().pack_start(scrolled, True, True, 0)
        dialog.show_all()
        dialog.run()
        dialog.destroy()

    def _on_scheme_selected(self, _listbox, row):
        """Handle color scheme selection."""
        if not HAS_SOURCEVIEW or not hasattr(row, 'scheme_id'):
            return
        scheme_id = row.scheme_id
        for tab in self.tabs:
            tab._set_color_scheme(scheme_id)

    def _action_recent(self, _action, param):
        """Open a recent file."""
        filepath = param.get_string()
        if filepath and os.path.isfile(filepath):
            self._open_file(filepath)

    def _update_status_bar(self):
        """Update the status bar with current cursor position and info."""
        tab = self._get_current_tab()
        if tab:
            line, col = tab.get_cursor_position()
            self.status_position.set_text(f"Ln {line}, Col {col}")
            self.status_language.set_text(tab.language_id.upper() if tab.language_id != "text" else "Plain Text")

            # Update tab title
            title = tab.display_name
            if tab.modified:
                title = f"• {title}"
                if hasattr(tab, 'tab_label') and tab.tab_label:
                    tab.tab_label.set_text(f"• {tab.display_name}")
            else:
                if hasattr(tab, 'tab_label') and tab.tab_label:
                    tab.tab_label.set_text(tab.display_name)

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
        app = AliciaTextEditor()
        app.run(sys.argv)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
