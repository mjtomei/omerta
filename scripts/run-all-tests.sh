#!/bin/bash
#
# Run tests for all Omerta submodules
#
# Usage: ./scripts/run-all-tests.sh [--quick] [--no-venv]
#   --quick:   Skip slow tests (Swift builds)
#   --no-venv: Skip Python venv setup (use existing environment)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$ROOT_DIR/.venv"

# Auto-setup git hooks if not configured
setup_git_hooks() {
    local dir="$1"
    if [[ -d "$dir/.githooks" ]]; then
        local current_hooks_path=$(cd "$dir" && git config --local core.hooksPath 2>/dev/null || echo "")
        if [[ "$current_hooks_path" != ".githooks" ]]; then
            echo "Configuring git hooks for $(basename "$dir")..."
            (cd "$dir" && git config --local core.hooksPath .githooks)
        fi
    fi
}

# Setup hooks for main repo and all submodules
setup_git_hooks "$ROOT_DIR"
for submodule in omerta_lang omerta_mesh omerta_node omerta_protocol; do
    setup_git_hooks "$ROOT_DIR/$submodule"
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

QUICK_MODE=false
SETUP_VENV=true

for arg in "$@"; do
    case $arg in
        --quick)
            QUICK_MODE=true
            ;;
        --no-venv)
            SETUP_VENV=false
            ;;
    esac
done

FAILED=()
PASSED=()

# Setup Python virtual environment
setup_python_env() {
    if [[ "$SETUP_VENV" == false ]]; then
        echo -e "${YELLOW}Skipping venv setup (--no-venv)${NC}"
        return
    fi

    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Setting up Python environment${NC}"
    echo -e "${YELLOW}========================================${NC}"

    # Create venv if it doesn't exist
    if [[ ! -d "$VENV_DIR" ]]; then
        echo "Creating virtual environment at $VENV_DIR..."
        python3 -m venv "$VENV_DIR"
    fi

    # Activate venv
    source "$VENV_DIR/bin/activate"

    # Upgrade pip
    pip install --quiet --upgrade pip

    # Install omerta_lang (editable install)
    echo "Installing omerta_lang..."
    pip install --quiet -e "$ROOT_DIR/omerta_lang"

    # Install omerta_protocol dependencies
    echo "Installing omerta_protocol dependencies..."
    pip install --quiet -r "$ROOT_DIR/omerta_protocol/requirements.txt"

    # Install pytest
    pip install --quiet pytest

    echo -e "${GREEN}Python environment ready${NC}"
}

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

# Setup Python environment first
setup_python_env

# Activate venv for tests if we set it up
if [[ "$SETUP_VENV" == true && -d "$VENV_DIR" ]]; then
    source "$VENV_DIR/bin/activate"
fi

# Python tests (fast)
run_test "omerta_lang" "$ROOT_DIR/omerta_lang" "pytest tests/ -v"
run_test "omerta_protocol" "$ROOT_DIR/omerta_protocol" "pytest simulations/tests/ -v"

# Swift tests (slow)
if [[ "$QUICK_MODE" == false ]]; then
    # Check if swift is available
    if command -v swift &> /dev/null; then
        run_test "omerta_node" "$ROOT_DIR/omerta_node" "swift test"
        run_test "omerta_mesh" "$ROOT_DIR/omerta_mesh" "swift test"
    else
        echo ""
        echo -e "${YELLOW}Swift not found, skipping Swift tests${NC}"
        echo -e "${YELLOW}To install Swift:${NC}"
        if [[ "$(uname)" == "Darwin" ]]; then
            echo "  macOS: Swift is not installed by default. Install via one of:"
            echo "         1. Install Xcode from the App Store (recommended)"
            echo "            - Open Xcode after install to accept the license"
            echo "            - Or run: sudo xcodebuild -license accept"
            echo "         2. Install Command Line Tools only:"
            echo "            xcode-select --install"
            echo "         3. Install via Homebrew:"
            echo "            brew install swift"
        elif [[ -f /etc/debian_version ]]; then
            echo "  Debian/Ubuntu: See https://swift.org/download/"
            echo "         Or use swiftly: curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash"
        elif [[ -f /etc/arch-release ]]; then
            echo "  Arch Linux: Use swiftly installer:"
            echo "         curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash"
        elif [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
            echo "  Fedora/RHEL: See https://swift.org/download/"
            echo "         Or use swiftly: curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash"
        else
            echo "  See https://swift.org/download/ for installation instructions"
            echo "  Or use the swiftly installer: curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash"
        fi
    fi
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
