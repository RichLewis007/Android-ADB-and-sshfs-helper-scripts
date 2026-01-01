#!/usr/bin/env bash
set -euo pipefail

# android-adb-helper.sh
#
# Author: Rich Lewis - GitHub @RichLewis007
#
# Helper script for easier file access to Android devices via ADB.
# This script provides shortcuts for common file operations using adb pull/push,
# similar to your minecraft-backup.sh script, but for general file access.
#
# Usage:
#   ./android-adb-helper.sh list                    # List device files
#   ./android-adb-helper.sh pull <remote> <local>  # Pull files/directory from device to local
#   ./android-adb-helper.sh push <local> <remote>  # Push files/directory from local to device
#   ./android-adb-helper.sh move <remote> <local>  # Move all files (excluding hidden) from Android to local
#   ./android-adb-helper.sh shell                   # Open adb shell
#   ./android-adb-helper.sh explorer                # Open Android file explorer paths in Finder

# ADB runs with elevated permissions
# Bypasses Scoped Storage restrictions
# Can access Android/data directories

# Useful paths on my Pixel8:
# /storage/emulated/0 (aliased to /sdcard/ need trailing slash)
# /sdcard/DCIM (photos)
# /sdcard/Download
# /sdcard/Movies
# /sdcard/Music
# /sdcard/Pictures
# /sdcard/Screenshots
# /sdcard/Documents

# Usually BLOCKED paths on Android that this script can access via ADB:
# /storage/emulated/0/Android/data/*
# /storage/emulated/0/Android/obb/*

ADB_BIN="adb"

usage() {
  cat <<'EOF'
Usage:
  android-adb-helper.sh <command> [args...]

Commands:
  list [path]              List files in path (default: /sdcard)
  pull <remote> <local>    Pull files/directory from device to local
  push <local> <remote>    Push files/directory from local to device
  move <remote> <local>    Move all files (excluding hidden) from Android to local
  shell                    Open interactive adb shell
  explorer                 Open common Android paths in Finder after pulling
  
Examples:
  ./android-adb-helper.sh list /sdcard/DCIM
  ./android-adb-helper.sh pull /sdcard/DCIM ~/Desktop/DCIM
  ./android-adb-helper.sh push ~/Downloads/file.txt /sdcard/Download/
  ./android-adb-helper.sh move /sdcard/Download ~/Downloads/moved
  ./android-adb-helper.sh explorer

ADB runs with elevated permissions
Bypasses Scoped Storage restrictions
Can access Android/data directories

Useful paths on my Pixel8:
 /storage/emulated/0
 /sdcard/DCIM
 /sdcard/Download
 /sdcard/Movies
 /sdcard/Music
 /sdcard/Pictures
 /sdcard/Pictures/Screenshots
 /sdcard/Documents

Usually BLOCKED paths on Android that this script can access via ADB:
 /storage/emulated/0/Android/data/*
 /storage/emulated/0/Android/obb/*

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

check_remote_dir_exists() {
  local remote_path="$1"
  if ! "$ADB_BIN" shell "test -d '$remote_path' 2>/dev/null && echo exists" 2>/dev/null | grep -q "exists"; then
    echo "ERROR: No directory of that name found on Android device: $remote_path" >&2
    return 1
  fi
  return 0
}

cmd_list() {
  local path="${1:-/sdcard}"
  
  # Check if directory exists
  if ! check_remote_dir_exists "$path"; then
    return 1
  fi
  
  echo "Listing: $path"
  echo
  
  # Get the listing
  local listing
  listing=$("$ADB_BIN" shell "ls -la '$path' 2>/dev/null" | tr -d '\r')
  
  if [[ -z "$listing" ]]; then
    echo "ERROR: Cannot list directory: $path" >&2
    return 1
  fi
  
  # Count items: all lines except "total" line and lines ending with " ." or " .."
  # The last field in ls -la output is the filename
  local item_count
  item_count=$(echo "$listing" | grep -v "^total" | awk 'NF > 0 && $NF != "." && $NF != ".." {count++} END {print count+0}')
  
  # Display the listing (excluding the "total" line)
  echo "$listing" | grep -v "^total"
  echo
  echo "Total items: $item_count"
}

cmd_pull() {
  if [[ $# -lt 2 ]]; then
    echo "ERROR: pull requires <remote_path> <local_path>" >&2
    usage
    exit 1
  fi
  local remote="$1"
  local local_path="$2"
  
  # Check if remote path looks like a directory (ends with /)
  # If so, verify the directory exists before attempting pull
  if [[ "$remote" == */ ]]; then
    local check_path="${remote%/}"
    if ! check_remote_dir_exists "$check_path"; then
      exit 1
    fi
  fi
  
  echo "Pulling: $remote -> $local_path"
  "$ADB_BIN" pull "$remote" "$local_path"
  echo "Done. Files are in: $local_path"
  
  # Open in Finder if on macOS
  if [[ "$(uname)" == "Darwin" ]]; then
    open "$local_path"
  fi
}

