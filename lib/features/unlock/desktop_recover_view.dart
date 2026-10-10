import '../../shared/desktop_ui.dart';

/// Recovery on desktop, in the lock screens' style (N00): type the recovery
/// key, then choose a new master password before the vault opens.
///
/// Only renders: [RecoverScreen] owns the key, the passwords and what
/// happens to them.
class DesktopRecoverView extends StatelessWidget {
  const DesktopRecoverView({
    super.key,
    required this.unlocked,
    required this.recoveryKey,
    required this.keyError,
    required this.password,
    required this.passwordError,
    required this.confirm,
    required this.confirmError,
    required this.busy,
    required this.onChanged,
    required this.onUnlockWithKey,
    required this.onSetPassword,
    required this.onBack,
    required this.onStartOver,
  });

  /// The key worked: choose the new password.
  final bool unlocked;

  final TextEditingController recoveryKey;
  final String? keyError;
  final TextEditingController password;
  final String? passwordError;
  final TextEditingController confirm;
  final String? confirmError;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onUnlockWithKey;
  final VoidCallback onSetPassword;
  final VoidCallback onBack;

  /// The recovery key is lost too: erase the vault and start over.
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) =>
      unlocked ? _newPassword(context) : _enterKey(context);

  Widget _enterKey(BuildContext context) {
    final hasKey = recoveryKey.text.trim().isNotEmpty;
    return DesktopLockWindow(
      mark: DesktopLockMark.recoveryKey,
      title: 'Use your recovery key',
      message:
          'Type the 56-character key from your recovery kit. Case, spaces '
          "and dashes don't matter.",
      footer: Row(
        children: [
          DesktopLink(label: 'Back to unlock', onPressed: busy ? null : onBack),
          const Spacer(),
          DesktopButton(
            label: busy ? 'Checking…' : 'Continue',
            kind: DesktopButtonKind.primary,
            size: DesktopButtonSize.large,
            onPressed: busy || !hasKey ? null : onUnlockWithKey,
          ),
        ],
      ),
      children: [
        DesktopForm(
          labelWidth: _labelWidth,
          children: [
            DesktopFormRow(
              label: 'Recovery key',
              multiline: true,
              child: Semantics(
                label: 'Recovery key',
                // Wraps, so the whole key (69 characters with its dashes)
                // can be read back; Return still submits.
                child: DesktopTextField(
                  controller: recoveryKey,
                  placeholder: 'XXXX-XXXX-XXXX-…',
                  mono: true,
                  maxLines: 3,
                  minLines: 3,
                  autocorrect: false,
                  autofocus: true,
                  enabled: !busy,
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onUnlockWithKey(),
                ),
              ),
            ),
          ],
        ),
        if (keyError case final error?)
          DesktopFieldMessage(error, indent: _labelWidth),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: _labelWidth),
          child: Row(
            spacing: 2,
            children: [
              Text(
                'Lost the recovery key too?',
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize + 1,
                  color: context.desktopColors.secondaryText,
                ),
              ),
              DesktopLink(
                label: 'Start over…',
                onPressed: busy ? null : onStartOver,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _newPassword(BuildContext context) {
    return DesktopLockWindow(
      title: 'Choose a new master password',
      message:
          'Your recovery key worked. Set a new password to finish; the '
          'vault opens right after.',
      footer: Row(
        children: [
          const Spacer(),
          DesktopButton(
            label: busy ? 'Saving…' : 'Set password and open vault',
            kind: DesktopButtonKind.primary,
            size: DesktopButtonSize.large,
            onPressed: busy ? null : onSetPassword,
          ),
        ],
      ),
      children: [
        DesktopForm(
          labelWidth: _labelWidth,
          children: [
            DesktopFormRow(
              label: 'New password',
              child: Semantics(
                label: 'New master password',
                child: DesktopTextField(
                  controller: password,
                  obscureText: true,
                  autofocus: true,
                  enabled: !busy,
                  onChanged: (_) => onChanged(),
                ),
              ),
            ),
            if (passwordError case final error?)
              DesktopFieldMessage(error, indent: _labelWidth),
            DesktopFormRow(
              label: 'Confirm',
              child: Semantics(
                label: 'Confirm new password',
                child: DesktopTextField(
                  controller: confirm,
                  obscureText: true,
                  enabled: !busy,
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSetPassword(),
                ),
              ),
            ),
            if (confirmError case final error?)
              DesktopFieldMessage(error, indent: _labelWidth),
          ],
        ),
      ],
    );
  }

  static const double _labelWidth = 104;
}
