#!/usr/bin/env bash
# android-sshfs-mounts-cleanup.sh
#
# Author: Rich Lewis - GitHub @RichLewis007
#
# Safely clean up stale or leftover SSHFS mount points on desktop machine.
#
# Usage: ./android-sshfs-mounts-cleanup.sh [directory...]
#
# If no directories provided, checks common mount point names

set -euo pipefail

cleanup_mount() {
  local dir="$1"
  local full_path="$dir"
  
  # Make absolute path if relative
  if [[ ! "$dir" =~ ^/ ]]; then
    full_path="$(cd "$(dirname "$dir")" && pwd)/$(basename "$dir")"
  fi
  
  echo "=== Cleaning up: $full_path ==="
  
  # Check if it exists
  if [[ ! -e "$full_path" ]]; then
    echo "  ✓ Does not exist, nothing to clean"
    return 0
  fi
  
  # Check if it's a mount point
  if mountpoint -q "$full_path" 2>/dev/null; then
    echo "  → Attempting to unmount..."
    if umount "$full_path" 2>/dev/null; then
      echo "  ✓ Unmounted successfully"
    elif sudo umount "$full_path" 2>/dev/null; then
      echo "  ✓ Unmounted successfully (with sudo)"
    else
      echo "  ⚠ WARNING: Could not unmount. It may be in use."
      echo "    Try manually: sudo umount -f '$full_path'"
      return 1
    fi
  else
    echo "  → Not currently mounted"
  fi
  
  # Check if it's a directory (or broken mount point)
  if [[ -d "$full_path" ]] || [[ -e "$full_path" ]]; then
    # Try to remove if it's empty
    if rmdir "$full_path" 2>/dev/null; then
      echo "  ✓ Removed empty directory"
      return 0
    else
      # Check if it has contents
      if [[ -d "$full_path" ]] && [[ -n "$(ls -A "$full_path" 2>/dev/null)" ]]; then
        echo "  ⚠ Directory is not empty. Contents:"
        ls -la "$full_path" | head -5
        echo "  → Remove manually with: rm -rf '$full_path'"
        return 1
      else
        echo "  ⚠ Could not remove (may be a broken mount point)"
        echo "  → Try manually: sudo rmdir '$full_path'"
        echo "  → Or force: sudo umount -f '$full_path' && rmdir '$full_path'"
        return 1
      fi
    fi
  fi
  
  echo "  ✓ Cleanup complete"
  return 0
}

# Main
if [[ $# -eq 0 ]]; then
  # Default: check common locations
  declare -a default_dirs=(
    "/Volumes/my-sshfs"
  )
  
  echo "No directories specified. Checking common mount points:"
  echo
  
  found_any=false
  for dir in "${default_dirs[@]}"; do
    if [[ -e "$dir" ]] || mountpoint -q "$dir" 2>/dev/null; then
      cleanup_mount "$dir"
      echo
      found_any=true
    fi
  done
  
  if [[ "$found_any" == false ]]; then
    echo "No common mount points were found."
  fi
else
  # Clean up specified directories
  for dir in "$@"; do
    cleanup_mount "$dir"
    echo
  done
fi



