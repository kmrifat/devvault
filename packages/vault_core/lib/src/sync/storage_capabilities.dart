import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'storage_backend.dart';

/// Which compare-and-swap operations a store really enforces, as found by
/// probing it (`vault_s3`'s `S3Backend.probe`). Sync is only race-free
/// when all three hold; otherwise [VerifyingBackend] checks before it
/// writes, and the app shows [warnings].
@immutable
class StorageCapabilities {
  const StorageCapabilities({
    required this.conditionalCreate,
    required this.conditionalUpdate,
    required this.conditionalDelete,
  });

  /// What the in-repo backends (memory, folder) guarantee.
  static const full = StorageCapabilities(
    conditionalCreate: true,
    conditionalUpdate: true,
    conditionalDelete: true,
  );

  /// `PUT` with `If-None-Match: *` refuses to overwrite.
  final bool conditionalCreate;

  /// `PUT` with `If-Match` refuses a stale etag and accepts the current one.
  final bool conditionalUpdate;

  /// `DELETE` with `If-Match` refuses a stale etag.
  final bool conditionalDelete;

  bool get isRaceFree =>
      conditionalCreate && conditionalUpdate && conditionalDelete;

  /// What the user should know, one sentence per gap.
  List<String> get warnings => [
    if (!conditionalCreate || !conditionalUpdate)
      'This storage doesn’t enforce conditional writes. DevVault checks '
          'before every write, but two devices saving at the same moment '
          'could still overwrite each other.',
    if (!conditionalDelete)
      'This storage ignores conditions on deletes. DevVault checks first, '
          'but a change made on another device at the same moment could be '
          'removed.',
  ];

  Map<String, Object?> toJson() => {
    'conditional_create': conditionalCreate,
    'conditional_update': conditionalUpdate,
    'conditional_delete': conditionalDelete,
  };

  factory StorageCapabilities.fromJson(Map<String, Object?> json) =>
      StorageCapabilities(
        conditionalCreate: json['conditional_create'] == true,
        conditionalUpdate: json['conditional_update'] == true,
        conditionalDelete: json['conditional_delete'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is StorageCapabilities &&
      other.conditionalCreate == conditionalCreate &&
      other.conditionalUpdate == conditionalUpdate &&
      other.conditionalDelete == conditionalDelete;

  @override
  int get hashCode =>
      Object.hash(conditionalCreate, conditionalUpdate, conditionalDelete);

  @override
  String toString() =>
      'StorageCapabilities(create: $conditionalCreate, '
      'update: $conditionalUpdate, delete: $conditionalDelete)';
}

/// Wraps a store that doesn't enforce some conditions: before each such
/// write it reads the current state and refuses if the condition fails,
/// then writes unconditionally and reads back to confirm its bytes landed.
///
/// This narrows races to the gap between the check and the write; it can't
/// close it. Conditions the store does enforce are passed straight through.
class VerifyingBackend implements StorageBackend {
  VerifyingBackend(this.inner, this.capabilities);

  final StorageBackend inner;
  final StorageCapabilities capabilities;

  @override
  Future<List<RemoteObject>> list(String prefix) => inner.list(prefix);

  @override
  Future<RemoteBody?> get(String key) => inner.get(key);

  @override
  Future<String> put(
    String key,
    Uint8List bytes, {
    WriteCondition condition = const WriteCondition.always(),
  }) async {
    final emulate = switch (condition) {
      WriteAlways() => false,
      WriteIfAbsent() => !capabilities.conditionalCreate,
      WriteIfMatch() => !capabilities.conditionalUpdate,
    };
    if (!emulate) return inner.put(key, bytes, condition: condition);

    final current = await inner.get(key);
    switch (condition) {
      case WriteIfAbsent() when current != null:
        throw PreconditionFailed('$key already exists');
      case WriteIfMatch(:final etag) when current?.etag != etag:
        throw PreconditionFailed('$key changed');
      default:
        break;
    }
    final etag = await inner.put(key, bytes);
    final landed = await inner.get(key);
    if (landed == null || !_same(landed.bytes, bytes)) {
      throw PreconditionFailed('$key was overwritten while saving');
    }
    return etag;
  }

  @override
  Future<void> delete(String key, {String? ifMatch}) =>
      // S3Backend already checks the etag before a conditional delete; the
      // fakes enforce it. Nothing more can be done without a lock.
      inner.delete(key, ifMatch: ifMatch);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
