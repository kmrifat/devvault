import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'desktop_macos_menu.dart';
import 'desktop_menu_focus.dart';
import 'desktop_pull_down_button.dart';
import 'desktop_theme.dart';

/// Opens a menu of [actions] where [child] is right-clicked (or
/// long-pressed on a touch screen): a sidebar row's "New item…", "Edit app…" …
///
/// - macOS: DevVault's macOS menu ([MacosMenuStyle]) at the pointer.
/// - Windows: a Fluent `MenuFlyout` at the pointer.
/// - Linux: Material's menu in the Yaru theme.
///
/// Each action is also a custom semantics action on [child], so assistive
/// tech reaches the commands without a pointer. With a
/// `GlobalKey<DesktopContextMenuState>`, [DesktopContextMenuState.open]
/// opens it from the keyboard (Shift-F10, the menu key). The open menu
/// takes the keyboard ([DesktopMenuFocus]) and gives it back when it
/// closes.
class DesktopContextMenu extends StatefulWidget {
  const DesktopContextMenu({
    super.key,
    required this.actions,
    required this.child,
  });

  /// Empty leaves [child] as it is.
  final List<DesktopMenuAction> actions;
  final Widget child;

  @override
  State<DesktopContextMenu> createState() => DesktopContextMenuState();
}

class DesktopContextMenuState extends State<DesktopContextMenu> {
  final _menu = MenuController();
  final _flyout = fl.FlyoutController();
  final _focus = DesktopMenuFocus('Context');

  @override
  void dispose() {
    _flyout.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Opens the menu under [child]'s leading edge, as a keyboard shortcut
  /// does, with its first command highlighted.
  void open() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _open(
      box.localToGlobal(Offset(box.size.height / 2, box.size.height)),
      fromKeyboard: true,
    );
  }

  void _open(Offset global, {bool fromKeyboard = false}) {
    final actions = widget.actions;
    if (actions.isEmpty) return;
    _focus.opened(count: actions.length, fromKeyboard: fromKeyboard);
    switch (context.desktopKit) {
      case DesktopKit.fluent:
        final colors = context.desktopColors;
        _flyout
            .showFlyout<void>(
              position: global,
              barrierColor: Colors.transparent,
              builder: (context) => _focus.holder(
                child: fl.MenuFlyout(
                  items: [
                    for (final (i, a) in actions.indexed)
                      fl.MenuFlyoutItem(
                        focusNode: _focus.item(i),
                        text: Text(
                          a.label,
                          style: a.destructive
                              ? TextStyle(color: colors.danger)
                              : null,
                        ),
                        onPressed: a.onSelected,
                      ),
                  ],
                ),
              ),
            )
            .whenComplete(_focus.closed);
      case DesktopKit.macos || DesktopKit.yaru:
        final box = context.findRenderObject()! as RenderBox;
        _menu.open(position: box.globalToLocal(global));
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    if (actions.isEmpty) return widget.child;
    final colors = context.desktopColors;
    final macos = context.desktopKit == DesktopKit.macos;
    final target = Semantics(
      customSemanticsActions: {
        for (final a in actions)
          CustomSemanticsAction(label: a.label): a.onSelected,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) => _open(d.globalPosition),
        // A long press with a mouse is the start of a drag.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          supportedDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
          },
          onLongPressStart: (d) => _open(d.globalPosition),
          child: widget.child,
        ),
      ),
    );
    if (context.desktopKit == DesktopKit.fluent) {
      return fl.FlyoutTarget(controller: _flyout, child: target);
    }
    return MenuAnchor(
      controller: _menu,
      style: macos ? MacosMenuStyle.panel(colors) : null,
      consumeOutsideTap: true,
      onClose: _focus.closed,
      menuChildren: [
        _focus.holder(),
        for (final (i, a) in actions.indexed)
          if (macos)
            MacosMenuStyle.item(
              context,
              label: a.label,
              width: 200,
              onPressed: a.onSelected,
              destructive: a.destructive,
              focusNode: _focus.item(i),
            )
          else
            MenuItemButton(
              onPressed: a.onSelected,
              focusNode: _focus.item(i),
              child: Text(
                a.label,
                style: a.destructive ? TextStyle(color: colors.danger) : null,
              ),
            ),
      ],
      child: target,
    );
  }
}
