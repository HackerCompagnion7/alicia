#!/usr/bin/env python3
"""
Alicia Package Manager - Package management GUI for the Alicia desktop environment.

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
import threading
import time
import json

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, Gio, GLib, Pango
except (ImportError, ValueError) as e:
    print(f"Error importing GTK3: {e}")
    print("Please install PyGObject: pip install PyGObject")
    sys.exit(1)

# Constants
APP_NAME = "Alicia Package Manager"
APP_ID = "com.proyectoTomorrow.alicia.packagemanager"
VERSION = "3.1.0"
HISTORY_FILE = os.path.expanduser("~/.config/alicia/package-history.json")

# Categories: (id, label, icon)
CATEGORIES = [
    ("all", "All Packages", "package-x-generic"),
    ("installed", "Installed", "emblem-default"),
    ("updates", "Updates Available", "software-update-available"),
    ("development", "Development", "applications-development"),
    ("graphics", "Graphics", "applications-graphics"),
    ("internet", "Internet", "applications-internet"),
    ("office", "Office", "applications-office"),
    ("system", "System", "applications-system"),
    ("utilities", "Utilities", "applications-utilities"),
]


class PackageManager:
    """Core package management logic wrapping apt/apk commands."""

    def __init__(self):
        self.packages = []
        self.installed = set()
        self.updates = []
        self._detect_backend()

    def _detect_backend(self):
        """Detect which package manager is available."""
        self.backend = None
        for cmd in ["apt", "apk", "pkg", "dnf", "pacman"]:
            if shutil_which(cmd):
                self.backend = cmd
                break

    def refresh(self):
        """Refresh the package list from the system."""
        self.packages = []
        self.installed = set()
        self.updates = []

        if self.backend in ("apt", "apt-get"):
            self._refresh_apt()
        elif self.backend == "apk":
            self._refresh_apk()
        elif self.backend == "pkg":
            self._refresh_pkg()
        else:
            self._refresh_fallback()

    def _refresh_apt(self):
        """Refresh packages using apt."""
        # Update package lists
        try:
            subprocess.run(["apt", "update"], capture_output=True, timeout=120)
        except Exception:
            pass

        # Get installed packages
        try:
            result = subprocess.run(
                ["dpkg-query", "-W", "-f=${Package}\t${Version}\t${Installed-Size}\t${Status}\t${Maintainer}\n"],
                capture_output=True, text=True, timeout=60
            )
            for line in result.stdout.splitlines():
                parts = line.strip().split('\t')
                if len(parts) >= 4 and "installed" in parts[3]:
                    name = parts[0]
                    version = parts[1] if len(parts) > 1 else "unknown"
                    size = parts[2] if len(parts) > 2 else "0"
                    maintainer = parts[4] if len(parts) > 4 else ""
                    self.packages.append({
                        "name": name,
                        "version": version,
                        "size": self._format_size(size),
                        "status": "installed",
                        "description": maintainer,
                        "category": self._guess_category(name),
                        "dependencies": [],
                    })
                    self.installed.add(name)
        except Exception as e:
            print(f"Error listing apt packages: {e}")

        # Get available updates
        try:
            result = subprocess.run(
                ["apt", "list", "--upgradable"],
                capture_output=True, text=True, timeout=60
            )
            for line in result.stdout.splitlines()[1:]:
                parts = line.strip().split()
                if parts:
                    name = parts[0].split("/")[0]
                    self.updates.append(name)
        except Exception:
            pass

        # Get all available packages (lightweight)
        try:
            result = subprocess.run(
                ["apt-cache", "search", "."],
                capture_output=True, text=True, timeout=120
            )
            existing_names = {p["name"] for p in self.packages}
            for line in result.stdout.splitlines()[:500]:
                if " - " in line:
                    name_ver, desc = line.split(" - ", 1)
                    name = name_ver.split()[0]
                    if name not in existing_names:
                        self.packages.append({
                            "name": name,
                            "version": "available",
                            "size": "--",
                            "status": "available",
                            "description": desc[:200],
                            "category": self._guess_category(name),
                            "dependencies": [],
                        })
                        existing_names.add(name)
        except Exception:
            pass

    def _refresh_apk(self):
        """Refresh packages using apk (Alpine)."""
        try:
            subprocess.run(["apk", "update"], capture_output=True, timeout=60)
        except Exception:
            pass

        try:
            result = subprocess.run(
                ["apk", "info", "-v"],
                capture_output=True, text=True, timeout=60
            )
            for line in result.stdout.splitlines():
                line = line.strip()
                if not line:
                    continue
                # Format: name-version
                parts = line.rsplit("-", 1)
                name = parts[0] if len(parts) > 1 else line
                version = parts[1] if len(parts) > 1 else "unknown"
                self.packages.append({
                    "name": name,
                    "version": version,
                    "size": "--",
                    "status": "installed",
                    "description": "",
                    "category": self._guess_category(name),
                    "dependencies": [],
                })
                self.installed.add(name)
        except Exception as e:
            print(f"Error listing apk packages: {e}")

        # Check for upgrades
        try:
            result = subprocess.run(
                ["apk", "version", "-l", "<"],
                capture_output=True, text=True, timeout=60
            )
            for line in result.stdout.splitlines():
                line = line.strip()
                if line and not line.startswith("Installed"):
                    name = line.split()[0]
                    self.updates.append(name)
        except Exception:
            pass

    def _refresh_pkg(self):
        """Refresh packages using Termux pkg."""
        try:
            subprocess.run(["pkg", "update"], capture_output=True, timeout=120)
        except Exception:
            pass

        try:
            result = subprocess.run(
                ["pkg", "list-installed"],
                capture_output=True, text=True, timeout=60
            )
            for line in result.stdout.splitlines():
                line = line.strip()
                if line and not line.startswith("List"):
                    name = line.split()[0].rstrip(",")
                    self.packages.append({
                        "name": name,
                        "version": "installed",
                        "size": "--",
                        "status": "installed",
                        "description": "",
                        "category": self._guess_category(name),
                        "dependencies": [],
                    })
                    self.installed.add(name)
        except Exception as e:
            print(f"Error listing pkg packages: {e}")

    def _refresh_fallback(self):
        """Fallback when no package manager is detected."""
        self.packages = [{
            "name": "no-pkg-manager",
            "version": "0",
            "size": "--",
            "status": "available",
            "description": "No supported package manager detected (apt/apk/pkg)",
            "category": "system",
            "dependencies": [],
        }]

    def get_package_info(self, name):
        """Get detailed information about a package."""
        info = {"name": name, "description": "", "version": "", "depends": "",
                "size": "", "status": "unknown"}

        if self.backend in ("apt", "apt-get"):
            try:
                result = subprocess.run(
                    ["apt-cache", "show", name],
                    capture_output=True, text=True, timeout=10
                )
                for line in result.stdout.splitlines():
                    if line.startswith("Description: "):
                        info["description"] = line[13:]
                    elif line.startswith("Version: "):
                        info["version"] = line[9:]
                    elif line.startswith("Depends: "):
                        info["depends"] = line[9:]
                    elif line.startswith("Installed-Size: "):
                        info["size"] = self._format_size(line[16:])
                    elif line.startswith("Status: "):
                        if "installed" in line:
                            info["status"] = "installed"
            except Exception:
                pass
        elif self.backend == "apk":
            try:
                result = subprocess.run(
                    ["apk", "info", "-a", name],
                    capture_output=True, text=True, timeout=10
                )
                lines = result.stdout.splitlines()
                if lines:
                    info["description"] = lines[0]
                for line in lines:
                    if line.startswith("depends:"):
                        info["depends"] = line.replace("depends:", "").strip()
                    elif line.startswith("size:"):
                        info["size"] = line.replace("size:", "").strip()
            except Exception:
                pass

        if name in self.installed:
            info["status"] = "installed"
        return info

    def install_package(self, name, progress_cb=None):
        """Install a package."""
        if progress_cb:
            progress_cb(0.0, f"Installing {name}...")
        try:
            if self.backend in ("apt", "apt-get"):
                cmd = ["apt", "install", "-y", name]
            elif self.backend == "apk":
                cmd = ["apk", "add", name]
            elif self.backend == "pkg":
                cmd = ["pkg", "install", "-y", name]
            else:
                return False, "No package manager available"

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if result.returncode == 0:
                self.installed.add(name)
                if progress_cb:
                    progress_cb(1.0, f"Installed {name}")
                return True, result.stdout
            else:
                if progress_cb:
                    progress_cb(1.0, f"Failed to install {name}")
                return False, result.stderr
        except subprocess.TimeoutExpired:
            if progress_cb:
                progress_cb(1.0, f"Installation timed out: {name}")
            return False, "Operation timed out"
        except Exception as e:
            if progress_cb:
                progress_cb(1.0, f"Error: {e}")
            return False, str(e)

    def remove_package(self, name, progress_cb=None):
        """Remove a package."""
        if progress_cb:
            progress_cb(0.0, f"Removing {name}...")
        try:
            if self.backend in ("apt", "apt-get"):
                cmd = ["apt", "remove", "-y", name]
            elif self.backend == "apk":
                cmd = ["apk", "del", name]
            elif self.backend == "pkg":
                cmd = ["pkg", "uninstall", "-y", name]
            else:
                return False, "No package manager available"

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if result.returncode == 0:
                self.installed.discard(name)
                if progress_cb:
                    progress_cb(1.0, f"Removed {name}")
                return True, result.stdout
            else:
                if progress_cb:
                    progress_cb(1.0, f"Failed to remove {name}")
                return False, result.stderr
        except subprocess.TimeoutExpired:
            if progress_cb:
                progress_cb(1.0, f"Removal timed out: {name}")
            return False, "Operation timed out"
        except Exception as e:
            if progress_cb:
                progress_cb(1.0, f"Error: {e}")
            return False, str(e)

    def update_package(self, name, progress_cb=None):
        """Update a single package."""
        if progress_cb:
            progress_cb(0.0, f"Updating {name}...")
        try:
            if self.backend in ("apt", "apt-get"):
                cmd = ["apt", "install", "--only-upgrade", "-y", name]
            elif self.backend == "apk":
                cmd = ["apk", "upgrade", name]
            elif self.backend == "pkg":
                cmd = ["pkg", "upgrade", "-y", name]
            else:
                return False, "No package manager available"

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if progress_cb:
                progress_cb(1.0, "Done")
            return result.returncode == 0, result.stdout or result.stderr
        except Exception as e:
            if progress_cb:
                progress_cb(1.0, f"Error: {e}")
            return False, str(e)

    def update_all(self, progress_cb=None):
        """Update all packages."""
        if progress_cb:
            progress_cb(0.0, "Updating all packages...")
        try:
            if self.backend in ("apt", "apt-get"):
                cmd = ["apt", "upgrade", "-y"]
            elif self.backend == "apk":
                cmd = ["apk", "upgrade"]
            elif self.backend == "pkg":
                cmd = ["pkg", "upgrade", "-y"]
            else:
                return False, "No package manager available"

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
            if progress_cb:
                progress_cb(1.0, "Update complete")
            return result.returncode == 0, result.stdout
        except Exception as e:
            if progress_cb:
                progress_cb(1.0, f"Error: {e}")
            return False, str(e)

    def add_repository(self, repo_line):
        """Add a repository."""
        if self.backend in ("apt", "apt-get"):
            sources_path = "/etc/apt/sources.list"
            try:
                with open(sources_path, 'a') as f:
                    f.write(f"\n{repo_line}\n")
                subprocess.run(["apt", "update"], capture_output=True, timeout=120)
                return True, "Repository added"
            except (IOError, OSError) as e:
                return False, str(e)
        elif self.backend == "apk":
            repos_path = "/etc/apk/repositories"
            try:
                with open(repos_path, 'a') as f:
                    f.write(f"\n{repo_line}\n")
                subprocess.run(["apk", "update"], capture_output=True, timeout=120)
                return True, "Repository added"
            except (IOError, OSError) as e:
                return False, str(e)
        return False, "Not supported for current backend"

    def get_repositories(self):
        """Get list of configured repositories."""
        repos = []
        if self.backend in ("apt", "apt-get"):
            try:
                with open("/etc/apt/sources.list", 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            repos.append(line)
            except (IOError, OSError):
                pass
        elif self.backend == "apk":
            try:
                with open("/etc/apk/repositories", 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            repos.append(line)
            except (IOError, OSError):
                pass
        return repos

    @staticmethod
    def _format_size(kb_str):
        """Format size from KB string."""
        try:
            kb = int(kb_str)
            if kb < 1024:
                return f"{kb} KB"
            return f"{kb / 1024:.1f} MB"
        except (ValueError, TypeError):
            return "--"

    @staticmethod
    def _guess_category(name):
        """Guess package category from name."""
        name_lower = name.lower()
        dev_keywords = ["dev", "lib", "gcc", "python", "perl", "ruby", "node",
                        "build", "make", "cmake", "git", "subversion"]
        gfx_keywords = ["image", "graphic", "gimp", "inkscape", "sdl", "opengl",
                        "vulkan", "mesa", "cairo", "pango", "imagemagick"]
        net_keywords = ["net", "curl", "wget", "ssh", "ftp", "http", "dns",
                        "browser", "firefox", "chromium", "nginx", "apache"]
        office_keywords = ["office", "libreoffice", "calc", "writer", "pdf",
                           "latex", "pandoc", "doc", "spell"]
        sys_keywords = ["kernel", "systemd", "dbus", "udev", "util", "core",
                        "base", "busybox", "sudo", "shadow", "procps", "sysv"]
        util_keywords = ["util", "tree", "htop", "nano", "vim", "mc",
                         "rsync", "tar", "zip", "unzip", "file"]

        for kw in dev_keywords:
            if kw in name_lower:
                return "development"
        for kw in gfx_keywords:
            if kw in name_lower:
                return "graphics"
        for kw in net_keywords:
            if kw in name_lower:
                return "internet"
        for kw in office_keywords:
            if kw in name_lower:
                return "office"
        for kw in sys_keywords:
            if kw in name_lower:
                return "system"
        for kw in util_keywords:
            if kw in name_lower:
                return "utilities"
        return "all"


def shutil_which(cmd):
    """Find the full path of a command, like shutil.which."""
    for path_dir in os.environ.get("PATH", "").split(os.pathsep):
        full_path = os.path.join(path_dir, cmd)
        if os.path.isfile(full_path) and os.access(full_path, os.X_OK):
            return full_path
    return None


class PackageHistory:
    """Tracks package operations history."""

    def __init__(self):
        self.entries = []
        self._load()

    def _load(self):
        """Load history from file."""
        try:
            os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
            if os.path.exists(HISTORY_FILE):
                with open(HISTORY_FILE, 'r') as f:
                    self.entries = json.load(f)
        except (IOError, json.JSONDecodeError):
            self.entries = []

    def _save(self):
        """Save history to file."""
        try:
            os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
            with open(HISTORY_FILE, 'w') as f:
                json.dump(self.entries[-100:], f, indent=2)
        except IOError:
            pass

    def add(self, action, package, status="success"):
        """Add an entry to the history."""
        entry = {
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "action": action,
            "package": package,
            "status": status,
        }
        self.entries.append(entry)
        self._save()


class AliciaPackageManagerApp(Gtk.Application):
    """Main Package Manager application class."""

    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.pkg_mgr = PackageManager()
        self.history = PackageHistory()
        self.current_category = "all"
        self.selected_packages = set()

    def do_activate(self):
        """Handle application activation."""
        win = self.props.active_window
        if not win:
            win = self._build_window()
        win.present()
        # Refresh packages in background
        threading.Thread(target=self._refresh_packages, daemon=True).start()

    def _build_window(self):
        """Build the main application window."""
        win = Gtk.ApplicationWindow(application=self)
        win.set_title(APP_NAME)
        win.set_default_size(950, 650)
        win.set_position(Gtk.WindowPosition.CENTER)

        # Header bar
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title(APP_NAME)
        win.set_titlebar(header)

        # Refresh button
        refresh_btn = Gtk.Button()
        refresh_btn.set_image(Gtk.Image.new_from_icon_name("view-refresh", Gtk.IconSize.BUTTON))
        refresh_btn.set_tooltip_text("Refresh Package List")
        refresh_btn.connect("clicked", self._on_refresh)
        header.pack_start(refresh_btn)

        # Update all button
        update_all_btn = Gtk.Button(label="Update All")
        update_all_btn.connect("clicked", self._on_update_all)
        header.pack_start(update_all_btn)

        # Apply button for batch operations
        self.apply_btn = Gtk.Button(label="Apply Changes")
        self.apply_btn.set_sensitive(False)
        self.apply_btn.get_style_context().add_class("suggested-action")
        self.apply_btn.connect("clicked", self._on_apply_changes)
        header.pack_end(self.apply_btn)

        # Search
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search packages...")
        self.search_entry.connect("search-changed", self._on_search)
        header.pack_end(self.search_entry)

        # Main layout: categories sidebar + content
        main_paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)

        # Sidebar
        sidebar = self._build_sidebar()
        main_paned.pack1(sidebar, False, False)

        # Content area
        content = self._build_content()
        main_paned.pack2(content, True, False)

        main_paned.set_position(200)
        win.add(main_paned)
        win.show_all()
        return win

    def _build_sidebar(self):
        """Build the category sidebar."""
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_size_request(200, -1)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        header = Gtk.Label(label="Categories", halign=Gtk.Align.START)
        header.set_margin_top(8)
        header.set_margin_start(8)
        header.get_style_context().add_class("dim-label")
        box.pack_start(header, False, False, 0)

        self.category_list = Gtk.ListBox()
        self.category_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.category_list.connect("row-selected", self._on_category_selected)

        self.category_badges = {}
        for cat_id, label, icon_name in CATEGORIES:
            row = Gtk.ListBoxRow()
            row.cat_id = cat_id
            h_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            h_box.set_margin_top(6)
            h_box.set_margin_bottom(6)
            h_box.set_margin_start(10)
            h_box.set_margin_end(10)

            icon = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.MENU)
            name_label = Gtk.Label(label=label, halign=Gtk.Align.START)
            badge = Gtk.Label(label="")
            badge.get_style_context().add_class("badge")

            h_box.pack_start(icon, False, False, 0)
            h_box.pack_start(name_label, True, True, 0)
            h_box.pack_start(badge, False, False, 0)
            row.add(h_box)
            self.category_list.add(row)
            self.category_badges[cat_id] = badge

        box.pack_start(self.category_list, True, True, 0)

        # Repositories section
        repo_header = Gtk.Label(label="Repositories", halign=Gtk.Align.START)
        repo_header.set_margin_top(12)
        repo_header.set_margin_start(8)
        repo_header.get_style_context().add_class("dim-label")
        box.pack_start(repo_header, False, False, 0)

        repo_btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        repo_btn_box.set_margin_top(4)
        repo_btn_box.set_margin_start(8)

        add_repo_btn = Gtk.Button(label="Add Repo")
        add_repo_btn.connect("clicked", self._on_add_repo)
        repo_btn_box.pack_start(add_repo_btn, False, False, 0)

        view_repo_btn = Gtk.Button(label="View Repos")
        view_repo_btn.connect("clicked", self._on_view_repos)
        repo_btn_box.pack_start(view_repo_btn, False, False, 0)

        box.pack_start(repo_btn_box, False, False, 0)

        # History button
        hist_btn = Gtk.Button(label="View History")
        hist_btn.set_margin_top(8)
        hist_btn.set_margin_start(8)
        hist_btn.connect("clicked", self._on_view_history)
        box.pack_start(hist_btn, False, False, 0)

        scrolled.add(box)
        return scrolled

    def _build_content(self):
        """Build the main content area with package list and details."""
        vpaned = Gtk.Paned(orientation=Gtk.Orientation.VERTICAL)

        # Package list
        list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        self.pkg_store = Gtk.ListStore(
            bool,   # selected (checkbox)
            str,    # name
            str,    # version
            str,    # size
            str,    # status
            str,    # category
        )
        self.pkg_tree = Gtk.TreeView(model=self.pkg_store)
        self.pkg_tree.set_headers_visible(True)
        self.pkg_tree.set_vexpand(True)

        # Checkbox column
        toggle_renderer = Gtk.CellRendererToggle()
        toggle_renderer.connect("toggled", self._on_package_toggled)
        col_select = Gtk.TreeViewColumn("Select", toggle_renderer, active=0)
        col_select.set_min_width(50)
        self.pkg_tree.append_column(col_select)

        # Other columns
        for i, (title, width) in enumerate([
            ("Package", 200), ("Version", 120), ("Size", 80), ("Status", 100), ("Category", 100)
        ], start=1):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(title, renderer, text=i)
            col.set_min_width(width)
            col.set_resizable(True)
            self.pkg_tree.append_column(col)

        self.pkg_tree.connect("row-activated", self._on_package_activated)

        selection = self.pkg_tree.get_selection()
        selection.connect("changed", self._on_selection_changed)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add(self.pkg_tree)
        list_box.pack_start(scrolled, True, True, 0)

        # Progress bar
        self.progress_bar = Gtk.ProgressBar()
        self.progress_bar.set_show_text(True)
        self.progress_bar.set_fraction(0)
        list_box.pack_start(self.progress_bar, False, False, 0)

        # Status label
        self.status_label = Gtk.Label(label="Ready")
        self.status_label.set_halign(Gtk.Align.START)
        self.status_label.set_margin_start(8)
        self.status_label.get_style_context().add_class("dim-label")
        list_box.pack_start(self.status_label, False, False, 0)

        vpaned.pack1(list_box, True, False)

        # Details panel
        self.details_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.details_box.set_margin_top(8)
        self.details_box.set_margin_bottom(8)
        self.details_box.set_margin_start(12)
        self.details_box.set_margin_end(12)

        self.details_title = Gtk.Label(label="Select a package to view details")
        self.details_title.set_halign(Gtk.Align.START)
        self.details_title.set_margin_top(4)
        self.details_box.pack_start(self.details_title, False, False, 0)

        self.details_grid = Gtk.Grid(row_spacing=4, column_spacing=12)
        self.details_box.pack_start(self.details_grid, False, False, 0)

        # Action buttons
        self.action_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.install_btn = Gtk.Button(label="Install")
        self.install_btn.connect("clicked", self._on_install)
        self.remove_btn = Gtk.Button(label="Remove")
        self.remove_btn.connect("clicked", self._on_remove)
        self.update_btn = Gtk.Button(label="Update")
        self.update_btn.connect("clicked", self._on_update)
        self.info_btn = Gtk.Button(label="Full Info")
        self.info_btn.connect("clicked", self._on_full_info)

        self.action_box.pack_start(self.install_btn, False, False, 0)
        self.action_box.pack_start(self.remove_btn, False, False, 0)
        self.action_box.pack_start(self.update_btn, False, False, 0)
        self.action_box.pack_start(self.info_btn, False, False, 0)
        self.details_box.pack_start(self.action_box, False, False, 0)

        vpaned.pack2(self.details_box, False, False)
        vpaned.set_position(400)

        return vpaned

    def _refresh_packages(self):
        """Refresh package list in a background thread."""
        GLib.idle_add(lambda: self.status_label.set_text("Refreshing package list..."))
        self.pkg_mgr.refresh()
        GLib.idle_add(self._update_package_list)
        GLib.idle_add(lambda: self._update_badges())
        GLib.idle_add(lambda: self.status_label.set_text(
            f"Loaded {len(self.pkg_mgr.packages)} packages ({self.pkg_mgr.backend} backend)"
        ))

    def _update_package_list(self):
        """Update the package list view."""
        self.pkg_store.clear()
        query = self.search_entry.get_text().strip().lower()

        for pkg in self.pkg_mgr.packages:
            # Filter by category
            if self.current_category == "installed" and pkg["status"] != "installed":
                continue
            elif self.current_category == "updates" and pkg["name"] not in self.pkg_mgr.updates:
                continue
            elif self.current_category not in ("all", "installed", "updates"):
                if pkg.get("category", "all") != self.current_category:
                    continue

            # Filter by search
            if query and query not in pkg["name"].lower() and query not in pkg.get("description", "").lower():
                continue

            selected = pkg["name"] in self.selected_packages
            self.pkg_store.append([
                selected,
                pkg["name"],
                pkg.get("version", "--"),
                pkg.get("size", "--"),
                pkg.get("status", "available"),
                pkg.get("category", "all"),
            ])

    def _update_badges(self):
        """Update category badge counts."""
        installed_count = sum(1 for p in self.pkg_mgr.packages if p["status"] == "installed")
        updates_count = len(self.pkg_mgr.updates)
        total_count = len(self.pkg_mgr.packages)

        self.category_badges["all"].set_text(str(total_count))
        self.category_badges["installed"].set_text(str(installed_count))
        self.category_badges["updates"].set_text(str(updates_count))

    def _on_category_selected(self, _listbox, row):
        """Handle category selection."""
        if row is not None:
            self.current_category = row.cat_id
            self._update_package_list()

    def _on_search(self, entry):
        """Handle search input."""
        self._update_package_list()

    def _on_package_toggled(self, _renderer, path):
        """Handle package selection toggle."""
        model = self.pkg_tree.get_model()
        tree_iter = model.get_iter(path)
        name = model.get_value(tree_iter, 1)
        current = model.get_value(tree_iter, 0)

        model.set_value(tree_iter, 0, not current)
        if not current:
            self.selected_packages.add(name)
        else:
            self.selected_packages.discard(name)

        self.apply_btn.set_sensitive(len(self.selected_packages) > 0)

    def _on_package_activated(self, _treeview, path, _column):
        """Handle double-click on a package."""
        model = self.pkg_tree.get_model()
        tree_iter = model.get_iter(path)
        name = model.get_value(tree_iter, 1)
        self._show_package_details(name)

    def _on_selection_changed(self, selection):
        """Handle tree view selection change."""
        model, tree_iter = selection.get_selected()
        if tree_iter is not None:
            name = model.get_value(tree_iter, 1)
            self._show_package_details(name)

    def _show_package_details(self, name):
        """Show package details in the details panel."""
        # Clear existing details
        for child in self.details_grid.get_children():
            self.details_grid.remove(child)

        info = self.pkg_mgr.get_package_info(name)

        self.details_title.set_markup(f"<b>{name}</b>")

        row = 0
        for label_text, value in [
            ("Version:", info.get("version", "--")),
            ("Status:", info.get("status", "--")),
            ("Size:", info.get("size", "--")),
            ("Description:", info.get("description", "No description available")),
            ("Dependencies:", info.get("depends", "None listed")),
        ]:
            label = Gtk.Label(label=label_text, halign=Gtk.Align.END)
            label.get_style_context().add_class("dim-label")
            val = Gtk.Label(label=value, halign=Gtk.Align.START, wrap=True)
            self.details_grid.attach(label, 0, row, 1, 1)
            self.details_grid.attach(val, 1, row, 1, 1)
            row += 1

        # Update button states
        is_installed = name in self.pkg_mgr.installed
        self.install_btn.set_sensitive(not is_installed)
        self.remove_btn.set_sensitive(is_installed)
        self.update_btn.set_sensitive(name in self.pkg_mgr.updates)

        self.details_grid.show_all()

    def _on_install(self, _btn):
        """Install the selected package."""
        name = self._get_selected_package_name()
        if not name:
            return
        threading.Thread(target=self._do_install, args=(name,), daemon=True).start()

    def _do_install(self, name):
        """Perform package installation in a thread."""
        GLib.idle_add(lambda: self._set_progress(0.0, f"Installing {name}..."))
        success, msg = self.pkg_mgr.install_package(
            name, lambda p, m: GLib.idle_add(lambda: self._set_progress(p, m))
        )
        self.history.add("install", name, "success" if success else "failed")
        GLib.idle_add(self._refresh_packages)
        GLib.idle_add(lambda: self._set_progress(1.0, "Installed" if success else f"Failed: {msg[:100]}"))

    def _on_remove(self, _btn):
        """Remove the selected package."""
        name = self._get_selected_package_name()
        if not name:
            return
        confirm = Gtk.MessageDialog(
            parent=self.props.active_window,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f"Remove package '{name}'?"
        )
        if confirm.run() == Gtk.ResponseType.YES:
            threading.Thread(target=self._do_remove, args=(name,), daemon=True).start()
        confirm.destroy()

    def _do_remove(self, name):
        """Perform package removal in a thread."""
        GLib.idle_add(lambda: self._set_progress(0.0, f"Removing {name}..."))
        success, msg = self.pkg_mgr.remove_package(
            name, lambda p, m: GLib.idle_add(lambda: self._set_progress(p, m))
        )
        self.history.add("remove", name, "success" if success else "failed")
        GLib.idle_add(self._refresh_packages)
        GLib.idle_add(lambda: self._set_progress(1.0, "Removed" if success else f"Failed: {msg[:100]}"))

    def _on_update(self, _btn):
        """Update the selected package."""
        name = self._get_selected_package_name()
        if not name:
            return
        threading.Thread(target=self._do_update, args=(name,), daemon=True).start()

    def _do_update(self, name):
        """Perform package update in a thread."""
        GLib.idle_add(lambda: self._set_progress(0.0, f"Updating {name}..."))
        success, msg = self.pkg_mgr.update_package(
            name, lambda p, m: GLib.idle_add(lambda: self._set_progress(p, m))
        )
        self.history.add("update", name, "success" if success else "failed")
        GLib.idle_add(self._refresh_packages)
        GLib.idle_add(lambda: self._set_progress(1.0, "Updated" if success else f"Failed: {msg[:100]}"))

    def _on_full_info(self, _btn):
        """Show full package info in a dialog."""
        name = self._get_selected_package_name()
        if not name:
            return
        info = self.pkg_mgr.get_package_info(name)

        dialog = Gtk.Dialog(title=f"Package Info - {name}",
                            parent=self.props.active_window, modal=True,
                            destroy_with_parent=True)
        dialog.add_button(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        dialog.set_default_size(500, 400)

        textview = Gtk.TextView()
        textview.set_editable(False)
        textview.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        textview.set_margin_top(8)
        textview.set_margin_bottom(8)
        textview.set_margin_start(8)
        textview.set_margin_end(8)

        info_text = f"Package: {name}\n"
        for key, value in info.items():
            info_text += f"{key.capitalize()}: {value}\n"

        textview.get_buffer().set_text(info_text)
        scrolled = Gtk.ScrolledWindow()
        scrolled.add(textview)
        dialog.get_content_area().pack_start(scrolled, True, True, 0)
        dialog.show_all()
        dialog.run()
        dialog.destroy()

    def _on_refresh(self, _btn):
        """Refresh the package list."""
        threading.Thread(target=self._refresh_packages, daemon=True).start()

    def _on_update_all(self, _btn):
        """Update all packages."""
        threading.Thread(target=self._do_update_all, daemon=True).start()

    def _do_update_all(self):
        """Perform full system update in a thread."""
        GLib.idle_add(lambda: self._set_progress(0.0, "Updating all packages..."))
        success, msg = self.pkg_mgr.update_all(
            lambda p, m: GLib.idle_add(lambda: self._set_progress(p, m))
        )
        GLib.idle_add(self._refresh_packages)
        GLib.idle_add(lambda: self._set_progress(1.0,
                      "All updated" if success else f"Update had issues: {msg[:100]}"))

    def _on_apply_changes(self, _btn):
        """Apply all pending batch operations."""
        if not self.selected_packages:
            return

        pkgs = list(self.selected_packages)
        confirm = Gtk.MessageDialog(
            parent=self.props.active_window,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f"Apply changes to {len(pkgs)} package(s)?"
        )
        confirm.set_property("secondary-text", "\n".join(pkgs[:10]))
        if confirm.run() == Gtk.ResponseType.YES:
            threading.Thread(target=self._do_batch, args=(pkgs,), daemon=True).start()
        confirm.destroy()

    def _do_batch(self, packages):
        """Process batch operations."""
        for i, name in enumerate(packages):
            progress = i / len(packages)
            GLib.idle_add(lambda p=progress: self._set_progress(p, f"Processing {name}..."))
            if name in self.pkg_mgr.installed:
                success, _ = self.pkg_mgr.remove_package(name)
            else:
                success, _ = self.pkg_mgr.install_package(name)
            self.history.add("batch", name, "success" if success else "failed")
            self.selected_packages.discard(name)

        GLib.idle_add(self._refresh_packages)
        GLib.idle_add(lambda: self._set_progress(1.0, "Batch operations complete"))
        GLib.idle_add(lambda: self.apply_btn.set_sensitive(False))

    def _on_add_repo(self, _btn):
        """Add a new repository."""
        dialog = Gtk.Dialog(title="Add Repository", parent=self.props.active_window,
                            modal=True, destroy_with_parent=True)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_ADD, Gtk.ResponseType.OK)
        dialog.set_default_size(450, 150)

        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        box.pack_start(Gtk.Label(label="Repository line:"), False, False, 0)
        entry = Gtk.Entry()
        entry.set_placeholder_text("e.g., deb http://deb.debian.org/debian bullseye main")
        box.pack_start(entry, True, True, 0)
        dialog.show_all()

        if dialog.run() == Gtk.ResponseType.OK:
            repo_line = entry.get_text().strip()
            if repo_line:
                success, msg = self.pkg_mgr.add_repository(repo_line)
                if not success:
                    self._show_error(f"Failed to add repository: {msg}")
                else:
                    threading.Thread(target=self._refresh_packages, daemon=True).start()
        dialog.destroy()

    def _on_view_repos(self, _btn):
        """Show configured repositories."""
        repos = self.pkg_mgr.get_repositories()
        dialog = Gtk.Dialog(title="Repositories", parent=self.props.active_window,
                            modal=True, destroy_with_parent=True)
        dialog.add_button(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        dialog.set_default_size(500, 350)

        textview = Gtk.TextView()
        textview.set_editable(False)
        textview.set_margin_top(8)
        textview.set_margin_bottom(8)
        textview.set_margin_start(8)
        textview.set_margin_end(8)
        textview.get_buffer().set_text("\n".join(repos) if repos else "No repositories found.")

        scrolled = Gtk.ScrolledWindow()
        scrolled.add(textview)
        dialog.get_content_area().pack_start(scrolled, True, True, 0)
        dialog.show_all()
        dialog.run()
        dialog.destroy()

    def _on_view_history(self, _btn):
        """Show package operation history."""
        dialog = Gtk.Dialog(title="Package History", parent=self.props.active_window,
                            modal=True, destroy_with_parent=True)
        dialog.add_button(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        dialog.set_default_size(500, 400)

        textview = Gtk.TextView()
        textview.set_editable(False)
        textview.set_margin_top(8)
        textview.set_margin_bottom(8)
        textview.set_margin_start(8)
        textview.set_margin_end(8)

        lines = []
        for entry in reversed(self.history.entries):
            lines.append(f"[{entry['timestamp']}] {entry['action']} {entry['package']} - {entry['status']}")
        textview.get_buffer().set_text("\n".join(lines) if lines else "No history available.")

        scrolled = Gtk.ScrolledWindow()
        scrolled.add(textview)
        dialog.get_content_area().pack_start(scrolled, True, True, 0)
        dialog.show_all()
        dialog.run()
        dialog.destroy()

    def _get_selected_package_name(self):
        """Get the currently selected package name from the tree view."""
        selection = self.pkg_tree.get_selection()
        model, tree_iter = selection.get_selected()
        if tree_iter is not None:
            return model.get_value(tree_iter, 1)
        return None

    def _set_progress(self, fraction, text=""):
        """Update the progress bar."""
        self.progress_bar.set_fraction(min(fraction, 1.0))
        if text:
            self.progress_bar.set_text(text)
        return False  # For GLib.idle_add

    def _show_error(self, msg):
        """Show an error dialog."""
        dialog = Gtk.MessageDialog(
            parent=self.props.active_window,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK, text=str(msg)
        )
        dialog.run()
        dialog.destroy()


def main():
    """Application entry point."""
    try:
        app = AliciaPackageManagerApp()
        app.run(sys.argv)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
