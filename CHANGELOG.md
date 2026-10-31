# Changelog

All notable changes to Velora will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-10-31

### ⚠️ Breaking Changes
- **Architecture & OS Exclusivity**: Enforced strict macOS 15.0 (Sequoia) deployment target and Apple Silicon (`arm64`) architecture requirement. Intel (`x86_64`) architecture and pre-macOS 15 runtimes are no longer supported.

### ✨ Features
- **Sparkle 2 Auto-Updates**: Integrated Sparkle 2 update framework with Ed25519 cryptographic verification and automated appcast updates.
- **Interactive Global Search Flow**:
  - Expanded search query result limit to 1,000 matches.
  - Added adaptive capping badge indicating matched vs. rendered results.
  - Seamless jump and filter navigation from the search bar directly into Sunburst and Directory tables.
- **Background Task Interaction Gating**: Disabled navigation, search queries, and tool switches while catalog loading and directory scanning operations are active to prevent race conditions.
- **Branding & Visual Identity**: Integrated modernized app icon assets across app bundle, dock, DMG volume, and in-app headers.

### 🎨 UI & Design Enhancements
- **Velora Bloom Design Language**: Implemented new visual theme with refined colors, modern translucency, and jewel accents.
- **Inspector Layout**: Fixed inspector safe-area layout and edge-to-edge content clipping on macOS Sequoia.
- **Sidebar Ergonomics**: Streamlined navigation structure, embedded clean version indicator in sidebar footer, and mapped sidebar logo click to overview dashboard.

### 📦 Packaging, DMG & Distribution
- **Retina DMG Presentation**:
  - Normalized DMG background artwork to 144 DPI for 1:1 pixel-perfect Retina rendering in Finder.
  - Precisely aligned application and drop-target link coordinates.
  - Configured window dimensions to eliminate unwanted vertical/horizontal scrollbars.
- **Inside-Out Code Signing & Notarization**:
  - Hardened runtime signing across embedded frameworks (`Sparkle.framework`, XPC services, `Autoupdate`) and main executable.
  - Integrated automated Apple Notary Service submission, stapling, and Gatekeeper verification.

### 🧪 CI & Testing
- Optimized search latency test assertions for unoptimized debug builds.
- Upgraded CI runners and test matrices to macOS 15 Sequoia on Apple Silicon.

---

## [0.1.0] - 2026-10-19

### ✨ Initial Release
- Multi-threaded directory traversal engine with Rayon.
- Linear-time zero-allocation bottom-up storage rollup.
- Native SwiftUI polar sunburst visualization.
- In-memory regex and glob pattern search engine.
- macOS FSEvents real-time filesystem watcher.
- Safe staged cleanup with macOS Trash integration.
