import 'package:cred_parsers/cred_parsers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/format.dart';
import '../../core/item_templates.dart';
import '../../data/providers.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import 'import_draft.dart';

/// Imports files into the vault (design frame D04): asks for [files], or
/// lets the user choose them, then opens the import dialog for each one and
/// shows the last item imported.
Future<void> showImportDialog(
  BuildContext context, {
  List<PickedFile>? files,
}) async {
  final container = ProviderScope.containerOf(context);
  final picked = files ?? await container.read(fileOpenerProvider).pick();
  String? lastId;
  var imported = 0;
  for (final file in picked) {
    if (!context.mounted) return;
    final outcome = await BCDialog.show<ImportOutcome>(
      context,
      builder: (_) => BCDialogContent(
        width: 640,
        showCloseButton: true,
        child: ImportDialog(file: file),
      ),
    );
    if (outcome == null) continue;
    lastId = outcome.itemId;
    if (outcome.imported) imported++;
  }
  if (lastId == null || !context.mounted) return;
  context.go(const VaultFilter().location(item: lastId));
  if (imported > 0) {
    BCToast.show(
      context,
      BCToastData(
        title: imported == 1 ? 'File imported' : '$imported files imported',
        variant: BCToastVariant.success,
      ),
    );
  }
}

/// How the dialog closed: the item to show, and whether a file was saved
/// (as opposed to opening an existing copy).
typedef ImportOutcome = ({String itemId, bool imported});

/// The import form for one file: what the file says (read-only, "From
/// file"), any password or choice it needs, what only the user knows, and
/// where the item belongs.
class ImportDialog extends ConsumerStatefulWidget {
  const ImportDialog({super.key, required this.file});

  final PickedFile file;

