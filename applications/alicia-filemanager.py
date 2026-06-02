#!/usr/bin/env python3
"""
Alicia File Manager - Custom file manager for the Alicia desktop environment.

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
import stat
import shutil
import subprocess
import datetime
import tempfile

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, Gio, GLib, Pango, GdkPixbuf
except (ImportError, ValueError) as e:
    print(f"Error importing GTK3: {e}")
    print("Please install PyGObject: pip install PyGObject")
    sys.exit(1)

# Constants
APP_NAME = "Alicia File Manager"
APP_ID = "com.proyectoTomorrow.alicia.filemanager"
VERSION = "3.1.0"

# Bookmarks: (name, path, icon)
DEFAULT_BOOKMARKS = [
    ("Home", os.path.expanduser("~"), "user-home"),
    ("Desktop", os.path.expanduser("~/Desktop"), "user-desktop"),
    ("Documents", os.path.expanduser("~/Documents"), "folder-documents"),
    ("Downloads", os.path.expanduser("~/Downloads"), "folder-download"),
    ("Music", os.path.expanduser("~/Music"), "folder-music"),
    ("Pictures", os.path.expanduser("~/Pictures"), "folder-pictures"),
    ("Videos", os.path.expanduser("~/Videos"), "folder-videos"),
    ("Trash", os.path.expanduser("~/.local/share/Trash"), "user-trash"),
]

# File type icons mapping
FILE_ICONS = {
    "directory": "folder",
    "text": "text-x-generic",
    "image": "image-x-generic",
    "audio": "audio-x-generic",
    "video": "video-x-generic",
    "pdf": "application-pdf",
    "archive": "package-x-generic",
    "executable": "application-x-executable",
    "code": "text-x-script",
    "default": "text-x-generic",
}

IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".bmp", ".svg", ".webp", ".ico"}
AUDIO_EXTENSIONS = {".mp3", ".wav", ".ogg", ".flac", ".aac", ".m4a", ".wma"}
VIDEO_EXTENSIONS = {".mp4", ".avi", ".mkv", ".mov", ".wmv", ".flv", ".webm"}
ARCHIVE_EXTENSIONS = {".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar"}
CODE_EXTENSIONS = {".py", ".js", ".html", ".css", ".c", ".cpp", ".h", ".java",
                   ".sh", ".bash", ".xml", ".json", ".yaml", ".yml", ".toml",
                   ".rs", ".go", ".rb", ".php", ".sql", ".md"}


def get_file_icon(path, is_dir=False):
    """Get the appropriate icon name for a file."""
    if is_dir:
        return FILE_ICONS["directory"]
    ext = os.path.splitext(path)[1].lower()
    if ext in IMAGE_EXTENSIONS:
        return FILE_ICONS["image"]
    if ext in AUDIO_EXTENSIONS:
        return FILE_ICONS["audio"]
    if ext in VIDEO_EXTENSIONS:
        return FILE_ICONS["video"]
    if ext == ".pdf":
        return FILE_ICONS["pdf"]
    if ext in ARCHIVE_EXTENSIONS:
        return FILE_ICONS["archive"]
    if ext in CODE_EXTENSIONS:
        return FILE_ICONS["code"]
    # Check if executable
    try:
        st = os.stat(path)
        if st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            return FILE_ICONS["executable"]
    except OSError:
        pass
    return FILE_ICONS["default"]


def format_size(size):
    """Format file size in human-readable form."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} PB"


def format_timestamp(ts):
    """Format a Unix timestamp to a readable string."""
    try:
        dt = datetime.datetime.fromtimestamp(ts)
        return dt.strftime("%Y-%m-%d %H:%M")
    except (OSError, ValueError):
        return "Unknown"


