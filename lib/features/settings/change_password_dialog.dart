import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/password_policy.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart';
import '../../shared/ui.dart';

/// Asks for the current master password and a new one, then rewraps the
/// vault key. Only `vault.json` changes; every item stays as it is.
///
/// A sheet on desktop, a bc_ui dialog on phones.
Future<void> showChangePasswordDialog(BuildContext context) {
  if (DesktopTheme.maybeOf(context) != null) {
    return showDesktopSheet<void>(
      context,
      builder: (_) => const ChangePasswordForm(),
    );
  }
  return BCDialog.show<void>(
    context,
    builder: (_) => const BCDialogContent(
      width: 460,
      showCloseButton: true,
      child: ChangePasswordForm(),
    ),
  );
}

class ChangePasswordForm extends ConsumerStatefulWidget {
  const ChangePasswordForm({super.key});

  @override
  ConsumerState<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends ConsumerState<ChangePasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _currentError;
  String? _nextError;
  String? _confirmError;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_current, _next, _confirm]) {
      c
        ..clear()
        ..dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final nextProblem = PasswordPolicy.problem(_next.text);
    setState(() {
      _currentError = _current.text.isEmpty
          ? 'Enter your current password'
          : null;
      _nextError =
          nextProblem ??
          (_next.text == _current.text
              ? 'Choose a password you aren’t using now'
              : null);
      _confirmError = _nextError == null
          ? PasswordPolicy.mismatch(_next.text, _confirm.text)
          : null;
    });
    if (_currentError != null || _nextError != null || _confirmError != null) {
      return;
    }
    setState(() => _busy = true);
    final session = ref.read(vaultSessionProvider.notifier);
    try {
      if (!await session.checkPassword(_current.text)) {
        if (mounted) {
          setState(() {
            _busy = false;
            _currentError = "That isn't your current password";
          });
        }
        return;
      }
      await session.changePassword(_next.text);
      if (!mounted) return;
      // The toast lives above the dialog, so it outlasts it.
      showAppToast(
        context,
        const BCToastData(
          title: 'Master password changed',
          description: 'Use the new one next time you unlock.',
          variant: BCToastVariant.success,
        ),
      );
      Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _nextError = "Couldn't change the password. Nothing was changed.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = PasswordPolicy.strength(_next.text);
    final hint = _next.text.isEmpty
        ? 'At least ${PasswordPolicy.minLength} characters; '
              '${PasswordPolicy.recommendedLength} or more is much safer'
        : strength == PasswordStrength.weak
        ? 'Strength (estimate): Weak. ${PasswordPolicy.shortWarning}'
        : 'Strength (estimate): ${strength.label}';
    if (DesktopTheme.maybeOf(context) != null) return _desktop(hint);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BCDialogTitle('Change master password'),
        const SizedBox(height: BCSpacing.xs),
        const BCDialogDescription(
          'Your recovery key keeps working. Other devices ask for the new '
          'password after they sync.',
        ),
        const SizedBox(height: BCSpacing.lg),
        PasswordField(
          label: 'Current password',
          controller: _current,
          autofocus: true,
          isDisabled: _busy,
          error: _currentError,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: BCSpacing.md),
        PasswordField(
          label: 'New password',
          controller: _next,
          isDisabled: _busy,
          error: _nextError,
          description: hint,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: BCSpacing.md),
        PasswordField(
          label: 'Confirm new password',
          controller: _confirm,
          isDisabled: _busy,
          error: _confirmError,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: BCSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: BCSpacing.sm,
          children: [
            BCButton(
              variant: BCButtonVariant.secondary,
              isDisabled: _busy,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            BCButton(
              isDisabled: _busy,
              onPressed: _submit,
              startContent: _busy
                  ? const BCSpinner(size: BCSpinnerSize.sm)
                  : null,
              child: Text(_busy ? 'Changing…' : 'Change password'),
            ),
          ],
        ),
      ],
    );
  }

  /// Desktop: a sheet with a classic form, one secure field per row.
  Widget _desktop(String hint) {
    Widget field(
      String label,
      TextEditingController controller, {
      bool autofocus = false,
      ValueChanged<String>? onChanged,
    }) => Semantics(
      label: label,
      textField: true,
      child: DesktopTextField(
        controller: controller,
        obscureText: true,
        autofocus: autofocus,
        enabled: !_busy,
        onChanged: onChanged,
        onSubmitted: (_) => _submit(),
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: DesktopSheet(
        width: 480,
        title: 'Change master password',
        message:
            'Your recovery key keeps working. Other devices ask for the new '
            'password after they sync.',
        actions: [
          if (_busy) const DesktopProgress(semanticLabel: 'Changing'),
          DesktopButton(
            label: 'Cancel',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
          DesktopButton(
            label: _busy ? 'Changing…' : 'Change Password',
            kind: DesktopButtonKind.primary,
            onPressed: _busy ? null : _submit,
          ),
        ],
        child: DesktopForm(
          labelWidth: 170,
          children: [
            DesktopFormRow(
              label: 'Current password',
              error: _currentError,
              child: field('Current password', _current, autofocus: true),
            ),
            DesktopFormRow(
              label: 'New password',
              note: hint,
              error: _nextError,
              child: field(
                'New password',
                _next,
                onChanged: (_) => setState(() {}),
              ),
            ),
            DesktopFormRow(
              label: 'Confirm new password',
              error: _confirmError,
              child: field('Confirm new password', _confirm),
            ),
          ],
        ),
      ),
    );
  }
}
