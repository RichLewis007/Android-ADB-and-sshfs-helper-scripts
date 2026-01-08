#!/usr/bin/env bash
set -euo pipefail

# android-sshfs-helper.sh
#
# Author: Rich Lewis - GitHub @RichLewis007
#
# Helper script to mount Android device in macOS Finder using SSHFS.
# This requires an SSH server app installed on your Android device.
# I use Termux on my Android device for SSH server.
#
# Usage:
#   ./android-sshfs-helper.sh get-ip                    # Get Android IP address
#   ./android-sshfs-helper.sh mount [OPTIONS]          # Mount Android device in Finder
#   ./android-sshfs-helper.sh unmount [OPTIONS]        # Unmount Android device
#   ./android-sshfs-helper.sh setup                    # Show setup instructions
#
# Options for mount command:
#   -u, --ssh-user USER     SSH username (e.g., u0_a123 for Termux)
#   -i, --android-ip IP     Android device IP address (auto-detected if not provided)
#   -p, --ssh-port PORT     SSH port (default: 8022)
#   -m, --mount-point PATH  Local mount point (default: ~/AndroidDevice)
#   -s, --use-sudo          Use sudo for mounting (requires password)
#   -h, --help              Show help message
# 
# Accessing Android files with ADB vs. sshfs Notes:
# ------------------------------------------------------------------------------
# Android blocks apps (including Termux) from accessing:
# /storage/emulated/0/Android/data/*
# /storage/emulated/0/Android/obb/*

# This restriction applies whether you access via:
# - Direct Termux terminal
# - SSHFS mount (same permissions)

# For Android/data files:
# Use ADB — the android-adb-helper.sh script can access these paths:
# - ADB runs with elevated permissions
# - Bypasses Scoped Storage restrictions
# - Can access Android/data directories

# For general file access via SSHFS:
# You can access:
# /storage/emulated/0/DCIM (photos)
# /storage/emulated/0/Download
# /storage/emulated/0/Documents
# /storage/emulated/0/Pictures
# /storage/emulated/0/Movies
# /storage/emulated/0/Music
# Most other directories (except Android/data and Android/obb)

# Created check-android-access.sh to see what's accessible:
# ./check-android-access.sh adb    # Check what ADB can access
# ./check-android-access.sh sshfs  # Check what SSHFS can access

# Use ADB for Android/data files and SSHFS for general storage.

ADB_BIN="adb"
MOUNT_POINT="${HOME}/AndroidDevice"
SSH_USER=""
ANDROID_IP=""
SSH_PORT="8022"
USE_SUDO="false"

usage() {
  cat <<EOF
Usage:
  android-sshfs-helper.sh <command> [OPTIONS]

Commands:
  get-ip           Get Android device IP address via ADB
  mount            Mount Android device using SSHFS
  unmount          Unmount Android device
  setup            Show setup instructions for SSH server on Android

Options for mount command:
  -u, --ssh-user USER     SSH username (e.g., u0_a123 for Termux) [will prompt if not provided]
  -i, --android-ip IP     Android device IP address [auto-detected if not provided]
  -p, --ssh-port PORT     SSH port (default: 8022)
  -m, --mount-point PATH  Local mount point (default: ~/AndroidDevice)
  -s, --use-sudo          Use sudo for mounting (requires password)
  -h, --help              Show this help message

Options for unmount command:
  -m, --mount-point PATH  Local mount point (default: ~/AndroidDevice)
  -h, --help              Show this help message

Examples:
  ./android-sshfs-helper.sh get-ip
  ./android-sshfs-helper.sh mount --ssh-user u0_a123
  ./android-sshfs-helper.sh mount -u u0_a123 -i 192.168.1.100 -p 8022
  ./android-sshfs-helper.sh mount -u u0_a123 --use-sudo
  ./android-sshfs-helper.sh unmount
  ./android-sshfs-helper.sh unmount --mount-point /custom/path
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $cmd" >&2
    exit 1
  fi
}

check_device() {
  device_count="$("$ADB_BIN" devices | awk 'NR>1 && $2=="device"{count++} END{print count+0}')"
  if [[ "$device_count" -lt 1 ]]; then
    echo "ERROR: No adb device found. Plug in phone, enable USB debugging, and accept the prompt." >&2
    exit 1
  fi
}

