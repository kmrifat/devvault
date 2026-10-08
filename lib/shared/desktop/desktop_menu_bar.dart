import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';

import 'desktop_theme.dart';

/// One top-level menu (File, Edit, …) of a [DesktopMenuBar].
@immutable
class DesktopMenu {
  const DesktopMenu(this.label, this.entries);

  final String label;
  final List<DesktopMenuEntry> entries;
}

sealed class DesktopMenuEntry {
  const DesktopMenuEntry();
}

/// A command. Null [onSelected] shows it disabled. [shortcut] runs it from
/// the keyboard on macOS, where the system menu owns the key; elsewhere it
/// is only shown, and the app handles the key itself.
class DesktopMenuItem extends DesktopMenuEntry {
  const DesktopMenuItem(this.label, {this.shortcut, this.onSelected});

  final String label;
  final SingleActivator? shortcut;
  final VoidCallback? onSelected;
}

class DesktopMenuDivider extends DesktopMenuEntry {
  const DesktopMenuDivider();
}

/// A standard item macOS provides itself (About, Hide, Quit, the Window
/// menu's items). Other OSes leave it out.
class DesktopMenuProvided extends DesktopMenuEntry {
  const DesktopMenuProvided(this.type);

  final PlatformProvidedMenuItemType type;
}

/// Whether the app's menus are the macOS menu bar, which then owns their
/// keyboard shortcuts: in-app key handlers must leave those keys alone, or
/// they'd run twice.
bool platformMenusActive(BuildContext context) {
  final theme = DesktopTheme.maybeOf(context);
  return theme != null && theme.nativeWindow && theme.kit == DesktopKit.macos;
}

/// The app's menus, the way each OS shows them (design doc › Menu bar):
/// the system menu bar on macOS (`PlatformMenuBar`), and a menu bar along
/// the top of the window on Windows and Linux, as TablePlus does.
///
/// The in-window bar is Flutter's `MenuBar`: Yaru's theme styles it on
/// Linux, and on Windows it takes Fluent's menu colours. (Fluent's own
/// `MenuBar` opens its menus through a Navigator, and this bar sits above
/// the app's.)
///
/// macOS tests (no native window) render [child] alone.
class DesktopMenuBar extends StatelessWidget {
  const DesktopMenuBar({super.key, required this.menus, required this.child});

  final List<DesktopMenu> menus;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = DesktopTheme.of(context);
    return switch (theme.kit) {
      DesktopKit.macos when theme.nativeWindow => PlatformMenuBar(
        menus: [for (final menu in menus) _platformMenu(menu)],
        child: child,
      ),
      DesktopKit.macos => child,
      DesktopKit.fluent || DesktopKit.yaru => _inWindow(
        context,
        MenuBar(
          style: const MenuStyle(
            elevation: WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(Colors.transparent),
          ),
          children: [
            for (final menu in menus)
              SubmenuButton(
                menuStyle: _menuStyle(context, theme.kit),
                menuChildren: [
                  for (final entry in menu.entries)
                    ?switch (entry) {
                      DesktopMenuItem() => MenuItemButton(
                        shortcut: entry.shortcut,
                        onPressed: entry.onSelected,
                        child: Text(entry.label),
                      ),
                      DesktopMenuDivider() => const Divider(height: 1),
                      DesktopMenuProvided() => null,
                    },
                ],
                child: Text(menu.label),
              ),
          ],
        ),
      ),
    };
  }

  /// Yaru's theme styles Flutter's menus already; on Windows they take
  /// Fluent's menu colour and corners.
  static MenuStyle? _menuStyle(BuildContext context, DesktopKit kit) {
    if (kit != DesktopKit.fluent) return null;
    final fluent = fl.FluentTheme.of(context);
    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll(fluent.menuColor),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          side: BorderSide(color: fluent.resources.surfaceStrokeColorFlyout),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }

  /// The menu bar above the rest of the window.
  Widget _inWindow(BuildContext context, Widget bar) {
    final colors = context.desktopColors;
    return _MenuOverlay(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.toolbar,
              border: Border(
                bottom: BorderSide(color: colors.separator, width: 0.5),
              ),
            ),
            child: Material(type: MaterialType.transparency, child: bar),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  static PlatformMenu _platformMenu(DesktopMenu menu) {
    // macOS draws dividers between groups of items.
    final groups = <List<PlatformMenuItem>>[[]];
    for (final entry in menu.entries) {
      switch (entry) {
        case DesktopMenuDivider():
          groups.add([]);
        case DesktopMenuItem():
          groups.last.add(
            PlatformMenuItem(
              label: entry.label,
              shortcut: entry.shortcut,
              onSelected: entry.onSelected,
            ),
          );
        case DesktopMenuProvided(:final type):
          if (PlatformProvidedMenuItem.hasMenu(type)) {
            groups.last.add(PlatformProvidedMenuItem(type: type));
          }
      }
    }
    final nonEmpty = groups.where((g) => g.isNotEmpty).toList();
    return PlatformMenu(
      label: menu.label,
      menus: nonEmpty.length == 1
          ? nonEmpty.single
          : [for (final g in nonEmpty) PlatformMenuItemGroup(members: g)],
    );
  }
}

/// An [Overlay] for the in-window menus to open into: the menu bar sits
/// above the app's Navigator, which holds the only other one.
class _MenuOverlay extends StatefulWidget {
  const _MenuOverlay({required this.child});

  final Widget child;

  @override
  State<_MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<_MenuOverlay> {
  late final _entry = OverlayEntry(builder: (context) => widget.child);

  @override
  void didUpdateWidget(_MenuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
