import 'package:flutter/services.dart';

import 'updates.dart';

/// Where Windows' installer finds the latest published release
/// (ADR-0007 §4, §6). Windows fetches it, not the app. CI's update test
/// builds with `--dart-define=DEVVAULT_UPDATE_FEED=<a local copy>`.
const appInstallerFeed = String.fromEnvironment(
  'DEVVAULT_UPDATE_FEED',
  defaultValue:
      'https://github.com/kmrifat/devvault/releases/latest/download/'
      'DevVault.appinstaller',
);

/// The OS's updater behind the `devvault/updater` channel: Sparkle on
/// macOS (macos/Runner/AppUpdater.swift, P6-04), Windows' package
/// installer for the MSIX (windows/runner/app_updater.cpp, P6-05).
class ChannelUpdateInstaller implements UpdateInstaller {
  const ChannelUpdateInstaller._();

  static const _channel = MethodChannel('devvault/updater');

  /// The installer when this build can update itself, else null: no
  /// channel (Linux), the Windows zip, or a Mac build without the update
  /// key.
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
      // Sparkle reads its feed from Info.plist; Windows needs it here.
      await _channel.invokeMethod<void>('install', {'feed': appInstallerFeed});
    } on PlatformException catch (e) {
      throw UpdateCheckFailed(e.message ?? 'The update couldn’t start.');
    }
  }
}