  @override
  ConsumerState<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<ImportDialog> {
  ImportDraft? _draft;
  late final String _sha256 = _hex(VaultCrypto.sha256(widget.file.bytes));
  late final _title = TextEditingController();
  final _secretControllers = <String, TextEditingController>{};
  final _fieldControllers = <String, TextEditingController>{};
  Map<String, String> _errors = const {};
  bool _busy = true;
  bool _ignoreDuplicates = false;
  String? _error;

  bool get _tooLarge => widget.file.bytes.length > Vault.maxAttachmentBytes;

  @override
  void initState() {
    super.initState();
    if (_tooLarge) {
      _busy = false;
    } else {
      _parse();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final c in [
      ..._secretControllers.values,
      ..._fieldControllers.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _secret(String key) =>
      _secretControllers.putIfAbsent(key, TextEditingController.new);

  TextEditingController _field(String key) =>
      _fieldControllers.putIfAbsent(key, TextEditingController.new);

  /// Parses (or re-parses, with the passwords and choice given so far) off
  /// the UI isolate.
  Future<void> _parse() async {
    final draft = _draft;
    setState(() => _busy = true);
    final result = await ref
        .read(credentialParsersProvider)
        .parseInIsolate(
          ParseInput(
            filename: widget.file.name,
            bytes: widget.file.bytes,
            secrets: draft?.secrets ?? const {},
            choice: draft?.choice,
          ),
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (draft == null) {
        _draft = ImportDraft(widget.file, result);
        _title.text = _draft!.title;
      } else {
        draft.result = result;
      }
    });
  }

  Future<void> _unlock() async {
    final draft = _draft!;
    for (final request in draft.result.secretsNeeded) {
      draft.secrets[request.key] = _secret(request.key).text;
    }
    await _parse();
  }

  List<Item> get _duplicates {
    final session = ref.read(vaultSessionProvider);
    if (session is! Unlocked || _ignoreDuplicates) return const [];
    return ImportDraft.duplicatesOf(_sha256, session.index.items.values);
  }

  Future<void> _import({Item? replacing}) async {
    final draft = _draft!;
    draft.title = _title.text;
    for (final field in draft.requiredFields) {
      draft.userFields[field.key] = _field(field.key).text;
    }
    final errors = replacing == null
        ? draft.validate()
        : const <String, String>{};
    setState(() {
      _errors = errors;
      _error = null;
    });
    if (errors.isNotEmpty || _busy) return;
    final session = ref.read(vaultSessionProvider);
    if (session is! Unlocked) return;
    setState(() => _busy = true);
    final notifier = ref.read(vaultSessionProvider.notifier);
    try {
      final attachment = await session.vault.addAttachment(
        widget.file.bytes,
        filename: widget.file.name.split(RegExp(r'[/\\]')).last,
        mime: _mimeFor(widget.file.name),
      );
      final item = replacing == null
          ? draft.toItem(notifier.newItem, attachment)
          : draft.replace(replacing, attachment);
      final saved = await notifier.saveItem(item);
      if (mounted) {
        Navigator.of(context).pop((itemId: saved.id, imported: true));
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't import the file. Nothing was changed.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BCDialogTitle('Import file'),
        const SizedBox(height: BCSpacing.lg),
        _FileHeader(
          name: widget.file.name,
          size: widget.file.bytes.length,
          sha256: _sha256,
          type: draft?.type,
        ),
        const SizedBox(height: BCSpacing.lg),
        if (_tooLarge)
          _Notice(
            icon: LucideIcons.circleAlert,
            danger: true,
            text:
                'This file is larger than '
                '${Format.bytes(Vault.maxAttachmentBytes)}, the most one '
                'item can hold.',
          )
        else if (draft == null)
          const Center(child: BCSpinner())
        else
          ..._body(context, draft),
      ],
    );
  }

  List<Widget> _body(BuildContext context, ImportDraft draft) {
    final result = draft.result;
    final duplicates = _duplicates;
    return [
      if (_error case final error?) ...[
        _Notice(icon: LucideIcons.circleAlert, danger: true, text: error),
        const SizedBox(height: BCSpacing.sm),
      ],
      for (final warning in result.warnings) ...[
        _Notice(icon: LucideIcons.info, text: warning),
        const SizedBox(height: BCSpacing.sm),
      ],
      if (duplicates.isNotEmpty) ...[
        _Duplicate(
          existing: duplicates.first,
          busy: _busy,
          onOpen: () =>
              Navigator.of(context)
                  .pop((itemId: duplicates.first.id, imported: false)),
          onReplace: () => _import(replacing: duplicates.first),
          onImportAnyway: () => setState(() => _ignoreDuplicates = true),
        ),
        const SizedBox(height: BCSpacing.lg),
        _Actions(onCancel: () => Navigator.of(context).pop()),
      ] else if (result.needsSecrets) ...[
        for (final (i, request) in result.secretsNeeded.indexed) ...[
          PasswordField(
            label: request.label,
            controller: _secret(request.key),
            autofocus: i == 0,
            error: request.rejected
                ? "That ${request.label.toLowerCase()} didn't open the file."
                : null,
            description:
                'Needed to read what’s inside. Stays on this '
                'device, encrypted with the vault.',
            onSubmitted: (_) => _unlock(),
          ),
          const SizedBox(height: BCSpacing.md),
        ],
        _Actions(
          busy: _busy,
          primary: 'Unlock file',
          onPrimary: _unlock,
          onCancel: () => Navigator.of(context).pop(),
        ),
      ] else if (result.needsChoice) ...[
        const _Label('Which app is this for?'),
        BCSelect<String>(
          listLabel: 'App in this file',
          value: draft.choice,
          placeholder: 'Choose an app',
          items: [
            for (final option in result.options)
              BCSelectItem(value: option.id, label: option.label),
          ],
          onValueChange: (id) {
            draft.choice = id;
            _parse();
          },
        ),
        const SizedBox(height: BCSpacing.lg),
        _Actions(onCancel: () => Navigator.of(context).pop()),
      ] else
        ..._form(context, draft),
    ];
  }

  List<Widget> _form(BuildContext context, ImportDraft draft) {
    final result = draft.result;
    final session = ref.watch(vaultSessionProvider);
    final apps = session is Unlocked
        ? (session.index.apps.values.toList()..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ))
        : <AppRecord>[];
    return [
      if (result.facts.isNotEmpty || result.expiresAt != null) ...[
        _Facts(facts: result.facts, expiresAt: result.expiresAt),
        const SizedBox(height: BCSpacing.lg),
      ],
      for (final field in draft.requiredFields) ...[
        BCTextField(
          key: ValueKey('import-field-${field.key}'),
          isRequired: true,
          isInvalid: _errors.containsKey(field.key),
          children: [
            BCTextFieldLabel(field.label),
            BCTextFieldInput(
              controller: _field(field.key),
              hintText: field.hint,
              onChanged: (_) => setState(() {}),
            ),
            if (_errors[field.key] case final error?)
              BCTextFieldError(error)
            else
              const BCTextFieldDescription('The file doesn’t say; enter it'),
          ],
        ),
        const SizedBox(height: BCSpacing.md),
      ],
      if (draft.asksPurpose) ...[
        const _Label('Used for'),
        // One choice, or none. Not a BCToggleButtonGroup: in bc_ui 0.7.0
        // its buttons centre their label in all the width the Wrap allows,
        // so in a wide dialog each option fills a row of its own.
        Wrap(
          spacing: BCSpacing.sm,
          runSpacing: BCSpacing.sm,
          children: [
            for (final purpose in KeyPurpose.values)
              IntrinsicWidth(
                child: BCToggleButton(
                  size: BCToggleButtonSize.sm,
                  isSelected: draft.purpose == purpose,
                  onSelectedChange: (on) =>
                      setState(() => draft.purpose = on ? purpose : null),
                  label: purpose.label,
                ),
              ),
          ],
        ),
        const SizedBox(height: BCSpacing.md),
      ],
      BCTextField(
        isRequired: true,
        isInvalid: _errors.containsKey('title'),
        children: [
          const BCTextFieldLabel('Name'),
          BCTextFieldInput(controller: _title),
          if (_errors['title'] case final error?) BCTextFieldError(error),
        ],
      ),
      const SizedBox(height: BCSpacing.md),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: BCSpacing.sm,
        children: [
          Expanded(
            child: _Choice(
              label: 'App',
              none: 'No app',
              value: draft.appId,
              options: {for (final app in apps) app.id: app.name},
              onChanged: (v) => setState(() => draft.appId = v),
            ),
          ),
          Expanded(
            child: _Choice(
              label: 'Platform',
              none: 'None',
              value: draft.platform,
              options: {
                for (final p in ItemTemplates.platforms)
                  p: VaultLabels.platform(p),
              },
              onChanged: (v) => setState(() => draft.platform = v),
            ),
          ),
          Expanded(
            child: _Choice(
              label: 'Environment',
              none: 'None',
              value: draft.environment,
              options: {
                for (final e in ItemTemplates.environments)
                  e: VaultLabels.environment(e),
              },
              onChanged: (v) => setState(() => draft.environment = v),
            ),
          ),
        ],
      ),
      if (draft.secrets.isNotEmpty) ...[
        const SizedBox(height: BCSpacing.md),
        BCControlField(
          label: 'Keep the password with the item',
          description: 'Saved as a secret field, encrypted with the vault.',
          control: BCCheckbox(
            isSelected: draft.keepSecrets,
            onSelectedChange: (v) => setState(() => draft.keepSecrets = v),
          ),
          onPressed: () =>
              setState(() => draft.keepSecrets = !draft.keepSecrets),
        ),
      ],
      const SizedBox(height: BCSpacing.lg),
      _Actions(
        busy: _busy,
        primary: 'Import',
        onPrimary: _import,
        onCancel: () => Navigator.of(context).pop(),
      ),
    ];
  }

  static String _mimeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.plist')) return 'application/x-plist';
    if (lower.endsWith('.pem') || lower.endsWith('.p8')) {
      return 'application/x-pem-file';
    }
    return 'application/octet-stream';
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// The file's name, size and short hash, with what it was read as.
class _FileHeader extends StatelessWidget {
  const _FileHeader({
    required this.name,
    required this.size,
    required this.sha256,
    required this.type,
  });

  final String name;
  final int size;
  final String sha256;
  final ItemType? type;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: BCSpacing.md,
      children: [
        TypeIconTile(type: type ?? ItemType.genericFile),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              MonoText(name, middleEllipsis: true),
              BCText(
                [
                  type?.label ?? 'Reading…',
                  Format.bytes(size),
                  'SHA-256 ${Format.shortHash(sha256)}',
                ].join(' · '),
                type: BCTextType.bodySm,
                color: BCTextColor.muted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the file says, read-only and marked as coming from the file.
class _Facts extends StatelessWidget {
  const _Facts({required this.facts, required this.expiresAt});

  final Map<String, ItemField> facts;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final expiry = expiresAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _Label('Details')),
            const ProvenanceLabel(source: ExpirySource.file),
          ],
        ),
        const SizedBox(height: BCSpacing.xs),
        BCListGroup(
          variant: BCSurfaceVariant.secondary,
          children: [
            if (expiry != null)
              _FactRow(
                label: 'Expires',
                value: DateFormat.yMMMd().add_Hm().format(expiry.toLocal()),
              ),
            for (final MapEntry(:key, :value) in facts.entries)
              _FactRow(
                label: Format.fieldLabel(key),
                value: value.secret ? SecretRow.mask : value.value,
              ),
          ],
        ),
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return BCListGroupItem(
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: BCSpacing.md,
        children: [
          SizedBox(
            width: 150,
            child: BCText(
              label,
              type: BCTextType.bodySm,
              color: BCTextColor.muted,
            ),
          ),
          Expanded(child: MonoText(value, selectable: true)),
        ],
      ),
    );
  }
}

