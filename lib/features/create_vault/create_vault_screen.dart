import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/password_policy.dart';
import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import 'setup_layout.dart';

/// Design frame D01: choose the master password for a new vault.
class CreateVaultScreen extends ConsumerStatefulWidget {
  const CreateVaultScreen({super.key});

  @override
  ConsumerState<CreateVaultScreen> createState() => _CreateVaultScreenState();
}

class _CreateVaultScreenState extends ConsumerState<CreateVaultScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _confirmFocus = FocusNode();
  bool _busy = false;
  bool _submitted = false;

  @override
  void dispose() {
    // The controllers hold the password; clear them before letting go.
    _password
      ..clear()
      ..dispose();
    _confirm
      ..clear()
      ..dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  String? get _passwordError =>
      _submitted ? PasswordPolicy.problem(_password.text) : null;

  String? get _confirmError => _submitted && _passwordError == null
      ? PasswordPolicy.mismatch(_password.text, _confirm.text)
      : null;

  Future<void> _create() async {
    setState(() => _submitted = true);
    if (PasswordPolicy.problem(_password.text) != null ||
        PasswordPolicy.mismatch(_password.text, _confirm.text) != null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final recoveryKey = await ref
          .read(vaultSessionProvider.notifier)
          .create(_password.text);
      // Holding the key sends the router to the recovery kit (D02).
      ref.read(pendingRecoveryKeyProvider.notifier).hold(recoveryKey);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      BCToast.show(
        context,
        const BCToastData(
          title: "Couldn't create the vault",
          description:
              'Nothing was saved. Check free disk space and try again.',
          variant: BCToastVariant.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = PasswordPolicy.strength(_password.text);
    final mib = ref.watch(kdfMemLimitProvider) ~/ (1024 * 1024);
    final passes = ref.watch(kdfOpsLimitProvider);

    return SetupLayout(
      step: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BCText(
            'Step 1 of 3',
            type: BCTextType.bodySm,
            weight: BCTextWeight.semibold,
            style: TextStyle(color: context.bcTheme.accent),
          ),
          const SizedBox(height: BCSpacing.sm),
          const BCText('Create a master password', type: BCTextType.h2),
          const SizedBox(height: BCSpacing.sm),
          const BCText(
            "You'll type this to unlock DevVault. It can't be reset or "
            "recovered by anyone else. Next you'll get a recovery key as a "
            'backup.',
            color: BCTextColor.muted,
          ),
          const SizedBox(height: BCSpacing.lg),
          PasswordField(
            label: 'Master password',
            controller: _password,
            autofocus: true,
            isDisabled: _busy,
            error: _passwordError,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirmFocus.requestFocus(),
          ),
          const SizedBox(height: BCSpacing.sm),
          _StrengthMeter(strength: strength, length: _password.text.length),
          const SizedBox(height: BCSpacing.md),
          PasswordField(
            label: 'Confirm password',
            controller: _confirm,
            focusNode: _confirmFocus,
            isDisabled: _busy,
            error: _confirmError,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: BCSpacing.lg),
          BCCard(
            child: Row(
              spacing: BCSpacing.sm,
              children: [
                Icon(LucideIcons.cpu, size: 16, color: context.bcTheme.muted),
                Expanded(
                  child: BCText(
                    'Key derivation: Argon2id, $mib MiB, '
                    '$passes ${passes == 1 ? 'pass' : 'passes'}. '
                    'Your password never leaves this device.',
                    type: BCTextType.bodySm,
                    color: BCTextColor.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: BCSpacing.xl),
          Align(
            alignment: Alignment.centerRight,
            child: BCButton(
              onPressed: _busy ? null : _create,
              isDisabled: _busy,
              startContent: _busy
                  ? const BCSpinner(size: BCSpinnerSize.sm)
                  : null,
              endContent: _busy
                  ? null
                  : const Icon(LucideIcons.arrowRight, size: 16),
              child: Text(_busy ? 'Creating vault…' : 'Continue'),
            ),
          ),
          const SizedBox(height: BCSpacing.lg),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: BCSpacing.xs,
              children: [
                const BCText(
                  'Already use DevVault elsewhere?',
                  type: BCTextType.bodySm,
                  color: BCTextColor.muted,
                ),
                Semantics(
                  link: true,
                  child: BCLinkButton(
                    onPressed: _busy
                        ? null
                        : () => context.go(Routes.joinVault),
                    child: const Text('Join from your bucket'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength, required this.length});

  final PasswordStrength strength;
  final int length;

  @override
  Widget build(BuildContext context) {
    if (length == 0) return const SizedBox(height: 20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: BCSpacing.xs,
      children: [
        BCProgress(
          value: strength.meter,
          size: BCProgressSize.sm,
          color: switch (strength) {
            PasswordStrength.tooShort => BCProgressColor.danger,
            PasswordStrength.fair => BCProgressColor.warning,
            PasswordStrength.good ||
            PasswordStrength.strong => BCProgressColor.success,
          },
        ),
        Row(
          children: [
            BCText(
              strength.label,
              type: BCTextType.bodyXs,
              weight: BCTextWeight.semibold,
            ),
            const Spacer(),
            BCText(
              '$length characters · an estimate',
              type: BCTextType.bodyXs,
              color: BCTextColor.muted,
            ),
          ],
        ),
      ],
    );
  }
}
