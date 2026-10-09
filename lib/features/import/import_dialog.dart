import 'package:cred_parsers/cred_parsers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/format.dart';
import '../../core/item_templates.dart';
import '../../data/expiry_alerts.dart';
import '../../data/providers.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart'
    show
        DesktopButton,
        DesktopButtonKind,
        DesktopChoice,
        DesktopComboBox,
        DesktopCheckbox,
        DesktopForm,
        DesktopFormRow,
        DesktopIcon,
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
import 'import_draft.dart';
import 'place_fields.dart';

/// Opens [dialog]: a sheet in the desktop layout (N04), bc_ui's dialog or
/// bottom sheet on a phone (B4).
Future<ImportOutcome?> _present(BuildContext context, ImportDialog dialog) {
  if (DesktopTheme.maybeOf(context) != null) {
    return showDesktopSheet<ImportOutcome>(context, builder: (_) => dialog);
  }
  return BCDialog.show<ImportOutcome>(
    context,
    builder: (_) =>
        BCDialogContent(width: 640, showCloseButton: true, child: dialog),
  );
}

/// Imports files into the vault (design frames N04, B4): asks for [files],
/// or lets the user choose them, then opens the import dialog for each one
/// and shows the last item imported.
Future<void> showImportDialog(
  BuildContext context, {
  List<PickedFile>? files,
}) async {
  final container = ProviderScope.containerOf(context);
  final picked = files ?? await container.read(fileOpenerProvider).pick();
  String? lastId;
  var imported = 0;
  var replaced = 0;
  for (final file in picked) {
    if (!context.mounted) return;
    final outcome = await _present(context, ImportDialog(file: file));
    if (outcome == null) continue;
    lastId = outcome.itemId;
    if (outcome.replaced) {
      replaced++;
    } else if (outcome.imported) {
      imported++;
    }
  }
  if (lastId == null || !context.mounted) return;
  context.go(const VaultFilter().location(item: lastId));
  if (imported + replaced > 0) {
    showAppToast(
      context,
      BCToastData(
        title: imported == 0
            ? (replaced == 1 ? 'File replaced' : '$replaced files replaced')
            : imported == 1
            ? 'File imported'
            : '$imported files imported',
        variant: BCToastVariant.success,
      ),
    );
  }
}

/// Replaces [item]'s file with one the user picks (P4-04): the item keeps
/// its id, name, tags, place and the fields the user typed; the file, what
/// it says and its expiry are the new file's, and its expiry reminders
/// start over.
Future<void> showReplaceFileDialog(BuildContext context, Item item) async {
  final container = ProviderScope.containerOf(context);
  final picked = await container.read(fileOpenerProvider).pick();
  if (picked.isEmpty || !context.mounted) return;
  final outcome = await _present(
    context,
    ImportDialog(file: picked.first, replacing: item),
  );
  if (outcome == null || !outcome.replaced || !context.mounted) return;
  showAppToast(
    context,
    BCToastData(
      title: 'File replaced',
      description: '“${item.title}” has its new file and expiry.',
      variant: BCToastVariant.success,
    ),
  );
}

/// How the dialog closed: the item to show, whether a file was saved (as
/// opposed to opening an existing copy), and whether it replaced an item's
/// file.
typedef ImportOutcome = ({String itemId, bool imported, bool replaced});

/// The import form for one file: what the file says (read-only, "From
/// file"), any password or choice it needs, what only the user knows, and
/// where the item belongs.
class ImportDialog extends ConsumerStatefulWidget {
  const ImportDialog({super.key, required this.file, this.replacing});

  final PickedFile file;

  /// The item whose file [file] replaces, when that's what the user asked
  /// for (P4-04). Null to import a new item.
  final Item? replacing;

