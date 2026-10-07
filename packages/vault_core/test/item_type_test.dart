import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  test('wire names are unique and round-trip', () {
    final names = ItemType.values.map((t) => t.wireName).toSet();
    expect(names, hasLength(ItemType.values.length));
    for (final type in ItemType.values) {
      expect(ItemType.fromWireName(type.wireName), type);
    }
  });

  test('wire names are the format strings from the plan', () {
    expect(ItemType.appleAuthKey.wireName, 'apple_auth_key');
    expect(ItemType.androidKeystore.wireName, 'android_keystore');
    expect(ItemType.genericSecret.wireName, 'generic_secret');
  });

  test('unknown types and sources are null, not guessed', () {
    expect(ItemType.fromWireName('ssh_key'), isNull);
    expect(ExpirySource.fromWireName('inferred'), isNull);
    expect(ExpirySource.fromWireName('file'), ExpirySource.file);
    expect(ExpirySource.fromWireName('user'), ExpirySource.user);
  });
}
