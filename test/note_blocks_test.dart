import 'package:devvault/shared/widgets/note_editor/note_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String roundTrip(String markdown) =>
      serializeNoteBlocks(parseNoteBlocks(markdown));

  List<NoteBlockKind> kinds(String markdown) => [
    for (final b in parseNoteBlocks(markdown)) b.kind,
  ];

  group('Markdown in the editor’s own shape comes back unchanged', () {
    for (final (name, markdown) in [
      ('a paragraph', 'Rotate the key every year.'),
      ('line breaks in a paragraph', 'Owner: Rifat\nEscalation: on-call'),
      ('headings', '# Billing API\n\n## Keys\n\n###### Small print'),
      ('nested lists', '- one\n- two\n  - two a\n  - two b\n- three'),
      ('ordered lists count on', '1. first\n2. second\n3. third'),
      ('a list that starts at 5', '5. fifth\n6. sixth'),
      ('ordered inside bullets', '- step\n  1. sub one\n  2. sub two'),
      ('a loose list', '- one\n\n- two'),
      ('a quote', '> Never commit this.\n>\n> Really.'),
      (
        'fenced code',
        '```bash\nexport KEY=…\ncurl -H "Authorization: \$KEY"\n```',
      ),
      ('tilde fences', '~~~\ncode\n~~~'),
      ('a rule', 'Above\n\n---\n\nBelow'),
      ('a star rule', '* * *'),
      (
        'inline Markdown stays as typed',
        'Use **prod** keys, `kid` from _the_ [console](https://x.example).',
      ),
      ('an empty heading', '#'),
      ('an empty list item', '- a\n-'),
    ]) {
      test(name, () => expect(roundTrip(markdown), markdown));
    }
  });

  group('what the editor doesn’t model is kept verbatim', () {
    for (final (name, markdown) in [
      ('a table', '| Key | Value |\n|---|---|\n| a | b |'),
      ('HTML', '<details>\n<summary>Old keys</summary>\n</details>'),
      ('a setext heading', 'Title\n====='),
      ('a setext heading 2', 'Title\n-----'),
      ('indented code', '    code line\n    second'),
      ('a link reference', '[docs]: https://x.example'),
      ('a closed heading', '# Title #'),
      ('a quote holding a list', '> - one\n> - two'),
    ]) {
      test(name, () {
        expect(kinds(markdown), [NoteBlockKind.raw]);
        expect(roundTrip(markdown), markdown);
      });
    }

    test('around blocks it does model', () {
      const markdown = '# Keys\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nAfter';
      expect(kinds(markdown), [
        NoteBlockKind.heading,
        NoteBlockKind.raw,
        NoteBlockKind.paragraph,
      ]);
      expect(roundTrip(markdown), markdown);
    });
  });

  group('parsing', () {
    test('blocks carry no syntax', () {
      final blocks = parseNoteBlocks(
        '## Keys\n\n- **prod**\n\n> quoted\n\n```js\nx()\n```',
      );
      expect(blocks.map((b) => b.text), ['Keys', '**prod**', 'quoted', 'x()']);
      expect(blocks[0].level, 2);
      expect(blocks[3].info, 'js');
    });

    test('nothing is one empty paragraph', () {
      final blocks = parseNoteBlocks('');
      expect(blocks, hasLength(1));
      expect(blocks.single.kind, NoteBlockKind.paragraph);
      expect(blocks.single.text, '');
    });

    test('a lazy line continues the list item', () {
      final blocks = parseNoteBlocks('- one\ncontinued\n- two');
      expect(blocks.map((b) => b.text), ['one\ncontinued', 'two']);
      expect(roundTrip('- one\ncontinued'), '- one\n  continued');
    });

    test('a list after a paragraph needs no blank line', () {
      expect(kinds('Steps:\n- one\n- two'), [
        NoteBlockKind.paragraph,
        NoteBlockKind.bullet,
        NoteBlockKind.bullet,
      ]);
    });

    test('an ordered list interrupts a paragraph only from 1', () {
      expect(kinds('Since\n2020. A year'), [NoteBlockKind.paragraph]);
      expect(kinds('Steps\n1. one'), [
        NoteBlockKind.paragraph,
        NoteBlockKind.ordered,
      ]);
    });

    test('an unclosed fence runs to the end, and gets its close', () {
      final blocks = parseNoteBlocks('```\nopen');
      expect(blocks.single.kind, NoteBlockKind.code);
      expect(serializeNoteBlocks(blocks), '```\nopen\n```');
    });

    test('Windows line breaks', () {
      expect(roundTrip('# A\r\n\r\nb'), '# A\n\nb');
    });
  });

  group('serializing what the editor made', () {
    test('a paragraph line that would start a block is escaped', () {
      final md = serializeNoteBlocks([
        NoteBlock.paragraph('Shopping\n- not a list\n# not a heading'),
      ]);
      expect(md, 'Shopping\n\\- not a list\n\\# not a heading');
      expect(kinds(md), [NoteBlockKind.paragraph]);
    });

    test('new numbered items count on from the first', () {
      final md = serializeNoteBlocks([
        NoteBlock(NoteBlockKind.ordered, text: 'a', number: 3, marker: '.'),
        NoteBlock(NoteBlockKind.ordered, text: 'b', number: 1, marker: '.'),
        NoteBlock(NoteBlockKind.ordered, text: 'c', number: 1, marker: '.'),
      ]);
      expect(md, '3. a\n4. b\n5. c');
    });

    test('nested items sit under their parent’s text', () {
      final md = serializeNoteBlocks([
        NoteBlock(NoteBlockKind.ordered, text: 'top', number: 10, marker: '.'),
        NoteBlock(NoteBlockKind.bullet, text: 'child', indent: 1),
        NoteBlock(NoteBlockKind.bullet, text: 'grandchild', indent: 2),
      ]);
      expect(md, '10. top\n    - child\n      - grandchild');
      expect(roundTrip(md), md);
    });

    test('a nesting level that skips one is pulled in', () {
      final md = serializeNoteBlocks([
        NoteBlock(NoteBlockKind.bullet, text: 'a'),
        NoteBlock(NoteBlockKind.bullet, text: 'b', indent: 3),
      ]);
      expect(md, '- a\n  - b');
    });

    test('a heading is one line', () {
      final md = serializeNoteBlocks([
        NoteBlock(NoteBlockKind.heading, text: 'two\nlines', level: 2),
      ]);
      expect(md, '## two lines');
    });

    test('code holding a fence gets a longer one', () {
      final md = serializeNoteBlocks([
        NoteBlock(NoteBlockKind.code, text: 'a\n```\nb'),
      ]);
      expect(md, '````\na\n```\nb\n````');
      expect(parseNoteBlocks(md).single.text, 'a\n```\nb');
    });
  });
}
