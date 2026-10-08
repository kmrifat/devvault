import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart'
    show
        DesktopButton,
        DesktopButtonKind,
        DesktopChoice,
        DesktopComboBox,
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
        showDesktopSheet;
import '../../shared/ui.dart';
import '../import/place_fields.dart'
    show NoteTone, SheetNote, SheetNotice, isNarrowSheet;
import 'app_draft.dart';

/// Opens the app form: [app] to edit it, or null for a new app. Resolves
/// to the saved app's id, or null when cancelled.
Future<String?> showAppEditor(BuildContext context, {AppRecord? app}) {
  final draft = app == null ? AppDraft.create() : AppDraft.edit(app);
  if (DesktopTheme.maybeOf(context) != null) {
    return showDesktopSheet<String>(
      context,
      builder: (_) => AppEditor(draft: draft),
    );
  }
  return BCDialog.show<String>(
    context,
    builder: (_) => BCDialogContent(
      width: 520,
      showCloseButton: true,
      child: AppEditor(draft: draft),
    ),
  );
}

const _about =
    'An app, site, service or tool you keep credentials for. Items are '
    'grouped by app in the sidebar, and every identifier is searchable.';

/// The choices of the Kind pop-up: Not set (''), every [AppKind], and a
/// newer kind kept from the record as it is.
List<(String, String)> _kindChoices(String? current) => [
  ('', 'Not set'),
  for (final kind in AppKind.values) (kind.wireName, kind.label),
  if (current != null && AppKind.fromWireName(current) == null)
    (current, current),
];

/// The choices of an identifier's kind pop-up: every [IdentifierKind],
/// and a newer kind kept from the record as it is.
List<(String, String)> _identifierChoices(String? current) => [
  for (final kind in IdentifierKind.values) (kind.wireName, kind.label),
  if (current != null && IdentifierKind.fromWireName(current) == null)
    (current, current),
];

/// The placeholder of an identifier's value field.
String _hintFor(IdentifierKind? kind) => switch (kind) {
  IdentifierKind.bundleId => 'com.example.app',
  IdentifierKind.packageName => 'com.example.android',
  IdentifierKind.domain => 'api.example.com',
  IdentifierKind.url => 'https://example.com/admin',
  IdentifierKind.repository => 'github.com/example/app',
  _ => 'Value',
};

/// The app form: its name, the organization it's for, what kind of app it
/// is, and its identifiers (bundle IDs, package names, domains, URLs,
/// repositories …), which tie items to it and are searchable. Nothing is
/// filled in for the user: organization and kind start empty, and a new
/// identifier has no kind until one is picked.
class AppEditor extends ConsumerStatefulWidget {
  const AppEditor({super.key, required this.draft});

  final AppDraft draft;

  @override
  ConsumerState<AppEditor> createState() => _AppEditorState();
}