class FileOperation:
    """Handles file copy/move/delete operations with undo support."""

    def __init__(self):
        self.clipboard_files = []
        self.clipboard_mode = None  # 'copy' or 'cut'

    def copy_files(self, files):
        """Store files for copying."""
        self.clipboard_files = list(files)
        self.clipboard_mode = 'copy'

    def cut_files(self, files):
        """Store files for moving."""
        self.clipboard_files = list(files)
        self.clipboard_mode = 'cut'

    def paste_files(self, dest_dir, progress_cb=None):
        """Paste clipboard files to destination directory."""
        results = []
        errors = []
        for src in self.clipboard_files:
            basename = os.path.basename(src)
            dest = os.path.join(dest_dir, basename)
            # Avoid overwriting
            dest = self._unique_path(dest)
            try:
                if self.clipboard_mode == 'copy':
                    if os.path.isdir(src):
                        shutil.copytree(src, dest, symlinks=True)
                    else:
                        shutil.copy2(src, dest)
                    results.append(dest)
                elif self.clipboard_mode == 'cut':
                    shutil.move(src, dest)
                    results.append(dest)
            except (OSError, shutil.Error) as e:
                errors.append((src, str(e)))
        if self.clipboard_mode == 'cut':
            self.clipboard_files = []
            self.clipboard_mode = None
        return results, errors

    def _unique_path(self, path):
        """Generate a unique file path if one already exists."""
        if not os.path.exists(path):
            return path
        base, ext = os.path.splitext(path)
        counter = 1
        while os.path.exists(f"{base} ({counter}){ext}"):
            counter += 1
        return f"{base} ({counter}){ext}"


class BreadcrumbBar(Gtk.Box):
    """Breadcrumb navigation bar for the file manager."""

    def __init__(self, file_manager):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        self.fm = file_manager
        self.set_margin_top(4)
        self.set_margin_bottom(4)
        self.set_margin_start(4)
        self.set_margin_end(4)

    def update_path(self, path):
        """Update breadcrumb buttons from a path."""
        for child in self.get_children():
            self.remove(child)

        parts = path.split(os.sep)
        if path.startswith('/'):
            parts = [''] + [p for p in parts if p]

        for i, part in enumerate(parts):
            if i > 0:
                sep = Gtk.Label(label=" / ")
                sep.get_style_context().add_class("dim-label")
                self.pack_start(sep, False, False, 0)

            if part == '':
                label = "/"
            else:
                label = part

            btn = Gtk.Button(label=label)
            btn.set_relief(Gtk.ReliefStyle.NONE)

            # Build path up to this point
            sub_path = os.sep.join(parts[:i + 1]) if i > 0 else '/'
            btn.connect("clicked", self._on_breadcrumb_click, sub_path)
            self.pack_start(btn, False, False, 0)

        self.show_all()

    def _on_breadcrumb_click(self, _btn, path):
        """Handle breadcrumb button click."""
        self.fm.navigate_to(path)


class SidebarPanel(Gtk.ScrolledWindow):
    """Side panel with bookmarks and devices."""

    def __init__(self, file_manager):
        super().__init__()
        self.fm = file_manager
        self.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.set_size_request(180, -1)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Bookmarks header
        header = Gtk.Label(label="Places", halign=Gtk.Align.START)
        header.set_margin_top(8)
        header.set_margin_start(8)
        header.get_style_context().add_class("dim-label")
        box.pack_start(header, False, False, 0)

        self.bookmark_list = Gtk.ListBox()
        self.bookmark_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.bookmark_list.connect("row-activated", self._on_bookmark_activated)

        self._load_bookmarks()

        box.pack_start(self.bookmark_list, False, False, 0)
        self.add(box)

    def _load_bookmarks(self):
        """Load bookmarks into the sidebar."""
        for child in self.bookmark_list.get_children():
            self.bookmark_list.remove(child)

        for name, path, icon_name in DEFAULT_BOOKMARKS:
            row = Gtk.ListBoxRow()
            h_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            h_box.set_margin_top(4)
            h_box.set_margin_bottom(4)
            h_box.set_margin_start(8)
            h_box.set_margin_end(8)

            icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.MENU)
            label = Gtk.Label(label=name, halign=Gtk.Align.START)
            h_box.pack_start(icon, False, False, 0)
            h_box.pack_start(label, True, True, 0)
            row.add(h_box)
            row.path = path
            self.bookmark_list.add(row)

        # Add root filesystem
        row = Gtk.ListBoxRow()
        h_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        h_box.set_margin_top(4)
        h_box.set_margin_bottom(4)
        h_box.set_margin_start(8)
        h_box.set_margin_end(8)
        icon = Gtk.Image.new_from_icon_name("drive-harddisk", Gtk.IconSize.MENU)
        label = Gtk.Label(label="File System", halign=Gtk.Align.START)
        h_box.pack_start(icon, False, False, 0)
        h_box.pack_start(label, True, True, 0)
        row.add(h_box)
        row.path = "/"
        self.bookmark_list.add(row)

        self.bookmark_list.show_all()

    def _on_bookmark_activated(self, _listbox, row):
        """Handle bookmark activation."""
        if hasattr(row, 'path'):
            self.fm.navigate_to(row.path)


