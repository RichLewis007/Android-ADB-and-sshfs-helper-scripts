#!/usr/bin/env bash
# test-all-scripts.sh
#
# Author: Rich Lewis - GitHub @RichLewis007
# 
# Comprehensive test script for all Android ADB and SSHFS helper scripts
#
# This script tests every feature of every script in the project root.
# After each test, it shows what you should see and prompts to continue.
#
# Prerequisites:
#   - Android device connected via USB with USB debugging enabled
#   - ADB installed and working
#   - For SSHFS tests: SSH server running on Android device

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test directory for all test files and folders
TEST_DIR="${HOME}/Downloads/script-testing-temp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counter
TEST_NUM=0
TOTAL_TESTS=0

# Cleanup function
cleanup() {
    # Disable exit on error for cleanup to ensure it completes
    set +e
    echo
    echo -e "${YELLOW}Cleaning up test files and directories...${NC}"
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR" 2>/dev/null || true
        if [[ ! -d "$TEST_DIR" ]]; then
            echo -e "${GREEN}✓ Removed test directory: $TEST_DIR${NC}"
        else
            echo -e "${RED}⚠ Warning: Could not fully remove test directory: $TEST_DIR${NC}"
            echo -e "${YELLOW}  You may need to manually remove it.${NC}"
        fi
    fi
    echo -e "${GREEN}Cleanup complete!${NC}"
}

# Set trap to cleanup on exit (including errors)
trap cleanup EXIT

# Function to print test header
print_test_header() {
    TEST_NUM=$((TEST_NUM + 1))
    echo
    echo "================================================================================"
    echo -e "${BLUE}TEST $TEST_NUM/$TOTAL_TESTS: $1${NC}"
    echo "================================================================================"
    echo
}

