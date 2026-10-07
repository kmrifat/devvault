import 'dart:io';
import 'dart:typed_data';

import 'package:cred_parsers/cred_parsers.dart';
import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

ParseResult parse(String filename, [String? fixtureName]) =>
    CredentialParsers.standard().parse(
      ParseInput(filename: filename, bytes: fixture(fixtureName ?? filename)),
    );

void main() {
  test('reads the Key ID from the AuthKey_ filename', () {
    final result = parse('AuthKey_TESTKEY123.p8');
    expect(result.type, ItemType.appleAuthKey);
    expect(result.format, CredentialFormat.appleAuthKey);
    expect(result.facts[AppleAuthKeyParser.keyId]!.value, 'TESTKEY123');
    expect(result.facts[AppleAuthKeyParser.keyAlgorithm]!.value, 'EC P-256');
    expect(
      result.facts.values.every((f) => f.source == FieldSource.file),
      isTrue,
    );
    expect(result.warnings, isEmpty);
  });

  test('a full path still yields the Key ID', () {
    final result = parse(
      '/Users/me/Downloads/AuthKey_TESTKEY123.p8',
      'AuthKey_TESTKEY123.p8',
    );
    expect(result.facts[AppleAuthKeyParser.keyId]!.value, 'TESTKEY123');
  });

  test('a renamed key has no Key ID fact, never a guessed one', () {
    final result = parse('renamed-key.p8');
    expect(result.type, ItemType.appleAuthKey);
    expect(result.facts.keys, [AppleAuthKeyParser.keyAlgorithm]);
  });

  test('Key IDs that are not 10 upper-case characters are ignored', () {
    for (final name in [
      'AuthKey_SHORT.p8',
      'AuthKey_testkey123.p8',
      'AuthKey_TESTKEY1234.p8',
      'AuthKey_TESTKEY123 (1).p8',
    ]) {
      final result = parse(name, 'AuthKey_TESTKEY123.p8');
      expect(result.type, ItemType.appleAuthKey, reason: name);
      expect(result.facts[AppleAuthKeyParser.keyId], isNull, reason: name);
    }
  });

  test('never reports an expiry or the key material', () {
    final result = parse('AuthKey_TESTKEY123.p8');
    expect(result.expiresAt, isNull);
    final pem = String.fromCharCodes(fixture('AuthKey_TESTKEY123.p8'));
    final body = pem.split('\n')[1];
    for (final fact in result.facts.values) {
      expect(body, isNot(contains(fact.value)));
    }
    expect(result.toString(), isNot(contains(body)));
  });

  test('a key that is not EC P-256 falls back to a generic file', () {
    final result = parse('AuthKey_ED25519KEY.p8');
    expect(result.format, CredentialFormat.appleAuthKey);
    expect(result.isGeneric, isTrue);
    expect(result.facts, isEmpty);
    expect(result.warnings.single, contains('could not be read'));
  });

  test('a mangled key falls back to a generic file', () {
    final text = String.fromCharCodes(fixture('AuthKey_TESTKEY123.p8'));
    for (final broken in [
      text.replaceFirst('M', '!'),
      text.replaceFirst('-----END PRIVATE KEY-----', ''),
      '$text\n$text',
    ]) {
      final result = CredentialParsers.standard().parse(
        ParseInput(
          filename: 'AuthKey_TESTKEY123.p8',
          bytes: Uint8List.fromList(broken.codeUnits),
        ),
      );
      expect(result.isGeneric, isTrue);
      expect(result.facts, isEmpty);
    }
  });
}
