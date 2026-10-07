import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import 'app_draft.dart';

/// Opens the app form: [app] to edit it, or null for a new app. Resolves
/// to the saved app's id, or null when cancelled.
Future<String?> showAppEditor(BuildContext context, {AppRecord? app}) {
  return BCDialog.show<String>(
    context,
    builder: (_) => BCDialogContent(
      width: 520,
      showCloseButton: true,
      child: AppEditor(
        draft: app == null ? AppDraft.create() : AppDraft.edit(app),
      ),
    ),
  );
}

/// The app form: its name and the store identifiers that tie imported
/// files to it (bundle IDs for Apple, package names for Android).
class AppEditor extends ConsumerStatefulWidget {
  const AppEditor({super.key, required this.draft});

  final AppDraft draft;

  @override
  ConsumerState<AppEditor> createState() => _AppEditorState();
}

class _AppEditorState extends ConsumerState<AppEditor> {
  late final AppDraft _draft = widget.draft;
  late final _name = TextEditingController(text: _draft.name);
  late final _bundleIds = TextEditingController(text: _draft.bundleIds);
  late final _packageNames = TextEditingController(text: _draft.packageNames);
  Map<String, String> _errors = const {};
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _name.dispose();
    _bundleIds.dispose();
    _packageNames.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _draft
      ..name = _name.text
      ..bundleIds = _bundleIds.text
      ..packageNames = _packageNames.text;
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

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BCDialogTitle(_draft.isNew ? 'New app' : 'Edit app'),
        const SizedBox(height: BCSpacing.xs),
        const BCDialogDescription(
          'Items are grouped by app in the sidebar. Bundle IDs and package '
          'names are searchable.',
        ),
        const SizedBox(height: BCSpacing.lg),
        BCTextField(
          isRequired: true,
          isInvalid: _errors.containsKey('name'),
          children: [
            const BCTextFieldLabel('Name'),
            BCTextFieldInput(
              controller: _name,
              autofocus: true,
              hintText: 'e.g. Kitchenly',
              onSubmitted: (_) => _save(),
            ),
            if (_errors['name'] case final error?) BCTextFieldError(error),
          ],
        ),
        const SizedBox(height: BCSpacing.md),
        BCTextField(
          isInvalid: _errors.containsKey('bundleIds'),
          children: [
            const BCTextFieldLabel('Apple bundle IDs'),
            BCTextFieldInput(
              controller: _bundleIds,
              hintText: 'com.example.app',
              maxLines: 3,
              minLines: 1,
              autocorrect: false,
              enableSuggestions: false,
            ),
            if (_errors['bundleIds'] case final error?)
              BCTextFieldError(error)
            else
              const BCTextFieldDescription('One per line or comma-separated'),
          ],
        ),
        const SizedBox(height: BCSpacing.md),
        BCTextField(
          isInvalid: _errors.containsKey('packageNames'),
          children: [
            const BCTextFieldLabel('Android package names'),
            BCTextFieldInput(
              controller: _packageNames,
              hintText: 'com.example.android',
              maxLines: 3,
              minLines: 1,
              autocorrect: false,
              enableSuggestions: false,
            ),
            if (_errors['packageNames'] case final error?)
              BCTextFieldError(error)
            else
              const BCTextFieldDescription('One per line or comma-separated'),
          ],
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
}
