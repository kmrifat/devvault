import 'package:devvault/core/password_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires at least 4 characters', () {
    expect(PasswordPolicy.problem(''), isNotNull);
    expect(PasswordPolicy.problem('abc'), 'Use at least 4 characters');
    expect(PasswordPolicy.problem('abcd'), isNull);
    // Counted in characters, not UTF-16 units: 4 emoji are 4 characters.
    expect(PasswordPolicy.problem('🔑' * 4), isNull);
    expect(PasswordPolicy.problem('🔑' * 3), isNotNull);
  });

  test('a short password is allowed, with a warning', () {
    expect(PasswordPolicy.warning('abc'), isNull, reason: 'not allowed at all');
    expect(PasswordPolicy.warning('abcd'), contains('easier to guess'));
    expect(PasswordPolicy.warning('elevenchars'), isNotNull);
    expect(PasswordPolicy.warning('twelve chars'), isNull);
  });

  test('confirmation has to match exactly', () {
    expect(PasswordPolicy.mismatch('abc', 'abc'), isNull);
    expect(PasswordPolicy.mismatch('abc', 'abc '), isNotNull);
  });

  test('strength grows with length and passphrases', () {
    expect(PasswordPolicy.strength('abc'), PasswordStrength.tooShort);
    expect(PasswordPolicy.strength('short'), PasswordStrength.weak);
    expect(PasswordPolicy.strength('elevenchars'), PasswordStrength.weak);
    expect(PasswordPolicy.strength('abcdefghijkl'), PasswordStrength.fair);
    expect(PasswordPolicy.strength('Abcdefghij1!'), PasswordStrength.good);
    expect(PasswordPolicy.strength('abcdefghijklmnop'), PasswordStrength.good);
    expect(
      PasswordPolicy.strength('correct horse battery staple'),
      PasswordStrength.strong,
    );
  });
}
