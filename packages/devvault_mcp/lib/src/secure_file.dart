import 'dart:io';
import 'dart:math';

import 'package:agent_bridge/agent_bridge.dart' show currentUserSid;

/// Creates [dir] if needed, readable only by this user (0700; on Windows a
/// DACL granting this user alone).
Future<void> ensurePrivateDir(Directory dir) async {
  if (await dir.exists()) return;
  await dir.create(recursive: true);
  await _ownerOnly(dir.path, directory: true);
}

/// Writes [bytes] to [file] so that no other user can ever read them: a
/// temp file next to it is made 0600 (on Windows: this user alone) *before*
/// anything is written, then renamed over [file], which keeps that. Replaces
/// [file] if it exists.
Future<void> writePrivateFile(File file, List<int> bytes) async {
  final random = Random.secure().nextInt(1 << 32).toRadixString(16);
  final temp = File('${file.parent.path}/.devvault-$random.tmp');
  await temp.create(exclusive: true);
  try {
    await _ownerOnly(temp.path);
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  } on Object {
    if (await temp.exists()) await temp.delete();
    rethrow;
  }
}

/// 0600 or 0700 on macOS and Linux. On Windows, `icacls` drops what [path]
/// inherits and grants this user alone (folders: to what's inside too).
Future<void> _ownerOnly(String path, {bool directory = false}) async {
  final result = Platform.isWindows
      ? await Process.run('icacls', [
          path,
          '/inheritance:r',
          '/grant:r',
          '*${currentUserSid()}:${directory ? '(OI)(CI)F' : 'F'}',
        ])
      : await Process.run('chmod', [directory ? '700' : '600', path]);
  if (result.exitCode != 0) {
    throw FileSystemException('Could not set permissions', path);
  }
}
