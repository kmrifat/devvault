#!/usr/bin/env bash
# Wraps DevVault.app in the disk image users download: a window with the
# app, an Applications link and an arrow between them, so installing is a
# drag (tool/release/dmg_settings.py). Signing and notarizing the DMG are
# the caller's (macos_sign_notarize.sh); the unsigned release path uses it
# as is.
#
#   tool/release/macos_dmg.sh <DevVault.app> <out.dmg>
#
# Needs macOS (tiffutil, hdiutil) and python3. dmgbuild writes the window
# layout itself, without scripting Finder, so it works on CI runners.
set -euo pipefail

app="$1"
dmg="$2"
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# dmgbuild in its own virtualenv: runner Pythons are externally managed.
python3 -m venv "$work/venv"
"$work/venv/bin/pip" install --quiet dmgbuild==1.6.7

# One TIFF with both resolutions, so the window is sharp on Retina.
tiffutil -cathidpicheck \
  "$root/assets/dmg/background.png" "$root/assets/dmg/background@2x.png" \
  -out "$work/background.tiff"

rm -f "$dmg"
"$work/venv/bin/dmgbuild" \
  -s "$root/tool/release/dmg_settings.py" \
  -D app="$app" \
  -D background="$work/background.tiff" \
  DevVault "$dmg"
