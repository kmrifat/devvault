import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';

import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// A text link that runs an action ("Use your recovery key…", "Join a vault
/// from your bucket…"): accent text with a pointer cursor on macOS, Fluent's
/// `HyperlinkButton` on Windows, a Yaru-themed `TextButton` on Linux.
///
/// It is at least 24 pt tall, so it meets the desktop pointer-target size,
/// and screen readers hear it as a link. Null [onPressed] disables it.
class DesktopLink extends StatelessWidget {
  const DesktopLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final link = switch (context.desktopKit) {
      DesktopKit.macos => _MacosLink(label: label, onPressed: onPressed),
      DesktopKit.fluent => fl.HyperlinkButton(
        onPressed: onPressed,
        child: Text(label),
      ),
      DesktopKit.yaru => TextButton(
        style: TextButton.styleFrom(foregroundColor: colors.accentIcon),
        onPressed: onPressed,
        child: Text(label),
      ),
    };
    return MergeSemantics(
      child: Semantics(
        link: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minHeight),
          child: Align(widthFactor: 1, heightFactor: 1, child: link),
        ),
      ),
    );
  }

  static const double _minHeight = 24;
}

/// macOS draws a link as plain accent text: no background, a pointing hand
/// on hover, and the focus ring when reached with the keyboard.
class _MacosLink extends StatefulWidget {
  const _MacosLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_MacosLink> createState() => _MacosLinkState();
}

class _MacosLinkState extends State<_MacosLink> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final onPressed = widget.onPressed;
    final enabled = onPressed != null;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => onPressed?.call(),
        ),
      },
      child: Semantics(
        link: true,
        enabled: enabled,
        onTap: onPressed,
        excludeSemantics: true,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(
                Radius.circular(DesktopMetrics.fieldRadius),
              ),
              border: Border.all(
                color: _focused ? colors.accent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: DesktopMetrics.bodySize,
                  color: enabled ? colors.accentIcon : colors.tertiaryText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