/// The same bytes are already in the vault.
class _Duplicate extends StatelessWidget {
  const _Duplicate({
    required this.existing,
    required this.busy,
    required this.onOpen,
    required this.onReplace,
    required this.onImportAnyway,
  });

  final Item existing;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onReplace;
  final VoidCallback onImportAnyway;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: BCSpacing.md,
      children: [
        _Notice(
          icon: LucideIcons.copy,
          text:
              'This exact file is already in your vault as '
              '“${existing.title}”.',
        ),
        Wrap(
          spacing: BCSpacing.sm,
          runSpacing: BCSpacing.sm,
          children: [
            BCButton(
              size: BCButtonSize.sm,
              onPressed: busy ? null : onOpen,
              child: const Text('Open existing'),
            ),
            BCButton(
              size: BCButtonSize.sm,
              variant: BCButtonVariant.secondary,
              isDisabled: busy,
              onPressed: onReplace,
              child: const Text('Replace'),
            ),
            BCButton(
              size: BCButtonSize.sm,
              variant: BCButtonVariant.ghost,
              isDisabled: busy,
              onPressed: onImportAnyway,
              child: const Text('Import anyway'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.danger = false});

  final IconData icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: danger ? bc.dangerSoft : bc.defaultColor,
        shape: BCShapes.continuous(BCRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BCSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: BCSpacing.sm,
          children: [
            Icon(
              icon,
              size: 16,
              color: danger ? bc.dangerSoftForeground : bc.muted,
            ),
            Expanded(child: BCText(text, type: BCTextType.bodySm)),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.onCancel,
    this.primary,
    this.onPrimary,
    this.busy = false,
  });

  final VoidCallback onCancel;
  final String? primary;
  final VoidCallback? onPrimary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: BCSpacing.sm,
      children: [
        BCButton(
          variant: BCButtonVariant.secondary,
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        if (primary case final label?)
          BCButton(
            isDisabled: busy,
            onPressed: onPrimary,
            startContent: busy ? const BCSpinner(size: BCSpinnerSize.sm) : null,
            child: Text(label),
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lines up with bc_ui's own field labels.
      padding: const EdgeInsets.only(left: 6, bottom: BCSpacing.xs),
      child: BCText(text, type: BCTextType.bodySm, weight: BCTextWeight.medium),
    );
  }
}

/// A select over [options] (value → label) with a "none" choice first.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.none,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String none;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(label),
        BCSelect<String>(
          listLabel: label,
          value: value ?? '',
          items: [
            BCSelectItem(value: '', label: none),
            for (final MapEntry(:key, value: text) in options.entries)
              BCSelectItem(value: key, label: text),
          ],
          onValueChange: (v) => onChanged(v.isEmpty ? null : v),
        ),
      ],
    );
  }
}
