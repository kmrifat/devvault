import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;
import 'package:yaru/yaru.dart' as yaru;

import 'desktop_colors.dart';

/// The UI kit that draws desktop controls (ADR-0005): each OS gets its own,
/// so the app looks and feels native there. Phones keep bc_ui.
enum DesktopKit {
  /// macOS: `macos_ui`.
  macos,

  /// Windows: `fluent_ui`.
  fluent,

  /// Linux: `yaru`.
  yaru;

  /// The kit native to [platform]. Phone platforms never reach the desktop
  /// layer; they map to the macOS kit only so the function is total.
  static DesktopKit forPlatform(TargetPlatform platform) => switch (platform) {
    TargetPlatform.windows => DesktopKit.fluent,
    TargetPlatform.linux => DesktopKit.yaru,
    _ => DesktopKit.macos,
  };

  /// The kit for the OS the app is running on.
  static DesktopKit get current => forPlatform(defaultTargetPlatform);
}

/// Puts [kit]'s theme, in the surrounding brightness, above [child], plus
/// DevVault's [DesktopColors]. Every desktop control reads the kit from here.
///
/// It goes in the app's `MaterialApp.builder`, around the Navigator, so
/// menus and flyouts the kits push as routes are themed too. bc_ui and
/// Material keep working below it: the macOS and Windows kits bring their
/// own theme widgets, and on Linux Yaru's Material theme is merged with the
/// app's theme extensions.
class DesktopTheme extends StatelessWidget {
  const DesktopTheme({super.key, this.kit, required this.child});

  /// Defaults to the running OS's kit; tests render each one.
  final DesktopKit? kit;

  final Widget child;

  /// The nearest [DesktopThemeData].
  static DesktopThemeData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DesktopScope>();
    assert(scope != null, 'No DesktopTheme above this widget.');
    return scope!.data;
  }

  @override
  Widget build(BuildContext context) {
    final kit = this.kit ?? DesktopKit.current;
    final brightness = Theme.of(context).brightness;
    final data = DesktopThemeData(
      kit: kit,
      brightness: brightness,
      colors: DesktopColors.of(brightness),
    );
    final scoped = _DesktopScope(data: data, child: child);
    return switch (kit) {
      DesktopKit.macos => _macos(brightness, scoped),
      DesktopKit.fluent => _fluent(context, brightness, scoped),
      DesktopKit.yaru => _yaru(context, brightness, scoped),
    };
  }

  Widget _macos(Brightness brightness, Widget child) {
    final theme = brightness == Brightness.dark
        ? mac.MacosThemeData.dark()
        : mac.MacosThemeData.light();
    return mac.MacosTheme(
      data: theme,
      child: DefaultTextStyle(style: theme.typography.body, child: child),
    );
  }

  Widget _fluent(BuildContext context, Brightness brightness, Widget child) {
    final theme = fl.FluentThemeData(
      brightness: brightness,
      accentColor: fl.Colors.blue,
    );
    // Fluent controls look up their own strings; the app's Localizations
    // only carries Material's and Cupertino's.
    return Localizations.override(
      context: context,
      delegates: const [fl.FluentLocalizations.delegate],
      child: fl.FluentTheme(
        data: theme,
        child: DefaultTextStyle(
          style: theme.typography.body ?? const TextStyle(),
          child: child,
        ),
      ),
    );
  }

  Widget _yaru(BuildContext context, Brightness brightness, Widget child) {
    final yaruTheme = brightness == Brightness.dark
        ? yaru.yaruDark
        : yaru.yaruLight;
    // Keep the app's extensions (bc_ui tokens) for widgets not yet moved
    // to the desktop layer.
    final extensions = {
      ...yaruTheme.extensions,
      ...Theme.of(context).extensions,
    };
    return Theme(
      data: yaruTheme.copyWith(extensions: extensions.values),
      child: child,
    );
  }
}

/// What [DesktopTheme] provides.
@immutable
class DesktopThemeData {
  const DesktopThemeData({
    required this.kit,
    required this.brightness,
    required this.colors,
  });

  final DesktopKit kit;
  final Brightness brightness;
  final DesktopColors colors;
}

class _DesktopScope extends InheritedWidget {
  const _DesktopScope({required this.data, required super.child});

  final DesktopThemeData data;

  @override
  bool updateShouldNotify(_DesktopScope oldWidget) =>
      data.kit != oldWidget.data.kit ||
      data.brightness != oldWidget.data.brightness;
}

extension DesktopThemeContext on BuildContext {
  /// The kit drawing desktop controls here.
  DesktopKit get desktopKit => DesktopTheme.of(this).kit;

  /// DevVault's desktop colours in the current brightness.
  DesktopColors get desktopColors => DesktopTheme.of(this).colors;
}
