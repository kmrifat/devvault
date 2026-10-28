import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import 'settings_layout.dart';

/// Opens Settings on [pane]: its own window on macOS (⌘,), the Settings
/// page in the main window elsewhere.
void openSettings(
  BuildContext context, [
  SettingsPane pane = SettingsPane.general,
]) {
  final window = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(settingsWindowProvider);
  if (window == null) {
    context.go(pane.route);
  } else {
    unawaited(window.open(pane));
  }
}
