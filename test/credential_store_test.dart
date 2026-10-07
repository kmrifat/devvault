import 'package:devvault/core/shortcuts.dart';
import 'package:devvault/services/credential_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A keychain that isn't there (Linux without a Secret Service).
class NoKeychain implements CredentialStore {
  int calls = 0;

  @override
  Future<String?> read(String key) async {
    calls++;
    throw Exception('org.freedesktop.secrets was not provided');
  }

  @override
  Future<void> write(String key, String value) async {
    calls++;
    throw Exception('org.freedesktop.secrets was not provided');
  }

  @override
  Future<void> delete(String key) async {
    calls++;
    throw Exception('org.freedesktop.secrets was not provided');
  }
}

void main() {
  test('uses the keychain while it works', () async {
    final keychain = MemoryCredentialStore();
    final store = FallbackCredentialStore(keychain);
    await store.write('s3:v', 'keys');
    expect(keychain.values, {'s3:v': 'keys'});
    expect(await store.read('s3:v'), 'keys');
    await store.delete('s3:v');
    expect(keychain.values, isEmpty);
    expect(store.isDegraded, isFalse);
  });

  test('without a keychain, keeps keys in memory and says so', () async {
    final keychain = NoKeychain();
    final store = FallbackCredentialStore(keychain);
    await store.write('s3:v', 'keys');
    expect(store.isDegraded, isTrue);
    expect(await store.read('s3:v'), 'keys');
    await store.delete('s3:v');
    expect(await store.read('s3:v'), isNull);
    // Once degraded it stops knocking on the missing keychain.
    expect(keychain.calls, 1);
  });

  test('shortcuts read the platform’s way', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(shortcutLabel('R'), '⌘R');
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(shortcutLabel('R'), 'Ctrl+R');
    debugDefaultTargetPlatformOverride = null;
  });
}
