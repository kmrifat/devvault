import '../../shared/desktop_ui.dart';

/// Asks for an organization's name: a new one when [organization] is
/// null, else a new name for it. Resolves to the trimmed name, or null when
/// cancelled. An empty name can't be saved: moving apps out of an
/// organization is done app by app.
Future<String?> showOrganizationSheet(
  BuildContext context, {
  String? organization,
}) => showDesktopSheet<String>(
  context,
  builder: (_) => _OrganizationSheet(organization: organization),
);

class _OrganizationSheet extends StatefulWidget {
  const _OrganizationSheet({required this.organization});

  /// Null for a new organization.
  final String? organization;

  @override
  State<_OrganizationSheet> createState() => _OrganizationSheetState();
}

class _OrganizationSheetState extends State<_OrganizationSheet> {
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
    final organization = widget.organization;
    return DesktopSheet(
      title: organization == null
          ? 'New organization'
          : 'Rename “$organization”',
      message: organization == null
          ? 'An employer or client to group apps under. Drag apps onto it '
                'to move them in.'
          : 'Every app in this organization moves to the new name.',
      width: 440,
      actions: [
        DesktopButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        DesktopButton(
          label: organization == null ? 'Create' : 'Rename',
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
