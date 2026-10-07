import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  test('writes format version 1', () {
    expect(vaultFormatVersion, 1);
  });
}
