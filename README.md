# Alicia Desktop Environment
## Proyecto Tomorrow

A complete enterprise-grade Linux desktop environment for Android, powered by Termux, proot, and XFCE4.

**Version:** 3.1.0 (Codename: Tomorrow)
**License:** GNU GPL v3.0+
**Author:** Proyecto Tomorrow (20+ years of experience)

---

## What is Alicia?

Alicia transforms your Android device into a full Linux desktop workstation. It runs a complete XFCE4 desktop environment accessible via any VNC viewer app, with no root required.

### Features
- Full XFCE4 desktop with custom Proyecto Tomorrow branding
- Pre-installed applications: file manager, text editor, terminal, system monitor
- Development tools: Python3, Node.js, git, gcc
- Custom Alicia commands: `alicia-health`, `alicia-repair`, `alicia-backup`, etc.
- VNC access from any VNC viewer app or browser (noVNC)
- Watchdog for automatic service recovery
- Backup and restore system
- Package manager GUI
- Settings manager GUI

---

## Requirements

- Android device with **2GB+ RAM**
- **4GB+ free storage** on internal memory
- **Termux** app installed (from F-Droid recommended)
- **VNC Viewer** app (e.g., RealVNC Viewer, TigerVNC, bVNC)
- **Internet connection** for package downloads

---

## Quick Install (From Termux)

```bash
# Step 1: Install Termux from F-Droid
# (Do NOT use Play Store version - it's outdated)

# Step 2: Update Termux packages
pkg update && pkg upgrade -y

# Step 3: Install git
pkg install git -y

# Step 4: Grant storage access
termux-setup-storage

# Step 5: Clone Alicia
git clone https://github.com/proyecto-tomorrow/alicia.git
cd alicia

# Step 6: Run the installer
chmod +x scripts/install.sh
./scripts/install.sh

# Step 7: Start Alicia
./scripts/start.sh

# Step 8: Open your VNC Viewer and connect to:
#   Address:  localhost:5901
#   Password: alicia
```

---

## Unattended Install (CI/automated)

```bash
./scripts/install.sh --unattended
```

---

## Usage

### Starting Alicia
```bash
alicia-start           # From Termux (after installation)
# OR
./scripts/start.sh     # From the alicia directory
```

### Stopping Alicia
```bash
alicia-stop            # From Termux
# OR
./scripts/stop.sh
```

### Checking Status
```bash
alicia-status
# OR
./scripts/status.sh
```

### Opening a Shell Inside proot
```bash
alicia-shell
# OR
proot-distro login alpine
```

### Inside the Desktop (via VNC)
Once connected via VNC, use these commands inside the terminal:

```bash
alicia-health          # Check system health
alicia-repair          # Repair common desktop issues
alicia-backup create   # Create a backup
alicia-backup list     # List backups
alicia-backup restore  # Restore from backup
alicia-install <pkg>   # Install a package
alicia-remove <pkg>    # Remove a package
alicia-update          # Update all packages
alicia-about           # Show Alicia info
alicia-vnc-info        # Show VNC connection details
alicia-system-info     # Show system information
alicia-tool-store      # Tool management utility
```

---

## Architecture

```
+----------------------------------+
|         UI Layer (VNC)           |
|   XFCE4 Desktop Environment      |
+----------------------------------+
              |
+----------------------------------+
|        Action Layer              |
|   Shell scripts & Python GUIs    |
+----------------------------------+
              |
+----------------------------------+
|        System Engine             |
|   proot + Alpine Linux rootfs    |
+----------------------------------+
              |
+----------------------------------+
|      Linux Environment           |
|   X11, VNC, dbus, pulseaudio    |
+----------------------------------+
```

---

## Project Structure

```
alicia/
  setup/              # Installation scripts (01-07)
    01-termux-setup.sh
    02-proot-setup.sh
    03-desktop-setup.sh
    04-vnc-setup.sh
    05-apps-setup.sh
    06-alicia-customize.sh
    07-alicia-commands.sh    # NEW: Internal commands + overlay
  scripts/            # Runtime scripts
    start.sh
    stop.sh
    status.sh
    config.sh
    update.sh
    backup.sh
    watchdog.sh
    install.sh
  lib/                # Shell libraries
    alicia-core.sh
    alicia-log.sh
    alicia-system.sh
    alicia-ui.sh
    alicia-storage.sh
    alicia-network.sh
  applications/       # Python GTK3 GUI apps
    alicia-settings.py
    alicia-filemanager.py
    alicia-package-manager.py
    alicia-terminal.py
    alicia-system-monitor.py
    alicia-text-editor.py
    alicia-welcome.py
    alicia-screenshot.py
  config/             # Configuration templates
    xfce4/
    vnc/
    gtk/
  tests/              # Test suite
```

---

## Troubleshooting

### VNC doesn't start
```bash
alicia-repair          # Auto-repair common issues
alicia-health          # Check what's wrong
```

### Can't connect to VNC
- Make sure Alicia is running: `alicia-status`
- Check VNC info: `alicia-vnc-info`
- Try restarting: `alicia-stop && alicia-start`

### Low memory
- Close unused applications inside the desktop
- Use `alicia-health` to check memory usage
- Lower VNC resolution: `./scripts/start.sh --resolution 720x480`

### Commands not found after install
```bash
source ~/.bashrc       # Reload shell aliases
```

---

## License

Copyright (C) 2005-2025 Proyecto Tomorrow

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
