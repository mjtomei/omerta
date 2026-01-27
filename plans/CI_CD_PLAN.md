# CI/CD Plan for Omerta

## Overview

This document outlines the CI/CD strategy for the Omerta project, covering automated testing, building, deployment, and security checks across multiple platforms.

## Supported Platforms

### Python Tests (omerta_lang, omerta_protocol)
- **Debian 12** (Bookworm)
- **Fedora 40**
- **Ubuntu 24.04** (Noble)
- **macOS** (latest)

### Swift Tests (omerta_node, omerta_mesh)
- **Ubuntu 24.04** with Swift 6.0 (Linux)
- **Debian 12** with Swift 6.0 (Linux)
- **Fedora 40** with Swift 6.0 (Linux)
- **macOS** with Xcode (native)

### Production Builds
- **Amazon Linux 2023** (x86_64) - Bootstrap nodes
- **macOS** (ARM64) - Desktop client
- **Linux** (ARM64, x86_64) - Server/daemon

---

## GitHub Actions Workflow

### Workflow Structure

```
.github/
└── workflows/
    ├── python-tests.yml      # Python tests on multiple distros
    ├── swift-tests.yml       # Swift tests on Ubuntu/Debian/Fedora + macOS
    ├── security-checks.yml   # Sensitive data, large files, license checks
    ├── build-release.yml     # Release builds
    └── deploy.yml            # Deployment to bootstrap nodes
```

### 1. Python Tests (`python-tests.yml`)

```yaml
name: Python Tests

on:
  push:
    branches: [master]
    paths:
      - 'omerta_lang/**'
      - 'omerta_protocol/**'
  pull_request:
    branches: [master]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-24.04, macos-latest]
        python-version: ['3.11', '3.12']

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -e omerta_lang
          pip install -r omerta_protocol/requirements.txt
          pip install pytest pytest-cov

      - name: Test omerta_lang with coverage
        run: |
          pytest omerta_lang/tests/ -v --cov=omerta_lang --cov-report=xml:coverage-lang.xml --cov-report=term

      - name: Test omerta_protocol with coverage
        run: |
          pytest omerta_protocol/simulations/tests/ -v --cov=omerta_protocol --cov-report=xml:coverage-protocol.xml --cov-report=term

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v4
        with:
          files: coverage-lang.xml,coverage-protocol.xml
          flags: python-${{ matrix.python-version }}
          fail_ci_if_error: false

  test-containers:
    strategy:
      matrix:
        container: ['debian:bookworm', 'fedora:40']

    runs-on: ubuntu-latest
    container: ${{ matrix.container }}

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install Python (Debian)
        if: contains(matrix.container, 'debian')
        run: |
          apt-get update
          apt-get install -y python3 python3-pip python3-venv git

      - name: Install Python (Fedora)
        if: contains(matrix.container, 'fedora')
        run: dnf install -y python3 python3-pip git

      - name: Run tests with coverage
        run: |
          python3 -m venv .venv
          source .venv/bin/activate
          pip install --upgrade pip
          pip install -e omerta_lang
          pip install -r omerta_protocol/requirements.txt
          pip install pytest pytest-cov
          pytest omerta_lang/tests/ -v --cov=omerta_lang --cov-report=term
          pytest omerta_protocol/simulations/tests/ -v --cov=omerta_protocol --cov-report=term
```

### 2. Swift Tests (`swift-tests.yml`)

