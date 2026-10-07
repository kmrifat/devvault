import 'dart:convert';
import 'dart:typed_data';

import 'storage_backend.dart';

/// The behaviour sync relies on, checked against a real [backend]: reads,
/// listings, conditional writes and deletes, and key validation.
///
/// Returns one line per failed check (empty when the backend conforms), so
/// any test framework, or a "Test connection" button, can use it. Works
/// under [prefix] and removes what it wrote. [listCount] objects are listed
/// at once; use more than 1,000 against S3 to cover paging.
Future<List<String>> checkStorageConformance(
  StorageBackend backend, {
  String prefix = 'conformance',
  int listCount = 25,
}) async {
  final failures = <String>[];
  final written = <String>{};
  String key(String name) => '$prefix/$name';
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  Future<String> put(
    String k,
    Uint8List b, [
    WriteCondition condition = const WriteCondition.always(),
  ]) async {
    final etag = await backend.put(k, b, condition: condition);
    written.add(k);
    return etag;
  }

  Future<void> check(String name, Future<void> Function() body) async {
    try {
      await body();
    } on _Failure catch (e) {
      failures.add('$name: ${e.message}');
    } on Object catch (e) {
      failures.add('$name: threw $e');
    }
  }

  void expect(bool condition, String what) {
    if (!condition) throw _Failure(what);
  }

  Future<void> expectThrows<T>(
    Future<void> Function() body,
    String what,
  ) async {
    try {
      await body();
    } on Object catch (e) {
      if (e is T) return;
      throw _Failure('$what: threw $e instead of $T');
    }
    throw _Failure('$what: did not throw $T');
  }

  bool same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  await check('a missing key reads as null', () async {
    expect(await backend.get(key('missing')) == null, 'get returned an object');
  });

  await check('bytes and etag round-trip', () async {
    final all = Uint8List.fromList(List.generate(256, (i) => i));
    final etag = await put(key('binary'), all);
    final body = await backend.get(key('binary'));
    expect(body != null, 'object missing after put');
    expect(same(body!.bytes, all), 'bytes changed');
    expect(body.etag == etag, 'etag from get differs from put');
    final empty = await put(key('empty'), Uint8List(0));
    final read = await backend.get(key('empty'));
    expect(read != null && read.bytes.isEmpty, 'empty object not stored');
    expect(read!.etag == empty, 'empty object etag differs');
  });

  await check('overwriting changes the etag', () async {
    final first = await put(key('overwrite'), bytes('one'));
    final second = await put(key('overwrite'), bytes('two'));
    expect(first != second, 'etag unchanged after new bytes');
    final body = await backend.get(key('overwrite'));
    expect(utf8.decode(body!.bytes) == 'two', 'old bytes returned');
  });

  await check('list returns keys under the prefix, sorted', () async {
    final names = [
      for (var i = 0; i < listCount; i++)
        'list/${i.toString().padLeft(5, '0')}.enc',
    ];
    final etags = <String, String>{};
    for (final name in names.reversed) {
      etags[key(name)] = await put(key(name), bytes(name));
    }
    await put(key('listed-not/x.enc'), bytes('outside'));
    final listed = await backend.list(key('list/'));
    expect(
      listed.map((o) => o.key).join(',') == names.map(key).join(','),
      'expected ${names.length} sorted keys, got ${listed.length}',
    );
    for (final object in listed) {
      expect(
        object.etag == etags[object.key],
        'etag differs for ${object.key}',
      );
      expect(
        object.size ==
            utf8.encode(object.key.substring(prefix.length + 1)).length,
        'size wrong for ${object.key}',
      );
    }
  });

  await check('put if absent', () async {
    await put(key('absent'), bytes('first'), const WriteCondition.ifAbsent());
    await expectThrows<PreconditionFailed>(
      () =>
          put(key('absent'), bytes('second'), const WriteCondition.ifAbsent()),
      'second create',
    );
    final body = await backend.get(key('absent'));
    expect(utf8.decode(body!.bytes) == 'first', 'losing write landed');
  });

  await check('put if match', () async {
    final etag = await put(key('match'), bytes('v1'));
    final next = await put(
      key('match'),
      bytes('v2'),
      WriteCondition.ifMatch(etag),
    );
    await expectThrows<PreconditionFailed>(
      () => put(key('match'), bytes('stale'), WriteCondition.ifMatch(etag)),
      'write at a stale etag',
    );
    final body = await backend.get(key('match'));
    expect(utf8.decode(body!.bytes) == 'v2', 'stale write landed');
    expect(body.etag == next, 'etag moved without a write');
    await expectThrows<PreconditionFailed>(
      () => put(key('match-missing'), bytes('x'), WriteCondition.ifMatch(etag)),
      'if-match on a missing key',
    );
  });

  await check('delete', () async {
    final etag = await put(key('delete'), bytes('bye'));
    await expectThrows<PreconditionFailed>(
      () => backend.delete(key('delete'), ifMatch: '"not-the-etag"'),
      'delete at a stale etag',
    );
    expect(await backend.get(key('delete')) != null, 'stale delete removed it');
    await backend.delete(key('delete'), ifMatch: etag);
    expect(await backend.get(key('delete')) == null, 'still there');
    await backend.delete(key('delete')); // already gone: fine
  });

  await check('invalid keys are refused before any request', () async {
    for (final bad in [
      '',
      '/abs.enc',
      '../escape.enc',
      'a//b',
      'a/./b',
      'sp ace',
    ]) {
      await expectThrows<ArgumentError>(
        () => backend.put(bad, bytes('x')),
        'put "$bad"',
      );
      await expectThrows<ArgumentError>(() => backend.get(bad), 'get "$bad"');
    }
  });

  for (final k in written) {
    try {
      await backend.delete(k);
    } on Object {
      // Best effort cleanup.
    }
  }
  return failures;
}

class _Failure implements Exception {
  _Failure(this.message);
  final String message;
}
