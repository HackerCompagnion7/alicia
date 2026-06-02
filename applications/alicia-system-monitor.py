#!/usr/bin/env python3
"""
Alicia System Monitor - Real-time system monitoring for the Alicia desktop environment.

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
import signal
import subprocess
import time
import shutil

try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk, Gdk, Gio, GLib, Pango, cairo
except (ImportError, ValueError) as e:
    print(f"Error importing GTK3: {e}")
    sys.exit(1)

# Constants
APP_NAME = "Alicia System Monitor"
APP_ID = "com.proyectoTomorrow.alicia.systemmonitor"
VERSION = "2.0.0"
REFRESH_INTERVAL = 2000  # milliseconds

# Colors for graphs
CPU_COLOR = (0.30, 0.60, 0.95)
MEM_COLOR = (0.45, 0.82, 0.36)
SWAP_COLOR = (0.93, 0.65, 0.15)
NET_RECV_COLOR = (0.20, 0.70, 0.90)
NET_SEND_COLOR = (0.90, 0.30, 0.30)

# Process state colors
STATE_COLORS = {
    "R": "#4e9a06",   # Running - green
    "S": "#3465a4",   # Sleeping - blue
    "D": "#cc0000",   # Disk sleep - red
    "Z": "#75507b",   # Zombie - purple
    "T": "#c4a000",   # Stopped - yellow
    "t": "#c4a000",   # Tracing stop
    "X": "#cc0000",   # Dead - red
    "default": "#d3d7cf",  # Unknown - gray
}


def read_proc_file(path):
    """Read a /proc file and return its contents, or empty string on error."""
    try:
        with open(path, 'r') as f:
            return f.read()
    except (IOError, OSError):
        return ""


def format_size(bytes_val):
    """Format bytes to human-readable string."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_val < 1024:
            return f"{bytes_val:.1f} {unit}"
        bytes_val /= 1024
    return f"{bytes_val:.1f} PB"


