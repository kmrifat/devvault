import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_metrics.dart';
import 'desktop_symbols.dart';
import 'desktop_theme.dart';

/// One command in a [DesktopPullDownButton]'s menu.
@immutable
class DesktopMenuAction {
  const DesktopMenuAction(
    this.label,
    this.onSelected, {
    this.destructive = false,
  });

  final String label;
  final VoidCallback onSelected;

  /// Deletes something: drawn in the danger colour.
  final bool destructive;
}

/// A pull-down button: an icon push button (⋯ by default) that drops a
/// menu of commands, such as the inspector's "Replace file…" and "Delete
/// item…". [label] names it for screen readers and its tooltip.
///
/// - macOS: a `PushButton` with the menu in the macOS menu style (the
///   macos_ui pull-down draws a caret the design doesn't have).
/// - Windows: Fluent `DropDownButton` with a menu flyout.
/// - Linux: Material's `PopupMenuButton` in the Yaru theme.
class DesktopPullDownButton extends StatelessWidget {
  const DesktopPullDownButton({
    super.key,
    required this.label,
    required this.actions,
    this.symbol = DesktopSymbol.more,
  }) : assert(actions.length > 0);

  final String label;
  final List<DesktopMenuAction> actions;
  final DesktopSymbol symbol;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final kit = context.desktopKit;
    final icon = Icon(symbol.of(kit), size: 14, color: colors.text);
    return switch (kit) {
      DesktopKit.macos => _MacosPullDown(
        label: label,
        actions: actions,
        icon: icon,
      ),
      DesktopKit.fluent => fl.DropDownButton(
        items: [
          for (final a in actions)
            fl.MenuFlyoutItem(
              text: Text(
                a.label,
                style: a.destructive ? TextStyle(color: colors.danger) : null,
              ),
              onPressed: a.onSelected,
            ),
        ],
        // Fluent's tooltip also names the button for screen readers.
        buttonBuilder: (context, onOpen) => fl.Tooltip(
          message: label,
          child: fl.Button(onPressed: onOpen, child: icon),
        ),
      ),
      DesktopKit.yaru => PopupMenuButton<int>(
        tooltip: label,
        // The tooltip isn't a label; the icon's is.
        icon: Icon(
          symbol.of(kit),
          size: 14,
          color: colors.text,
          semanticLabel: label,
        ),
        onSelected: (i) => actions[i].onSelected(),
        itemBuilder: (context) => [
          for (final (i, a) in actions.indexed)
            PopupMenuItem(
              value: i,
              child: Text(
                a.label,
                style: a.destructive ? TextStyle(color: colors.danger) : null,
              ),
            ),
        ],
      ),
    };
  }
}

const double _menuPadding = 5;
const double _menuMinWidth = 160;

class _MacosPullDown extends StatelessWidget {
  const _MacosPullDown({
    required this.label,
    required this.actions,
    required this.icon,
  });

  final String label;
  final List<DesktopMenuAction> actions;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    bool highlighted(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.menu),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(_menuPadding)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            side: BorderSide(color: colors.groupBoxStroke, width: 0.5),
            borderRadius: const BorderRadius.all(
              Radius.circular(DesktopMetrics.menuRadius),
            ),
          ),
        ),
      ),
      menuChildren: [
        for (final a in actions)
          MenuItemButton(
            onPressed: a.onSelected,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(
                Size(_menuMinWidth, DesktopMetrics.controlHeight),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10),
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
                (states) =>
                    highlighted(states) ? colors.accent : Colors.transparent,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => highlighted(states)
                    ? colors.onAccent
                    : a.destructive
                    ? colors.danger
                    : colors.text,
              ),
              textStyle: WidgetStatePropertyAll(
                DefaultTextStyle.of(context).style
                    .copyWith(fontSize: DesktopMetrics.bodySize),
              ),
            ),
            child: Text(a.label),
          ),
      ],
      builder: (context, menu, _) => mac.MacosTooltip(
        message: label,
        // The button carries the name; the tooltip would say it twice.
        excludeFromSemantics: true,
        child: SizedBox(
          // An icon-only push button: the kit's 60 pt minimum is for text.
          width: 32,
          child: mac.PushButton(
            controlSize: mac.ControlSize.regular,
            secondary: true,
            semanticLabel: label,
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            child: icon,
          ),
        ),
      ),
    );
  }
}
