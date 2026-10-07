import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import 'setup_layout.dart';

/// Design frame D02: the new vault's recovery key, shown once.
///
/// The user can copy it (cleared from the clipboard after 30 s) or save it
/// as a text file, and has to confirm they kept it before the vault opens.
/// Confirming wipes the key from memory; it is never shown again.
class RecoveryKitScreen extends ConsumerStatefulWidget {
  const RecoveryKitScreen({super.key});

  @override
  ConsumerState<RecoveryKitScreen> createState() => _RecoveryKitScreenState();
}

class _RecoveryKitScreenState extends ConsumerState<RecoveryKitScreen> {
  bool _saved = false;

  /// Read once: the pending key is wiped as soon as the user confirms.
  late final String _keyText =
      ref.read(pendingRecoveryKeyProvider)?.toDisplayString() ?? '';

  String get _vaultId => switch (ref.read(vaultSessionProvider)) {
    Unlocked(:final vault) => vault.vaultId,
    _ => '',
  };

  Future<void> _copy() async {
    await ref.read(clipboardGuardProvider).copySecret(_keyText);
    if (!mounted) return;
    BCToast.show(
      context,
      const BCToastData(
        title: 'Recovery key copied',
        description: 'It clears from the clipboard in 30 seconds.',
        variant: BCToastVariant.success,
      ),
    );
  }

  Future<void> _saveFile() async {
    final created = DateFormat.yMMMMd().format(ref.read(clockProvider)());
    final text =
        'DevVault recovery key\n'
        '\n'
        '$_keyText\n'
        '\n'
        'Vault: $_vaultId\n'
        'Created: $created\n'
        '\n'
        'This key unlocks your vault and lets you set a new master password.\n'
        'Keep it offline: a password manager, a printed copy or a safe.\n'
        "Don't store it inside DevVault itself.\n";
    final saved = await ref
        .read(fileSaverProvider)
        .save(
          fileName: 'DevVault Recovery Key.txt',
          bytes: Uint8List.fromList(utf8.encode(text)),
          mimeType: 'text/plain',
        );
    if (!mounted || !saved) return;
    BCToast.show(
      context,
      const BCToastData(
        title: 'Recovery kit saved',
        variant: BCToastVariant.success,
      ),
    );
  }

  void _continue() =>
      ref.read(pendingRecoveryKeyProvider.notifier).confirmSaved();

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final groups = _keyText.split('-');

    return SetupLayout(
      step: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BCText(
            'Step 2 of 3',
            type: BCTextType.bodySm,
            weight: BCTextWeight.semibold,
            style: TextStyle(color: bc.accent),
          ),
          const SizedBox(height: BCSpacing.sm),
          const BCText('Save your recovery key', type: BCTextType.h2),
          const SizedBox(height: BCSpacing.sm),
          const BCText(
            'Shown once. It unlocks the vault and lets you set a new '
            'password. Without it, a forgotten password means the vault is '
            'gone.',
            color: BCTextColor.muted,
          ),
          const SizedBox(height: BCSpacing.lg),
          BCCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: BCSpacing.md,
              children: [
                Row(
                  spacing: BCSpacing.sm,
                  children: [
                    Icon(LucideIcons.keyRound, size: 16, color: bc.accent),
                    const BCText(
                      'Recovery key',
                      type: BCTextType.bodySm,
                      weight: BCTextWeight.semibold,
                    ),
                    const Spacer(),
                    Flexible(
                      child: MonoText(
                        'vault $_vaultId',
                        middleEllipsis: true,
                        style: TextStyle(
                          fontSize: BCTypography.sizeXs,
                          color: bc.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                Semantics(
                  label: 'Recovery key',
                  value: _keyText,
                  child: SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: bc.background,
                        shape: BCShapes.continuous(BCRadius.xxl),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: _KeyGrid(groups: groups),
                      ),
                    ),
                  ),
                ),
                Wrap(
                  spacing: BCSpacing.sm,
                  runSpacing: BCSpacing.sm,
                  children: [
                    BCButton(
                      size: BCButtonSize.sm,
                      onPressed: _saveFile,
                      startContent: const Icon(LucideIcons.fileDown, size: 15),
                      child: const Text('Save as text file'),
                    ),
                    BCButton(
                      size: BCButtonSize.sm,
                      variant: BCButtonVariant.secondary,
                      onPressed: _copy,
                      startContent: const Icon(LucideIcons.copy, size: 15),
                      child: const Text('Copy'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: BCSpacing.md),
          DecoratedBox(
            decoration: ShapeDecoration(
              color: bc.warningSoft,
              shape: BCShapes.continuous(BCRadius.xxl),
            ),
            child: Padding(
              padding: const EdgeInsets.all(BCSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: BCSpacing.sm,
                children: [
                  Icon(LucideIcons.triangleAlert, size: 17, color: bc.warning),
                  Expanded(
                    child: Text(
                      'Keep it offline: a password manager, a printed copy or '
                      "a safe. Don't store it inside this vault.",
                      style: BCTypography.textSm.copyWith(
                        color: bc.warningSoftForeground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: BCSpacing.xl),
          LayoutBuilder(
            builder: (context, constraints) {
              final confirm = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BCCheckbox(
                    isSelected: _saved,
                    onSelectedChange: (value) => setState(() => _saved = value),
                  ),
                  const SizedBox(width: BCSpacing.sm),
                  Flexible(
                    child: GestureDetector(
                      onTap: () => setState(() => _saved = !_saved),
                      child: const BCText("I've saved my recovery key"),
                    ),
                  ),
                ],
              );
              final button = BCButton(
                isDisabled: !_saved,
                fullWidth: constraints.maxWidth < 480,
                onPressed: _saved ? _continue : null,
                endContent: const Icon(LucideIcons.arrowRight, size: 16),
                child: const Text('Continue'),
              );
              return constraints.maxWidth < 480
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: BCSpacing.md,
                      children: [confirm, button],
                    )
                  : Row(
                      children: [
                        Expanded(child: confirm),
                        button,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

/// The 14 groups of the recovery key: two rows of 7 when there's room,
/// rows of 4 on a phone.
class _KeyGrid extends StatelessWidget {
  const _KeyGrid({required this.groups});

  final List<String> groups;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 460 ? 7 : 4;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            for (var i = 0; i < groups.length; i += perRow)
              MonoText(
                groups.skip(i).take(perRow).join('  '),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: BCTypography.medium,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        );
      },
    );
  }
}
