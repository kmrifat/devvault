import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_macos_menu.dart';
import 'desktop_menu_focus.dart';
import 'desktop_symbols.dart';
import 'desktop_theme.dart';

/// One command in a [DesktopPullDownButton]'s or a `DesktopContextMenu`'s
/// menu.
@immutable
class DesktopMenuAction {
  const DesktopMenuAction(
    this.label,
    this.onSelected, {
    this.destructive = false,
    this.startsGroup = false,
  });

  final String label;
  final VoidCallback onSelected;

  /// Deletes something: drawn in the danger colour.
  final bool destructive;

  /// Begins a new group of commands: a separator above it, unless it is
  /// the menu's first.
  final bool startsGroup;
}

/// Whether a separator goes above [actions]' command [i].
bool separatorBefore(List<DesktopMenuAction> actions, int i) =>
    i > 0 && actions[i].startsGroup;

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
          for (final (i, a) in actions.indexed) ...[
            if (separatorBefore(actions, i)) const fl.MenuFlyoutSeparator(),
            fl.MenuFlyoutItem(
              text: Text(
                a.label,
                style: a.destructive ? TextStyle(color: colors.danger) : null,
              ),
              onPressed: a.onSelected,
            ),
          ],
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
          for (final (i, a) in actions.indexed) ...[
            if (separatorBefore(actions, i)) const PopupMenuDivider(),
            PopupMenuItem(
              value: i,
              child: Text(
                a.label,
                style: a.destructive ? TextStyle(color: colors.danger) : null,
              ),
            ),
          ],
        ],
      ),
    };
  }
}

const double _menuMinWidth = 160;

class _MacosPullDown extends StatefulWidget {
  const _MacosPullDown({
    required this.label,
    required this.actions,
    required this.icon,
  });

  final String label;
  final List<DesktopMenuAction> actions;
  final Widget icon;

  @override
  State<_MacosPullDown> createState() => _MacosPullDownState();
}

class _MacosPullDownState extends State<_MacosPullDown> {
  /// The push button takes no focus, so the menu always opens from the
  /// pointer: it holds the keyboard with nothing highlighted.
  final _focus = DesktopMenuFocus('Pull-down');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final actions = widget.actions;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MacosMenuStyle.panel(context.desktopColors),
      clipBehavior: Clip.antiAlias,
      onOpen: () => _focus.opened(count: actions.length, fromKeyboard: false),
      onClose: _focus.closed,
      menuChildren: [
        MacosMenuStyle.surface(
          context,
          children: [
            _focus.holder(),
            for (final (i, a) in actions.indexed) ...[
              if (separatorBefore(actions, i))
                MacosMenuStyle.separator(context),
              MacosMenuStyle.item(
                context,
                label: a.label,
                width: _menuMinWidth,
                onPressed: a.onSelected,
                destructive: a.destructive,
                focusNode: _focus.item(i),
              ),
            ],
          ],
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
            child: widget.icon,
          ),
        ),
      ),
    );
  }
}
