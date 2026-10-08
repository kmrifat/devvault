import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// Opens [builder]'s [DesktopPanel] floating near the top of the window,
/// like Spotlight (or PowerToys Run, or GNOME's search): the window behind
/// isn't dimmed, and a click outside or Escape closes it. Resolves with
/// what the panel pops.
///
/// DevVault draws the panel itself on every OS; the controls inside it are
/// the kit's.
Future<T?> showDesktopPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

/// A floating panel: rounded, with a shadow, [width] wide, at the top
/// centre of the window. Escape closes it.
class DesktopPanel extends StatelessWidget {
  const DesktopPanel({
    super.key,
    required this.child,
    this.width = DesktopMetrics.panelWidth,
    this.semanticLabel,
  });

  final Widget child;
  final double width;

  /// Names the panel for screen readers ("Quick open").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    const radius = BorderRadius.all(
      Radius.circular(DesktopMetrics.panelRadius),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: DesktopMetrics.panelTop),
          child: Semantics(
            label: semanticLabel,
            scopesRoute: true,
            namesRoute: semanticLabel != null,
            explicitChildNodes: true,
            child: SizedBox(
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.menu,
                  borderRadius: radius,
                  border: Border.all(color: colors.groupBoxStroke, width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Material(
                    type: MaterialType.transparency,
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: DesktopMetrics.bodySize,
                        color: colors.text,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
