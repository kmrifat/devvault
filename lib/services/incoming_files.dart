import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Files another app handed to DevVault: "Open in DevVault" from Files,
/// Mail or AirDrop on iOS, a VIEW or SEND intent on Android (P3-03).
///
/// The native side copies each file into a fresh temporary folder and
/// keeps the paths until Dart [take]s them, so nothing arrives twice and
/// nothing is lost while the vault is locked.
abstract interface class IncomingFiles {
  /// Paths waiting to be imported; the native side forgets them.
  Future<List<String>> take();

  /// Fires when new files are waiting.
  Stream<void> get available;
}

class ChannelIncomingFiles implements IncomingFiles {
  ChannelIncomingFiles() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'available') _available.add(null);
    });
  }

  static const _channel = MethodChannel('devvault/incoming_files');
  final _available = StreamController<void>.broadcast();

  @override
  Stream<void> get available => _available.stream;

  @override
  Future<List<String>> take() async {
    try {
      return await _channel.invokeListMethod<String>('take') ?? const [];
    } on MissingPluginException {
      return const []; // desktop: files arrive by drag and drop instead
    }
  }
}

/// Nothing ever arrives (desktop and tests).
class NoIncomingFiles implements IncomingFiles {
  const NoIncomingFiles();

  @override
  Future<List<String>> take() async => const [];

  @override
  Stream<void> get available => const Stream.empty();
}

/// Reads a received file and removes the temporary copy (and its folder,
/// which the native side made for it alone).
Future<({String name, Uint8List bytes})?> readIncoming(String path) async {
  final file = File(path);
  try {
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    return (name: path.split(Platform.pathSeparator).last, bytes: bytes);
  } finally {
    final dir = file.parent;
    if (dir.existsSync() &&
        dir.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('devvault-incoming-')) {
      await dir.delete(recursive: true);
    } else if (file.existsSync()) {
      await file.delete();
    }
  }
}
