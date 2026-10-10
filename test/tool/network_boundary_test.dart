import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The update check: the one file in the app allowed an HTTP client.
const updateCheck = 'lib/services/updates.dart';

/// DevVault talks to the network in two places: the user's own bucket,
/// through `packages/vault_s3`, and, on desktop and only once the user
/// agrees, GitHub's latest-release API, from `lib/services/updates.dart`
/// (ADR-0007). Nothing else in the app or its packages may open a
/// connection. The AI agent bridge (`packages/agent_bridge`, P5) opens
/// sockets, but only Unix domain sockets on this machine.
void main() {
  final network = RegExp(
    r'''package:(http|dio|web_socket_channel|url_launcher)/|'''
    r'''\b(HttpClient|RawSocket|Socket|SecureSocket|WebSocket)\b''',
  );

  test('only vault_s3 opens network connections', () {
    final offenders = <String>[];
    for (final root in [
      Directory('lib'),
      ...Directory('packages').listSync(),
    ]) {
      if (root is! Directory ||
          root.path.endsWith('vault_s3') ||
          root.path.endsWith('agent_bridge')) {
        continue;
      }
      final lib = root.path == 'lib' ? root : Directory('${root.path}/lib');
      if (!lib.existsSync()) continue;
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') || file.path == updateCheck) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (network.hasMatch(lines[i])) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the agent bridge opens Unix domain sockets only', () {
    final lib = Directory('packages/agent_bridge/lib');
    final source = [
      for (final file in lib.listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart')) file.readAsStringSync(),
    ].join('\n');
    // Every address it makes is a Unix domain socket path…
    final addresses = RegExp(r'InternetAddress\(').allMatches(source).length;
    final unix = RegExp(
      r'InternetAddress\(\s*\w+,\s*type: InternetAddressType\.unix\s*,?\s*\)',
    ).allMatches(source).length;
    expect(addresses, greaterThan(0));
    expect(unix, addresses);
    // …and it never looks up, or binds to, an internet address.
    expect(
      source,
      isNot(
        matches(
          RegExp(
            r'InternetAddress\.(loopback|any|lookup)|'
            r'HttpClient|SecureSocket|WebSocket|RawSocket|package:http/',
          ),
        ),
      ),
    );
  });

  test('the update check asks GitHub for the latest release, nothing else', () {
    final source = File(updateCheck).readAsStringSync();
    // One request, a GET, to one URL…
    expect(
      RegExp(r'_client\s*\.\s*(\w+)\(').allMatches(source).map((m) => m[1]),
      unorderedEquals(['get', 'close']),
    );
    expect(source, matches(RegExp(r'\.get\(\s*latestUrl,')));
    // …built from fixed parts: api.github.com and this repository.
    expect(
      RegExp(r"Uri\.https\(\s*'([^']+)'").allMatches(source).map((m) => m[1]),
      unorderedEquals(['github.com', 'api.github.com']),
    );
    expect(source, contains("'/repos/\$releaseRepo/releases/latest'"));
    expect(source, contains("const releaseRepo = 'kmrifat/devvault';"));
    // No sockets of its own.
    expect(
      source,
      isNot(matches(RegExp(r'\b(HttpClient|RawSocket|Socket|WebSocket)\b'))),
    );
  });

  test('only vault_s3 depends on an HTTP client', () {
    final pubspecs = [
      for (final dir in Directory('packages').listSync().whereType<Directory>())
        if (!dir.path.endsWith('vault_s3')) File('${dir.path}/pubspec.yaml'),
    ];
    for (final pubspec in pubspecs.where((f) => f.existsSync())) {
      expect(
        pubspec.readAsStringSync(),
        isNot(
          matches(
            RegExp(r'^\s+(http|dio|web_socket_channel):', multiLine: true),
          ),
        ),
        reason: pubspec.path,
      );
    }
    // The app itself: only for the update check (ADR-0007).
    final app = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(
        r'^\s+(http|dio|web_socket_channel):',
        multiLine: true,
      ).allMatches(app).map((m) => m[1]),
      ['http'],
    );
  });
}
