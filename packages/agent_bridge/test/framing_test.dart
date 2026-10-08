import 'dart:convert';

import 'package:agent_bridge/agent_bridge.dart';
import 'package:test/test.dart';

void main() {
  Stream<List<int>> chunks(List<String> parts) =>
      Stream.fromIterable([for (final p in parts) utf8.encode(p)]);

  test('one message per line, across and within chunks', () async {
    final messages = await decodeLines(
      chunks(['{"a":1}\n{"b"', ':2}\n\n{"c":"ü"}\n']),
    ).toList();
    expect(messages, [
      {'a': 1},
      {'b': 2},
      {'c': 'ü'},
    ]);
  });

  test('encodeLine round-trips and ends in one newline', () async {
    final line = encodeLine({'id': 1, 'text': 'two\nlines'});
    expect(line.where((b) => b == 0x0a), hasLength(1));
    expect(await decodeLines(Stream.value(line)).single, {
      'id': 1,
      'text': 'two\nlines',
    });
  });

  test('a line over the limit fails, even before its newline', () {
    expect(
      decodeLines(chunks(['x' * 20]), maxLine: 10).toList(),
      throwsA(isA<BridgeException>()),
    );
    expect(
      decodeLines(chunks(['{"a":"${'x' * 20}"}\n']), maxLine: 10).toList(),
      throwsA(isA<BridgeException>()),
    );
  });

  test('a line that is not a JSON object fails', () {
    expect(
      decodeLines(chunks(['[1]\n'])).toList(),
      throwsA(
        isA<BridgeException>().having(
          (e) => e.code,
          'code',
          BridgeError.badRequest,
        ),
      ),
    );
    expect(
      decodeLines(chunks(['nope\n'])).toList(),
      throwsA(isA<BridgeException>()),
    );
  });
}
