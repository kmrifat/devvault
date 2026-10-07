import 'dart:io';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'file_saver.dart';

/// Opens the share sheet with one file and says whether the user picked
/// a destination. Abstract so tests don't open a sheet.
typedef ShareFile = Future<bool> Function(
  String path,
  String fileName,
  String mimeType,
);

/// Exports on phones (B3, P3-02): the file goes to the system share sheet
/// (Files, AirDrop, another app) instead of a save dialog.
///
/// The bytes are written to a fresh folder in the app's temporary
/// directory only for as long as the sheet is open, then overwritten with
/// zeros and deleted, whatever the user chose. [sweep] removes copies a
/// crash left behind.
class ShareSheetSaver implements FileSaver {
  ShareSheetSaver({ShareFile? share, this.tempRoot})
    : _share = share ?? _systemShare;

  final ShareFile _share;

  /// Where the short-lived copies go; the system temp folder by default.
  final Directory? tempRoot;

  static const _prefix = 'devvault-share-';

  static Future<bool> _systemShare(
    String path,
    String fileName,
    String mimeType,
  ) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType, name: fileName)],
      ),
    );
    // "unavailable": shared, but the platform can't say where to.
    return result.status != ShareResultStatus.dismissed;
  }

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    final dir = (tempRoot ?? Directory.systemTemp).createTempSync(_prefix);
    final file = File('${dir.path}/$fileName');
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await _share(file.path, fileName, mimeType);
    } finally {
      if (file.existsSync()) {
        await file.writeAsBytes(Uint8List(bytes.length), flush: true);
      }
      await dir.delete(recursive: true);
    }
  }

  /// Deletes share folders left by an earlier run that didn't finish.
  static void sweep([Directory? tempRoot]) {
    final root = tempRoot ?? Directory.systemTemp;
    if (!root.existsSync()) return;
    for (final entity in root.listSync()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is Directory && name.startsWith(_prefix)) {
        try {
          entity.deleteSync(recursive: true);
        } on FileSystemException {
          // In use or already gone: the next launch tries again.
        }
      }
    }
  }
}
