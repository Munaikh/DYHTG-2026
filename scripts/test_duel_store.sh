#!/bin/bash
# Compile and exercise the production store without a simulator or network.
set -euo pipefail
TASK_REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/arena-duel-store.XXXXXX")"
trap 'rm -rf "$TASK_BUILD_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="$TASK_BUILD_DIR/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_BUILD_DIR/module-cache"
xcrun swiftc -disable-sandbox -swift-version 6 -parse-as-library \
  -emit-library -emit-module -module-name AlgorithmArenaCore \
  -emit-module-path "$TASK_BUILD_DIR/AlgorithmArenaCore.swiftmodule" \
  "$TASK_REPO_ROOT"/Packages/AlgorithmArenaCore/Sources/AlgorithmArenaCore/*.swift \
  -o "$TASK_BUILD_DIR/libAlgorithmArenaCore.dylib"
xcrun swiftc -disable-sandbox -swift-version 6 -parse-as-library \
  -I "$TASK_BUILD_DIR" -L "$TASK_BUILD_DIR" -lAlgorithmArenaCore \
  -Xlinker -rpath -Xlinker "$TASK_BUILD_DIR" \
  "$TASK_REPO_ROOT/DYHTG-2026/Duel/DuelStore.swift" \
  "$TASK_REPO_ROOT/DYHTG-2026/Match/ActionError.swift" \
  "$TASK_REPO_ROOT/DYHTG-2026/Match/DisplayText.swift" \
  "$TASK_REPO_ROOT/scripts/test_duel_store.swift" \
  -o "$TASK_BUILD_DIR/test-duel-store"
"$TASK_BUILD_DIR/test-duel-store"
