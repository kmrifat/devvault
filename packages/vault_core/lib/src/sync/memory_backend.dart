import 'dart:typed_data';

import 'storage_backend.dart';

/// The operations [MemoryBackend] can be told to fail.
enum StorageOp { list, get, put, delete }

/// A [StorageBackend] in memory, for tests of sync.
///
/// Etags are a per-backend counter (`"m1"`, `"m2"`, …), so two writes of the
/// same bytes still get different etags, as on S3 with multipart uploads.
/// [failNext] injects errors; [log] records every call (keys only).
class MemoryBackend implements StorageBackend {
  final _objects = <String, RemoteBody>{};
  final _faults = <({StorageOp op, String? key, StorageException error})>[];
  int _version = 0;

  /// `op key` for every call, in order (e.g. `put alpha/vault.json`).
  final List<String> log = [];

  /// Makes the next [op] (on [key], if given) throw [error] instead.
  void failNext(StorageOp op, StorageException error, {String? key}) =>
      _faults.add((op: op, key: key, error: error));

  /// The stored keys, sorted.
  List<String> get keys => _objects.keys.toList()..sort();

  void _call(StorageOp op, String key) {
    log.add('${op.name} $key');
    final index = _faults.indexWhere(
      (f) => f.op == op && (f.key == null || f.key == key),
    );
    if (index >= 0) throw _faults.removeAt(index).error;
  }

  @override
  Future<List<RemoteObject>> list(String prefix) async {
    StorageKeys.checkPrefix(prefix);
    _call(StorageOp.list, prefix);
    return [
      for (final key in keys)
        if (key.startsWith(prefix))
          RemoteObject(
            key: key,
            etag: _objects[key]!.etag,
            size: _objects[key]!.bytes.length,
          ),
    ];
  }

  @override
  Future<RemoteBody?> get(String key) async {
    StorageKeys.check(key);
    _call(StorageOp.get, key);
    final body = _objects[key];
    return body == null
        ? null
        : RemoteBody(Uint8List.fromList(body.bytes), body.etag);
  }

  @override
  Future<String> put(
    String key,
    Uint8List bytes, {
    WriteCondition condition = const WriteCondition.always(),
  }) async {
    StorageKeys.check(key);
    _call(StorageOp.put, key);
    final current = _objects[key];
    switch (condition) {
      case WriteAlways():
        break;
      case WriteIfAbsent():
        if (current != null) throw PreconditionFailed('$key already exists');
      case WriteIfMatch(:final etag):
        if (current?.etag != etag) throw PreconditionFailed('$key changed');
    }
    final etag = '"m${++_version}"';
    _objects[key] = RemoteBody(Uint8List.fromList(bytes), etag);
    return etag;
  }

  @override
  Future<void> delete(String key, {String? ifMatch}) async {
    StorageKeys.check(key);
    _call(StorageOp.delete, key);
    if (ifMatch != null && _objects[key]?.etag != ifMatch) {
      throw PreconditionFailed('$key changed');
    }
    _objects.remove(key);
  }
}
