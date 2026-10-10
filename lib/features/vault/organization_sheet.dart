import '../../shared/desktop_ui.dart';
import '../notes/notes.dart' show DesktopNotesEditor;

/// What the organization sheet saves: a trimmed name and the notes as
/// typed (Markdown, SPEC §6.6).
typedef OrganizationDraft = ({String name, String notes});

/// Asks for an organization's name and notes: a new one when
/// [organization] is null, else its new name and notes ([notes] are its
/// current ones). Resolves to what to save, or null when cancelled. An
/// empty name can't be saved: moving apps out of an organization is done
/// app by app.
Future<OrganizationDraft?> showOrganizationSheet(
  BuildContext context, {
  String? organization,
  String notes = '',
}) => showDesktopSheet<OrganizationDraft>(
  context,
  builder: (_) => _OrganizationSheet(organization: organization, notes: notes),
);

class _OrganizationSheet extends StatefulWidget {
  const _OrganizationSheet({required this.organization, required this.notes});

  /// Null for a new organization.
  final String? organization;
  final String notes;

  @override
  State<_OrganizationSheet> createState() => _OrganizationSheetState();
}

class _OrganizationSheetState extends State<_OrganizationSheet> {
  late final _name = TextEditingController(text: widget.organization)
    ..addListener(() => setState(() {}));
  late final _notes = TextEditingController(text: widget.notes);

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.trim();

  void _save() {
    if (_trimmed.isEmpty) return;
    Navigator.of(context).pop((name: _trimmed, notes: _notes.text));
  }

  @override
  Widget build(BuildContext context) {
    final organization = widget.organization;
    return DesktopSheet(
      title: organization == null ? 'New organization' : 'Edit “$organization”',
      message: organization == null
          ? 'An employer or client to group apps under. Drag apps onto it '
                'to move them in.'
          : 'A new name moves every app in this organization to it.',
      width: 520,
      actions: [
        DesktopButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        DesktopButton(
          label: organization == null ? 'Create' : 'Save',
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
          DesktopFormRow(
            label: 'Notes',
            multiline: true,
            child: DesktopNotesEditor(
              controller: _notes,
              fieldKey: const ValueKey('organization-notes'),
              minLines: 4,
              maxLines: 8,
            ),
          ),
        ],
      ),
    );
  }
}
