# Test Script for Tile and Center Commands

## Overview

`test-tile-center.sh` - Comprehensive test script for `wctl tile` and `wctl center` commands.

## Prerequisites

Before running the tests, ensure the Window Control extension is properly loaded with the `GetWorkarea` method:

### On Wayland (Current Session)

The extension needs GNOME Shell to be restarted to load new JavaScript code:

1. Install the latest extension:
   ```bash
   ./scripts/build.sh install
   ```

2. Log out and log back in

3. Enable the extension (if not already enabled):
   ```bash
   gnome-extensions enable window-control@hko9890
   ```

### Using Nested Session (Recommended for Testing)

Use a nested GNOME Shell session to test without logging out:

1. Install the extension:
   ```bash
   ./scripts/build.sh install
   ```

2. Start nested session:
   ```bash
   ./scripts/start-nested.sh
   ```

3. In another terminal, set environment variables for the nested session:
   ```bash
   export WAYLAND_DISPLAY=wayland-1  # Check output from start-nested.sh
   export DISPLAY=:99
   ```

4. Enable the extension in the nested session:
   ```bash
   gnome-extensions enable window-control@hko9890
   ```

5. Open a test window in the nested session:
   ```bash
   gedit &
   ```

6. Run the tests:
   ```bash
   ./scripts/test-tile-center.sh
   ```

### On X11

Restart GNOME Shell without logging out:

1. Install the extension:
   ```bash
   ./scripts/build.sh install
   ```

2. Press `Alt+F2`, type `r`, press Enter

3. Run the tests:
   ```bash
   ./scripts/test-tile-center.sh
   ```

## Running the Tests

Simply execute the script:

```bash
./scripts/test-tile-center.sh
```

The script will:
- Check that `wctl` and the extension are available
- Verify that the `GetWorkarea` method is accessible
- Open a test window (or use an existing one)
- Test all 9 tile positions
- Test all center modes (both, horizontal, vertical)
- Test short forms (h, v)
- Test error cases (missing args, invalid positions, etc.)
- Verify geometry changes

## Test Coverage

### Tile Positions (9 total)
- `top-left` - Top-left quarter
- `top-center` - Top-center half
- `top-right` - Top-right quarter
- `left` - Left half (full height)
- `center` - Center half (full height)
- `right` - Right half (full height)
- `bottom-left` - Bottom-left quarter
- `bottom-center` - Bottom-center half
- `bottom-right` - Bottom-right quarter

### Center Modes (6 total)
- `both` - Center on both axes (default)
- `horizontal` - Center horizontally only
- `vertical` - Center vertically only
- `h` - Short form for horizontal
- `v` - Short form for vertical
- (no argument) - Defaults to both

### Error Cases (9 total)
- Tile with no arguments
- Tile with missing position
- Tile with invalid position
- Tile with invalid window ID
- Tile with non-numeric ID
- Center with no arguments
- Center with invalid mode
- Center with invalid window ID
- Center with non-numeric ID

## Expected Output

```
==========================================
wctl tile and center command tests
==========================================

Using test window ID: 123456789
Window title: gedit

Testing tile positions...
✓ Tile to top-left
✓ Tile to top-center
✓ Tile to top-right
✓ Tile to left
✓ Tile to center
✓ Tile to right
✓ Tile to bottom-left
✓ Tile to bottom-center
✓ Tile to bottom-right

Testing center modes...
✓ Center with mode 'both'
✓ Center with mode 'horizontal'
✓ Center with mode 'vertical'
✓ Center with mode 'h'
✓ Center with mode 'v'
✓ Center with default mode (both)

Testing tile error cases...
✓ Tile with no args returns error
✓ Tile with missing position returns error
✓ Tile with invalid position returns error
✓ Tile with invalid window ID returns error
✓ Tile with non-numeric ID returns error

Testing center error cases...
✓ Center with no args returns error
✓ Center with invalid mode returns error
✓ Center with invalid window ID returns error
✓ Center with non-numeric ID returns error

==========================================
Test Summary
==========================================
Total:   24
Passed:  24
Failed:  0
```

## Troubleshooting

### Error: "wctl not found in current directory"

Run the script from the project root directory:

```bash
cd /path/to/gnome-window-control
./scripts/test-tile-center.sh
```

### Error: "Window Control extension is not running"

Enable the extension:

```bash
gnome-extensions enable window-control@hko9890
```

### Error: "GetWorkarea D-Bus method not available"

The extension hasn't been reloaded with the new code. See Prerequisites section above for how to reload it properly.

### Error: "No windows available for testing"

Open at least one window before running the tests:

```bash
gedit &  # or any other application
./scripts/test-tile-center.sh
```

## Manual Testing

If automated tests can't run, you can manually test the commands:

```bash
# Get a window ID
ID=$(./wctl list --json | jq -r '.[0].id')

# Test tile positions
./wctl tile $ID top-left
./wctl tile $ID center
./wctl tile $ID bottom-right

# Test center modes
./wctl center $ID both
./wctl center $ID horizontal
./wctl center $ID vertical

# Test error cases
./wctl tile  # Should error: missing arguments
./wctl tile $ID invalid  # Should error: invalid position
./wctl center 99999999  # Should error: window not found
```
