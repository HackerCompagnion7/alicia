#!/usr/bin/env python3
"""
Alicia Screenshot - Screenshot capture tool for the Alicia desktop environment.

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
Version: 2.0.0
"""

import os
import sys
import subprocess
import time
import glob as glob_module
import shutil

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, Gio, GLib, Pango, GdkPixbuf
except (ImportError, ValueError) as e:
    print(f"Error importing GTK3: {e}")
    sys.exit(1)

# Constants
APP_NAME = "Alicia Screenshot"
APP_ID = "com.proyectoTomorrow.alicia.screenshot"
VERSION = "2.0.0"
SCREENSHOT_DIR = os.path.expanduser("~/Pictures/Screenshots")
HISTORY_FILE = os.path.expanduser("~/.config/alicia/screenshot-history.txt")
MAX_HISTORY = 20

# Screenshot backends (in order of preference)
BACKENDS = ["xfce4-screenshooter", "scrot", "import", "gnome-screenshot"]


def detect_backend():
    """Detect available screenshot backend."""
    for backend in BACKENDS:
        if shutil.which(backend):
            return backend
    return None


def generate_filename():
    """Generate a timestamp-based filename for the screenshot."""
    timestamp = time.strftime("%Y-%m-%d_%H-%M-%S")
    return f"alicia-screenshot-{timestamp}.png"


def ensure_screenshot_dir():
    """Ensure the screenshot directory exists."""
    os.makedirs(SCREENSHOT_DIR, exist_ok=True)


class ScreenshotHistory:
    """Manages the screenshot history list."""

    def __init__(self):
        self.entries = []
        self._load()

    def _load(self):
        """Load history from file."""
        try:
            os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
            if os.path.exists(HISTORY_FILE):
                with open(HISTORY_FILE, 'r') as f:
                    self.entries = [line.strip() for line in f if line.strip()]
        except IOError:
            self.entries = []

    def _save(self):
        """Save history to file."""
        try:
            os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
            with open(HISTORY_FILE, 'w') as f:
                for entry in self.entries[:MAX_HISTORY]:
                    f.write(f"{entry}\n")
        except IOError:
            pass

    def add(self, filepath):
        """Add a screenshot to the history."""
        if os.path.isfile(filepath):
            self.entries.insert(0, filepath)
            self.entries = self.entries[:MAX_HISTORY]
            self._save()

    def get_list(self):
        """Get the list of history entries that still exist."""
        return [f for f in self.entries if os.path.isfile(f)]

    def clear(self):
        """Clear the history."""
        self.entries = []
        self._save()


