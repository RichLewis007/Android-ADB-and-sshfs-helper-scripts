#!/usr/bin/env bash
# minecraft-backup-tui.sh
#
# TUI (Text User Interface) for Minecraft Bedrock Android backup script
# Uses bash-ui.sh for menu functionality
#
# Description:
#   This script provides an interactive menu-driven interface for backing up
#   Minecraft Bedrock worlds from an Android device via ADB (Android Debug Bridge).
#   It allows users to selectively backup individual worlds or all worlds at once,
#   in either "as-is" directory format or as .mcworld files (zipped format).
#
# Features:
#   - Interactive menu system using bash-ui.sh (supports fzf/gum/basic menu)
#   - Lists all Minecraft worlds from the Android device
#   - Displays world names from levelname.txt files
#   - Backup individual worlds with format choice:
#     * World folders: Full directory structure with descriptive names
#       (format: <world-name>_<world-id>)
#     * .mcworld files: Zipped world archives ready for import
#   - Backup all worlds at once with format choice
#   - Automatic path detection (tries primary path, falls back to alternative)
#   - Progress indicators with spinners for long operations
#   - Organized backup directory structure with timestamps
#
# Requirements:
#   - ADB (Android Debug Bridge) installed and in PATH
#   - Android device connected via USB with USB debugging enabled
#   - bash-ui.sh library at ~/utils/bash-ui.sh
#   - zip command (for .mcworld export)
#
# Usage:
#   ./minecraft-backup-tui.sh
#
# Configuration:
#   - MINECRAFT_WORLDS_PATH: Primary path to Minecraft worlds on Android
#   - MINECRAFT_WORLDS_ALT_PATH: Alternative path (used as fallback)
#   - BACKUP_BASE_DIR: Base directory for backups (default: ~/Downloads/Minecraft-Worlds-Backups)
#
# Backup Directory Structure:
#   ~/Downloads/Minecraft-Worlds-Backups/
#   ├── world-folders/
#   │   └── <timestamp>/
#   │       └── <world-name>_<world-id>/
#   │           └── (world files)
#   └── mcworld-files/
#       └── <timestamp>/
#           └── <world-name>.mcworld
#
# Notes:
#   - Close Minecraft app before backing up for best consistency
#   - World names are sanitized for folder names (spaces/special chars -> dashes)
#   - The script tries both /sdcard/... and /storage/emulated/0/... paths automatically
#   - Menu navigation: Arrow keys (with fzf/gum) or type to search/filter

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/minecraft-backup.sh"
UI_LIB="${HOME}/utils/bash-ui.sh"

# Source the UI library
if [[ ! -f "$UI_LIB" ]]; then
  echo "ERROR: bash-ui.sh not found at $UI_LIB" >&2
  exit 1
fi
source "$UI_LIB"

# Configuration
ADB_BIN="adb"
MINECRAFT_WORLDS_PATH="/storage/emulated/0/Android/data/com.mojang.minecraftpe/files/games/com.mojang/minecraftWorlds"
BACKUP_BASE_DIR="${HOME}/Downloads/Minecraft-Worlds-Backups"
MINECRAFT_WORLDS_ALT_PATH="/sdcard/Android/data/com.mojang.minecraftpe/files/games/com.mojang/minecraftWorlds"


# Global variables
declare -a WORLD_LIST
declare -a WORLD_NAMES

# ============================================================
# Helper Functions
# ============================================================

check_device() {
  if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
    log_error "adb not found. Install with: brew install android-platform-tools"
    return 1
  fi

  device_count=$("$ADB_BIN" devices 2>/dev/null | awk 'NR>1 && $2=="device"{count++} END{print count+0}')
  if [[ "$device_count" -lt 1 ]]; then
    log_error "No ADB device found. Connect your phone and enable USB debugging."
    return 1
  fi
  return 0
}

