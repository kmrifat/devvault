import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/item_templates.dart';
import '../../data/providers.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import 'import_dialog.dart';
import 'place_fields.dart';

/// What the phone's Import button offers (B4a).
enum _Add { file, secret }

/// Import on a phone (B4a): pick a file (B4) or paste a secret (B4b).
Future<void> showPhoneImport(BuildContext context) async {
  final choice = await BCDialog.show<_Add>(
    context,
    builder: (context) => BCDialogContent(
      showCloseButton: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BCDialogTitle('Add to vault'),
          const SizedBox(height: BCSpacing.lg),
          BCListGroup(
            children: [
              BCListGroupItem(
                title: 'Pick a file',
                description: 'A key, certificate, keystore or config',
                prefix: const _ChoiceTile(
                  icon: LucideIcons.fileUp,
                  accent: true,
                ),
                suffix: const Icon(LucideIcons.chevronRight, size: 16),
                onPressed: () => Navigator.of(context).pop(_Add.file),
              ),
              BCListGroupItem(
                title: 'Paste a secret',
                description: 'An API key, token or password',
                prefix: const _ChoiceTile(icon: LucideIcons.clipboardPaste),
                suffix: const Icon(LucideIcons.chevronRight, size: 16),
                onPressed: () => Navigator.of(context).pop(_Add.secret),
              ),
            ],
          ),
          const SizedBox(height: BCSpacing.md),
          const BCText(
            'Files can also come from other apps: Share › DevVault, or Open '
            'in DevVault.',
            type: BCTextType.bodyXs,
            color: BCTextColor.muted,
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _Add.file:
      await showImportDialog(context);
    case _Add.secret:
      final saved = await BCDialog.show<Item>(
        context,
        builder: (_) => const BCDialogContent(
          showCloseButton: true,
          child: PasteSecretSheet(),
        ),
      );
      if (saved == null || !context.mounted) return;
      context.go(const VaultFilter().location(item: saved.id));
      BCToast.show(
        context,
        BCToastData(
          title: '“${saved.title}” added',
          variant: BCToastVariant.success,
        ),
      );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.icon, this.accent = false});

  final IconData icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: accent ? bc.accentSoft : bc.defaultColor,
        shape: BCShapes.continuous(BCRadius.xl),
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Icon(
          icon,
          size: 20,
          color: accent ? bc.accentSoftForeground : bc.foreground,
        ),
      ),
    );
  }
}

/// B4b: a secret typed or pasted on a phone, saved as a Generic Secret.
/// Its value is a secret field; an expiry only if the user sets one
/// (facts only: nothing is guessed). Pops with the saved item.
class PasteSecretSheet extends ConsumerStatefulWidget {
  const PasteSecretSheet({super.key});

  @override
  ConsumerState<PasteSecretSheet> createState() => _PasteSecretSheetState();
}

class _PasteSecretSheetState extends ConsumerState<PasteSecretSheet> {
  final _name = TextEditingController();
  final _secret = TextEditingController();
  String? _appId;
  String? _platform;
  String? _environment;
  DateTime? _expiresAt;
  Map<String, String> _errors = const {};
  bool _busy = false;
  String? _failed;

  @override
  void dispose() {
    // The controller holds the secret; clear it before letting go.
    _secret
      ..clear()
      ..dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = await ref.read(clipboardGuardProvider).takePasted();
    if (text == null || !mounted) return;
    setState(() {
      _secret.text = text.trim();
      _errors = {..._errors}..remove('secret');
    });
  }