```yaml
name: Swift Tests

on:
  push:
    branches: [master]
    paths:
      - 'omerta_node/**'
      - 'omerta_mesh/**'
  pull_request:
    branches: [master]

jobs:
  test-ubuntu:
    runs-on: ubuntu-24.04
    container: swift:6.0-noble

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build and test omerta_node with coverage
        working-directory: omerta_node
        run: |
          swift test --enable-code-coverage
          xcrun llvm-cov export -format="lcov" \
            .build/debug/OmertaNodePackageTests.xctest \
            -instr-profile .build/debug/codecov/default.profdata \
            > coverage-node.lcov || true

      - name: Build and test omerta_mesh with coverage
        working-directory: omerta_mesh
        run: |
          swift test --enable-code-coverage
          xcrun llvm-cov export -format="lcov" \
            .build/debug/OmertaMeshPackageTests.xctest \
            -instr-profile .build/debug/codecov/default.profdata \
            > coverage-mesh.lcov || true

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v4
        with:
          files: omerta_node/coverage-node.lcov,omerta_mesh/coverage-mesh.lcov
          flags: swift-ubuntu
          fail_ci_if_error: false

  test-debian:
    runs-on: ubuntu-latest
    container: swift:6.0-bookworm

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build and test omerta_node
        working-directory: omerta_node
        run: swift test

      - name: Build and test omerta_mesh
        working-directory: omerta_mesh
        run: swift test

  test-fedora:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build Swift container for Fedora
        run: |
          docker build -t swift-fedora -f - . <<'EOF'
          FROM fedora:40
          RUN dnf install -y \
              git \
              gcc \
              gcc-c++ \
              libcurl-devel \
              libedit-devel \
              libicu-devel \
              libuuid-devel \
              libxml2-devel \
              ncurses-devel \
              python3 \
              sqlite-devel \
              tar \
              tzdata \
              zlib-devel
          RUN curl -sL https://download.swift.org/swift-6.0.3-release/fedora39/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-fedora39.tar.gz | tar xz -C /opt
          ENV PATH="/opt/swift-6.0.3-RELEASE-fedora39/usr/bin:${PATH}"
          WORKDIR /build
          EOF

      - name: Run Swift tests on Fedora
        run: |
          docker run --rm -v $(pwd):/build swift-fedora bash -c "
            cd omerta_node && swift test &&
            cd ../omerta_mesh && swift test
          "

  test-macos:
    runs-on: macos-latest

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode.app

      - name: Build and test omerta_node with coverage
        working-directory: omerta_node
        run: |
          swift test --enable-code-coverage
          xcrun llvm-cov export -format="lcov" \
            .build/debug/OmertaNodePackageTests.xctest/Contents/MacOS/OmertaNodePackageTests \
            -instr-profile .build/debug/codecov/default.profdata \
            > coverage-node.lcov || true

      - name: Build and test omerta_mesh with coverage
        working-directory: omerta_mesh
        run: |
          swift test --enable-code-coverage
          xcrun llvm-cov export -format="lcov" \
            .build/debug/OmertaMeshPackageTests.xctest/Contents/MacOS/OmertaMeshPackageTests \
            -instr-profile .build/debug/codecov/default.profdata \
            > coverage-mesh.lcov || true

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v4
        with:
          files: omerta_node/coverage-node.lcov,omerta_mesh/coverage-mesh.lcov
          flags: swift-macos
          fail_ci_if_error: false
```

### 3. Security Checks (`security-checks.yml`)

