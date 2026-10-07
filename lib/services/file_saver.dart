import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Saves bytes to a place the user picks (a save dialog on desktop, the
/// system file browser on phones). Abstract so tests don't open dialogs.
abstract interface class FileSaver {
  /// Returns `false` if the user cancelled.
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  });
}

class SystemFileSaver implements FileSaver {
  const SystemFileSaver();

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async =>
      await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      ) !=
      null;
}
