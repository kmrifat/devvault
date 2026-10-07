import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../format/envelope.dart';
import '../format/vault_header.dart';

/// One vault on local disk, in the SPEC §3 layout:
///
/// ```
/// <root>/vault.json
/// <root>/items/<id>.enc   apps/   blobs/   tombstones/
/// ```
///
/// Every write is atomic: the bytes go to a temporary file in the same
/// folder, are flushed to disk, and the file is renamed over the target. A
/// reader sees the old object or the new one, never part of one.
class VaultStore {
  VaultStore(
    this.root, {
    @visibleForTesting this.onWrite,
    @visibleForTesting this.beforeRename,
  });

  /// The `<vault_id>/` folder.
  final Directory root;

  /// Called with the store-relative path of every completed write or
  /// delete (`vault.json`, `items/<id>.enc`, …). Tests use it to prove what
  /// an operation touched.
  final void Function(String path)? onWrite;

  /// Called after the temporary file is written and before it replaces the
  /// target. Tests throw from it to simulate a crash mid-write.
  final void Function(File temporary)? beforeRename;

  static const String _temporarySuffix = '.tmp';
  static final Random _random = Random.secure();

  File get _headerFile => File(_join(root.path, VaultHeader.fileName));

  bool get exists => _headerFile.existsSync();

  /// Creates the folders and removes temporary files left by a crash.
  Future<void> open() async {
    for (final type in _folderTypes) {
      await Directory(_join(root.path, type.folder!)).create(recursive: true);
    }
    await for (final entity in root.list(recursive: true)) {
      if (entity is File && entity.path.endsWith(_temporarySuffix)) {
        await entity.delete();
      }
    }
  }

  Future<VaultHeader> readHeader() async =>
      VaultHeader.parse(await _headerFile.readAsString());

  /// [readHeader] without awaiting; for code that has to stay synchronous.
  VaultHeader readHeaderSync() =>
      VaultHeader.parse(_headerFile.readAsStringSync());

  Future<void> writeHeader(VaultHeader header) => _writeAtomically(
    _headerFile,
    utf8.encode(header.toJsonString()),
    VaultHeader.fileName,
  );

  /// Device-local rotation journal. It sits next to the `<vault_id>/`
  /// folder, not inside it, so it is never synced (SPEC §3).
  File get _journalFile => File('${root.path}.rotation');

  Future<Uint8List?> readJournal() async =>
      await _journalFile.exists() ? _journalFile.readAsBytes() : null;

  Future<void> writeJournal(Uint8List bytes) =>
      _writeAtomically(_journalFile, bytes, '../rotation journal');

  Future<void> deleteJournal() async {
    if (await _journalFile.exists()) {
      await _journalFile.delete();
      onWrite?.call('-../rotation journal');
    }
  }

  /// The encrypted object at [type]/[id], or `null` if there is none.
  Future<Uint8List?> read(ObjectType type, String id) async {
    final file = _objectFile(type, id);
    return await file.exists() ? file.readAsBytes() : null;
  }

  /// Writes [envelope] to [type]/[id], replacing what was there.
  ///
  /// Blobs are immutable (SPEC §3): writing a blob id that already exists
  /// throws [BlobExists].
  Future<void> write(ObjectType type, String id, Uint8List envelope) async {
    final file = _objectFile(type, id);
    if (type == ObjectType.blob && await file.exists()) {
      throw BlobExists(id);
    }
    await _writeAtomically(file, envelope, _relative(type, id));
  }

  Future<void> delete(ObjectType type, String id) async {
    final file = _objectFile(type, id);
    if (await file.exists()) {
      await file.delete();
      onWrite?.call('-${_relative(type, id)}');
    }
  }

  /// Ids of every object of [type]. Files that aren't `<uuid>.enc`
  /// (temporary files, `.DS_Store`, …) are ignored.
  Future<List<String>> list(ObjectType type) async {
    final dir = Directory(_join(root.path, _folder(type)));
    if (!await dir.exists()) return const [];
    return [
      await for (final entity in dir.list())
        if (entity is File) ?_idFromFileName(_baseName(entity.path)),
    ]..sort();
  }

  static String? _idFromFileName(String name) {
    if (!name.endsWith('.enc')) return null;
    final id = name.substring(0, name.length - 4);
    return isCanonicalUuid(id) ? id : null;
  }

  Future<void> _writeAtomically(
    File target,
    Uint8List bytes,
    String relativePath,
  ) async {
    final temporary = File(
      '${target.path}.${_random.nextInt(1 << 32).toRadixString(16)}'
      '$_temporarySuffix',
    );
    try {
      final handle = await temporary.open(mode: FileMode.writeOnly);
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }
      beforeRename?.call(temporary);
      await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    onWrite?.call(relativePath);
  }

  File _objectFile(ObjectType type, String id) {
    if (!isCanonicalUuid(id)) {
      throw ArgumentError.value(id, 'id', 'not a lowercase UUID');
    }
    return File(_join(root.path, _folder(type), '$id.enc'));
  }

  static String _folder(ObjectType type) =>
      type.folder ??
      (throw ArgumentError.value(type, 'type', 'lives in vault.json'));

  static String _relative(ObjectType type, String id) =>
      '${_folder(type)}/$id.enc';

  static final List<ObjectType> _folderTypes = [
    for (final type in ObjectType.values)
      if (type.folder != null) type,
  ];

  static String _join(String a, [String? b, String? c]) =>
      [a, ?b, ?c].join(Platform.pathSeparator);

  static String _baseName(String path) =>
      path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);
}

/// A blob with this id already exists. Blobs are written once; a changed
/// file gets a new blob id (SPEC §3).
class BlobExists implements Exception {
  const BlobExists(this.id);

  final String id;

  @override
  String toString() => 'BlobExists($id)';
}
