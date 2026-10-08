import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// The main window's frame (design frame N03): a resizable source-list
/// sidebar the full height of the window, and [child] beside it.
///
/// In the app's window on macOS it's macos_ui's `MacosWindow` and
/// `Sidebar`: the sidebar runs under the traffic lights with the system's
/// vibrancy behind it, and can be resized. Windows and Linux keep their own
/// title bar and get a fixed sidebar in the sidebar colour; so do tests on
/// every kit ([DesktopTheme.nativeWindow]).
class DesktopWindow extends StatelessWidget {
  const DesktopWindow({
    super.key,
    required this.sidebarBuilder,
    required this.child,
  });

  /// Builds the sidebar's content. macOS hands it a scroll controller for
  /// its list; elsewhere it gets null.
  final Widget Function(BuildContext context, ScrollController? scroll)
  sidebarBuilder;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    if (DesktopTheme.of(context).nativeWindow) {
      return mac.MacosWindow(
        backgroundColor: colors.window,
        sidebar: mac.Sidebar(
          minWidth: DesktopMetrics.sidebarWidth - 20,
          startWidth: DesktopMetrics.sidebarWidth,
          maxWidth: DesktopMetrics.sidebarWidth + 100,
          dragClosed: false,
          builder: sidebarBuilder,
        ),
        child: child,
      );
    }
    return ColoredBox(
      color: colors.window,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: DesktopMetrics.sidebarWidth,
            child: ColoredBox(
              color: colors.sidebar,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: sidebarBuilder(context, null),
              ),
            ),
          ),
          SizedBox(width: 1, child: ColoredBox(color: colors.separator)),
          Expanded(child: child),
        ],
      ),
    );
  }
}
