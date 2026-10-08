import 'dart:io';
import 'dart:math';

/// Creates [dir] if needed, readable only by this user (0700).
Future<void> ensurePrivateDir(Directory dir) async {
  if (await dir.exists()) return;
  await dir.create(recursive: true);
  await _chmod('700', dir.path);
}

/// Writes [bytes] to [file] so that no other user can ever read them: a
/// temp file next to it is made 0600 *before* anything is written, then
/// renamed over [file]. Replaces [file] if it exists.
Future<void> writePrivateFile(File file, List<int> bytes) async {
  final random = Random.secure().nextInt(1 << 32).toRadixString(16);
  final temp = File('${file.parent.path}/.devvault-$random.tmp');
  await temp.create(exclusive: true);
  try {
    await _chmod('600', temp.path);
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  } on Object {
    if (await temp.exists()) await temp.delete();
    rethrow;
  }
}

Future<void> _chmod(String mode, String path) async {
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw FileSystemException('Could not set permissions', path);
  }
}
