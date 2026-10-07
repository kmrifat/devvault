import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/storage_conformance.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  test('MemoryBackend conforms', () async {
    expect(await checkStorageConformance(MemoryBackend()), isEmpty);
  });

  test('LocalDirBackend conforms', () async {
    final dir = Directory.systemTemp.createTempSync('devvault_storage_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final backend = LocalDirBackend(Directory('${dir.path}/bucket'));
    expect(await checkStorageConformance(backend, listCount: 40), isEmpty);
    // Cleanup leaves nothing behind but empty folders.
    expect(await backend.list(''), isEmpty);
  });

  test('the suite catches a backend that ignores conditions', () async {
    final failures = await checkStorageConformance(_Careless());
    expect(failures.join('\n'), contains('put if absent'));
    expect(failures.join('\n'), contains('put if match'));
  });

  group('MemoryBackend', () {
    test('injects faults once, on the chosen key', () async {
      final backend = MemoryBackend()
        ..failNext(
          StorageOp.put,
          const StorageUnavailable('offline'),
          key: 'v/items/a.enc',
        );
      await backend.put('v/items/b.enc', Uint8List(1));
      await expectLater(
        backend.put('v/items/a.enc', Uint8List(1)),
        throwsA(isA<StorageUnavailable>()),
      );
      await backend.put('v/items/a.enc', Uint8List(1));
      expect(backend.log, [
        'put v/items/b.enc',
        'put v/items/a.enc',
        'put v/items/a.enc',
      ]);
      expect(backend.keys, ['v/items/a.enc', 'v/items/b.enc']);
    });

    test('same bytes written twice get a new etag', () async {
      final backend = MemoryBackend();
      final a = await backend.put('k', Uint8List(1));
      final b = await backend.put('k', Uint8List(1));
      expect(a, isNot(b));
    });
  });

  group('LocalDirBackend', () {
    test('keeps files where the key says and never escapes its root', () async {
      final dir = Directory.systemTemp.createTempSync('devvault_storage_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final backend = LocalDirBackend(Directory('${dir.path}/bucket'));
      await backend.put('v1/items/x.enc', Uint8List.fromList(utf8.encode('x')));
      expect(File('${dir.path}/bucket/v1/items/x.enc').readAsStringSync(), 'x');
      expect(
        () => backend.put('../outside.enc', Uint8List(1)),
        throwsArgumentError,
      );
      expect(File('${dir.path}/outside.enc').existsSync(), isFalse);
    });

    test('concurrent conditional creates: exactly one wins', () async {
      final dir = Directory.systemTemp.createTempSync('devvault_storage_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final backend = LocalDirBackend(dir);
      final results = await Future.wait([
        for (var i = 0; i < 10; i++)
          backend
              .put(
                'race.enc',
                Uint8List.fromList([i]),
                condition: const WriteCondition.ifAbsent(),
              )
              .then((_) => true, onError: (Object e) => false),
      ]);
      expect(results.where((won) => won), hasLength(1));
    });
  });

  test('errors say whether a retry can help, without data', () {
    expect(const StorageUnavailable('503').isRetryable, isTrue);
    expect(const PreconditionFailed('k changed').isRetryable, isFalse);
    expect(const StorageAccessDenied('403').toString(), contains('403'));
    expect(
      RemoteBody(Uint8List.fromList(utf8.encode('secret')), '"e"').toString(),
      isNot(contains('secret')),
    );
  });
}

/// Writes whatever it's given: the suite must notice.
class _Careless extends MemoryBackend {
  @override
  Future<String> put(
    String key,
    Uint8List bytes, {
    WriteCondition condition = const WriteCondition.always(),
  }) => super.put(key, bytes);
}
