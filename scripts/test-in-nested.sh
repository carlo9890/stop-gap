#!/usr/bin/env bash
#
# Test extension inside a nested GNOME Shell session
# Starts nested session, runs tests, captures output, exits
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXTENSION_UUID="window-control@hko9890"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Create a test script that will run inside the nested session
TEST_SCRIPT=$(mktemp)
cat > "$TEST_SCRIPT" << 'INNEREOF'
#!/usr/bin/env bash
sleep 5  # Wait for GNOME Shell to fully start

echo ""
echo "=========================================="
echo "Testing Window Control Extension"
echo "=========================================="
echo ""

# Test GetFocused
echo "=== Test 1: GetFocused() ==="
gdbus call --session --dest org.gnome.Shell \
  --object-path /org/gnome/Shell/Extensions/WindowControl \
  --method org.gnome.Shell.Extensions.WindowControl.GetFocused 2>&1
echo ""

# Test List
echo "=== Test 2: List() ==="
gdbus call --session --dest org.gnome.Shell \
  --object-path /org/gnome/Shell/Extensions/WindowControl \
  --method org.gnome.Shell.Extensions.WindowControl.List 2>&1
echo ""

# Test ListDetailed
echo "=== Test 3: ListDetailed() ==="
RESULT=$(gdbus call --session --dest org.gnome.Shell \
  --object-path /org/gnome/Shell/Extensions/WindowControl \
  --method org.gnome.Shell.Extensions.WindowControl.ListDetailed 2>&1)
echo "$RESULT" | head -c 500
echo ""
echo ""

echo "=========================================="
echo "Tests complete - closing nested session"
echo "=========================================="

# Kill the nested gnome-shell
sleep 2
pkill -f "gnome-shell --nested" || true
INNEREOF
chmod +x "$TEST_SCRIPT"

log_info "Starting nested GNOME Shell session with automated tests..."
log_info "Tests will run automatically and session will close when done."
echo ""

# Determine GNOME version for correct flag
gnome_version=$(gnome-shell --version | awk '{print int($3)}')

if [[ "$gnome_version" -ge 49 ]]; then
    NESTED_FLAG="--devkit"
else
    NESTED_FLAG="--nested"
fi

# Start nested session with test script running inside
# The test script runs via a bash process that we launch after a delay
(
    sleep 3
    # Run tests in the nested session's D-Bus context
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" "$TEST_SCRIPT"
) &
TEST_PID=$!

# Run nested session (this blocks until session closes)
dbus-run-session bash -c "
    gnome-shell $NESTED_FLAG --wayland &
    SHELL_PID=\$!
    
    # Wait a bit then run tests
    sleep 6
    
    echo ''
    echo '=========================================='
    echo 'Testing Window Control Extension'
    echo '=========================================='
    echo ''
    
    # Test GetFocused
    echo '=== Test 1: GetFocused() ==='
    gdbus call --session --dest org.gnome.Shell \
      --object-path /org/gnome/Shell/Extensions/WindowControl \
      --method org.gnome.Shell.Extensions.WindowControl.GetFocused 2>&1
    echo ''
    
    # Test List
    echo '=== Test 2: List() ==='
    gdbus call --session --dest org.gnome.Shell \
      --object-path /org/gnome/Shell/Extensions/WindowControl \
      --method org.gnome.Shell.Extensions.WindowControl.List 2>&1
    echo ''
    
    # Test ListDetailed
    echo '=== Test 3: ListDetailed() ==='
    gdbus call --session --dest org.gnome.Shell \
      --object-path /org/gnome/Shell/Extensions/WindowControl \
      --method org.gnome.Shell.Extensions.WindowControl.ListDetailed 2>&1 | head -c 1000
    echo ''
    echo ''
    
    echo '=========================================='
    echo 'Tests complete'
    echo '=========================================='
    
    # Close the nested session
    sleep 1
    kill \$SHELL_PID 2>/dev/null || true
"

# Cleanup
kill $TEST_PID 2>/dev/null || true
rm -f "$TEST_SCRIPT"

log_info "Nested test session finished."
