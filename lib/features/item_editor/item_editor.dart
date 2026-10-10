import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/item_templates.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart'
    show
        DesktopButton,
        DesktopButtonKind,
        DesktopCheckbox,
        DesktopChoice,
        DesktopComboBox,
        DesktopDateField,
        DesktopDateProblem,
        DesktopForm,
        DesktopFormRow,
        DesktopIconButton,
        DesktopMetrics,
        DesktopPopup,
        DesktopProgress,
        DesktopSheet,
        DesktopSymbol,
        DesktopTextField,
        DesktopTheme,
        DesktopThemeContext,
        DesktopTokenController,
        DesktopTokenField,
        showDesktopSheet;
import '../../shared/ui.dart';
import '../import/place_fields.dart'
    show
        NoteTone,
        SheetNote,
        SheetNotice,
        SourceTag,
        placeSuggestions,
        typedPlace;
import '../notes/notes.dart'
    show DesktopNotesEditor, PhoneNotesField, SecureNoteEditor;
import '../vault/desktop_item_type.dart' show DesktopTypeTile;
import 'item_draft.dart';

/// Opens the item form: [item] to edit it, or null for a new item of
/// [type] (a secret unless given) placed in [app], [platform] and [env]
/// (where the user is looking). Resolves to the saved item's id, or null
/// when cancelled.
Future<String?> showItemEditor(
  BuildContext context, {
  Item? item,
  ItemType type = ItemType.genericSecret,
  String? app,
  String? platform,
  String? env,
}) {
  final draft = item == null
      ? ItemDraft.create(type, appId: app, platform: platform, environment: env)
      : ItemDraft.edit(item);
  if (DesktopTheme.maybeOf(context) != null) {
    return showDesktopSheet<String>(
      context,
      builder: (_) => ItemEditor(draft: draft),
    );
  }
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
/// notes. Values read from a file are shown but locked. A secure note has
/// no fields or expiry: its body, in the WYSIWYG note editor, takes their
/// place.
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
  final _tagInput = DesktopTokenController();
  late final _notes = TextEditingController(text: _draft.notes);

  /// A secure note's body, as the note editor last reported it.
  late String _body = _draft.notes;
  Map<String, String> _errors = const {};
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _tagInput.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Desktop: why the expiry typed into the date field isn't a date yet,
  /// if it isn't. Checked on save.
  DesktopDateProblem? _expiryProblem;

  bool get _desktop => DesktopTheme.maybeOf(context) != null;

  bool get _isNote => _draft.type == ItemType.secureNote;

  /// Changes the new item's type. Notes typed so far go with it: into a
  /// secure note's body, or back out into the notes field.
  void _changeType(ItemType type) {
    final wasNote = _isNote;
    setState(() => _draft.changeType(type));
    if (_isNote && !wasNote) _body = _notes.text;
    if (!_isNote && wasNote) _notes.text = _body;
  }

  Future<void> _save() async {
    _draft
      ..title = _title.text
      ..notes = _isNote ? _body : _notes.text;
    if (_isNote) {
      // A secure note is its body: what was typed into fields or an expiry
      // before the type changed isn't shown, so it isn't saved either.
      _draft
        ..fields.clear()
        ..expiresAt = null;
    }
    // On a desktop the token field keeps the draft's tags as it goes; a
    // tag still being typed is added here.
    _draft.tags = _desktop
        ? _tagInput.commit(_draft.tagList).join(', ')
        : _tags.text;
    final expiryError = _desktop && !_draft.expiryFromFile
        ? switch (_expiryProblem) {
            DesktopDateProblem.unreadable =>
              'Type the date as YYYY-MM-DD, or pick it',
            DesktopDateProblem.noSuchDate => 'No such date',
            null => null,
          }
        : null;
    final errors = {..._draft.validate(), 'expiry': ?expiryError};
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
    if (_desktop) return _sheet(context);
    final session = ref.watch(vaultSessionProvider);
    final apps = session is Unlocked
        ? (session.index.apps.values.toList()..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
          ))
        : <AppRecord>[];
    final draft = _draft;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BCDialogTitle(switch ((draft.isNew, _isNote)) {
          (true, true) => 'New secure note',
          (true, false) => 'New item',
          (false, true) => 'Edit note',
          (false, false) => 'Edit item',
        }),
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
            onValueChange: _changeType,
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
                options: {for (final app in apps) app.id: app.label},
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
        if (_isNote) ...[
          const _Label('Note'),
          SecureNoteEditor(
            key: const ValueKey('secure-note-body'),
            initialMarkdown: _body,
            minHeight: 220,
            onChanged: (markdown) => _body = markdown,
          ),
        ] else ...[
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
          PhoneNotesField(
            controller: _notes,
            fieldKey: const ValueKey('item-notes'),
          ),
        ],
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
              child: Text(
                draft.isNew ? (_isNote ? 'Add note' : 'Add item') : 'Save',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Desktop (N03e): a sheet with a classic form. Same fields and rules as
  // the phone form above.
  // -------------------------------------------------------------------------

  static const double _labelWidth = 100;

  Widget _sheet(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    final unlocked = session is Unlocked ? session : null;
    final apps = [...?unlocked?.index.apps.values]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final items = unlocked?.index.items.values ?? const <Item>[];
    final draft = _draft;
    final base = draft.base;
    final placeWidth = DesktopMetrics.placeFieldWidth(context.desktopKit);

    return DesktopSheet(
      width: _isNote ? 720 : 640,
      title: base == null
          ? (_isNote ? 'New secure note' : 'New item')
          : 'Edit “${base.title}”',
      leadingAction: _saving
          ? const DesktopProgress(semanticLabel: 'Saving')
          : null,
      actions: [
        DesktopButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        DesktopButton(
          label: draft.isNew ? (_isNote ? 'Add note' : 'Add item') : 'Save',
          kind: DesktopButtonKind.primary,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            DesktopForm(
              labelWidth: _labelWidth,
              children: [
                DesktopFormRow(
                  label: 'Type',
                  child: draft.isNew
                      ? SheetNote(
                          width: 240,
                          control: DesktopPopup<ItemType>(
                            value: draft.type,
                            choices: [
                              for (final type in ItemType.values)
                                DesktopChoice(type, type.label),
                            ],
                            onChanged: _changeType,
                          ),
                        )
                      // An item keeps its type.
                      : Row(
                          spacing: 6,
                          children: [
                            DesktopTypeTile(type: draft.type, size: 20),
                            Text(draft.type.label),
                          ],
                        ),
                ),
                DesktopFormRow(
                  label: 'Name',
                  child: SheetNote(
                    tone: NoteTone.problem,
                    note: _errors['title'],
                    control: DesktopTextField(
                      key: const ValueKey('item-name'),
                      controller: _title,
                      autofocus: draft.isNew,
                      placeholder: 'e.g. Upload keystore',
                    ),
                  ),
                ),
                DesktopFormRow(
                  label: 'Place',
                  child: Row(
                    spacing: DesktopMetrics.formLabelGap,
                    children: [
                      // The rest: an app's label carries its organization
                      // ("Acme Corp › Billing API") and ends in an ellipsis.
                      Expanded(
                        child: DesktopPopup<String>(
                          // An app deleted since shows as no app, as in the
                          // sidebar.
                          value: apps.any((a) => a.id == draft.appId)
                              ? draft.appId!
                              : '',
                          choices: [
                            const DesktopChoice('', 'No app'),
                            for (final app in apps)
                              DesktopChoice(app.id, app.label),
                          ],
                          onChanged: (id) => setState(
                            () => draft.appId = id.isEmpty ? null : id,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: placeWidth,
                        child: DesktopComboBox(
                          key: const ValueKey('item-platform'),
                          value: draft.platform ?? '',
                          placeholder: 'Platform',
                          menuLabel: 'Platform suggestions',
                          suggestions: placeSuggestions(
                            ItemTemplates.platforms,
                            items.map((i) => i.platform),
                          ),
                          onChanged: (text) =>
                              setState(() => draft.platform = typedPlace(text)),
                        ),
                      ),
                      SizedBox(
                        width: placeWidth,
                        child: DesktopComboBox(
                          key: const ValueKey('item-environment'),
                          value: draft.environment ?? '',
                          placeholder: 'Environment',
                          menuLabel: 'Environment suggestions',
                          suggestions: placeSuggestions(
                            ItemTemplates.environments,
                            items.map((i) => i.environment),
                          ),
                          onChanged: (text) => setState(
                            () => draft.environment = typedPlace(text),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                DesktopFormRow(
                  label: 'Tags',
                  child: DesktopTokenField(
                    controller: _tagInput,
                    tokens: draft.tagList,
                    placeholder: 'Press Return after each tag',
                    onChanged: (tags) =>
                        setState(() => draft.tags = tags.join(', ')),
                  ),
                ),
              ],
            ),
            if (_isNote)
              SecureNoteEditor(
                key: const ValueKey('secure-note-body'),
                initialMarkdown: _body,
                onChanged: (markdown) => _body = markdown,
              )
            else ...[
              _FieldTable(
                fields: draft.fields,
                errors: _errors,
                onRemove: (field) => setState(() => draft.fields.remove(field)),
                onAdd: () => setState(() => draft.fields.add(DraftField())),
                onChanged: () => setState(() {}),
              ),
              DesktopForm(
                labelWidth: _labelWidth,
                children: [
                  DesktopFormRow(
                    label: 'Expires',
                    child: switch (draft.expiresAt) {
                      // Read from the file: shown with its source, not
                      // editable.
                      final expiresAt? when draft.expiryFromFile => Row(
                        spacing: 10,
                        children: [
                          Text(DateFormat.yMMMd().format(expiresAt.toLocal())),
                          const SourceTag('From the file'),
                        ],
                      ),
                      _ => SheetNote(
                        width: 160,
                        tone: _errors.containsKey('expiry')
                            ? NoteTone.problem
                            : NoteTone.hint,
                        note:
                            _errors['expiry'] ??
                            'Set by you · leave empty for no expiry',
                        // Picked or typed by the user: a date, kept as
                        // midnight UTC with the user as its source.
                        control: DesktopDateField(
                          key: const ValueKey('item-expiry'),
                          value: switch (draft.expiresAt?.toUtc()) {
                            final utc? => DateTime(
                              utc.year,
                              utc.month,
                              utc.day,
                            ),
                            null => null,
                          },
                          placeholder: 'No expiry date',
                          calendarLabel: 'Choose expiry date',
                          onProblem: (problem) => _expiryProblem = problem,
                          onChanged: (date) => setState(
                            () => draft.expiresAt = date == null
                                ? null
                                : DateTime.utc(date.year, date.month, date.day),
                          ),
                        ),
                      ),
                    },
                  ),
                  DesktopFormRow(
                    label: 'Notes',
                    child: DesktopNotesEditor(
                      controller: _notes,
                      fieldKey: const ValueKey('item-notes'),
                    ),
                  ),
                ],
              ),
            ],
            if (_saveError case final error?)
              SheetNotice(
                symbol: DesktopSymbol.alert,
                problem: true,
                child: Text(error),
              ),
          ],
        ),
      ),
    );
  }
}

/// The fields as a table (N03e): name, value, and whether it's secret.
/// Fields read from the file are shown, not editable.
class _FieldTable extends StatelessWidget {
  const _FieldTable({
    required this.fields,
    required this.errors,
    required this.onRemove,
    required this.onAdd,
    required this.onChanged,
  });

  final List<DraftField> fields;
  final Map<String, String> errors;
  final ValueChanged<DraftField> onRemove;
  final VoidCallback onAdd;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final header = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      fontWeight: FontWeight.w600,
      color: colors.secondaryText,
    );
    Widget rule() =>
        SizedBox(height: 0.5, child: ColoredBox(color: colors.innerSeparator));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.groupBoxInner,
        border: Border.all(color: colors.groupBoxStroke, width: 0.5),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.menuRadius + 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: colors.bar,
            child: SizedBox(
              height: DesktopMetrics.tableHeaderHeight,
              child: _FieldColumns(
                name: Text('Field', style: header),
                value: Text('Value', style: header),
                secret: Text('Secret', style: header),
              ),
            ),
          ),
          for (final (i, field) in fields.indexed) ...[
            rule(),
            _FieldRow(
              key: ObjectKey(field),
              field: field,
              error: errors['$i'],
              onRemove: () => onRemove(field),
              onChanged: onChanged,
            ),
          ],
          rule(),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: DesktopButton(label: 'Add Field', onPressed: onAdd),
            ),
          ),
        ],
      ),
    );
  }
}

