#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Velora Dev Watcher: End-to-End Live Reload Pipeline
# -----------------------------------------------------------------------------
# Watches Rust crates and Swift sources for changes, triggers selective
# incremental compilation, packages Velora.app, and relaunches the app.
#
# Requirements:
#   - cargo (Rust 1.75+)
#   - swift (Swift 5.9+ / Xcode 15+)
#   - fswatch (`brew install fswatch`)
# -----------------------------------------------------------------------------

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# -----------------------------------------------------------------------------
# 1. Prerequisite Verification
# -----------------------------------------------------------------------------
check_prerequisites() {
    local missing=0

    if ! command -v cargo >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: 'cargo' is required but not installed or not in PATH.${NC}"
        missing=1
    fi

    if ! command -v swift >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: 'swift' is required but not installed or not in PATH.${NC}"
        missing=1
    fi

    if ! command -v fswatch >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: 'fswatch' is required for filesystem monitoring.${NC}"
        echo -e "${YELLOW}   Install it via Homebrew:${NC} brew install fswatch"
        missing=1
    fi

    if [ "$missing" -ne 0 ]; then
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 2. Lifecycle: Application Process Management
# -----------------------------------------------------------------------------
terminate_running_app() {
    # Terminate running instance so executable file is unlocked
    if pgrep -x Velora >/dev/null 2>&1; then
        echo -e "${GRAY}Terminating previous Velora instance...${NC}"
        pkill -x Velora 2>/dev/null || true
        # Brief pause to ensure kernel releases process locks
        sleep 0.2
    fi
}

launch_app() {
    echo -e "${CYAN}🔄 Launching Velora.app...${NC}"
    open Velora.app
    echo -e "${GREEN}✨ Velora is running with latest changes.${NC}\n"
}

# -----------------------------------------------------------------------------
# 3. Build & Package Pipeline
# -----------------------------------------------------------------------------
build_and_package() {
    local rebuild_rust="$1"
    local rebuild_swift="$2"

    local start_time
    start_time=$(date +%s)

    # Step A: Compile Rust FFI if needed
    if [ "$rebuild_rust" = true ]; then
        echo -e "${BOLD}⚙️  [1/3] Compiling Rust core (velora-ffi)...${NC}"
        if ! cargo build -p velora-ffi; then
            echo -e "${RED}❌ Rust compilation failed. Preserving current running app.${NC}\n"
            return 1
        fi
    fi

    # Step B: Compile Swift app if needed (or if Rust was rebuilt)
    if [ "$rebuild_swift" = true ] || [ "$rebuild_rust" = true ]; then
        echo -e "${BOLD}⚡️ [2/3] Compiling Swift app (arm64)...${NC}"
        if ! (cd swift && swift build --arch arm64); then
            echo -e "${RED}❌ Swift compilation failed. Preserving current running app.${NC}\n"
            return 1
        fi
    fi

    # Compilation succeeded! Safely terminate old instance before updating the bundle
    terminate_running_app

    # Step C: Bundle into Velora.app
    echo -e "${BOLD}📦 [3/3] Packaging Velora.app...${NC}"
    if ! ./bundle_app.sh; then
        echo -e "${RED}❌ Packaging failed.${NC}\n"
        return 1
    fi

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    echo -e "${GREEN}✅ Build completed in ${elapsed}s.${NC}"

    launch_app
    return 0
}

# -----------------------------------------------------------------------------
# 4. Watch Loop
# -----------------------------------------------------------------------------
start_watcher() {
    echo -e "=================================================="
    echo -e "${BOLD}${CYAN}  Velora Live Dev Environment${NC}"
    echo -e "=================================================="
    echo -e "${GRAY}Monitoring:${NC}"
    echo -e "  • crates/ (*.rs, Cargo.toml)"
    echo -e "  • swift/Sources/ (*.swift)"
    echo -e "  • swift/Package.swift"
    echo -e "  • assets/"
    echo -e "${GRAY}Press Ctrl+C to stop.${NC}\n"

    # Initial build and launch
    echo -e "${CYAN}🚀 Performing initial startup build...${NC}"
    build_and_package true true || true

    echo -e "${BOLD}${GREEN}👀 Watching for changes...${NC}"

    # Use fswatch with batch-marker to debounce and classify changes
    fswatch -r \
        --latency 0.4 \
        --batch-marker="BATCH_END" \
        --exclude "/\." \
        --exclude "/target" \
        --exclude "/swift/\.build" \
        --exclude "/Velora\.app" \
        --exclude "/build" \
        crates swift/Sources swift/Package.swift assets Cargo.toml Cargo.lock | while read -r line; do
            
            if [ "$line" = "BATCH_END" ]; then
                if [ -n "${PENDING_FILES:-}" ]; then
                    local rust_changed=false
                    local swift_changed=false

                    while IFS= read -r file; do
                        [ -z "$file" ] && continue
                        case "$file" in
                            *.rs|*Cargo.toml|*Cargo.lock)
                                rust_changed=true
                                ;;
                            *.swift|*Package.swift)
                                swift_changed=true
                                ;;
                            *)
                                # Assets or other configs trigger at least swift re-link / bundle
                                swift_changed=true
                                ;;
                        esac
                    done <<< "$PENDING_FILES"

                    echo -e "\n${YELLOW}⚡️ Changes detected:${NC}"
                    if [ "$rust_changed" = true ]; then
                        echo -e "   • Rust core modified"
                    fi
                    if [ "$swift_changed" = true ]; then
                        echo -e "   • Swift / UI modified"
                    fi

                    build_and_package "$rust_changed" "$swift_changed" || true

                    PENDING_FILES=""
                    echo -e "${BOLD}${GREEN}👀 Watching for changes...${NC}"
                fi
            else
                PENDING_FILES="${PENDING_FILES:-}${line}"$'\n'
            fi
        done
}

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------
check_prerequisites
start_watcher
