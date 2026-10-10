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
import '../../shared/widgets/note_editor/note_editor.dart';

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
      style: NoteView.noteStyleOf(context),
      showLinkOnHover: desktop,
      onLink: (url) => copyNoteLink(context, ref, url),
    );
  }

  /// How notes look in the running layout.
  static MarkdownNoteStyle noteStyleOf(BuildContext context) =>
      DesktopTheme.maybeOf(context) != null
      ? _desktopStyle(context)
      : _phoneStyle(context);

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

/// What the secure note editor says while a note is empty.
const secureNotePlaceholder =
    'Write in Markdown: # for a heading, - for a list, ``` for code.';

/// A secure note's body (an item of type Secure Note, SPEC §6.5): the
/// WYSIWYG [NoteEditor] in a field-like box, with a Preview / Markdown
/// switch over it. Preview shows the note as it reads while it is typed;
/// Markdown shows its source.
class SecureNoteEditor extends ConsumerStatefulWidget {
  const SecureNoteEditor({
    super.key,
    required this.initialMarkdown,
    required this.onChanged,
    this.minHeight = 260,
  });

  final String initialMarkdown;
  final ValueChanged<String> onChanged;
  final double minHeight;

  @override
  ConsumerState<SecureNoteEditor> createState() => _SecureNoteEditorState();
}

class _SecureNoteEditorState extends ConsumerState<SecureNoteEditor> {
  bool _markdown = false;

  void _setMode(bool markdown) => setState(() => _markdown = markdown);

  @override
  Widget build(BuildContext context) {
    final desktop = DesktopTheme.maybeOf(context) != null;
    final style = NoteEditorStyle(
      markdown: NoteView.noteStyleOf(context),
      cursorColor: desktop
          ? context.desktopColors.accent
          : context.bcTheme.accent,
      selectionColor: desktop
          ? context.desktopColors.accent.withValues(alpha: 0.25)
          : context.bcTheme.accent.withValues(alpha: 0.25),
      placeholderColor: desktop
          ? context.desktopColors.tertiaryText
          : context.bcTheme.fieldPlaceholder,
    );
    final editor = NoteEditor(
      initialMarkdown: widget.initialMarkdown,
      markdownMode: _markdown,
      style: style,
      placeholder: secureNotePlaceholder,
      onChanged: widget.onChanged,
      onLink: (url) => copyNoteLink(context, ref, url),
    );
    return desktop ? _desktop(context, editor) : _phone(context, editor);
  }

  Widget _desktop(BuildContext context, Widget editor) {
    final colors = context.desktopColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          spacing: DesktopMetrics.formLabelGap,
          children: [
            Semantics(
              container: true,
              label: 'Note view',
              child: DesktopSegmented<bool>(
                value: _markdown,
                choices: const [
                  DesktopChoice(false, 'Preview'),
                  DesktopChoice(true, 'Markdown'),
                ],
                onChanged: _setMode,
              ),
            ),
            Expanded(
              child: Text(
                'Markdown · not searchable',
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize,
                  color: colors.secondaryText,
                ),
              ),
            ),
          ],
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.field,
            border: Border.all(color: colors.fieldStroke, width: 0.5),
            borderRadius: const BorderRadius.all(
              Radius.circular(DesktopMetrics.fieldRadius),
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: editor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _phone(BuildContext context, Widget editor) {
    final bc = context.bcTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: BCSpacing.sm,
      children: [
        BCTabs<bool>(
          value: _markdown,
          fullWidth: true,
          onValueChange: _setMode,
          items: const [
            BCTabItem(value: false, label: 'Preview'),
            BCTabItem(value: true, label: 'Markdown'),
          ],
        ),
        DecoratedBox(
          decoration: ShapeDecoration(
            color: bc.field,
            shape: BCShapes.continuous(
              BCRadius.xl,
              side: BorderSide(color: bc.fieldBorder),
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            child: Padding(
              padding: const EdgeInsets.all(BCSpacing.md),
              child: editor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Copies a secure note's Markdown through the clipboard guard, as a
/// secret: it comes off the clipboard again after the set time.
Future<void> copySecureNote(
  BuildContext context,
  WidgetRef ref,
  String markdown,
) async {
  final guard = ref.read(clipboardGuardProvider);
  await guard.copySecret(markdown);
  if (!context.mounted) return;
  showAppToast(
    context,
    BCToastData(
      title: 'Note copied',
      description:
          'Clears from the clipboard in ${guard.clearAfter.inSeconds} seconds.',
    ),
  );
}