  @override
  ConsumerState<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<ImportDialog> {
  ImportDraft? _draft;
  late final String _sha256 = _hex(VaultCrypto.sha256(widget.file.bytes));
  late final _title = TextEditingController();
  final _tagInput = DesktopTokenController();
  final _secretControllers = <String, TextEditingController>{};
  final _fieldControllers = <String, TextEditingController>{};
  Map<String, String> _errors = const {};
  bool _busy = true;
  bool _ignoreDuplicates = false;
  String? _error;

  /// Set from the start ([ImportDialog.replacing]) or when the user picks
  /// Replace on a duplicate.
  late Item? _replacing = widget.replacing;

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
    _tagInput.dispose();
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
        _draft = ImportDraft(widget.file, result, replacing: _replacing);
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
    if (session is! Unlocked || _ignoreDuplicates || _replacing != null) {
      return const [];
    }
    return ImportDraft.duplicatesOf(_sha256, session.index.items.values);
  }

  /// Replace on a duplicate: the same form as Replace file, for that item,
  /// so anything it still needs is asked for in plain sight.
  void _replaceInstead(Item target) {
    final old = _draft!;
    setState(() {
      _replacing = target;
      _draft = ImportDraft(widget.file, old.result, replacing: target)
        ..choice = old.choice
        ..keepSecrets = old.keepSecrets
        ..secrets.addAll(old.secrets);
      _title.text = target.title;
      _errors = const {};
    });
  }

