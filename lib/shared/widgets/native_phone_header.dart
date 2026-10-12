import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

/// One button in a [NativePhoneHeader]: an SF Symbol named for screen
/// readers by [label], or, without a [symbol], [label] as text ("Show
/// all").
@immutable
class NativeHeaderAction {
  const NativeHeaderAction({
    required this.id,
    required this.label,
    required this.onPressed,
    this.symbol,
  });

  final String id;
  final String? symbol;
  final String label;
  final VoidCallback onPressed;
}

/// A phone screen's header on iPhone: UIKit's own navigation bar
/// (`native_liquid_glass`), Liquid Glass on iOS 26. The title, a back
/// chevron when [onBack] is set, and [actions] as SF Symbols in the accent
/// colour. Put it in `Scaffold.appBar` with `extendBodyBehindAppBar`, so
/// the page scrolls under the glass; the scaffold then adds the bar's
/// height to the page's top padding.
///
/// Screens show it only when [nativeBarsProvider] is on (iOS); elsewhere,
/// and in tests, they keep their bc_ui headers.
class NativePhoneHeader extends StatelessWidget implements PreferredSizeWidget {
  const NativePhoneHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final VoidCallback? onBack;
  final List<NativeHeaderAction> actions;

  static const double barHeight = 44;

  @override
  Size get preferredSize => const Size.fromHeight(barHeight);

  void _tapped(String id) {
    if (id == 'back') {
      onBack?.call();
      return;
    }
    for (final action in actions) {
      if (action.id == id) action.onPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final onBack = this.onBack;
    return Semantics(
      container: true,
      header: true,
      label: title,
      child: SafeArea(
        bottom: false,
        child: LiquidGlassNavigationBar(
          title: title,
          height: barHeight,
          tintColor: bc.accent,
          brightness: Theme.of(context).brightness,
          leadingItems: [
            if (onBack != null)
              const LiquidGlassNavBarItem(
                id: 'back',
                icon: NativeLiquidGlassIcon.sfSymbol('chevron.left'),
              ),
          ],
          trailingItems: [
            for (final action in actions)
              switch (action.symbol) {
                final symbol? => LiquidGlassNavBarItem(
                  id: action.id,
                  icon: NativeLiquidGlassIcon.sfSymbol(symbol),
                ),
                null => LiquidGlassNavBarItem(
                  id: action.id,
                  label: action.label,
                ),
              },
          ],
          onItemTapped: _tapped,
        ),
      ),
    );
  }
}