```yaml
name: Security Checks

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  sensitive-data-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
          fetch-depth: 0

      - name: Check for sensitive patterns
        run: |
          # Patterns that indicate sensitive data
          PATTERNS=(
            'PRIVATE KEY'
            'BEGIN RSA'
            'BEGIN DSA'
            'BEGIN EC PRIVATE'
            'BEGIN OPENSSH PRIVATE'
            'password\s*[:=]'
            'api[_-]?key\s*[:=]'
            'secret[_-]?key\s*[:=]'
            'access[_-]?token\s*[:=]'
            'auth[_-]?token\s*[:=]'
            'AWS_ACCESS_KEY'
            'AWS_SECRET'
            'ANTHROPIC_API_KEY'
            'OPENAI_API_KEY'
          )

          FOUND=0
          for pattern in "${PATTERNS[@]}"; do
            if grep -rniE "$pattern" --include="*.swift" --include="*.py" --include="*.json" --include="*.yaml" --include="*.yml" --include="*.toml" --include="*.cfg" --include="*.conf" --include="*.txt" --include="*.md" . 2>/dev/null | grep -v 'node_modules\|\.git\|\.venv\|__pycache__' | grep -v '# Example\|# TODO\|placeholder\|<your\|YOUR_\|example\.com'; then
              echo "::error::Potential sensitive data found in repository"
              FOUND=1
            fi
          done

          # Check for .env files that shouldn't be committed
          if find . -name ".env" -o -name ".env.*" | grep -v '.env.example\|.env.template' | head -1 | grep -q .; then
            echo "::error::.env files found - these should not be committed"
            FOUND=1
          fi

          exit $FOUND

  large-file-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Check for large files (>1MB)
        run: |
          # Find files larger than 1MB
          LARGE_FILES=$(find . -type f -size +1M -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.venv/*" -not -path "./__pycache__/*" -not -path "./.build/*")

          if [ -n "$LARGE_FILES" ]; then
            echo "::error::Large files (>1MB) found in repository:"
            echo "$LARGE_FILES"
            echo ""
            echo "Consider using Git LFS for large files or moving them to a separate storage."
            exit 1
          fi

          echo "No large files found."

      - name: Check for binary files that should be tracked with LFS
        run: |
          # Binary file extensions that should use Git LFS
          BINARY_EXTENSIONS="*.exe *.dll *.so *.dylib *.a *.lib *.zip *.tar *.gz *.7z *.rar *.iso *.dmg *.pkg *.deb *.rpm *.mp3 *.mp4 *.avi *.mov *.mkv *.wav *.flac *.png *.jpg *.jpeg *.gif *.bmp *.tiff *.psd *.ai *.pdf *.doc *.docx *.xls *.xlsx *.ppt *.pptx *.sqlite *.db"

          FOUND=0
          for ext in $BINARY_EXTENSIONS; do
            FILES=$(find . -type f -name "$ext" -not -path "./.git/*" -not -path "./.build/*" 2>/dev/null)
            if [ -n "$FILES" ]; then
              echo "::warning::Binary files with extension $ext found (consider Git LFS):"
              echo "$FILES"
              FOUND=1
            fi
          done

          # Don't fail on warnings, just notify
          exit 0

  license-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Check for license headers in source files
        run: |
          # Check if source files have license headers or if there's a LICENSE file
          if [ ! -f LICENSE ] && [ ! -f LICENSE.md ] && [ ! -f LICENSE.txt ]; then
            echo "::warning::No LICENSE file found in repository root"
          fi

          # Check for third-party code without attribution
          if [ -d licenses ]; then
            echo "Found licenses directory"
          else
            echo "::warning::No licenses directory found - consider adding one for third-party attributions"
          fi

      - name: Check for SPDX license identifiers
        run: |
          # Look for files that might be third-party without attribution
          # This checks for common third-party indicators
          SUSPECT_FILES=$(grep -rliE 'copyright|license|MIT|Apache|GPL|BSD|Mozilla' --include="*.swift" --include="*.py" . 2>/dev/null | grep -v '.git\|.venv\|__pycache__\|node_modules' | head -20)

          if [ -n "$SUSPECT_FILES" ]; then
            echo "Files with license/copyright mentions (verify attributions):"
            echo "$SUSPECT_FILES"
          fi

  git-secrets-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
          fetch-depth: 0

      - name: Install git-secrets
        run: |
          git clone https://github.com/awslabs/git-secrets.git
          cd git-secrets && sudo make install

      - name: Register common patterns
        run: |
          git secrets --register-aws
          # Add custom patterns
          git secrets --add 'ANTHROPIC_API_KEY'
          git secrets --add 'OPENAI_API_KEY'
          git secrets --add 'sk-[a-zA-Z0-9]{48}'

      - name: Scan repository
        run: |
          git secrets --scan || echo "::warning::git-secrets found potential issues"

  hooks-sync-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Verify hooks are in sync across repos
        run: ./scripts/check-hooks-sync.sh
```

### 4. Release Builds (`build-release.yml`)

```yaml
name: Build Release

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  # Run security checks before building
  security-gate:
    uses: ./.github/workflows/security-checks.yml

  build-linux-x86:
    needs: security-gate
    runs-on: ubuntu-24.04
    container: swift:6.0-noble

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build release
        run: |
          cd omerta_node
          swift build -c release
          cd ../omerta_mesh
          swift build -c release

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: linux-x86_64
          path: |
            omerta_node/.build/release/omertad
            omerta_node/.build/release/omerta
            omerta_mesh/.build/release/libOmertaMesh.so

  build-macos:
    needs: security-gate
    runs-on: macos-latest

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build release
        run: |
          cd omerta_node
          swift build -c release
          cd ../omerta_mesh
          swift build -c release

      - name: Sign binaries
        run: |
          cd omerta_node
          codesign --force --sign - --entitlements Entitlements/Omerta.entitlements .build/release/omertad .build/release/omerta

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: macos-arm64
          path: |
            omerta_node/.build/release/omertad
            omerta_node/.build/release/omerta

  build-linux-docker:
    needs: security-gate
    runs-on: ubuntu-24.04

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build for Amazon Linux 2023 (glibc 2.34)
        run: |
          docker build -t omerta-builder -f docker/Dockerfile.amazonlinux .
          docker run --rm -v $(pwd)/dist:/dist omerta-builder

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: linux-amazonlinux
          path: dist/
```

