# CI/CD Plan for Omerta

## Overview

This document outlines the CI/CD strategy for the Omerta project. CI (testing, security checks) runs automatically via GitHub Actions. Deployment is handled locally using scripts in `omerta_infra`.

## What Runs Where

| Task | Where | Trigger |
|------|-------|---------|
| Python tests | GitHub Actions | Push/PR to master |
| Swift tests | GitHub Actions | Push/PR to master |
| Security checks | GitHub Actions | Push/PR to master |
| Build for production | Local (arch-home/Docker) | Manual |
| Deploy to bootstrap | Local | Manual |

---

## GitHub Actions (Automated)

### Workflow Files

```
.github/workflows/
├── tests.yml      # Python + Swift tests
└── security.yml   # Security scans and hook tests
```

### Test Matrix

| Component | Ubuntu | Debian | Fedora | macOS |
|-----------|--------|--------|--------|-------|
| omerta_lang (Python) | 3.11, 3.12 | 3.11 | 3.11 | 3.11, 3.12 |
| omerta_protocol (Python) | 3.11, 3.12 | 3.11 | 3.11 | 3.11, 3.12 |
| omerta_node (Swift) | 6.0 | - | - | Xcode |
| omerta_mesh (Swift) | 6.0 | - | - | Xcode |

### Security Checks

| Check | Blocks PR |
|-------|-----------|
| Hook functionality test | Yes |
| Hooks in sync across repos | Yes |
| Sensitive data patterns | Yes |
| Large files (>1MB) | Yes |
| Private key files (.pem, .key, id_rsa, etc.) | Yes |

---

## Local Deployment

Deployment is handled manually using scripts in `omerta_infra/scripts/`.

### Quick Reference

```bash
# Full update: pull, build on arch-home, deploy to all servers
cd ~/omerta-infra
./scripts/update.sh prod --arch-home

# Deploy to specific server only
./scripts/update.sh prod --arch-home --server bootstrap1

# Rolling update (zero downtime)
./scripts/update.sh prod --arch-home --rolling

# Skip build (redeploy existing binaries)
./scripts/update.sh prod --skip-build

# Dry run (see what would happen)
./scripts/update.sh prod --arch-home --dry-run
```

### Build Options

| Option | Description |
|--------|-------------|
| (none) | Build locally (requires Swift on ARM) |
| `--arch-home` | Build via Docker on arch-home (x86_64) |
| `--docker` | Build in local Docker container |

### Prerequisites

1. SSH key at `~/.ssh/omerta-key.pem`
2. Terraform state in `terraform/environments/prod/`
3. For `--arch-home`: SSH access to arch-home with Swift installed

---

## Git Hooks (Local Protection)

Pre-commit and pre-push hooks provide local protection before code reaches CI.

### Setup

Hooks are automatically configured when running tests:

```bash
./scripts/run-all-tests.sh
```

Or manually:

```bash
git config core.hooksPath .githooks
```

### What Hooks Check

**Pre-commit (every commit):**
- Private keys (RSA, DSA, EC, OpenSSH, PGP)
- API keys, passwords, secrets in code
- AWS, GitHub, Stripe, Slack, npm, PyPI tokens
- Credentials in URLs
- Bearer tokens
- Key file extensions (.pem, .key, .p12, id_rsa, etc.)

**Pre-push (before push):**
- Large files (>1MB)

### Bypass

```bash
git commit --no-verify  # Skip pre-commit
git push --no-verify    # Skip pre-push
```

---

## Future: Automated Deployment

If automated deployment is needed later:

**Option A: IPs as GitHub Secrets (simple)**
- Store `BOOTSTRAP1_IP`, `BOOTSTRAP2_IP` as secrets
- CI SSHs directly using `BOOTSTRAP_SSH_KEY` secret
- Update secrets manually if IPs change

**Option B: Terraform in CI (complex)**
- Store AWS credentials in GitHub secrets
- CI runs `terraform output` to get IPs
- Requires S3 backend for shared state

**Option C: Webhook trigger**
- CI builds and uploads artifacts
- Webhook triggers local deploy script
- Best of both worlds

---

## Branch Protection (Recommended)

Settings for `master` branch:

1. Require pull request reviews (1 approval)
2. Require status checks:
   - `Python (3.12, ubuntu-24.04)`
   - `Swift (Ubuntu)`
   - `Swift (macOS)`
   - `Git Hook Tests`
   - `Sensitive Data Scan`
3. Require branches to be up to date
4. Do not allow force pushes

---

## Release Process

1. Ensure all CI checks pass on master
2. Tag the release: `git tag v1.0.0 && git push origin v1.0.0`
3. Build locally: `cd ~/omerta-infra && ./scripts/update.sh prod --arch-home`
4. Verify deployment: `ssh bootstrap1 'omerta --version'`
5. Create GitHub Release with changelog

---

## Local Testing

```bash
# Run all tests locally
./scripts/run-all-tests.sh

# Quick mode (Python only, skip Swift)
./scripts/run-all-tests.sh --quick

# Test hooks
./scripts/test-hooks.sh

# Verify hooks are in sync
./scripts/check-hooks-sync.sh
```
