import 'package:flutter/material.dart'
    show
        InputDecoration,
        Material,
        MaterialType,
        TextField,
        TextSelectionTheme,
        TextSelectionThemeData;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../app/theme.dart' show AppText;
import '../markdown_note.dart';
import 'inline_markdown.dart';
import 'note_blocks.dart';

/// What a [NoteEditor] draws with: a [MarkdownNoteStyle] (so a note looks
/// the same edited and read) plus the editing colours.
@immutable
class NoteEditorStyle {
  const NoteEditorStyle({
    required this.markdown,
    required this.cursorColor,
    required this.selectionColor,
    required this.placeholderColor,
  });

  final MarkdownNoteStyle markdown;
  final Color cursorColor;
  final Color selectionColor;
  final Color placeholderColor;
}

/// A Markdown editor that shows the note as it reads (WYSIWYG), or as its
/// Markdown source ([markdownMode]).
///
/// The note is a column of blocks, each its own text field: paragraphs,
/// headings, bullet and numbered items, quotes, code and rules. Block
/// syntax turns into the block as it is typed at the start of a paragraph
/// (`# ` makes a heading 1 and disappears; `- `, `1. `, `> ` likewise; a
/// line of ` ``` ` or `---` followed by Return makes code or a rule).
/// Inline Markdown (`**bold**`, `_italic_`, `` `code` ``, `~~struck~~`,
/// links) shows formatted; its marks show, faintly, only in the block
/// being edited. Markdown the editor doesn't model (tables, HTML) is kept
/// as typed, shown rendered, and edited as source.
///
/// Keys: Return starts a new block (a new list item in a list; on an empty
/// item it leaves the list); Shift-Return breaks the line; Backspace at
/// the start of a block undoes its kind, then joins it to the block above;
/// Tab and Shift-Tab nest list items; the arrows move between blocks.
///
/// [onChanged] gets the whole note as Markdown after every change. Nothing
/// is fetched and no link opens: an image shows its alt text, and a link
/// in rendered source goes to [onLink].
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.initialMarkdown,
    required this.onChanged,
    required this.style,
    required this.onLink,
    this.markdownMode = false,
    this.placeholder = '',
    this.autofocus = false,
    this.enabled = true,
  });

  final String initialMarkdown;
  final ValueChanged<String> onChanged;
  final NoteEditorStyle style;

  /// A link clicked in source shown rendered (a table, say).
  final ValueChanged<String> onLink;

  /// Shows the Markdown source in one plain field instead of the blocks.
  final bool markdownMode;

  /// Shown while the note is empty.
  final String placeholder;
  final bool autofocus;
  final bool enabled;

  @override
  State<NoteEditor> createState() => NoteEditorState();
}

/// Each block's text starts with this, invisible, so that Backspace at the
/// start of a block (which changes no text) can be seen: it deletes it.
const _start = '\u200B';

class NoteEditorState extends State<NoteEditor> {
  final _blocks = <_Block>[];
  late final _source = TextEditingController(text: widget.initialMarkdown);
  late String _markdown = widget.initialMarkdown;
  bool _softBreak = false;

  /// The note as Markdown, as [NoteEditor.onChanged] last reported it.
  String get markdown => _markdown;

