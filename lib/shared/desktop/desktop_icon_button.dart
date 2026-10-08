import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_metrics.dart';
import 'desktop_symbols.dart';
import 'desktop_theme.dart';

/// A borderless icon button with a tooltip (toolbar actions, Lock):
/// `MacosIconButton`, Fluent `IconButton`, or a Yaru-themed `IconButton`.
/// [tooltip] also names it for screen readers.
class DesktopIconButton extends StatelessWidget {
  const DesktopIconButton({
    super.key,
    required this.symbol,
    required this.tooltip,
    required this.onPressed,
    this.size = 16,
  });

  final DesktopSymbol symbol;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final kit = context.desktopKit;
    final icon = Icon(
      symbol.of(kit),
      size: size,
      color: onPressed == null ? colors.tertiaryText : colors.secondaryText,
    );
    return switch (kit) {
      DesktopKit.macos => mac.MacosTooltip(
        message: tooltip,
        // The button carries the name; the tooltip would say it twice.
        excludeFromSemantics: true,
        child: mac.MacosIconButton(
          icon: icon,
          semanticLabel: tooltip,
          backgroundColor: Colors.transparent,
          hoverColor: colors.innerSeparator,
          borderRadius: const BorderRadius.all(
            Radius.circular(DesktopMetrics.fieldRadius),
          ),
          boxConstraints: BoxConstraints.tight(
            const Size.square(DesktopMetrics.toolbarSearchHeight),
          ),
          onPressed: onPressed,
        ),
      ),
      DesktopKit.fluent => fl.Tooltip(
        message: tooltip,
        child: Semantics(
          label: tooltip,
          child: fl.IconButton(icon: icon, onPressed: onPressed),
        ),
      ),
      DesktopKit.yaru => IconButton(
        tooltip: tooltip,
        icon: icon,
        onPressed: onPressed,
      ),
    };
  }
}
