/// A note as the WYSIWYG editor holds it: a list of blocks, each with its
/// own text and no block syntax. Markdown goes in through [parseNoteBlocks]
/// and comes back out through [serializeNoteBlocks].
///
/// Only what the editor can show as itself is modelled: paragraphs, ATX
/// headings, bullet and numbered list items, quotes, fenced code and rules.
/// Anything else (tables, HTML, setext headings, indented code, link
/// reference definitions, quotes holding other blocks) becomes a [raw]
/// block that keeps its lines exactly as typed. Inline Markdown (`**bold**`,
/// `` `code` ``, links) stays in a block's text as typed.
///
/// Markdown in the shape [serializeNoteBlocks] writes comes back unchanged
/// through a parse and a serialize. Other shapes are normalized only where
/// it doesn't change what the note says: list markers keep their
/// character, numbers restart where a list starts, continuation lines are
/// re-indented.
library;

enum NoteBlockKind {
  paragraph,
  heading,
  bullet,
  ordered,
  quote,
  code,
  rule,

  /// Markdown the editor doesn't model, kept verbatim.
  raw,
}

class NoteBlock {
  NoteBlock(
    this.kind, {
    this.text = '',
    this.level = 1,
    this.marker = '-',
    this.gap = ' ',
    this.number = 1,
    this.indent = 0,
    this.info = '',
    this.fence = '```',
    this.blankBefore = false,
  });

  NoteBlock.paragraph([String text = ''])
    : this(NoteBlockKind.paragraph, text: text);

  NoteBlockKind kind;

  /// The block's own text: for a heading, list item or quote, without its
  /// marker; for code, the lines between the fences; for raw, the source.
  String text;

  /// Heading level, 1 to 6.
  int level;

  /// A bullet's character (`-`, `*`, `+`), an ordered item's delimiter
  /// (`.` or `)`), or a rule as typed (`---`).
  String marker;

  /// The spaces between a list marker and its text.
  String gap;

  /// An ordered item's number as typed. Only the first item of a list is
  /// written as typed; the rest count on from it.
  int number;

  /// How deeply a list item is nested: 0 at the top.
  int indent;

  /// A code block's info string (its language).
  String info;

  /// A code block's fence: three or more backticks or tildes.
  String fence;

  /// A blank line came before this list item: the list is loose there.
  bool blankBefore;

  bool get isListItem =>
      kind == NoteBlockKind.bullet || kind == NoteBlockKind.ordered;

  NoteBlock copy() => NoteBlock(
    kind,
    text: text,
    level: level,
    marker: marker,
    gap: gap,
    number: number,
    indent: indent,
    info: info,
    fence: fence,
    blankBefore: blankBefore,
  );

  @override
  String toString() => 'NoteBlock(${kind.name})';
}

final _blank = RegExp(r'^[ \t]*$');
final _fenceOpen = RegExp(r'^(`{3,}|~{3,})(.*)$');
final _heading = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*$');
final _closedHeading = RegExp(r'[ \t]#+[ \t]*$');
final _rule = RegExp(
  r'^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$',
);
final _bullet = RegExp(r'^( *)([-*+])( +)(.*)$');
final _emptyBullet = RegExp(r'^( *)([-*+])$');
final _ordered = RegExp(r'^( *)(\d{1,9})([.)])( +)(.*)$');
final _emptyOrdered = RegExp(r'^( *)(\d{1,9})([.)])$');
final _quote = RegExp(r'^ {0,3}>(.*)$');
final _html = RegExp(r'^ {0,3}<[A-Za-z/!?]');
final _indentedCode = RegExp(r'^(?: {4}|\t)');
final _tableDelimiter = RegExp(
  r'^[ \t]*\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*$',
);
final _setext = RegExp(r'^ {0,3}(?:=+|-+)[ \t]*$');
final _reference = RegExp(r'^ {0,3}\[[^\]]+\]:');

