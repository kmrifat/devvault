import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sparkle on macOS (ADR-0007 §3): it never checks or installs on its own,
/// installs through its XPC launcher because the app is sandboxed, reads
/// the appcast of the latest published release, and the release tools are
/// the version the app ships.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// The value after `<key>name</key>` in a plist.
  String plistValue(String plist, String key) {
    final match = RegExp(
      '<key>$key</key>\\s*(<true/>|<false/>|<string>[^<]*</string>)',
    ).firstMatch(plist);
    expect(match, isNotNull, reason: key);
    return match![1]!;
  }

  test('no checks or installs of its own', () {
    final info = read('macos/Runner/Info.plist');
    expect(plistValue(info, 'SUEnableAutomaticChecks'), '<false/>');
    expect(plistValue(info, 'SUAllowsAutomaticUpdates'), '<false/>');
    expect(plistValue(info, 'SUAutomaticallyUpdate'), '<false/>');
    expect(plistValue(info, 'SUEnableInstallerLauncherService'), '<true/>');
    expect(
      plistValue(info, 'SUFeedURL'),
      '<string>\$(SPARKLE_FEED_URL)</string>',
    );
    expect(
      plistValue(info, 'SUPublicEDKey'),
      '<string>\$(SPARKLE_PUBLIC_ED_KEY)</string>',
    );
  });

  test('the feed is the latest published release’s appcast', () {
    expect(
      read('macos/Runner/Configs/AppInfo.xcconfig'),
      contains(
        'SPARKLE_FEED_URL = https:/\$()/github.com/kmrifat/devvault/'
        'releases/latest/download/appcast.xml',
      ),
    );
  });

  test('the sandbox lets the installer launcher in', () {
    for (final path in [
      'macos/Runner/Release.entitlements',
      'macos/Runner/DebugProfile.entitlements',
    ]) {
      final entitlements = read(path);
      expect(
        entitlements,
        matches(
          RegExp(
            r'temporary-exception\.mach-lookup\.global-name</key>\s*<array>\s*'
            r'<string>\$\(PRODUCT_BUNDLE_IDENTIFIER\)-spks</string>\s*'
            r'<string>\$\(PRODUCT_BUNDLE_IDENTIFIER\)-spki</string>\s*</array>',
          ),
        ),
        reason: path,
      );
    }
  });

  test('the release tools are the version the app ships', () {
    final pod = RegExp(r"pod 'Sparkle', '([\d.]+)'")
        .firstMatch(read('macos/Podfile'))![1];
    final tools = RegExp(r'sparkle_version=([\d.]+)')
        .firstMatch(read('tool/release/macos_appcast.sh'))![1];
    expect(tools, pod);
    expect(read('macos/Podfile.lock'), contains('Sparkle ($pod)'));
  });
}
