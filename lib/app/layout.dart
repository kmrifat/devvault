import 'package:flutter/foundation.dart';

/// Which shell the app uses: the three-pane window (design frame D03) or the
/// phone layout with a bottom nav (B2).
enum AppLayout {
  desktop,
  mobile;

  /// Desktop operating systems always get the three-pane layout. Their windows
  /// have a 1100×700 minimum, so the panes always fit.
  static AppLayout forPlatform(TargetPlatform platform) => switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => AppLayout.desktop,
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => AppLayout.mobile,
  };

  /// The layout for the platform the app is running on.
  static AppLayout get current => forPlatform(defaultTargetPlatform);
}