def format_uptime(seconds):
    """Format uptime seconds to a readable string."""
    days = int(seconds // 86400)
    hours = int((seconds % 86400) // 3600)
    mins = int((seconds % 3600) // 60)
    if days > 0:
        return f"{days}d {hours}h {mins}m"
    elif hours > 0:
        return f"{hours}h {mins}m"
    else:
        return f"{mins}m"


class ProcessList:
    """Manages process information from /proc filesystem."""

    def __init__(self):
        self.processes = []

    def refresh(self):
        """Refresh the process list from /proc."""
        self.processes = []
        try:
            pids = [int(p) for p in os.listdir("/proc") if p.isdigit()]
        except OSError:
            return

        for pid in pids:
            proc_info = self._get_process_info(pid)
            if proc_info:
                self.processes.append(proc_info)

    def _get_process_info(self, pid):
        """Get information about a single process."""
        stat_path = f"/proc/{pid}/stat"
        status_path = f"/proc/{pid}/status"

        content = read_proc_file(stat_path)
        if not content:
            return None

        try:
            parts = content.split()
            # Comm field may contain spaces in parentheses
            comm_start = content.index('(')
            comm_end = content.rindex(')')
            comm = content[comm_start + 1:comm_end]

            # Fields after the comm
            after_comm = content[comm_end + 2:].split()
            state = after_comm[0] if len(after_comm) > 0 else "?"
            ppid = int(after_comm[1]) if len(after_comm) > 1 else 0

            # Get more fields from stat
            field_offset = 11  # utime is field index 13 (0-based after pid)
            utime = int(after_comm[field_offset]) if len(after_comm) > field_offset else 0
            stime = int(after_comm[field_offset + 1]) if len(after_comm) > field_offset + 1 else 0

        except (ValueError, IndexError):
            return None

        # Get UID and name from status
        uid = 0
        name = comm
        vm_rss = 0
        status_content = read_proc_file(status_path)
        if status_content:
            for line in status_content.splitlines():
                if line.startswith("Uid:"):
                    try:
                        uid = int(line.split()[1])
                    except (ValueError, IndexError):
                        pass
                elif line.startswith("Name:"):
                    name = line.split(":", 1)[1].strip()
                elif line.startswith("VmRSS:"):
                    try:
                        vm_rss = int(line.split()[1])
                    except (ValueError, IndexError):
                        pass

        # Get username
        try:
            import pwd
            username = pwd.getpwuid(uid).pw_name
        except (KeyError, ImportError):
            username = str(uid)

        # CPU times (in clock ticks)
        total_time = utime + stime

        return {
            "pid": pid,
            "name": name,
            "username": username,
            "state": state,
            "cpu_time": total_time,
            "mem_kb": vm_rss,
            "ppid": ppid,
        }


class ResourceGraph(Gtk.DrawingArea):
    """Custom widget that draws a real-time resource usage graph."""

    def __init__(self, label="", color=(0.3, 0.6, 0.95), max_value=100):
        super().__init__()
        self.label = label
        self.color = color
        self.max_value = max_value
        self.data_points = []
        self.max_points = 60
        self.set_size_request(-1, 120)
        self.connect("draw", self._on_draw)

    def add_data_point(self, value):
        """Add a new data point to the graph."""
        self.data_points.append(value)
        if len(self.data_points) > self.max_points:
            self.data_points.pop(0)
        self.queue_draw()

    def _on_draw(self, _widget, cr):
        """Draw the graph."""
        allocation = self.get_allocation()
        width = allocation.width
        height = allocation.height

        # Background
        cr.set_source_rgb(0.12, 0.12, 0.14)
        cr.rectangle(0, 0, width, height)
        cr.fill()

        # Grid lines
        cr.set_source_rgb(0.25, 0.25, 0.28)
        cr.set_line_width(0.5)
        for i in range(1, 4):
            y = height * i / 4
            cr.move_to(0, y)
            cr.line_to(width, y)
            cr.stroke()

        # Data line
        if len(self.data_points) < 2:
            return True

        r, g, b = self.color

        # Fill area
        cr.set_source_rgba(r, g, b, 0.3)
        cr.move_to(0, height)
        for i, value in enumerate(self.data_points):
            x = (i / (self.max_points - 1)) * width
            y = height - (value / self.max_value) * height
            cr.line_to(x, y)
        cr.line_to(((len(self.data_points) - 1) / (self.max_points - 1)) * width, height)
        cr.close_path()
        cr.fill()

        # Line
        cr.set_source_rgb(r, g, b)
        cr.set_line_width(2)
        for i, value in enumerate(self.data_points):
            x = (i / (self.max_points - 1)) * width
            y = height - (value / self.max_value) * height
            if i == 0:
                cr.move_to(x, y)
            else:
                cr.line_to(x, y)
        cr.stroke()

        # Label
        cr.set_source_rgb(0.8, 0.8, 0.8)
        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
        cr.set_font_size(11)
        cr.move_to(8, 14)
        cr.show_text(f"{self.label}: {self.data_points[-1]:.1f}%"
                     if self.max_value == 100 else
                     f"{self.label}: {format_size(self.data_points[-1])}")

        # Scale labels
        cr.set_font_size(9)
        cr.set_source_rgb(0.5, 0.5, 0.5)
        if self.max_value == 100:
            for i, pct in enumerate([100, 75, 50, 25, 0]):
                y = height * i / 4 + 10
                cr.move_to(width - 35, y)
                cr.show_text(f"{pct}%")

        return True


class ProcessesTab(Gtk.Box):
    """Processes listing tab."""

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Search bar
        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        search_box.set_margin_top(6)
        search_box.set_margin_bottom(6)
        search_box.set_margin_start(8)
        search_box.set_margin_end(8)

        search_label = Gtk.Label(label="Search:")
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Filter processes...")
        self.search_entry.connect("search-changed", self._on_search)

        search_box.pack_start(search_label, False, False, 0)
        search_box.pack_start(self.search_entry, True, True, 0)

        end_process_btn = Gtk.Button(label="End Process")
        end_process_btn.connect("clicked", self._on_end_process)
        search_box.pack_start(end_process_btn, False, False, 0)

        kill_process_btn = Gtk.Button(label="Kill Process")
        kill_process_btn.get_style_context().add_class("destructive-action")
        kill_process_btn.connect("clicked", self._on_kill_process)
        search_box.pack_start(kill_process_btn, False, False, 0)

        self.pack_start(search_box, False, False, 0)

        # Process tree view
        self.proc_store = Gtk.ListStore(
            int,    # PID
            str,    # Name
            str,    # User
            float,  # CPU%
            float,  # MEM%
            str,    # State
            str,    # State color
        )

        # Filterable model
        self.proc_filter = self.proc_store.filter_new()
        self.proc_filter.set_visible_func(self._filter_func)
        self.proc_sort = Gtk.TreeModelSort(model=self.proc_filter)

        self.proc_tree = Gtk.TreeView(model=self.proc_sort)
        self.proc_tree.set_headers_visible(True)
        self.proc_tree.set_vexpand(True)

        columns = [
            ("PID", 0, 70, int),
            ("Process Name", 1, 250, str),
            ("User", 2, 100, str),
            ("CPU %", 3, 80, float),
            ("MEM %", 4, 80, float),
            ("State", 5, 80, str),
        ]

        for title, col_idx, width, _dtype in columns:
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(title, renderer, text=col_idx)

            if col_idx == 5:
                # Color-code state column
                renderer = Gtk.CellRendererText()
                col = Gtk.TreeViewColumn(title, renderer, text=col_idx,
                                         foreground=6)

            col.set_min_width(width)
            col.set_resizable(True)
            col.set_sort_column_id(col_idx)
            self.proc_tree.append_column(col)

        selection = self.proc_tree.get_selection()
        selection.set_mode(Gtk.SelectionMode.SINGLE)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add(self.proc_tree)
        self.pack_start(scrolled, True, True, 0)

        # Status bar
        self.status_label = Gtk.Label(label="Loading processes...")
        self.status_label.set_halign(Gtk.Align.START)
        self.status_label.set_margin_start(8)
        self.status_label.get_style_context().add_class("dim-label")
        self.pack_start(self.status_label, False, False, 0)

        # Data
        self.process_list = ProcessList()
        self.prev_cpu_times = {}
        self._total_cpu_prev = 0
        self._idle_cpu_prev = 0
        self.search_query = ""

    def refresh(self):
        """Refresh the process list."""
        # Get CPU totals for percentage calculation
        cpu_stats = self._get_cpu_stats()
        total_diff = cpu_stats["total"] - self._total_cpu_prev
        idle_diff = cpu_stats["idle"] - self._idle_cpu_prev

        self.process_list.refresh()
        self.proc_store.clear()

        total_mem = self._get_total_memory()

        for proc in self.process_list.processes:
            # Calculate CPU percentage
            pid = proc["pid"]
            cpu_time = proc["cpu_time"]
            prev_time = self.prev_cpu_times.get(pid, 0)
            cpu_pct = 0.0
            if total_diff > 0:
                cpu_pct = ((cpu_time - prev_time) / total_diff) * 100.0
            self.prev_cpu_times[pid] = cpu_time

            # Calculate memory percentage
            mem_pct = 0.0
            if total_mem > 0 and proc["mem_kb"] > 0:
                mem_pct = (proc["mem_kb"] * 1024 / total_mem) * 100.0

            state = proc["state"]
            state_color = STATE_COLORS.get(state, STATE_COLORS["default"])

            self.proc_store.append([
                proc["pid"],
                proc["name"],
                proc["username"],
                round(cpu_pct, 1),
                round(mem_pct, 1),
                state,
                state_color,
            ])

        self._total_cpu_prev = cpu_stats["total"]
        self._idle_cpu_prev = cpu_stats["idle"]

        count = len(self.process_list.processes)
        self.status_label.set_text(f"{count} processes")

    def _get_cpu_stats(self):
        """Get total and idle CPU times from /proc/stat."""
        content = read_proc_file("/proc/stat")
        if not content:
            return {"total": 0, "idle": 0}

        line = content.splitlines()[0]
        parts = line.split()
        values = [int(v) for v in parts[1:]]
        idle = values[3] if len(values) > 3 else 0
        total = sum(values)
        return {"total": total, "idle": idle}

    def _get_total_memory(self):
        """Get total system memory in bytes."""
        content = read_proc_file("/proc/meminfo")
        if not content:
            return 0
        for line in content.splitlines():
            if line.startswith("MemTotal:"):
                try:
                    return int(line.split()[1]) * 1024
                except (ValueError, IndexError):
                    return 0
        return 0

    def _on_search(self, entry):
        """Handle search filter."""
        self.search_query = entry.get_text().strip().lower()
        self.proc_filter.refilter()

    def _filter_func(self, model, tree_iter, _data):
        """Filter function for the process list."""
        if not self.search_query:
            return True
        name = model.get_value(tree_iter, 1).lower()
        user = model.get_value(tree_iter, 2).lower()
        pid = str(model.get_value(tree_iter, 0))
        return (self.search_query in name or
                self.search_query in user or
                self.search_query in pid)

    def _get_selected_pid(self):
        """Get the PID of the selected process."""
        selection = self.proc_tree.get_selection()
        model, tree_iter = selection.get_selected()
        if tree_iter is not None:
            return model.get_value(tree_iter, 0)
        return None

    def _on_end_process(self, _btn):
        """Send SIGTERM to the selected process."""
        pid = self._get_selected_pid()
        if pid is None:
            return
        try:
            os.kill(pid, signal.SIGTERM)
        except (OSError, ProcessLookupError) as e:
            self._show_error(f"Cannot end process: {e}")

    def _on_kill_process(self, _btn):
        """Send SIGKILL to the selected process."""
        pid = self._get_selected_pid()
        if pid is None:
            return
        confirm = Gtk.MessageDialog(
            parent=self.get_toplevel(),
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f"Force kill process {pid}?"
        )
        if confirm.run() == Gtk.ResponseType.YES:
            try:
                os.kill(pid, signal.SIGKILL)
            except (OSError, ProcessLookupError) as e:
                self._show_error(f"Cannot kill process: {e}")
        confirm.destroy()

    def _show_error(self, msg):
        """Show an error dialog."""
        dialog = Gtk.MessageDialog(
            parent=self.get_toplevel(),
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK, text=str(msg)
        )
        dialog.run()
        dialog.destroy()


class ResourcesTab(Gtk.Box):
    """Resources tab with real-time graphs."""

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.set_margin_top(8)
        self.set_margin_bottom(8)
        self.set_margin_start(8)
        self.set_margin_end(8)

        # CPU graph
        self.cpu_graph = ResourceGraph("CPU Usage", CPU_COLOR, 100)
        self.pack_start(self._wrap_graph("CPU", self.cpu_graph), False, False, 0)

        # Memory graph
        self.mem_graph = ResourceGraph("Memory Usage", MEM_COLOR, 100)
        self.pack_start(self._wrap_graph("Memory", self.mem_graph), False, False, 0)

        # Network graph
        self.net_graph = ResourceGraph("Network I/O", NET_RECV_COLOR, 1024 * 1024)
        self.pack_start(self._wrap_graph("Network", self.net_graph), False, False, 0)

        # Info labels
        info_frame = Gtk.Frame(label="Resource Summary")
        info_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        info_box.set_margin_top(6)
        info_box.set_margin_bottom(6)
        info_box.set_margin_start(10)
        info_box.set_margin_end(10)

        self.cpu_label = Gtk.Label(label="CPU: --", halign=Gtk.Align.START)
        self.mem_label = Gtk.Label(label="Memory: --", halign=Gtk.Align.START)
        self.swap_label = Gtk.Label(label="Swap: --", halign=Gtk.Align.START)
        self.net_label = Gtk.Label(label="Network: --", halign=Gtk.Align.START)

        info_box.pack_start(self.cpu_label, False, False, 0)
        info_box.pack_start(self.mem_label, False, False, 0)
        info_box.pack_start(self.swap_label, False, False, 0)
        info_box.pack_start(self.net_label, False, False, 0)

        info_frame.add(info_box)
        self.pack_start(info_frame, False, False, 0)

        # Previous values for rate calculation
        self._prev_cpu_total = 0
        self._prev_cpu_idle = 0
        self._prev_net_recv = 0
        self._prev_net_send = 0

    def _wrap_graph(self, title, graph):
        """Wrap a graph widget in a frame."""
        frame = Gtk.Frame(label=title)
        frame.add(graph)
        return frame

    def refresh(self):
        """Refresh resource data."""
        cpu_pct = self._update_cpu()
        mem_info = self._update_memory()
        net_speed = self._update_network()

        self.cpu_graph.add_data_point(cpu_pct)
        self.mem_graph.add_data_point(mem_info["mem_pct"])
        self.net_graph.add_data_point(net_speed)

    def _update_cpu(self):
        """Update CPU usage data."""
        content = read_proc_file("/proc/stat")
        if not content:
            return 0

        line = content.splitlines()[0]
        parts = line.split()
        values = [int(v) for v in parts[1:]]
        idle = values[3] if len(values) > 3 else 0
        total = sum(values)

        diff_total = total - self._prev_cpu_total
        diff_idle = idle - self._prev_cpu_idle
        cpu_pct = 0.0
        if diff_total > 0:
            cpu_pct = ((diff_total - diff_idle) / diff_total) * 100.0

        self._prev_cpu_total = total
        self._prev_cpu_idle = idle

        self.cpu_label.set_text(
            f"CPU Usage: {cpu_pct:.1f}%  |  Cores: {os.cpu_count() or 'N/A'}"
        )
        return cpu_pct

    def _update_memory(self):
        """Update memory usage data."""
        content = read_proc_file("/proc/meminfo")
        mem_total = mem_free = mem_available = swap_total = swap_free = 0

        if content:
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
                elif key == "SwapTotal":
                    swap_total = value
                elif key == "SwapFree":
                    swap_free = value

        mem_used = mem_total - mem_available
        mem_pct = (mem_used / mem_total * 100) if mem_total > 0 else 0
        swap_used = swap_total - swap_free
        swap_pct = (swap_used / swap_total * 100) if swap_total > 0 else 0

        self.mem_label.set_text(
            f"Memory: {format_size(mem_used * 1024)} / {format_size(mem_total * 1024)} "
            f"({mem_pct:.1f}%)"
        )
        self.swap_label.set_text(
            f"Swap: {format_size(swap_used * 1024)} / {format_size(swap_total * 1024)} "
            f"({swap_pct:.1f}%)"
        )

        return {"mem_pct": mem_pct, "swap_pct": swap_pct}

    def _update_network(self):
        """Update network data."""
        recv_bytes = send_bytes = 0
        net_dir = "/proc/net/dev"
        content = read_proc_file(net_dir)

        if content:
            for line in content.splitlines()[2:]:
                parts = line.split()
                if len(parts) < 10:
                    continue
                iface = parts[0].rstrip(':')
                if iface == "lo":
                    continue
                try:
                    recv_bytes += int(parts[1])
                    send_bytes += int(parts[9])
                except (ValueError, IndexError):
                    pass

        # Calculate rate
        recv_diff = recv_bytes - self._prev_net_recv
        send_diff = send_bytes - self._prev_net_send
        rate = recv_diff + send_diff  # bytes per interval

        self._prev_net_recv = recv_bytes
        self._prev_net_send = send_bytes

        self.net_label.set_text(
            f"Network — ↓ {format_size(recv_diff)}/s  ↑ {format_size(send_diff)}/s  "
            f"(Total: ↓ {format_size(recv_bytes)} ↑ {format_size(send_bytes)})"
        )

        return rate


class FileSystemsTab(Gtk.Box):
    """File systems / disk usage tab."""

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # Disk list
        scrolled = Gtk.ScrolledWindow()
        self.disk_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.disk_box.set_margin_top(8)
        self.disk_box.set_margin_bottom(8)
        self.disk_box.set_margin_start(8)
        self.disk_box.set_margin_end(8)
        scrolled.add(self.disk_box)
        self.pack_start(scrolled, True, True, 0)

    def refresh(self):
        """Refresh disk usage information."""
        for child in self.disk_box.get_children():
            self.disk_box.remove(child)

        mounts = self._get_mounts()
        for mount in mounts:
            frame = self._create_mount_widget(mount)
            self.disk_box.pack_start(frame, False, False, 0)

        self.disk_box.show_all()

    def _get_mounts(self):
        """Get list of mount points with usage data."""
        mounts = []
        seen_devices = set()
        content = read_proc_file("/proc/mounts")

        if content:
            for line in content.splitlines():
                parts = line.split()
                if len(parts) < 4:
                    continue
                device = parts[0]
                mount_point = parts[1]
                fs_type = parts[2]

                # Skip pseudo filesystems
                if fs_type in ("proc", "sysfs", "devpts", "tmpfs", "cgroup",
                               "cgroup2", "debugfs", "tracefs", "securityfs",
                               "devtmpfs", "pstore", "bpf", "overlay"):
                    continue
                if device in seen_devices or not os.path.ismount(mount_point):
                    continue
                if not os.path.isdir(mount_point):
                    continue

                seen_devices.add(device)

                try:
                    usage = shutil.disk_usage(mount_point)
                    mounts.append({
                        "device": device,
                        "mount": mount_point,
                        "fs_type": fs_type,
                        "total": usage.total,
                        "used": usage.used,
                        "free": usage.free,
                    })
                except (OSError, PermissionError):
                    continue

        return mounts

    def _create_mount_widget(self, mount):
        """Create a widget showing mount point usage."""
        frame = Gtk.Frame()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_top(6)
        box.set_margin_bottom(6)
        box.set_margin_start(10)
        box.set_margin_end(10)

        pct = (mount["used"] / mount["total"] * 100) if mount["total"] > 0 else 0

        # Title
        title = Gtk.Label(halign=Gtk.Align.START)
        title.set_markup(
            f"<b>{mount['mount']}</b>  ({mount['device']}, {mount['fs_type']})"
        )
        box.pack_start(title, False, False, 0)

        # Usage bar
        progress = Gtk.ProgressBar()
        progress.set_fraction(pct / 100)
        if pct > 90:
            progress.get_style_context().add_class("destructive-action")
        box.pack_start(progress, False, False, 0)

        # Details
        details = Gtk.Label(halign=Gtk.Align.START)
        details.set_text(
            f"Total: {format_size(mount['total'])}  |  "
            f"Used: {format_size(mount['used'])}  |  "
            f"Free: {format_size(mount['free'])}  |  "
            f"Usage: {pct:.1f}%"
        )
        box.pack_start(details, False, False, 0)

        frame.add(box)
        return frame


class SummaryTab(Gtk.Box):
    """System summary / information tab."""

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.set_margin_top(18)
        self.set_margin_bottom(18)
        self.set_margin_start(18)
        self.set_margin_end(18)
        self._build_ui()

    def _build_ui(self):
        """Build the summary UI."""
        lbl = Gtk.Label(label="System Information")
        lbl.set_halign(Gtk.Align.START)
        lbl.get_style_context().add_class("title-2")
        self.pack_start(lbl, False, False, 0)

        grid = Gtk.Grid(row_spacing=8, column_spacing=16)
        grid.set_margin_top(12)
        row = 0

        info = self._gather_info()
        for key, value in info:
            key_label = Gtk.Label(label=key, halign=Gtk.Align.END)
            key_label.get_style_context().add_class("dim-label")
            val_label = Gtk.Label(label=value, halign=Gtk.Align.START, selectable=True)
            grid.attach(key_label, 0, row, 1, 1)
            grid.attach(val_label, 1, row, 1, 1)
            row += 1

        self.pack_start(grid, False, False, 0)

    def _gather_info(self):
        """Gather system information."""
        info = []

        # Hostname
        try:
            hostname = os.uname().nodename
        except AttributeError:
            hostname = "Unknown"
        info.append(("Hostname:", hostname))

        # OS
        try:
            os_name = os.uname().sysname
            os_release = os.uname().release
            os_version = os.uname().version
            info.append(("Operating System:", f"{os_name} {os_release}"))
            info.append(("Kernel Version:", os_version))
        except AttributeError:
            info.append(("Operating System:", "Unknown"))

        # Architecture
        try:
            info.append(("Architecture:", os.uname().machine))
        except AttributeError:
            pass

        # Uptime
        try:
            content = read_proc_file("/proc/uptime")
            uptime_secs = float(content.split()[0])
            info.append(("Uptime:", format_uptime(uptime_secs)))
        except (ValueError, IndexError):
            info.append(("Uptime:", "Unknown"))

        # CPU model
        content = read_proc_file("/proc/cpuinfo")
        cpu_model = "Unknown"
        cpu_cores = os.cpu_count() or "N/A"
        if content:
            for line in content.splitlines():
                if line.startswith("model name") or line.startswith("Model"):
                    cpu_model = line.split(":", 1)[1].strip()
                    break
        info.append(("CPU Model:", cpu_model))
        info.append(("CPU Cores:", str(cpu_cores)))

        # Memory
        mem_content = read_proc_file("/proc/meminfo")
        if mem_content:
            mem_total = 0
            for line in mem_content.splitlines():
                if line.startswith("MemTotal:"):
                    try:
                        mem_total = int(line.split()[1]) * 1024
                    except (ValueError, IndexError):
                        pass
            info.append(("Total RAM:", format_size(mem_total)))

        # Alicia version
        info.append(("Alicia Desktop:", VERSION))
        info.append(("GTK Version:", f"{Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()}"))

        return info

    def refresh(self):
        """Refresh is a no-op for summary (static info)."""
        pass


class AliciaSystemMonitor(Gtk.Application):
    """Main System Monitor application class."""

    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.refresh_timeout_id = None

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
        win.set_default_size(800, 600)
        win.set_position(Gtk.WindowPosition.CENTER)

        # Header bar
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title(APP_NAME)
        win.set_titlebar(header)

        # Kill process button
        kill_btn = Gtk.Button(label="End Process")
        kill_btn.connect("clicked", self._on_kill_process)
        header.pack_start(kill_btn)

        # Notebook tabs
        self.notebook = Gtk.Notebook()
        self.notebook.set_tab_pos(Gtk.PositionType.TOP)

        self.processes_tab = ProcessesTab()
        self.resources_tab = ResourcesTab()
        self.filesystems_tab = FileSystemsTab()
        self.summary_tab = SummaryTab()

        tabs = [
            (self.processes_tab, "Processes"),
            (self.resources_tab, "Resources"),
            (self.filesystems_tab, "File Systems"),
            (self.summary_tab, "Summary"),
        ]

        for tab_widget, tab_label in tabs:
            self.notebook.append_page(tab_widget, Gtk.Label(label=tab_label))

        win.add(self.notebook)

        # Start refresh timer
        self.refresh_timeout_id = GLib.timeout_add(REFRESH_INTERVAL, self._refresh_data)

        # Initial refresh
        self._refresh_data()

        # Handle window close
        win.connect("delete-event", self._on_window_close)

        win.show_all()
        return win

    def _refresh_data(self):
        """Refresh all tab data."""
        current_page = self.notebook.get_current_page()

        try:
            if current_page == 0:
                self.processes_tab.refresh()
            elif current_page == 1:
                self.resources_tab.refresh()
            elif current_page == 2:
                self.filesystems_tab.refresh()
            # Summary doesn't need refresh
        except Exception as e:
            print(f"Error refreshing data: {e}")

        return True  # Keep the timer running

    def _on_kill_process(self, _btn):
        """Kill process from header button."""
        if self.notebook.get_current_page() == 0:
            self.processes_tab._on_end_process(None)

    def _on_window_close(self, window, event):
        """Handle window close event."""
        if self.refresh_timeout_id:
            GLib.source_remove(self.refresh_timeout_id)
            self.refresh_timeout_id = None
        return False


def main():
    """Application entry point."""
    try:
        app = AliciaSystemMonitor()
        app.run(sys.argv)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
