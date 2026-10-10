import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'desktop_colors.dart';
import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// The macOS menu look DevVault draws itself (context, pull-down, pop-up
/// and combo box menus), after the system's own: a translucent panel that
/// blurs what is behind it, with a hairline border and a soft shadow;
/// 24 pt rows that fill with the accent when hovered or focused, a check
/// mark beside the chosen one, and hairline separators between groups.
///
/// A `MenuAnchor` takes [panel] as its style, `Clip.antiAlias` as its
/// clip, and one [surface] holding the rows as its menu children.
abstract final class MacosMenuStyle {
  /// Between the panel's edge and its rows.
  static const double padding = 5;

  /// A row's label and a separator are this far in from the row's edge.
  static const double _inset = 10;

  /// How much of the panel's colour covers the blurred window behind it.
  static const double _opacity = 0.75;
  static const double _blur = 24;

  /// The panel itself: its shape, border and shadow. It is clear;
  /// [surface] fills it.
  static MenuStyle panel(DesktopColors colors) => MenuStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: WidgetStatePropertyAll(colors.shadow),
    elevation: const WidgetStatePropertyAll(12),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: WidgetStatePropertyAll(shape(colors)),
  );

  static RoundedRectangleBorder shape(DesktopColors colors) =>
      RoundedRectangleBorder(
        side: BorderSide(color: colors.groupBoxStroke, width: 0.5),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.menuPanelRadius),
        ),
      );

  /// The panel's fill: the window behind it blurred, under a veil of the
  /// menu colour, and [children] (rows, separators) stacked as wide as
  /// the widest.
  static Widget surface(
    BuildContext context, {
    required List<Widget> children,
  }) => backdrop(
    context,
    child: IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  /// [surface]'s fill around any [child] (the date field's calendar).
  static Widget backdrop(BuildContext context, {required Widget child}) =>
      BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
        child: ColoredBox(
          color: context.desktopColors.menu.withValues(alpha: _opacity),
          child: Padding(padding: const EdgeInsets.all(padding), child: child),
        ),
      );

  /// The hairline between two groups of rows.
  static Widget separator(BuildContext context) => Divider(
    height: DesktopMetrics.menuSeparatorHeight,
    thickness: 1,
    indent: _inset,
    endIndent: _inset,
    color: context.desktopColors.innerSeparator,
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
    FocusNode? focusNode,
  }) {
    final colors = context.desktopColors;
    bool lit(Set<WidgetState> s) =>
        s.contains(WidgetState.hovered) || s.contains(WidgetState.focused);
    return MenuItemButton(
      onPressed: onPressed,
      focusNode: focusNode,
      leadingIcon: checked == null
          ? null
          : SizedBox(
              width: 14,
              child: checked
                  ? const Icon(CupertinoIcons.checkmark_alt, size: 13)
                  : null,
            ),
      style: ButtonStyle(
        // The row's own height on every platform: desktop's compact
        // density would take 8 pt off it.
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: WidgetStatePropertyAll(
          Size(width - 2 * padding, DesktopMetrics.menuRowHeight),
        ),
        maximumSize: WidgetStatePropertyAll(
          Size(
            math.max(width, DesktopMetrics.menuMaxWidth) - 2 * padding,
            double.infinity,
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: _inset),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(DesktopMetrics.menuRowRadius),
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
