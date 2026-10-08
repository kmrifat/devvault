#!/usr/bin/env bash
# Compiles devvault-mcp (packages/devvault_mcp) to a native executable at
# $1 and signs it for the hardened runtime with macos/Runner/Helper.entitlements
# (ADR-0006). The macOS build runs it to embed the helper at
# DevVault.app/Contents/Helpers/devvault-mcp; it skips the compile when the
# helper is newer than its sources.
#
#   tool/build_mcp_helper.sh <output> [signing identity, default "-"]
set -euo pipefail

out="$1"
identity="${2:--}"
root="$(cd "$(dirname "$0")/.." && pwd)"
dart="${FLUTTER_ROOT:+$FLUTTER_ROOT/bin/}dart"
sources=("$root/packages/devvault_mcp" "$root/packages/agent_bridge")

stale=1
if [[ -f "$out" ]] && [[ -z "$(find "${sources[@]}" -name '*.dart' -newer "$out" -print -quit)" ]]; then
  stale=0
fi
if [[ "$stale" == 1 ]]; then
  mkdir -p "$(dirname "$out")"
  (cd "$root" && "$dart" compile exe packages/devvault_mcp/bin/devvault_mcp.dart -o "$out")
fi

codesign --force --options runtime --timestamp=none \
  --entitlements "$root/macos/Runner/Helper.entitlements" \
  --identifier com.binarycastle.devvault.mcp --sign "$identity" "$out"
