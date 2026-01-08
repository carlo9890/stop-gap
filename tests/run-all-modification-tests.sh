#!/usr/bin/env bash
#
# run-all-modification-tests.sh - Runner for modification tests
#
# Runs all state-modifying command tests
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
if [[ -t 1 ]]; then
    GREEN='\033[32m'
    RED='\033[31m'
    YELLOW='\033[33m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    BOLD=''
    RESET=''
fi

echo -e "${BOLD}========================================"
echo "Running wctl Modification Tests"
echo -e "========================================${RESET}"
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# Run modification tests
echo -e "${BOLD}>> Running: test-modifications.sh${RESET}"
if "$SCRIPT_DIR/test-modifications.sh"; then
    echo -e "${GREEN}SUITE PASSED${RESET}: test-modifications.sh"
else
    echo -e "${RED}SUITE FAILED${RESET}: test-modifications.sh"
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

echo ""
echo -e "${BOLD}========================================"
echo "All Modification Tests Complete"
echo -e "========================================${RESET}"

if [[ $TOTAL_FAILED -gt 0 ]]; then
    echo -e "${RED}Some test suites failed${RESET}"
    exit 1
else
    echo -e "${GREEN}All test suites passed${RESET}"
    exit 0
fi