  @override
  void initState() {
    super.initState();
    _load(widget.initialMarkdown);
    if (widget.autofocus && !widget.markdownMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _blocks.isNotEmpty) _focus(0, atEnd: true);
      });
    }
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdownMode == widget.markdownMode) return;
    if (widget.markdownMode) {
      _source.text = _markdown;
    } else {
      _load(_source.text);
    }
  }

  @override
  void dispose() {
    for (final b in _blocks) {
      b.dispose();
    }
    _source.dispose();
    super.dispose();
  }

  void _load(String markdown) {
    for (final b in _blocks) {
      b.dispose();
    }
    _blocks
      ..clear()
      ..addAll(parseNoteBlocks(markdown).map(_entry));
  }

  _Block _entry(NoteBlock block) {
    late final _Block entry;
    entry = _Block(
      block,
      buildSpans: (style) => _spans(entry, style),
      onKey: (event) => _key(entry, event),
    );
    entry.controller.addListener(() => _changed(entry));
    entry.focus.addListener(() {
      // Raw source goes back to rendered when the caret leaves it.
      if (!entry.focus.hasFocus) entry.showSource = false;
      if (mounted) setState(() {});
    });
    return entry;
  }

  /// Disposes a removed block after the frame: it may be removed from its
  /// own controller's listener, and its field is still on screen.
  void _retire(_Block entry) {
    WidgetsBinding.instance.addPostFrameCallback((_) => entry.dispose());
  }

  void _emit() {
    _markdown = serializeNoteBlocks([for (final b in _blocks) b.block]);
    widget.onChanged(_markdown);
  }

  // Looks.

  MarkdownNoteStyle get _md => widget.style.markdown;

  InlineMarkdownLook get _look => InlineMarkdownLook(
    markColor: _md.secondaryColor.withValues(alpha: 0.7),
    linkColor: _md.linkColor,
    secondaryColor: _md.secondaryColor,
    codeBackground: _md.codeBackground,
    monoFamily: AppText.monoFamily,
  );

  TextStyle get _mono => _md.body.copyWith(
    fontFamily: AppText.monoFamily,
    fontSize: (_md.body.fontSize ?? 14) * 0.92,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  TextStyle _styleOf(NoteBlock block) => switch (block.kind) {
    NoteBlockKind.heading => _md.body.copyWith(
      fontSize: block.level <= _md.headingSizes.length
          ? _md.headingSizes[block.level - 1]
          : null,
      fontWeight: block.level <= 2 ? FontWeight.w700 : FontWeight.w600,
      height: 1.25,
    ),
    NoteBlockKind.quote => _md.body.copyWith(color: _md.secondaryColor),
    NoteBlockKind.code || NoteBlockKind.raw => _mono,
    _ => _md.body,
  };

  TextSpan _spans(_Block entry, TextStyle style) {
    final text = entry.controller.text;
    final body = text.startsWith(_start) ? text.substring(1) : text;
    final source =
        entry.block.kind == NoteBlockKind.code ||
        entry.block.kind == NoteBlockKind.raw;
    return TextSpan(
      style: style,
      children: [
        if (text.startsWith(_start))
          const TextSpan(text: _start, style: hiddenMarkStyle),
        if (source)
          TextSpan(text: body, style: style)
        else
          ...inlineMarkdownSpans(
            body,
            style,
            _look,
            showMarks: entry.focus.hasFocus,
          ),
      ],
    );
  }

  // Editing.

  /// Reacts to an edit of [entry]: keeps the start mark, turns typed
  /// syntax into blocks, splits on Return.
  void _changed(_Block entry) {
    if (entry.applying) return;
    final value = entry.controller.value;
    final previous = entry.last;
    entry.last = value.text;

    if (!value.text.startsWith(_start)) {
      if (value.text == previous.substring(1)) {
        // Backspace at the very start.
        entry.set(previous, 1);
        entry.last = previous;
        _backspaceAtStart(entry);
      } else {
        // Everything was replaced: put the mark back in front.
        final offset = value.selection.isValid
            ? value.selection.extentOffset + 1
            : value.text.length + 1;
        entry.set('$_start${value.text}', offset);
        entry.last = entry.controller.text;
        _textChanged(entry, previous);
      }
      return;
    }
    // Nothing goes before the mark.
    final selection = value.selection;
    if (selection.isValid && (selection.start == 0 || selection.end == 0)) {
      entry.applying = true;
      entry.controller.selection = TextSelection(
        baseOffset: selection.baseOffset.clamp(1, value.text.length),
        extentOffset: selection.extentOffset.clamp(1, value.text.length),
      );
      entry.applying = false;
    }
    if (value.text != previous) _textChanged(entry, previous);
  }

  void _textChanged(_Block entry, String previous) {
    final block = entry.block;
    final text = entry.controller.text.substring(1);
    final before = previous.startsWith(_start) ? previous.substring(1) : '';
    final caret = entry.controller.selection.extentOffset - 1;

    final source =
        block.kind == NoteBlockKind.code || block.kind == NoteBlockKind.raw;
    final inserted = text.length - before.length;

    // A paste of several lines into a paragraph becomes blocks.
    if (block.kind == NoteBlockKind.paragraph &&
        inserted > 1 &&
        text.contains('\n') &&
        !before.contains('\n')) {
      _replaceWithParsed(entry, text);
      return;
    }

    // Return.
    final typedNewline =
        inserted == 1 &&
        caret > 0 &&
        caret <= text.length &&
        text[caret - 1] == '\n';
    if (typedNewline && !source) {
      if (_softBreak && block.kind != NoteBlockKind.heading) {
        _softBreak = false;
      } else {
        _softBreak = false;
        _return(entry, text.substring(0, caret - 1), text.substring(caret));
        return;
      }
    }
    if (typedNewline && block.kind == NoteBlockKind.code) {
      // A closing fence on its own line ends the code block.
      final lines = text.substring(0, caret - 1).split('\n');
      if (lines.length > 1 &&
          RegExp(r'^(`{3,}|~{3,})$').hasMatch(lines.last) &&
          text.substring(caret).isEmpty) {
        block.text = lines.sublist(0, lines.length - 1).join('\n');
        entry.set('$_start${block.text}', block.text.length + 1);
        _insert(_blocks.indexOf(entry) + 1, NoteBlock.paragraph());
        return;
      }
    }

    // Block syntax typed at the start of a paragraph.
    if (block.kind == NoteBlockKind.paragraph &&
        _shortcut(entry, text, before)) {
      return;
    }

    block.text = text;
    _emit();
  }

  /// Turns `# `, `- `, `1. ` or `> ` just typed at the start of a
  /// paragraph into its block. True when it did.
  bool _shortcut(_Block entry, String text, String before) {
    final block = entry.block;
    final heading = RegExp(r'^(#{1,6}) ').firstMatch(text);
    final bullet = RegExp(r'^([-*+]) ').firstMatch(text);
    final ordered = RegExp(r'^(\d{1,9})([.)]) ').firstMatch(text);
    final quote = RegExp(r'^> ').firstMatch(text);
    final m = heading ?? bullet ?? ordered ?? quote;
    if (m == null || before.startsWith(m[0]!)) return false;
    final prefix = m[0]!.length;
    if (entry.controller.selection.extentOffset - 1 != prefix) return false;
    if (heading != null) {
      block
        ..kind = NoteBlockKind.heading
        ..level = heading[1]!.length;
    } else if (bullet != null) {
      block
        ..kind = NoteBlockKind.bullet
        ..marker = bullet[1]!
        ..gap = ' '
        ..indent = _nestUnder(entry);
    } else if (ordered != null) {
      block
        ..kind = NoteBlockKind.ordered
        ..number = int.parse(ordered[1]!)
        ..marker = ordered[2]!
        ..gap = ' '
        ..indent = _nestUnder(entry);
    } else {
      block.kind = NoteBlockKind.quote;
    }
    block.text = text.substring(prefix);
    entry.set('$_start${block.text}', 1);
    setState(() {});
    _emit();
    return true;
  }

  /// A new list item right under another sits at that item's level.
  int _nestUnder(_Block entry) {
    final i = _blocks.indexOf(entry);
    if (i == 0) return 0;
    final above = _blocks[i - 1].block;
    return above.isListItem ? above.indent : 0;
  }

  /// Return in [entry], with the text [before] and [after] the caret.
  void _return(_Block entry, String before, String after) {
    final block = entry.block;
    final index = _blocks.indexOf(entry);
    switch (block.kind) {
      case NoteBlockKind.paragraph:
        final fence = RegExp(r'^(`{3,}|~{3,})([^`]*)$').firstMatch(before);
        if (fence != null && after.isEmpty) {
          block
            ..kind = NoteBlockKind.code
            ..fence = fence[1]!
            ..info = fence[2]!.trim()
            ..text = '';
          entry.set(_start, 1);
          setState(() {});
          _emit();
          return;
        }
        if (RegExp(r'^(?:-{3,}|\*{3,}|_{3,})$').hasMatch(before) &&
            after.isEmpty) {
          block
            ..kind = NoteBlockKind.rule
            ..marker = before
            ..text = '';
          _insert(index + 1, NoteBlock.paragraph());
          return;
        }
        _split(entry, before, NoteBlock.paragraph(after));
      case NoteBlockKind.heading:
        _split(entry, before, NoteBlock.paragraph(after));
      case NoteBlockKind.bullet || NoteBlockKind.ordered:
        if (before.isEmpty && after.isEmpty) {
          // Return on an empty item leaves the list, a level at a time.
          if (block.indent > 0) {
            block.indent--;
          } else {
            block.kind = NoteBlockKind.paragraph;
          }
          entry.set(_start, 1);
          setState(() {});
          _emit();
          return;
        }
        _split(
          entry,
          before,
          block.copy()
            ..text = after
            ..number = block.number + 1
            ..blankBefore = false,
        );
      case NoteBlockKind.quote:
        final lineStart = before.lastIndexOf('\n') + 1;
        if (before.substring(lineStart).isEmpty && after.isEmpty) {
          // Return on an empty last line leaves the quote.
          final kept = lineStart == 0 ? '' : before.substring(0, lineStart - 1);
          if (kept.isEmpty) {
            block.kind = NoteBlockKind.paragraph;
            block.text = '';
            entry.set(_start, 1);
            setState(() {});
            _emit();
            return;
          }
          _split(entry, kept, NoteBlock.paragraph());
          return;
        }
        // Otherwise a quote takes several lines.
        block.text = '$before\n$after';
        entry.set('$_start${block.text}', before.length + 2);
        _emit();
      case NoteBlockKind.code || NoteBlockKind.raw || NoteBlockKind.rule:
        break;
    }
  }

  /// Keeps [before] in [entry] and starts [next] after it, focused at its
  /// start.
  void _split(_Block entry, String before, NoteBlock next) {
    entry.block.text = before;
    entry.set('$_start$before', before.length + 1);
    _insert(_blocks.indexOf(entry) + 1, next);
  }

  void _insert(int index, NoteBlock block, {bool atEnd = false}) {
    setState(() => _blocks.insert(index, _entry(block)));
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus(index, atEnd: atEnd);
    });
  }

  void _replaceWithParsed(_Block entry, String markdown) {
    final index = _blocks.indexOf(entry);
    final parsed = parseNoteBlocks(markdown);
    setState(() {
      _retire(_blocks.removeAt(index));
      _blocks.insertAll(index, parsed.map(_entry));
    });
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus(index + parsed.length - 1, atEnd: true);
    });
  }

  /// Backspace with the caret at the start of [entry]: first undoes its
  /// kind (a list item comes out a level first), then joins it to the
  /// block above.
  void _backspaceAtStart(_Block entry) {
    final block = entry.block;
    final index = _blocks.indexOf(entry);
    if (block.isListItem && block.indent > 0) {
      setState(() => block.indent--);
      _emit();
      return;
    }
    switch (block.kind) {
      case NoteBlockKind.heading ||
          NoteBlockKind.bullet ||
          NoteBlockKind.ordered ||
          NoteBlockKind.quote:
        setState(() => block.kind = NoteBlockKind.paragraph);
        _emit();
        return;
      case NoteBlockKind.code || NoteBlockKind.raw:
        if (block.text.isEmpty) {
          setState(() => block.kind = NoteBlockKind.paragraph);
          _emit();
        }
        return;
      case NoteBlockKind.rule:
        return;
      case NoteBlockKind.paragraph:
        break;
    }
    if (index == 0) return;
    final above = _blocks[index - 1];
    if (above.block.kind == NoteBlockKind.rule) {
      setState(() => _retire(_blocks.removeAt(index - 1)));
      _emit();
      return;
    }
    if (above.block.kind == NoteBlockKind.code ||
        above.block.kind == NoteBlockKind.raw) {
      if (block.text.isEmpty) {
        setState(() => _retire(_blocks.removeAt(index)));
        _emit();
      }
      _focus(index - 1, atEnd: true);
      return;
    }
    // Join: this block's text goes on the end of the one above.
    final join = above.block.text.length;
    above.block.text += block.text;
    above.set('$_start${above.block.text}', join + 1);
    setState(() => _retire(_blocks.removeAt(index)));
    _emit();
    above.focus.requestFocus();
    above.applying = true;
    above.controller.selection = TextSelection.collapsed(offset: join + 1);
    above.applying = false;
  }

  // Keys.

  KeyEventResult _key(_Block entry, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final index = _blocks.indexOf(entry);
    final selection = entry.controller.selection;
    final collapsed = selection.isValid && selection.isCollapsed;
    final length = entry.controller.text.length;

    if (key == LogicalKeyboardKey.enter && keys.isShiftPressed) {
      _softBreak = true;
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.tab && entry.block.isListItem) {
      final block = entry.block;
      if (keys.isShiftPressed) {
        if (block.indent > 0) setState(() => block.indent--);
      } else {
        final above = index > 0 ? _blocks[index - 1].block : null;
        final max = above != null && above.isListItem ? above.indent + 1 : 0;
        if (block.indent < max) setState(() => block.indent++);
      }
      _emit();
      return KeyEventResult.handled;
    }
    if (!collapsed || keys.isShiftPressed) return KeyEventResult.ignored;
    final caret = selection.extentOffset;

    if (key == LogicalKeyboardKey.arrowUp && entry.onFirstLine(caret)) {
      return _move(index, -1, atEnd: true);
    }
    if (key == LogicalKeyboardKey.arrowDown && entry.onLastLine(caret)) {
      return _move(index, 1, atEnd: false);
    }
    if (key == LogicalKeyboardKey.arrowLeft && caret <= 1) {
      return _move(index, -1, atEnd: true);
    }
    if (key == LogicalKeyboardKey.arrowRight && caret >= length) {
      return _move(index, 1, atEnd: false);
    }
    return KeyEventResult.ignored;
  }

  /// Focuses the next text block from [index] in [step]'s direction. Down
  /// from the last block, when that isn't a paragraph, adds one to type in.
  KeyEventResult _move(int index, int step, {required bool atEnd}) {
    var i = index + step;
    while (i >= 0 && i < _blocks.length) {
      if (_blocks[i].block.kind != NoteBlockKind.rule) {
        _focus(i, atEnd: atEnd);
        return KeyEventResult.handled;
      }
      i += step;
    }
    if (step > 0 && _blocks[index].block.kind != NoteBlockKind.paragraph) {
      _insert(_blocks.length, NoteBlock.paragraph());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _focus(int index, {required bool atEnd}) {
    if (index < 0 || index >= _blocks.length) return;
    final entry = _blocks[index];
    if (entry.block.kind == NoteBlockKind.rule) return;
    if (entry.block.kind == NoteBlockKind.raw && !entry.showSource) {
      // Its field appears first, then takes the caret.
      setState(() => entry.showSource = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _blocks.contains(entry)) _focus(index, atEnd: atEnd);
      });
      return;
    }
    entry.focus.requestFocus();
    entry.applying = true;
    entry.controller.selection = TextSelection.collapsed(
      offset: atEnd ? entry.controller.text.length : 1,
    );
    entry.applying = false;
  }

  // Layout.

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return Material(
      type: MaterialType.transparency,
      child: TextSelectionTheme(
        data: TextSelectionThemeData(
          cursorColor: style.cursorColor,
          selectionColor: style.selectionColor,
        ),
        child: widget.markdownMode ? _sourceField() : _blockColumn(),
      ),
    );
  }

  Widget _sourceField() => TextField(
    controller: _source,
    enabled: widget.enabled,
    autofocus: widget.autofocus,
    maxLines: null,
    minLines: 6,
    keyboardType: TextInputType.multiline,
    textInputAction: TextInputAction.newline,
    autocorrect: false,
    enableSuggestions: false,
    style: _mono,
    cursorColor: widget.style.cursorColor,
    decoration: InputDecoration.collapsed(
      hintText: widget.placeholder,
      hintStyle: _mono.copyWith(color: widget.style.placeholderColor),
    ),
    onChanged: (text) {
      _markdown = text;
      widget.onChanged(text);
    },
  );

  Widget _blockColumn() {
    final places = listPlaces([for (final b in _blocks) b.block]);
    final empty =
        _blocks.length == 1 &&
        _blocks.single.block.kind == NoteBlockKind.paragraph &&
        _blocks.single.block.text.isEmpty;
    final children = <Widget>[];
    for (final (i, entry) in _blocks.indexed) {
      if (i > 0) {
        final tight =
            entry.block.isListItem &&
            _blocks[i - 1].block.isListItem &&
            !entry.block.blankBefore;
        children.add(SizedBox(height: tight ? _md.blockGap / 2 : _md.blockGap));
      }
      children.add(
        KeyedSubtree(
          key: entry.key,
          child: _block(entry, places[i], placeholder: empty),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _block(
    _Block entry,
    ({int level, int number})? place, {
    required bool placeholder,
  }) {
    final block = entry.block;
    switch (block.kind) {
      case NoteBlockKind.rule:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: _md.blockGap / 2),
          child: SizedBox(height: 1, child: ColoredBox(color: _md.ruleColor)),
        );
      case NoteBlockKind.raw when !entry.showSource && !entry.focus.hasFocus:
        // Rendered until clicked, then edited as source.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focus(_blocks.indexOf(entry), atEnd: true),
          // The editor takes the click, not the rendered text's selection.
          child: IgnorePointer(
            child: MarkdownNote(block.text, style: _md, onLink: widget.onLink),
          ),
        );
      case NoteBlockKind.code:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: _md.codeBackground,
            border: Border.all(color: _md.ruleColor, width: 0.5),
            borderRadius: BorderRadius.all(Radius.circular(_md.codeRadius)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: _field(entry, placeholder: false),
          ),
        );
      case NoteBlockKind.quote:
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: _md.ruleColor, width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _field(entry, placeholder: false),
          ),
        );
      case NoteBlockKind.bullet || NoteBlockKind.ordered:
        final level = place?.level ?? 0;
        final marker = block.kind == NoteBlockKind.ordered
            ? '${place?.number ?? block.number}${block.marker}'
            : '•';
        return Padding(
          padding: EdgeInsets.only(left: level * _md.listIndent),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _md.listIndent,
                child: Text(
                  marker,
                  style: _md.body.copyWith(color: _md.secondaryColor),
                ),
              ),
              Expanded(child: _field(entry, placeholder: false)),
            ],
          ),
        );
      case NoteBlockKind.paragraph ||
          NoteBlockKind.heading ||
          NoteBlockKind.raw:
        return Semantics(
          header: block.kind == NoteBlockKind.heading,
          child: _field(entry, placeholder: placeholder),
        );
    }
  }

  Widget _field(_Block entry, {required bool placeholder}) {
    final style = _styleOf(entry.block);
    final source =
        entry.block.kind == NoteBlockKind.code ||
        entry.block.kind == NoteBlockKind.raw;
    return TextField(
      // Kept when the block changes kind and its field moves (into a list
      // row, a quote), so it keeps the caret.
      key: entry.fieldKey,
      controller: entry.controller,
      focusNode: entry.focus,
      enabled: widget.enabled,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      autocorrect: !source,
      enableSuggestions: !source,
      style: style,
      cursorColor: widget.style.cursorColor,
      decoration: InputDecoration.collapsed(
        hintText: placeholder ? widget.placeholder : null,
        hintStyle: style.copyWith(color: widget.style.placeholderColor),
      ),
    );
  }
}

