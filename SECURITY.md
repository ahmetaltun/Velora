# Security Policy for Velora

The Velora development team takes the security of our application and our users seriously. This document outlines our vulnerability disclosure process, supported software versions, and key architectural security controls.

---

## Supported Versions

Security updates and bug fixes are applied to the active development and release branches. We strongly advise users to run the latest official release.

| Version | Supported          | Platform Architecture             |
| ------- | ------------------ | --------------------------------- |
| 0.2.x   | Yes                | macOS 15.0+ / Apple Silicon arm64 |
| 0.1.x   | No                 | Discontinued                      |
| < 0.1.0 | No                 | Discontinued                      |

---

## Reporting a Vulnerability

If you discover a security vulnerability in Velora, please report it responsibly through private channels. Do not open public GitHub issues or disclose vulnerabilities publicly prior to remediation.

### How to Report Privately

1. **GitHub Security Advisory (Recommended)**:
   Navigate to the Velora repository on GitHub, select the **Security** tab, click **Report a vulnerability**, and submit your findings.
2. **Direct Email**:
   If you cannot access GitHub Security Advisories, send an encrypted or direct email to:
   `github@ahmetaltun.dev` with the subject line `[SECURITY] Velora Vulnerability Report`.

### What to Include in Your Report

To help us triage and resolve the issue quickly, include:
- A clear description of the vulnerability.
- The specific version or commit hash where the issue was observed.
- Step-by-step instructions or a minimal proof of concept to reproduce the behavior.
- The potential security impact or attack scenario.
- Any suggested remediation or patch.

### Response and Remediation Timeline

- **Initial Acknowledgment**: We aim to acknowledge receipt of your report within 48 hours.
- **Triage and Assessment**: We will assess severity and confirm reproducibility within 3 business days of acknowledgment.
- **Coordinated Disclosure**: We will collaborate with the reporter to agree on a public disclosure date once a tested patch has been prepared and released.

---

## Application Security Architecture

Velora incorporates several defensive engineering practices to ensure safe operation:

### Memory Safety via Rust

The entire storage engine, filesystem crawler, search indexer, and hash calculators are implemented in Rust. Rust's strict ownership model and borrow checker eliminate entire categories of memory corruption vulnerabilities, including buffer overflows, double frees, use-after-free, and concurrent data races.

### macOS Hardened Runtime and Entitlements

Production builds of Velora are compiled with the macOS Hardened Runtime flag enabled (`--options runtime`). This enforces integrity restrictions on process execution, memory page execution, and library loading.

### Code Signing and Notarization

Official distribution binaries and disk images (`.dmg`) are:
- Cryptographically signed with an Apple Developer ID Application certificate.
- Validated with embedded secure timestamps.
- Notarized by Apple's automated notary service and stapled with Gatekeeper verification tickets.

### Secure Update Delivery

In-app updates via the Sparkle 2 framework require Ed25519 cryptographic public-key verification. Update packages cannot be substituted, modified, or tampered with in transit without failing signature verification. All update metadata is transferred over TLS/HTTPS.

### Safe Filesystem Interactions

- **Reversible Deletion**: File removal operations are mediated through the macOS Trash system (`NSWorkspace.shared.recycle`) rather than permanent filesystem unlinking (`unlink` / `rm`).
- **Path Sanitization**: Filesystem traversals and path manipulations strictly check boundary limits to prevent path traversal attacks.
- **Permission Neutralization in Quarantine**: Files identified as potential threats and routed to the quarantine vault are stripped of all executable permissions (`chmod 0000`) to prevent accidental invocation.

---

## Security Practices for Contributors

Contributors should adhere to the following security standards:

- Do not introduce `unsafe` blocks in Rust unless accompanied by an explicit, verified safety rationale.
- Run `cargo audit` periodically to inspect third-party dependencies for known vulnerabilities:
  ```bash
  cargo install cargo-audit
  cargo audit
  ```
- Validate all inputs and boundary conditions when handling external files or system commands.
- Ensure that sensitive paths or tokens are never committed or logged.
