import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/sync_controller.dart';
import '../../shared/desktop_ui.dart';
import '../../shared/ui.dart';

/// The bucket's vault has a new key (SyncKeyChanged): most likely rotated
/// on another device, possibly a replaced `vault.json` (SPEC §4.4). The
/// master password decides: it opens a genuine rotation, and nothing else.
///
/// A sheet on desktop, a bc_ui dialog on phones.
Future<void> showAdoptKeyDialog(BuildContext context) {
  if (DesktopTheme.maybeOf(context) != null) {
    return showDesktopSheet<void>(
      context,
      builder: (_) => const AdoptKeyForm(),
    );
  }
  return BCDialog.show<void>(
    context,
    builder: (_) => const BCDialogContent(
      width: 480,
      showCloseButton: true,
      child: AdoptKeyForm(),
    ),
  );
}

class AdoptKeyForm extends ConsumerStatefulWidget {
  const AdoptKeyForm({super.key});

  @override
  ConsumerState<AdoptKeyForm> createState() => _AdoptKeyFormState();
}

class _AdoptKeyFormState extends ConsumerState<AdoptKeyForm> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your master password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final adoption = await ref
          .read(syncControllerProvider.notifier)
          .adoptRemoteKey(_password.text);
      if (!mounted) return;
      final kept = adoption.rescued;
      BCToast.show(
        context,
        BCToastData(
          title: 'Switched to the new vault key',
          description: kept == 0
              ? null
              : kept == 1
              ? 'The change you made here meanwhile was kept.'
              : 'The $kept changes you made here meanwhile were kept.',
          variant: BCToastVariant.success,
        ),
      );
      Navigator.of(context).pop();
    } on WrongPassword {
      _fail(
        "That password doesn't open the new key. If the password was also "
        'changed on the other device, use that one.',
      );
    } on StorageException {
      _fail("Couldn't reach the storage. Nothing changed; try again.");
    } on Object {
      _fail("Couldn't switch keys. Nothing changed on this device.");
    }
  }

  void _fail(String message) {
    _password.clear();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) != null) return _desktop(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BCDialogTitle('The vault key changed'),
        const SizedBox(height: BCSpacing.xs),
        const BCDialogDescription(
          'The vault in your storage now uses a new key, most likely '
          'because it was rotated on another device. Sync is paused and '
          'nothing here has changed.',
        ),
        const SizedBox(height: BCSpacing.sm),
        const BCText(
          "If you didn't rotate it, someone with access to your bucket may "
          'have replaced it. Close this and check your storage instead.',
          type: BCTextType.bodySm,
          color: BCTextColor.muted,
        ),
        const SizedBox(height: BCSpacing.lg),
        PasswordField(
          label: 'Master password',
          controller: _password,
          autofocus: true,
          isDisabled: _busy,
          error: _error,
          description: 'Changes you made here meanwhile are kept.',
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
              child: const Text('Not now'),
            ),
            BCButton(
              isDisabled: _busy,
              onPressed: _submit,
              startContent: _busy
                  ? const BCSpinner(size: BCSpinnerSize.sm)
                  : null,
              child: Text(_busy ? 'Switching…' : 'Use the new key'),
            ),
          ],
        ),
      ],
    );
  }

  /// Desktop: a sheet with the warning, then the master password.
  Widget _desktop(BuildContext context) {
    final colors = context.desktopColors;
    return PopScope(
      canPop: !_busy,
      child: DesktopSheet(
        width: 500,
        icon: _KeyTile(colors: colors),
        title: 'The vault key changed',
        message:
            'The vault in your storage now uses a new key, most likely '
            'because it was rotated on another device. Sync is paused and '
            'nothing here has changed.',
        actions: [
          if (_busy) const DesktopProgress(semanticLabel: 'Switching'),
          DesktopButton(
            label: 'Not Now',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
          DesktopButton(
            label: _busy ? 'Switching…' : 'Use the New Key',
            kind: DesktopButtonKind.primary,
            onPressed: _busy ? null : _submit,
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Text(
              "If you didn't rotate it, someone with access to your bucket "
              'may have replaced it. Close this and check your storage '
              'instead.',
              style: TextStyle(
                fontSize: DesktopMetrics.secondarySize + 1,
                color: colors.secondaryText,
              ),
            ),
            DesktopForm(
              children: [
                DesktopFormRow(
                  label: 'Master password',
                  note: 'Changes you made here meanwhile are kept.',
                  error: _error,
                  child: Semantics(
                    label: 'Master password',
                    textField: true,
                    child: DesktopTextField(
                      controller: _password,
                      obscureText: true,
                      autofocus: true,
                      enabled: !_busy,
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The key-changed mark, in the warning colours.
class _KeyTile extends StatelessWidget {
  const _KeyTile({required this.colors});

  final DesktopColors colors;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: colors.warningBadge,
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.menuRadius + 2),
        ),
      ),
      child: SizedBox.square(
        dimension: DesktopMetrics.toolbarSearchHeight + 8,
        child: DesktopIcon(
          DesktopSymbol.keyChanged,
          size: 18,
          color: colors.onWarningBadge,
        ),
      ),
    ),
  );
}