/// Lines that start a block of their own: inside a paragraph they would
/// end it, so [serializeNoteBlocks] escapes them there.
final _blockStart = RegExp(
  r'^(?:#{1,6}(?:[ \t]|$)|[-*+](?:[ \t]|$)|\d{1,9}[.)](?:[ \t]|$)|>|`{3,}|~{3,}|'
  r'(?:-[ \t]*){3,}$|(?:\*[ \t]*){3,}$|(?:_[ \t]*){3,}$|=+[ \t]*$)',
);

/// The note's blocks. Empty Markdown gives one empty paragraph, so there
/// is always somewhere to type.
List<NoteBlock> parseNoteBlocks(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final blocks = <NoteBlock>[];
  // Content columns of the open list items, outermost first.
  final listColumns = <int>[];
  var blankBefore = false;
  var i = 0;

  bool startsBlock(String line) =>
      _fenceOpen.hasMatch(line) ||
      _heading.hasMatch(line) ||
      _rule.hasMatch(line) ||
      _quote.hasMatch(line) ||
      _bullet.hasMatch(line) ||
      _ordered.hasMatch(line) ||
      _html.hasMatch(line);

  void raw(int from, int to) {
    blocks.add(
      NoteBlock(NoteBlockKind.raw, text: lines.sublist(from, to).join('\n')),
    );
    listColumns.clear();
  }

  while (i < lines.length) {
    final line = lines[i];
    if (_blank.hasMatch(line)) {
      blankBefore = true;
      i++;
      continue;
    }
    final wasBlank = blankBefore;
    blankBefore = false;

    // Fenced code, up to its closing fence (or the end of the note).
    if (_fenceOpen.firstMatch(line) case final m?) {
      final fence = m[1]!;
      final info = m[2]!;
      if (!(fence.startsWith('`') && info.contains('`'))) {
        final close = RegExp(
          '^${RegExp.escape(fence[0])}{${fence.length},}[ \\t]*\$',
        );
        var end = i + 1;
        while (end < lines.length && !close.hasMatch(lines[end])) {
          end++;
        }
        blocks.add(
          NoteBlock(
            NoteBlockKind.code,
            text: lines
                .sublist(i + 1, end.clamp(i + 1, lines.length))
                .join('\n'),
            fence: fence,
            info: info.trim(),
          ),
        );
        listColumns.clear();
        i = end < lines.length ? end + 1 : end;
        continue;
      }
    }

    if (_heading.firstMatch(line) case final m?) {
      final text = m[2] ?? '';
      if (_closedHeading.hasMatch(' $text') && text.isNotEmpty) {
        raw(i, i + 1);
      } else {
        blocks.add(
          NoteBlock(NoteBlockKind.heading, text: text, level: m[1]!.length),
        );
        listColumns.clear();
      }
      i++;
      continue;
    }

    // Before list items: `- - -` and `* * *` are rules.
    if (_rule.hasMatch(line)) {
      blocks.add(NoteBlock(NoteBlockKind.rule, marker: line));
      listColumns.clear();
      i++;
      continue;
    }

    // A quote: its lines, and any lazy lines after them.
    if (_quote.hasMatch(line)) {
      final start = i;
      final content = <String>[];
      var nested = false;
      while (i < lines.length && !_blank.hasMatch(lines[i])) {
        final q = _quote.firstMatch(lines[i]);
        if (q == null && startsBlock(lines[i])) break;
        var text = q == null ? lines[i] : q[1]!;
        if (q != null && text.startsWith(' ')) text = text.substring(1);
        if (startsBlock(text) || _quote.hasMatch(text)) nested = true;
        content.add(text);
        i++;
      }
      if (nested) {
        raw(start, i);
      } else {
        blocks.add(NoteBlock(NoteBlockKind.quote, text: content.join('\n')));
        listColumns.clear();
      }
      continue;
    }

    // A list item, with its continuation lines.
    final bullet = _bullet.firstMatch(line) ?? _emptyBullet.firstMatch(line);
    final ordered = bullet == null
        ? _ordered.firstMatch(line) ?? _emptyOrdered.firstMatch(line)
        : null;
    if (bullet != null || ordered != null) {
      final m = (bullet ?? ordered)!;
      final lead = m[1]!.length;
      while (listColumns.isNotEmpty && lead < listColumns.last) {
        listColumns.removeLast();
      }
      final indent = listColumns.length;
      final block = bullet != null
          ? NoteBlock(
              NoteBlockKind.bullet,
              marker: m[2]!,
              gap: m.groupCount >= 4 ? m[3] ?? ' ' : ' ',
              text: m.groupCount >= 4 ? m[4] ?? '' : '',
              indent: indent,
              blankBefore: wasBlank,
            )
          : NoteBlock(
              NoteBlockKind.ordered,
              number: int.parse(m[2]!),
              marker: m[3]!,
              gap: m.groupCount >= 5 ? m[4] ?? ' ' : ' ',
              text: m.groupCount >= 5 ? m[5] ?? '' : '',
              indent: indent,
              blankBefore: wasBlank,
            );
      if (block.gap.isEmpty) block.gap = ' ';
      final markerWidth = bullet != null ? 1 : m[2]!.length + 1;
      listColumns.add(lead + markerWidth + block.gap.length);
      i++;
      // Lazy and indented continuation lines belong to the item.
      final more = <String>[];
      while (i < lines.length &&
          !_blank.hasMatch(lines[i]) &&
          !startsBlock(lines[i].trimLeft()) &&
          !_setext.hasMatch(lines[i])) {
        more.add(lines[i].trimLeft());
        i++;
      }
      if (more.isNotEmpty) block.text = [block.text, ...more].join('\n');
      blocks.add(block);
      continue;
    }

    // HTML, as CommonMark's HTML blocks: up to the next blank line.
    if (_html.hasMatch(line)) {
      final start = i;
      while (i < lines.length && !_blank.hasMatch(lines[i])) {
        i++;
      }
      raw(start, i);
      continue;
    }

    // Everything else runs to the next blank line or block start.
    final start = i;
    final paragraph = <String>[line];
    i++;
    while (i < lines.length &&
        !_blank.hasMatch(lines[i]) &&
        !_interruptsParagraph(lines[i])) {
      paragraph.add(lines[i]);
      i++;
    }
    final isRaw =
        _html.hasMatch(line) ||
        _reference.hasMatch(line) ||
        _indentedCode.hasMatch(line) && (wasBlank || blocks.isEmpty) ||
        paragraph.length > 1 &&
            (_tableDelimiter.hasMatch(paragraph[1]) ||
                paragraph.skip(1).any(_setext.hasMatch));
    if (isRaw) {
      raw(start, i);
    } else {
      blocks.add(NoteBlock.paragraph(paragraph.join('\n')));
      listColumns.clear();
    }
  }
  if (blocks.isEmpty) blocks.add(NoteBlock.paragraph());
  return blocks;
}

