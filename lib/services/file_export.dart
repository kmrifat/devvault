import 'dart:typed_data';

import 'package:vault_core/vault_core.dart';

import 'file_saver.dart';

/// How exporting one attachment ended.
enum ExportOutcome {
  /// The file was written where the user picked.
  saved,

  /// The user closed the save dialog; nothing was written.
  cancelled,

  /// The blob is missing, won't decrypt, or its bytes don't match the
  /// sha256 recorded at import; nothing was written.
  corrupt,

  /// The bytes checked out but the file couldn't be written (for example
  /// the folder isn't writable).
  failed,
}

/// Writes an attachment back out byte for byte (P1-19).
///
/// The decrypted bytes are hashed and compared with [Attachment.sha256]
/// (and [Attachment.size]) right before the save dialog opens, so a file
/// that doesn't match what was imported is never written. The bytes are
/// zeroed once the save returns.
class FileExport {
  const FileExport(this._saver);

  final FileSaver _saver;

  Future<ExportOutcome> export(Vault vault, Attachment attachment) async {
    final Uint8List bytes;
    try {
      bytes = await vault.readAttachment(attachment);
    } on AttachmentCorrupt {
      return ExportOutcome.corrupt;
    } on Object {
      // Locked meanwhile, or the disk failed. The error isn't passed on.
      return ExportOutcome.failed;
    }
    try {
      if (!matches(bytes, attachment)) return ExportOutcome.corrupt;
      final saved = await _saver.save(
        fileName: attachment.filename,
        bytes: bytes,
        mimeType: attachment.mime,
      );
      return saved ? ExportOutcome.saved : ExportOutcome.cancelled;
    } on Object {
      // Deliberately drops the error: it may describe the bytes or the path.
      return ExportOutcome.failed;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Whether [bytes] are exactly the file that was imported as [attachment].
  static bool matches(Uint8List bytes, Attachment attachment) =>
      bytes.length == attachment.size &&
      _hex(VaultCrypto.sha256(bytes)) == attachment.sha256;

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
