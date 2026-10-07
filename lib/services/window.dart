import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../app/layout.dart';

/// Sets up the desktop window before the first frame: title, the default
/// size, and the minimum the three-pane layout (D03) needs. Does nothing on
/// phones.
Future<void> initWindow() async {
  if (kIsWeb || AppLayout.current != AppLayout.desktop) return;

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    title: 'DevVault',
    size: Size(1280, 800),
    minimumSize: Size(1100, 700),
    center: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
