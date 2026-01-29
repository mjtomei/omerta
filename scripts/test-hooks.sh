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
    # Configure git user for CI (needed for test commits)
    git config user.email "test@example.com" 2>/dev/null || true
    git config user.name "Test User" 2>/dev/null || true

    for dir in "$ROOT_DIR" "$ROOT_DIR"/omerta_lang "$ROOT_DIR"/omerta_mesh "$ROOT_DIR"/omerta_node "$ROOT_DIR"/omerta_protocol; do
        if [ -d "$dir/.githooks" ]; then
            (cd "$dir" && git config core.hooksPath .githooks 2>/dev/null || true)
            (cd "$dir" && git config user.email "test@example.com" 2>/dev/null || true)
            (cd "$dir" && git config user.name "Test User" 2>/dev/null || true)
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

expect_blocked "PGP private key" "test-key.txt" '-----BEGIN PGP PRIVATE KEY BLOCK-----
lQPGBGF...
-----END PGP PRIVATE KEY BLOCK-----'

# API keys and passwords
expect_blocked "API key assignment" "config.py" 'api_key = "sk-abc123def456ghi789"'
expect_blocked "Secret key" "settings.py" 'secret_key = "mysupersecret123"'
expect_blocked "AWS Access Key" "aws.conf" 'AWS_ACCESS_KEY_ID=AKIAREALKEY12345678'
expect_blocked "AWS Secret Key" "aws.conf" 'AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG'

# GitHub tokens
expect_blocked "GitHub PAT" "config.txt" 'token=ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789'

# Other service tokens
expect_blocked "Stripe live key" "config.py" 'stripe_key = "sk_live_abcdef123456"'
expect_blocked "Slack token" "config.py" 'slack = "xoxb-123456789-abcdefghij"'
expect_blocked "npm token" "npmrc" '//registry.npmjs.org/:_authToken=npm_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789'

# Credentials in URLs
expect_blocked "Password in URL" "config.py" 'db_url = "postgres://admin:secretpass@localhost/db"'

# Bearer tokens
expect_blocked "Bearer token" "api.py" 'headers = {"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9abcdef"}'

echo ""
echo "--- Pre-commit: Blocked File Extensions ---"
echo ""

# Key file extensions
expect_blocked ".pem file" "server.pem" 'certificate content'
expect_blocked ".key file" "private.key" 'key content'
expect_blocked ".p12 file" "cert.p12" 'pkcs12 content'
expect_blocked "id_rsa file" "id_rsa" 'ssh key content'

echo ""
echo "--- Pre-commit: Normal Files (should be allowed) ---"
echo ""

expect_allowed "Normal code" "app.py" 'def get_user():
    return {"name": "test"}'
expect_allowed "Public key file" "server.pub" 'ssh-rsa AAAAB3NzaC1yc2E...'
expect_allowed "Documentation" "README.md" '# Project README'

echo ""
echo "--- Pre-commit: Local Network State Detection ---"
echo ""

# LAN IP addresses
expect_blocked "Private IP (192.168)" "deploy.sh" 'ssh 192.168.12.121 "echo hello"'
expect_blocked "Private IP (10.x)" "config.sh" 'SERVER=10.0.0.1'
expect_blocked "Private IP (172.16)" "run.sh" 'HOST=172.16.0.50'

# Firewall commands
expect_blocked "iptables command" "setup.sh" 'iptables -A INPUT -p tcp --dport 80 -j ACCEPT'
expect_blocked "pfctl command" "setup.sh" 'echo "block all" | pfctl -ef -'
expect_blocked "nftables command" "setup.sh" 'nft add rule inet filter input accept'

# Traffic control
expect_blocked "tc netem command" "test.sh" 'tc qdisc add dev eth0 root netem delay 100ms'

# Interface manipulation
expect_blocked "ip addr add" "setup.sh" 'ip addr add 10.0.0.2/24 dev eth0'

# SSH with sudo
expect_blocked "ssh sudo" "deploy.sh" 'ssh mac "sudo systemctl restart app"'

# Machine-specific interfaces
expect_blocked "Specific NIC name" "setup.sh" 'IFACE=enP7s7'

echo ""
echo "--- Pre-commit: Absolute Path Detection ---"
echo ""

expect_blocked "Home directory path" "run.sh" 'BINARY=/home/matt/bin/app'
expect_blocked "macOS user path" "run.sh" 'CONFIG=/Users/johndoe/config.json'
expect_blocked "Tmp path" "run.sh" 'LOGDIR=/tmp/myapp_logs'
expect_blocked "Opt path" "test-opt-path.sh" 'APP=/opt/myapp/bin/server'

# These should be allowed (standard system paths, shebangs)
expect_allowed "Shebang" "run.sh" '#!/usr/bin/env bash
echo "hello"'
expect_allowed "System binary ref" "docs.md" 'Uses /usr/bin/env to locate interpreter'

echo ""
echo "--- Pre-commit: RFC 5737 Documentation IPs (should be allowed) ---"
echo ""

expect_allowed "RFC 5737 TEST-NET-1" "example.swift" 'let addr = "192.0.2.1"' "omerta_mesh"
expect_allowed "RFC 5737 TEST-NET-2" "example.swift" 'let server = "198.51.100.50"' "omerta_mesh"
expect_allowed "RFC 5737 TEST-NET-3" "example.swift" 'let host = "203.0.113.99"' "omerta_mesh"

echo ""
echo "--- Pre-commit: Real IPs blocked even in source files ---"
echo ""

expect_blocked "Real LAN IP in source" "example.swift" 'let addr = "192.168.1.1"'
expect_blocked "Real LAN IP in test" "test-net.swift" 'let addr = "10.0.0.1"'

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