class PropertiesDialog(Gtk.Dialog):
    """File/directory properties dialog."""

    def __init__(self, parent, path):
        super().__init__(title=f"Properties - {os.path.basename(path)}",
                         parent=parent, modal=True, destroy_with_parent=True)
        self.add_button(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        self.set_default_size(400, 450)

        box = self.get_content_area()
        box.set_spacing(8)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        try:
            st = os.lstat(path)
        except OSError as e:
            box.pack_start(Gtk.Label(label=f"Error: {e}"), True, True, 0)
            self.show_all()
            return

        is_dir = os.path.isdir(path)
        icon_name = get_file_icon(path, is_dir)
        icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.DIALOG)

        name_label = Gtk.Label()
        name_label.set_markup(f"<b>{os.path.basename(path)}</b>")

        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        header_box.pack_start(icon, False, False, 0)
        header_box.pack_start(name_label, False, False, 0)
        box.pack_start(header_box, False, False, 0)

        # Info grid
        grid = Gtk.Grid(row_spacing=6, column_spacing=12)
        grid.set_margin_top(12)
        row = 0

        info_items = [
            ("Type:", "Directory" if is_dir else "File"),
            ("Location:", os.path.dirname(path)),
            ("Size:", format_size(st.st_size) if not is_dir else self._dir_size(path)),
            ("Modified:", format_timestamp(st.st_mtime)),
            ("Accessed:", format_timestamp(st.st_atime)),
            ("Permissions:", stat.filemode(st.st_mode)),
            ("Owner UID:", str(st.st_uid)),
            ("Group GID:", str(st.st_gid)),
        ]

        for label_text, value in info_items:
            label = Gtk.Label(label=label_text, halign=Gtk.Align.END)
            label.get_style_context().add_class("dim-label")
            val = Gtk.Label(label=value, halign=Gtk.Align.START, selectable=True)
            grid.attach(label, 0, row, 1, 1)
            grid.attach(val, 1, row, 1, 1)
            row += 1

        box.pack_start(grid, False, False, 0)

        # Permissions checkboxes
        perm_frame = Gtk.Frame(label="Permissions")
        perm_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        perm_box.set_margin_top(8)
        perm_box.set_margin_bottom(8)
        perm_box.set_margin_start(12)
        perm_box.set_margin_end(12)

        self.perm_checks = {}
        for perm_name, perm_bit in [("Read", stat.S_IRUSR), ("Write", stat.S_IWUSR),
                                     ("Execute", stat.S_IXUSR)]:
            check = Gtk.CheckButton(label=perm_name)
            check.set_active(bool(st.st_mode & perm_bit))
            perm_box.pack_start(check, False, False, 0)
            self.perm_checks[perm_name] = (check, perm_bit)

        perm_frame.add(perm_box)
        box.pack_start(perm_frame, False, False, 0)

        self.show_all()

    def _dir_size(self, path):
        """Calculate directory size."""
        total = 0
        try:
            for dirpath, _dirnames, filenames in os.walk(path):
                for fname in filenames:
                    try:
                        total += os.path.getsize(os.path.join(dirpath, fname))
                    except OSError:
                        pass
        except OSError:
            pass
        return format_size(total)