get_world_list() {
  WORLD_LIST=()
  WORLD_NAMES=()

  log_info "Fetching world list from Android device..."
  log_info "Trying path: ${MINECRAFT_WORLDS_PATH}"
  
  # Use a simple loop approach - list all items in directory and check if they're directories
  # Try primary path first
  local worlds_raw=""
  # Use spinner but capture command output to temp file to avoid mixing with spinner output
  local temp_output=$(mktemp)
  if run_with_spinner "Listing worlds..." bash -c "\"$ADB_BIN\" shell \"for item in '${MINECRAFT_WORLDS_PATH}'/*; do [ -d \\\"\\\$item\\\" ] && basename \\\"\\\$item\\\"; done 2>/dev/null\" 2>/dev/null | tr -d '\r' > \"$temp_output\""; then
    worlds_raw=$(cat "$temp_output" 2>/dev/null || true)
  fi
  rm -f "$temp_output"
  
  if [[ -z "$worlds_raw" ]]; then
    # Try alternative path (MINECRAFT_WORLDS_ALT_PATH)
    log_info "Primary path not found, trying alternative: ${MINECRAFT_WORLDS_ALT_PATH}"
    temp_output=$(mktemp)
    if run_with_spinner "Listing worlds (alternative path)..." bash -c "\"$ADB_BIN\" shell \"for item in '${MINECRAFT_WORLDS_ALT_PATH}'/*; do [ -d \\\"\\\$item\\\" ] && basename \\\"\\\$item\\\"; done 2>/dev/null\" 2>/dev/null | tr -d '\r' > \"$temp_output\""; then
      worlds_raw=$(cat "$temp_output" 2>/dev/null || true)
      if [[ -n "$worlds_raw" ]]; then
        MINECRAFT_WORLDS_PATH="$MINECRAFT_WORLDS_ALT_PATH"
      fi
    fi
    rm -f "$temp_output"
  fi
  
  if [[ -z "$worlds_raw" ]]; then
    log_error "No worlds found in: ${MINECRAFT_WORLDS_PATH}"
    log_error "Or alternative: ${MINECRAFT_WORLDS_ALT_PATH}"
    log_warn "Make sure Minecraft is installed and has worlds."
    return 1
  fi
  
  # Parse the output line by line - convert to array and process
  # Split by newlines and process each
  local count=0
  mapfile -t world_lines < <(printf '%s\n' "$worlds_raw")
  
  log_info "Reading world names (${#world_lines[@]} worlds)..."
  for wid in "${world_lines[@]}"; do
    # Skip empty lines
    [[ -z "$wid" ]] && continue
    # Remove any trailing/leading whitespace
    wid=$(echo "$wid" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    [[ -z "$wid" ]] && continue
    
    # Skip if it looks like an error message
    [[ "$wid" == *"No such file"* ]] && continue
    [[ "$wid" == *"Permission denied"* ]] && continue
    
    # Try to get world name from levelname.txt (this is fast, no spinner needed)
    local world_name="$wid"
    local name_file="${MINECRAFT_WORLDS_PATH}/${wid}/levelname.txt"
    local name=""
    
    # Try to read levelname.txt
    name=$("$ADB_BIN" shell "cat '${name_file}' 2>/dev/null | head -1" 2>/dev/null | tr -d '\r\n' || true)
    if [[ -n "$name" ]]; then
      # Clean up the name
      name=$(echo "$name" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
      [[ -n "$name" ]] && world_name="$name"
    fi
    
    WORLD_LIST+=("$wid")
    WORLD_NAMES+=("$world_name")
    ((count++))
  done
  
  log_info "Parsed $count world(s) from output"

  if [[ ${#WORLD_LIST[@]} -eq 0 ]]; then
    log_warn "No worlds found after parsing. Make sure Minecraft is installed and has worlds."
    return 1
  fi

  log_info "Found ${#WORLD_LIST[@]} world(s)"
  return 0
}

timestamp_now() {
  date +"%Y-%m-%d__%I-%M-%S-%p"
}

# ============================================================
# Backup Functions
# ============================================================

backup_world_as_is() {
  local world_id="$1"
  local world_name="$2"
  
  local ts=$(timestamp_now)
  local backup_dir="${BACKUP_BASE_DIR}/world-folders/${ts}"
  
  # Sanitize world name: replace spaces and special characters with dashes
  local safe_name=$(echo "$world_name" | sed 's/[^A-Za-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
  local folder_name="${safe_name}_${world_id}"
  local dest_dir="${backup_dir}/${folder_name}"
  
  mkdir -p "$dest_dir"
  
  log_info "Backing up world: $world_name"
  log_info "Destination: $dest_dir"
  
  # Pull the world directory
  local world_path="${MINECRAFT_WORLDS_PATH}/${world_id}"
  if run_with_spinner "Pulling world files..." "$ADB_BIN" pull "$world_path" "$dest_dir" >/dev/null 2>&1; then
    log_ok "World backed up successfully!"
    log_info "Location: $dest_dir"
    
    if [[ "$(uname)" == "Darwin" ]]; then
      if confirm "Open backup location in Finder?"; then
        open "$backup_dir"
      fi
    fi
  else
    log_error "Failed to backup world"
    return 1
  fi
}

backup_world_as_mcworld() {
  local world_id="$1"
  local world_name="$2"
  
  local ts=$(timestamp_now)
  local backup_dir="${BACKUP_BASE_DIR}/mcworld-files/${ts}"
  mkdir -p "$backup_dir"
  
  # Sanitize world name for filename: replace all non-alphanumeric with dashes
  local safe_name=$(echo "$world_name" | sed 's/[^A-Za-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
  local out_file="${backup_dir}/${safe_name}.mcworld"
  local temp_dir="${backup_dir}/.temp_${world_id}"
  
  log_info "Exporting world: $world_name"
  log_info "Destination: $out_file"
  
  # Pull world to temp directory
  mkdir -p "$temp_dir"
  local world_path="${MINECRAFT_WORLDS_PATH}/${world_id}"
  if ! run_with_spinner "Pulling world files..." "$ADB_BIN" pull "$world_path" "$temp_dir/${world_id}" >/dev/null 2>&1; then
    log_error "Failed to pull world files"
    rm -rf "$temp_dir"
    return 1
  fi
  
  # Create zip file
  if command -v zip >/dev/null 2>&1; then
    if run_with_spinner "Creating .mcworld file..." bash -c "cd '$temp_dir/${world_id}' && zip -r -q '$out_file' ."; then
      rm -rf "$temp_dir"
      log_ok "World exported successfully!"
      log_info "File: $out_file"
      
      if [[ "$(uname)" == "Darwin" ]]; then
        if confirm "Open backup location in Finder?"; then
          open "$backup_dir"
        fi
      fi
    else
      log_error "Failed to create .mcworld file"
      rm -rf "$temp_dir"
      return 1
    fi
  else
    log_error "zip command not found. Install with: brew install zip"
    rm -rf "$temp_dir"
    return 1
  fi
}

# ============================================================
# Menu Handlers
# ============================================================

handler_list_worlds() {
  if ! check_device; then
    return 1
  fi
  
  if ! get_world_list; then
    echo
    printf "Press Enter to continue..."
    read -r
    return 1
  fi
  
  # Create display names with IDs, with "Return to main menu" at the top
  local display_items=("Return to main menu")
  local i
  for i in "${!WORLD_LIST[@]}"; do
    display_items+=("${WORLD_NAMES[$i]} (${WORLD_LIST[$i]})")
  done
  
  local choice
  choice=$(pick_option "Select a world to backup:" "${display_items[@]}") || return 0
  
  # Check if user selected "Return to main menu"
  if [[ "$choice" == "Return to main menu" ]]; then
    return 0
  fi
  
  # Extract world ID from choice (account for "Return to main menu" at index 0)
  local selected_world_id=""
  local selected_world_name=""
  for i in "${!WORLD_LIST[@]}"; do
    # display_items[0] is "Return to main menu", so worlds start at index 1
    local display_index=$((i + 1))
    if [[ "${display_items[$display_index]}" == "$choice" ]]; then
      selected_world_id="${WORLD_LIST[$i]}"
      selected_world_name="${WORLD_NAMES[$i]}"
      break
    fi
  done
  
  if [[ -z "$selected_world_id" ]]; then
    log_error "Could not find selected world"
    return 1
  fi
  
  # Prompt for backup type
  local backup_type
  backup_type=$(pick_option "Backup type for: $selected_world_name" \
    "Backup as world folder (full directory)" \
    "Export as .mcworld file") || return 0
  
  case "$backup_type" in
    "Backup as world folder (full directory)")
      backup_world_as_is "$selected_world_id" "$selected_world_name"
      ;;
    "Export as .mcworld file")
      backup_world_as_mcworld "$selected_world_id" "$selected_world_name"
      ;;
    *)
      log_error "Unknown backup type"
      return 1
      ;;
  esac
  
  echo
  printf "Press Enter to continue..."
  read -r
}

handler_backup_all() {
  if ! check_device; then
    return 1
  fi
  
  if ! get_world_list; then
    return 1
  fi
  
  log_info "Backing up all worlds..."
  
  local backup_type
  backup_type=$(pick_option "Backup all worlds as:" \
    "Backup as world folders (full directories)" \
    "Export as .mcworld files") || return 0
  
  local i
  for i in "${!WORLD_LIST[@]}"; do
    local world_id="${WORLD_LIST[$i]}"
    local world_name="${WORLD_NAMES[$i]}"
    
    echo
    log_info "Processing: $world_name"
    
    case "$backup_type" in
      "Backup as world folders (full directories)")
        backup_world_as_is "$world_id" "$world_name" || log_warn "Failed to backup $world_name"
        ;;
      "Export as .mcworld files")
        backup_world_as_mcworld "$world_id" "$world_name" || log_warn "Failed to export $world_name"
        ;;
    esac
  done
  
  log_ok "All worlds processed!"
  echo
  printf "Press Enter to continue..."
  read -r
}

handler_open_backup_folder() {
  if [[ "$(uname)" == "Darwin" ]]; then
    mkdir -p "$BACKUP_BASE_DIR"
    open "$BACKUP_BASE_DIR"
    log_ok "Opened backup folder in Finder"
  else
    log_info "Backup folder: $BACKUP_BASE_DIR"
  fi
  echo
  printf "Press Enter to continue..."
  read -r
}

# ============================================================
# Main Menu (using bash-ui.sh ui_run_page)
# ============================================================

main_menu() {
  ui_run_page "Minecraft Bedrock Backup Tool" \
    "List Minecraft Worlds - Show all worlds and backup individually::handler_list_worlds" \
    "Backup All Worlds - Backup all worlds at once::handler_backup_all" \
    "Open Backup Folder - Open the backup folder in Finder::handler_open_backup_folder" \
    "Quit - Exit the program::QUIT"
}

# ============================================================
# Main Entry Point
# ============================================================

main() {
  # Check dependencies
  if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
    log_error "adb not found. Install with: brew install android-platform-tools"
    exit 1
  fi
  
  # Check device on startup
  if ! check_device; then
    log_error "Please connect your Android device and try again."
    exit 1
  fi
  
  # Ensure backup directory exists
  mkdir -p "$BACKUP_BASE_DIR"
  
  # Run main menu (ui_run_page handles the loop internally)
  main_menu
  
  log_info "Goodbye!"
}

main "$@"