/// Whether [line] ends the paragraph above it and starts a block. A `---`
/// or `===` line doesn't: it turns the paragraph into a setext heading. An
/// ordered list interrupts only when it starts at 1.
bool _interruptsParagraph(String line) {
  if (_setext.hasMatch(line)) return false;
  if (_ordered.firstMatch(line) case final m?) return m[2] == '1';
  return _fenceOpen.hasMatch(line) ||
      _heading.hasMatch(line) ||
      _rule.hasMatch(line) ||
      _quote.hasMatch(line) ||
      _bullet.hasMatch(line) && _bullet.firstMatch(line)![4]!.isNotEmpty ||
      _html.hasMatch(line);
}

/// Where each list item sits and what an ordered one counts as, the way
/// [serializeNoteBlocks] writes them: a nesting level is at most one deeper
/// than the item above, and a list (the same kind and marker at a level)
/// keeps its first item's number and counts on from there. Null for blocks
/// that aren't list items.
List<({int level, int number})?> listPlaces(List<NoteBlock> blocks) {
  final out = <({int level, int number})?>[];
  final lastAt = <int, (NoteBlock, int)>{};
  var depth = 0;
  for (final block in blocks) {
    if (!block.isListItem) {
      lastAt.clear();
      depth = 0;
      out.add(null);
      continue;
    }
    final level = block.indent.clamp(0, depth);
    depth = level + 1;
    lastAt.removeWhere((l, _) => l > level);
    final last = lastAt[level];
    final continues =
        last != null &&
        last.$1.kind == block.kind &&
        last.$1.marker == block.marker;
    final number = block.kind == NoteBlockKind.ordered
        ? (continues ? last.$2 + 1 : block.number)
        : 0;
    lastAt[level] = (block, number);
    out.add((level: level, number: number));
  }
  return out;
}

