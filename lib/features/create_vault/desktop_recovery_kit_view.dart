import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/recovery_kit.dart';
import '../../shared/desktop_ui.dart';
import 'recovery_kit_card.dart' show RecoveryKitActions;

/// Design frame N02: the new vault's recovery key on desktop, shown once,
/// with Save PDF…, Print…, Save as Text… and Copy (through the clipboard
/// guard), and the confirmation that opens the vault.
///
/// [RecoveryKitScreen] holds the key and the confirmation; this view only
/// renders them and runs the save, print and copy actions.
class DesktopRecoveryKitView extends ConsumerStatefulWidget {
  const DesktopRecoveryKitView({
    super.key,
    required this.kit,
    required this.saved,
    required this.onSavedChanged,
    required this.onContinue,
  });

  final RecoveryKitDocument kit;
  final bool saved;
  final ValueChanged<bool> onSavedChanged;
  final VoidCallback onContinue;

  @override
  ConsumerState<DesktopRecoveryKitView> createState() =>
      _DesktopRecoveryKitViewState();
}

class _DesktopRecoveryKitViewState extends ConsumerState<DesktopRecoveryKitView>
    with RecoveryKitActions {
  @override
  RecoveryKitDocument get kit => widget.kit;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final groups = kit.groups;
    final mono = AppText.mono(context, fontSize: 15).copyWith(
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: colors.text,
    );
    return DesktopLockWindow(
      step: 'Step 2 of 3',
      mark: DesktopLockMark.recoveryKey,
      title: 'Save your recovery key',
      message:
          'If you forget your master password, this key is the only way '
          "back in. It's shown once. Keep it somewhere safe, outside "
          'DevVault.',
      footer: Row(
        children: [
          const Spacer(),
          DesktopButton(
            label: 'Open Vault',
            kind: DesktopButtonKind.primary,
            size: DesktopButtonSize.large,
            onPressed: widget.saved ? widget.onContinue : null,
          ),
        ],
      ),
      children: [
        Semantics(
          label: 'Recovery key',
          value: kit.recoveryKey,
          child: DesktopLockBox(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  // Two rows of seven groups, as the key is written down.
                  for (var i = 0; i < groups.length; i += 7)
                    Text(groups.skip(i).take(7).join('-'), style: mono),
                  Text(
                    'vault ${kit.vaultId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(
                      context,
                      fontSize: DesktopMetrics.secondarySize,
                    ).copyWith(color: colors.secondaryText),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DesktopButton(
              label: 'Save PDF…',
              icon: DesktopSymbol.savePdf,
              size: DesktopButtonSize.large,
              onPressed: kitBusy ? null : saveKitPdf,
            ),
            DesktopButton(
              label: 'Print…',
              icon: DesktopSymbol.printer,
              size: DesktopButtonSize.large,
              onPressed: kitBusy ? null : printKit,
            ),
            DesktopButton(
              label: 'Save as Text…',
              icon: DesktopSymbol.saveText,
              size: DesktopButtonSize.large,
              onPressed: saveKitText,
            ),
            DesktopButton(
              label: 'Copy',
              icon: DesktopSymbol.copy,
              size: DesktopButtonSize.large,
              onPressed: copyKit,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: DesktopCheckbox(
            value: widget.saved,
            onChanged: widget.onSavedChanged,
            label: "I've saved my recovery key somewhere safe",
          ),
        ),
      ],
    );
  }
}