### 5. Deployment (`deploy.yml`)

```yaml
name: Deploy

on:
  workflow_run:
    workflows: ["Build Release"]
    types: [completed]
    branches: [master]

jobs:
  deploy-bootstrap:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest
    environment: production

    steps:
      - name: Download artifacts
        uses: actions/download-artifact@v4
        with:
          name: linux-amazonlinux
          path: dist/

      - name: Deploy to bootstrap1
        uses: appleboy/ssh-action@v1
        with:
          host: bootstrap1.omerta.run
          username: omerta
          key: ${{ secrets.BOOTSTRAP_SSH_KEY }}
          script: |
            systemctl --user stop omertad || true
            cp /tmp/omertad ~/bin/omertad
            chmod +x ~/bin/omertad
            systemctl --user start omertad

      - name: Deploy to bootstrap2
        uses: appleboy/ssh-action@v1
        with:
          host: bootstrap2.omerta.run
          username: omerta
          key: ${{ secrets.BOOTSTRAP_SSH_KEY }}
          script: |
            systemctl --user stop omertad || true
            cp /tmp/omertad ~/bin/omertad
            chmod +x ~/bin/omertad
            systemctl --user start omertad
```

---

## Git Hooks (No External Tools Required)

Git hooks are stored in `.githooks/` and work with vanilla git - no pre-commit framework needed.

### Automatic Setup

Hooks are **automatically configured** when you run the test script:

```bash
./scripts/run-all-tests.sh
```

This configures `core.hooksPath` for the main repo and all submodules.

### Manual Setup (if needed)

```bash
# For a single repo
git config core.hooksPath .githooks

# For all repos at once
for dir in . omerta_lang omerta_mesh omerta_node omerta_protocol; do
  (cd "$dir" && git config core.hooksPath .githooks)
done
```

### Hook Files

#### `.githooks/pre-commit`

Checks for sensitive data patterns before each commit:
- Private keys (RSA, DSA, EC, OpenSSH)
- Passwords, API keys, secret keys
- AWS credentials
- Common API tokens (Anthropic, OpenAI)

#### `.githooks/pre-push`

Checks for large files (>1MB) before push to prevent bloating the repository.

### Keeping Hooks in Sync

The same `.githooks/` directory exists in the parent repo and each submodule. CI verifies they stay in sync:

```bash
# Check sync status
./scripts/check-hooks-sync.sh

# Propagate hooks from parent to submodules
for dir in omerta_lang omerta_mesh omerta_node omerta_protocol; do
  cp .githooks/* "$dir/.githooks/"
done
```

### Bypassing Hooks

For false positives or special cases:
```bash
git commit --no-verify  # Skip pre-commit hooks
git push --no-verify    # Skip pre-push hooks
```

---

## Required Secrets

| Secret | Description |
|--------|-------------|
| `BOOTSTRAP_SSH_KEY` | SSH private key for deploying to bootstrap nodes |
| `CODECOV_TOKEN` | Token for uploading coverage reports to Codecov |
| `APPLE_SIGNING_CERT` | (Optional) Apple signing certificate for notarization |
| `APPLE_SIGNING_PASSWORD` | (Optional) Password for Apple signing certificate |

---

## Docker Images

### `docker/Dockerfile.amazonlinux`

For building binaries compatible with Amazon Linux 2023:

```dockerfile
FROM amazonlinux:2023

# Install Swift dependencies
RUN dnf install -y \
    git \
    gcc \
    gcc-c++ \
    libcurl-devel \
    libedit-devel \
    libicu-devel \
    libuuid-devel \
    libxml-devel \
    ncurses-devel \
    python3 \
    sqlite-devel \
    tar \
    tzdata \
    zlib-devel

# Install Swift
RUN curl -sL https://download.swift.org/swift-6.0-release/amazonlinux2/swift-6.0-RELEASE/swift-6.0-RELEASE-amazonlinux2.tar.gz | tar xz -C /opt
ENV PATH="/opt/swift-6.0-RELEASE-amazonlinux2/usr/bin:${PATH}"

WORKDIR /build
COPY . .

RUN cd omerta_node && swift build -c release
RUN cd omerta_mesh && swift build -c release

CMD ["cp", "-r", "/build/omerta_node/.build/release/omertad", "/build/omerta_mesh/.build/release/", "/dist/"]
```

