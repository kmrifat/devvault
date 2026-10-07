import 'package:file_picker/file_picker.dart';

import '../features/import/import_draft.dart';

/// Lets the user choose files to import (an open dialog on desktop, the
/// system file browser on phones). Abstract so tests don't open dialogs.
abstract interface class FileOpener {
  /// The chosen files with their bytes, or an empty list if cancelled.
  Future<List<PickedFile>> pick();
}

class SystemFileOpener implements FileOpener {
  const SystemFileOpener();

  @override
  Future<List<PickedFile>> pick() async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Import files');
    return [
      for (final file in files)
        PickedFile(name: file.name, bytes: await file.readAsBytes()),
    ];
  }
}
