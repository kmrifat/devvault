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
    this.backSymbol = 'chevron.left',
    this.actions = const [],
  });

  final String title;
  final VoidCallback? onBack;

  /// The leading button's SF Symbol: a back chevron, or `xmark` for a
  /// form's Cancel.
  final String backSymbol;
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
      // UIKit fades a page out under its bar (the scroll edge effect); a
      // bar hosted over Flutter has no scroll view to do that, so the page
      // fades here, behind it.
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bc.background, bc.background.withValues(alpha: 0)],
            stops: const [0.8, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: LiquidGlassNavigationBar(
            title: title,
            height: barHeight,
            tintColor: bc.accent,
            brightness: Theme.of(context).brightness,
            leadingItems: [
              if (onBack != null)
                LiquidGlassNavBarItem(
                  id: 'back',
                  icon: NativeLiquidGlassIcon.sfSymbol(backSymbol),
                ),
            ],
            // UIKit lays trailing items out from the right edge; [actions]
            // read left to right.
            trailingItems: [
              for (final action in actions.reversed)
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
      ),
    );
  }
}

/// A root tab's large title on iPhone (design frames I1, I2, I6, I7): the
/// title, and an optional line of facts under it, at the top of the
/// page, which scrolls with it. Pair it with [LargeTitleScroll], which
/// puts the title in the [NativePhoneHeader] once this has scrolled under
/// the bar, as UIKit's large titles do.
class PhoneLargeTitle extends StatelessWidget {
  const PhoneLargeTitle(this.title, {super.key, this.subtitle});

  final String title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BCSpacing.md, 0, BCSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: BCSpacing.xxs,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: BCTypography.size3xl,
                height: 1.2,
                fontWeight: BCTypography.bold,
                letterSpacing: BCTypography.trackingTight(BCTypography.size3xl),
                color: bc.foreground,
              ),
            ),
          ),
          ?subtitle,
        ],
      ),
    );
  }
}

/// The scroll position of a page with a [PhoneLargeTitle]: [titleInBar]
/// turns true once the large title has scrolled under the bar. Give
/// [titleScroll] to the page's scroll view.
mixin LargeTitleScroll<T extends StatefulWidget> on State<T> {
  final titleScroll = ScrollController();
  bool titleInBar = false;

  /// How far the page scrolls before the title belongs in the bar: about
  /// the large title's own height.
  static const threshold = 36.0;

  @override
  void initState() {
    super.initState();
    titleScroll.addListener(_scrolled);
  }

  void _scrolled() {
    final under = titleScroll.offset > threshold;
    if (under != titleInBar) setState(() => titleInBar = under);
  }

  @override
  void dispose() {
    titleScroll.dispose();
    super.dispose();
  }
}
