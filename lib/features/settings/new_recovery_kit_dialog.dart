import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/providers.dart';
import '../../data/sync_controller.dart';
import '../../data/sync_setup.dart';
import '../../data/vault_session.dart';
import '../../services/recovery_kit.dart';
import '../../shared/ui.dart';
import '../create_vault/recovery_kit_card.dart';

/// What the dialog does with the master password.
enum RecoveryKeyAction {
  /// A new recovery key only (P4-05): `vault.json` is rewritten, the old
  /// key stops working.
  newKit,

  /// Rotate the vault key (P4-08, SPEC §9): everything is re-encrypted
  /// under a new key, with a new recovery key.
  rotate,
}

/// Makes a new recovery kit (P4-05). The old key can't be shown again (it
/// was never stored), so this issues a new one and the old one stops
/// working.
///
/// The master password is asked for first. The new key is shown once, in
/// the same card as on first run (PDF, print, text, copy), and wiped from
/// memory when the dialog closes.
Future<void> showNewRecoveryKitDialog(BuildContext context) =>
    BCDialog.show<void>(
      context,
      barrierDismissible: false,
      builder: (_) =>
          const BCDialogContent(width: 640, child: NewRecoveryKitDialog()),
    );

/// Rotates the vault key (P4-08): after a suspected leak of the vault key
/// or a recovery key. Asks for the master password, re-encrypts every
/// item and file, shows the new recovery key once, then syncs.
Future<void> showRotateVaultKeyDialog(BuildContext context) =>
    BCDialog.show<void>(
      context,
      barrierDismissible: false,
      builder: (_) => const BCDialogContent(
        width: 640,
        child: NewRecoveryKitDialog(action: RecoveryKeyAction.rotate),
      ),
    );

/// A rotation was interrupted (a crash, a quit) and this unlock finished
/// it: its new recovery key has never been shown, and the old one no
/// longer works. Shows [key] once and disposes it.
Future<void> showFinishedRotationDialog(
  BuildContext context,
  RecoveryKey key,
) => BCDialog.show<void>(
  context,
  barrierDismissible: false,
  builder: (_) => BCDialogContent(
    width: 640,
    child: NewRecoveryKitDialog(
      action: RecoveryKeyAction.rotate,
      finished: key,
    ),
  ),
);

class NewRecoveryKitDialog extends ConsumerStatefulWidget {
  const NewRecoveryKitDialog({
    super.key,
    this.action = RecoveryKeyAction.newKit,
    this.finished,
  });

  final RecoveryKeyAction action;

  /// A key already made (an interrupted rotation finished on unlock): skip
  /// the password and show it.
  final RecoveryKey? finished;

  @override
  ConsumerState<NewRecoveryKitDialog> createState() =>
      _NewRecoveryKitDialogState();
}

class _NewRecoveryKitDialogState extends ConsumerState<NewRecoveryKitDialog> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _saved = false;

  /// The new key, once made. Wiped on close.
  late RecoveryKey? _key = widget.finished;
  late String? _keyText = widget.finished?.toDisplayString();

  bool get _rotate => widget.action == RecoveryKeyAction.rotate;

  @override
  void dispose() {
    _password.dispose();
    _key?.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your master password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(vaultSessionProvider.notifier);
    try {
      if (!await session.checkPassword(_password.text)) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = "That isn't your master password";
          });
        }
        return;
      }
      final key = _rotate
          ? await session.rotateVaultKey(_password.text)
          : await session.replaceRecoveryKey();
      if (_rotate && ref.read(syncSetupProvider) != null) {
        // Push the re-encrypted vault now; other devices pause until they
        // adopt the new key with the master password.
        unawaited(ref.read(syncControllerProvider.notifier).syncNow());
      }
      if (!mounted) {
        key.dispose();
        return;
      }
      _password.clear();
      setState(() {
        _busy = false;
        _key = key;
        _keyText = key.toDisplayString();
      });
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _rotate
              ? "Couldn't finish the rotation. Unlock again with your master "
                    'password to finish it.'
              : "Couldn't make a new key. Your old one still works.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyText = _keyText;
    return keyText == null ? _ask(context) : _show(context, keyText);
  }

  Widget _ask(BuildContext context) {
    final bc = context.bcTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BCDialogTitle(_rotate ? 'Rotate vault key' : 'New recovery kit'),
        const SizedBox(height: BCSpacing.xs),
        BCDialogDescription(
          _rotate
              ? 'Re-encrypts every item and file under a new vault key, with '
                    'a new recovery key. Do this if you think the vault key '
                    'or a recovery key leaked. Your master password stays '
                    'the same.'
              : 'Your recovery key can’t be shown again, so this makes a new '
                    'one. The old key stops working as soon as it’s made.',
        ),
        const SizedBox(height: BCSpacing.lg),
        PasswordField(
          label: 'Master password',
          controller: _password,
          autofocus: true,
          error: _error,
          isDisabled: _busy,
          onSubmitted: (_) => _make(),
        ),
        const SizedBox(height: BCSpacing.md),
        DecoratedBox(
          decoration: ShapeDecoration(
            color: bc.warningSoft,
            shape: BCShapes.continuous(BCRadius.xl),
          ),
          child: Padding(
            padding: const EdgeInsets.all(BCSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: BCSpacing.sm,
              children: [
                Icon(LucideIcons.triangleAlert, size: 17, color: bc.warning),
                Expanded(
                  child: BCText(
                    _rotate
                        ? 'Other devices on this vault pause syncing until '
                              'you unlock them with your master password. '
                              'Your old recovery key stops working.'
                        : 'Other devices on this vault switch to the new key '
                              'once they sync. Destroy any printed copy of '
                              'the old one.',
                    type: BCTextType.bodySm,
                    style: TextStyle(color: bc.warningSoftForeground),
                  ),
                ),
              ],
            ),
          ),
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
              onPressed: _make,
              startContent: _busy
                  ? const BCSpinner(size: BCSpinnerSize.sm)
                  : null,
              child: Text(
                _busy && _rotate
                    ? 'Re-encrypting…'
                    : _rotate
                    ? 'Rotate key'
                    : 'Make new key',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _show(BuildContext context, String keyText) {
    final vault = switch (ref.read(vaultSessionProvider)) {
      Unlocked(:final vault) => vault.vaultId,
      _ => '',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BCDialogTitle(
          widget.finished != null
              ? 'Key rotation finished'
              : 'Your new recovery key',
        ),
        const SizedBox(height: BCSpacing.xs),
        BCDialogDescription(
          widget.finished != null
              ? 'A vault key rotation was interrupted and has now finished. '
                    'This is its new recovery key, shown once: the old one '
                    'no longer works.'
              : _rotate
              ? 'The vault key was rotated. Shown once: save it now, the old '
                    'recovery key no longer works.'
              : 'Shown once. Save it now: the old key no longer works.',
        ),
        const SizedBox(height: BCSpacing.lg),
        RecoveryKitCard(
          kit: RecoveryKitDocument(
            recoveryKey: keyText,
            vaultId: vault,
            created: ref.read(clockProvider)(),
          ),
        ),
        const SizedBox(height: BCSpacing.lg),
        Row(
          children: [
            Expanded(
              child: BCControlField(
                label: "I've saved the new key",
                control: BCCheckbox(
                  isSelected: _saved,
                  onSelectedChange: (v) => setState(() => _saved = v),
                ),
                onPressed: () => setState(() => _saved = !_saved),
              ),
            ),
            BCButton(
              isDisabled: !_saved,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }
}