class AliciaFileManager(Gtk.Application):
    """Main File Manager application class."""

    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.current_dir = os.path.expanduser("~")
        self.file_op = FileOperation()
        self.show_hidden = False
        self.sort_column = 0  # 0=name, 1=size, 2=date
        self.sort_ascending = True
        self.history = []
        self.history_index = -1

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
        win.set_default_size(900, 600)
        win.set_position(Gtk.WindowPosition.CENTER)

        # Header bar
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title(APP_NAME)
        win.set_titlebar(header)

        # Navigation buttons
        back_btn = Gtk.Button()
        back_btn.set_image(Gtk.Image.new_from_icon_name("go-previous", Gtk.IconSize.BUTTON))
        back_btn.set_tooltip_text("Go Back")
        back_btn.connect("clicked", self._on_go_back)
        header.pack_start(back_btn)

        forward_btn = Gtk.Button()
        forward_btn.set_image(Gtk.Image.new_from_icon_name("go-next", Gtk.IconSize.BUTTON))
        forward_btn.set_tooltip_text("Go Forward")
        forward_btn.connect("clicked", self._on_go_forward)
        header.pack_start(forward_btn)

        up_btn = Gtk.Button()
        up_btn.set_image(Gtk.Image.new_from_icon_name("go-up", Gtk.IconSize.BUTTON))
        up_btn.set_tooltip_text("Go Up")
        up_btn.connect("clicked", self._on_go_up)
        header.pack_start(up_btn)

        # Search
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search files...")
        self.search_entry.connect("search-changed", self._on_search)
        header.pack_end(self.search_entry)

        # View toggle
        menu_btn = Gtk.MenuButton()
        menu = Gio.Menu()
        menu.append("Toggle Hidden Files", "app.toggle_hidden")
        menu.append("Sort by Name", "app.sort_name")
        menu.append("Sort by Size", "app.sort_size")
        menu.append("Sort by Date", "app.sort_date")
        menu_btn.set_menu_model(menu)
        menu_btn.set_image(Gtk.Image.new_from_icon_name("view-more", Gtk.IconSize.BUTTON))
        header.pack_end(menu_btn)

        # App actions
        toggle_hidden_action = Gio.SimpleAction.new("toggle_hidden", None)
        toggle_hidden_action.connect("activate", self._on_toggle_hidden)
        self.add_action(toggle_hidden_action)

        for name, col in [("sort_name", 0), ("sort_size", 1), ("sort_date", 2)]:
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda a, p, c=col: self._on_sort(a, p, c))
            self.add_action(action)

        # Main layout
        main_paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)

        # Sidebar
        self.sidebar = SidebarPanel(self)
        main_paned.pack1(self.sidebar, False, False)

        # Right side: breadcrumb + file view
        right_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Breadcrumb bar
        self.breadcrumb = BreadcrumbBar(self)
        right_box.pack_start(self.breadcrumb, False, False, 0)

        # File view
        self.file_store = Gtk.ListStore(
            GdkPixbuf.Pixbuf,  # icon
            str,               # name
            str,               # size
            str,               # type
            str,               # modified
            str,               # full path (hidden)
            bool,              # is directory (hidden)
        )

        self.file_view = Gtk.TreeView(model=self.file_store)
        self.file_view.set_headers_visible(True)
        self.file_view.set_activate_on_single_click(False)
        self.file_view.connect("row-activated", self._on_row_activated)
        self.file_view.connect("button-press-event", self._on_button_press)

        # Enable drag and drop
        self.file_view.enable_model_drag_source(
            Gdk.ModifierType.BUTTON1_MASK, [], Gdk.DragAction.COPY | Gdk.DragAction.MOVE
        )
        self.file_view.enable_model_drag_dest([], Gdk.DragAction.COPY | Gdk.DragAction.MOVE)
        self.file_view.connect("drag-data-get", self._on_drag_data_get)
        self.file_view.connect("drag-data-received", self._on_drag_data_received)

        # Columns
        renderer_icon = Gtk.CellRendererPixbuf()
        renderer_text = Gtk.CellRendererText()

        col_name = Gtk.TreeViewColumn("Name", renderer_icon, pixbuf=0)
        col_name.pack_start(renderer_text, True)
        col_name.add_attribute(renderer_text, "text", 1)
        col_name.set_sort_column_id(1)
        col_name.set_min_width(250)
        col_name.set_resizable(True)
        self.file_view.append_column(col_name)

        col_size = Gtk.TreeViewColumn("Size", Gtk.CellRendererText(), text=2)
        col_size.set_min_width(80)
        col_size.set_resizable(True)
        self.file_view.append_column(col_size)

        col_type = Gtk.TreeViewColumn("Type", Gtk.CellRendererText(), text=3)
        col_type.set_min_width(100)
        col_type.set_resizable(True)
        self.file_view.append_column(col_type)

        col_modified = Gtk.TreeViewColumn("Modified", Gtk.CellRendererText(), text=4)
        col_modified.set_min_width(130)
        col_modified.set_resizable(True)
        self.file_view.append_column(col_modified)

        # Selection
        selection = self.file_view.get_selection()
        selection.set_mode(Gtk.SelectionMode.MULTIPLE)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add(self.file_view)
        right_box.pack_start(scrolled, True, True, 0)

        # Status bar
        self.status_bar = Gtk.Label(label="Ready")
        self.status_bar.set_halign(Gtk.Align.START)
        self.status_bar.set_margin_top(4)
        self.status_bar.set_margin_start(8)
        self.status_bar.get_style_context().add_class("dim-label")
        right_box.pack_start(self.status_bar, False, False, 0)

        main_paned.pack2(right_box, True, False)
        main_paned.set_position(180)

        win.add(main_paned)

        # Keyboard shortcuts
        self._setup_shortcuts(win)

        # Load initial directory
        self.navigate_to(self.current_dir, add_history=True)

        win.show_all()
        return win

    def _setup_shortcuts(self, win):
        """Set up keyboard shortcuts."""
        accel = Gtk.AccelGroup()
        accel.connect(Gdk.keyval_from_name("c"), Gdk.ModifierType.CONTROL_MASK,
                      Gtk.AccelFlags.VISIBLE, self._accel_copy)
        accel.connect(Gdk.keyval_from_name("x"), Gdk.ModifierType.CONTROL_MASK,
                      Gtk.AccelFlags.VISIBLE, self._accel_cut)
        accel.connect(Gdk.keyval_from_name("v"), Gdk.ModifierType.CONTROL_MASK,
                      Gtk.AccelFlags.VISIBLE, self._accel_paste)
        accel.connect(Gdk.keyval_from_name("Delete"), 0,
                      Gtk.AccelFlags.VISIBLE, self._accel_delete)
        accel.connect(Gdk.keyval_from_name("h"), Gdk.ModifierType.CONTROL_MASK,
                      Gtk.AccelFlags.VISIBLE, self._accel_toggle_hidden)
        win.add_accel_group(accel)

    def _accel_copy(self, *_args):
        self._copy_selected()

    def _accel_cut(self, *_args):
        self._cut_selected()

    def _accel_paste(self, *_args):
        self._paste_to_current()

    def _accel_delete(self, *_args):
        self._delete_selected()

    def _accel_toggle_hidden(self, *_args):
        self.show_hidden = not self.show_hidden
        self._load_directory(self.current_dir)

    def navigate_to(self, path, add_history=False):
        """Navigate to a directory path."""
        path = os.path.abspath(path)
        if not os.path.isdir(path):
            self._show_error(f"Directory not found: {path}")
            return

        self.current_dir = path
        if add_history:
            self.history = self.history[:self.history_index + 1]
            self.history.append(path)
            self.history_index = len(self.history) - 1

        self._load_directory(path)
        self.breadcrumb.update_path(path)
        self._update_status()

    def _load_directory(self, path):
        """Load directory contents into the file store."""
        self.file_store.clear()
        try:
            entries = os.listdir(path)
        except PermissionError:
            self._show_error(f"Permission denied: {path}")
            return
        except OSError as e:
            self._show_error(f"Error reading directory: {e}")
            return

        if not self.show_hidden:
            entries = [e for e in entries if not e.startswith('.')]

        items = []
        for name in entries:
            full_path = os.path.join(path, name)
            try:
                st = os.lstat(full_path)
            except OSError:
                continue

            is_dir = os.path.isdir(full_path)
            icon_name = get_file_icon(full_path, is_dir)

            try:
                icon_theme = Gtk.IconTheme.get_default()
                pixbuf = icon_theme.load_icon(icon_name, 24,
                                               Gtk.IconLookupFlags.FORCE_SIZE)
            except Exception:
                pixbuf = None

            if is_dir:
                size_str = "--"
                type_str = "Directory"
            else:
                size_str = format_size(st.st_size)
                ext = os.path.splitext(name)[1].lower()
                type_str = ext[1:].upper() + " File" if ext else "File"

            modified = format_timestamp(st.st_mtime)
            items.append((pixbuf, name, size_str, type_str, modified,
                          full_path, is_dir, st.st_mtime, st.st_size))

        # Sort items: directories first, then by selected column
        def sort_key(item):
            _, name, _, _, _, _, is_dir, mtime, fsize = item
            dir_priority = 0 if is_dir else 1
            if self.sort_column == 0:
                return (dir_priority, name.lower())
            elif self.sort_column == 1:
                return (dir_priority, fsize)
            else:
                return (dir_priority, mtime)

        items.sort(key=sort_key, reverse=not self.sort_ascending)

        for item in items:
            self.file_store.append(item[:7])

    def _update_status(self):
        """Update status bar with directory info."""
        count = len(self.file_store)
        dir_count = sum(1 for row in self.file_store if row[6])
        file_count = count - dir_count
        self.status_bar.set_text(
            f"{dir_count} directories, {file_count} files — {self.current_dir}"
        )

    def _on_row_activated(self, _treeview, path, _column):
        """Handle double-click on a file/directory."""
        model = self.file_view.get_model()
        tree_iter = model.get_iter(path)
        full_path = model.get_value(tree_iter, 5)
        is_dir = model.get_value(tree_iter, 6)

        if is_dir:
            self.navigate_to(full_path, add_history=True)
        else:
            self._open_file(full_path)

    def _open_file(self, path):
        """Open a file with the default application."""
        try:
            subprocess.Popen(["xdg-open", path],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            self._show_error(f"Cannot open file: {e}")

    def _on_button_press(self, _widget, event):
        """Handle mouse button press for context menu."""
        if event.button == 3:  # Right-click
            self._show_context_menu(event)
            return True
        return False

    def _show_context_menu(self, event):
        """Show the right-click context menu."""
        menu = Gtk.Menu()

        open_item = Gtk.MenuItem(label="Open")
        open_item.connect("activate", self._on_open_selected)
        menu.append(open_item)

        menu.append(Gtk.SeparatorMenuItem())

        copy_item = Gtk.MenuItem(label="Copy")
        copy_item.connect("activate", lambda _: self._copy_selected())
        menu.append(copy_item)

        cut_item = Gtk.MenuItem(label="Cut")
        cut_item.connect("activate", lambda _: self._cut_selected())
        menu.append(cut_item)

        paste_item = Gtk.MenuItem(label="Paste")
        paste_item.connect("activate", lambda _: self._paste_to_current())
        menu.append(paste_item)

        menu.append(Gtk.SeparatorMenuItem())

        rename_item = Gtk.MenuItem(label="Rename...")
        rename_item.connect("activate", self._on_rename)
        menu.append(rename_item)

        delete_item = Gtk.MenuItem(label="Delete")
        delete_item.connect("activate", lambda _: self._delete_selected())
        menu.append(delete_item)

        menu.append(Gtk.SeparatorMenuItem())

        new_folder_item = Gtk.MenuItem(label="New Folder")
        new_folder_item.connect("activate", lambda _: self._new_folder())
        menu.append(new_folder_item)

        new_file_item = Gtk.MenuItem(label="New File")
        new_file_item.connect("activate", lambda _: self._new_file())
        menu.append(new_file_item)

        menu.append(Gtk.SeparatorMenuItem())

        props_item = Gtk.MenuItem(label="Properties")
        props_item.connect("activate", self._on_properties)
        menu.append(props_item)

        menu.show_all()
        menu.popup_at_pointer(event)

    def _get_selected_paths(self):
        """Get list of selected file paths."""
        selection = self.file_view.get_selection()
        model, paths = selection.get_selected_rows()
        result = []
        for path in paths:
            tree_iter = model.get_iter(path)
            full_path = model.get_value(tree_iter, 5)
            result.append(full_path)
        return result

    def _on_open_selected(self, _item):
        """Open the selected file."""
        paths = self._get_selected_paths()
        for path in paths:
            if os.path.isdir(path):
                self.navigate_to(path, add_history=True)
            else:
                self._open_file(path)

    def _copy_selected(self):
        """Copy selected files to clipboard."""
        paths = self._get_selected_paths()
        if paths:
            self.file_op.copy_files(paths)

    def _cut_selected(self):
        """Cut selected files to clipboard."""
        paths = self._get_selected_paths()
        if paths:
            self.file_op.cut_files(paths)

    def _paste_to_current(self):
        """Paste files from clipboard to current directory."""
        if not self.file_op.clipboard_files:
            return
        results, errors = self.file_op.paste_files(self.current_dir)
        if errors:
            self._show_error(f"Errors during paste: {errors}")
        self._load_directory(self.current_dir)

    def _delete_selected(self):
        """Delete selected files after confirmation."""
        paths = self._get_selected_paths()
        if not paths:
            return

        file_list = "\n".join(os.path.basename(p) for p in paths[:10])
        if len(paths) > 10:
            file_list += f"\n... and {len(paths) - 10} more"

        confirm = Gtk.MessageDialog(
            parent=self.props.active_window,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f"Move {len(paths)} item(s) to trash?"
        )
        confirm.set_property("secondary-text", file_list)

        if confirm.run() == Gtk.ResponseType.YES:
            for path in paths:
                try:
                    # Try trash command first, fall back to delete
                    result = subprocess.run(
                        ["gio", "trash", path],
                        capture_output=True, timeout=10
                    )
                    if result.returncode != 0:
                        if os.path.isdir(path):
                            shutil.rmtree(path)
                        else:
                            os.remove(path)
                except Exception as e:
                    self._show_error(f"Error deleting {path}: {e}")

            self._load_directory(self.current_dir)
        confirm.destroy()

    def _on_rename(self, _item):
        """Rename the selected file."""
        paths = self._get_selected_paths()
        if len(paths) != 1:
            return

        old_path = paths[0]
        old_name = os.path.basename(old_path)

        dialog = Gtk.Dialog(title="Rename", parent=self.props.active_window,
                            modal=True, destroy_with_parent=True)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OK, Gtk.ResponseType.OK)
        dialog.set_default_size(350, 100)

        entry = Gtk.Entry()
        entry.set_text(old_name)
        entry.set_margin_top(12)
        entry.set_margin_bottom(12)
        entry.set_margin_start(12)
        entry.set_margin_end(12)
        entry.grab_focus()
        dialog.get_content_area().pack_start(entry, True, True, 0)
        dialog.show_all()

        if dialog.run() == Gtk.ResponseType.OK:
            new_name = entry.get_text().strip()
            if new_name and new_name != old_name:
                new_path = os.path.join(os.path.dirname(old_path), new_name)
                try:
                    os.rename(old_path, new_path)
                    self._load_directory(self.current_dir)
                except OSError as e:
                    self._show_error(f"Rename failed: {e}")
        dialog.destroy()

    def _new_folder(self):
        """Create a new folder in the current directory."""
        dialog = Gtk.Dialog(title="New Folder", parent=self.props.active_window,
                            modal=True, destroy_with_parent=True)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_CREATE, Gtk.ResponseType.OK)

        entry = Gtk.Entry()
        entry.set_text("New Folder")
        entry.set_margin_top(12)
        entry.set_margin_bottom(12)
        entry.set_margin_start(12)
        entry.set_margin_end(12)
        dialog.get_content_area().pack_start(entry, True, True, 0)
        dialog.show_all()

        if dialog.run() == Gtk.ResponseType.OK:
            name = entry.get_text().strip()
            if name:
                path = os.path.join(self.current_dir, name)
                try:
                    os.makedirs(path, exist_ok=True)
                    self._load_directory(self.current_dir)
                except OSError as e:
                    self._show_error(f"Cannot create folder: {e}")
        dialog.destroy()

    def _new_file(self):
        """Create a new file in the current directory."""
        dialog = Gtk.Dialog(title="New File", parent=self.props.active_window,
                            modal=True, destroy_with_parent=True)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_CREATE, Gtk.ResponseType.OK)

        entry = Gtk.Entry()
        entry.set_text("New File.txt")
        entry.set_margin_top(12)
        entry.set_margin_bottom(12)
        entry.set_margin_start(12)
        entry.set_margin_end(12)
        dialog.get_content_area().pack_start(entry, True, True, 0)
        dialog.show_all()

        if dialog.run() == Gtk.ResponseType.OK:
            name = entry.get_text().strip()
            if name:
                path = os.path.join(self.current_dir, name)
                try:
                    open(path, 'a').close()
                    self._load_directory(self.current_dir)
                except OSError as e:
                    self._show_error(f"Cannot create file: {e}")
        dialog.destroy()

    def _on_properties(self, _item):
        """Show properties dialog for selected file."""
        paths = self._get_selected_paths()
        if len(paths) == 1:
            dialog = PropertiesDialog(self.props.active_window, paths[0])
            dialog.run()
            dialog.destroy()

    def _on_go_back(self, _btn):
        """Navigate back in history."""
        if self.history_index > 0:
            self.history_index -= 1
            self.navigate_to(self.history[self.history_index])

    def _on_go_forward(self, _btn):
        """Navigate forward in history."""
        if self.history_index < len(self.history) - 1:
            self.history_index += 1
            self.navigate_to(self.history[self.history_index])

    def _on_go_up(self, _btn):
        """Navigate to parent directory."""
        parent = os.path.dirname(self.current_dir)
        if parent != self.current_dir:
            self.navigate_to(parent, add_history=True)

    def _on_search(self, entry):
        """Filter files by search query."""
        query = entry.get_text().strip().lower()
        if not query:
            self._load_directory(self.current_dir)
            return

        # Simple in-directory search
        self.file_store.clear()
        try:
            for name in os.listdir(self.current_dir):
                if not self.show_hidden and name.startswith('.'):
                    continue
                if query in name.lower():
                    full_path = os.path.join(self.current_dir, name)
                    try:
                        st = os.lstat(full_path)
                    except OSError:
                        continue

                    is_dir = os.path.isdir(full_path)
                    icon_name = get_file_icon(full_path, is_dir)
                    try:
                        icon_theme = Gtk.IconTheme.get_default()
                        pixbuf = icon_theme.load_icon(icon_name, 24,
                                                       Gtk.IconLookupFlags.FORCE_SIZE)
                    except Exception:
                        pixbuf = None

                    size_str = "--" if is_dir else format_size(st.st_size)
                    type_str = "Directory" if is_dir else "File"
                    modified = format_timestamp(st.st_mtime)

                    self.file_store.append((pixbuf, name, size_str, type_str,
                                            modified, full_path, is_dir))
        except OSError:
            pass

    def _on_toggle_hidden(self, _action, _param):
        """Toggle display of hidden files."""
        self.show_hidden = not self.show_hidden
        self._load_directory(self.current_dir)

    def _on_sort(self, _action, _param, column):
        """Sort files by a column."""
        if self.sort_column == column:
            self.sort_ascending = not self.sort_ascending
        else:
            self.sort_column = column
            self.sort_ascending = True
        self._load_directory(self.current_dir)

    def _on_drag_data_get(self, _widget, _drag_context, data, info, _time):
        """Provide drag data for drag and drop."""
        paths = self._get_selected_paths()
        if paths:
            uris = [GLib.filename_to_uri(p) for p in paths]
            data.set_uris(uris)

    def _on_drag_data_received(self, _widget, _drag_context, x, y, data, info, _time):
        """Handle drag and drop data received."""
        uris = data.get_uris()
        if not uris:
            return

        for uri in uris:
            try:
                src_path = GLib.filename_from_uri(uri)[0]
                basename = os.path.basename(src_path)
                dest_path = os.path.join(self.current_dir, basename)
                dest_path = self.file_op._unique_path(dest_path)

                if data.get_selected_action() == Gdk.DragAction.MOVE:
                    shutil.move(src_path, dest_path)
                else:
                    if os.path.isdir(src_path):
                        shutil.copytree(src_path, dest_path)
                    else:
                        shutil.copy2(src_path, dest_path)
            except Exception as e:
                self._show_error(f"Drag and drop error: {e}")

        self._load_directory(self.current_dir)

    def _show_error(self, msg):
        """Show an error dialog."""
        win = self.props.active_window
        dialog = Gtk.MessageDialog(
            parent=win, message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK, text=str(msg)
        )
        dialog.run()
        dialog.destroy()


def main():
    """Application entry point."""
    try:
        app = AliciaFileManager()
        app.run(sys.argv)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
