#!/usr/bin/env bash
# android-adb-find-paths.sh
#
# Author: Rich Lewis - GitHub @RichLewis007
# 
# Helper script to find Android storage paths via ADB.
# This helps you discover which path to use for SSHFS mounting.
#
# Usage: ./android-adb-find-paths.sh

ADB_BIN="adb"

echo "== Finding Android Storage Paths via ADB =="
echo

check_device() {
  device_count="$("$ADB_BIN" devices | awk 'NR>1 && $2=="device"{count++} END{print count+0}')"
  if [[ "$device_count" -lt 1 ]]; then
    echo "ERROR: No adb device found. Plug in phone, enable USB debugging, and accept the prompt." >&2
    exit 1
  fi
}

check_device

echo "Checking common Android storage paths..."
echo

declare -a paths=(
  "/sdcard"
  "/storage/emulated/0"
  "/storage/self/primary"
  "/storage/emulated/0/DCIM"
  "/storage/emulated/0/Download"
  "/mnt/sdcard"
)

echo "Path                      | Exists | Accessible | Sample Files"
echo "--------------------------|--------|------------|--------------"

for path in "${paths[@]}"; do
  # Check if path exists
  if "$ADB_BIN" shell "test -e '$path' 2>/dev/null && echo exists" 2>/dev/null | grep -q "exists"; then
    exists="YES"
    
    # Check if it's a directory
    if "$ADB_BIN" shell "test -d '$path' 2>/dev/null && echo dir" 2>/dev/null | grep -q "dir"; then
      # Try to list a few items
      sample="$("$ADB_BIN" shell "ls -1 '$path' 2>/dev/null | head -3 | tr '\n' ' ' | sed 's/ $//'")"
      if [[ -n "$sample" ]]; then
        accessible="YES"
        # Truncate sample if too long
        if [[ ${#sample} -gt 30 ]]; then
          sample="${sample:0:27}..."
        fi
      else
        accessible="EMPTY"
        sample="(empty)"
      fi
    else
      accessible="FILE"
      sample="(is a file)"
    fi
  else
    exists="NO"
    accessible="-"
    sample="-"
  fi
  
  printf "%-25s | %-6s | %-10s | %s\n" "$path" "$exists" "$accessible" "$sample"
done

echo
echo "=== Recommended paths to try for SSHFS ==="
echo
echo "1. If /storage/emulated/0 exists and is accessible, use:"
echo "   /storage/emulated/0"
echo
echo "2. If you're using Termux's shared storage, use:"
echo "   ~/storage/shared"
echo "   (Note: ~ expands to /data/data/com.termux/files/home)"
echo
echo "3. Try /sdcard if it exists (often a symlink)"
echo "   /sdcard"
echo
echo "=== To explore more in Termux ==="
echo "Run these commands IN TERMUX on your Android device:"
echo "  ls -la /storage/"
echo "  ls -la ~/storage/"
echo "  ls -la /sdcard/"
echo "  find /storage -maxdepth 2 -type d 2>/dev/null"



