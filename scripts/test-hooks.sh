#!/bin/bash
#
# Test git hooks for sensitive data and large file detection
# Run this after cloning to verify hooks work correctly
#
# Usage: ./scripts/test-hooks.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

setup_hooks() {
    for dir in "$ROOT_DIR" "$ROOT_DIR"/omerta_lang "$ROOT_DIR"/omerta_mesh "$ROOT_DIR"/omerta_node "$ROOT_DIR"/omerta_protocol; do
        if [ -d "$dir/.githooks" ]; then
            (cd "$dir" && git config core.hooksPath .githooks 2>/dev/null || true)
        fi
    done
}

expect_blocked() {
    local test_name="$1"
    local test_file="$2"
    local test_content="$3"
    local test_dir="${4:-.}"

    cd "$ROOT_DIR/$test_dir"
    echo "$test_content" > "$test_file"
    git add "$test_file"

    if git commit -m "test: $test_name" 2>&1 | grep -q "Commit blocked\|ERROR:"; then
        echo -e "${GREEN}PASS${NC}: $test_name (blocked as expected)"
        ((PASSED++))
    else
        echo -e "${RED}FAIL${NC}: $test_name (should have been blocked)"
        ((FAILED++))
    fi

    git restore --staged "$test_file" 2>/dev/null || true
    rm -f "$test_file"
    cd "$ROOT_DIR"
}

expect_allowed() {
    local test_name="$1"
    local test_file="$2"
    local test_content="$3"
    local test_dir="${4:-.}"

    cd "$ROOT_DIR/$test_dir"
    echo "$test_content" > "$test_file"
    git add "$test_file"

    if git commit -m "test: $test_name" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}: $test_name (allowed as expected)"
        git reset --soft HEAD~1 2>/dev/null || true
        ((PASSED++))
    else
        echo -e "${RED}FAIL${NC}: $test_name (should have been allowed)"
        ((FAILED++))
    fi

    git restore --staged "$test_file" 2>/dev/null || true
    rm -f "$test_file"
    cd "$ROOT_DIR"
}

echo "=== Git Hook Tests ==="
echo ""

setup_hooks

echo "--- Pre-commit: Sensitive Data Detection ---"
echo ""

# Private keys
expect_blocked "RSA private key" "test-key.txt" '-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA0Z3VS5JJcds3xfn
-----END RSA PRIVATE KEY-----'

expect_blocked "OpenSSH private key" "test-key.txt" '-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUA
-----END OPENSSH PRIVATE KEY-----'

# API keys and passwords
expect_blocked "API key assignment" "config.py" 'api_key = "sk-abc123def456ghi789"'
expect_blocked "Secret key" "settings.py" 'secret_key = "mysupersecret123"'
expect_blocked "AWS Access Key" "aws.conf" 'AWS_ACCESS_KEY_ID=AKIAREALKEY12345678'
expect_blocked "AWS Secret Key" "aws.conf" 'AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG'

# False positives that should be allowed
expect_allowed "Placeholder API key" "docs.md" 'api_key = "YOUR_API_KEY_HERE"'
expect_allowed "Template password" "template.yaml" 'password: <your-password-here>'
expect_allowed "Normal code" "app.py" 'def get_user():
    return {"name": "test"}'
expect_allowed "Comment with example" "config.py" '# Example: api_key = "your_key_here"'

# Test in submodule if available
if [ -d "$ROOT_DIR/omerta_lang/.githooks" ]; then
    echo ""
    echo "--- Submodule Tests (omerta_lang) ---"
    echo ""
    expect_blocked "Secret in submodule" "test-secret.py" 'secret_key = "abc123secret"' "omerta_lang"
    expect_allowed "Normal file in submodule" "test-normal.md" '# Documentation' "omerta_lang"
fi

echo ""
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
exit 0
