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

/// A clipboard that can mark a copy as a secret: kept off other devices and
/// out of clipboard previews, and expired by the system (P3-06).
abstract interface class SecretClipboardAccess implements ClipboardAccess {
  Future<void> writeSecret(String text, {required Duration expiresIn});
}

/// The phone clipboard through `packages/device_privacy`: on iOS the copy is
/// local-only (no Universal Clipboard) and expires after [expiresIn]; on
/// Android it's marked sensitive, so the clipboard preview hides it.
class ChannelSensitiveClipboard extends SystemClipboard
    implements SecretClipboardAccess {
  const ChannelSensitiveClipboard();

  static const _channel = MethodChannel('devvault/privacy');

  @override
  Future<void> writeSecret(String text, {required Duration expiresIn}) async {
    try {
      await _channel.invokeMethod<void>('copySensitive', {
        'text': text,
        'expiresInSeconds': expiresIn.inSeconds,
      });
    } on MissingPluginException {
      await write(text);
    }
  }
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

  /// Applies to the next copy; a clear already scheduled keeps its time.
  Duration clearAfter;

  String? _copied;
  Timer? _timer;

  /// Whether a secret DevVault copied may still be on the clipboard.
  bool get isHoldingSecret => _copied != null;

  Future<void> copySecret(String value) async {
    final clipboard = this.clipboard;
    if (clipboard is SecretClipboardAccess) {
      await clipboard.writeSecret(value, expiresIn: clearAfter);
    } else {
      await clipboard.write(value);
    }
    _copied = value;
    _timer?.cancel();
    _timer = Timer(clearAfter, () => unawaited(clearNow()));
  }

  /// Takes a secret the user copied elsewhere to paste it here (B4b): reads
  /// the clipboard and empties it, so the secret doesn't stay there. Null
  /// when it holds no text.
  Future<String?> takePasted() async {
    final text = await clipboard.read();
    if (text == null || text.isEmpty) return null;
    await clipboard.write('');
    return text;
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
