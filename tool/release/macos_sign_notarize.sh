#!/usr/bin/env bash
# Signs DevVault.app with a Developer ID, wraps it in a DMG, notarizes the
# DMG with Apple and staples the ticket (P4-09). Run after
# `flutter build macos --release`, on a macOS runner.
#
# Needs (see docs/release.md):
#   MACOS_CERT_P12_BASE64   Developer ID Application certificate + key, .p12, base64
#   MACOS_CERT_PASSWORD     its password
#   APPLE_TEAM_ID           10-character Team ID
#   APPLE_ID                Apple ID used for notarization
#   APPLE_APP_PASSWORD      an app-specific password for that Apple ID
#
# Writes DevVault-macos.dmg in the current directory.
set -euo pipefail

app="build/macos/Build/Products/Release/DevVault.app"
dmg="DevVault-macos.dmg"
entitlements="macos/Runner/Release.entitlements"
keychain="$RUNNER_TEMP/devvault-signing.keychain-db"
keychain_password="$(openssl rand -base64 24)"

cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -f "$RUNNER_TEMP/devvault-cert.p12"
}
trap cleanup EXIT

# A throwaway keychain holding only the signing identity.
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
printf '%s' "$MACOS_CERT_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/devvault-cert.p12"
security import "$RUNNER_TEMP/devvault-cert.p12" -k "$keychain" \
  -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "$keychain_password" "$keychain" >/dev/null
# Put it first in the search list, keeping the user's own keychains.
existing=()
while IFS= read -r line; do
  line="${line//\"/}"
  existing+=("$(echo "$line" | xargs)")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$keychain" "${existing[@]}"

identity="$(security find-identity -v -p codesigning "$keychain" \
  | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"/\1/')"
if [[ -z "$identity" ]]; then
  echo "No 'Developer ID Application' identity in the certificate." >&2
  exit 1
fi
echo "Signing as: $identity"

sign() {
  codesign --force --timestamp --options runtime --keychain "$keychain" \
    --sign "$identity" "$@"
}

# Inside out: every framework and dylib (Flutter, plugins, libsodium from
# native assets), the agent helper, then the app itself with its sandbox
# entitlements.
while IFS= read -r -d '' nested; do
  sign "$nested"
done < <(find "$app/Contents/Frameworks" \( -name '*.framework' -o -name '*.dylib' \) -print0)
# devvault-mcp (P5-09): not sandboxed, with the three code-signing
# exceptions a Dart executable needs under the hardened runtime.
sign --entitlements macos/Runner/Helper.entitlements \
  --identifier com.binarycastle.devvault.mcp \
  "$app/Contents/Helpers/devvault-mcp"
sign --entitlements "$entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

# The DMG is what users download; notarizing it covers the app inside.
rm -f "$dmg"
hdiutil create -volname DevVault -srcfolder "$app" -ov -format UDZO "$dmg"
sign "$dmg"
xcrun notarytool submit "$dmg" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
