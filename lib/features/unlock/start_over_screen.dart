import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/start_over.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart' show DesktopTheme;
import '../../shared/ui.dart';
import 'desktop_start_over_view.dart';

/// The master password and the recovery key are both lost (P1-25): erase
/// this device's vault and create a new one. Says what goes and what stays,
/// and asks for [confirmWord] to be typed first, since nothing can bring
/// the vault back.
class StartOverScreen extends ConsumerStatefulWidget {
  const StartOverScreen({super.key});

  /// What the user types to confirm, in any case.
  static const confirmWord = 'ERASE';

  /// What gets erased, one line each.
  static const erased = [
    'Every item and file in this vault',
    'Its sync settings and storage keys',
    'Biometric unlock and expiry reminders',
    'Paired AI agents',
  ];

  /// What becomes of the bucket copy, or that there is none.
  static String bucketNote(SyncedCopy? copy) => copy == null
      ? "This vault doesn't sync, so this is its only copy."
      : 'Its encrypted copy stays in the bucket ${copy.bucket}, under '
            '${copy.prefix}. Another device that can still unlock it keeps '
            'working. Delete that folder in the bucket when nothing needs '
            'it.';

  @override
  ConsumerState<StartOverScreen> createState() => _StartOverScreenState();
}

class _StartOverScreenState extends ConsumerState<StartOverScreen> {
  final _confirm = TextEditingController();
  late final SyncedCopy? _copy = ref.read(startOverProvider).syncedCopy();
  bool _busy = false;

  bool get _confirmed =>
      _confirm.text.trim().toUpperCase() == StartOverScreen.confirmWord;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _erase() async {
    if (_busy || !_confirmed) return;
    setState(() => _busy = true);
    try {
      await ref.read(startOverProvider)();
      if (!mounted) return;
      showAppToast(
        context,
        const BCToastData(
          title: 'Vault erased',
          description: 'Create a new one, or join one from your bucket.',
          variant: BCToastVariant.success,
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(
        context,
        const BCToastData(
          title: "Couldn't erase the vault",
          description: 'Nothing was opened. Try again.',
          variant: BCToastVariant.danger,
        ),
      );
    }
  }

  void _back() => context.go(Routes.recover);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    final vaultId = session is Locked ? session.header?.vaultId : null;

    if (DesktopTheme.maybeOf(context) != null) {
      return DesktopStartOverView(
        vaultId: vaultId,
        bucketNote: StartOverScreen.bucketNote(_copy),
        confirm: _confirm,
        canErase: _confirmed && !_busy,
        busy: _busy,
        onChanged: () => setState(() {}),
        onErase: _erase,
        onBack: _back,
      );
    }

    final bc = context.bcTheme;
    return Scaffold(
      backgroundColor: bc.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BCSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.trash2, size: 32, color: bc.danger),
                  const SizedBox(height: BCSpacing.md),
                  const BCText(
                    'Start over with a new vault',
                    type: BCTextType.h2,
                  ),
                  const SizedBox(height: BCSpacing.sm),
                  const BCText(
                    'Without the master password or the recovery key, '
                    'nothing can open this vault. Starting over erases it '
                    'from this device so you can create a new one.',
                    color: BCTextColor.muted,
                  ),
                  const SizedBox(height: BCSpacing.lg),
                  const BCText('Erased from this device', type: BCTextType.h6),
                  const SizedBox(height: BCSpacing.xs),
                  for (final line in StartOverScreen.erased)
                    Padding(
                      padding: const EdgeInsets.only(top: BCSpacing.xs),
                      child: BCText('•  $line', type: BCTextType.bodySm),
                    ),
                  const SizedBox(height: BCSpacing.md),
                  BCText(
                    StartOverScreen.bucketNote(_copy),
                    type: BCTextType.bodySm,
                    color: BCTextColor.muted,
                  ),
                  const SizedBox(height: BCSpacing.lg),
                  BCTextField(
                    isDisabled: _busy,
                    children: [
                      const BCTextFieldLabel(
                        'Type ${StartOverScreen.confirmWord} to confirm',
                      ),
                      BCTextFieldInput(
                        controller: _confirm,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _erase(),
                      ),
                    ],
                  ),
                  const SizedBox(height: BCSpacing.md),
                  BCButton(
                    fullWidth: true,
                    variant: BCButtonVariant.danger,
                    isDisabled: !_confirmed || _busy,
                    onPressed: _erase,
                    startContent: _busy
                        ? const BCSpinner(size: BCSpinnerSize.sm)
                        : null,
                    child: Text(_busy ? 'Erasing…' : 'Erase and start over'),
                  ),
                  const SizedBox(height: BCSpacing.md),
                  Center(
                    child: BCLinkButton(
                      onPressed: _busy ? null : _back,
                      child: const Text('Back'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