class ScreenshotCapture:
    """Handles screenshot capture using available system backends."""

    def __init__(self):
        self.backend = detect_backend()

    def capture_fullscreen(self, output_path, delay=0):
        """Capture the full screen."""
        if delay > 0:
            time.sleep(delay)

        if self.backend == "xfce4-screenshooter":
            return self._capture_xfce4("fullscreen", output_path)
        elif self.backend == "scrot":
            return self._capture_scrot(output_path, delay=0)
        elif self.backend == "import":
            return self._capture_import_window(output_path)
        elif self.backend == "gnome-screenshot":
            return self._capture_gnome("window", output_path)
        else:
            return self._capture_fallback(output_path)

    def capture_window(self, output_path, delay=0):
        """Capture the active window."""
        if delay > 0:
            time.sleep(delay)

        if self.backend == "xfce4-screenshooter":
            return self._capture_xfce4("window", output_path)
        elif self.backend == "scrot":
            return self._capture_scrot(output_path, delay=0, window=True)
        elif self.backend == "import":
            return self._capture_import_window(output_path)
        elif self.backend == "gnome-screenshot":
            return self._capture_gnome("window", output_path)
        else:
            return self._capture_fallback(output_path)

    def capture_selection(self, output_path, delay=0):
        """Capture a screen selection/area."""
        if delay > 0:
            time.sleep(delay)

        if self.backend == "xfce4-screenshooter":
            return self._capture_xfce4("region", output_path)
        elif self.backend == "scrot":
            return self._capture_scrot(output_path, delay=0, selection=True)
        elif self.backend == "import":
            return self._capture_import_selection(output_path)
        elif self.backend == "gnome-screenshot":
            return self._capture_gnome("area", output_path)
        else:
            return self._capture_fallback(output_path)

    def _capture_xfce4(self, mode, output_path):
        """Capture using xfce4-screenshooter."""
        try:
            mode_map = {"fullscreen": "full", "window": "window", "region": "region"}
            cmd = ["xfce4-screenshooter", f"--{mode_map.get(mode, 'full')}", "-s", output_path]
            result = subprocess.run(cmd, capture_output=True, timeout=60)
            return result.returncode == 0 or os.path.isfile(output_path)
        except Exception:
            return os.path.isfile(output_path)

    def _capture_scrot(self, output_path, delay=0, window=False, selection=False):
        """Capture using scrot."""
        try:
            cmd = ["scrot", output_path]
            if window:
                cmd = ["scrot", "-u", output_path]
            elif selection:
                cmd = ["scrot", "-s", output_path]
            if delay > 0:
                cmd.insert(1, f"-d{delay}")
            result = subprocess.run(cmd, capture_output=True, timeout=60)
            return os.path.isfile(output_path)
        except Exception:
            return False

    def _capture_import_window(self, output_path):
        """Capture using ImageMagick import (window)."""
        try:
            result = subprocess.run(
                ["import", "-window", "root", output_path],
                capture_output=True, timeout=60
            )
            return os.path.isfile(output_path)
        except Exception:
            return False

    def _capture_import_selection(self, output_path):
        """Capture using ImageMagick import (selection)."""
        try:
            result = subprocess.run(
                ["import", output_path],
                capture_output=True, timeout=120
            )
            return os.path.isfile(output_path)
        except Exception:
            return False

    def _capture_gnome(self, mode, output_path):
        """Capture using gnome-screenshot."""
        try:
            mode_map = {"window": "-w", "area": "-a"}
            cmd = ["gnome-screenshot", mode_map.get(mode, ""), "-f", output_path]
            cmd = [c for c in cmd if c]
            result = subprocess.run(cmd, capture_output=True, timeout=60)
            return os.path.isfile(output_path)
        except Exception:
            return False

    def _capture_fallback(self, output_path):
        """Fallback capture using xdotool + import."""
        try:
            # Try xdotool to get active window
            result = subprocess.run(
                ["xdotool", "getactivewindow"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                window_id = result.stdout.strip()
                result = subprocess.run(
                    ["import", "-window", window_id, output_path],
                    capture_output=True, timeout=60
                )
                return os.path.isfile(output_path)
        except Exception:
            pass

        # Last resort: try to capture root window
        try:
            result = subprocess.run(
                ["import", "-window", "root", output_path],
                capture_output=True, timeout=60
            )
            return os.path.isfile(output_path)
        except Exception:
            return False


class AliciaScreenshot(Gtk.Application):
    """Main Screenshot application class."""

    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.capture = ScreenshotCapture()
        self.history = ScreenshotHistory()
        self.last_screenshot_path = None
        self.preview_pixbuf = None

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
        win.set_default_size(600, 500)
        win.set_position(Gtk.WindowPosition.CENTER)

        # Header bar
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title(APP_NAME)
        win.set_titlebar(header)

        # Capture button
        capture_btn = Gtk.Button(label="Take Screenshot")
        capture_btn.get_style_context().add_class("suggested-action")
        capture_btn.connect("clicked", self._on_capture)
        header.pack_start(capture_btn)

        # History button
        history_btn = Gtk.Button()
        history_btn.set_image(Gtk.Image.new_from_icon_name("document-open-recent", Gtk.IconSize.BUTTON))
        history_btn.set_tooltip_text("Screenshot History")
        history_btn.connect("clicked", self._on_show_history)
        header.pack_end(history_btn)

        # Main content
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        main_box.set_margin_top(16)
        main_box.set_margin_bottom(16)
        main_box.set_margin_start(16)
        main_box.set_margin_end(16)

        # Capture mode selection
        mode_frame = Gtk.Frame(label="Capture Mode")
        mode_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        mode_box.set_margin_top(8)
        mode_box.set_margin_bottom(8)
        mode_box.set_margin_start(12)
        mode_box.set_margin_end(12)

        self.mode_group = None
        modes = [
            ("fullscreen", "Full Screen", "Capture the entire screen"),
            ("window", "Active Window", "Capture the currently focused window"),
            ("selection", "Selection", "Select an area of the screen to capture"),
        ]

        self.mode_buttons = {}
        for i, (mode_id, label, tooltip) in enumerate(modes):
            btn = Gtk.RadioButton.new_with_label_from_widget(self.mode_group, label)
            btn.set_tooltip_text(tooltip)
            if i == 0:
                self.mode_group = btn
            btn.set_active(i == 0)
            mode_box.pack_start(btn, False, False, 0)
            self.mode_buttons[mode_id] = btn

        mode_frame.add(mode_box)
        main_box.pack_start(mode_frame, False, False, 0)

        # Delay timer
        delay_frame = Gtk.Frame(label="Delay Timer")
        delay_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        delay_box.set_margin_top(8)
        delay_box.set_margin_bottom(8)
        delay_box.set_margin_start(12)
        delay_box.set_margin_end(12)

        delay_label = Gtk.Label(label="Delay (seconds):")
        delay_box.pack_start(delay_label, False, False, 0)

        self.delay_spin = Gtk.SpinButton.new_with_range(0, 10, 1)
        self.delay_spin.set_value(0)
        delay_box.pack_start(self.delay_spin, True, True, 0)

        delay_frame.add(delay_box)
        main_box.pack_start(delay_frame, False, False, 0)

        # Save options
        save_frame = Gtk.Frame(label="Save Options")
        save_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        save_box.set_margin_top(8)
        save_box.set_margin_bottom(8)
        save_box.set_margin_start(12)
        save_box.set_margin_end(12)

        # Auto-save toggle
        self.auto_save_check = Gtk.CheckButton(label="Save automatically to screenshots folder")
        self.auto_save_check.set_active(True)
        save_box.pack_start(self.auto_save_check, False, False, 0)

        # Custom save path
        path_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.save_path_entry = Gtk.Entry()
        self.save_path_entry.set_text(os.path.join(SCREENSHOT_DIR, generate_filename()))
        self.save_path_entry.set_hexpand(True)
        path_box.pack_start(self.save_path_entry, True, True, 0)

        browse_btn = Gtk.Button(label="Browse...")
        browse_btn.connect("clicked", self._on_browse_save)
        path_box.pack_start(browse_btn, False, False, 0)

        save_box.pack_start(path_box, False, False, 0)

        # Open after capture
        self.open_after_check = Gtk.CheckButton(label="Open in image viewer after capture")
        self.open_after_check.set_active(False)
        save_box.pack_start(self.open_after_check, False, False, 0)

        # Copy to clipboard
        self.clipboard_check = Gtk.CheckButton(label="Copy to clipboard after capture")
        self.clipboard_check.set_active(False)
        save_box.pack_start(self.clipboard_check, False, False, 0)

        save_frame.add(save_box)
        main_box.pack_start(save_frame, False, False, 0)

        # Preview area
        preview_frame = Gtk.Frame(label="Preview")
        self.preview_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        self.preview_image = Gtk.Image()
        self.preview_image.set_size_request(-1, 180)
        self.preview_label = Gtk.Label(label="No screenshot captured yet")
        self.preview_label.get_style_context().add_class("dim-label")
        self.preview_label.set_margin_top(60)
        self.preview_label.set_margin_bottom(60)

        self.preview_box.pack_start(self.preview_label, True, True, 0)
        preview_frame.add(self.preview_box)
        main_box.pack_start(preview_frame, True, True, 0)

        # Action buttons after capture
        self.action_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.action_box.set_no_show_all(True)

        self.save_btn = Gtk.Button(label="Save")
        self.save_btn.connect("clicked", self._on_save)
        self.action_box.pack_start(self.save_btn, False, False, 0)

        self.copy_btn = Gtk.Button(label="Copy to Clipboard")
        self.copy_btn.connect("clicked", self._on_copy_clipboard)
        self.action_box.pack_start(self.copy_btn, False, False, 0)

        self.open_btn = Gtk.Button(label="Open in Viewer")
        self.open_btn.connect("clicked", self._on_open_viewer)
        self.action_box.pack_start(self.open_btn, False, False, 0)

        self.folder_btn = Gtk.Button(label="Open Folder")
        self.folder_btn.connect("clicked", self._on_open_folder)
        self.action_box.pack_start(self.folder_btn, False, False, 0)

        main_box.pack_start(self.action_box, False, False, 0)

        # Backend info
        backend_name = self.capture.backend or "None (screenshots may not work)"
        backend_label = Gtk.Label()
        backend_label.set_markup(f"<small>Backend: {backend_name}</small>")
        backend_label.get_style_context().add_class("dim-label")
        main_box.pack_start(backend_label, False, False, 0)

        win.add(main_box)
        win.show_all()
        return win

    def _get_capture_mode(self):
        """Get the selected capture mode."""
        for mode_id, btn in self.mode_buttons.items():
            if btn.get_active():
                return mode_id
        return "fullscreen"

    def _on_capture(self, _btn):
        """Take a screenshot."""
        mode = self._get_capture_mode()
        delay = int(self.delay_spin.get_value())

        ensure_screenshot_dir()

        if self.auto_save_check.get_active():
            output_path = os.path.join(SCREENSHOT_DIR, generate_filename())
        else:
            output_path = self.save_path_entry.get_text().strip()
            if not output_path:
                output_path = os.path.join(SCREENSHOT_DIR, generate_filename())

        # Hide the window during capture
        win = self.props.active_window
        if delay > 0 or mode == "fullscreen":
            win.iconify()
            # Give window manager time to hide the window
            GLib.timeout_add(delay * 1000 + 300, self._do_capture, mode, output_path, win)
        else:
            self._do_capture(mode, output_path, win)

    def _do_capture(self, mode, output_path, win):
        """Perform the actual screenshot capture."""
        success = False

        try:
            if mode == "fullscreen":
                success = self.capture.capture_fullscreen(output_path)
            elif mode == "window":
                success = self.capture.capture_window(output_path)
            elif mode == "selection":
                success = self.capture.capture_selection(output_path)
        except Exception as e:
            self._show_error(f"Capture failed: {e}")
            win.present()
            return

        win.present()

        if success and os.path.isfile(output_path):
            self.last_screenshot_path = output_path
            self._update_preview(output_path)
            self.history.add(output_path)
            self.save_path_entry.set_text(output_path)

            # Auto actions
            if self.clipboard_check.get_active():
                self._copy_to_clipboard(output_path)
            if self.open_after_check.get_active():
                self._open_in_viewer(output_path)

            # Show action buttons
            self.action_box.set_no_show_all(False)
            self.action_box.show_all()
        else:
            self._show_error(
                f"Screenshot capture failed.\n"
                f"Backend: {self.capture.backend or 'None'}\n"
                f"Please ensure a screenshot tool is installed (scrot, xfce4-screenshooter, or ImageMagick)."
            )

    def _update_preview(self, filepath):
        """Update the preview image."""
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(filepath, 500, 200)
            self.preview_image.set_from_pixbuf(pixbuf)
            self.preview_pixbuf = pixbuf

            # Replace placeholder label with image
            for child in self.preview_box.get_children():
                self.preview_box.remove(child)
            self.preview_box.pack_start(self.preview_image, True, True, 0)
            self.preview_box.show_all()
        except Exception as e:
            self.preview_label.set_text(f"Preview unavailable: {e}")

    def _on_browse_save(self, _btn):
        """Browse for save location."""
        dialog = Gtk.FileChooserDialog(
            title="Save Screenshot As",
            parent=self.props.active_window,
            action=Gtk.FileChooserAction.SAVE,
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_SAVE, Gtk.ResponseType.OK,
        )
        dialog.set_do_overwrite_confirmation(True)
        dialog.set_current_name(generate_filename())

        png_filter = Gtk.FileFilter()
        png_filter.set_name("PNG Image")
        png_filter.add_pattern("*.png")
        dialog.add_filter(png_filter)

        if dialog.run() == Gtk.ResponseType.OK:
            self.save_path_entry.set_text(dialog.get_filename())
        dialog.destroy()

    def _on_save(self, _btn):
        """Save the last screenshot to a new location."""
        if not self.last_screenshot_path or not os.path.isfile(self.last_screenshot_path):
            self._show_error("No screenshot to save.")
            return

        dialog = Gtk.FileChooserDialog(
            title="Save Screenshot As",
            parent=self.props.active_window,
            action=Gtk.FileChooserAction.SAVE,
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_SAVE, Gtk.ResponseType.OK,
        )
        dialog.set_do_overwrite_confirmation(True)
        dialog.set_filename(self.last_screenshot_path)

        if dialog.run() == Gtk.ResponseType.OK:
            dest = dialog.get_filename()
            try:
                shutil.copy2(self.last_screenshot_path, dest)
                self._show_info(f"Screenshot saved to: {dest}")
            except (IOError, OSError) as e:
                self._show_error(f"Could not save: {e}")
        dialog.destroy()

    def _on_copy_clipboard(self, _btn):
        """Copy the last screenshot to the clipboard."""
        if self.last_screenshot_path:
            self._copy_to_clipboard(self.last_screenshot_path)

    def _copy_to_clipboard(self, filepath):
        """Copy a screenshot image to the clipboard."""
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file(filepath)
            clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
            clipboard.set_image(pixbuf)
            clipboard.store()
        except Exception as e:
            self._show_error(f"Could not copy to clipboard: {e}")

    def _on_open_viewer(self, _btn):
        """Open the last screenshot in an image viewer."""
        if self.last_screenshot_path:
            self._open_in_viewer(self.last_screenshot_path)

    def _open_in_viewer(self, filepath):
        """Open a file in the default image viewer."""
        try:
            subprocess.Popen(["xdg-open", filepath],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            self._show_error(f"Could not open image viewer: {e}")

    def _on_open_folder(self, _btn):
        """Open the screenshots folder in the file manager."""
        folder = SCREENSHOT_DIR
        if self.last_screenshot_path:
            folder = os.path.dirname(self.last_screenshot_path)
        try:
            subprocess.Popen(["xdg-open", folder],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            self._show_error(f"Could not open file manager: {e}")

    def _on_show_history(self, _btn):
        """Show the screenshot history dialog."""
        dialog = Gtk.Dialog(title="Screenshot History", parent=self.props.active_window,
                            modal=True, destroy_with_parent=True)
        dialog.add_button(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        dialog.set_default_size(500, 400)

        box = dialog.get_content_area()

        # History list
        store = Gtk.ListStore(str, str)  # path, basename
        for filepath in self.history.get_list():
            store.append([filepath, os.path.basename(filepath)])

        tree = Gtk.TreeView(model=store)
        renderer = Gtk.CellRendererText()
        col = Gtk.TreeViewColumn("Screenshot", renderer, text=1)
        tree.append_column(col)
        tree.connect("row-activated", self._on_history_row_activated)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add(tree)
        box.pack_start(scrolled, True, True, 0)

        # Buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        btn_box.set_margin_top(8)

        open_btn = Gtk.Button(label="Open Selected")
        open_btn.connect("clicked", self._on_history_open, tree, store, dialog)
        btn_box.pack_start(open_btn, False, False, 0)

        delete_btn = Gtk.Button(label="Delete Selected")
        delete_btn.connect("clicked", self._on_history_delete, tree, store)
        btn_box.pack_start(delete_btn, False, False, 0)

        clear_btn = Gtk.Button(label="Clear History")
        clear_btn.connect("clicked", self._on_history_clear, store)
        btn_box.pack_start(clear_btn, False, False, 0)

        box.pack_start(btn_box, False, False, 0)
        dialog.show_all()
        dialog.run()
        dialog.destroy()

    def _on_history_row_activated(self, _treeview, path, _column):
        """Handle double-click on history entry."""
        pass  # Handled by Open button

    def _on_history_open(self, _btn, tree, store, parent_dialog):
        """Open the selected history screenshot."""
        selection = tree.get_selection()
        model, tree_iter = selection.get_selected()
        if tree_iter:
            filepath = model.get_value(tree_iter, 0)
            parent_dialog.destroy()
            self._open_in_viewer(filepath)

    def _on_history_delete(self, _btn, tree, store):
        """Delete the selected history screenshot file."""
        selection = tree.get_selection()
        model, tree_iter = selection.get_selected()
        if tree_iter:
            filepath = model.get_value(tree_iter, 0)
            confirm = Gtk.MessageDialog(
                parent=self.props.active_window,
                message_type=Gtk.MessageType.WARNING,
                buttons=Gtk.ButtonsType.YES_NO,
                text=f"Delete '{os.path.basename(filepath)}'?"
            )
            if confirm.run() == Gtk.ResponseType.YES:
                try:
                    os.remove(filepath)
                    store.remove(tree_iter)
                except OSError as e:
                    self._show_error(f"Could not delete: {e}")
            confirm.destroy()

    def _on_history_clear(self, _btn, store):
        """Clear the screenshot history."""
        self.history.clear()
        store.clear()

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
        app = AliciaScreenshot()
        app.run(sys.argv)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
