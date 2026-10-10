import 'package:flutter/services.dart';

import 'updates.dart';

/// The OS's updater behind the `devvault/updater` channel: Sparkle on
/// macOS (macos/Runner/AppUpdater.swift, P6-04).
class ChannelUpdateInstaller implements UpdateInstaller {
  const ChannelUpdateInstaller._();

  static const _channel = MethodChannel('devvault/updater');

  /// The installer when this build can update itself, else null: no
  /// channel (Linux, the Windows zip), or a build without the update key.
  static Future<UpdateInstaller?> load() async {
    try {
      final available = await _channel.invokeMethod<bool>('isAvailable');
      return available == true ? const ChannelUpdateInstaller._() : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> install(Release release) async {
    try {
      await _channel.invokeMethod<void>('install');
    } on PlatformException catch (e) {
      throw UpdateCheckFailed(e.message ?? 'The update couldn’t start.');
    }
  }
}
