#!/usr/bin/env bash
# Regenerates the app icon for every platform from test/tool/app_icon_test.dart.
#
#   tool/app_icon.sh
#
# 1. Renders the 1024 px sources into assets/icon/.
# 2. flutter_launcher_icons expands them for iOS, Android, macOS and Windows.
# 3. The macOS 16 and 32 px slots get the simple mark, which stays legible
#    there; the Linux window icon is the macOS tile at 256 px.
# Needs macOS (sips).
set -euo pipefail
cd "$(dirname "$0")/.."

DEVVAULT_RENDER_ICON=1 flutter test test/tool/app_icon_test.dart
dart run flutter_launcher_icons

macos=macos/Runner/Assets.xcassets/AppIcon.appiconset
sips -z 16 16 assets/icon/app_icon_macos_small.png --out "$macos/app_icon_16.png" >/dev/null
sips -z 32 32 assets/icon/app_icon_macos_small.png --out "$macos/app_icon_32.png" >/dev/null
sips -z 256 256 assets/icon/app_icon_macos.png --out linux/runner/resources/app_icon.png >/dev/null