---

## Test Matrix Summary

| Component | Python 3.11 | Python 3.12 | Swift (Ubuntu) | Swift (Debian) | Swift (Fedora) | Swift (macOS) |
|-----------|-------------|-------------|----------------|----------------|----------------|---------------|
| omerta_lang | ✅ | ✅ | N/A | N/A | N/A | N/A |
| omerta_protocol | ✅ | ✅ | N/A | N/A | N/A | N/A |
| omerta_node | N/A | N/A | ✅ | ✅ | ✅ | ✅ |
| omerta_mesh | N/A | N/A | ✅ | ✅ | ✅ | ✅ |

---

## Test Coverage

### Python Coverage

Python test coverage is collected using `pytest-cov` and reported to Codecov:

```bash
# Run locally with coverage
pytest omerta_lang/tests/ --cov=omerta_lang --cov-report=html --cov-report=term
pytest omerta_protocol/simulations/tests/ --cov=omerta_protocol --cov-report=html --cov-report=term
```

### Swift Coverage

Swift test coverage uses the built-in `--enable-code-coverage` flag:

```bash
# Run locally with coverage
swift test --enable-code-coverage

# Generate HTML report (macOS)
xcrun llvm-cov show \
    .build/debug/PackageTests.xctest/Contents/MacOS/PackageTests \
    -instr-profile .build/debug/codecov/default.profdata \
    -format=html -output-dir=coverage-html

# Generate lcov report for CI
xcrun llvm-cov export -format="lcov" \
    .build/debug/PackageTests.xctest/Contents/MacOS/PackageTests \
    -instr-profile .build/debug/codecov/default.profdata \
    > coverage.lcov
```

---

## Security Checks Summary

| Check | When | Blocks |
|-------|------|--------|
| Sensitive data patterns | Pre-commit | Commit |
| Private keys detection | Pre-commit | Commit |
| Large files (>1MB) | Pre-push | Push |
| License compliance | CI | No (warning only) |
| git-secrets scan | CI | PR merge |
| Binary file detection | CI | No (warning only) |
| Hooks sync check | CI | PR merge |

---

## Branch Protection Rules

Recommended settings for the `master` branch:

1. **Require pull request reviews** - At least 1 approval
2. **Require status checks to pass**:
   - `Python Tests / test`
   - `Swift Tests / test-ubuntu`
   - `Swift Tests / test-macos`
   - `Security Checks / sensitive-data-check`
   - `Security Checks / large-file-check`
3. **Require branches to be up to date**
4. **Do not allow force pushes**

---

## Release Process

1. **Version bump**: Update version in relevant files
2. **Security review**: Ensure all security checks pass
3. **Create tag**: `git tag v1.0.0 && git push origin v1.0.0`
4. **Automated build**: GitHub Actions builds all platforms
5. **Automated deploy**: Binaries deployed to bootstrap nodes
6. **Manual release**: Create GitHub Release with release notes

---

## Local Testing

Developers can run the full test suite locally:

```bash
# Quick Python tests only
./scripts/run-all-tests.sh --quick

# Full test suite (requires Swift)
./scripts/run-all-tests.sh

# Skip venv setup (use existing environment)
./scripts/run-all-tests.sh --no-venv

# Run with coverage
./scripts/run-all-tests.sh --coverage
```

### Git Hooks Setup

Git hooks are automatically configured when running tests. For manual setup:

```bash
# Configure hooks for all repos
git config core.hooksPath .githooks
for dir in omerta_lang omerta_mesh omerta_node omerta_protocol; do
  (cd "$dir" && git config core.hooksPath .githooks)
done

# Verify hooks are in sync
./scripts/check-hooks-sync.sh
```

---

## Future Improvements

1. **Performance benchmarks** - Track performance regression
2. **Nightly builds** - Build and test against Swift nightly
3. **Cross-compilation** - Build ARM64 Linux from x86_64 runners
4. **Integration tests** - Add E2E tests in isolated network namespaces
5. **Dependency scanning** - Add Dependabot or similar for security updates
6. **SBOM generation** - Generate Software Bill of Materials for releases
