import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../data/providers.dart';
import '../data/search_query.dart';
import '../features/search/search_screen.dart';

/// The phone layout (design frames I1–I7): the selected branch with the
/// tab bar over it.
///
/// On iPhone the tab bar is UIKit's own (`native_liquid_glass`): Liquid
/// Glass on iOS 26, the standard bar before it, with SF Symbols. Vault,
/// Expiry and Settings share the bar and Search is its own button beside
/// it, like a `UITab` with the search role. On the Search tab the bar
/// gives way to the search field, with one button back to the last tab.
/// It hides itself while a sheet or dialog covers the shell. Android, and
/// tests ([nativeBarsProvider]), keep bc_ui's floating bar with Search as
/// a fourth tab.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({
    super.key,
    required this.navigationShell,
    required this.uri,
  });

  final StatefulNavigationShell navigationShell;

  /// The current location, for the search field's text.
  final Uri uri;

  /// The branches, in order: label, Lucide icon, SF Symbol (and its filled
  /// form for the selected tab). Search is last.
  static const tabs = [
    ('Vault', LucideIcons.layers, 'square.stack.3d.up'),
    ('Expiry', LucideIcons.clock, 'clock'),
    ('Settings', LucideIcons.settings, 'gearshape'),
    ('Search', LucideIcons.search, 'magnifyingglass'),
  ];

  static const searchIndex = 3;

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  /// The tab Search goes back to.
  late int _lastTab = _current == MobileShell.searchIndex ? 0 : _current;

  int get _current => widget.navigationShell.currentIndex;

  @override
  void didUpdateWidget(MobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_current != MobileShell.searchIndex) _lastTab = _current;
  }

  void _select(int i) =>
      widget.navigationShell.goBranch(i, initialLocation: i == _current);

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final native = ref.watch(nativeBarsProvider);
    final searching = _current == MobileShell.searchIndex;
    return Scaffold(
      backgroundColor: bc.background,
      extendBody: true,
      body: widget.navigationShell,
      bottomNavigationBar: !native
          ? BCBottomNav(
              variant: BCBottomNavVariant.floating,
              currentIndex: _current,
              onTap: _select,
              items: [
                for (final (label, icon, _) in MobileShell.tabs)
                  BCBottomNavItem(icon: Icon(icon), label: label),
              ],
            )
          : searching
          ? SearchDock(
              uri: widget.uri,
              backIcon: MobileShell.tabs[_lastTab].$2,
              backLabel: MobileShell.tabs[_lastTab].$1,
              onBack: () => _select(_lastTab),
            )
          : LiquidGlassTabBar(
              currentIndex: _current,
              onTabSelected: _select,
              selectedItemColor: bc.accent,
              items: [
                for (final (label, _, symbol) in MobileShell.tabs.take(
                  MobileShell.searchIndex,
                ))
                  LiquidGlassTabItem(
                    label: label,
                    icon: NativeLiquidGlassIcon.sfSymbol(symbol),
                    selectedIcon: NativeLiquidGlassIcon.sfSymbol(
                      '$symbol.fill',
                    ),
                  ),
              ],
              iosActionButton: LiquidGlassTabItem(
                label: MobileShell.tabs[MobileShell.searchIndex].$1,
                icon: NativeLiquidGlassIcon.sfSymbol(
                  MobileShell.tabs[MobileShell.searchIndex].$3,
                ),
              ),
              onActionButtonPressed: () => _select(MobileShell.searchIndex),
            ),
    );
  }
}

/// The iPhone's tab bar while Search is open (design frames I2–I4): a
/// round button back to the last tab and the search field, which rides
/// above the keyboard. What is typed goes into the `/search` query.
///
/// Drawn by Flutter as frosted glass rather than with native views: the
/// field is Flutter's, and a native glass behind it barely shows on a
/// light list. IDs aren't words, so autocorrection and suggestions are off.
class SearchDock extends StatefulWidget {
  const SearchDock({
    super.key,
    required this.uri,
    required this.backIcon,
    required this.backLabel,
    required this.onBack,
  });

  final Uri uri;
  final IconData backIcon;
  final String backLabel;
  final VoidCallback onBack;

  static const height = 56.0;

  @override
  State<SearchDock> createState() => _SearchDockState();
}

class _SearchDockState extends State<SearchDock> {
  late final _field = TextEditingController(text: _query.q ?? '');
  final _focus = FocusNode();

  SearchQuery get _query => SearchQuery.fromUri(widget.uri);

  @override
  void initState() {
    super.initState();
    _field.addListener(_changed);
    // Opening Search is for typing, unless it comes back to a search.
    if (_query.isBrowse) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(SearchDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final q = _query.q ?? '';
    if (q.trim() != _field.text.trim()) _field.text = q;
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _search(String text) => context.go(_query.withQ(text).location());

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final media = MediaQuery.of(context);
    final bottom = math.max(
      media.viewInsets.bottom + BCSpacing.sm,
      media.padding.bottom,
    );
    return AnimatedPadding(
      duration: BCDuration.fast,
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom),
      child: SizedBox(
        height: SearchDock.height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Semantics(
              button: true,
              label: widget.backLabel,
              excludeSemantics: true,
              child: _Glass(
                shape: const CircleBorder(),
                onPressed: widget.onBack,
                child: SizedBox.square(
                  dimension: SearchDock.height,
                  child: Icon(widget.backIcon, size: 22, color: bc.foreground),
                ),
              ),
            ),
            Expanded(
              child: _Glass(
                shape: const StadiumBorder(),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 18, right: 10),
                  child: Row(
                    spacing: 10,
                    children: [
                      Icon(LucideIcons.search, size: 19, color: bc.muted),
                      Expanded(
                        child: Semantics(
                          label: 'Search',
                          textField: true,
                          child: TextField(
                            controller: _field,
                            focusNode: _focus,
                            onChanged: _search,
                            autocorrect: false,
                            enableSuggestions: false,
                            smartDashesType: SmartDashesType.disabled,
                            smartQuotesType: SmartQuotesType.disabled,
                            textInputAction: TextInputAction.search,
                            keyboardAppearance: Theme.of(context).brightness,
                            cursorColor: bc.accent,
                            style: TextStyle(
                              fontSize: BCTypography.sizeLg,
                              color: bc.foreground,
                            ),
                            decoration: InputDecoration.collapsed(
                              hintText: SearchScreen.placeholder,
                              hintStyle: TextStyle(
                                fontSize: BCTypography.sizeLg,
                                color: bc.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_field.text.isNotEmpty)
                        Semantics(
                          button: true,
                          label: 'Clear search',
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              _field.clear();
                              _search('');
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(BCSpacing.xs),
                              child: Icon(
                                LucideIcons.circleX,
                                size: 20,
                                color: bc.muted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frosted glass in [shape]: what is behind it blurred, under the
/// overlay surface and a hairline, like the tab bar it stands in for.
class _Glass extends StatelessWidget {
  const _Glass({required this.shape, required this.child, this.onPressed});

  final OutlinedBorder shape;
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final outlined = shape.copyWith(side: BorderSide(color: bc.border));
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: outlined,
        shadows: bc.overlayShadow.shadows,
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: BCPressable(
            onPressed: onPressed,
            enabled: onPressed != null,
            feedback: onPressed == null
                ? BCPressFeedback.none
                : BCPressFeedback.scaleHighlight,
            shape: shape,
            background: DecoratedBox(
              decoration: ShapeDecoration(
                color: bc.overlay.withValues(alpha: 0.78),
                shape: outlined,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