get_android_ip() {
  echo "Getting Android device IP address via ADB..."
  echo
  
  # Try multiple methods (order: most compatible first)
  local ip1=""
  
  # Method 1: ifconfig (works on most Android devices, including older ones)
  ip1="$("$ADB_BIN" shell "ifconfig wlan0 2>/dev/null | grep 'inet addr' | awk '{print \$2}' | cut -d: -f2" 2>/dev/null | tr -d '\r' || true)"
  
  # Method 2: ip command (newer Android)
  if [[ -z "$ip1" ]]; then
    ip1="$("$ADB_BIN" shell "ip -4 addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" 2>/dev/null | tr -d '\r' || true)"
  fi
  
  # Method 3: getprop (Android system property)
  if [[ -z "$ip1" ]]; then
    ip1="$("$ADB_BIN" shell "getprop dhcp.wlan0.ipaddress" 2>/dev/null | tr -d '\r' || true)"
  fi
  
  # Method 4: netcfg (older Android)
  if [[ -z "$ip1" ]]; then
    ip1="$("$ADB_BIN" shell "netcfg 2>/dev/null | grep wlan0 | awk '{print \$3}' | cut -d'/' -f1" 2>/dev/null | tr -d '\r' || true)"
  fi
  
  # Method 5: Try any interface with "inet" (fallback)
  if [[ -z "$ip1" ]]; then
    ip1="$("$ADB_BIN" shell "ifconfig 2>/dev/null | grep 'inet addr' | head -1 | awk '{print \$2}' | cut -d: -f2" 2>/dev/null | tr -d '\r' || true)"
  fi
  
  # Validate IP format (basic check)
  if [[ -n "$ip1" ]] && [[ "$ip1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Android IP address: $ip1"
    echo "$ip1"
    return 0
  else
    echo "ERROR: Could not detect Android IP address automatically." >&2
    echo >&2
    echo "Please get the IP address manually:" >&2
    echo "  1. On Android: Settings > Wi-Fi > (tap connected network) > IP address" >&2
    echo "  2. Or provide it with: --android-ip 192.168.1.xxx" >&2
    echo >&2
    echo "Debug: Tried multiple methods but couldn't find a valid IP." >&2
    return 1
  fi
}

cmd_get_ip() {
  check_device
  get_android_ip
}

cmd_setup() {
  cat <<'EOF'
================================================================================
SSH Server Setup for Android
================================================================================

STEP 1: Install an SSH Server App on Android

Choose one of these options:

Option A: Termux (recommended, free)
  - Install "Termux" from Google Play Store or F-Droid
  - Open Termux and run:
      pkg update && pkg upgrade
      pkg install openssh
      sshd
  - Your username will be shown by running 'whoami' in Termux
  - Default port: 8022

Option B: SSHelper (simple, free)
  - Install "SSHelper" from Google Play Store
  - Open SSHelper and tap "Start"
  - Username: sshelper
  - Password: shown in the app
  - Default port: 2222

Option C: JuiceSSH (requires root, free)
  - Install "JuiceSSH" and enable SSH server
  - Check app for username (often "root" if rooted)

STEP 2: Find Your SSH Username

For Termux, run in Termux:
  whoami
  (Output will be something like: u0_a123)

For SSHelper:
  Username: sshelper (check app for password)

STEP 3: Get Android IP Address

Run this script:
  ./android-sshfs-helper.sh get-ip

Or manually:
  On Android: Settings > Wi-Fi > (tap network) > IP address

STEP 4: Mount the Device

  ./android-sshfs-helper.sh mount --ssh-user your_username

Or with explicit IP and port:
  ./android-sshfs-helper.sh mount -u your_username -i 192.168.1.xxx -p 8022

Or using sshfs directly:
  sshfs -p 8022 your_username@192.168.1.xxx:/sdcard ~/AndroidDevice

Common paths to mount:
  /sdcard              - Main storage (most common)
  /storage/emulated/0  - Same as /sdcard (alternative path)
  /storage/self/primary - Another alternative

================================================================================
EOF
}

cmd_mount() {
  require_cmd sshfs
  
  check_device
  
  # Get IP address
  if [[ -z "$ANDROID_IP" ]]; then
    ANDROID_IP=$(get_android_ip)
    if [[ -z "$ANDROID_IP" ]]; then
      exit 1
    fi
  else
    echo "Using provided IP: $ANDROID_IP"
  fi
  
  # Get username
  if [[ -z "$SSH_USER" ]]; then
    echo
    echo "Please enter your SSH username (e.g., u0_a123 for Termux, sshelper for SSHelper):"
    read -r SSH_USER
    if [[ -z "$SSH_USER" ]]; then
      echo "ERROR: Username cannot be empty" >&2
      exit 1
    fi
  fi
  
  # Check if already mounted FIRST (before trying to create directory)
  # Use mount command for better detection (mountpoint doesn't always work for FUSE)
  local is_mounted=false
  if mount | grep -q " on $MOUNT_POINT "; then
    is_mounted=true
  elif mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    is_mounted=true
  fi
  
  if [[ "$is_mounted" == "true" ]]; then
    echo "ERROR: $MOUNT_POINT is already mounted" >&2
    echo "Run: ./android-sshfs-helper.sh unmount" >&2
    exit 1
  fi
  
  # Create mount point (required for sshfs) - skip for /Volumes (macOS manages those)
  if [[ ! "$MOUNT_POINT" =~ ^/Volumes/ ]]; then
    mkdir -p "$MOUNT_POINT" 2>/dev/null || {
      # If mkdir fails and it's not because it's a mount point, it might be a file
      if [[ ! -d "$MOUNT_POINT" ]] && [[ -e "$MOUNT_POINT" ]]; then
        echo "ERROR: $MOUNT_POINT exists but is not a directory" >&2
        exit 1
      fi
    }
  fi
  
  echo
  echo "Mounting Android device..."
  echo "  IP: $ANDROID_IP"
  echo "  User: $SSH_USER"
  echo "  Port: $SSH_PORT"
  echo "  Mount point: $MOUNT_POINT"
  echo
  
  # Try multiple Android storage paths
  # Order: most common/useful first
  declare -a android_paths=(
    "/storage/emulated/0"                              # Main internal storage (most common)
    "/sdcard"                                          # Symlink (if available)
    "/data/data/com.termux/files/home/storage/shared"  # Termux shared storage (user-friendly)
    "/storage/self/primary"                            # Alternative path
    "/data/data/com.termux/files/home"                 # Termux home directory
  )
  
  mount_success=false
  for remote_path in "${android_paths[@]}"; do
    echo "Trying remote path: $remote_path"
    
    # Run sshfs (with or without sudo based on USE_SUDO flag)
    # Note: If using sudo, it will prompt for password - that's expected
    sshfs_exit=1
    if [[ "$USE_SUDO" == "true" ]]; then
      echo "  (Using sudo - you'll be prompted for your Mac password)"
      # Run sudo directly (not in subshell) so password prompt is visible
      if sudo sshfs -p "$SSH_PORT" -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,allow_other,defer_permissions \
         "${SSH_USER}@${ANDROID_IP}:${remote_path}" "$MOUNT_POINT" 2>&1; then
        sshfs_exit=0
      else
        sshfs_exit=$?
      fi
    else
      # Run sshfs directly (don't capture output so errors are visible)
      # Use minimal options to match working command, but add useful ones
      if sshfs -p "$SSH_PORT" -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 \
         "${SSH_USER}@${ANDROID_IP}:${remote_path}" "$MOUNT_POINT" 2>&1; then
        sshfs_exit=0
        sshfs_output=""
      else
        sshfs_exit=$?
        # Capture output for error checking (only if it failed)
        sshfs_output="Mount failed with exit code $sshfs_exit"
      fi
    fi
    
    # Check if mount actually succeeded
    # sshfs returns 0 on success, but verify with mount command
    if [[ $sshfs_exit -eq 0 ]]; then
      # Brief pause to let mount register in mount table
      sleep 0.3
      
      # Check if mount is visible (mount command is more reliable than mountpoint for FUSE)
      local mount_verified=false
      if mount | grep -q " on $MOUNT_POINT "; then
        mount_verified=true
      elif mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        mount_verified=true
      elif [[ -d "$MOUNT_POINT" ]] && ls "$MOUNT_POINT" >/dev/null 2>&1; then
        # Mount point is accessible even if not in mount table yet
        mount_verified=true
      fi
      
      if [[ "$mount_verified" == "true" ]]; then
        echo
        echo "SUCCESS! Android device mounted at: $MOUNT_POINT"
        echo "Remote path: $remote_path"
        echo "Opening in Finder..."
        open "$MOUNT_POINT"
        mount_success=true
        break
      else
        echo "  ⚠ Mount command returned success but mount not verified"
        echo "  → This might still work - check $MOUNT_POINT manually"
        # Continue to try next path
      fi
    else
      # sshfs failed - check for permission errors
      if [[ "$USE_SUDO" != "true" ]] && echo "${sshfs_output:-}" | grep -q "Operation not permitted"; then
        echo "  ❌ Permission error: macFUSE needs Full Disk Access"
        echo "     Try adding Terminal.app to: System Settings > Privacy & Security > Full Disk Access"
        echo "     Or use --use-sudo flag to use sudo instead"
      fi
      # Unmount if partial mount occurred
      umount "$MOUNT_POINT" 2>/dev/null || diskutil unmount "$MOUNT_POINT" 2>/dev/null || true
      echo "  Failed, trying next path..."
      echo
    fi
  done
  
  if [[ "$mount_success" != "true" ]]; then
    echo
    echo "Mount failed for all paths. Common issues:" >&2
    echo "  1. macFUSE permission:" >&2
    echo "     - Add Terminal.app to: System Settings > Privacy & Security > Full Disk Access" >&2
    echo "     - Also add: /Library/Filesystems/macfuse.fs/Contents/Resources/mount_macfuse" >&2
    echo "     - Restart Terminal (or reboot) after granting permissions" >&2
    echo "  2. Alternative: Try mounting with sudo:" >&2
    echo "     sudo sshfs -o allow_other,defer_permissions -p $SSH_PORT ${SSH_USER}@${ANDROID_IP}:/storage/emulated/0 $MOUNT_POINT" >&2
    echo "  2. SSH server not running on Android (run 'sshd' in Termux)" >&2
    echo "  3. Wrong username or password (check with 'whoami' in Termux)" >&2
    echo "  4. Wrong port (Termux: 8022, SSHelper: 2222)" >&2
    echo "  5. Device not on same Wi-Fi network as Mac" >&2
    echo
    echo "Test SSH connection:" >&2
    echo "  ssh -p $SSH_PORT ${SSH_USER}@${ANDROID_IP}" >&2
    exit 1
  fi
}

cmd_unmount() {
  # Check if mounted using mount command (more reliable than mountpoint for FUSE)
  local is_mounted=false
  if mount | grep -q " on $MOUNT_POINT "; then
    is_mounted=true
  elif mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    is_mounted=true
  fi
  
  if [[ "$is_mounted" != "true" ]]; then
    echo "$MOUNT_POINT is not mounted"
    return 0
  fi
  
  echo "Unmounting $MOUNT_POINT..."
  
  # For /Volumes paths, use diskutil (macOS standard)
  # For other paths, try umount first, then diskutil
  local unmount_success=false
  if [[ "$MOUNT_POINT" =~ ^/Volumes/ ]]; then
    # /Volumes paths - use diskutil
    if diskutil unmount "$MOUNT_POINT" 2>/dev/null; then
      unmount_success=true
    elif diskutil unmount force "$MOUNT_POINT" 2>/dev/null; then
      unmount_success=true
    fi
  else
    # Other paths - try umount first, then diskutil
    if umount "$MOUNT_POINT" 2>/dev/null; then
      unmount_success=true
    elif diskutil unmount "$MOUNT_POINT" 2>/dev/null; then
      unmount_success=true
    fi
  fi
  
  if [[ "$unmount_success" == "true" ]]; then
    echo "SUCCESS! Unmounted $MOUNT_POINT"
    # Only try to remove if it's not in /Volumes (macOS manages /Volumes)
    if [[ ! "$MOUNT_POINT" =~ ^/Volumes/ ]]; then
      rmdir "$MOUNT_POINT" 2>/dev/null || true
    fi
  else
    echo "ERROR: Failed to unmount. You may need to:" >&2
    echo "  - Close Finder windows that have this volume open" >&2
    if [[ "$MOUNT_POINT" =~ ^/Volumes/ ]]; then
      echo "  - Try manually: diskutil unmount '$MOUNT_POINT'" >&2
      echo "  - Or force: diskutil unmount force '$MOUNT_POINT'" >&2
    else
      echo "  - Try manually: umount '$MOUNT_POINT'" >&2
      echo "  - Or: diskutil unmount '$MOUNT_POINT'" >&2
    fi
    exit 1
  fi
}

# Parse flags (called after command is extracted)
parse_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--ssh-user)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR: --ssh-user requires a value" >&2
          exit 1
        fi
        SSH_USER="$2"
        shift 2
        ;;
      -i|--android-ip)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR: --android-ip requires a value" >&2
          exit 1
        fi
        ANDROID_IP="$2"
        shift 2
        ;;
      -p|--ssh-port)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR: --ssh-port requires a value" >&2
          exit 1
        fi
        SSH_PORT="$2"
        shift 2
        ;;
      -m|--mount-point)
        if [[ -z "${2:-}" ]]; then
          echo "ERROR: --mount-point requires a value" >&2
          exit 1
        fi
        MOUNT_POINT="$2"
        shift 2
        ;;
      -s|--use-sudo)
        USE_SUDO="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

# Main
if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

# Handle help flag before command
if [[ "$COMMAND" == "-h" ]] || [[ "$COMMAND" == "--help" ]]; then
  usage
  exit 0
fi

# Parse flags for the command
parse_flags "$@"

case "$COMMAND" in
  get-ip)
    cmd_get_ip
    ;;
  mount)
    cmd_mount
    ;;
  unmount)
    cmd_unmount
    ;;
  setup)
    cmd_setup
    ;;
  *)
    echo "ERROR: Unknown command: $COMMAND" >&2
    usage
    exit 1
    ;;
esac

