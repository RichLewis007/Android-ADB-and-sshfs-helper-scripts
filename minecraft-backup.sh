#!/usr/bin/env bash
set -euo pipefail

# minecraft-backup.sh
#
# One-command backup for Minecraft Bedrock (Android) worlds + packs.
# Works on modern Android (Pixel 8) using adb pull.
#
# What it backs up:
#   - minecraftWorlds/ (world data)
#   - resource_packs/ and behavior_packs/ (optional content)
#   - other com.mojang data under games/com.mojang
#
# Outputs:
#   ./mc_backups/<timestamp>/com.mojang/...
#   ./mc_backups/<timestamp>/mcworld_exports/*.mcworld (optional)
#
# Usage:
#   ./minecraft-backup.sh
#   ./minecraft-backup.sh --export-mcworld
#   ./minecraft-backup.sh --adb-path /path/to/adb --export-mcworld
#   ./minecraft-backup.sh --out-dir /some/dir
#
# Notes:
# - Close Minecraft before running for best consistency.
# - If adb is not installed, install android platform tools.
#   macOS: brew install android-platform-tools

ANDROID_SRC_1="/sdcard/Android/data/com.mojang.minecraftpe/files/games/com.mojang"
ANDROID_SRC_2="/storage/emulated/0/Android/data/com.mojang.minecraftpe/files/games/com.mojang"

ADB_BIN="adb"
OUT_DIR="./mc_backups"
EXPORT_MCWORLD="false"

usage() {
  cat <<'EOF'
Usage:
  minecraft-backup.sh [--export-mcworld] [--out-dir DIR] [--adb-path PATH]

Options:
  --export-mcworld     Also export each world as a .mcworld file (zip of world contents)
  --out-dir DIR        Output root directory (default: ./mc_backups)
  --adb-path PATH      Path to adb binary (default: adb in PATH)
  -h, --help           Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --export-mcworld)
      EXPORT_MCWORLD="true"
      shift
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      if [[ -z "$OUT_DIR" ]]; then
        echo "ERROR: --out-dir requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --adb-path)
      ADB_BIN="${2:-}"
      if [[ -z "$ADB_BIN" ]]; then
        echo "ERROR: --adb-path requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

timestamp_now() {
  # Your preferred style: %Y-%m-%d__%I-%M-%S-%p
  date +"%Y-%m-%d__%I-%M-%S-%p"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $cmd" >&2
    exit 1
  fi
}

echo "== Minecraft Bedrock Android backup =="
require_cmd "$ADB_BIN"
require_cmd "zip"
require_cmd "find"
require_cmd "wc"

echo
echo "Checking adb connection..."
"$ADB_BIN" devices 1>/dev/null

device_count="$("$ADB_BIN" devices | awk 'NR>1 && $2=="device"{count++} END{print count+0}')"
if [[ "$device_count" -lt 1 ]]; then
  echo "ERROR: No adb device found. Plug in phone, enable USB debugging, and accept the prompt." >&2
  exit 1
fi

ts="$(timestamp_now)"
dest_root="${OUT_DIR}/${ts}"
dest_data="${dest_root}/com.mojang"

mkdir -p "$dest_root"

echo
echo "Backup destination:"
echo "  $dest_root"
echo

try_pull() {
  local src="$1"
  echo "Attempting adb pull from:"
  echo "  $src"
  if "$ADB_BIN" pull "$src" "$dest_data" >/dev/null 2>&1; then
    echo "SUCCESS: Pulled from $src"
    return 0
  fi
  echo "FAILED: Could not pull from $src"
  return 1
}

if ! try_pull "$ANDROID_SRC_1"; then
  if ! try_pull "$ANDROID_SRC_2"; then
    echo
    echo "ERROR: Could not adb pull Minecraft data from either path."
    echo "Tried:"
    echo "  $ANDROID_SRC_1"
    echo "  $ANDROID_SRC_2"
    echo
    echo "Possible causes:"
    echo "  - Android is blocking access on this build"
    echo "  - The path differs due to Minecraft storage setting"
    echo "  - USB debugging permission not granted"
    echo
    echo "Tip: Open Minecraft once, confirm worlds exist, close it, then retry."
    exit 1
  fi
fi

worlds_dir="${dest_data}/minecraftWorlds"
report="${dest_root}/backup_report.txt"

echo
echo "Writing report:"
echo "  $report"

{
  echo "Minecraft Bedrock backup report"
  echo "Timestamp: $ts"
  echo "Output: $dest_root"
  echo
  echo "Top-level folders backed up under com.mojang:"
  (cd "$dest_data" && ls -1) || true
  echo
  if [[ -d "$worlds_dir" ]]; then
    echo "World folders found:"
    (cd "$worlds_dir" && ls -1) || true
    echo
    echo "World name sanity check (levelname.txt):"
    for w in "$worlds_dir"/*; do
      [[ -d "$w" ]] || continue
      wid="$(basename "$w")"
      name_file="$w/levelname.txt"
      if [[ -f "$name_file" ]]; then
        name="$(cat "$name_file" | tr -d '\r' | head -n 1)"
        echo "  $wid -> $name"
      else
        echo "  $wid -> (no levelname.txt)"
      fi
    done
    echo
    echo "World basic integrity check:"
    for w in "$worlds_dir"/*; do
      [[ -d "$w" ]] || continue
      wid="$(basename "$w")"
      ok="yes"
      [[ -f "$w/level.dat" ]] || ok="no"
      [[ -d "$w/db" ]] || ok="no"
      dbcount="0"
      if [[ -d "$w/db" ]]; then
        dbcount="$(find "$w/db" -type f 2>/dev/null | wc -l | tr -d ' ')"
      fi
      echo "  $wid -> level.dat: $([[ -f "$w/level.dat" ]] && echo yes || echo no), db/: $([[ -d "$w/db" ]] && echo yes || echo no), db files: $dbcount, overall: $ok"
    done
  else
    echo "No minecraftWorlds directory found at:"
    echo "  $worlds_dir"
    echo "Your Minecraft may be using a different storage mode, or access was blocked."
  fi
} > "$report"

echo
echo "Backup pull complete."

if [[ "$EXPORT_MCWORLD" == "true" ]]; then
  if [[ ! -d "$worlds_dir" ]]; then
    echo "WARNING: Cannot export .mcworld because minecraftWorlds/ was not found."
  else
    export_dir="${dest_root}/mcworld_exports"
    mkdir -p "$export_dir"
    echo
    echo "Exporting .mcworld files to:"
    echo "  $export_dir"
    echo

    for w in "$worlds_dir"/*; do
      [[ -d "$w" ]] || continue
      wid="$(basename "$w")"
      name_file="$w/levelname.txt"
      world_name="$wid"
      if [[ -f "$name_file" ]]; then
        world_name="$(cat "$name_file" | tr -d '\r' | head -n 1)"
      fi

      # Sanitize filename
      safe_name="$(echo "$world_name" | tr '/\n\r\t' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ *//; s/ *$//' | sed 's/[^A-Za-z0-9._ -]/_/g')"
      out_file="${export_dir}/${safe_name}.mcworld"

      # mcworld is a zip of the CONTENTS of the world folder (not the folder itself)
      (
        cd "$w"
        zip -r -q "$out_file" ./*
      )

      echo "Exported: $out_file"
    done
  fi
fi

echo
echo "Done."
echo "Backup folder:"
echo "  $dest_root"
echo "Report:"
echo "  $report"