  Future<void> _import() async {
    final draft = _draft!;
    final replacing = _replacing;
    draft.title = replacing?.title ?? _title.text;
    // A tag still being typed counts.
    draft.tags = _tagInput.commit(draft.tags);
    for (final field in draft.requiredFields) {
      draft.userFields[field.key] = _field(field.key).text;
    }
    final errors = draft.validate();
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
      // A new file: its reminders start over, so the warning clears.
      if (replacing != null) {
        ref.read(expiryAlertsProvider.notifier).reset(saved.id);
      }
      if (mounted) {
        Navigator.of(
          context,
        ).pop((itemId: saved.id, imported: true, replaced: replacing != null));
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
    if (DesktopTheme.maybeOf(context) != null) return _sheet(context);
    final draft = _draft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BCDialogTitle(_replacing == null ? 'Import file' : 'Replace file'),
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
    final replacing = _replacing;
    return [
      if (replacing != null) ...[
        _Notice(
          icon: LucideIcons.fileUp,
          text:
              'Replaces the file of “${replacing.title}”. Its name, tags, '
              'place and the fields you entered stay; what the file says '
              'and its expiry come from this file, and its reminders start '
              'over.',
        ),
        const SizedBox(height: BCSpacing.md),
      ],
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
          onOpen: () => Navigator.of(context).pop((
            itemId: duplicates.first.id,
            imported: false,
            replaced: false,
          )),
          onReplace: () => _replaceInstead(duplicates.first),
          onImportAnyway: () => setState(() => _ignoreDuplicates = true),
        ),
        const SizedBox(height: BCSpacing.lg),
        _Actions(onCancel: () => Navigator.of(context).pop()),
      ] else if (widget.replacing case final target?
          when target.attachments.any((a) => a.sha256 == _sha256)) ...[
        _Notice(
          icon: LucideIcons.copy,
          text: 'This is the file “${target.title}” already has.',
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
        const SheetLabel('Which app is this for?'),
        BCSelect<String>(
          listLabel: 'App in this file',
          presentation: isNarrowSheet(context)
              ? BCSelectPresentation.bottomSheet
              : BCSelectPresentation.popover,
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
      ] else if (!draft.fitsReplaced) ...[
        _Notice(
          icon: LucideIcons.circleAlert,
          danger: true,
          text:
              'This is ${_article(draft.type.label)} ${draft.type.label}, '
              'but “${_replacing!.title}” is '
              '${_article(_replacing!.type?.label ?? 'item')} '
              '${_replacing!.type?.label ?? 'item'}. Choose a file of the '
              'same kind, or import this one as a new item.',
        ),
        const SizedBox(height: BCSpacing.lg),
        _Actions(onCancel: () => Navigator.of(context).pop()),
      ] else
        ..._form(context, draft),
    ];
  }

  static String _article(String word) =>
      RegExp('^[AEIOU]').hasMatch(word) ? 'an' : 'a';

  List<Widget> _form(BuildContext context, ImportDraft draft) {
    final result = draft.result;
    final session = ref.watch(vaultSessionProvider);
    final apps = session is Unlocked
        ? (session.index.apps.values.toList()..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
          ))
        : <AppRecord>[];
    final replacing = _replacing;
    final narrow = isNarrowSheet(context);
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
      if (draft.asksPurpose &&
          replacing?.fields[ImportDraft.purposeKey] == null) ...[
        const SheetLabel('Used for'),
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
      if (replacing == null) ...[
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
        PlaceFields(
          app: PlaceChoice(
            label: 'App',
            none: 'No app',
            value: draft.appId,
            options: {for (final app in apps) app.id: app.label},
            onChanged: (v) => setState(() => draft.appId = v),
          ),
          platform: PlaceChoice(
            label: 'Platform',
            none: 'None',
            value: draft.platform,
            options: {
              for (final p in ItemTemplates.platforms)
                p: VaultLabels.platform(p),
            },
            onChanged: (v) => setState(() => draft.platform = v),
          ),
          environment: PlaceChoice(
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
        // B4 says "Add to vault" on a phone; D04 says "Import".
        primary: replacing != null
            ? 'Replace file'
            : narrow
            ? 'Add to vault'
            : 'Import',
        onPrimary: _import,
        onCancel: () => Navigator.of(context).pop(),
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Desktop (N04): a sheet with a classic form. Same states and rules as the
  // phone path above; only the look differs.
  // -------------------------------------------------------------------------

  /// The label column of the import form.
  static const double _labelWidth = 110;

  /// Fixed-width controls (IDs, pickers) leave room for a note beside them.
  static const double _controlWidth = 200;

  Widget _sheet(BuildContext context) {
    final draft = _draft;
    final replacing = _replacing;
    final name = widget.file.name.split(RegExp(r'[/\\]')).last;
    final cancel = DesktopButton(
      label: 'Cancel',
      onPressed: () => Navigator.of(context).pop(),
    );
    final (content, actions) = _sheetBody(context, cancel);
    return DesktopSheet(
      width: 580,
      title: replacing == null
          ? 'Import $name'
          : 'Replace the file of “${replacing.title}”',
      icon: TypeIconTile(type: draft?.type ?? ItemType.genericFile, size: 36),
      subtitle: _SheetFileLine(
        type: _tooLarge ? null : draft?.type,
        reading: !_tooLarge && draft == null,
        generic: draft?.result.isGeneric ?? false,
        size: widget.file.bytes.length,
        sha256: _sha256,
      ),
      leadingAction: _busy && draft != null
          ? const DesktopProgress(semanticLabel: 'Working')
          // Room for it beside Cancel and one action.
          : actions.length <= 2
          ? const _SheetPrivacyNote()
          : null,
      actions: actions,
      child: SingleChildScrollView(child: content),
    );
  }

  /// What the sheet shows and which buttons it offers, by state: the same
  /// states, in the same order, as [_body] on a phone.
  (Widget, List<Widget>) _sheetBody(BuildContext context, Widget cancel) {
    final draft = _draft;
    if (_tooLarge) {
      return (
        SheetNotice(
          symbol: DesktopSymbol.alert,
          problem: true,
          child: Text(
            'This file is larger than '
            '${Format.bytes(Vault.maxAttachmentBytes)}, the most one item '
            'can hold.',
          ),
        ),
        [cancel],
      );
    }
    if (draft == null) {
      return (
        const Padding(
          padding: EdgeInsets.all(12),
          child: Center(
            child: DesktopProgress(size: 20, semanticLabel: 'Reading the file'),
          ),
        ),
        [cancel],
      );
    }
    final result = draft.result;
    final duplicates = _duplicates;
    final replacing = _replacing;
    final notices = <Widget>[
      if (replacing != null)
        SheetNotice(
          symbol: DesktopSymbol.document,
          child: Text(
            'Replaces the file of “${replacing.title}”. Its name, tags, '
            'place and the fields you entered stay; what the file says and '
            'its expiry come from this file, and its reminders start over.',
          ),
        ),
      if (_error case final error?)
        SheetNotice(
          symbol: DesktopSymbol.alert,
          problem: true,
          child: Text(error),
        ),
      for (final warning in result.warnings)
        SheetNotice(symbol: DesktopSymbol.info, child: Text(warning)),
    ];
    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        // Under the header, as in N04.
        SizedBox(
          height: 0.5,
          child: ColoredBox(color: context.desktopColors.innerSeparator),
        ),
        ...notices,
        ...children,
      ],
    );

    if (duplicates.isNotEmpty) {
      final existing = duplicates.first;
      return (
        column([
          SheetNotice(
            symbol: DesktopSymbol.copy,
            child: Text(
              'This exact file is already in your vault as '
              '“${existing.title}”.',
            ),
          ),
        ]),
        [
          cancel,
          DesktopButton(
            label: 'Import anyway',
            onPressed: _busy
                ? null
                : () => setState(() => _ignoreDuplicates = true),
          ),
          DesktopButton(
            label: 'Replace',
            onPressed: _busy ? null : () => _replaceInstead(existing),
          ),
          DesktopButton(
            label: 'Open existing',
            kind: DesktopButtonKind.primary,
            onPressed: _busy
                ? null
                : () => Navigator.of(context).pop((
                    itemId: existing.id,
                    imported: false,
                    replaced: false,
                  )),
          ),
        ],
      );
    }
    if (widget.replacing case final target?
        when target.attachments.any((a) => a.sha256 == _sha256)) {
      return (
        column([
          SheetNotice(
            symbol: DesktopSymbol.copy,
            child: Text('This is the file “${target.title}” already has.'),
          ),
        ]),
        [cancel],
      );
    }
    if (result.needsSecrets) {
      return (
        column([
          DesktopForm(
            labelWidth: _labelWidth,
            children: [
              for (final (i, request) in result.secretsNeeded.indexed)
                DesktopFormRow(
                  label: request.label,
                  child: SheetNote(
                    tone: request.rejected ? NoteTone.problem : NoteTone.hint,
                    note: request.rejected
                        ? "That ${request.label.toLowerCase()} didn't open "
                              'the file.'
                        : 'Needed to read what’s inside. Stays on this '
                              'device, encrypted with the vault.',
                    control: Semantics(
                      label: request.label,
                      child: DesktopTextField(
                        key: ValueKey('import-secret-${request.key}'),
                        controller: _secret(request.key),
                        obscureText: true,
                        autofocus: i == 0,
                        onSubmitted: (_) => _unlock(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ]),
        [
          cancel,
          DesktopButton(
            label: 'Unlock file',
            kind: DesktopButtonKind.primary,
            onPressed: _busy ? null : _unlock,
          ),
        ],
      );
    }
    if (result.needsChoice) {
      return (
        column([
          DesktopForm(
            labelWidth: _labelWidth,
            children: [
              DesktopFormRow(
                label: 'App in the file',
                child: SheetNote(
                  width: _controlWidth,
                  control: DesktopPopup<String>(
                    value: draft.choice,
                    placeholder: 'Choose an app',
                    choices: [
                      for (final option in result.options)
                        DesktopChoice(option.id, option.label),
                    ],
                    onChanged: (id) {
                      draft.choice = id;
                      _parse();
                    },
                  ),
                ),
              ),
            ],
          ),
        ]),
        [cancel],
      );
    }
    if (!draft.fitsReplaced) {
      final target = _replacing!;
      final targetKind = target.type?.label ?? 'item';
      return (
        column([
          SheetNotice(
            symbol: DesktopSymbol.alert,
            problem: true,
            child: Text(
              'This is ${_article(draft.type.label)} ${draft.type.label}, '
              'but “${target.title}” is ${_article(targetKind)} '
              '$targetKind. Choose a file of the same kind, or import this '
              'one as a new item.',
            ),
          ),
        ]),
        [cancel],
      );
    }
    return (
      column(_sheetForm(context, draft)),
      [
        cancel,
        DesktopButton(
          label: replacing == null ? 'Add to Vault' : 'Replace file',
          kind: DesktopButtonKind.primary,
          onPressed: _busy ? null : _import,
        ),
      ],
    );
  }

  /// The form for a file that's ready: what it says, what only the user
  /// knows, where the item belongs, and its expiry.
  List<Widget> _sheetForm(BuildContext context, ImportDraft draft) {
    final result = draft.result;
    final session = ref.watch(vaultSessionProvider);
    final unlocked = session is Unlocked ? session : null;
    final apps = [...?unlocked?.index.apps.values]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final items = unlocked?.index.items.values ?? const <Item>[];
    final replacing = _replacing;
    return [
      if (result.facts.isNotEmpty) _SheetFacts(facts: result.facts),
      DesktopForm(
        labelWidth: _labelWidth,
        children: [
          if (replacing == null)
            DesktopFormRow(
              label: 'Name',
              child: SheetNote(
                tone: NoteTone.problem,
                note: _errors['title'],
                control: DesktopTextField(controller: _title),
              ),
            ),
          for (final field in draft.requiredFields)
            DesktopFormRow(
              label: field.label,
              child: SheetNote(
                width: _controlWidth,
                tone: _errors.containsKey(field.key)
                    ? NoteTone.problem
                    : NoteTone.needed,
                note: _errors[field.key] ?? 'Required · not in the file',
                control: Semantics(
                  label: field.label,
                  child: DesktopTextField(
                    key: ValueKey('import-field-${field.key}'),
                    controller: _field(field.key),
                    placeholder: field.example,
                    mono: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ),
          if (draft.asksPurpose &&
              replacing?.fields[ImportDraft.purposeKey] == null)
            DesktopFormRow(
              label: 'Used for',
              child: SheetNote(
                // Fits "App Store Connect API" (macOS sizes the menu to
                // the button).
                width: _controlWidth + 30,
                note: 'Optional · the file doesn’t say',
                // One choice, or none: "Not set" stores nothing.
                control: DesktopPopup<String>(
                  value: draft.purpose?.name ?? '',
                  choices: [
                    const DesktopChoice('', 'Not set'),
                    for (final purpose in KeyPurpose.values)
                      DesktopChoice(purpose.name, purpose.label),
                  ],
                  onChanged: (name) => setState(
                    () => draft.purpose = KeyPurpose.values
                        .where((p) => p.name == name)
                        .firstOrNull,
                  ),
                ),
              ),
            ),
          if (replacing == null) ...[
            DesktopFormRow(
              label: 'App',
              child: SheetNote(
                width: _controlWidth,
                control: DesktopPopup<String>(
                  value: draft.appId ?? '',
                  choices: [
                    const DesktopChoice('', 'No app'),
                    for (final app in apps) DesktopChoice(app.id, app.label),
                  ],
                  onChanged: (id) =>
                      setState(() => draft.appId = id.isEmpty ? null : id),
                ),
              ),
            ),
            DesktopFormRow(
              label: 'Platform',
              child: SheetNote(
                width: _controlWidth,
                note: 'Type your own, or pick one',
                control: DesktopComboBox(
                  key: const ValueKey('import-platform'),
                  value: draft.platform ?? '',
                  menuLabel: 'Platform suggestions',
                  suggestions: placeSuggestions(
                    ItemTemplates.platforms,
                    items.map((i) => i.platform),
                  ),
                  onChanged: (text) =>
                      setState(() => draft.platform = typedPlace(text)),
                ),
              ),
            ),
            DesktopFormRow(
              label: 'Environment',
              child: SheetNote(
                width: _controlWidth,
                control: DesktopComboBox(
                  key: const ValueKey('import-environment'),
                  value: draft.environment ?? '',
                  menuLabel: 'Environment suggestions',
                  suggestions: placeSuggestions(
                    ItemTemplates.environments,
                    items.map((i) => i.environment),
                  ),
                  onChanged: (text) =>
                      setState(() => draft.environment = typedPlace(text)),
                ),
              ),
            ),
            DesktopFormRow(
              label: 'Tags',
              child: DesktopTokenField(
                controller: _tagInput,
                tokens: draft.tags,
                placeholder: 'Press Return after each tag',
                onChanged: (tags) => setState(() => draft.tags = tags),
              ),
            ),
          ],
          if (draft.secrets.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: _labelWidth + DesktopMetrics.formLabelGap,
              ),
              child: SheetNote(
                note: 'Saved as a secret field, encrypted with the vault.',
                control: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DesktopCheckbox(
                    label: 'Keep the password with the item',
                    value: draft.keepSecrets,
                    onChanged: (v) => setState(() => draft.keepSecrets = v),
                  ),
                ),
              ),
            ),
        ],
      ),
      _SheetExpiry(expiresAt: result.expiresAt),
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
            const Expanded(child: SheetLabel('Details')),
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

  /// A phone (B4): one full-width button, and the sheet's close button
  /// or a swipe down to cancel. Wider screens (D04): Cancel and the action
  /// side by side.
  @override
  Widget build(BuildContext context) {
    if (isNarrowSheet(context)) {
      return switch (primary) {
        final label? => BCButton(
          size: BCButtonSize.lg,
          fullWidth: true,
          isDisabled: busy,
          onPressed: onPrimary,
          startContent: busy ? const BCSpinner(size: BCSpinnerSize.sm) : null,
          child: Text(label),
        ),
        null => BCButton(
          size: BCButtonSize.lg,
          fullWidth: true,
          variant: BCButtonVariant.secondary,
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
      };
    }
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

/// The sheet's subtitle: what the file was read as, its size and short
/// hash. A check only when a parser recognised it.
class _SheetFileLine extends StatelessWidget {
  const _SheetFileLine({
    required this.type,
    required this.reading,
    required this.generic,
    required this.size,
    required this.sha256,
  });

  final ItemType? type;
  final bool reading;
  final bool generic;
  final int size;
  final String sha256;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final type = this.type;
    final recognised = type != null && !generic;
    return Row(
      spacing: 4,
      children: [
        if (!reading)
          DesktopIcon(
            recognised ? DesktopSymbol.verified : DesktopSymbol.info,
            size: 12,
            color: recognised ? colors.success : colors.secondaryText,
          ),
        Flexible(
          child: Text(
            [
              if (reading) 'Reading…' else ?type?.label,
              Format.bytes(size),
              'SHA-256 ${Format.shortHash(sha256)}',
            ].join(' · '),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Bottom left of the sheet: where the file is read.
class _SheetPrivacyNote extends StatelessWidget {
  const _SheetPrivacyNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        DesktopIcon(DesktopSymbol.privacy, size: 12, color: colors.success),
        Text(
          'Read on this device, stored encrypted.',
          style: TextStyle(
            fontSize: DesktopMetrics.secondarySize,
            color: colors.secondaryText,
          ),
        ),
      ],
    );
  }
}

/// What the file says, read-only, in a box marked as coming from the file.
class _SheetFacts extends StatelessWidget {
  const _SheetFacts({required this.facts});

  final Map<String, ItemField> facts;

  /// Lines the values up with the form's controls below the box.
  static const double _labelWidth = 99;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final mono = AppText.mono(
      context,
      fontSize: 12,
    ).copyWith(color: colors.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Details',
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
            ),
            const SourceTag('From the file'),
          ],
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.groupBoxInner,
            border: Border.all(color: colors.groupBoxStroke, width: 0.5),
            borderRadius: const BorderRadius.all(
              Radius.circular(DesktopMetrics.menuRadius + 2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final MapEntry(:key, :value) in facts.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: DesktopMetrics.formLabelGap,
                      children: [
                        SizedBox(
                          width: _labelWidth,
                          child: Text(
                            Format.fieldLabel(key),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: DesktopMetrics.bodySize - 1,
                              color: colors.secondaryText,
                            ),
                          ),
                        ),
                        Expanded(
                          child: value.secret
                              ? Text(SecretRow.mask, style: mono)
                              : SelectableText(value.value, style: mono),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The expiry as the file gives it, with where it came from; or that the
/// file has none. Nothing is inferred.
class _SheetExpiry extends StatelessWidget {
  const _SheetExpiry({required this.expiresAt});

  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final expiry = expiresAt;
    return SheetNotice(
      symbol: DesktopSymbol.expiring,
      child: expiry == null
          ? const Text(
              'No expiry date in the file, so this item won’t raise expiry '
              'warnings. You can set one later in the editor.',
            )
          : Row(
              spacing: 8,
              children: [
                Flexible(
                  child: Text(
                    'Expires '
                    '${DateFormat.yMMMd().add_Hm().format(expiry.toLocal())}',
                  ),
                ),
                const SourceTag('From the file'),
              ],
            ),
    );
  }
}
