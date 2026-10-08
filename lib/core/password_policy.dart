/// What DevVault asks of a master password, and a rough strength hint.
///
/// The choice is the user's: the only rule is [minLength]. Argon2id makes
/// each guess slow, but the master password is still the only thing between
/// a stolen bucket and the vault, so anything shorter than
/// [recommendedLength] gets a [warning] (it doesn't block). The strength
/// hint is deliberately simple and labelled as an estimate; it never claims
/// more than it knows.
abstract final class PasswordPolicy {
  static const int minLength = 4;

  /// Below this, the password is allowed but called weak.
  static const int recommendedLength = 12;

  /// Why [password] can't be used, or `null` if it can.
  static String? problem(String password) {
    if (password.isEmpty) return 'Enter a master password';
    if (password.runes.length < minLength) {
      return 'Use at least $minLength characters';
    }
    return null;
  }

  /// A warning for an allowed but short [password], or `null`.
  static String? warning(String password) {
    final length = password.runes.length;
    if (length < minLength || length >= recommendedLength) return null;
    return shortWarning;
  }

  static const shortWarning =
      'Short passwords are easier to guess. $recommendedLength or more '
      'characters is much safer.';

  /// Why [confirmation] doesn't confirm [password], or `null`.
  static String? mismatch(String password, String confirmation) =>
      confirmation == password ? null : "The passwords don't match";

  static PasswordStrength strength(String password) {
    final length = password.runes.length;
    if (length < minLength) return PasswordStrength.tooShort;
    if (length < recommendedLength) return PasswordStrength.weak;
    final words = password
        .split(RegExp(r'[\s\-_.]+'))
        .where((w) => w.length >= 3)
        .length;
    final classes = [
      RegExp('[a-z]'),
      RegExp('[A-Z]'),
      RegExp('[0-9]'),
      RegExp(r'[^a-zA-Z0-9]'),
    ].where((r) => r.hasMatch(password)).length;
    if (length >= 20 || (words >= 4 && length >= 16)) {
      return PasswordStrength.strong;
    }
    if (length >= 16 || classes >= 3) return PasswordStrength.good;
    return PasswordStrength.fair;
  }
}

enum PasswordStrength {
  tooShort('Too short', 0.1),
  weak('Weak', 0.25),
  fair('Fair', 0.4),
  good('Good', 0.7),
  strong('Strong', 1);

  const PasswordStrength(this.label, this.meter);

  final String label;

  /// How full the meter is, 0–1.
  final double meter;
}