/// The note as Markdown, without a trailing line break.
String serializeNoteBlocks(List<NoteBlock> blocks) {
  final out = StringBuffer();
  // Content columns of the list items above, by nesting level.
  final columns = <int>[];
  final places = listPlaces(blocks);
  NoteBlock? previous;

  for (final (index, block) in blocks.indexed) {
    if (previous != null) {
      final tight =
          previous.isListItem && block.isListItem && !block.blankBefore;
      out.write(tight ? '\n' : '\n\n');
    }
    if (!block.isListItem) columns.clear();
    switch (block.kind) {
      case NoteBlockKind.paragraph:
        out.write(
          block.text
              .split('\n')
              .map(
                (l) => _blockStart.hasMatch(l.trimLeft())
                    ? l.replaceFirstMapped(RegExp('^ *'), (m) => '${m[0]}\\')
                    : l,
              )
              .join('\n'),
        );
      case NoteBlockKind.heading:
        final text = block.text.replaceAll('\n', ' ');
        out.write(
          '${'#' * block.level.clamp(1, 6)}${text.isEmpty ? '' : ' $text'}',
        );
      case NoteBlockKind.bullet || NoteBlockKind.ordered:
        final (:level, :number) = places[index]!;
        final lead = level == 0 ? 0 : columns[level - 1];
        columns.length = level;
        final marker = block.kind == NoteBlockKind.ordered
            ? '$number${block.marker}'
            : block.marker;
        final gap = block.gap.isEmpty ? ' ' : block.gap;
        final column = lead + marker.length + gap.length;
        columns.add(column);
        final lines = block.text.split('\n');
        out.write(' ' * lead);
        out.write(
          lines.first.isEmpty && lines.length == 1
              ? marker
              : '$marker$gap${lines.first}',
        );
        for (final l in lines.skip(1)) {
          out.write('\n${' ' * column}$l');
        }
      case NoteBlockKind.quote:
        out.write(
          block.text
              .split('\n')
              .map((l) => l.isEmpty ? '>' : '> $l')
              .join('\n'),
        );
      case NoteBlockKind.code:
        final info = block.info.isEmpty ? '' : block.info;
        // A longer fence when the code itself holds one.
        var fence = block.fence;
        while (block.text
            .split('\n')
            .any(
              (l) =>
                  l.trimRight().startsWith(fence) &&
                  l.trimRight().replaceAll(fence[0], '').isEmpty,
            )) {
          fence += fence[0];
        }
        out.write('$fence$info\n');
        if (block.text.isNotEmpty) out.write('${block.text}\n');
        out.write(fence);
      case NoteBlockKind.rule:
        out.write(_rule.hasMatch(block.marker) ? block.marker : '---');
      case NoteBlockKind.raw:
        out.write(block.text);
    }
    previous = block;
  }
  return out.toString();
}
