import 'package:devvault/shared/widgets/markdown_note.dart';
import 'package:devvault/shared/widgets/note_editor/inline_markdown.dart';
import 'package:devvault/shared/widgets/note_editor/note_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = NoteEditorStyle(
  markdown: MarkdownNoteStyle(
    body: TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF111111)),
    secondaryColor: Color(0xFF666666),
    linkColor: Color(0xFF0066CC),
    codeBackground: Color(0xFFEEEEEE),
    ruleColor: Color(0xFFCCCCCC),
    headingSizes: [24, 18, 16],
    codeRadius: 4,
    hintBackground: Color(0xFFFFFFFF),
    hintColor: Color(0xFF111111),
  ),
  cursorColor: Color(0xFF0066CC),
  selectionColor: Color(0x330066CC),
  placeholderColor: Color(0xFF999999),
);

void main() {
  late String markdown;

  Future<void> pumpEditor(
    WidgetTester tester, {
    String initial = '',
    bool markdownMode = false,
  }) async {
    markdown = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 600,
              child: NoteEditor(
                initialMarkdown: initial,
                markdownMode: markdownMode,
                style: _style,
                placeholder: 'Write in Markdown',
                onLink: (_) {},
                onChanged: (m) => markdown = m,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder focusedField() =>
      find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus);

  /// Types [chars] one at a time where the caret is, as a keyboard does.
  Future<void> type(WidgetTester tester, String chars) async {
    for (final ch in chars.split('')) {
      final value = tester
          .state<EditableTextState>(focusedField())
          .textEditingValue;
      final selection = value.selection;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: value.text.replaceRange(selection.start, selection.end, ch),
          selection: TextSelection.collapsed(offset: selection.start + 1),
        ),
      );
      await tester.pump();
      await tester.pump();
    }
  }

  /// Backspace: deletes the character before the caret.
  Future<void> backspace(WidgetTester tester) async {
    final value = tester
        .state<EditableTextState>(focusedField())
        .textEditingValue;
    final at = value.selection.start;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: value.text.replaceRange(at - 1, at, ''),
        selection: TextSelection.collapsed(offset: at - 1),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> startTyping(WidgetTester tester) async {
    await tester.tap(find.byType(EditableText).first);
    await tester.pump();
  }

  /// The text the focused block's field shows, without its start mark.
  String focusedText(WidgetTester tester) => tester
      .widget<EditableText>(focusedField())
      .controller
      .text
      .replaceAll('\u200B', '');

  testWidgets('"# " makes a heading 1, and the # is gone', (tester) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, '# Title');
    expect(markdown, '# Title');
    expect(focusedText(tester), 'Title');
    final field = tester.widget<EditableText>(focusedField());
    expect(field.style.fontSize, 24, reason: 'drawn as a heading 1');
    expect(find.bySemanticsLabel('Title'), findsNothing);
  });

  testWidgets('"## " and "###### " make smaller headings', (tester) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, '## Keys\nbody');
    expect(markdown, '## Keys\n\nbody');
    await type(tester, '\n###### small');
    expect(markdown, '## Keys\n\nbody\n\n###### small');
  });

  testWidgets('Return after a heading starts a paragraph', (tester) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, '# A\nplain');
    expect(markdown, '# A\n\nplain');
    expect(tester.widget<EditableText>(focusedField()).style.fontSize, 14);
  });

  testWidgets('bullets: Return adds an item, Return on an empty one leaves', (
    tester,
  ) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, '- one\ntwo\n');
    expect(markdown, '- one\n- two\n-');
    await type(tester, '\nafter');
    expect(markdown, '- one\n- two\n\nafter');
    expect(find.text('•'), findsNWidgets(2));
  });

  testWidgets('numbered items count on', (tester) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, '1. first\nsecond\nthird');
    expect(markdown, '1. first\n2. second\n3. third');
    expect(find.text('3.'), findsOneWidget);
  });

  testWidgets('Tab nests a list item, Shift-Tab brings it back', (
    tester,
  ) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, '- a\nb');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(markdown, '- a\n  - b');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(markdown, '- a\n- b');
  });

  testWidgets('"> " makes a quote; Return on its empty last line leaves it', (
    tester,
  ) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, '> careful\nreally\n\nout');
    expect(markdown, '> careful\n> really\n\nout');
  });

  testWidgets('``` and Return makes code; a closing fence ends it', (
    tester,
  ) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, '```bash\n');
    expect(markdown, '```bash\n```');
    await type(tester, 'export A=1\n# a comment, not a heading\n```\nafter');
    expect(
      markdown,
      '```bash\nexport A=1\n# a comment, not a heading\n```\n\nafter',
    );
  });

  testWidgets('--- and Return makes a rule', (tester) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, 'above\n---\nbelow');
    expect(markdown, 'above\n\n---\n\nbelow');
  });

  testWidgets('Shift-Return breaks the line inside a paragraph', (
    tester,
  ) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, 'line one');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await type(tester, '\n');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await type(tester, 'line two');
    expect(markdown, 'line one\nline two');
  });

  testWidgets('Backspace at the start undoes a heading, then joins', (
    tester,
  ) async {
    await pumpEditor(tester);
    await startTyping(tester);
    await type(tester, '# Title\nbody');
    // To the start of "body", then Backspace twice: join, nothing else.
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();
    await backspace(tester);
    expect(markdown, '# Titlebody');
    expect(focusedText(tester), 'Titlebody');
    // At the very start of the heading now: it becomes a paragraph.
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.pump();
    await backspace(tester);
    expect(markdown, 'Titlebody');
  });

  testWidgets('Backspace at the start of a list item takes it out a level', (
    tester,
  ) async {
    await pumpEditor(tester, initial: '- a\n  - b');
    await tester.tap(find.byType(EditableText).last);
    await tester.pump();
    // The caret to the start of "b", just after the hidden start mark.
    final value = tester
        .state<EditableTextState>(focusedField())
        .textEditingValue;
    tester.testTextInput.updateEditingValue(
      value.copyWith(selection: const TextSelection.collapsed(offset: 1)),
    );
    await tester.pump();
    await backspace(tester);
    expect(markdown, '- a\n- b');
    await backspace(tester);
    expect(markdown, '- a\n\nb');
  });

  testWidgets('the arrows move between blocks', (tester) async {
    await pumpEditor(tester, initial: '# One\n\nTwo');
    await tester.tap(find.byType(EditableText).last);
    await tester.pump();
    expect(focusedText(tester), 'Two');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusedText(tester), 'One');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedText(tester), 'Two');
  });

  testWidgets('pasting Markdown into a paragraph makes blocks', (tester) async {
    await pumpEditor(tester);
    await startTyping(tester);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '\u200B# Pasted\n- one\n- two',
        selection: TextSelection.collapsed(offset: 21),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(markdown, '# Pasted\n\n- one\n- two');
    expect(find.text('•'), findsNWidgets(2));
  });

  testWidgets('a note opens in its blocks and saves as it was', (tester) async {
    const note =
        '# Billing API\n\nKeys rotate **yearly**.\n\n- prod\n  - eu\n\n'
        '| a | b |\n|---|---|\n| 1 | 2 |\n\n```\ncode\n```';
    await pumpEditor(tester, initial: note);
    await tester.tap(find.byType(EditableText).first);
    await tester.pump();
    await type(tester, '!');
    expect(markdown, note.replaceFirst('Billing API', 'Billing API!'));
  });

  testWidgets('a table shows rendered, and as source once clicked', (
    tester,
  ) async {
    const table = '| a | b |\n|---|---|\n| 1 | 2 |';
    await pumpEditor(tester, initial: table);
    expect(find.byType(MarkdownNote), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    await tester.tap(find.byType(MarkdownNote));
    await tester.pump();
    await tester.pump();
    expect(find.byType(MarkdownNote), findsNothing);
    expect(focusedText(tester), table);
  });

  group('inline marks', () {
    TextSpan spansOf(WidgetTester tester, Finder field) {
      final editable = tester.widget<EditableText>(field);
      return editable.controller.buildTextSpan(
        context: tester.element(field),
        style: editable.style,
        withComposing: false,
      );
    }

    List<TextSpan> leaves(InlineSpan span) => [
      if (span is TextSpan) ...[
        if (span.text != null) span,
        for (final c in span.children ?? const <InlineSpan>[]) ...leaves(c),
      ],
    ];

    testWidgets('show faintly while editing, take no room otherwise', (
      tester,
    ) async {
      await pumpEditor(tester, initial: 'Use **prod** and `kid`\n\nOther');
      final first = find.byType(EditableText).first;
      final stars = leaves(spansOf(tester, first)).where((s) => s.text == '**');
      expect(stars, hasLength(2));
      expect(stars.every((s) => s.style == hiddenMarkStyle), isTrue);
      final bold = leaves(spansOf(tester, first))
          .firstWhere((s) => s.text == 'prod');
      expect(bold.style?.fontWeight, FontWeight.w700);

      await tester.tap(first);
      await tester.pump();
      final shown = leaves(spansOf(tester, first)).where((s) => s.text == '**');
      expect(shown.every((s) => s.style != hiddenMarkStyle), isTrue);
      expect(
        shown.first.style?.color,
        _style.markdown.secondaryColor.withValues(alpha: 0.7),
      );
    });

    testWidgets('snake_case and lone stars stay as typed', (tester) async {
      await pumpEditor(tester, initial: 'my_api_key costs 2 * 3');
      final spans = leaves(spansOf(tester, find.byType(EditableText)));
      expect(
        spans.any((s) => s.style == hiddenMarkStyle && s.text != '\u200B'),
        isFalse,
      );
    });
  });

  testWidgets('Markdown mode edits the source; back to blocks parses it', (
    tester,
  ) async {
    await pumpEditor(tester, initial: '# A');
    await pumpEditor(tester, initial: '# A', markdownMode: true);
    expect(find.text('# A'), findsOneWidget);
  });

  testWidgets('switching modes keeps the note', (tester) async {
    var mode = false;
    late StateSetter setMode;
    markdown = '# A';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setMode = setState;
              return NoteEditor(
                initialMarkdown: '# A',
                markdownMode: mode,
                style: _style,
                onLink: (_) {},
                onChanged: (m) => markdown = m,
              );
            },
          ),
        ),
      ),
    );
    setMode(() => mode = true);
    await tester.pump();
    expect(find.text('# A'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), '# A\n\n- b');
    expect(markdown, '# A\n\n- b');
    setMode(() => mode = false);
    await tester.pump();
    expect(find.text('•'), findsOneWidget);
    expect(find.byType(EditableText), findsNWidgets(2));
  });

  testWidgets('an empty note shows the placeholder', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Write in Markdown'), findsOneWidget);
  });
}
