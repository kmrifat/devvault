import 'package:flutter/material.dart';

import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// The Linux command menu (context and pull-down menus), after GNOME's
/// GTK 4 popover menus that Ubuntu's Yaru styles: Yaru's menu colours and
/// border on a rounder panel with an inset all round, and rows that light
/// up as rounded pills inside it, with separators that keep to the inset.
///
/// A `MenuAnchor` takes [panel] as its style and `Clip.antiAlias` as its
/// clip; its rows are [item]s, with a [separator] between groups.
abstract final class YaruMenuStyle {
  /// Yaru's own menu style, reshaped.
  static MenuStyle panel(BuildContext context) {
    final yaru = Theme.of(context).menuTheme.style ?? const MenuStyle();
    final side = yaru.side?.resolve(const {});
    return MenuStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.all(DesktopMetrics.yaruMenuPadding),
      ),
      minimumSize: const WidgetStatePropertyAll(
        Size(DesktopMetrics.yaruMenuMinWidth, 0),
      ),
      // Rows set their own height; desktop's compact density would also
      // take from the panel's inset.
      visualDensity: VisualDensity.standard,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          side: side ?? BorderSide.none,
          borderRadius: const BorderRadius.all(
            Radius.circular(DesktopMetrics.yaruMenuRadius),
          ),
        ),
      ),
    ).merge(yaru);
  }

  /// The line between two groups of rows.
  static Widget separator() =>
      const Divider(height: DesktopMetrics.yaruMenuSeparatorHeight);

  /// One row. A [destructive] row's label is in the danger colour.
  static Widget item(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
    bool destructive = false,
    FocusNode? focusNode,
  }) => MenuItemButton(
    onPressed: onPressed,
    focusNode: focusNode,
    style: ButtonStyle(
      visualDensity: VisualDensity.standard,
      alignment: AlignmentDirectional.centerStart,
      minimumSize: const WidgetStatePropertyAll(
        Size(0, DesktopMetrics.yaruMenuRowHeight),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: DesktopMetrics.yaruMenuRowInset),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(DesktopMetrics.yaruMenuRowRadius),
          ),
        ),
      ),
    ),
    child: Text(
      label,
      style: destructive
          ? TextStyle(color: context.desktopColors.danger)
          : null,
    ),
  );
}
