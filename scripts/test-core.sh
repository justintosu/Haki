#!/usr/bin/env bash
# Compiles Haki's pure-Foundation core (Haki/Core) together with the tests in
# Tests/CoreTests and runs them. Works on macOS (Xcode command line tools) and
# Linux (a swift.org toolchain); no Xcode project or simulator needed.
#
#   scripts/test-core.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build/core-tests}"
mkdir -p "$BUILD_DIR"

# Mirror the app target's Swift settings (Swift 5 mode, main-actor default
# isolation, approachable concurrency) so code that compiles here compiles there.
swiftc \
  -swift-version 5 \
  -default-isolation MainActor \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature MemberImportVisibility \
  -warnings-as-errors \
  -module-name HakiCoreTests \
  "$ROOT"/Haki/Core/*.swift \
  "$ROOT"/Tests/CoreTests/*.swift \
  -o "$BUILD_DIR/haki-core-tests"

"$BUILD_DIR/haki-core-tests"
