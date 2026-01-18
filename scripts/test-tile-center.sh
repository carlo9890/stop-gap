#!/usr/bin/env bash
#
# test-tile-center.sh - Test script for wctl tile and center commands
#
# Tests:
# - All 9 tile positions
# - All 3 center modes (both, horizontal, vertical)
# - Error cases
# - Geometry verification
#

set -euo pipefail

# Colors for output
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    GREEN='\033[32m'
    RED='\033[31m'
    YELLOW='\033[33m'
    RESET='\033[0m'
else
    BOLD=''
    GREEN=''
    RED=''
    YELLOW=''
    RESET=''
fi

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test window ID (global)
TEST_WINDOW_ID=""

# Print test result
pass() {
    echo -e "${GREEN}✓${RESET} $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

fail() {
    echo -e "${RED}✗${RESET} $1"
    if [[ $# -gt 1 ]]; then
        echo -e "  ${RED}Error:${RESET} $2"
    fi
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

skip() {
    echo -e "${YELLOW}⊘${RESET} $1"
    if [[ $# -gt 1 ]]; then
        echo -e "  ${YELLOW}Reason:${RESET} $2"
    fi
    ((TESTS_SKIPPED++))
}

info() {
    echo -e "${BOLD}$1${RESET}"
}

# Check if wctl is available
check_wctl() {
    if ! command -v ./wctl &>/dev/null; then
        echo -e "${RED}Error:${RESET} wctl not found in current directory"
        exit 1
    fi
    
    # Check if extension is running
    if ! ./wctl list &>/dev/null; then
        echo -e "${RED}Error:${RESET} Window Control extension is not running"
        echo "Enable it with: gnome-extensions enable window-control@hko9890"
        exit 1
    fi
    
    # Check if GetWorkarea method is available (required for tile/center commands)
    if ! busctl --user call org.gnome.Shell \
        /org/gnome/Shell/Extensions/WindowControl \
        org.gnome.Shell.Extensions.WindowControl \
        GetWorkarea i 0 &>/dev/null; then
        echo -e "${RED}Error:${RESET} GetWorkarea D-Bus method not available"
        echo ""
        echo "The extension needs to be reloaded for tile/center commands to work."
        echo ""
        echo "On Wayland, you need to log out and log back in, or use nested session:"
        echo "  ./scripts/build.sh install"
        echo "  ./scripts/start-nested.sh"
        echo "  # In nested session: gnome-extensions enable window-control@hko9890"
        echo ""
        echo "On X11, you can restart GNOME Shell with Alt+F2, type 'r', press Enter"
        exit 1
    fi
}

# Get a test window ID (use focused window or any available window)
get_test_window() {
    local json
    json=$(./wctl list --json 2>/dev/null)
    
    if [[ -z "$json" ]] || [[ "$json" == "[]" ]]; then
        echo ""
        return
    fi
    
    # Try to get focused window first
    local focused_id
    focused_id=$(echo "$json" | jq -r '.[] | select(.has_focus == true) | .id // empty' 2>/dev/null)
    
    if [[ -n "$focused_id" ]]; then
        echo "$focused_id"
        return
    fi
    
    # Otherwise get first window
    echo "$json" | jq -r '.[0].id // empty' 2>/dev/null
}

# Get window geometry
get_window_geometry() {
    local id="$1"
    local json
    json=$(./wctl info "$id" --json 2>/dev/null)
    
    if [[ -z "$json" ]]; then
        echo ""
        return
    fi
    
    local x y width height
    x=$(echo "$json" | jq -r '.frame_rect.x')
    y=$(echo "$json" | jq -r '.frame_rect.y')
    width=$(echo "$json" | jq -r '.frame_rect.width')
    height=$(echo "$json" | jq -r '.frame_rect.height')
    
    echo "$x $y $width $height"
}

# Get workarea for a window's monitor
# Note: This tries to use GetWorkarea D-Bus method, but falls back to
# estimating from monitor geometry if the method is not available
# (e.g., if extension hasn't been reloaded after adding the method)
get_workarea() {
    local id="$1"
    local json monitor_index
    json=$(./wctl info "$id" --json 2>/dev/null)
    monitor_index=$(echo "$json" | jq -r '.monitor_index')
    
    # Try to use D-Bus GetWorkarea method
    local raw
    if raw=$(gdbus call --session \
        --dest org.gnome.Shell \
        --object-path /org/gnome/Shell/Extensions/WindowControl \
        --method org.gnome.Shell.Extensions.WindowControl.GetWorkarea \
        "$monitor_index" 2>/dev/null); then
        
        # Parse workarea - format is (x, y, width, height)
        if [[ "$raw" =~ \(([0-9]+),\ ([0-9]+),\ ([0-9]+),\ ([0-9]+)\) ]]; then
            echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
            return
        fi
    fi
    
    # Fallback: estimate workarea from screen resolution
    # This is approximate but good enough for testing when GetWorkarea is unavailable
    # Get screen size from xrandr
    local screen_info
    if command -v xrandr &>/dev/null; then
        screen_info=$(xrandr --current 2>/dev/null | grep -w connected | head -1)
        if [[ "$screen_info" =~ ([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
            local width="${BASH_REMATCH[1]}"
            local height="${BASH_REMATCH[2]}"
            local x="${BASH_REMATCH[3]}"
            local y="${BASH_REMATCH[4]}"
            # Assume some panel space (e.g., 32px top bar)
            echo "$x $((y + 32)) $width $((height - 32))"
            return
        fi
    fi
    
    # Last resort: return empty (tests will be skipped)
    echo ""
}

# Test tile command with a specific position
test_tile_position() {
    local position="$1"
    local start_col="$2"
    local end_col="$3"
    local start_row="$4"
    local end_row="$5"
    
    # Store initial geometry for comparison
    local init_x init_y init_w init_h
    read init_x init_y init_w init_h <<< "$(get_window_geometry "$TEST_WINDOW_ID")"
    
    # Run tile command
    local output
    if ! output=$(./wctl tile "$TEST_WINDOW_ID" "$position" 2>&1); then
        fail "Tile to $position" "Command failed: $output"
        return
    fi
    
    # Give the window manager a moment to apply the changes
    sleep 0.2
    
    # Get new window geometry
    local win_x win_y win_w win_h
    read win_x win_y win_w win_h <<< "$(get_window_geometry "$TEST_WINDOW_ID")"
    
    # Basic sanity check: geometry should have changed
    if [[ "$win_x" == "$init_x" && "$win_y" == "$init_y" && \
          "$win_w" == "$init_w" && "$win_h" == "$init_h" ]]; then
        fail "Tile to $position" "Window geometry did not change"
        return
    fi
    
    # Try to get workarea for detailed verification
    local wa_x wa_y wa_w wa_h
    read wa_x wa_y wa_w wa_h <<< "$(get_workarea "$TEST_WINDOW_ID")"
    
    if [[ -n "$wa_x" && -n "$wa_w" ]]; then
        # We have workarea info - do detailed verification
        local cell_w=$((wa_w / 4))
        local cell_h=$((wa_h / 2))
        
        local exp_x=$((wa_x + cell_w * start_col))
        local exp_y=$((wa_y + cell_h * start_row))
        local exp_w=$((cell_w * (end_col - start_col + 1)))
        local exp_h=$((cell_h * (end_row - start_row + 1)))
        
        # Verify geometry (allow some tolerance for window manager rounding/decorations)
        local tolerance=10
        
        if [[ $((win_x - exp_x)) -lt -$tolerance || $((win_x - exp_x)) -gt $tolerance ]] || \
           [[ $((win_y - exp_y)) -lt -$tolerance || $((win_y - exp_y)) -gt $tolerance ]] || \
           [[ $((win_w - exp_w)) -lt -$tolerance || $((win_w - exp_w)) -gt $tolerance ]] || \
           [[ $((win_h - exp_h)) -lt -$tolerance || $((win_h - exp_h)) -gt $tolerance ]]; then
            fail "Tile to $position" "Geometry mismatch: expected ${exp_x},${exp_y} ${exp_w}x${exp_h}, got ${win_x},${win_y} ${win_w}x${win_h}"
            return
        fi
    fi
    
    pass "Tile to $position"
}

# Test center command with a specific mode
test_center_mode() {
    local mode="$1"
    local axis="$2"  # "horizontal", "vertical", or "both"
    
    # First, move window to a non-centered position
    ./wctl move "$TEST_WINDOW_ID" 100 100 &>/dev/null
    sleep 0.2
    
    # Get initial geometry
    local init_x init_y init_w init_h
    read init_x init_y init_w init_h <<< "$(get_window_geometry "$TEST_WINDOW_ID")"
    
    # Run center command
    local output
    if ! output=$(./wctl center "$TEST_WINDOW_ID" "$mode" 2>&1); then
        fail "Center with mode '$mode'" "Command failed: $output"
        return
    fi
    
    # Give the window manager a moment to apply the changes
    sleep 0.2
    
    # Get new window geometry
    local win_x win_y win_w win_h
    read win_x win_y win_w win_h <<< "$(get_window_geometry "$TEST_WINDOW_ID")"
    
    # Basic sanity check based on axis
    case "$axis" in
        horizontal)
            if [[ "$win_x" == "$init_x" ]]; then
                fail "Center with mode '$mode'" "X position did not change"
                return
            fi
            ;;
        vertical)
            if [[ "$win_y" == "$init_y" ]]; then
                fail "Center with mode '$mode'" "Y position did not change"
                return
            fi
            ;;
        both)
            if [[ "$win_x" == "$init_x" && "$win_y" == "$init_y" ]]; then
                fail "Center with mode '$mode'" "Position did not change"
                return
            fi
            ;;
    esac
    
    # Try to get workarea for detailed verification
    local wa_x wa_y wa_w wa_h
    read wa_x wa_y wa_w wa_h <<< "$(get_workarea "$TEST_WINDOW_ID")"
    
    if [[ -n "$wa_x" && -n "$wa_w" ]]; then
        # We have workarea info - do detailed verification
        local exp_x=$((wa_x + (wa_w - win_w) / 2))
        local exp_y=$((wa_y + (wa_h - win_h) / 2))
        
        local tolerance=10
        local check_x=false
        local check_y=false
        
        case "$axis" in
            horizontal)
                check_x=true
                ;;
            vertical)
                check_y=true
                ;;
            both)
                check_x=true
                check_y=true
                ;;
        esac
        
        local failed=false
        
        if [[ "$check_x" == true ]]; then
            if [[ $((win_x - exp_x)) -lt -$tolerance || $((win_x - exp_x)) -gt $tolerance ]]; then
                fail "Center with mode '$mode'" "X position mismatch: expected ${exp_x}, got ${win_x}"
                failed=true
            fi
        fi
        
        if [[ "$check_y" == true ]] && [[ "$failed" == false ]]; then
            if [[ $((win_y - exp_y)) -lt -$tolerance || $((win_y - exp_y)) -gt $tolerance ]]; then
                fail "Center with mode '$mode'" "Y position mismatch: expected ${exp_y}, got ${win_y}"
                failed=true
            fi
        fi
        
        if [[ "$failed" == true ]]; then
            return
        fi
    fi
    
    pass "Center with mode '$mode'"
}

# Test error cases for tile command
test_tile_errors() {
    info ""
    info "Testing tile error cases..."
    
    # Missing arguments
    if ./wctl tile &>/dev/null; then
        fail "Tile with no args should error" "Command succeeded unexpectedly"
    else
        pass "Tile with no args returns error"
    fi
    
    # Missing position
    if ./wctl tile "$TEST_WINDOW_ID" &>/dev/null; then
        fail "Tile with missing position should error" "Command succeeded unexpectedly"
    else
        pass "Tile with missing position returns error"
    fi
    
    # Invalid position
    if ./wctl tile "$TEST_WINDOW_ID" invalid-position &>/dev/null; then
        fail "Tile with invalid position should error" "Command succeeded unexpectedly"
    else
        pass "Tile with invalid position returns error"
    fi
    
    # Invalid window ID
    if ./wctl tile 99999999 center &>/dev/null; then
        fail "Tile with invalid window ID should error" "Command succeeded unexpectedly"
    else
        pass "Tile with invalid window ID returns error"
    fi
    
    # Non-numeric window ID
    if ./wctl tile abc center &>/dev/null; then
        fail "Tile with non-numeric ID should error" "Command succeeded unexpectedly"
    else
        pass "Tile with non-numeric ID returns error"
    fi
}

# Test error cases for center command
test_center_errors() {
    info ""
    info "Testing center error cases..."
    
    # Missing window ID
    if ./wctl center &>/dev/null; then
        fail "Center with no args should error" "Command succeeded unexpectedly"
    else
        pass "Center with no args returns error"
    fi
    
    # Invalid mode
    if ./wctl center "$TEST_WINDOW_ID" invalid-mode &>/dev/null; then
        fail "Center with invalid mode should error" "Command succeeded unexpectedly"
    else
        pass "Center with invalid mode returns error"
    fi
    
    # Invalid window ID
    if ./wctl center 99999999 &>/dev/null; then
        fail "Center with invalid window ID should error" "Command succeeded unexpectedly"
    else
        pass "Center with invalid window ID returns error"
    fi
    
    # Non-numeric window ID
    if ./wctl center abc &>/dev/null; then
        fail "Center with non-numeric ID should error" "Command succeeded unexpectedly"
    else
        pass "Center with non-numeric ID returns error"
    fi
}

# Run all tests
run_tests() {
    info "=========================================="
    info "wctl tile and center command tests"
    info "=========================================="
    info ""
    
    # Check prerequisites
    check_wctl
    
    # Get test window
    TEST_WINDOW_ID=$(get_test_window)
    
    if [[ -z "$TEST_WINDOW_ID" ]]; then
        echo -e "${RED}Error:${RESET} No windows available for testing"
        echo "Please open at least one window and try again"
        exit 1
    fi
    
    info "Using test window ID: $TEST_WINDOW_ID"
    
    # Get window title for reference
    local title
    title=$(./wctl info "$TEST_WINDOW_ID" --json | jq -r '.title')
    info "Window title: $title"
    info ""
    
    # Test all tile positions
    info "Testing tile positions..."
    test_tile_position "top-left" 0 0 0 0
    test_tile_position "top-center" 1 2 0 0
    test_tile_position "top-right" 3 3 0 0
    test_tile_position "left" 0 0 0 1
    test_tile_position "center" 1 2 0 1
    test_tile_position "right" 3 3 0 1
    test_tile_position "bottom-left" 0 0 1 1
    test_tile_position "bottom-center" 1 2 1 1
    test_tile_position "bottom-right" 3 3 1 1
    
    # Test center modes
    info ""
    info "Testing center modes..."
    test_center_mode "both" "both"
    test_center_mode "horizontal" "horizontal"
    test_center_mode "vertical" "vertical"
    test_center_mode "h" "horizontal"  # short form
    test_center_mode "v" "vertical"    # short form
    
    # Test default mode (no argument)
    ./wctl move "$TEST_WINDOW_ID" 100 100 &>/dev/null
    sleep 0.2
    if ./wctl center "$TEST_WINDOW_ID" &>/dev/null; then
        pass "Center with default mode (both)"
    else
        fail "Center with default mode (both)"
    fi
    
    # Test error cases
    test_tile_errors
    test_center_errors
    
    # Summary
    info ""
    info "=========================================="
    info "Test Summary"
    info "=========================================="
    echo -e "Total:   $TESTS_RUN"
    echo -e "${GREEN}Passed:  $TESTS_PASSED${RESET}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed:  $TESTS_FAILED${RESET}"
    else
        echo -e "Failed:  $TESTS_FAILED"
    fi
    if [[ $TESTS_SKIPPED -gt 0 ]]; then
        echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${RESET}"
    fi
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

# Main entry point
run_tests