cmd_push() {
  if [[ $# -lt 2 ]]; then
    echo "ERROR: push requires <local_path> <remote_path>" >&2
    usage
    exit 1
  fi
  local local_path="$1"
  local remote="$2"
  
  echo "Pushing: $local_path -> $remote"
  "$ADB_BIN" push "$local_path" "$remote"
  echo "Done."
}

cmd_shell() {
  echo "Opening adb shell..."
  "$ADB_BIN" shell
}

cmd_move() {
  if [[ $# -lt 2 ]]; then
    echo "ERROR: move requires <remote_path> <local_path>" >&2
    usage
    exit 1
  fi
  local remote="$1"
  local local_path="$2"
  
  # Ensure remote path doesn't end with / (for consistency)
  remote="${remote%/}"
  
  # Check if remote directory exists
  if ! check_remote_dir_exists "$remote"; then
    exit 1
  fi
  
  # Ensure local directory exists
  mkdir -p "$local_path" || {
    echo "ERROR: Cannot create local directory: $local_path" >&2
    exit 1
  }
  
  echo "Scanning Android directory: $remote"
  echo "(excluding hidden files)"
  echo
  
  # Get list of all files (non-hidden) in the Android directory
  # Using find to get files recursively, filtering out hidden files
  local files_list
  files_list=$("$ADB_BIN" shell "find '$remote' -type f ! -name '.*' ! -path '*/.*' 2>/dev/null" | tr -d '\r' || true)
  
  if [[ -z "$files_list" ]]; then
    echo "No non-hidden files found in: $remote"
    return 0
  fi
  
  # Count files
  local file_count
  file_count=$(echo "$files_list" | grep -c . || echo "0")
  
  echo "Found $file_count files to move"
  echo "Source: $remote"
  echo "Destination: $local_path"
  echo
  echo "Starting copy operation..."
  echo
  
  # Copy files using adb pull (this will preserve directory structure)
  if ! "$ADB_BIN" pull "$remote" "$local_path"; then
    echo "ERROR: Failed to copy files from Android device" >&2
    exit 1
  fi
  
  echo
  echo "================================================================================"
  echo "Copy complete: $file_count files copied"
  echo "================================================================================"
  echo
  echo "Files have been copied to: $local_path"
  echo
  echo "Please verify the copied files before they are deleted from the Android device."
  echo
  echo "Press ENTER to continue (delete files from Android), CTRL-C to cancel"
  read -r
  
  echo
  echo "Deleting files from Android device: $remote"
  echo
  
  # Delete files from Android device
  # Use find to delete files (excluding hidden files)
  if ! "$ADB_BIN" shell "find '$remote' -type f ! -name '.*' ! -path '*/.*' -delete 2>/dev/null"; then
    echo "WARNING: Some files may not have been deleted. Check manually." >&2
  fi
  
  # Also try to remove empty directories (optional, but clean)
  "$ADB_BIN" shell "find '$remote' -type d -empty -delete 2>/dev/null" || true
  
  echo "Done. $file_count files moved from $remote to $local_path"
  
  # Open in Finder if on macOS
  if [[ "$(uname)" == "Darwin" ]]; then
    open "$local_path"
  fi
}

cmd_explorer() {
  echo "================================================================================"
  echo "Android File Explorer"
  echo "================================================================================"
  echo
  echo "This will pull the following directories from your Android device:"
  echo "  - DCIM (photos/videos)"
  echo "  - Download"
  echo "  - Movies"
  echo "  - Music"
  echo "  - Pictures"
  echo "  - Documents"
  echo
  echo "Files will be temporarily downloaded to: ${HOME}/AndroidExplorer"
  echo "The folder will be opened in Finder when complete."
  echo
  echo "Note: This operation may take a while depending on the amount of data."
  echo
  echo "Press ENTER to continue, CTRL-C to cancel"
  read -r
  
  local temp_dir="${HOME}/AndroidExplorer"
  mkdir -p "$temp_dir"
  
  echo
  echo "Pulling common Android directories to: $temp_dir"
  echo "(This may take a while...)"
  echo
  
  # Common paths to explore
  declare -a paths=(
    "/sdcard/DCIM"
    "/sdcard/Download"
    "/sdcard/Movies"
    "/sdcard/Music"
    "/sdcard/Pictures"
    "/sdcard/Documents"
  )
  
  for path in "${paths[@]}"; do
    local name=$(basename "$path")
    local dest="$temp_dir/$name"
    echo "Pulling $path..."
    if "$ADB_BIN" pull "$path" "$dest" 2>/dev/null; then
      echo "  ✓ $name"
    else
      echo "  ✗ $name (not accessible or empty)"
      rm -rf "$dest" 2>/dev/null || true
    fi
  done
  
  echo
  echo "Done! Opening in Finder..."
  open "$temp_dir"
  echo "Files are temporarily in: $temp_dir"
  echo "You can delete this folder when done browsing."
}

# Main
require_cmd "$ADB_BIN"
check_device

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

case "$1" in
  list)
    cmd_list "${2:-}"
    ;;
  pull)
    shift
    cmd_pull "$@"
    ;;
  push)
    shift
    cmd_push "$@"
    ;;
  move)
    shift
    cmd_move "$@"
    ;;
  shell)
    cmd_shell
    ;;
  explorer)
    cmd_explorer
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: Unknown command: $1" >&2
    usage
    exit 1
    ;;
esac



