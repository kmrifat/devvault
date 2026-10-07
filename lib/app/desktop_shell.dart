import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/vault_filter.dart';
import '../data/vault_session.dart';
import '../features/search/quick_open.dart';
import '../features/vault/vault_sidebar.dart';
import 'routes.dart';
import 'theme.dart';

/// The desktop window (design frame D03): the vault sidebar, and next to it
/// a toolbar (search, lock) above the content of the selected branch.
///
/// The shell branches are Vault, Expiry and Settings, in that order; the
/// sidebar links into them by location rather than branch index.
///
/// Keyboard: ⌘F (Ctrl+F) focuses search, ⌘K (Ctrl+K) opens quick-open.
class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    required this.navigationShell,
    required this.uri,
  });

  final StatefulNavigationShell navigationShell;

  /// The current location, which the sidebar and search reflect.
  final Uri uri;

  static const double sidebarWidth = VaultSidebar.width;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final _searchFocus = FocusNode(debugLabel: 'vault search');
  bool _quickOpenShowing = false;

  @override
  void initState() {
    super.initState();
    // A global handler rather than Shortcuts: it works wherever focus is,
    // including nowhere after a click on empty space.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _searchFocus.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    // Not while a dialog or another screen is on top.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!(keyboard.isMetaPressed || keyboard.isControlPressed) ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyK) {
      _quickOpen();
      return true;
    }
    return false;
  }

  Future<void> _quickOpen() async {
    if (_quickOpenShowing) return;
    _quickOpenShowing = true;
    try {
      final id = await showQuickOpen(context);
      if (id != null && mounted) context.go(Routes.vault(item: id));
    } finally {
      _quickOpenShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final section = ShellSection.values[widget.navigationShell.currentIndex];
    final uri = widget.uri;
    return Scaffold(
      backgroundColor: bc.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VaultSidebar(section: section, uri: uri),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Toolbar(
                  section: section,
                  uri: uri,
                  searchFocus: _searchFocus,
                  onQuickOpen: _quickOpen,
                ),
                Expanded(child: widget.navigationShell),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Search across the vault and the lock button.
class _Toolbar extends ConsumerStatefulWidget {
  const _Toolbar({
    required this.section,
    required this.uri,
    required this.searchFocus,
    required this.onQuickOpen,
  });

  final ShellSection section;
  final Uri uri;
  final FocusNode searchFocus;
  final VoidCallback onQuickOpen;

  static const double height = 64;

  @override
  ConsumerState<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends ConsumerState<_Toolbar> {
  late final _search = TextEditingController(text: _query ?? '');

  String? get _query => widget.section == ShellSection.vault
      ? VaultFilter.fromUri(widget.uri).q
      : null;

  @override
  void didUpdateWidget(_Toolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the location (back, forward, a sidebar link) unless it already
    // says what the field does.
    final query = _query ?? '';
    if (query.trim() != _search.text.trim()) _search.text = query;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Searches within the current filter; from Expiry or Settings it
  /// searches the whole vault.
  void _onSearch(String text) {
    final filter = widget.section == ShellSection.vault
        ? VaultFilter.fromUri(widget.uri)
        : const VaultFilter();
    final item = widget.section == ShellSection.vault
        ? widget.uri.queryParameters['item']
        : null;
    context.go(filter.withQuery(text).location(item: item));
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: bc.border)),
      ),
      child: SizedBox(
        height: _Toolbar.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            spacing: BCSpacing.md,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: BCSpacing.sm,
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: BCSearchField(
                            controller: _search,
                            focusNode: widget.searchFocus,
                            variant: BCInputVariant.secondary,
                            placeholder:
                                'Search items, bundle IDs, key IDs, '
                                'fingerprints',
                            onChanged: _onSearch,
                            onClear: () => _onSearch(''),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Quick open',
                        child: BCButton(
                          size: BCButtonSize.sm,
                          variant: BCButtonVariant.tertiary,
                          onPressed: widget.onQuickOpen,
                          child: Text(
                            defaultTargetPlatform == TargetPlatform.macOS
                                ? '⌘K'
                                : 'Ctrl K',
                            style: AppText.mono(
                              context,
                              fontSize: BCTypography.sizeXs,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Tooltip(
                message: defaultTargetPlatform == TargetPlatform.macOS
                    ? 'Lock now (⌘L)'
                    : 'Lock now (Ctrl+L)',
                child: BCButton(
                  size: BCButtonSize.sm,
                  variant: BCButtonVariant.tertiary,
                  onPressed: () =>
                      ref.read(vaultSessionProvider.notifier).lock(),
                  startContent: const Icon(LucideIcons.lock, size: 14),
                  child: const Text('Lock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The vault branch on desktop: item list and detail side by side.
class VaultPanes extends StatelessWidget {
  const VaultPanes({super.key, required this.list, required this.detail});

  final Widget list;
  final Widget detail;

  static const double listWidth = 420;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: listWidth, child: list),
        VerticalDivider(width: 1, thickness: 1, color: bc.border),
        Expanded(child: detail),
      ],
    );
  }
}
