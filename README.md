# Omerta: Infrastructure for Machine-Managed Compute

---

## Summary

Omerta is a platform for ephemeral compute swarms which allows providers to share their compute without worrying about what is being run. It does this by deleting VMs after use and requiring all networking traffic go through a VPN served by the compute consumer. This decreases risks of providing compute in a swarm without requiring heavyweight mechanisms for encrypted computation or identity attestation. This functionality is built on top of a new mesh networking library which supports encrypted communication and seamless reconnection on session interruptions from either side.

Omerta also includes a protocol and associated programming language for specifying transactions on a novel blockchain which supports a type of eventual consistency for which there is never a single global consensus. This greatly reduces the overhead of currency and identity management without losing the benefits of blockchains. The ability to tolerate a lack of a single global consensus is accomplished by moving trust into explicit mechanisms for granting trust and verifying that trust is not abused which are recorded on-chain. Transactions on this blockchain are described using a new language describing Mealy machines and adopting a lockless programming style for synchronization.

In order to gain confidence in the technology, we simulate economic actors participating in transactions and attempting to exploit the system. We study various types of economic participants and compute market conditions, and we borrow from an existing blockchain network simulation methodology to try to maintain accuracy in the performance characteristics of networking between participants. We also study the potential economic impact for existing cloud providers and potential market participants as well as various attack scenarios with higher level simulation methodologies.

---

## Why This Might Work Now

Prior attempts at decentralized compute (Golem, iExec, BOINC) faced real limitations:
- Humans don't want to manage unreliable infrastructure
- Blockchain consensus overhead erased the cost advantage
- Complex setup limited participation to experts
- Token economics created extractive incentives

Machine intelligence solves each of these problems:
- Machines can orchestrate parallel workloads across unreliable infrastructure—retrying, rerouting, recovering—in ways humans never would. What's friction for humans is normal operation for machines.
- Trust measurement at scale was impractical when humans had to rate each other. Automated verification of every transaction enables trust computation that prior systems could only theorize about.
- We remove friction during onboarding through app store compatibility and user space execution. And we choose a simpler software architecture over unclear benefits from more complex mechanisms for managing cloud compute. Machine intelligences have shown a capability to handle the more diverse and unpredictable compute environments that will be exposed as a result.
- An infrastructure project can have benefits beyond what are attainable with things that work at smaller scales. The introduction of a new market comes with insider benefits that likely increase with good early choices that increase user trust like open sourcing the code and not retaining coins for yourself.

---

## Repository Structure

This is the top-level repository for the Omerta project. The codebase is organized into focused submodules:

### [omerta_node](omerta_node/)

Swift application implementing provider and consumer nodes. Handles VM management, CLI tooling, and orchestration.

- **Sources**: OmertaCore, OmertaConsumer, OmertaProvider, OmertaVM, OmertaDaemon, OmertaCLI
- **Testing**: `swift test`

### [omerta_mesh](omerta_mesh/)

Peer-to-peer mesh networking layer. Handles NAT traversal, peer discovery, encrypted communication, and the wire protocol.

- **Implementation**: ~17,000 lines of Swift with ~16,000 lines of tests
- **Features**: ChaCha20-Poly1305 encryption, X25519 key exchange, channel-based messaging
- **Testing**: `swift test`

### [omerta_lang](omerta_lang/)

Transaction language toolchain for the `.omt` protocol specification language.

- **Components**: Parser (Lark-based), validator, linter with auto-fix, code generators
- **Output**: Python state machines, Markdown documentation
- **Editors**: Syntax highlighting for Vim, PrismJS, HighlightJS
- **Testing**: `pytest`

### [omerta_protocol](omerta_protocol/)

Protocol specifications and simulation infrastructure.

- **Protocol**: Transaction specifications in `.omt` format (escrow_lock, cabal_attestation, etc.)
- **Simulations**: Economic simulations, chain primitives, discrete event simulation framework
- **Papers**: Economic analysis, mechanism design documents
- **Testing**: `pytest simulations/tests/`

---

## Documentation

### Papers

Polished documents intended for external consumption by humans and machines.

- [WHITEPAPER.md](papers/WHITEPAPER.md) - Technical whitepaper with literature review
- [papers/paper/](papers/paper/) - LaTeX source for academic paper

### Plans

Working documents for development - design docs, implementation plans, review cycles.

- [plans/](plans/) - Project-wide plans and design documents
- [plans/reviews/](plans/reviews/) - Paper review cycles and responses
- Each submodule has its own `plans/` directory for repo-specific documentation

---

## Getting Started

Clone with submodules:
```bash
git clone --recursive <repo-url>
```

Or initialize submodules after cloning:
```bash
git submodule update --init --recursive
```

### Running Tests

Run all tests:
```bash
./scripts/run-all-tests.sh        # All tests
./scripts/run-all-tests.sh --quick  # Python tests only (faster)
```

Or run individually:
```bash
# Node (Swift)
cd omerta_node && swift test

# Mesh (Swift)
cd omerta_mesh && swift test

# Language toolchain (Python)
cd omerta_lang && pytest

# Protocol simulations (Python, requires omerta_lang)
cd omerta_protocol && pip install -e ../omerta_lang && pytest simulations/tests/
```