/// The table's columns: name, value (the rest), secret, then room for the
/// remove button.
class _FieldColumns extends StatelessWidget {
  const _FieldColumns({
    required this.name,
    required this.value,
    required this.secret,
    this.remove,
  });

  final Widget name;
  final Widget value;
  final Widget secret;
  final Widget? remove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        spacing: 10,
        children: [
          SizedBox(width: 150, child: name),
          Expanded(child: value),
          SizedBox(width: 96, child: secret),
          SizedBox(width: DesktopMetrics.toolbarSearchHeight, child: remove),
        ],
      ),
    );
  }
}

/// One field: a file fact (locked) or the user's own (name, value with
/// show / hide when secret, the secret box, remove).
class _FieldRow extends StatefulWidget {
  const _FieldRow({
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
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
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
    final colors = context.desktopColors;
    final field = widget.field;
    final mono = AppText.mono(
      context,
      fontSize: 12,
    ).copyWith(color: colors.text);
    final Widget row;
    if (field.fromFile) {
      row = _FieldColumns(
        name: Text(field.name),
        value: field.secret
            ? Text(SecretRow.mask, style: mono)
            : Text(
                field.value,
                style: mono,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        secret: const SourceTag('From file'),
      );
    } else {
      final name = field.name.isEmpty ? 'Field' : field.name;
      row = _FieldColumns(
        name: Semantics(
          label: 'Field name',
          child: DesktopTextField(
            controller: _name,
            placeholder: 'Name',
            onChanged: (v) => field.name = v,
          ),
        ),
        value: Row(
          spacing: 2,
          children: [
            Expanded(
              child: Semantics(
                label: '$name value',
                child: DesktopTextField(
                  controller: _value,
                  obscureText: field.secret && !_revealed,
                  mono: true,
                  placeholder: field.secret ? 'Secret value' : 'Value',
                  onChanged: (v) => field.value = v,
                ),
              ),
            ),
            if (field.secret)
              DesktopIconButton(
                symbol: _revealed
                    ? DesktopSymbol.conceal
                    : DesktopSymbol.reveal,
                tooltip: _revealed ? 'Hide value' : 'Show value',
                onPressed: () => setState(() => _revealed = !_revealed),
              ),
          ],
        ),
        secret: Semantics(
          label: field.secret
              ? 'Secret: masked, never searched'
              : 'Mark $name secret',
          child: DesktopCheckbox(
            label: '',
            value: field.secret,
            onChanged: (secret) {
              setState(() {
                field.secret = secret;
                _revealed = false;
              });
              widget.onChanged();
            },
          ),
        ),
        remove: DesktopIconButton(
          symbol: DesktopSymbol.remove,
          tooltip: 'Remove $name',
          onPressed: widget.onRemove,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesktopMetrics.toolbarSearchHeight,
            ),
            child: Center(child: row),
          ),
          if (widget.error case final error?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                error,
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize,
                  color: colors.danger,
                ),
              ),
            ),
        ],
      ),
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
