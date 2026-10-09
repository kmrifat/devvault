import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_metrics.dart';
import 'desktop_symbols.dart';
import 'desktop_theme.dart';

enum DesktopButtonKind {
  /// A plain push button (Cancel, Export, Edit).
  plain,

  /// The default action, in the accent colour (Add to Vault, Unlock).
  primary,

  /// An action that destroys data (Delete): red on Windows and Linux, a
  /// plain button with a red label on macOS (red, too, in dark mode, where
  /// that label would be too faint).
  destructive,
}

enum DesktopButtonSize {
  /// 26 pt on macOS: forms, sheets.
  regular,

  /// The larger size: lock screens. (Windows and Linux have one size.)
  large,
}

/// A push button drawn by the desktop kit: `PushButton`, Fluent `Button` /
/// `FilledButton`, or Yaru-themed `OutlinedButton` / `ElevatedButton` (the
/// default action, Ubuntu's green "suggested action") / `FilledButton` (red,
/// destructive).
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
    // On a macOS button in dark mode the red label is 2.4:1, so there it
    // is filled like the others' and keeps a white label.
    final redFill =
        danger &&
        (kit != DesktopKit.macos ||
            DesktopTheme.of(context).brightness == Brightness.dark);
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
                : redFill
                ? colors.onDangerButton
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
      // macos_ui paints default buttons in the system's bright blue, which
      // carries white text at only 3.9:1; this keeps the native shape in
      // the design's accent (5.6:1).
      DesktopKit.macos
          when kind == DesktopButtonKind.primary && onPressed != null =>
        _MacosFilledButton(
          fill: colors.accent,
          large: size == DesktopButtonSize.large,
          onPressed: onPressed!,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: colors.onAccent),
            child: text,
          ),
        ),
      DesktopKit.macos when redFill && onPressed != null => _MacosFilledButton(
        fill: colors.dangerButton,
        large: size == DesktopButtonSize.large,
        onPressed: onPressed!,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.onDangerButton),
          child: text,
        ),
      ),
      // macOS draws a destructive action as a plain button with a red
      // label; only the default action is filled.
      // macos_ui's large push button is 26 pt, level with the 28 pt fields
      // beside it; the large size stretches it to the lock screens' 32 pt.
      DesktopKit.macos => SizedBox(
        height: size == DesktopButtonSize.large
            ? DesktopMetrics.largeButtonHeight
            : DesktopMetrics.buttonHeight,
        child: mac.PushButton(
          controlSize: mac.ControlSize.large,
          secondary: kind != DesktopButtonKind.primary,
          onPressed: onPressed,
          child: danger
              ? labelled(Text(label, style: TextStyle(color: colors.danger)))
              : text,
        ),
      ),
      DesktopKit.fluent when filled => fl.FilledButton(
        style: danger
            ? fl.ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(colors.dangerButton),
                foregroundColor: WidgetStatePropertyAll(colors.onDangerButton),
              )
            : null,
        onPressed: onPressed,
        child: text,
      ),
      DesktopKit.fluent => fl.Button(onPressed: onPressed, child: text),
      // Yaru's FilledButton is a neutral grey that reads as disabled; its
      // ElevatedButton is the suggested action.
      DesktopKit.yaru when danger => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: colors.dangerButton,
          foregroundColor: colors.onDangerButton,
        ),
        onPressed: onPressed,
        child: text,
      ),
      DesktopKit.yaru when filled => ElevatedButton(
        onPressed: onPressed,
        child: text,
      ),
      DesktopKit.yaru => OutlinedButton(
        style: symbol == null
            ? null
            : OutlinedButton.styleFrom(
                padding: DesktopMetrics.yaruSymbolButtonPadding,
              ),
        onPressed: onPressed,
        child: text,
      ),
    };
  }
}

/// A filled macOS push button in [fill]: the default action (blue), or a
/// destructive one in dark mode. The same size, corners and pressed state
/// as macos_ui's.
class _MacosFilledButton extends StatefulWidget {
  const _MacosFilledButton({
    required this.fill,
    required this.large,
    required this.onPressed,
    required this.child,
  });

  final Color fill;
  final bool large;
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_MacosFilledButton> createState() => _MacosFilledButtonState();
}

class _MacosFilledButtonState extends State<_MacosFilledButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final accent = _down
        ? Color.lerp(widget.fill, const Color(0xFF000000), 0.15)!
        : widget.fill;
    final radius = BorderRadius.all(Radius.circular(widget.large ? 8 : 7));
    return Semantics(
      button: true,
      enabled: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: widget.large
                ? DesktopMetrics.largeButtonHeight
                : DesktopMetrics.buttonHeight,
            minWidth: widget.large ? 48 : 60,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(accent, const Color(0xFFFFFFFF), 0.06)!,
                  accent,
                ],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  offset: Offset(0, 0.5),
                  blurRadius: 0.5,
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.large ? 18 : 14,
                vertical: widget.large ? 7 : 5,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: widget.large
                      ? DesktopMetrics.bodySize + 2
                      : DesktopMetrics.bodySize,
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
