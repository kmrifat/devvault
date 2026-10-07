import 'dart:async';

import 'package:flutter/services.dart';

/// Reads and writes the system clipboard. Abstract so tests can watch it.
abstract interface class ClipboardAccess {
  Future<String?> read();
  Future<void> write(String text);
}

class SystemClipboard implements ClipboardAccess {
  const SystemClipboard();

  @override
  Future<String?> read() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  @override
  Future<void> write(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// Copies secrets to the clipboard and takes them off again.
///
/// After [clearAfter], and whenever [clearNow] is called (on lock and on
/// quit), the clipboard is emptied, but only if it still holds the secret
/// DevVault put there. Anything the user copied since is left alone.
class ClipboardGuard {
  ClipboardGuard({
    this.clipboard = const SystemClipboard(),
    this.clearAfter = const Duration(seconds: 30),
  });

  final ClipboardAccess clipboard;
  final Duration clearAfter;

  String? _copied;
  Timer? _timer;

  /// Whether a secret DevVault copied may still be on the clipboard.
  bool get isHoldingSecret => _copied != null;

  Future<void> copySecret(String value) async {
    await clipboard.write(value);
    _copied = value;
    _timer?.cancel();
    _timer = Timer(clearAfter, () => unawaited(clearNow()));
  }

  /// Empties the clipboard if it still holds the copied secret.
  Future<void> clearNow() async {
    _timer?.cancel();
    _timer = null;
    final copied = _copied;
    _copied = null;
    if (copied == null) return;
    if (await clipboard.read() == copied) await clipboard.write('');
  }

  void dispose() => _timer?.cancel();
}