/// One block on screen: its model, its field's controller and focus.
class _Block {
  _Block(
    this.block, {
    required TextSpan Function(TextStyle style) buildSpans,
    required KeyEventResult Function(KeyEvent event) onKey,
  }) : controller = _BlockController('$_start${block.text}', buildSpans),
       key = UniqueKey() {
    focus = FocusNode(onKeyEvent: (_, event) => onKey(event));
    last = controller.text;
  }

  final NoteBlock block;
  final _BlockController controller;
  late final FocusNode focus;
  final Key key;
  final fieldKey = GlobalKey();

  /// The text before the latest edit.
  late String last;

  /// Set while the editor itself changes [controller], so its listener
  /// leaves that change alone.
  bool applying = false;

  /// A raw block shows its source field (rather than rendered Markdown).
  bool showSource = false;

  void set(String text, int caret) {
    applying = true;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret.clamp(1, text.length)),
    );
    last = text;
    applying = false;
  }

  EditableTextState? get _editable =>
      focus.context?.findAncestorStateOfType<EditableTextState>();

  double? _caretTop(int offset) => _editable?.renderEditable
      .getLocalRectForCaret(TextPosition(offset: offset))
      .top;

  bool onFirstLine(int caret) {
    final top = _caretTop(caret);
    final first = _caretTop(1);
    return top == null || first == null || (top - first).abs() < 1;
  }

  bool onLastLine(int caret) {
    final top = _caretTop(caret);
    final last = _caretTop(controller.text.length);
    return top == null || last == null || (top - last).abs() < 1;
  }

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

/// Draws a block's text with its inline Markdown, through the editor.
class _BlockController extends TextEditingController {
  _BlockController(String text, this._buildSpans) : super(text: text);

  final TextSpan Function(TextStyle style) _buildSpans;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // While an input method composes, show its text plainly, underlined.
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return _buildSpans(style ?? const TextStyle());
  }
}
