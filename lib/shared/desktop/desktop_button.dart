import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_symbols.dart';
import 'desktop_theme.dart';

enum DesktopButtonKind {
  /// A plain push button (Cancel, Export, Edit).
  plain,

  /// The default action, in the accent colour (Add to Vault, Unlock).
  primary,

  /// An action that destroys data (Delete): red on Windows and Linux, a
  /// plain button with a red label on macOS.
  destructive,
}

enum DesktopButtonSize {
  /// 22 pt on macOS: forms, sheets, toolbars.
  regular,

  /// The larger size: lock screens. (Windows and Linux have one size.)
  large,
}

/// A push button drawn by the desktop kit: `PushButton`, Fluent `Button` /
/// `FilledButton`, or Yaru-themed `OutlinedButton` / `FilledButton`.
class DesktopButton extends StatelessWidget {
  const DesktopButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = DesktopButtonKind.plain,
    this.size = DesktopButtonSize.regular,
    this.icon,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final DesktopButtonKind kind;
  final DesktopButtonSize size;

  /// A symbol before the label (Save PDF…, Unlock with Touch ID).
  final DesktopSymbol? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final filled = kind != DesktopButtonKind.plain;
    final danger = kind == DesktopButtonKind.destructive;
    final kit = context.desktopKit;
    final symbol = icon;
    Widget labelled(Widget text) {
      if (symbol == null) return text;
      final onMacAccent = kit == DesktopKit.macos
          ? kind == DesktopButtonKind.primary
          : filled;
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          Icon(
            symbol.of(kit),
            size: 14,
            color: onPressed == null
                ? colors.tertiaryText
                : onMacAccent
                ? colors.onAccent
                : danger
                ? colors.danger
                : colors.text,
          ),
          Flexible(child: text),
        ],
      );
    }

    final text = labelled(Text(label));
    return switch (kit) {
      // macOS draws a destructive action as a plain button with a red
      // label; only the default action is filled.
      DesktopKit.macos => mac.PushButton(
        controlSize: size == DesktopButtonSize.large
            ? mac.ControlSize.large
            : mac.ControlSize.regular,
        secondary: kind != DesktopButtonKind.primary,
        onPressed: onPressed,
        child: danger
            ? labelled(Text(label, style: TextStyle(color: colors.danger)))
            : text,
      ),
      DesktopKit.fluent when filled => fl.FilledButton(
        style: danger
            ? fl.ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(colors.danger),
              )
            : null,
        onPressed: onPressed,
        child: text,
      ),
      DesktopKit.fluent => fl.Button(onPressed: onPressed, child: text),
      DesktopKit.yaru when filled => FilledButton(
        style: danger
            ? FilledButton.styleFrom(backgroundColor: colors.danger)
            : null,
        onPressed: onPressed,
        child: text,
      ),
      DesktopKit.yaru => OutlinedButton(onPressed: onPressed, child: text),
    };
  }
}
