#!/usr/bin/env bash
# Packages the Linux release bundle as an AppImage (P2-13). Run after
# `flutter build linux --release`. GTK 3 and libsecret come from the host,
# as for the tarball.
#
# appimagetool is pinned to a release and checked against the SHA-256 that
# GitHub records for it. It fetches the AppImage runtime while packaging.
set -euo pipefail

version=1.9.1
sha256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
tmp="${RUNNER_TEMP:-$(mktemp -d)}"
tool="$tmp/appimagetool-x86_64.AppImage"
curl -fsSL -o "$tool" \
  "https://github.com/AppImage/appimagetool/releases/download/$version/appimagetool-x86_64.AppImage"
echo "$sha256  $tool" | sha256sum -c -
chmod +x "$tool"

appdir="$tmp/DevVault.AppDir"
rm -rf "$appdir"
mkdir -p "$appdir/usr/lib/devvault"
cp -r build/linux/x64/release/bundle/. "$appdir/usr/lib/devvault/"

cat > "$appdir/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/devvault/devvault" "$@"
RUN
chmod +x "$appdir/AppRun"

cat > "$appdir/com.binarycastle.devvault.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=DevVault
Comment=End-to-end encrypted vault for developer credential files
Exec=devvault
Icon=com.binarycastle.devvault
Categories=Development;Utility;
Terminal=false
DESKTOP
cp linux/runner/resources/app_icon.png "$appdir/com.binarycastle.devvault.png"

# No FUSE on the runners: let the tool unpack itself.
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" "$appdir" devvault-linux-x64.AppImage
echo "Wrote devvault-linux-x64.AppImage"