class _AppEditorState extends ConsumerState<AppEditor> {
  late final AppDraft _draft = widget.draft;
  late final _name = TextEditingController(text: _draft.name);
  late final _organization = TextEditingController(text: _draft.organization);
  Map<String, String> _errors = const {};
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _organization.addListener(() {
      if (_organization.text == _draft.organization) return;
      setState(() => _draft.organization = _organization.text);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _organization.dispose();
    super.dispose();
  }

  /// The organizations the vault's apps already name: suggestions only.
  List<String> get _organizations {
    final session = ref.watch(vaultSessionProvider);
    return session is Unlocked ? session.index.organizations : const [];
  }

  Future<void> _save() async {
    _draft.name = _name.text;
    final session = ref.read(vaultSessionProvider);
    final others = session is Unlocked
        ? session.index.apps.values
        : const <AppRecord>[];
    final errors = _draft.validate(others);
    setState(() {
      _errors = errors;
      _saveError = null;
    });
    if (errors.isNotEmpty || _saving) return;
    setState(() => _saving = true);
    final notifier = ref.read(vaultSessionProvider.notifier);
    try {
      final saved = await notifier.saveApp(_draft.toApp(notifier.newApp));
      if (mounted) Navigator.of(context).pop(saved.id);
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = "Couldn't save the app. Nothing was changed.";
        });
      }
    }
  }

  void _addIdentifier() =>
      setState(() => _draft.identifiers.add(DraftIdentifier()));

  void _removeIdentifier(DraftIdentifier id) => setState(() {
    _draft.identifiers.remove(id);
    // Errors are keyed by position, which just moved.
    _errors = const {};
  });

  @override
  Widget build(BuildContext context) {
    if (DesktopTheme.maybeOf(context) != null) return _sheet(context);
    final bc = context.bcTheme;
    final typed = _organization.text.trim().toLowerCase();
    final suggestions = [
      for (final org in _organizations)
        if (org.toLowerCase() != typed && org.toLowerCase().contains(typed))
          org,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BCDialogTitle(_draft.isNew ? 'New app' : 'Edit app'),
        const SizedBox(height: BCSpacing.xs),
        const BCDialogDescription(_about),
        const SizedBox(height: BCSpacing.lg),
        BCTextField(
          isRequired: true,
          isInvalid: _errors.containsKey('name'),
          children: [
            const BCTextFieldLabel('Name'),
            BCTextFieldInput(
              key: const ValueKey('app-name'),
              controller: _name,
              autofocus: true,
              hintText: 'e.g. Billing API',
              onSubmitted: (_) => _save(),
            ),
            if (_errors['name'] case final error?) BCTextFieldError(error),
          ],
        ),
        const SizedBox(height: BCSpacing.md),
        BCTextField(
          children: [
            const BCTextFieldLabel('Organization'),
            BCTextFieldInput(
              key: const ValueKey('app-organization'),
              controller: _organization,
              hintText: 'None',
              textCapitalization: TextCapitalization.words,
            ),
            const BCTextFieldDescription(
              'Who it’s for: an employer, a client. Optional.',
            ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: BCSpacing.sm),
          Semantics(
            container: true,
            label: 'Organizations in this vault',
            child: Wrap(
              spacing: BCSpacing.sm,
              runSpacing: BCSpacing.sm,
              children: [
                for (final org in suggestions)
                  BCChip(
                    size: BCChipSize.md,
                    variant: BCChipVariant.secondary,
                    color: BCChipColor.defaultColor,
                    startContent: const Icon(LucideIcons.building2, size: 14),
                    onPressed: () => _organization.value = TextEditingValue(
                      text: org,
                      selection: TextSelection.collapsed(offset: org.length),
                    ),
                    child: Text(org),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: BCSpacing.md),
        const _Label('Kind'),
        BCSelect<String>(
          key: const ValueKey('app-kind'),
          listLabel: 'Kind',
          presentation: isNarrowSheet(context)
              ? BCSelectPresentation.bottomSheet
              : BCSelectPresentation.popover,
          value: _draft.kindName ?? '',
          items: [
            for (final (value, label) in _kindChoices(_draft.kindName))
              BCSelectItem(value: value, label: label),
          ],
          onValueChange: (v) =>
              setState(() => _draft.kindName = v.isEmpty ? null : v),
        ),
        const SizedBox(height: BCSpacing.lg),
        const _Label('Identifiers'),
        for (final (i, id) in _draft.identifiers.indexed)
          _PhoneIdentifierRow(
            key: ObjectKey(id),
            index: i,
            identifier: id,
            error: _errors['id$i'],
            onChanged: () => setState(() {}),
            onRemove: () => _removeIdentifier(id),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: BCButton(
            size: BCButtonSize.sm,
            variant: BCButtonVariant.ghost,
            onPressed: _addIdentifier,
            startContent: const Icon(LucideIcons.plus, size: 15),
            child: const Text('Add identifier'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: BCText(
            'Bundle IDs, package names, domains, URLs, repositories. '
            'All searchable.',
            type: BCTextType.bodyXs,
            color: BCTextColor.muted,
          ),
        ),
        if (_saveError case final error?) ...[
          const SizedBox(height: BCSpacing.md),
          BCText(
            error,
            type: BCTextType.bodySm,
            style: TextStyle(color: bc.danger),
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
              child: Text(_draft.isNew ? 'Add app' : 'Save'),
            ),
          ],
        ),
      ],
    );
  }

  static const double _labelWidth = 110;

  /// Desktop: the same form as a sheet with a classic form (N03e's style)
  /// and the identifiers as a table, like the item editor's fields.
  Widget _sheet(BuildContext context) {
    return DesktopSheet(
      width: 600,
      title: _draft.isNew ? 'New app' : 'Edit app',
      message: _about,
      leadingAction: _saving
          ? const DesktopProgress(semanticLabel: 'Saving')
          : null,
      actions: [
        DesktopButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        DesktopButton(
          label: _draft.isNew ? 'Add app' : 'Save',
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
                  label: 'Name',
                  child: SheetNote(
                    tone: NoteTone.problem,
                    note: _errors['name'],
                    control: DesktopTextField(
                      key: const ValueKey('app-name'),
                      controller: _name,
                      autofocus: true,
                      placeholder: 'e.g. Billing API',
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                ),
                DesktopFormRow(
                  label: 'Organization',
                  child: DesktopComboBox(
                    key: const ValueKey('app-organization'),
                    value: _draft.organization,
                    placeholder: 'None',
                    menuLabel: 'Organizations in this vault',
                    suggestions: _organizations,
                    onChanged: (text) =>
                        setState(() => _draft.organization = text),
                  ),
                ),
                DesktopFormRow(
                  label: 'Kind',
                  child: SheetNote(
                    width: 200,
                    control: Semantics(
                      key: const ValueKey('app-kind'),
                      container: true,
                      label: 'Kind',
                      child: DesktopPopup<String>(
                        value: _draft.kindName ?? '',
                        choices: [
                          for (final (value, label) in _kindChoices(
                            _draft.kindName,
                          ))
                            DesktopChoice(value, label),
                        ],
                        onChanged: (v) => setState(
                          () => _draft.kindName = v.isEmpty ? null : v,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            _IdentifierTable(
              identifiers: _draft.identifiers,
              errors: _errors,
              onAdd: _addIdentifier,
              onRemove: _removeIdentifier,
              onChanged: () => setState(() {}),
            ),
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

/// Desktop: the identifiers as a table (Kind, Value), each row with a
/// remove button, and Add Identifier under them.
class _IdentifierTable extends StatelessWidget {
  const _IdentifierTable({
    required this.identifiers,
    required this.errors,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  final List<DraftIdentifier> identifiers;
  final Map<String, String> errors;
  final VoidCallback onAdd;
  final ValueChanged<DraftIdentifier> onRemove;
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
              child: _IdentifierColumns(
                kind: Text('Identifier', style: header),
                value: Text('Value', style: header),
              ),
            ),
          ),
          if (identifiers.isEmpty) ...[
            rule(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                'Bundle IDs, package names, domains, URLs, repositories. '
                'All searchable.',
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize,
                  color: colors.secondaryText,
                ),
              ),
            ),
          ],
          for (final (i, id) in identifiers.indexed) ...[
            rule(),
            _IdentifierRow(
              key: ObjectKey(id),
              index: i,
              identifier: id,
              error: errors['id$i'],
              onRemove: () => onRemove(id),
              onChanged: onChanged,
            ),
          ],
          rule(),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: DesktopButton(label: 'Add Identifier', onPressed: onAdd),
            ),
          ),
        ],
      ),
    );
  }
}

/// The table's columns: the kind, the value (the rest), then room for the
/// remove button.
class _IdentifierColumns extends StatelessWidget {
  const _IdentifierColumns({
    required this.kind,
    required this.value,
    this.remove,
  });

  final Widget kind;
  final Widget value;
  final Widget? remove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        spacing: 10,
        children: [
          SizedBox(width: 240, child: kind),
          Expanded(child: value),
          SizedBox(width: DesktopMetrics.toolbarSearchHeight, child: remove),
        ],
      ),
    );
  }
}

/// One identifier on desktop: its kind pop-up, its value and remove.
class _IdentifierRow extends StatefulWidget {
  const _IdentifierRow({
    super.key,
    required this.index,
    required this.identifier,
    required this.onRemove,
    required this.onChanged,
    this.error,
  });

  final int index;
  final DraftIdentifier identifier;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final String? error;

  @override
  State<_IdentifierRow> createState() => _IdentifierRowState();
}

class _IdentifierRowState extends State<_IdentifierRow> {
  late final _value = TextEditingController(text: widget.identifier.value);

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final id = widget.identifier;
    final name = id.kindName == null
        ? 'Identifier'
        : id.kind?.label ?? id.kindName!;
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
            child: Center(
              child: _IdentifierColumns(
                kind: Semantics(
                  key: ValueKey('app-identifier-kind-${widget.index}'),
                  container: true,
                  label: 'Identifier ${widget.index + 1} kind',
                  child: DesktopPopup<String>(
                    value: id.kindName,
                    placeholder: 'Choose…',
                    choices: [
                      for (final (value, label) in _identifierChoices(
                        id.kindName,
                      ))
                        DesktopChoice(value, label),
                    ],
                    onChanged: (kind) {
                      setState(() => id.kindName = kind);
                      widget.onChanged();
                    },
                  ),
                ),
                value: Semantics(
                  label: '$name value',
                  child: DesktopTextField(
                    key: ValueKey('app-identifier-${widget.index}'),
                    controller: _value,
                    mono: true,
                    placeholder: _hintFor(id.kind),
                    onChanged: (v) => id.value = v,
                  ),
                ),
                remove: DesktopIconButton(
                  symbol: DesktopSymbol.remove,
                  tooltip: 'Remove $name',
                  onPressed: widget.onRemove,
                ),
              ),
            ),
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

/// One identifier on a phone: its kind, its value and remove. On a narrow
/// screen the kind sits above the value, so neither is cut short.
class _PhoneIdentifierRow extends StatefulWidget {
  const _PhoneIdentifierRow({
    super.key,
    required this.index,
    required this.identifier,
    required this.onRemove,
    required this.onChanged,
    this.error,
  });

  final int index;
  final DraftIdentifier identifier;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final String? error;

  @override
  State<_PhoneIdentifierRow> createState() => _PhoneIdentifierRowState();
}

class _PhoneIdentifierRowState extends State<_PhoneIdentifierRow> {
  late final _value = TextEditingController(text: widget.identifier.value);

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.identifier;
    final narrow = isNarrowSheet(context);
    final name = id.kindName == null
        ? 'Identifier'
        : id.kind?.label ?? id.kindName!;
    final kind = Semantics(
      container: true,
      label: 'Identifier ${widget.index + 1} kind',
      child: BCSelect<String>(
        key: ValueKey('app-identifier-kind-${widget.index}'),
        listLabel: 'Identifier',
        placeholder: 'Choose a kind',
        presentation: narrow
            ? BCSelectPresentation.bottomSheet
            : BCSelectPresentation.popover,
        value: id.kindName,
        items: [
          for (final (value, label) in _identifierChoices(id.kindName))
            BCSelectItem(value: value, label: label),
        ],
        onValueChange: (v) {
          setState(() => id.kindName = v);
          widget.onChanged();
        },
      ),
    );
    final value = Row(
      spacing: BCSpacing.sm,
      children: [
        Expanded(
          child: Semantics(
            label: '$name value',
            child: BCInput(
              key: ValueKey('app-identifier-${widget.index}'),
              controller: _value,
              isInvalid: widget.error != null,
              placeholder: _hintFor(id.kind),
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (v) => id.value = v,
            ),
          ),
        ),
        BCButton(
          size: BCButtonSize.sm,
          variant: BCButtonVariant.ghost,
          isIconOnly: true,
          onPressed: widget.onRemove,
          child: Icon(LucideIcons.x, size: 16, semanticLabel: 'Remove $name'),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: BCSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: BCSpacing.xs,
        children: [
          if (narrow)
            kind
          else
            Row(
              spacing: BCSpacing.sm,
              children: [
                SizedBox(width: 190, child: kind),
                Expanded(child: value),
              ],
            ),
          if (narrow) value,
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
