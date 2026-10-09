import '../../shared/desktop_ui.dart';

/// Asks for a new name for [organization]. Resolves to the trimmed name,
/// or null when cancelled. An empty name can't be saved: moving apps out
/// of an organization is done app by app.
Future<String?> showRenameOrganizationSheet(
  BuildContext context,
  String organization,
) => showDesktopSheet<String>(
  context,
  builder: (_) => _RenameOrganizationSheet(organization: organization),
);

class _RenameOrganizationSheet extends StatefulWidget {
  const _RenameOrganizationSheet({required this.organization});

  final String organization;

  @override
  State<_RenameOrganizationSheet> createState() =>
      _RenameOrganizationSheetState();
}

class _RenameOrganizationSheetState extends State<_RenameOrganizationSheet> {
  late final _name = TextEditingController(text: widget.organization)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.trim();

  void _save() {
    if (_trimmed.isEmpty) return;
    Navigator.of(context).pop(_trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return DesktopSheet(
      title: 'Rename “${widget.organization}”',
      message: 'Every app in this organization moves to the new name.',
      width: 440,
      actions: [
        DesktopButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        DesktopButton(
          label: 'Rename',
          kind: DesktopButtonKind.primary,
          onPressed: _trimmed.isEmpty ? null : _save,
        ),
      ],
      child: DesktopForm(
        children: [
          DesktopFormRow(
            label: 'Name',
            child: DesktopTextField(
              key: const ValueKey('organization-name'),
              controller: _name,
              autofocus: true,
              onSubmitted: (_) => _save(),
            ),
          ),
        ],
      ),
    );
  }
}
