import 'dart:io';

/// Shows a folder in the system file manager. Abstract so tests don't
/// open windows.
abstract interface class FolderRevealer {
  /// Whether this platform can show folders (desktop only).
  bool get isSupported;

  Future<void> reveal(Directory folder);
}

class SystemFolderRevealer implements FolderRevealer {
  const SystemFolderRevealer();

  @override
  bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Future<void> reveal(Directory folder) async {
    final (command, args) = Platform.isMacOS
        ? ('open', [folder.path])
        : Platform.isWindows
        ? ('explorer', [folder.path])
        : ('xdg-open', [folder.path]);
    await Process.run(command, args);
  }
}
