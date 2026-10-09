// P2-13: the real OS keychain keeps the sync keys across launches. CI runs
// it twice on Windows and Linux (desktop-checks.yml): once to write, then,
// in a new process, to read back and clean up.
//
//   flutter test integration_test/keyring_test.dart -d <device> \
//     --dart-define=KEYRING_PHASE=write --dart-define=KEYRING_VALUE=<v>
//   flutter test integration_test/keyring_test.dart -d <device> \
//     --dart-define=KEYRING_PHASE=read --dart-define=KEYRING_VALUE=<v>
//
// KEYRING_PHASE=both runs both in one process. Without KEYRING_PHASE the
// test is skipped: roundtrip.yml runs every integration test where no
// keychain daemon is running.
import 'package:devvault/services/credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _phase = String.fromEnvironment('KEYRING_PHASE');
const _value = String.fromEnvironment(
  'KEYRING_VALUE',
  defaultValue: 'devvault-keyring-check',
);

// Not a name DevVault itself uses, so the check never touches real keys.
const _key = 'devvault-ci-keyring-check';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the keychain stores a key', (tester) async {
    final store = FallbackCredentialStore(const SystemCredentialStore());
    await store.write(_key, _value);
    expect(await store.read(_key), _value);
    expect(store.isDegraded, isFalse, reason: 'the keychain call failed');
  }, skip: _phase != 'write' && _phase != 'both');

  testWidgets('a new process reads it back, and delete removes it', (
    tester,
  ) async {
    final store = FallbackCredentialStore(const SystemCredentialStore());
    expect(await store.read(_key), _value);
    expect(store.isDegraded, isFalse, reason: 'the keychain call failed');
    await store.delete(_key);
    expect(await const SystemCredentialStore().read(_key), isNull);
  }, skip: _phase != 'read' && _phase != 'both');
}
