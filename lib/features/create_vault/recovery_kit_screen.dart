import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import '../../services/recovery_kit.dart';
import 'recovery_kit_card.dart';
import 'setup_layout.dart';

/// Design frame D02: the new vault's recovery key, shown once.
///
/// The user can save it as a PDF or text file, print it, or copy it
/// (cleared from the clipboard after 30 s), and has to confirm they kept it
/// before the vault opens.
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

  void _continue() =>
      ref.read(pendingRecoveryKeyProvider.notifier).confirmSaved();

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;

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
          RecoveryKitCard(
            kit: RecoveryKitDocument(
              recoveryKey: _keyText,
              vaultId: _vaultId,
              created: ref.read(clockProvider)(),
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
