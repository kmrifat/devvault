import '../../shared/desktop_ui.dart';
import 'start_over_screen.dart';

/// Start over on desktop, in the lock screens' style (N00): what gets
/// erased, what becomes of the bucket copy, and a field to type
/// [StartOverScreen.confirmWord] into before the destructive button works.
///
/// Only renders: [StartOverScreen] owns the field and the erase.
class DesktopStartOverView extends StatelessWidget {
  const DesktopStartOverView({
    super.key,
    required this.vaultId,
    required this.bucketNote,
    required this.confirm,
    required this.canErase,
    required this.busy,
    required this.onChanged,
    required this.onErase,
    required this.onBack,
  });

  /// The vault that would be erased, from its `vault.json`.
  final String? vaultId;
  final String bucketNote;
  final TextEditingController confirm;
  final bool canErase;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onErase;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final body = TextStyle(
      fontSize: DesktopMetrics.bodySize,
      color: colors.text,
    );
    final secondary = TextStyle(
      fontSize: DesktopMetrics.secondarySize + 1,
      color: colors.secondaryText,
    );
    final vaultId = this.vaultId;

    return DesktopLockWindow(
      mark: DesktopLockMark.erase,
      title: 'Start over with a new vault',
      message:
          'Without the master password or the recovery key, nothing can '
          'open this vault. Starting over erases it from this device so you '
          'can create a new one.',
      footer: Row(
        children: [
          DesktopLink(label: 'Back', onPressed: busy ? null : onBack),
          const Spacer(),
          DesktopButton(
            label: busy ? 'Erasing…' : 'Erase and Start Over',
            kind: DesktopButtonKind.destructive,
            size: DesktopButtonSize.large,
            onPressed: canErase ? onErase : null,
          ),
        ],
      ),
      children: [
        Text('Erased from this device', style: body),
        const SizedBox(height: 6),
        for (final line in StartOverScreen.erased)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('•  $line', style: secondary),
          ),
        if (vaultId != null) ...[
          const SizedBox(height: 6),
          Text(
            'vault $vaultId',
            style: AppText.mono(
              context,
              fontSize: DesktopMetrics.secondarySize,
            ).copyWith(color: colors.secondaryText),
          ),
        ],
        const SizedBox(height: 14),
        Text(bucketNote, style: secondary),
        const SizedBox(height: 18),
        DesktopForm(
          labelWidth: _labelWidth,
          children: [
            DesktopFormRow(
              label: 'Type ${StartOverScreen.confirmWord}',
              child: Semantics(
                label: 'Type ${StartOverScreen.confirmWord} to confirm',
                child: DesktopTextField(
                  controller: confirm,
                  autocorrect: false,
                  autofocus: true,
                  enabled: !busy,
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onErase(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static const double _labelWidth = 104;
}
