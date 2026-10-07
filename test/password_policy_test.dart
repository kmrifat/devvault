import 'package:devvault/core/password_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires at least 12 characters', () {
    expect(PasswordPolicy.problem(''), isNotNull);
    expect(PasswordPolicy.problem('elevenchars'), isNotNull);
    expect(PasswordPolicy.problem('twelve chars'), isNull);
    // Counted in characters, not UTF-16 units: 12 emoji are 12 characters.
    expect(PasswordPolicy.problem('🔑' * 12), isNull);
    expect(PasswordPolicy.problem('🔑' * 6), isNotNull);
  });

  test('confirmation has to match exactly', () {
    expect(PasswordPolicy.mismatch('abc', 'abc'), isNull);
    expect(PasswordPolicy.mismatch('abc', 'abc '), isNotNull);
  });

  test('strength grows with length and passphrases', () {
    expect(PasswordPolicy.strength('short'), PasswordStrength.tooShort);
    expect(PasswordPolicy.strength('abcdefghijkl'), PasswordStrength.fair);
    expect(PasswordPolicy.strength('Abcdefghij1!'), PasswordStrength.good);
    expect(PasswordPolicy.strength('abcdefghijklmnop'), PasswordStrength.good);
    expect(
      PasswordPolicy.strength('correct horse battery staple'),
      PasswordStrength.strong,
    );
  });
}
