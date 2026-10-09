import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'desktop_macos_menu.dart';
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
/// tech reaches the commands without a pointer.
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
  State<DesktopContextMenu> createState() => _DesktopContextMenuState();
}

class _DesktopContextMenuState extends State<DesktopContextMenu> {
  final _menu = MenuController();
  final _flyout = fl.FlyoutController();

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  void _open(Offset global) {
    final actions = widget.actions;
    if (actions.isEmpty) return;
    switch (context.desktopKit) {
      case DesktopKit.fluent:
        final colors = context.desktopColors;
        _flyout.showFlyout<void>(
          position: global,
          barrierColor: Colors.transparent,
          builder: (context) => fl.MenuFlyout(
            items: [
              for (final a in actions)
                fl.MenuFlyoutItem(
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
        );
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
      menuChildren: [
        for (final a in actions)
          if (macos)
            MacosMenuStyle.item(
              context,
              label: a.label,
              width: 200,
              onPressed: a.onSelected,
              destructive: a.destructive,
            )
          else
            MenuItemButton(
              onPressed: a.onSelected,
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
