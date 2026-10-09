import 'dart:io';

/// Opens a web page in the default browser. Abstract so tests don't open
/// browsers.
abstract interface class LinkOpener {
  Future<void> open(Uri link);
}

/// Hands the link to the OS the way `SystemFolderRevealer` hands it a
/// folder (desktop only).
class SystemLinkOpener implements LinkOpener {
  const SystemLinkOpener();

  @override
  Future<void> open(Uri link) async {
    final (command, args) = Platform.isMacOS
        ? ('open', [link.toString()])
        : Platform.isWindows
        ? ('explorer', [link.toString()])
        : ('xdg-open', [link.toString()]);
    await Process.run(command, args);
  }
}
