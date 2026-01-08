#!/usr/bin/env bash
# android-check-adb-or-sshfs-access.sh
#
# Author: Rich Lewis - GitHub @RichLewis007
#
# Check what directories are accessible on Android device via ADB or SSHFS
#
# Usage: ./android-check-adb-or-sshfs-access.sh [adb|sshfs] [OPTIONS]
#
# Options for sshfs mode:
#   -u, --ssh-user USER     SSH username (Termux user, e.g., u0_a499)
#   -i, --android-ip IP     Android device IP address
#   -p, --ssh-port PORT     SSH port (default: 8022)
#   -h, --help              Show this help message
#
# SSH Authentication:
#   The script first attempts SSH key authentication (passwordless). If that fails,
#   it will fall back to password authentication and prompt for a password.
#
#   For password authentication:
#     1. On your Android device (in Termux), set a password using: passwd
#     2. Use that password when prompted by this script
#
#   For SSH key authentication (recommended for automation):
#     Set up SSH keys between your Mac and the Android device for passwordless access

set -euo pipefail

ADB_BIN="adb"
SSH_USER=""
ANDROID_IP=""
SSH_PORT="8022"
MODE=""

check_device() {
  device_count="$("$ADB_BIN" devices | awk 'NR>1 && $2=="device"{count++} END{print count+0}')"
  if [[ "$device_count" -lt 1 ]]; then
    echo "ERROR: No adb device found. Plug in phone, enable USB debugging, and accept the prompt." >&2
    exit 1
  fi
}

check_via_adb() {
  echo "=== Checking Access via ADB ==="
  echo "(ADB has elevated permissions and can access most directories)"
  echo
  
  declare -a paths=(
    "/storage/emulated/0"
    "/storage/emulated/0/DCIM"
    "/storage/emulated/0/Download"
    "/storage/emulated/0/Android/data"
  )
  
  for path in "${paths[@]}"; do
    echo -n "Checking: $path ... "
    if "$ADB_BIN" shell "test -d '$path' 2>/dev/null && echo 'EXISTS'" 2>/dev/null | grep -q "EXISTS"; then
      echo "✓ EXISTS"
      # Try to list contents
      count="$("$ADB_BIN" shell "ls -1 '$path' 2>/dev/null | wc -l" 2>/dev/null | tr -d '\r' || echo '0')"
      echo "  → Contains $count items"
    else
      echo "✗ NOT FOUND or NOT ACCESSIBLE"
    fi
  done
}

check_via_ssh() {
  if [[ -z "$SSH_USER" ]] || [[ -z "$ANDROID_IP" ]]; then
    echo "ERROR: --ssh-user and --android-ip must be provided for SSHFS check" >&2
    echo "Example: $0 sshfs --ssh-user u0_a499 --android-ip 192.168.86.100" >&2
    exit 1
  fi
  
  echo "=== Checking Access via SSHFS ==="
  echo "(SSHFS runs as the Termux user - restricted by Android Scoped Storage)"
  echo
  
  declare -a paths=(
    "/storage/emulated/0"
    "/storage/emulated/0/DCIM"
    "/storage/emulated/0/Download"
    "/storage/emulated/0/Android/data"
    "/data/data/com.termux/files/home/storage/shared"
    "/data/data/com.termux/files/home/storage/shared/Android/data"
  )
  
  # Test SSH connection first
  if ! ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no \
    "${SSH_USER}@${ANDROID_IP}" "echo 'SSH_OK'" 2>/dev/null | grep -q "SSH_OK"; then
    echo "WARNING: SSH key authentication failed. Install SSH keys for passwordless access." >&2
    echo "Attempting with password authentication (you may be prompted for password)..." >&2
    echo
    USE_BATCHMODE=no
  else
    USE_BATCHMODE=yes
  fi
  
  for path in "${paths[@]}"; do
    echo -n "Checking: $path ... "
    
    local ssh_opts="-p $SSH_PORT -o ConnectTimeout=5 -o StrictHostKeyChecking=no"
    if [[ "$USE_BATCHMODE" == "yes" ]]; then
      ssh_opts="$ssh_opts -o BatchMode=yes"
    fi
    
    result=$(ssh $ssh_opts "${SSH_USER}@${ANDROID_IP}" \
      "test -d '$path' 2>/dev/null && echo 'EXISTS'" 2>/dev/null || echo "")
    
    if echo "$result" | grep -q "EXISTS"; then
      echo "✓ EXISTS"
      # Try to list contents
      count=$(ssh $ssh_opts "${SSH_USER}@${ANDROID_IP}" \
        "ls -1 '$path' 2>/dev/null | wc -l" 2>/dev/null | tr -d '\r' || echo "0")
      echo "  → Contains $count items"
    else
      echo "✗ NOT FOUND or PERMISSION DENIED"
    fi
  done
}

usage() {
  cat <<EOF
Usage: android-check-adb-or-sshfs-access.sh [adb|sshfs] [OPTIONS]

Checks what directories are accessible on the Android device.

Modes:
  adb     - Check access via ADB (has elevated permissions)
  sshfs   - Check access via SSHFS (restricted by Android Scoped Storage)

Options for sshfs mode:
  -u, --ssh-user USER     SSH username (Termux user, e.g., u0_a499) [required]
  -i, --android-ip IP     Android device IP address [required]
  -p, --ssh-port PORT     SSH port (default: 8022)
  -h, --help              Show this help message

Examples:
  $0 adb
  $0 sshfs --ssh-user u0_a499 --android-ip 192.168.86.100
  $0 sshfs -u u0_a499 -i 192.168.86.100 -p 8022

EOF
}

# Parse command line arguments
parse_args() {
  # First argument should be the mode
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi
  
  MODE="$1"
  shift
  
  # Validate mode
  if [[ "$MODE" != "adb" ]] && [[ "$MODE" != "sshfs" ]]; then
    echo "ERROR: Unknown mode: $MODE" >&2
    echo "Must be either 'adb' or 'sshfs'" >&2
    usage
    exit 1
  fi
  
  # Parse flags
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
parse_args "$@"

check_device

case "$MODE" in
  adb)
    check_via_adb
    ;;
  sshfs)
    check_via_ssh
    ;;
esac

echo
echo "=== Notes ==="
echo "Android 11+ (Scoped Storage) restricts access to:"
echo "  - /storage/emulated/0/Android/data/* (except via ADB or owning app)"
echo "  - /storage/emulated/0/Android/obb/*"
echo
echo "For protected app data directories, use ADB (android-adb-helper.sh)"
echo "For general file access, SSHFS works fine for most other directories"

