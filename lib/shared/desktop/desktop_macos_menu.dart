import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'desktop_colors.dart';
import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// The macOS menu look DevVault draws itself (pop-up and combo box menus):
/// a light panel with a hairline border, rows that fill with the accent
/// when hovered or focused, and a check mark beside the chosen one.
abstract final class MacosMenuStyle {
  static const double padding = 5;

  static MenuStyle panel(DesktopColors colors) => MenuStyle(
    backgroundColor: WidgetStatePropertyAll(colors.menu),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(8),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(padding)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        side: BorderSide(color: colors.groupBoxStroke, width: 0.5),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.menuRadius),
        ),
      ),
    ),
  );

  /// One row, at least [width] wide so the menu is as wide as its field.
  /// A long label shows in full up to [DesktopMetrics.menuMaxWidth], then
  /// ends in an ellipsis. A [destructive] row's label is in the danger
  /// colour until lit.
  static Widget item(
    BuildContext context, {
    required String label,
    required double width,
    required VoidCallback onPressed,
    bool? checked,
    bool destructive = false,
  }) {
    final colors = context.desktopColors;
    bool lit(Set<WidgetState> s) =>
        s.contains(WidgetState.hovered) || s.contains(WidgetState.focused);
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: checked == null
          ? null
          : SizedBox(
              width: 14,
              child: checked
                  ? const Icon(CupertinoIcons.checkmark_alt, size: 13)
                  : null,
            ),
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size(width - 2 * padding, DesktopMetrics.controlHeight + 2),
        ),
        maximumSize: WidgetStatePropertyAll(
          Size(
            math.max(width, DesktopMetrics.menuMaxWidth) - 2 * padding,
            double.infinity,
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(DesktopMetrics.menuItemRadius),
            ),
          ),
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => lit(s) ? colors.accent : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => lit(s)
              ? colors.onAccent
              : destructive
              ? colors.danger
              : colors.text,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => lit(s) ? colors.onAccent : colors.text,
        ),
        textStyle: WidgetStatePropertyAll(
          DefaultTextStyle.of(context).style
              .copyWith(fontSize: DesktopMetrics.bodySize),
        ),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