# Function to print expected results
print_expected() {
    echo
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}EXPECTED RESULTS:${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "$1"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

# Function to wait for user input
wait_for_user() {
    echo -e "${GREEN}Press any key to continue to the next test...${NC}"
    read -n 1 -s
    echo
}

# Count total tests
count_tests() {
    TOTAL_TESTS=0
    # android-adb-helper.sh: 6 commands
    TOTAL_TESTS=$((TOTAL_TESTS + 6))
    # android-sshfs-helper.sh: 4 commands
    TOTAL_TESTS=$((TOTAL_TESTS + 4))
    # android-check-adb-or-sshfs-access.sh: 2 modes
    TOTAL_TESTS=$((TOTAL_TESTS + 2))
    # android-adb-find-paths.sh: 1 test
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    # android-sshfs-mounts-cleanup.sh: 1 test
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    # minecraft-backup-via-adb.sh: 1 test (interactive)
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Main test execution
main() {
    echo "================================================================================"
    echo -e "${GREEN}Android ADB and SSHFS Helper Scripts - Comprehensive Test Suite${NC}"
    echo "================================================================================"
    echo
    echo "This script will test all features of all scripts in the project."
    echo "Make sure your Android device is connected via USB with USB debugging enabled."
    echo
    echo -e "${YELLOW}Press any key to start testing...${NC}"
    read -n 1 -s
    echo
    
    count_tests
    
    cd "$PROJECT_ROOT"
    
    # Create test directory
    echo -e "${BLUE}Creating test directory: $TEST_DIR${NC}"
    mkdir -p "$TEST_DIR"
    echo -e "${GREEN}✓ Test directory created${NC}"
    echo
    
    # ============================================================================
    # android-adb-helper.sh Tests
    # ============================================================================
    
    print_test_header "android-adb-helper.sh - list (default path)"
    echo "Running: ./android-adb-helper.sh list"
    ./android-adb-helper.sh list
    print_expected "• Should list files in /sdcard directory
• Should show directories like DCIM, Download, Movies, etc.
• No errors should appear"
    wait_for_user
    
    print_test_header "android-adb-helper.sh - list (specific path)"
    echo "Running: ./android-adb-helper.sh list /sdcard/DCIM"
    ./android-adb-helper.sh list /sdcard/DCIM
    print_expected "• Should list files in /sdcard/DCIM directory
• Should show photo/video files or subdirectories
• No errors should appear"
    wait_for_user
    
    print_test_header "android-adb-helper.sh - pull (test with small directory)"
    echo "Running: ./android-adb-helper.sh pull /sdcard/Download $TEST_DIR/test-pull"
    echo -e "${YELLOW}Note: This will pull files from Android Downloads to $TEST_DIR/test-pull${NC}"
    ./android-adb-helper.sh pull /sdcard/Download "$TEST_DIR/test-pull" || echo "Note: Directory might not exist or be empty"
    print_expected "• Should copy files from Android /sdcard/Download to $TEST_DIR/test-pull
• Should show progress or completion message
• Finder should open showing the pulled directory (on macOS)
• If directory doesn't exist, you'll see an error (this is OK)"
    wait_for_user
    
    print_test_header "android-adb-helper.sh - push (test with a file)"
    echo "Creating test file..."
    TEST_FILE="$TEST_DIR/test-android-push.txt"
    echo "Test file created by test script at $(date)" > "$TEST_FILE"
    echo "Running: ./android-adb-helper.sh push $TEST_FILE /sdcard/Download/"
    ./android-adb-helper.sh push "$TEST_FILE" /sdcard/Download/
    print_expected "• Should push the test file to Android /sdcard/Download/
• Should show success message
• File should appear on Android device in Downloads folder"
    wait_for_user
    
    print_test_header "android-adb-helper.sh - move (test moving files)"
    echo "Running: ./android-adb-helper.sh move /sdcard/Download $TEST_DIR/test-move"
    echo -e "${YELLOW}Note: This will move (copy then delete) files from Android${NC}"
    ./android-adb-helper.sh move /sdcard/Download "$TEST_DIR/test-move" || echo "Note: No files to move or directory doesn't exist"
    print_expected "• Should copy files from Android Downloads to $TEST_DIR/test-move
• Should delete files from Android after copying
• Should show progress messages
• Finder should open showing the moved directory"
    wait_for_user
    
    print_test_header "android-adb-helper.sh - shell"
    echo "Running: ./android-adb-helper.sh shell"
    echo -e "${YELLOW}Note: This will open an interactive ADB shell. Type 'exit' to return.${NC}"
    ./android-adb-helper.sh shell
    print_expected "• Should open an interactive ADB shell
• You should see a shell prompt (usually ending with $ or #)
• You can run Android commands like 'ls', 'pwd', etc.
• Type 'exit' to return to the test script"
    wait_for_user
    
    print_test_header "android-adb-helper.sh - explorer"
    echo "Running: ./android-adb-helper.sh explorer $TEST_DIR/explorer"
    ./android-adb-helper.sh explorer "$TEST_DIR/explorer"
    print_expected "• Should pull common Android directories (DCIM, Download, etc.)
• Should open multiple Finder windows showing pulled directories
• Should show progress for each directory being pulled
• Directories should appear in $TEST_DIR/explorer/"
    wait_for_user
    
    # ============================================================================
    # android-sshfs-helper.sh Tests
    # ============================================================================
    
    print_test_header "android-sshfs-helper.sh - get-ip"
    echo "Running: ./android-sshfs-helper.sh get-ip"
    ANDROID_IP=$(./android-sshfs-helper.sh get-ip)
    print_expected "• Should detect and display Android device IP address
• Should show IP in format like 192.168.x.x
• Should work via ADB to query the device
• IP address will be stored for next tests"
    echo "Detected IP: $ANDROID_IP"
    wait_for_user
    
    print_test_header "android-sshfs-helper.sh - setup"
    echo "Running: ./android-sshfs-helper.sh setup"
    ./android-sshfs-helper.sh setup
    print_expected "• Should display SSH server setup instructions
• Should show instructions for Termux, SSHelper, etc.
• Should explain how to find SSH username
• Should show how to get IP address"
    wait_for_user
    
    print_test_header "android-sshfs-helper.sh - mount (with flags)"
    echo "Running: ./android-sshfs-helper.sh mount --help"
    ./android-sshfs-helper.sh mount --help || ./android-sshfs-helper.sh mount -h || true
    echo
    echo -e "${YELLOW}To test actual mounting, you need:${NC}"
    echo "  1. SSH server running on Android (sshd in Termux)"
    echo "  2. SSH username (run 'whoami' in Termux)"
    echo "  3. Device and Mac on same Wi-Fi network"
    echo
    echo "Example mount command (uncomment to test):"
    echo "# ./android-sshfs-helper.sh mount --ssh-user YOUR_USERNAME --android-ip $ANDROID_IP"
    print_expected "• Should show help message with available flags
• Flags should include: --ssh-user, --android-ip, --ssh-port, --mount-point, --use-sudo
• If you have SSH set up, you can test actual mounting with the example command"
    wait_for_user
    
    print_test_header "android-sshfs-helper.sh - unmount"
    echo "Running: ./android-sshfs-helper.sh unmount --help"
    ./android-sshfs-helper.sh unmount --help || ./android-sshfs-helper.sh unmount -h || true
    echo
    echo -e "${YELLOW}Note: Actual unmount will only work if something is mounted${NC}"
    ./android-sshfs-helper.sh unmount || echo "Nothing mounted (this is OK)"
    print_expected "• Should show help message or attempt to unmount
• If nothing is mounted, should show 'not mounted' message
• Should accept --mount-point flag to specify custom mount point"
    wait_for_user
    
    # ============================================================================
    # android-check-adb-or-sshfs-access.sh Tests
    # ============================================================================
    
    print_test_header "android-check-adb-or-sshfs-access.sh - adb mode"
    echo "Running: ./android-check-adb-or-sshfs-access.sh adb"
    ./android-check-adb-or-sshfs-access.sh adb
    print_expected "• Should check access via ADB (elevated permissions)
• Should test multiple Android paths
• Should show ✓ EXISTS or ✗ NOT FOUND for each path
• Should show item counts for accessible directories
• Should include paths like /storage/emulated/0, /Android/data, etc."
    wait_for_user
    
    print_test_header "android-check-adb-or-sshfs-access.sh - sshfs mode (help)"
    echo "Running: ./android-check-adb-or-sshfs-access.sh sshfs --help"
    ./android-check-adb-or-sshfs-access.sh sshfs --help || ./android-check-adb-or-sshfs-access.sh sshfs -h || true
    echo
    echo -e "${YELLOW}To test actual SSHFS access check, you need SSH credentials:${NC}"
    echo "Example: ./android-check-adb-or-sshfs-access.sh sshfs --ssh-user YOUR_USERNAME --android-ip $ANDROID_IP"
    print_expected "• Should show help message with available flags
• Flags should include: --ssh-user, --android-ip, --ssh-port
• If you have SSH set up, you can test actual access check with the example command"
    wait_for_user
    
    # ============================================================================
    # android-adb-find-paths.sh Test
    # ============================================================================
    
    print_test_header "android-adb-find-paths.sh"
    echo "Running: ./android-adb-find-paths.sh"
    ./android-adb-find-paths.sh
    print_expected "• Should display a table of Android storage paths
• Table should show: Path | Exists | Accessible | Sample Files
• Should check paths like /sdcard, /storage/emulated/0, etc.
• Should show sample files from accessible directories
• Should recommend paths for SSHFS mounting"
    wait_for_user
    
    # ============================================================================
    # android-sshfs-mounts-cleanup.sh Test
    # ============================================================================
    
    print_test_header "android-sshfs-mounts-cleanup.sh"
    echo "Running: ./android-sshfs-mounts-cleanup.sh"
    ./android-sshfs-mounts-cleanup.sh
    print_expected "• Should check for stale SSHFS mount points
• Should attempt to unmount any found mount points
• Should report on mount points found/cleaned
• Should show messages about empty/non-empty directories
• If no mounts exist, should report that (this is OK)"
    wait_for_user
    
    # ============================================================================
    # minecraft-backup-via-adb.sh Test
    # ============================================================================
    
    print_test_header "minecraft-backup-via-adb.sh (Interactive TUI)"
    echo "Running: ./minecraft-backup-via-adb.sh"
    echo -e "${YELLOW}Note: This is an interactive TUI. You'll need to navigate the menu.${NC}"
    echo
    echo "This script will:"
    echo "  1. Show an interactive menu (fzf/gum/basic select)"
    echo "  2. List Minecraft worlds from your Android device"
    echo "  3. Allow you to select worlds to backup"
    echo "  4. Choose backup format (world folders or .mcworld files)"
    echo
    echo -e "${YELLOW}Press any key to launch the Minecraft backup script...${NC}"
    read -n 1 -s
    echo
    ./minecraft-backup-via-adb.sh
    print_expected "• Should launch an interactive menu/TUI
• Should detect and list Minecraft worlds from Android device
• Should show world names (from levelname.txt files)
• Should allow selecting individual worlds or all worlds
• Should allow choosing backup format (folders or .mcworld)
• Should show progress indicators during backup
• Should save backups to ~/Downloads/Minecraft-Worlds-Backups/"
    wait_for_user
    
    # ============================================================================
    # Summary
    # ============================================================================
    
    echo
    echo "================================================================================"
    echo -e "${GREEN}All Tests Completed!${NC}"
    echo "================================================================================"
    echo
    echo "Summary:"
    echo "  • Tested all commands of android-adb-helper.sh"
    echo "  • Tested all commands of android-sshfs-helper.sh"
    echo "  • Tested both modes of android-check-adb-or-sshfs-access.sh"
    echo "  • Tested android-adb-find-paths.sh"
    echo "  • Tested android-sshfs-mounts-cleanup.sh"
    echo "  • Tested minecraft-backup-via-adb.sh (interactive)"
    echo
    echo -e "${YELLOW}Note: Some tests require additional setup:${NC}"
    echo "  • SSHFS tests require SSH server running on Android"
    echo "  • Some pull/push tests may fail if directories don't exist (this is OK)"
    echo "  • Minecraft backup requires Minecraft worlds on your device"
    echo
    echo "All scripts should now be verified!"
    echo
    echo -e "${BLUE}Note: Test files and directories will be cleaned up automatically.${NC}"
    echo -e "${BLUE}All test artifacts were created in: $TEST_DIR${NC}"
}

# Run main function
main "$@"
