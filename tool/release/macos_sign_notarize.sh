#!/usr/bin/env bash
# Signs DevVault.app with a Developer ID, wraps it in a DMG, notarizes the
# DMG with Apple and staples the ticket (P4-09). Run after
# `flutter build macos --release`, on a macOS runner.
#
# Needs (see docs/release.md):
#   MACOS_CERT_P12_BASE64   Developer ID Application certificate + key, .p12, base64
#   MACOS_CERT_PASSWORD     its password
#   MACOS_PROVISION_PROFILE_BASE64
#                           Developer ID provisioning profile for the app, base64
#   APPLE_TEAM_ID           10-character Team ID
#   APPLE_ID                Apple ID used for notarization
#   APPLE_APP_PASSWORD      an app-specific password for that Apple ID
#
# Writes DevVault-macos.dmg in the current directory.
set -euo pipefail

app="build/macos/Build/Products/Release/DevVault.app"
dmg="DevVault-macos.dmg"
keychain="$RUNNER_TEMP/devvault-signing.keychain-db"
keychain_password="$(openssl rand -base64 24)"
entitlements="$RUNNER_TEMP/devvault-release.entitlements"
profile="$RUNNER_TEMP/devvault.provisionprofile"
profile_plist="$RUNNER_TEMP/devvault-profile.plist"

cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -f "$RUNNER_TEMP/devvault-cert.p12" "$entitlements" "$profile" \
    "$profile_plist"
}
trap cleanup EXIT

# The sandbox entitlements with Xcode's variables filled in: the Sparkle
# mach-lookup exceptions name the bundle id (ADR-0007 §3).
bundle_id=com.binarycastle.devvault
sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$bundle_id/g" \
  macos/Runner/Release.entitlements > "$entitlements"
if grep -qF -- "\$(" "$entitlements"; then
  echo "Unexpanded variable in the entitlements:" >&2
  grep -F -- "\$(" "$entitlements" >&2
  exit 1
fi

# Touch ID (SPEC §9.1) keeps the vault key in the data protection keychain,
# which only a build with an application identifier and a keychain access
# group can use. On macOS those entitlements must be authorised by an
# embedded provisioning profile, or the app won't launch. Without them the
# app runs but Touch ID can't be turned on, so a release stops here.
if [[ -z "${MACOS_PROVISION_PROFILE_BASE64:-}" ]]; then
  echo "MACOS_PROVISION_PROFILE_BASE64 is not set (docs/release.md)." >&2
  exit 1
fi
printf '%s' "$MACOS_PROVISION_PROFILE_BASE64" | base64 --decode > "$profile"
security cms -D -i "$profile" > "$profile_plist"
plist() { /usr/libexec/PlistBuddy -c "$1" "$2"; }
app_id="$APPLE_TEAM_ID.$bundle_id"
profile_app_id="$(plist 'Print :Entitlements:com.apple.application-identifier' "$profile_plist")"
if [[ "$profile_app_id" != "$app_id" ]]; then
  echo "The provisioning profile is for $profile_app_id, not $app_id." >&2
  exit 1
fi
# Developer ID profiles run on any Mac; a development one lists devices.
if [[ "$(plist 'Print :ProvisionsAllDevices' "$profile_plist" 2>/dev/null)" != true ]]; then
  echo "The provisioning profile isn't a Developer ID one." >&2
  exit 1
fi
plist "Add :com.apple.application-identifier string $app_id" "$entitlements"
plist "Add :com.apple.developer.team-identifier string $APPLE_TEAM_ID" "$entitlements"
plist "Add :keychain-access-groups array" "$entitlements"
plist "Add :keychain-access-groups:0 string $app_id" "$entitlements"

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

# Inside out. Sparkle's own helpers first, as its docs list them, never
# with --deep: the installer and downloader XPC services (the downloader
# keeps its entitlements), Autoupdate and Updater.app.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$sparkle/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
sign "$sparkle/Autoupdate"
sign "$sparkle/Updater.app"
# Then every framework and dylib (Flutter, plugins, Sparkle, libsodium from
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
cp "$profile" "$app/Contents/embedded.provisionprofile"
sign --entitlements "$entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
if ! codesign -d --entitlements - --xml "$app" 2>/dev/null \
  | grep -qF "<string>$app_id</string>"; then
  echo "The signed app is missing its keychain entitlements." >&2
  exit 1
fi

# The DMG is what users download (the drag-to-Applications window);
# notarizing it covers the app inside.
tool/release/macos_dmg.sh "$app" "$dmg"
sign "$dmg"
xcrun notarytool submit "$dmg" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
