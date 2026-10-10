#!/usr/bin/env bash
# Prints the Homebrew cask for a published release (ADR-0007 §7, P6-06).
# publish.yml commits it to kmrifat/homebrew-tap as Casks/devvault.rb, so
# `brew install --cask kmrifat/tap/devvault` installs the notarized DMG.
#
#   homebrew_cask.sh <version> <dmg-sha256> <auto-updates: true|false>
#
# auto_updates is true only when the release carries an appcast, i.e. the
# app updates itself with Sparkle; then `brew upgrade` leaves it to the app.
set -euo pipefail

version="$1"
sha256="$2"
auto_updates="$3"

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a version like 1.2.0, got '$version'." >&2
  exit 1
fi
if ! [[ "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Expected a SHA-256, got '$sha256'." >&2
  exit 1
fi
case "$auto_updates" in
  true) auto_line="  auto_updates true"$'\n' ;;
  false) auto_line="" ;;
  *) echo "auto-updates must be true or false." >&2; exit 1 ;;
esac

cat <<RUBY
cask "devvault" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/kmrifat/devvault/releases/download/v#{version}/DevVault-macos.dmg"
  name "DevVault"
  desc "Local-first, end-to-end encrypted vault for developer credential files"
  homepage "https://github.com/kmrifat/devvault"

  livecheck do
    url :url
    strategy :github_latest
  end

${auto_line}  depends_on macos: ">= :monterey"

  app "DevVault.app"

  # No zap stanza: the app's container holds the user's encrypted vaults,
  # and \`brew uninstall --zap\` must never be the way they disappear.
end
RUBY
