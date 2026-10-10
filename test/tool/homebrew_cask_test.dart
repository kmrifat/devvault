@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tool/release/homebrew_cask.sh (P6-06), which publish.yml commits to
/// kmrifat/homebrew-tap.
void main() {
  final sha = 'ab' * 32;

  ProcessResult cask(List<String> args) =>
      Process.runSync('bash', ['tool/release/homebrew_cask.sh', ...args]);

  test('points at the release’s notarized DMG', () {
    final result = cask(['1.2.0', sha, 'false']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final rb = result.stdout as String;
    expect(rb, contains('version "1.2.0"'));
    expect(rb, contains('sha256 "$sha"'));
    expect(
      rb,
      contains(
        'url "https://github.com/kmrifat/devvault/releases/download/'
        'v#{version}/DevVault-macos.dmg"',
      ),
    );
    expect(rb, contains('depends_on macos: ">= :monterey"'));
    expect(rb, isNot(contains('auto_updates')));
  });

  test('auto_updates only when the app updates itself', () {
    expect(cask(['1.2.0', sha, 'true']).stdout, contains('auto_updates true'));
  });

  test('never zaps the vaults', () {
    expect(
      cask(['1.2.0', sha, 'true']).stdout,
      isNot(matches(RegExp(r'^\s*zap\b', multiLine: true))),
    );
  });

  test('refuses what isn’t a version or a SHA-256', () {
    for (final args in [
      ['v1.2.0', sha, 'true'],
      ['1.2', sha, 'true'],
      ['1.2.0', 'abc', 'true'],
      ['1.2.0', sha, 'yes'],
    ]) {
      expect(cask(args).exitCode, isNot(0), reason: '$args');
    }
  });
}
