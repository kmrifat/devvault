import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/vault_filter.dart';
import '../data/vault_session.dart';
import '../features/vault/vault_sidebar.dart';

/// The desktop window (design frame D03): the vault sidebar, and next to it
/// a toolbar (search, lock) above the content of the selected branch.
///
/// The shell branches are Vault, Expiry and Settings, in that order; the
/// sidebar links into them by location rather than branch index.
class DesktopShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final section = ShellSection.values[navigationShell.currentIndex];
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
                _Toolbar(section: section, uri: uri),
                Expanded(child: navigationShell),
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
  const _Toolbar({required this.section, required this.uri});

  final ShellSection section;
  final Uri uri;

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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: BCSearchField(
                      controller: _search,
                      variant: BCInputVariant.secondary,
                      placeholder:
                          'Search items, bundle IDs, key IDs, fingerprints',
                      onChanged: _onSearch,
                      onClear: () => _onSearch(''),
                    ),
                  ),
                ),
              ),
              BCButton(
                size: BCButtonSize.sm,
                variant: BCButtonVariant.tertiary,
                onPressed: () => ref.read(vaultSessionProvider.notifier).lock(),
                startContent: const Icon(LucideIcons.lock, size: 14),
                child: const Text('Lock'),
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
