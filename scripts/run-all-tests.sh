#!/bin/bash
#
# Run tests for all Omerta submodules
#
# Usage: ./scripts/run-all-tests.sh [--quick]
#   --quick: Skip slow tests (Swift builds)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

QUICK_MODE=false
if [[ "$1" == "--quick" ]]; then
    QUICK_MODE=true
fi

FAILED=()
PASSED=()

run_test() {
    local name="$1"
    local dir="$2"
    local cmd="$3"

    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Testing: $name${NC}"
    echo -e "${YELLOW}========================================${NC}"

    if [[ ! -d "$dir" ]]; then
        echo -e "${RED}Directory not found: $dir${NC}"
        FAILED+=("$name (not found)")
        return
    fi

    cd "$dir"
    if eval "$cmd"; then
        echo -e "${GREEN}✓ $name passed${NC}"
        PASSED+=("$name")
    else
        echo -e "${RED}✗ $name failed${NC}"
        FAILED+=("$name")
    fi
    cd "$ROOT_DIR"
}

echo "Running all Omerta tests..."
echo "Root directory: $ROOT_DIR"

# Python tests (fast)
run_test "omerta_lang" "$ROOT_DIR/omerta_lang" "pytest tests/ -v"
run_test "omerta_protocol" "$ROOT_DIR/omerta_protocol" "PYTHONPATH=$ROOT_DIR/omerta_lang:\$PYTHONPATH pytest simulations/tests/ -v"

# Swift tests (slow)
if [[ "$QUICK_MODE" == false ]]; then
    run_test "omerta_node" "$ROOT_DIR/omerta_node" "swift test"
    run_test "omerta_mesh" "$ROOT_DIR/omerta_mesh" "swift test"
else
    echo ""
    echo -e "${YELLOW}Skipping Swift tests (--quick mode)${NC}"
fi

# Summary
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Test Summary${NC}"
echo -e "${YELLOW}========================================${NC}"

if [[ ${#PASSED[@]} -gt 0 ]]; then
    echo -e "${GREEN}Passed:${NC}"
    for name in "${PASSED[@]}"; do
        echo -e "  ${GREEN}✓${NC} $name"
    done
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo -e "${RED}Failed:${NC}"
    for name in "${FAILED[@]}"; do
        echo -e "  ${RED}✗${NC} $name"
    done
    echo ""
    exit 1
fi

echo ""
echo -e "${GREEN}All tests passed!${NC}"
