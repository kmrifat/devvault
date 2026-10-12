import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'desktop_pull_down_button.dart';
import 'desktop_theme.dart';

/// AppKit's own menu (`NSMenu`), for context and pull-down menus in the
/// real macOS window (P7-01): the system draws it, so it looks, reads and
/// behaves like every other app's, keyboard and VoiceOver included.
///
/// Channel `devvault/menu` (macos/Runner/NativeMenu.swift): `popUp` with
/// the window position and the commands; it returns the index of the one
/// picked, or null. Tests and the other kits keep the drawn menus.
abstract final class DesktopNativeMenu {
  static const channel = MethodChannel('devvault/menu');

  /// Whether menus in [context] are AppKit's: macOS, in the app's window
  /// ([DesktopTheme.nativeWindow]).
  static bool usedIn(BuildContext context) {
    final theme = DesktopTheme.maybeOf(context);
    return theme != null && theme.nativeWindow && theme.kit == DesktopKit.macos;
  }

  /// Shows [actions] with its top-left corner at [global] (logical pixels
  /// from the window's top-left) and runs the one picked.
  static Future<void> show(
    List<DesktopMenuAction> actions,
    Offset global,
  ) async {
    if (actions.isEmpty) return;
    final picked = await channel.invokeMethod<int>('popUp', {
      'x': global.dx,
      'y': global.dy,
      'items': [
        for (final (i, a) in actions.indexed)
          {
            'title': a.label,
            'symbol': ?a.macSymbol,
            'separatorBefore': separatorBefore(actions, i),
          },
      ],
    });
    if (picked != null && picked >= 0 && picked < actions.length) {
      actions[picked].onSelected();
    }
  }
}
