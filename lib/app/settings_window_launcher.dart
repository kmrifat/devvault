import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../features/settings/settings_layout.dart';
import 'settings_bridge.dart';

/// Opens Settings in its own macOS window (⌘,): one window at most, a
/// second engine that `main()` starts as [SettingsWindowArguments.window]
/// (desktop_multi_window), kept up to date by [host].
class SettingsWindows {
  SettingsWindows(this.host);

  final SettingsBridgeHost host;

  /// The window being made, so a second ⌘, doesn't make another.
  Future<void>? _opening;

  /// Shows the Settings window on [pane], making it if it isn't open. It
  /// shows itself once its first frame is drawn.
  Future<void> open([SettingsPane pane = SettingsPane.general]) =>
      _opening ??= _open(pane).whenComplete(() => _opening = null);

  Future<void> _open(SettingsPane pane) async {
    final open = await _find();
    if (open != null) {
      await host.show(pane.name);
      await open.show();
      return;
    }
    await WindowController.create(
      WindowConfiguration(
        arguments: SettingsWindowArguments(pane).encode(),
        hiddenAtLaunch: true,
      ),
    );
  }

  /// Closes the Settings window, if it's open.
  Future<void> close() => host.close();

  static Future<WindowController?> _find() async {
    for (final window in await WindowController.getAll()) {
      if (SettingsWindowArguments.decode(window.arguments) != null) {
        return window;
      }
    }
    return null;
  }
}

/// What the Settings window's engine is started with.
class SettingsWindowArguments {
  const SettingsWindowArguments(this.pane);

  static const window = 'settings';

  final SettingsPane pane;

  String encode() => jsonEncode({'window': window, 'pane': pane.name});

  /// Null for anything that isn't a Settings window's (the main window's
  /// are empty).
  static SettingsWindowArguments? decode(String arguments) {
    try {
      final json = jsonDecode(arguments);
      if (json is! Map || json['window'] != window) return null;
      return SettingsWindowArguments(
        SettingsPane.values.where((p) => p.name == json['pane']).firstOrNull ??
            SettingsPane.general,
      );
    } on FormatException {
      return null;
    }
  }
}
