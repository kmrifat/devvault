#!/usr/bin/env bash
# Packages the Linux release bundle as an AppImage (P2-13). Run after
# `flutter build linux --release`. GTK 3 and libsecret come from the host,
# as for the tarball.
#
# appimagetool is pinned to a release and checked against the SHA-256 that
# GitHub records for it. It fetches the AppImage runtime while packaging.
#
# The AppImage carries update information (ADR-0007 §5, P6-03): tools such
# as AppImageUpdate fetch the latest published release's .zsync and
# download only the blocks that changed. appimagetool writes the .zsync
# beside the AppImage with `zsyncmake` (apt package `zsync`).
set -euo pipefail

name=devvault-linux-x64.AppImage
update_info="gh-releases-zsync|kmrifat|devvault|latest|$name.zsync"

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

command -v zsyncmake >/dev/null || {
  echo "zsyncmake is missing: install the zsync package" >&2
  exit 1
}

# No FUSE on the runners: let the tool unpack itself.
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" \
  --updateinformation "$update_info" "$appdir" "$name"

# Check what the AppImage says about where its updates come from.
embedded="$(APPIMAGE_EXTRACT_AND_RUN=1 "./$name" --appimage-updateinformation)"
if [ "$embedded" != "$update_info" ]; then
  echo "Update information is '$embedded', expected '$update_info'" >&2
  exit 1
fi
test -s "$name.zsync" || { echo "No $name.zsync was written" >&2; exit 1; }
echo "Wrote $name and $name.zsync ($embedded)"
