import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DevVault talks to one place on the network: the user's own bucket,
/// through `packages/vault_s3`. Nothing else in the app or its packages may
/// open a connection.
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
      if (root is! Directory || root.path.endsWith('vault_s3')) continue;
      final lib = root.path == 'lib' ? root : Directory('${root.path}/lib');
      if (!lib.existsSync()) continue;
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
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

  test('only vault_s3 depends on an HTTP client', () {
    final pubspecs = [
      File('pubspec.yaml'),
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
  });
}
