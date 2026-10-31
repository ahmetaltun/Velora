# Contributing to Velora

Thank you for your interest in contributing to Velora. This document provides guidelines and instructions for contributing to the codebase, submitting bug reports, and proposing new features.

---

## Code of Conduct

All contributors and maintainers are expected to maintain a professional, respectful, and collaborative environment. Treat every participant with courtesy regardless of experience level, background, or identity. Constructive feedback and thoughtful technical discussions are welcomed.

---

## Architecture and Scope

Velora is an Apple Silicon-first storage management utility built specifically for macOS 15 (Sequoia) and subsequent releases. The project does not maintain backward compatibility with Intel (x86_64) architectures or legacy macOS versions.

The repository is structured into two primary layers connected via Mozilla UniFFI:
1. **Rust Core Engine (`crates/`)**: A modular workspace handling high-throughput disk traversal, in-memory indexing, binary serialization, bottom-up tree rollup, FSEvents monitoring, cryptographic hashing, and threat analysis.
2. **Swift Native Application (`swift/Sources/`)**: A native macOS application written in Swift 6 and SwiftUI, providing the user interface, interaction state management, and system integrations.

When contributing code, adhere strictly to this architectural separation. Heavy computational tasks, filesystem operations, and parsing belong in the Rust crates; UI presentation, window management, and native macOS interactions belong in the Swift layer.

---

## Prerequisites

Before building Velora, ensure your development environment satisfies the following requirements:

- **Hardware**: Mac with Apple Silicon (M1, M2, M3, M4 or later).
- **Operating System**: macOS 15.0 (Sequoia) or newer.
- **Rust Toolchain**: Rust 1.75 or later with the `aarch64-apple-darwin` target:
  ```bash
  rustup update stable
  rustup target add aarch64-apple-darwin
  ```
- **Xcode**: Xcode 16.0 or later with Swift 6.0+ Command Line Tools installed:
  ```bash
  xcode-select --install
  ```

---

## Getting Started

1. Fork the repository on GitHub.
2. Clone your fork locally:
   ```bash
   git clone https://github.com/your-username/Velora.git
   cd Velora
   ```
3. Verify your toolchain by compiling the Rust workspace:
   ```bash
   cargo check --workspace
   ```

---

## Development Workflow

### Live Reload Development

Velora provides an automated development watcher script that compiles both the Rust backend and Swift frontend, bundles the application, and relaunches it upon file changes:

```bash
./scripts/dev.sh
```

The script monitors `crates/`, `swift/Sources/`, and `assets/`. If a compilation error occurs, the existing application process remains active while the terminal displays diagnostic errors.

### Manual Build Steps

If you prefer building individual components manually:

1. Compile the UniFFI bridge crate:
   ```bash
   cargo build -p velora-ffi
   ```
2. Build the Swift application target:
   ```bash
   cd swift
   swift build --arch arm64
   cd ..
   ```
3. Bundle the application into `Velora.app`:
   ```bash
   ./bundle_app.sh
   ```

---

## Coding Standards

### Rust Guidelines

- **Safety**: Avoid `unsafe` blocks. If an unsafe construct is strictly necessary (e.g., specific POSIX system calls), thoroughly document the safety invariants with a `// SAFETY:` comment.
- **Error Handling**: Use structured error enums with `thiserror` in library crates. Never panic in production code paths; propagate errors across the UniFFI boundary cleanly.
- **Performance**: In traversal and rollup routines, minimize allocations inside tight loops. Prefer slice references, arenas, and pre-allocated vectors.
- **Formatting and Linting**:
  All Rust code must adhere to rustfmt and clippy standards without warnings:
  ```bash
  cargo fmt --check
  cargo clippy --workspace --all-targets -- -D warnings
  ```

### Swift and SwiftUI Guidelines

- **Concurrency**: Adhere to Swift 6 strict concurrency checks. Ensure view models and UI-facing state operations are annotated with `@MainActor`. Never block the main thread with long-running operations.
- **State Management**: Use the observation framework (`@Observable`) and structured ViewModels. Keep SwiftUI views lightweight and focused on layout and user interaction.
- **Design Consistency**: Follow the Velora Bloom design language. Use the centralized tokens and colors defined in `VeloraTheme` rather than hardcoding arbitrary colors or dimensions.

---

## Testing Requirements

Every bug fix or new capability must be accompanied by relevant unit or integration tests:

```bash
# Run all workspace tests
cargo test --workspace

# Run tests for a specific crate
cargo test -p velora-index
cargo test -p velora-search
cargo test -p velora-dev
cargo test -p velora-hygiene
```

Before opening a pull request, verify that:
1. All existing and new tests pass.
2. `cargo fmt --check` reports no formatting discrepancies.
3. `cargo clippy --workspace --all-targets -- -D warnings` finishes cleanly.

---

## Pull Request Process

1. Create a feature branch from `master` or `dev`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. Commit your changes using conventional commit messages:
   - `feat:` for new capabilities
   - `fix:` for bug fixes
   - `refactor:` for code restructuring without behavior changes
   - `perf:` for performance optimizations
   - `test:` for adding or correcting test suites
   - `chore:` for build, tooling, or dependency updates
3. Push your branch to your fork and submit a Pull Request to the main repository.
4. Provide a clear description of the problem solved, the architectural approach taken, and the verification steps performed.
5. Address any review feedback promptly.

---

## Submitting Issues

When submitting an issue on GitHub, include:
- A clear, concise title.
- macOS version and Mac hardware model (e.g., macOS 15.1, Apple M3 Pro).
- Steps to reproduce the unexpected behavior.
- Relevant log output or backtraces if applicable.

---

## License

All contributions to Velora are licensed under the MIT License. By submitting a pull request, you agree that your contributions will be licensed under the terms of the project's [LICENSE-MIT](LICENSE-MIT).
