import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart'
    show
        LiquidGlassAlert,
        LiquidGlassAlertAction,
        LiquidGlassAlertStyle,
        LiquidGlassToggle;
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/item_templates.dart';
import '../../data/providers.dart';
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
    show NoteTone, PlaceKind, SheetNote, SheetNotice, SourceTag;
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
  // Phones: a page of its own (design frames I10, I11).
  return GoRouter.of(context).push<String>(
    item == null
        ? Routes.newItem(
            type: type.wireName,
            app: app,
            platform: platform,
            env: env,
          )
        : Routes.editItem(item.id),
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
        : [..._tagChips, _tags.text].join(', ');
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
      if (mounted) _close(saved.id);
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
    return _page(context);
  }

  /// Tags typed so far on a phone, as chips; the tag field adds to them.
  late final List<String> _tagChips = [..._draft.tagList];

  void _addTags(String text) {
    final added = [
      for (final tag in text.split(','))
        if (tag.trim().replaceFirst('#', '').isNotEmpty)
          tag.trim().replaceFirst('#', ''),
    ];
    if (added.isEmpty) return;
    setState(() {
      for (final tag in added) {
        if (!_tagChips.contains(tag)) _tagChips.add(tag);
      }
      _tags.clear();
    });
  }

  /// The form as a page of its own on a phone (design frames I10, I11):
  /// Cancel and Add / Save in the bar, then the type, the name, where it
  /// belongs, expiry, fields (the file's locked, the user's as cards),
  /// tags and notes.
  Widget _page(BuildContext context) {
    final bc = context.bcTheme;
    final native = ref.watch(nativeBarsProvider);
    final session = ref.watch(vaultSessionProvider);
    final apps = session is Unlocked
        ? (session.index.apps.values.toList()..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
          ))
        : <AppRecord>[];
    final draft = _draft;
    final title = switch ((draft.isNew, _isNote)) {
      (true, true) => 'New secure note',
      (true, false) => 'New item',
      (false, true) => 'Edit note',
      (false, false) => 'Edit item',
    };
    final saveLabel = draft.isNew
        ? (_isNote ? 'Add note' : 'Add item')
        : 'Save';
    void cancel() => _close();
    final app = apps.where((a) => a.id == draft.appId).firstOrNull;
    final fileFields = [
      for (final field in draft.fields)
        if (field.fromFile) field,
    ];
    final ownFields = [
      for (final (i, field) in draft.fields.indexed)
        if (!field.fromFile) (i, field),
    ];

    final form = <Widget>[
      if (draft.isNew)
        _PageSection(
          title: 'Type',
          child: native
              ? _TypeRow(
                  type: draft.type,
                  onPressed: () => _chooseType(context),
                )
              : BCSelect<ItemType>(
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
        )
      else
        _TypeRow(
          type: draft.type,
          detail: switch (draft.base?.attachments.firstOrNull) {
            final file? => '${file.filename} · ${Format.bytes(file.size)}',
            null => null,
          },
        ),
      _PageSection(
        title: 'Name',
        required: true,
        child: BCTextField(
          isRequired: true,
          isInvalid: _errors.containsKey('title'),
          children: [
            BCTextFieldInput(
              controller: _title,
              autofocus: draft.isNew,
              hintText: 'e.g. Upload keystore',
            ),
            if (_errors['title'] case final error?) BCTextFieldError(error),
          ],
        ),
      ),
      _PageSection(
        title: 'Where it belongs',
        child: BCListGroup(
          children: [
            ChoiceRow<String?>(
              native: native,
              compact: true,
              title: 'App',
              value: app?.id,
              leading: app == null ? null : AppBadge(app: app, size: 20),
              options: {null: 'No app', for (final a in apps) a.id: a.label},
              onChanged: (v) => setState(() => draft.appId = v),
            ),
            ChoiceRow<String?>(
              native: native,
              compact: true,
              title: 'Platform',
              value: draft.platform,
              options: {
                null: 'None',
                for (final p in {...ItemTemplates.platforms, ?draft.platform})
                  p: VaultLabels.platform(p),
              },
              onChanged: (v) => setState(() => draft.platform = v),
            ),
            ChoiceRow<String?>(
              native: native,
              compact: true,
              title: 'Environment',
              value: draft.environment,
              options: {
                null: 'None',
                for (final e in {
                  ...ItemTemplates.environments,
                  ?draft.environment,
                })
                  e: VaultLabels.environment(e),
              },
              onChanged: (v) => setState(() => draft.environment = v),
            ),
          ],
        ),
      ),
      if (_isNote)
        _PageSection(
          title: 'Note',
          child: SecureNoteEditor(
            key: const ValueKey('secure-note-body'),
            initialMarkdown: _body,
            minHeight: 220,
            onChanged: (markdown) => _body = markdown,
          ),
        )
      else ...[
        _PageSection(
          title: 'Expiry',
          child: _Expiry(
            draft: draft,
            onChanged: (date) => setState(() => draft.expiresAt = date),
          ),
        ),
        if (fileFields.isNotEmpty)
          _PageSection(
            title: 'From the file',
            locked: true,
            child: _LockedFields(fields: fileFields),
          ),
        _PageSection(
          title: draft.isNew || fileFields.isEmpty ? 'Fields' : 'Your fields',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: BCSpacing.sm,
            children: [
              for (final (i, field) in ownFields)
                _FieldCard(
                  key: ObjectKey(field),
                  field: field,
                  native: native,
                  error: _errors['$i'],
                  onRemove: () => setState(() => draft.fields.remove(field)),
                  onChanged: () => setState(() {}),
                ),
              BCButton(
                variant: BCButtonVariant.secondary,
                fullWidth: true,
                onPressed: () => setState(() => draft.fields.add(DraftField())),
                startContent: const Icon(LucideIcons.plus, size: 17),
                child: const Text('Add field'),
              ),
            ],
          ),
        ),
      ],
      _PageSection(
        title: 'Tags',
        child: _TagsField(
          tags: _tagChips,
          controller: _tags,
          onAdd: _addTags,
          onRemove: (tag) => setState(() => _tagChips.remove(tag)),
        ),
      ),
      if (!_isNote)
        _PageSection(
          title: 'Notes',
          child: PhoneNotesField(
            controller: _notes,
            fieldKey: const ValueKey('item-notes'),
          ),
        ),
      if (_saveError case final error?)
        BCText(
          error,
          type: BCTextType.bodySm,
          style: TextStyle(color: bc.danger),
        ),
    ];

    return Scaffold(
      backgroundColor: bc.background,
      extendBodyBehindAppBar: native,
      appBar: native
          ? NativePhoneHeader(
              title: title,
              onBack: cancel,
              backSymbol: 'xmark',
              actions: [
                NativeHeaderAction(
                  id: 'save',
                  label: draft.isNew ? 'Add' : 'Save',
                  onPressed: _saving ? () {} : _save,
                ),
              ],
            )
          : BCAppHeader(
              variant: BCAppHeaderVariant.solid,
              automaticallyImplyLeading: false,
              leading: BCHeaderIconButton(
                size: 48,
                icon: const Icon(LucideIcons.x, semanticLabel: 'Cancel'),
                onPressed: cancel,
              ),
              title: Text(title),
              actions: [
                BCButton(
                  size: BCButtonSize.sm,
                  isDisabled: _saving,
                  onPressed: _save,
                  startContent: _saving
                      ? const BCSpinner(size: BCSpinnerSize.sm)
                      : null,
                  child: Text(saveLabel),
                ),
              ],
            ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          16,
          (native
                  ? MediaQuery.paddingOf(context).top +
                        NativePhoneHeader.barHeight
                  : 0) +
              12,
          16,
          48 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: form,
        ),
      ),
    );
  }

  /// Closes the form with the saved item's [id], or nothing. On a phone
  /// it's one of the router's pages. Saving changes the vault, which makes
  /// the router rebuild its pages; a pop already under way then has its
  /// page put back. So the page pops after that frame.
  void _close([String? id]) {
    if (_desktop) {
      Navigator.of(context).pop(id);
      return;
    }
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) context.pop(id);
      })
      ..ensureVisualUpdate();
  }

  /// iPhone: the new item's type from UIKit's action sheet.
  Future<void> _chooseType(BuildContext context) async {
    final id = await LiquidGlassAlert.show(
      context: context,
      title: 'Type: ${_draft.type.label}',
      style: LiquidGlassAlertStyle.actionSheet,
      actions: [
        for (final type in ItemType.values)
          LiquidGlassAlertAction(id: type.wireName, title: type.label),
        const LiquidGlassAlertAction(
          id: 'cancel',
          title: 'Cancel',
          isCancel: true,
        ),
      ],
    );
    if (ItemType.fromWireName(id ?? '') case final type?) _changeType(type);
  }

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
                          value: PlaceKind.platform.label(draft.platform),
                          placeholder: 'Platform',
                          menuLabel: 'Platform suggestions',
                          suggestions: PlaceKind.platform.suggestions(
                            items.map((i) => i.platform),
                          ),
                          onChanged: (text) => setState(
                            () =>
                                draft.platform = PlaceKind.platform.value(text),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: placeWidth,
                        child: DesktopComboBox(
                          key: const ValueKey('item-environment'),
                          value: PlaceKind.environment.label(draft.environment),
                          placeholder: 'Environment',
                          menuLabel: 'Environment suggestions',
                          suggestions: PlaceKind.environment.suggestions(
                            items.map((i) => i.environment),
                          ),
                          onChanged: (text) => setState(
                            () => draft.environment = PlaceKind.environment
                                .value(text),
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
                remove: Text('Remove', style: header),
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

/// A field row's least height: an editable row's text fields and
/// buttons, and the same for a locked one.
const double _fieldRowHeight = 36;

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
          SizedBox(width: 180, child: name),
          Expanded(child: value),
          SizedBox(width: 48, child: Center(child: secret)),
          SizedBox(width: 52, child: Center(child: remove)),
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
      // Read from the file and locked: indented like the fields' text, the
      // "From file" tag in the value cell, and Secret showing what the file
      // said (P7-05; the tag used to sit in the Secret column).
      row = _FieldColumns(
        name: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(field.name),
        ),
        value: Row(
          spacing: 6,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: field.secret
                    ? Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SecretMask(color: colors.text),
                      )
                    : Text(
                        field.value,
                        style: mono,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
            const SourceTag('From file'),
          ],
        ),
        secret: DesktopCheckbox(
          label: '',
          value: field.secret,
          onChanged: null,
        ),
      );
    } else {
      final name = field.name.isEmpty ? 'Field' : field.name;
      final masked = field.secret && !_revealed;
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
                  // A new field when the dots go, so it can grow: a masked
                  // field holds one line, a shown value wraps to its full
                  // length (a connection string, a key).
                  key: ValueKey(masked),
                  controller: _value,
                  obscureText: masked,
                  mono: true,
                  minLines: 1,
                  maxLines: masked ? 1 : 6,
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
          // One height for every row, locked or editable, at least. A
          // field is never squeezed: the system font can need more than
          // the tests' font, and a shown value wraps to more lines.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _fieldRowHeight),
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

/// The expiry date: picked by the user (and marked as theirs), or shown
/// locked when it was read from the file.
class _Expiry extends StatelessWidget {
  const _Expiry({required this.draft, required this.onChanged});

  final ItemDraft draft;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final expiresAt = draft.expiresAt;
    if (draft.expiryFromFile && expiresAt != null) {
      return BCListGroup(
        children: [
          BCListGroupItem(
            title: DateFormat.yMMMd().format(expiresAt.toLocal()),
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: BCSpacing.sm,
              children: [
                const ProvenanceLabel(source: ExpirySource.file),
                Icon(LucideIcons.lock, size: 15, color: bc.muted),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      spacing: BCSpacing.sm,
      children: [
        Expanded(
          child: Semantics(
            label: 'Expiry date',
            child: BCDateField(
              value: expiresAt?.toLocal(),
              placeholder: 'No expiry date',
              presentation: BCPickerPresentation.bottomSheet,
              formatDate: DateFormat.yMMMd().format,
              onChanged: (date) =>
                  onChanged(DateTime.utc(date.year, date.month, date.day)),
            ),
          ),
        ),
        if (expiresAt != null)
          BCButton(
            variant: BCButtonVariant.ghost,
            onPressed: () => onChanged(null),
            child: const Text('Clear'),
          ),
      ],
    );
  }
}

/// A section of the phone form: its name over its content.
class _PageSection extends StatelessWidget {
  const _PageSection({
    required this.title,
    required this.child,
    this.required = false,
    this.locked = false,
  });

  final String title;
  final Widget child;
  final bool required;

  /// The values under it came from the file and can't change.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: BCSpacing.sm,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            header: true,
            child: Row(
              spacing: 4,
              children: [
                BCText(
                  title.toUpperCase(),
                  type: BCTextType.bodyXs,
                  weight: BCTextWeight.semibold,
                  color: BCTextColor.muted,
                ),
                if (required)
                  BCText(
                    '*',
                    type: BCTextType.bodyXs,
                    weight: BCTextWeight.semibold,
                    style: TextStyle(color: bc.dangerSoftForeground),
                  ),
                if (locked) Icon(LucideIcons.lock, size: 11, color: bc.muted),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The item's type: a row that opens the choice for a new item on iPhone
/// ([onPressed]), or a fixed one, with its file, when editing.
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, this.onPressed, this.detail});

  final ItemType type;
  final VoidCallback? onPressed;

  /// Under the type's name instead of what it's for, e.g. the file.
  final String? detail;

  /// What each type is for, under its name.
  static String about(ItemType type) => switch (type) {
    ItemType.appleAuthKey => 'A .p8 key for APNs or App Store Connect',
    ItemType.appleCertificate => 'A signing certificate, .cer or .p12',
    ItemType.provisioningProfile => 'A .mobileprovision profile',
    ItemType.androidKeystore => 'A .jks or .keystore for signing',
    ItemType.firebaseConfig => 'google-services.json or a GoogleService plist',
    ItemType.gcpServiceAccount => 'A service account key, .json',
    ItemType.oauthClient => 'A client ID and its secret',
    ItemType.sshKey => 'A private key and its passphrase',
    ItemType.genericFile => 'Any other file',
    ItemType.genericSecret => 'An API key, token or password',
    ItemType.secureNote => 'A Markdown note, encrypted',
  };

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Semantics(
      button: onPressed != null,
      label: 'Type, ${type.label}',
      excludeSemantics: true,
      child: BCListGroup(
        children: [
          BCListGroupItem(
            prefix: TypeIconTile(type: type),
            title: type.label,
            description: detail ?? about(type),
            onPressed: onPressed,
            suffix: Icon(
              onPressed == null ? LucideIcons.lock : LucideIcons.chevronsUpDown,
              size: 15,
              color: bc.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fields read from the file: shown, never edited (secrets masked).
class _LockedFields extends StatelessWidget {
  const _LockedFields({required this.fields});

  final List<DraftField> fields;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return BCListGroup(
      children: [
        for (final field in fields)
          BCListGroupItem(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                BCText(
                  Format.fieldLabel(field.name),
                  type: BCTextType.bodySm,
                  color: BCTextColor.muted,
                ),
                if (field.secret)
                  SecretMask(color: bc.foreground)
                else
                  Text(
                    field.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(context),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One of the user's own fields as a card: its name, its value (hidden
/// when secret, with show / hide), whether it's secret, and remove.
class _FieldCard extends StatefulWidget {
  const _FieldCard({
    super.key,
    required this.field,
    required this.native,
    required this.onRemove,
    required this.onChanged,
    this.error,
  });

  final DraftField field;
  final bool native;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final String? error;

  @override
  State<_FieldCard> createState() => _FieldCardState();
}

class _FieldCardState extends State<_FieldCard> {
  late final _name = TextEditingController(text: widget.field.name);
  late final _value = TextEditingController(text: widget.field.value);
  bool _revealed = false;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  void _setSecret(bool secret) {
    setState(() => widget.field.secret = secret);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final field = widget.field;
    final hidden = field.secret && !_revealed;
    final name = field.name.isEmpty ? 'field' : field.name;

    return BCCard(
      padding: const EdgeInsets.all(BCSpacing.sm + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: BCSpacing.sm,
        children: [
          Row(
            spacing: BCSpacing.sm,
            children: [
              Expanded(
                child: Semantics(
                  label: 'Field name',
                  child: BCInput(
                    controller: _name,
                    isInvalid: widget.error != null,
                    placeholder: 'Name, e.g. API key',
                    onChanged: (v) => setState(() => field.name = v),
                  ),
                ),
              ),
              BCButton(
                variant: BCButtonVariant.ghost,
                isIconOnly: true,
                onPressed: widget.onRemove,
                child: Icon(
                  LucideIcons.trash2,
                  size: 18,
                  color: bc.danger,
                  semanticLabel: 'Remove $name',
                ),
              ),
            ],
          ),
          Row(
            spacing: BCSpacing.sm,
            children: [
              Expanded(
                child: Semantics(
                  label: '${field.name.isEmpty ? 'Field' : field.name} value',
                  child: BCInput(
                    controller: _value,
                    obscureText: hidden,
                    placeholder: field.secret ? 'Secret value' : 'Value',
                    // Keys and IDs aren't words.
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (v) => field.value = v,
                  ),
                ),
              ),
              if (field.secret)
                BCButton(
                  variant: BCButtonVariant.ghost,
                  isIconOnly: true,
                  onPressed: () => setState(() => _revealed = !_revealed),
                  child: Icon(
                    _revealed ? LucideIcons.eyeOff : LucideIcons.eye,
                    size: 18,
                    semanticLabel: _revealed ? 'Hide value' : 'Show value',
                  ),
                ),
            ],
          ),
          if (widget.error case final error?)
            BCText(
              error,
              type: BCTextType.bodyXs,
              style: TextStyle(color: bc.danger),
            ),
          MergeSemantics(
            child: Row(
              spacing: BCSpacing.sm + 2,
              children: [
                Icon(LucideIcons.lock, size: 16, color: bc.muted),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 1,
                    children: [
                      BCText('Secret'),
                      BCText(
                        'Hidden until revealed, never searched',
                        type: BCTextType.bodyXs,
                        color: BCTextColor.muted,
                      ),
                    ],
                  ),
                ),
                if (widget.native)
                  LiquidGlassToggle(
                    value: field.secret,
                    onChanged: _setSecret,
                    color: bc.accent,
                    height: 32,
                  )
                else
                  BCSwitch(
                    isSelected: field.secret,
                    onSelectedChange: _setSecret,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tags as chips, removable, and a field that adds more (Return or a
/// comma).
class _TagsField extends StatelessWidget {
  const _TagsField({
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> tags;
  final TextEditingController controller;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: BCSpacing.sm,
      children: [
        if (tags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in tags)
                Semantics(
                  button: true,
                  label: 'Remove tag $tag',
                  excludeSemantics: true,
                  child: BCChip(
                    variant: BCChipVariant.soft,
                    color: BCChipColor.accent,
                    endContent: const Icon(LucideIcons.x, size: 13),
                    onPressed: () => onRemove(tag),
                    child: Text('#$tag'),
                  ),
                ),
            ],
          ),
        Semantics(
          label: 'Add tag',
          child: BCInput(
            controller: controller,
            placeholder: 'Add tag, e.g. release',
            onChanged: (text) {
              if (text.contains(',')) onAdd(text);
            },
            onSubmitted: onAdd,
          ),
        ),
      ],
    );
  }
}