  Future<void> _save() async {
    final errors = {
      if (_name.text.trim().isEmpty) 'name': 'Give it a name',
      if (_secret.text.isEmpty) 'secret': 'Paste or type the secret',
    };
    setState(() {
      _errors = errors;
      _failed = null;
    });
    if (errors.isNotEmpty || _busy) return;
    setState(() => _busy = true);
    final notifier = ref.read(vaultSessionProvider.notifier);
    final expiresAt = _expiresAt;
    try {
      final saved = await notifier.saveItem(
        notifier
            .newItem(ItemType.genericSecret, _name.text.trim())
            .copyWith(
              appId: _appId,
              platform: _platform,
              environment: _environment,
              fields: {
                'value': ItemField(
                  value: _secret.text,
                  source: FieldSource.user,
                  secret: true,
                ),
              },
              expiresAt: expiresAt,
              expiresSource: expiresAt == null ? null : ExpirySource.user,
            ),
      );
      if (mounted) Navigator.of(context).pop(saved);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = "Couldn't save it. Nothing was changed.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    final apps = session is Unlocked
        ? (session.index.apps.values.toList()..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ))
        : <AppRecord>[];
    final expiresAt = _expiresAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BCDialogTitle('Paste a secret'),
        const SizedBox(height: BCSpacing.lg),
        BCTextField(
          isRequired: true,
          isInvalid: _errors.containsKey('name'),
          children: [
            const BCTextFieldLabel('Name'),
            BCTextFieldInput(
              controller: _name,
              autofocus: true,
              hintText: 'Stripe secret key',
              textInputAction: TextInputAction.next,
            ),
            if (_errors['name'] case final error?) BCTextFieldError(error),
          ],
        ),
        const SizedBox(height: BCSpacing.md),
        PasswordField(
          label: 'Secret',
          controller: _secret,
          isRequired: true,
          error: _errors['secret'],
          description:
              'Saved as a secret field: masked, never searchable. The '
              'clipboard is cleared after pasting.',
          action: BCButton(
            size: BCButtonSize.sm,
            variant: BCButtonVariant.secondary,
            startContent: const Icon(LucideIcons.clipboardPaste, size: 14),
            onPressed: _paste,
            child: const Text('Paste'),
          ),
        ),
        const SizedBox(height: BCSpacing.md),
        PlaceFields(
          app: PlaceChoice(
            label: 'App',
            none: 'No app',
            value: _appId,
            options: {for (final app in apps) app.id: app.name},
            onChanged: (v) => setState(() => _appId = v),
          ),
          platform: PlaceChoice(
            label: 'Platform',
            none: 'None',
            value: _platform,
            options: {
              for (final p in ItemTemplates.platforms)
                p: VaultLabels.platform(p),
            },
            onChanged: (v) => setState(() => _platform = v),
          ),
          environment: PlaceChoice(
            label: 'Environment',
            none: 'None',
            value: _environment,
            options: {
              for (final e in ItemTemplates.environments)
                e: VaultLabels.environment(e),
            },
            onChanged: (v) => setState(() => _environment = v),
          ),
        ),
        const SizedBox(height: BCSpacing.md),
        Row(
          children: [
            const SheetLabel('Expires'),
            const Spacer(),
            if (expiresAt != null)
              BCLinkButton(
                onPressed: () => setState(() => _expiresAt = null),
                child: const Text('Clear'),
              )
            else
              const BCText(
                'Optional',
                type: BCTextType.bodyXs,
                color: BCTextColor.muted,
              ),
          ],
        ),
        BCDateField(
          value: expiresAt?.toLocal(),
          placeholder: 'No expiry date',
          presentation: BCPickerPresentation.bottomSheet,
          formatDate: DateFormat.yMMMd().format,
          onChanged: (date) => setState(
            () => _expiresAt = DateTime.utc(date.year, date.month, date.day),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 6, top: BCSpacing.xs),
          child: BCText(
            'Only if you know it. A date you set shows as “Set by you”.',
            type: BCTextType.bodyXs,
            color: BCTextColor.muted,
          ),
        ),
        if (_failed case final failed?) ...[
          const SizedBox(height: BCSpacing.md),
          BCText(failed, style: TextStyle(color: context.bcTheme.danger)),
        ],
        const SizedBox(height: BCSpacing.xl),
        BCButton(
          size: BCButtonSize.lg,
          fullWidth: true,
          isDisabled: _busy,
          onPressed: _save,
          startContent: _busy ? const BCSpinner(size: BCSpinnerSize.sm) : null,
          child: const Text('Add to vault'),
        ),
      ],
    );
  }
}
