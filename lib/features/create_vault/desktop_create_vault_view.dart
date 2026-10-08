import '../../core/password_policy.dart';
import '../../shared/desktop_ui.dart';

/// Design frame N01: choose the master password for a new vault, on
/// desktop. The password and its confirmation, a strength estimate, the
/// Argon2id settings it will be stretched with, and the way to join a vault
/// that already exists instead.
///
/// Only renders: [CreateVaultScreen] owns the passwords and creates the
/// vault.
class DesktopCreateVaultView extends StatelessWidget {
  const DesktopCreateVaultView({
    super.key,
    required this.password,
    required this.passwordError,
    required this.confirm,
    required this.confirmError,
    required this.confirmFocus,
    required this.busy,
    required this.mib,
    required this.passes,
    required this.onChanged,
    required this.onCreate,
    required this.onJoin,
  });

  final TextEditingController password;
  final String? passwordError;
  final TextEditingController confirm;
  final String? confirmError;
  final FocusNode confirmFocus;
  final bool busy;

  /// The Argon2id settings the vault will use.
  final int mib;
  final int passes;

  final VoidCallback onChanged;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final passwordError = this.passwordError;
    final confirmError = this.confirmError;
    return DesktopLockWindow(
      step: 'Step 1 of 3',
      title: 'Create a master password',
      message:
          "You'll type this to unlock DevVault. No one can reset or recover "
          "it for you. Next you'll get a recovery key as a backup.",
      footer: Row(
        children: [
          DesktopLink(
            label: 'Join a vault from your bucket…',
            onPressed: busy ? null : onJoin,
          ),
          const Spacer(),
          DesktopButton(
            label: busy ? 'Creating vault…' : 'Continue',
            kind: DesktopButtonKind.primary,
            size: DesktopButtonSize.large,
            onPressed: busy ? null : onCreate,
          ),
        ],
      ),
      children: [
        Padding(
          // The form is narrower than the text above it, as in the frame.
          padding: const EdgeInsetsDirectional.only(end: 46),
          child: DesktopForm(
            children: [
              DesktopFormRow(
                label: 'Password',
                child: Semantics(
                  label: 'Master password',
                  child: DesktopTextField(
                    controller: password,
                    obscureText: true,
                    autofocus: true,
                    enabled: !busy,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => confirmFocus.requestFocus(),
                  ),
                ),
              ),
              if (passwordError != null)
                DesktopFieldMessage(
                  passwordError,
                  indent: DesktopMetrics.formLabelWidth,
                )
              else
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start:
                        DesktopMetrics.formLabelWidth +
                        DesktopMetrics.formLabelGap,
                  ),
                  child: _StrengthMeter(
                    strength: PasswordPolicy.strength(password.text),
                    length: password.text.length,
                  ),
                ),
              DesktopFormRow(
                label: 'Confirm',
                child: Semantics(
                  label: 'Confirm password',
                  child: DesktopTextField(
                    controller: confirm,
                    focusNode: confirmFocus,
                    obscureText: true,
                    enabled: !busy,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onCreate(),
                  ),
                ),
              ),
              if (confirmError != null)
                DesktopFieldMessage(
                  confirmError,
                  indent: DesktopMetrics.formLabelWidth,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        DesktopLockBox(
          child: Row(
            spacing: 8,
            children: [
              const DesktopIcon(DesktopSymbol.keyDerivation, size: 14),
              Expanded(
                child: Text(
                  'Key derivation: Argon2id, $mib MiB, '
                  '$passes ${passes == 1 ? 'pass' : 'passes'}. '
                  'Your password never leaves this device.',
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize + 1,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Four segments that fill with the estimate, and what it says. Kept the
/// same height when empty so the form doesn't jump.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength, required this.length});

  final PasswordStrength strength;
  final int length;

  static const _segments = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final filled = length == 0
        ? 0
        : switch (strength) {
            PasswordStrength.tooShort || PasswordStrength.weak => 1,
            PasswordStrength.fair => 2,
            PasswordStrength.good => 3,
            PasswordStrength.strong => 4,
          };
    final tint = switch (strength) {
      PasswordStrength.tooShort || PasswordStrength.weak => colors.danger,
      PasswordStrength.fair => colors.warning,
      PasswordStrength.good || PasswordStrength.strong => colors.success,
    };
    final small = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        Row(
          spacing: 4,
          children: [
            for (var i = 0; i < _segments; i++)
              Expanded(
                child: SizedBox(
                  height: 4,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: i < filled ? tint : colors.innerSeparator,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 14,
          child: length == 0
              ? null
              : Row(
                  spacing: 6,
                  children: [
                    // In text colour: the success green is under 4.5:1 as
                    // small text on the lock window.
                    Text(
                      strength.label,
                      style: small.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                    Text('$length characters · an estimate', style: small),
                  ],
                ),
        ),
        // Allowed, but said plainly.
        if (strength == PasswordStrength.weak)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 5,
            children: [
              DesktopIcon(
                DesktopSymbol.warning,
                size: 12,
                color: colors.warning,
              ),
              Expanded(child: Text(PasswordPolicy.shortWarning, style: small)),
            ],
          ),
      ],
    );
  }
}
