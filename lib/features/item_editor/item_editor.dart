import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/item_templates.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import 'item_draft.dart';

/// Opens the item form: [item] to edit it, or null for a new item placed
/// in [app], [platform] and [env] (where the user is looking). Resolves to
/// the saved item's id, or null when cancelled.
Future<String?> showItemEditor(
  BuildContext context, {
  Item? item,
  String? app,
  String? platform,
  String? env,
}) {
  final draft = item == null
      ? ItemDraft.create(
          ItemType.genericSecret,
          appId: app,
          platform: platform,
          environment: env,
        )
      : ItemDraft.edit(item);
  return BCDialog.show<String>(
    context,
    builder: (_) => BCDialogContent(
      width: 640,
      showCloseButton: true,
      child: ItemEditor(draft: draft),
    ),
  );
}

/// The item form: type, name, where it belongs, tags, expiry, fields and
/// notes. Values read from a file are shown but locked.
class ItemEditor extends ConsumerStatefulWidget {
  const ItemEditor({super.key, required this.draft});

  final ItemDraft draft;

  @override
  ConsumerState<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends ConsumerState<ItemEditor> {
  late final ItemDraft _draft = widget.draft;
  late final _title = TextEditingController(text: _draft.title);
  late final _tags = TextEditingController(text: _draft.tags);
  late final _notes = TextEditingController(text: _draft.notes);
  Map<String, String> _errors = const {};
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _draft
      ..title = _title.text
      ..tags = _tags.text
      ..notes = _notes.text;
    final errors = _draft.validate();
    setState(() {
      _errors = errors;
      _saveError = null;
    });
    if (errors.isNotEmpty || _saving) return;
    setState(() => _saving = true);
    final session = ref.read(vaultSessionProvider.notifier);
    try {
      final saved = await session.saveItem(_draft.toItem(session.newItem));
      if (mounted) Navigator.of(context).pop(saved.id);
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = "Couldn't save the item. Nothing was changed.";
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
    final draft = _draft;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BCDialogTitle(draft.isNew ? 'New item' : 'Edit item'),
        const SizedBox(height: BCSpacing.lg),
        if (draft.isNew) ...[
          const _Label('Type'),
          BCSelect<ItemType>(
            value: draft.type,
            items: [
              for (final type in ItemType.values)
                BCSelectItem(
                  value: type,
                  label: type.label,
                  leading: TypeIconTile(type: type, size: 24),
                ),
            ],
            onValueChange: (type) => setState(() => draft.changeType(type)),
          ),
          const SizedBox(height: BCSpacing.md),
        ],
        BCTextField(
          isRequired: true,
          isInvalid: _errors.containsKey('title'),
          children: [
            const BCTextFieldLabel('Name'),
            BCTextFieldInput(
              controller: _title,
              autofocus: draft.isNew,
              hintText: 'e.g. Upload keystore',
            ),
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
                // An app deleted since shows as no app, as in the sidebar.
                value: apps.any((a) => a.id == draft.appId)
                    ? draft.appId
                    : null,
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
                  for (final p in {...ItemTemplates.platforms, ?draft.platform})
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
                  for (final e in {
                    ...ItemTemplates.environments,
                    ?draft.environment,
                  })
                    e: VaultLabels.environment(e),
                },
                onChanged: (v) => setState(() => draft.environment = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: BCSpacing.md),
        BCTextField(
          children: [
            const BCTextFieldLabel('Tags'),
            BCTextFieldInput(controller: _tags, hintText: 'release, signing'),
            const BCTextFieldDescription('Separate tags with commas'),
          ],
        ),
        const SizedBox(height: BCSpacing.md),
        _Expiry(
          draft: draft,
          onChanged: (date) => setState(() => draft.expiresAt = date),
        ),
        const SizedBox(height: BCSpacing.lg),
        const _Label('Fields'),
        for (final (i, field) in draft.fields.indexed)
          _FieldEditor(
            key: ObjectKey(field),
            field: field,
            error: _errors['$i'],
            onRemove: () => setState(() => draft.fields.remove(field)),
            onChanged: () => setState(() {}),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: BCButton(
            size: BCButtonSize.sm,
            variant: BCButtonVariant.ghost,
            onPressed: () => setState(() => draft.fields.add(DraftField())),
            startContent: const Icon(LucideIcons.plus, size: 15),
            child: const Text('Add field'),
          ),
        ),
        const SizedBox(height: BCSpacing.md),
        const _Label('Notes'),
        BCTextArea(
          controller: _notes,
          height: 96,
          placeholder: 'Anything worth remembering. Notes aren’t searchable.',
        ),
        if (_saveError case final error?) ...[
          const SizedBox(height: BCSpacing.md),
          BCText(
            error,
            type: BCTextType.bodySm,
            style: TextStyle(color: context.bcTheme.danger),
          ),
        ],
        const SizedBox(height: BCSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: BCSpacing.sm,
          children: [
            BCButton(
              variant: BCButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            BCButton(
              isDisabled: _saving,
              onPressed: _save,
              startContent: _saving
                  ? const BCSpinner(size: BCSpinnerSize.sm)
                  : null,
              child: Text(draft.isNew ? 'Add item' : 'Save'),
            ),
          ],
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

/// The expiry date: picked by the user (and marked as theirs), or shown
/// locked when it was read from the file.
class _Expiry extends StatelessWidget {
  const _Expiry({required this.draft, required this.onChanged});

  final ItemDraft draft;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final expiresAt = draft.expiresAt;
    if (draft.expiryFromFile && expiresAt != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('Expires'),
          Row(
            spacing: BCSpacing.sm,
            children: [
              BCText(DateFormat.yMMMd().format(expiresAt.toLocal())),
              const ProvenanceLabel(source: ExpirySource.file),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('Expires'),
        Row(
          spacing: BCSpacing.sm,
          children: [
            Expanded(
              child: BCDateField(
                value: expiresAt?.toLocal(),
                placeholder: 'No expiry date',
                presentation: BCPickerPresentation.popover,
                formatDate: DateFormat.yMMMd().format,
                onChanged: (date) =>
                    onChanged(DateTime.utc(date.year, date.month, date.day)),
              ),
            ),
            if (expiresAt != null)
              BCButton(
                size: BCButtonSize.sm,
                variant: BCButtonVariant.ghost,
                onPressed: () => onChanged(null),
                child: const Text('Clear'),
              ),
          ],
        ),
      ],
    );
  }
}

/// One field row: name, value, secret toggle, remove. A field read from a
/// file is shown locked.
class _FieldEditor extends StatefulWidget {
  const _FieldEditor({
    super.key,
    required this.field,
    required this.onRemove,
    required this.onChanged,
    this.error,
  });

  final DraftField field;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final String? error;

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  late final _name = TextEditingController(text: widget.field.name);
  late final _value = TextEditingController(text: widget.field.value);
  bool _revealed = false;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final locked = field.fromFile;
    final hidden = field.secret && !_revealed;

    return Padding(
      padding: const EdgeInsets.only(bottom: BCSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: BCSpacing.xs,
        children: [
          Row(
            spacing: BCSpacing.sm,
            children: [
              SizedBox(
                width: 170,
                child: Semantics(
                  label: 'Field name',
                  child: BCInput(
                    controller: _name,
                    isDisabled: locked,
                    isInvalid: widget.error != null,
                    placeholder: 'Name',
                    onChanged: (v) => field.name = v,
                  ),
                ),
              ),
              Expanded(
                child: Semantics(
                  label: '${field.name.isEmpty ? 'Field' : field.name} value',
                  child: BCInput(
                    controller: _value,
                    isDisabled: locked,
                    obscureText: hidden,
                    placeholder: field.secret ? 'Secret value' : 'Value',
                    onChanged: (v) => field.value = v,
                  ),
                ),
              ),
              if (field.secret && !locked)
                BCButton(
                  size: BCButtonSize.sm,
                  variant: BCButtonVariant.ghost,
                  isIconOnly: true,
                  onPressed: () => setState(() => _revealed = !_revealed),
                  child: Icon(
                    _revealed ? LucideIcons.eyeOff : LucideIcons.eye,
                    size: 16,
                    semanticLabel: _revealed ? 'Hide value' : 'Show value',
                  ),
                ),
              if (locked)
                const ProvenanceLabel(source: ExpirySource.file)
              else ...[
                BCToggleButton(
                  size: BCToggleButtonSize.sm,
                  isIconOnly: true,
                  isSelected: field.secret,
                  onSelectedChange: (secret) {
                    setState(() => field.secret = secret);
                    widget.onChanged();
                  },
                  icon: Icon(
                    LucideIcons.lockOpen,
                    size: 15,
                    semanticLabel: 'Mark ${field.name} secret',
                  ),
                  selectedIcon: Icon(
                    LucideIcons.lock,
                    size: 15,
                    semanticLabel: 'Secret: masked, never searched',
                  ),
                ),
                BCButton(
                  size: BCButtonSize.sm,
                  variant: BCButtonVariant.ghost,
                  isIconOnly: true,
                  onPressed: widget.onRemove,
                  child: Icon(
                    LucideIcons.x,
                    size: 16,
                    semanticLabel: 'Remove ${field.name}',
                  ),
                ),
              ],
            ],
          ),
          if (widget.error case final error?)
            BCText(
              error,
              type: BCTextType.bodyXs,
              style: TextStyle(color: context.bcTheme.danger),
            ),
        ],
      ),
    );
  }
}
