import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../core/password_policy.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';

/// Forgot the master password: unlock with the recovery key, then choose a
/// new password before the vault opens. Setting it rewrites `vault.json`
/// only; the recovery key keeps working.
class RecoverScreen extends ConsumerStatefulWidget {
  const RecoverScreen({super.key});

  @override
  ConsumerState<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends ConsumerState<RecoverScreen> {
  final _recoveryKey = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _keyError;
  bool _busy = false;
  bool _submitted = false;

  @override
  void dispose() {
    for (final c in [_recoveryKey, _password, _confirm]) {
      c
        ..clear()
        ..dispose();
    }
    super.dispose();
  }

  Future<void> _unlockWithKey() async {
    if (_busy || _recoveryKey.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _keyError = null;
    });
    try {
      await ref
          .read(vaultSessionProvider.notifier)
          .unlockWithRecovery(_recoveryKey.text);
      _recoveryKey.clear();
      ref.read(passwordResetPendingProvider.notifier).require();
    } on RecoveryKeyFormatException catch (e) {
      _keyError = switch (e.kind) {
        RecoveryKeyProblem.invalidCharacter =>
          'Character ${e.position} isn\'t part of a recovery key',
        RecoveryKeyProblem.wrongLength =>
          'A recovery key has 14 groups of 4 characters',
        RecoveryKeyProblem.checksum =>
          'This recovery key has a typo. Check each group.',
      };
    } on WrongRecoveryKey {
      _keyError = "This recovery key doesn't belong to this vault";
    } on VaultKeyMismatch {
      _keyError =
          "vault.json was changed outside DevVault, so it isn't safe to open";
    } on Object {
      _keyError = "Couldn't read the vault on this device";
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _passwordError =>
      _submitted ? PasswordPolicy.problem(_password.text) : null;
  String? get _confirmError => _submitted && _passwordError == null
      ? PasswordPolicy.mismatch(_password.text, _confirm.text)
      : null;

  Future<void> _setPassword() async {
    setState(() => _submitted = true);
    if (PasswordPolicy.problem(_password.text) != null ||
        PasswordPolicy.mismatch(_password.text, _confirm.text) != null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(vaultSessionProvider.notifier)
          .changePassword(_password.text);
      ref.read(passwordResetPendingProvider.notifier).done();
      if (!mounted) return;
      BCToast.show(
        context,
        const BCToastData(
          title: 'New master password set',
          description: 'Your recovery key still works too.',
          variant: BCToastVariant.success,
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      BCToast.show(
        context,
        const BCToastData(
          title: "Couldn't save the new password",
          description: 'The old one still works. Try again.',
          variant: BCToastVariant.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final unlocked = ref.watch(vaultSessionProvider) is Unlocked;

    return Scaffold(
      backgroundColor: bc.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BCSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: unlocked ? _newPassword(context) : _enterKey(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _enterKey(BuildContext context) {
    final bc = context.bcTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.lifeBuoy, size: 32, color: bc.accent),
        const SizedBox(height: BCSpacing.md),
        const BCText('Use your recovery key', type: BCTextType.h2),
        const SizedBox(height: BCSpacing.sm),
        const BCText(
          'Type the 56-character key from your recovery kit. Case, spaces '
          'and dashes don\'t matter.',
          color: BCTextColor.muted,
        ),
        const SizedBox(height: BCSpacing.lg),
        BCTextField(
          isInvalid: _keyError != null,
          isDisabled: _busy,
          children: [
            const BCTextFieldLabel('Recovery key'),
            BCTextFieldInput(
              controller: _recoveryKey,
              hintText: 'XXXX-XXXX-XXXX-…',
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              maxLines: 2,
              minLines: 2,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _unlockWithKey(),
            ),
            if (_keyError != null) BCTextFieldError(_keyError!),
          ],
        ),
        const SizedBox(height: BCSpacing.md),
        BCButton(
          fullWidth: true,
          isDisabled: _busy || _recoveryKey.text.trim().isEmpty,
          onPressed: _unlockWithKey,
          startContent: _busy ? const BCSpinner(size: BCSpinnerSize.sm) : null,
          child: Text(_busy ? 'Checking…' : 'Continue'),
        ),
        const SizedBox(height: BCSpacing.md),
        Center(
          child: BCLinkButton(
            onPressed: () => context.go(Routes.unlock),
            child: const Text('Back to unlock'),
          ),
        ),
      ],
    );
  }

  Widget _newPassword(BuildContext context) {
    final bc = context.bcTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.keyRound, size: 32, color: bc.success),
        const SizedBox(height: BCSpacing.md),
        const BCText('Choose a new master password', type: BCTextType.h2),
        const SizedBox(height: BCSpacing.sm),
        const BCText(
          'Your recovery key worked. Set a new password to finish; the '
          'vault opens right after.',
          color: BCTextColor.muted,
        ),
        const SizedBox(height: BCSpacing.lg),
        PasswordField(
          label: 'New master password',
          controller: _password,
          autofocus: true,
          isDisabled: _busy,
          error: _passwordError,
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
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _setPassword(),
        ),
        const SizedBox(height: BCSpacing.lg),
        BCButton(
          fullWidth: true,
          isDisabled: _busy,
          onPressed: _setPassword,
          startContent: _busy ? const BCSpinner(size: BCSpinnerSize.sm) : null,
          child: Text(_busy ? 'Saving…' : 'Set password and open vault'),
        ),
      ],
    );
  }
}
