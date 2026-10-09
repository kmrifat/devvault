import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../shared/desktop_ui.dart'
    show
        DesktopChoice,
        DesktopMetrics,
        DesktopSegmented,
        DesktopTextField,
        DesktopTheme,
        DesktopThemeContext;
import '../../shared/ui.dart';
import '../../shared/widgets/markdown_note.dart';

/// What the note fields say under or beside them.
const notesPlaceholder = 'Anything worth remembering. Notes aren’t searchable.';
const notesMarkdownHint =
    'Markdown: **bold**, _italic_, `code`, lists, quotes and links. '
    'Notes aren’t searchable.';

/// An item's or an app's notes, rendered as Markdown (SPEC §6.6) in the
/// running layout's style: the desktop layer's on a desktop, bc_ui's on a
/// phone.
///
/// Nothing in a note reaches the network. Images show as their alt text,
/// raw HTML as text, and a link is never opened: clicking or tapping it
/// copies its URL ([copyNoteLink]), and on a desktop pointing at it shows
/// the URL first.
class NoteView extends ConsumerWidget {
  const NoteView(this.notes, {super.key});

  final String notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = DesktopTheme.maybeOf(context) != null;
    return MarkdownNote(
      notes,
      style: desktop ? _desktopStyle(context) : _phoneStyle(context),
      showLinkOnHover: desktop,
      onLink: (url) => copyNoteLink(context, ref, url),
    );
  }

  static MarkdownNoteStyle _desktopStyle(BuildContext context) {
    final colors = context.desktopColors;
    return MarkdownNoteStyle(
      // As the inspector's notes were before they were rendered.
      body: TextStyle(
        fontSize: DesktopMetrics.bodySize,
        height: 1.4,
        color: colors.text,
      ),
      secondaryColor: colors.secondaryText,
      linkColor: colors.accentIcon,
      codeBackground: colors.groupBox,
      ruleColor: colors.groupBoxStroke,
      headingSizes: const [
        DesktopMetrics.inspectorTitleSize - 2,
        DesktopMetrics.bodySize + 2,
        DesktopMetrics.bodySize + 1,
      ],
      codeRadius: DesktopMetrics.menuItemRadius,
      hintBackground: colors.menu,
      hintColor: colors.text,
    );
  }

  static MarkdownNoteStyle _phoneStyle(BuildContext context) {
    final bc = context.bcTheme;
    return MarkdownNoteStyle(
      // As the detail screen's notes were before they were rendered.
      body: DefaultTextStyle.of(context).style,
      secondaryColor: bc.muted,
      linkColor: bc.accent,
      codeBackground: bc.surfaceSecondary,
      ruleColor: bc.separator,
      headingSizes: const [
        BCTypography.sizeLg,
        BCTypography.sizeBase,
        BCTypography.sizeSm,
      ],
      codeRadius: BCRadius.sm,
      hintBackground: bc.overlay,
      hintColor: bc.overlayForeground,
    );
  }
}

/// What following a link in a note does: copies its URL, and says so.
///
/// DevVault never opens a link from a note itself. A note can hold any
/// URL, and opening one would be a network request the user didn't make
/// on purpose (the app reaches only the user's own bucket). Copying is
/// harmless and lets the user decide where to paste it. A URL isn't a
/// secret field, so it stays on the clipboard like other plain values.
Future<void> copyNoteLink(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  await ref.read(clipboardGuardProvider).clipboard.write(url);
  if (!context.mounted) return;
  showAppToast(context, BCToastData(title: 'Link copied', description: url));
}

/// Desktop: a note's text field, with an Edit / Preview switch that shows
/// the Markdown as it will look, and a hint that notes are Markdown.
class DesktopNotesEditor extends StatefulWidget {
  const DesktopNotesEditor({
    super.key,
    required this.controller,
    this.fieldKey,
    this.minLines = 3,
    this.maxLines = 4,
  });

  final TextEditingController controller;

  /// The text field's key, for tests.
  final Key? fieldKey;
  final int minLines;
  final int maxLines;

  @override
  State<DesktopNotesEditor> createState() => _DesktopNotesEditorState();
}

class _DesktopNotesEditorState extends State<DesktopNotesEditor> {
  bool _preview = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final hint = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    final text = widget.controller.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          spacing: DesktopMetrics.formLabelGap,
          children: [
            Semantics(
              container: true,
              label: 'Notes view',
              child: DesktopSegmented<bool>(
                value: _preview,
                choices: const [
                  DesktopChoice(false, 'Edit'),
                  DesktopChoice(true, 'Preview'),
                ],
                onChanged: (preview) => setState(() => _preview = preview),
              ),
            ),
            Expanded(
              child: Text(
                'Markdown · not searchable',
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hint,
              ),
            ),
          ],
        ),
        if (_preview)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.field,
              border: Border.all(color: colors.fieldStroke, width: 0.5),
              borderRadius: const BorderRadius.all(
                Radius.circular(DesktopMetrics.fieldRadius),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DesktopMetrics.notesPreviewMinHeight,
                maxHeight: DesktopMetrics.notesPreviewMaxHeight,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: text.trim().isEmpty
                    ? Text('Nothing to preview', style: hint)
                    : NoteView(text),
              ),
            ),
          )
        else
          DesktopTextField(
            key: widget.fieldKey,
            controller: widget.controller,
            maxLines: widget.maxLines,
            minLines: widget.minLines,
            placeholder: notesPlaceholder,
          ),
      ],
    );
  }
}

/// Phone: a note's text area, with a line saying it's Markdown.
class PhoneNotesField extends StatelessWidget {
  const PhoneNotesField({
    super.key,
    required this.controller,
    this.fieldKey,
    this.height = 96,
  });

  final TextEditingController controller;
  final Key? fieldKey;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: BCSpacing.xs,
      children: [
        BCTextArea(
          key: fieldKey,
          controller: controller,
          height: height,
          placeholder: notesPlaceholder,
        ),
        const Padding(
          padding: EdgeInsets.only(left: 6),
          child: BCText(
            notesMarkdownHint,
            type: BCTextType.bodyXs,
            color: BCTextColor.muted,
          ),
        ),
      ],
    );
  }
}

/// Phone: notes in a card titled "Notes", like the item screen's other
/// sections.
class PhoneNotesCard extends StatelessWidget {
  const PhoneNotesCard({super.key, required this.notes, this.title = 'Notes'});

  final String notes;
  final String title;

  @override
  Widget build(BuildContext context) {
    final shape = BCShapes.continuous(BCRadius.xxxl);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.bcTheme.surface,
          shape: shape,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              BCText(title, type: BCTextType.bodySm, color: BCTextColor.muted),
              NoteView(notes),
            ],
          ),
        ),
      ),
    );
  }
}
