# Licensing and Attribution Report

**Date:** 2026-01-27
**Scope:** All omerta repositories

---

## Summary

A comprehensive audit was performed to identify third-party code, ensure proper attribution, and clean up files that should not be in version control.

**Key Findings:**
- One vendored binary requiring attribution (gVisor netstack)
- One standard specification requiring attribution (BIP-39 wordlist)
- Multiple build artifacts and large files improperly committed to history
- All issues have been resolved

---

## Third-Party Code Identified

### 1. gVisor Netstack (omerta_mesh)

**Location:** `Sources/CNetstack/libnetstack.a`
**License:** Apache-2.0
**Type:** Statically linked library

The OmertaTunnel module uses Google's gVisor netstack for userspace TCP/IP processing. Our Go wrapper code (`Sources/OmertaTunnel/Netstack/*.go`) imports gVisor as a library dependency and is compiled into a static library for Swift integration.

**Code Relationship:**
- We wrote: `tunnel_netstack.go`, `cmd/main.go` (wrapper code)
- We use: `gvisor.dev/gvisor/pkg/tcpip/*` (as library imports)
- We did NOT modify any gVisor source code

**Attribution Added:**
- Created `licenses/` directory with full dependency documentation
- `licenses/go-dependencies.md` - Lists gVisor and transitive Go dependencies
- `licenses/swift-dependencies.md` - Lists Swift package dependencies
- Updated `README.md` with "Third-Party Dependencies" section

### 2. BIP-39 Wordlist (omerta_node)

**Location:** `Sources/OmertaCore/Identity/BIP39.swift`
**License:** BSD 2-Clause (Bitcoin Improvement Proposals)
**Type:** Embedded data (2048-word English wordlist)

The BIP-39 English wordlist is a standard from the Bitcoin community used for mnemonic phrase generation.

**Attribution Added:**
- Added header comment with specification reference
- Links to official BIP-39 documentation and wordlist source

### 3. Swift Package Dependencies (all Swift repos)

**Packages:** swift-nio, swift-log, swift-crypto, swift-argument-parser
**License:** Apache-2.0 (all from Apple)
**Type:** External dependencies (fetched by SPM, not vendored)

These are standard Apple libraries fetched at build time via Swift Package Manager. They are not included in the repository.

**Attribution:** Listed in `omerta_mesh/licenses/swift-dependencies.md`

---

## Files Removed from History

Large files and build artifacts were improperly committed and have been removed using `git-filter-repo`:

### omerta_node

| Path | Size | Reason |
|------|------|--------|
| `.vm-test/` | 2.5 GB | VM disk images (qcow2, ubuntu-cloud.img, UEFI vars) |
| `simulations/.venv/` | ~25 MB | Python virtual environment |
| `Sources/OmertaTunnel/Netstack/libnetstack.a` | 18 MB | Duplicate of file now in omerta_mesh |

### omerta_mesh

| Path | Size | Reason |
|------|------|--------|
| `Sources/OmertaTunnel/Netstack/libnetstack.a` | 18 MB | Build product (duplicate of CNetstack copy) |

### omerta_lang

| Path | Size | Reason |
|------|------|--------|
| `*__pycache__*` | ~400 KB | Python bytecode cache |

---

## Gitignore Updates

### omerta_node/.gitignore
Added:
```gitignore
.vm-test/
*.qcow2
*.fd
```

### omerta_mesh/.gitignore
Added:
```gitignore
# Go build products (rebuilt with 'make' in Sources/OmertaTunnel/Netstack/)
Sources/OmertaTunnel/Netstack/libnetstack.a
Sources/OmertaTunnel/Netstack/libnetstack.h
```

---

## Current Vendored Files

Only one vendored binary remains in the repositories:

| File | Repo | Size | License | Justification |
|------|------|------|---------|---------------|
| `Sources/CNetstack/libnetstack.a` | omerta_mesh | 18 MB | Apache-2.0 | Required for Swift compilation; Go toolchain not available on all build systems |

This file is properly attributed in `licenses/go-dependencies.md`.

---

## Compliance Status

| Requirement | Status |
|-------------|--------|
| Apache-2.0 attribution for gVisor | ✅ Complete |
| Apache-2.0 attribution for Swift packages | ✅ Complete |
| BIP-39 specification reference | ✅ Complete |
| No unattributed third-party code | ✅ Verified |
| No build artifacts in git | ✅ Cleaned |
| No secrets/credentials in git | ✅ Verified (see SECURITY_AUDIT_REPORT.md) |

---

## License Files Created

```
omerta_mesh/
└── licenses/
    ├── README.md              # Overview of third-party licenses
    ├── go-dependencies.md     # gVisor and Go dependencies (Apache-2.0)
    └── swift-dependencies.md  # Swift package dependencies (Apache-2.0)
```

---

## Recommendations

1. **Before public release:** Consider whether to keep `libnetstack.a` vendored or require Go toolchain for builds. Vendoring simplifies builds but adds 18 MB to the repository.

2. **Automated license checking:** Consider adding `go-licenses` to CI to catch new dependencies.

3. **NOTICE file:** For formal Apache-2.0 compliance, a top-level NOTICE file listing all Apache-licensed dependencies could be added.

---

## Audit Methodology

1. **File search:** Searched for common patterns (`.venv`, `__pycache__`, `*.a`, `*.so`, `*.pyc`)
2. **Git history analysis:** Used `git rev-list --objects --all` to find large objects in history
3. **Copyright search:** Grepped for "copyright", "license", "BSD", "MIT", "Apache" in source files
4. **Attribution search:** Searched for "copied from", "based on", "derived from" comments
5. **Dependency analysis:** Reviewed Package.swift, go.mod, and pyproject.toml files
6. **Standard detection:** Identified implementations of standards (BIP-39, RFC references)

---

## Related Documents

- [SECURITY_AUDIT_REPORT.md](../SECURITY_AUDIT_REPORT.md) - Sensitive information audit
- [omerta_mesh/licenses/](../omerta_mesh/licenses/) - Third-party license documentation
