import 'package:devvault/app/theme.dart';
import 'package:devvault/shared/widgets/markdown_note.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Markdown renderer for notes (SPEC §6.6), on its own.
void main() {
  const style = MarkdownNoteStyle(
    body: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF111111)),
    secondaryColor: Color(0xFF666666),
    linkColor: Color(0xFF0A64D8),
    codeBackground: Color(0xFFF0F0F0),
    ruleColor: Color(0xFFDDDDDD),
    headingSizes: [20, 17, 15],
    codeRadius: 4,
    hintBackground: Color(0xFFFAFAFA),
    hintColor: Color(0xFF111111),
  );

  late List<String> followed;

  Future<void> pump(
    WidgetTester tester,
    String markdown, {
    bool hover = false,
  }) async {
    followed = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownNote(
              markdown,
              style: style,
              showLinkOnHover: hover,
              onLink: followed.add,
            ),
          ),
        ),
      ),
    );
  }

  /// Every piece of text the note draws, as plain text.
  List<String> texts(WidgetTester tester) => [
    for (final t in tester.widgetList<RichText>(find.byType(RichText)))
      t.text.toPlainText(),
  ];

  /// The innermost span that holds [text], and the style it draws with.
  (TextSpan, TextStyle) spanOf(WidgetTester tester, String text) {
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      (TextSpan, TextStyle)? found;
      void visit(InlineSpan span, TextStyle inherited) {
        if (span is! TextSpan || found != null) return;
        final merged = inherited.merge(span.style);
        if (span.text?.contains(text) ?? false) {
          found = (span, merged);
          return;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, merged);
        }
      }

      visit(rich.text, const TextStyle());
      if (found case final hit?) return hit;
    }
    fail('no span with "$text"');
  }

  /// The middle of [text] on screen.
  Offset centerOf(WidgetTester tester, String text) {
    final range = find.textRange.ofSubstring(text).evaluate().first;
    final box = range.renderObject
        .getBoxesForSelection(
          TextSelection(
            baseOffset: range.textRange.start,
            extentOffset: range.textRange.end,
          ),
        )
        .first
        .toRect();
    return range.renderObject.localToGlobal(box.center);
  }

  testWidgets('headings are headers, larger than the body, in bold', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, '# Keys\n\n## Rotation\n\n### Steps\n\nBody');
    final (_, h1) = spanOf(tester, 'Keys');
    final (_, h2) = spanOf(tester, 'Rotation');
    final (_, h3) = spanOf(tester, 'Steps');
    final (_, body) = spanOf(tester, 'Body');
    expect(
      [h1.fontSize, h2.fontSize, h3.fontSize, body.fontSize],
      [20, 17, 15, 13],
    );
    expect(h1.fontWeight, FontWeight.w700);
    expect(
      tester.getSemantics(find.text('Keys')),
      matchesSemantics(isHeader: true, label: 'Keys'),
    );
    semantics.dispose();
  });

  testWidgets('emphasis: italic, bold, and both', (tester) async {
    await pump(tester, 'Some *italic*, **bold** and ***both***.');
    expect(spanOf(tester, 'italic').$2.fontStyle, FontStyle.italic);
    expect(spanOf(tester, 'bold').$2.fontWeight, FontWeight.w700);
    final both = spanOf(tester, 'both').$2;
    expect(both.fontStyle, FontStyle.italic);
    expect(both.fontWeight, FontWeight.w700);
    expect(texts(tester), ['Some italic, bold and both.']);
  });

  testWidgets('lists: bullets, numbers from their start, nesting', (
    tester,
  ) async {
    await pump(tester, '- one\n- two\n  - nested\n\n3. three\n4. four');
    final shown = texts(tester);
    expect(shown.where((t) => t == '•'), hasLength(3));
    expect(shown, containsAll(['one', 'two', 'nested', '3.', 'three', '4.']));
    expect(shown, contains('four'));
  });

  testWidgets('code spans and blocks are mono, on the code background', (
    tester,
  ) async {
    await pump(tester, 'Run `make rotate`.\n\n```sh\nmake deploy <env>\n```');
    final (_, inline) = spanOf(tester, 'make rotate');
    expect(inline.fontFamily, AppText.monoFamily);
    expect(inline.backgroundColor, style.codeBackground);
    final (_, block) = spanOf(tester, 'make deploy');
    expect(block.fontFamily, AppText.monoFamily);
    // A code block keeps its lines and scrolls sideways rather than wrap.
    expect(texts(tester), contains('make deploy <env>'));
    expect(
      find.ancestor(
        of: find.text('make deploy <env>'),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('quotes are set off in the secondary colour', (tester) async {
    await pump(tester, '> Ask Sam before rotating.');
    expect(spanOf(tester, 'Ask Sam').$2.color, style.secondaryColor);
  });

  testWidgets('single line breaks are kept, as typed in a note', (
    tester,
  ) async {
    await pump(tester, 'Line one\nLine two\n\nNext paragraph');
    expect(texts(tester), ['Line one\nLine two', 'Next paragraph']);
  });

  testWidgets('plain notes written before Markdown read the same', (
    tester,
  ) async {
    const plain =
        'Upload key for Play App Signing. Google holds the app signing key.';
    await pump(tester, plain);
    expect(texts(tester), [plain]);
    expect(spanOf(tester, 'Upload').$2.fontSize, 13);
  });

  group('images', () {
    testWidgets('are never loaded: their alt text, or their URL, instead', (
      tester,
    ) async {
      await pump(
        tester,
        'Logo: ![Acme logo](https://acme.example/logo.png)\n\n'
        '![](https://tracker.example/pixel.gif)\n\n'
        '![local](file:///etc/passwd)',
      );
      expect(find.byType(Image), findsNothing);
      expect(texts(tester), [
        'Logo: [Image: Acme logo]',
        '[Image: https://tracker.example/pixel.gif]',
        '[Image: local]',
      ]);
      expect(spanOf(tester, 'Acme logo').$2.color, style.secondaryColor);
    });

    testWidgets('an image inside a link is the link, in words', (tester) async {
      await pump(
        tester,
        '[![badge](https://ci.example/badge.svg)](https://ci.example)',
      );
      expect(find.byType(Image), findsNothing);
      await tester.tapOnText(find.textRange.ofSubstring('badge'));
      expect(followed, ['https://ci.example']);
    });
  });

  group('HTML', () {
    testWidgets('inline HTML is shown as text, not interpreted', (
      tester,
    ) async {
      await pump(tester, 'Not <b>bold</b> or <img src="https://x.example/a">');
      expect(texts(tester), [
        'Not <b>bold</b> or <img src="https://x.example/a">',
      ]);
      expect(spanOf(tester, 'bold').$2.fontWeight, isNot(FontWeight.w700));
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('an HTML block is shown as text', (tester) async {
      await pump(
        tester,
        'Before\n\n<div>\n<script>alert(1)</script>\n</div>\n\nAfter',
      );
      expect(texts(tester), [
        'Before',
        '<div>\n<script>alert(1)</script>\n</div>',
        'After',
      ]);
    });
  });

  group('links', () {
    testWidgets('look like links; a click reports the URL and opens nothing', (
      tester,
    ) async {
      await pump(
        tester,
        'See the [wiki](https://wiki.example/billing) or '
        '<https://status.example>.',
      );
      final (span, linkStyle) = spanOf(tester, 'wiki');
      expect(linkStyle.color, style.linkColor);
      expect(linkStyle.decoration, TextDecoration.underline);
      expect(span.recognizer, isA<TapGestureRecognizer>());
      expect(followed, isEmpty);

      await tester.tapOnText(find.textRange.ofSubstring('wiki'));
      await tester.tapOnText(find.textRange.ofSubstring('status.example'));
      expect(followed, [
        'https://wiki.example/billing',
        'https://status.example',
      ]);
    });

    testWidgets('a javascript: link is only ever reported, like any other', (
      tester,
    ) async {
      await pump(tester, '[click](javascript:alert(1))');
      await tester.tapOnText(find.textRange.ofSubstring('click'));
      expect(followed, ['javascript:alert(1)']);
    });

    testWidgets('on desktop, pointing at a link shows where it goes', (
      tester,
    ) async {
      await pump(
        tester,
        'See the [wiki](https://wiki.example/billing).',
        hover: true,
      );
      expect(find.textContaining('wiki.example/billing'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(centerOf(tester, 'wiki'));
      await tester.pump();
      expect(
        find.text('https://wiki.example/billing\nClick to copy the link'),
        findsOneWidget,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(find.textContaining('wiki.example/billing'), findsNothing);
    });

    testWidgets('without hover, pointing shows nothing extra', (tester) async {
      await pump(tester, '[wiki](https://wiki.example)');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(centerOf(tester, 'wiki'));
      await tester.pump();
      expect(find.textContaining('Click to copy'), findsNothing);
    });
  });

  test('firstLine: the first line of text, without Markdown', () {
    expect(
      MarkdownNote.firstLine('\n## Rotate **keys**\n\nEvery 90 days'),
      'Rotate keys',
    );
    expect(MarkdownNote.firstLine('- `make deploy`\n- check'), 'make deploy');
    expect(MarkdownNote.firstLine('   '), '');
  });
}
