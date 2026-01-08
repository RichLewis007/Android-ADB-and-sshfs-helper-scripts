# Android ADB and SSHFS Helper Scripts

**Author:** Rich Lewis - [GitHub @RichLewis007](https://github.com/RichLewis007)

A collection of bash scripts for managing files on Android devices via ADB (Android Debug Bridge) and SSHFS. These utilities help you access Android storage and manage SSHFS mounts on macOS.

## Overview

These scripts provide convenient command-line tools for:

- **ADB-based file access**: Pull/push files with elevated permissions (bypasses Android Scoped Storage restrictions)
- **SSHFS mounting**: Mount Android device storage in macOS Finder via SSH
- **Mount management**: Clean up stale SSHFS mount points

## Understanding ADB and SSHFS

ADB (Android Debug Bridge) and SSHFS are two complementary methods for accessing files on your Android device, each with different strengths and use cases.

### ADB (Android Debug Bridge)

**Connection:** USB cable (or WiFi ADB)

**Access Method:** Command-line tools (`adb pull`, `adb push`, `adb shell`)

**Key Features:**

- **Elevated permissions**: Runs with system-level access, bypassing Android Scoped Storage restrictions
- **Full access**: Can access protected directories like `/Android/data/*` and `/Android/obb/*` that apps cannot normally access
- **Direct file operations**: Pull files from device to your Mac, push files to device, or run shell commands
- **Finder integration**: Scripts automatically open pulled directories in Finder after transfer

**Best for:** Backing up app data, accessing protected folders, bulk file transfers, automated scripts

### SSHFS (SSH Filesystem)

**Connection:** WiFi network (device and Mac must be on same network)

**Access Method:** Mounts Android storage as a network drive in macOS Finder

**Key Features:**

- **Finder integration**: Appears as a mounted volume, accessible like any external drive
- **GUI-friendly**: Browse files visually, drag-and-drop, use standard macOS file operations
- **Live access**: Files are accessed directly over the network (no need to copy first)
- **Limited permissions**: Runs with Termux user permissions, subject to Android Scoped Storage restrictions

**Best for:** Browsing files visually, quick file access, working with photos/documents in standard folders

### When to Use Which?

| Task                       | Recommended Method                          |
| -------------------------- | ------------------------------------------- |
| Browsing photos in Finder  | **SSHFS** (convenient GUI access)           |
| Accessing app data folders | **ADB** (only method that can access these) |
| Quick file transfer        | Either (ADB for bulk, SSHFS for browsing)   |
| Automated backups          | **ADB** (better for scripting)              |

**Note:** Both methods require USB Debugging to be enabled. ADB uses the USB connection directly, while SSHFS uses ADB to discover the device's IP address, then connects over WiFi.

## Requirements

### macOS Dependencies

**Using Homebrew:**

```bash
# Install ADB (Android Debug Bridge)
brew install android-platform-tools

# Install SSHFS (for mounting Android device)
brew install macfuse sshfs

# Optional: Enhanced menu experience
brew install fzf        # or
brew install gum
```

**Using MacPorts:**

```bash
# Install ADB (Android Debug Bridge)
sudo port install android-platform-tools

# Install SSHFS (for mounting Android device)
sudo port install macfuse sshfs

# Optional: Enhanced menu experience
sudo port install fzf        # or
sudo port install gum
```

### Android Setup

1. **Enable USB Debugging**:

   - Settings → About Phone → Tap "Build Number" 7 times
   - Settings → Developer Options → Enable "USB Debugging"
   - Connect device via USB and accept the debugging prompt

2. **For SSHFS (optional)**:
   - Install [Termux](https://termux.com/) or another SSH server app
   - Set up SSH server (see `android-sshfs-helper.sh setup` for instructions)

## Scripts

### `android-adb-helper.sh`

General-purpose file access tool for Android devices via ADB. Provides shortcuts for common file operations with elevated permissions.

**Commands:**

```bash
# List files in a directory (default: /sdcard)
./android-adb-helper.sh list [path]

# Pull files/directory from device to local
./android-adb-helper.sh pull <remote_path> <local_path>

# Push files/directory from local to device
./android-adb-helper.sh push <local_path> <remote_path>

# Move all files (excluding hidden) from Android to local
./android-adb-helper.sh move <remote_path> <local_path>

# Open interactive adb shell
./android-adb-helper.sh shell

# Pull common Android directories and open in Finder
./android-adb-helper.sh explorer
```

**Examples:**

```bash
# List photos
./android-adb-helper.sh list /sdcard/DCIM

# Pull photos to Desktop
./android-adb-helper.sh pull /sdcard/DCIM ~/Downloads/DCIM

# Push a file to Downloads
./android-adb-helper.sh push ~/Documents/file.txt /sdcard/Download/

# Move all files from Downloads (copies then deletes from device)
./android-adb-helper.sh move /sdcard/Download ~/Downloads/moved

# Explore common directories
./android-adb-helper.sh explorer
```

**Key Advantages:**

- **Elevated permissions**: ADB bypasses Android Scoped Storage restrictions
- **Access protected paths**: Can access `/Android/data/*` directories that apps can't
- **Automatic Finder integration**: Opens pulled directories in Finder (macOS)

**Common Android Paths:**

- `/sdcard/DCIM` - Photos and videos
- `/sdcard/Download` - Downloads folder
- `/sdcard/Movies`, `/sdcard/Music`, `/sdcard/Pictures`
- `/storage/emulated/0/Android/data/*` - App data (requires ADB)

---

### `android-sshfs-helper.sh`

Mount your Android device's storage in macOS Finder using SSHFS. Useful for browsing files with a GUI.

**Commands:**

```bash
# Get Android device IP address via ADB
./android-sshfs-helper.sh get-ip

# Mount Android device in Finder
./android-sshfs-helper.sh mount [OPTIONS]

# Unmount Android device
./android-sshfs-helper.sh unmount [OPTIONS]

# Show setup instructions for SSH server on Android
./android-sshfs-helper.sh setup
```

**Options for mount command:**

```bash
-u, --ssh-user USER     SSH username (e.g., u0_a123 for Termux) [will prompt if not provided]
-i, --android-ip IP     Android device IP address [auto-detected if not provided]
-p, --ssh-port PORT     SSH port (default: 8022)
-m, --mount-point PATH  Local mount point (default: ~/AndroidDevice)
-s, --use-sudo          Use sudo for mounting (requires password)
-h, --help              Show help message
```

**Options for unmount command:**

```bash
-m, --mount-point PATH  Local mount point (default: ~/AndroidDevice)
-h, --help              Show help message
```

**Quick Start:**

```bash
# 1. Get IP address
./android-sshfs-helper.sh get-ip

# 2. Mount device (will prompt for username if not provided, auto-detects IP)
./android-sshfs-helper.sh mount --ssh-user u0_a123

# Or with all options:
./android-sshfs-helper.sh mount -u u0_a123 -i 192.168.1.100 -p 8022

# 3. Browse in Finder at ~/AndroidDevice

# 4. Unmount when done
./android-sshfs-helper.sh unmount
```

**Limitations:**

- SSHFS runs with Termux user permissions (restricted by Android Scoped Storage)
- Cannot access `/Android/data/*` directories via SSHFS
- Use ADB (`android-adb-helper.sh`) for protected paths

**Troubleshooting:**

- If mount fails, check `macFUSE` permissions in System Settings → Privacy & Security → Full Disk Access
- Ensure SSH server is running on Android (`sshd` in Termux)
- Verify device and Mac are on the same Wi-Fi network

---

### `android-sshfs-mounts-cleanup.sh`

Safely clean up stale or leftover SSHFS mount points on your Mac.

**Usage:**

```bash
# Check and clean common mount points
./android-sshfs-mounts-cleanup.sh

# Clean specific directories
./android-sshfs-mounts-cleanup.sh ~/AndroidDevice /Volumes/my-sshfs
```

**What it does:**

- Checks if directories are mount points
- Attempts to unmount safely (with sudo if needed)
- Removes empty directories
- Reports non-empty directories that need manual cleanup

**Common Use Cases:**

- Clean up after SSHFS connection drops
- Remove leftover mount points from crashed sessions
- Clean up before remounting

---

### `android-check-adb-or-sshfs-access.sh`

Check which directories are accessible on your Android device via ADB or SSHFS. Useful for troubleshooting access issues.

**Usage:**

```bash
# Check access via ADB (elevated permissions)
./android-check-adb-or-sshfs-access.sh adb

# Check access via SSHFS (Termux user permissions)
./android-check-adb-or-sshfs-access.sh sshfs --ssh-user u0_a123 --android-ip 192.168.1.100

# Or with short flags:
./android-check-adb-or-sshfs-access.sh sshfs -u u0_a123 -i 192.168.1.100 -p 8022
```

**Options for sshfs mode:**

```bash
-u, --ssh-user USER     SSH username (Termux user, e.g., u0_a499) [required]
-i, --android-ip IP     Android device IP address [required]
-p, --ssh-port PORT     SSH port (default: 8022)
-h, --help              Show help message
```

**What it checks:**

- Common storage paths (`/storage/emulated/0`, `/sdcard`, etc.)
- Android data directories
- Termux shared storage paths
- Reports existence and accessibility of each path

**Use this to:**

- Understand Android Scoped Storage restrictions
- Determine which method (ADB vs SSHFS) to use for specific paths
- Troubleshoot access issues

---

### `android-adb-find-paths.sh`

Discover which Android storage paths are available and accessible via ADB. Helps you find the correct path for SSHFS mounting.

**Usage:**

```bash
./android-adb-find-paths.sh
```

**Output:**

- Table showing path existence, accessibility, and sample files
- Recommended paths for SSHFS mounting
- Commands to explore more in Termux

**Example Output:**

```
Path                      | Exists | Accessible | Sample Files
--------------------------|--------|------------|--------------
/storage/emulated/0       | YES    | YES        | DCIM Download Android
/sdcard                   | YES    | YES        | DCIM Download Android
```

---

## Common Workflows

### Transferring Photos from Android

**Option 1: Using ADB (recommended for large transfers)**

```bash
./android-adb-helper.sh pull /sdcard/DCIM ~/Downloads/AndroidPhotos
```

**Option 2: Using SSHFS (for browsing)**

```bash
./android-sshfs-helper.sh mount --ssh-user u0_a123
# Browse ~/AndroidDevice/DCIM in Finder
# Copy files manually
./android-sshfs-helper.sh unmount
```

### Accessing Protected Android Data Directories

```bash
# ADB can access /Android/data/* (SSHFS cannot)
./android-adb-helper.sh list /storage/emulated/0/Android/data
./android-adb-helper.sh pull /storage/emulated/0/Android/data/com.example.app ~/Downloads/app-data
```

### Cleaning Up After SSHFS Issues

```bash
# Check and clean common mount points
./android-sshfs-mounts-cleanup.sh

# Or clean specific mount point
./android-sshfs-mounts-cleanup.sh ~/AndroidDevice
```

## Understanding Android Storage Access

### ADB vs SSHFS

| Feature                         | ADB                       | SSHFS                    |
| ------------------------------- | ------------------------- | ------------------------ |
| **Permissions**                 | Elevated (root-like)      | Termux user (restricted) |
| **Scoped Storage**              | Bypasses restrictions     | Subject to restrictions  |
| **Access to `/Android/data/*`** | ✅ Yes                    | ❌ No                    |
| **Access to `/Android/obb/*`**  | ✅ Yes                    | ❌ No                    |
| **GUI Integration**             | Pulls files, opens Finder | Mounts in Finder         |
| **Use Case**                    | Backups, protected data   | General file browsing    |

### Android Scoped Storage (Android 11+)

Android restricts app access to:

- `/storage/emulated/0/Android/data/*` - App-specific data
- `/storage/emulated/0/Android/obb/*` - OBB files

**Solution:** Use ADB for these paths. SSHFS cannot access them.

## Troubleshooting

### ADB Issues

**"No adb device found"**

- Enable USB Debugging in Developer Options
- Connect device via USB
- Accept the debugging prompt on your phone
- Try: `adb devices` to verify connection

**"Permission denied"**

- ADB should have elevated permissions automatically
- Try: `adb shell` to test connection

### SSHFS Issues

**"Operation not permitted"**

- Grant Full Disk Access to Terminal.app:
  - System Settings → Privacy & Security → Full Disk Access
  - Add Terminal.app and `/Library/Filesystems/macfuse.fs/Contents/Resources/mount_macfuse`
  - Restart Terminal

**"Connection refused"**

- Ensure SSH server is running on Android (`sshd` in Termux)
- Verify device and Mac are on the same Wi-Fi network
- Check SSH port (Termux: 8022, SSHelper: 2222)

**"Mount failed for all paths"**

- Try using sudo: `./android-sshfs-helper.sh mount --ssh-user u0_a123 --use-sudo`
- Verify SSH credentials: `ssh -p 8022 user@ip`
- Check Android storage paths with `android-adb-find-paths.sh`

## License

MIT License

Copyright (c) 2024 Rich Lewis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
