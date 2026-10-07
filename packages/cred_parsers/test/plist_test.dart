import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cred_parsers/src/plist.dart';
import 'package:test/test.dart';

String wrap(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n$body\n</plist>\n';

void main() {
  group('parseXmlPlist reads', () {
    test('every value type', () {
      final value = parseXmlPlist(
        wrap('''
<dict>
  <key>s</key><string>a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos; &#65;&#x42;</string>
  <key>empty</key><string/>
  <key>i</key><integer>-42</integer>
  <key>big</key><integer>9007199254740993</integer>
  <key>r</key><real>1.5e3</real>
  <key>t</key><true/>
  <key>f</key><false></false>
  <key>d</key><date>2026-10-07T09:00:00Z</date>
  <key>b</key><data>
    AAEC
    /w==
  </data>
  <key>a</key><array><string>x</string><integer>1</integer><array/></array>
  <key>nested</key><dict><key>k</key><dict/></dict>
</dict>'''),
      );
      expect(value, isA<Map<String, Object>>());
      final map = value as Map<String, Object>;
      expect(map.keys, [
        's',
        'empty',
        'i',
        'big',
        'r',
        't',
        'f',
        'd',
        'b',
        'a',
        'nested',
      ]);
      expect(map['s'], 'a & b <c> "d" \'e\' AB');
      expect(map['empty'], '');
      expect(map['i'], -42);
      expect(map['big'], 9007199254740993);
      expect(map['r'], 1500.0);
      expect(map['t'], isTrue);
      expect(map['f'], isFalse);
      expect(map['d'], DateTime.utc(2026, 10, 7, 9));
      expect((map['d'] as DateTime).isUtc, isTrue);
      expect(map['b'], Uint8List.fromList([0, 1, 2, 0xFF]));
      expect(map['a'], ['x', 1, <Object>[]]);
      expect(map['nested'], {'k': <String, Object>{}});
    });

    test('results are unmodifiable', () {
      final map = parseXmlPlist(
        wrap('<dict><key>a</key><array/></dict>'),
      ) as Map<String, Object>;
      expect(() => map['b'] = 1, throwsUnsupportedError);
      final list = parseXmlPlist(wrap('<array><true/></array>')) as List;
      expect(() => list.add(1), throwsUnsupportedError);
    });

    test('a root that is not a dict, comments and a BOM', () {
      expect(
        parseXmlPlist('﻿<plist><!-- hi --><string>x</string></plist>'),
        'x',
      );
      expect(parseXmlPlist('<plist version="1.0"><array/></plist>'), isEmpty);
    });

    test('CRLF line ends are normalised', () {
      expect(parseXmlPlist(wrap('<string>a\r\nb\rc</string>')), 'a\nb\nc');
    });

    test('the Firebase fixture', () {
      final map = parseXmlPlist(
        File('test/fixtures/GoogleService-Info.plist').readAsStringSync(),
      ) as Map<String, Object>;
      expect(map['BUNDLE_ID'], 'dev.devvault.test');
      expect(map['IS_GCM_ENABLED'], isTrue);
      expect(map['IS_ADS_ENABLED'], isFalse);
    });
  });

  group('parseXmlPlist rejects', () {
    const bad = {
      'empty input': '',
      'no plist element': '<dict/>',
      'two root values': '<plist><true/><false/></plist>',
      'no root value': '<plist></plist>',
      'unclosed plist': '<plist><true/>',
      'trailing content': '<plist><true/></plist>x',
      'unknown element': '<plist><foo/></plist>',
      'attribute on a value': '<plist><string a="1">x</string></plist>',
      'value without a key': '<plist><dict><string>x</string></dict></plist>',
      'key without a value': '<plist><dict><key>a</key></dict></plist>',
      'duplicate keys':
          '<plist><dict><key>a</key><true/><key>a</key><true/></dict></plist>',
      'mismatched close': '<plist><string>x</data></plist>',
      'markup in a string': '<plist><string>a<b/>c</string></plist>',
      'CDATA': '<plist><string><![CDATA[x]]></string></plist>',
      'unknown entity': '<plist><string>&nbsp;</string></plist>',
      'bare ampersand': '<plist><string>a & b</string></plist>',
      'NUL char ref': '<plist><string>&#0;</string></plist>',
      'surrogate char ref': '<plist><string>&#xD800;</string></plist>',
      'char ref out of range': '<plist><string>&#x110000;</string></plist>',
      'bad integer': '<plist><integer>1.0</integer></plist>',
      'hex integer': '<plist><integer>0x10</integer></plist>',
      'integer overflow':
          '<plist><integer>99999999999999999999</integer></plist>',
      'empty integer': '<plist><integer/></plist>',
      'bad real': '<plist><real>one</real></plist>',
      'bad date': '<plist><date>2026-10-07</date></plist>',
      'out-of-range date': '<plist><date>2026-13-01T00:00:00Z</date></plist>',
      'bad data': '<plist><data>!!!</data></plist>',
      'content in true': '<plist><true>yes</true></plist>',
      'DOCTYPE with an internal subset':
          '<!DOCTYPE plist [<!ENTITY x "y">]><plist><true/></plist>',
      'unterminated comment': '<plist><!-- <true/></plist>',
      'binary plist': 'bplist00\u0000\u0001',
    };
    for (final MapEntry(key: name, value: text) in bad.entries) {
      test(name, () {
        expect(() => parseXmlPlist(text), throwsFormatException);
      });
    }

    test('deep nesting', () {
      final deep = '${'<array>' * 10000}${'</array>' * 10000}';
      expect(
        () => parseXmlPlist('<plist>$deep</plist>'),
        throwsFormatException,
      );
    });

    test('errors never quote the input', () {
      const secret = 'hunter2-SECRET';
      for (final text in [
        '<plist><string>$secret&bogus;</string></plist>',
        '<plist><integer>$secret</integer></plist>',
        '<plist><$secret/></plist>',
        '<plist><dict><key>$secret</key><key>x</key></dict></plist>',
      ]) {
        try {
          parseXmlPlist(text);
          fail('should have thrown');
        } on FormatException catch (e) {
          expect(e.toString(), isNot(contains(secret)));
          expect(e.source, isNull);
        }
      }
    });
  });

  test('fuzzing only ever throws FormatException', () {
    final seed = File('test/fixtures/GoogleService-Info.plist')
        .readAsStringSync();
    final random = Random(0x9115);
    const alphabet = '<>/&;#x!-[]?="\' \n abcdefkeystringdicttrue0123';
    for (var i = 0; i < 3000; i++) {
      final chars = seed.split('');
      for (var n = 1 + random.nextInt(6); n > 0; n--) {
        final at = random.nextInt(chars.length);
        switch (random.nextInt(3)) {
          case 0:
            chars[at] = alphabet[random.nextInt(alphabet.length)];
          case 1:
            chars.removeAt(at);
          default:
            chars.insert(at, alphabet[random.nextInt(alphabet.length)]);
        }
      }
      var text = chars.join();
      if (random.nextBool()) {
        text = text.substring(0, random.nextInt(text.length + 1));
      }
      try {
        parseXmlPlist(text);
      } on FormatException {
        // Expected for most mutations.
      }
    }
  });
}
