# Changelog

## 0.5.0 (unreleased)

### Storage reporting

- Measure application footprints using allocated disk space, including associated files and applications in the user's Applications folder.
- Report Docker virtual disk allocation in Package Caches instead of virtual capacity, matching Docker Deep Inspection.

### Interface

- Redesign the Overview and File Catalog dashboards with clearer storage breakdowns and scan status.
- Improve responsive layouts, tool cards, controls, and selection states across storage and security tools.

### Fixes

- Prevent overlapping parent and child entries in the cleanup basket.
- Improve search filter parsing and folder navigation.
- Strengthen quarantine and restore handling, including associated files.

Requires macOS 15 or later and an Apple Silicon Mac.

The release remains a draft until its signed installer and update archive have been reviewed.
