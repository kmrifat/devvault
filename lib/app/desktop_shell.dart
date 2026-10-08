import 'package:flutter/material.dart' show Scaffold, VerticalDivider;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart' show VaultIndex;

import '../core/shortcuts.dart';
import '../data/sync_controller.dart';
import '../data/vault_filter.dart';
import '../data/vault_session.dart';
import '../features/import/drop_import.dart';
import '../features/import/import_dialog.dart';
import '../features/search/quick_open.dart';
import '../features/sync/desktop_sync_status.dart';
import '../features/vault/vault_actions.dart';
import '../features/vault/vault_heading.dart';
import '../features/vault/vault_sidebar.dart';
import '../shared/desktop_ui.dart';
import 'desktop_commands.dart';
import 'routes.dart';

/// The desktop window (design frame N03): the source list down the left,
/// and beside it a toolbar (title, Import, New, search, sync, Lock) over
/// the selected branch, with a status bar along the bottom.
///
/// The shell branches are Vault, Expiry and Settings, in that order; the
/// sidebar links into them by location rather than branch index.
///
/// Keyboard: ⌘F (Ctrl+F) focuses search, ⌘K (Ctrl+K) opens quick-open,
/// ⌘I imports, ⌘N adds an item, ⌘R syncs now. On macOS the menu bar
/// handles these keys; the window binds the commands it runs.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({
    super.key,
    required this.navigationShell,
    required this.uri,
  });

  final StatefulNavigationShell navigationShell;

  /// The current location, which the sidebar and search reflect.
  final Uri uri;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  final _searchFocus = FocusNode(debugLabel: 'vault search');
  bool _quickOpenShowing = false;

  @override
  void initState() {
    super.initState();
    // A global handler rather than Shortcuts: it works wherever focus is,
    // including nowhere after a click on empty space.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  DesktopCommands? _commands;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final commands = DesktopCommands.maybeOf(context);
    if (commands == _commands) return;
    _commands?.unbind();
    _commands = commands
      ?..bind(
        find: _inFront(_searchFocus.requestFocus),
        newItem: _inFront(_newItem),
        importFile: _inFront(() => showImportDialog(context)),
        quickOpen: _inFront(_quickOpen),
      );
  }

  /// [action], run only while the window is in front: not under a dialog
  /// or another screen.
  VoidCallback _inFront(VoidCallback action) => () {
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) action();
  };

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _commands?.unbind();
    _searchFocus.dispose();
    super.dispose();
  }

  /// A new item where the user is looking: in the selected app, platform,
  /// environment or tag.
  void _newItem() => createItem(
    context,
    ShellSection.values[widget.navigationShell.currentIndex] ==
            ShellSection.vault
        ? VaultFilter.fromUri(widget.uri)
        : const VaultFilter(),
  );

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    // The macOS menu bar owns these keys there.
    if (platformMenusActive(context)) return false;
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
    if (event.logicalKey == LogicalKeyboardKey.keyI) {
      showImportDialog(context);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      _newItem();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyR &&
        ref.read(syncControllerProvider) is! SyncOff) {
      ref.read(syncControllerProvider.notifier).syncNow();
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
    final colors = context.desktopColors;
    final section = ShellSection.values[widget.navigationShell.currentIndex];
    final uri = widget.uri;
    return Scaffold(
      backgroundColor: colors.window,
      body: ImportDropTarget(
        child: DesktopWindow(
          sidebarBuilder: (context, scroll) => VaultSidebar(
            section: section,
            uri: uri,
            scrollController: scroll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShellToolbar(
                section: section,
                uri: uri,
                searchFocus: _searchFocus,
              ),
              Expanded(child: widget.navigationShell),
              ShellStatusBar(section: section, uri: uri),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the toolbar and status bar say about the current list: its title,
/// the path to it, and how many items it holds (null outside the vault).
({String title, String path, int? count}) _describe(
  ShellSection section,
  Uri uri,
  VaultIndex? index,
) {
  switch (section) {
    case ShellSection.expiry:
      return (
        title: 'Expiry',
        path: 'Every date is from a file or from you',
        count: null,
      );
    case ShellSection.settings:
      return (title: 'Settings', path: '', count: null);
    case ShellSection.vault:
      final filter = VaultFilter.fromUri(uri);
      if (index == null) return (title: 'All items', path: '', count: null);
      final heading = vaultHeading(filter, index.apps);
      return (
        title: heading.title,
        path: heading.path.join(' › '),
        count: filter.view == VaultView.quarantine
            ? index.quarantined.length
            : filter.apply(index).length,
      );
  }
}

String _items(int count) => count == 1 ? '1 item' : '$count items';

/// The window's unified toolbar: the list's title, path and count, Import
/// and New, search (⌘F), the sync status and Lock.
class ShellToolbar extends ConsumerStatefulWidget {
  const ShellToolbar({
    super.key,
    required this.section,
    required this.uri,
    required this.searchFocus,
  });

  final ShellSection section;
  final Uri uri;
  final FocusNode searchFocus;

  @override
  ConsumerState<ShellToolbar> createState() => _ToolbarState();
}

class _ToolbarState extends ConsumerState<ShellToolbar> {
  late final _search = TextEditingController(text: _query ?? '');

  String? get _query => widget.section == ShellSection.vault
      ? VaultFilter.fromUri(widget.uri).q
      : null;

  @override
  void didUpdateWidget(ShellToolbar oldWidget) {
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

  VaultFilter get _filter => widget.section == ShellSection.vault
      ? VaultFilter.fromUri(widget.uri)
      : const VaultFilter();

  /// Searches within the current filter; from Expiry or Settings it
  /// searches the whole vault.
  void _onSearch(String text) {
    final item = widget.section == ShellSection.vault
        ? widget.uri.queryParameters['item']
        : null;
    context.go(_filter.withQuery(text).location(item: item));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final session = ref.watch(vaultSessionProvider);
    final index = session is Unlocked ? session.index : null;
    final about = _describe(widget.section, widget.uri, index);
    final count = about.count;
    final subtitle = [
      if (about.path.isNotEmpty) about.path,
      if (count != null) _items(count),
    ].join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(bottom: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: SizedBox(
        height: DesktopMetrics.toolbarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            spacing: 6,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 140, maxWidth: 240),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      about.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesktopMetrics.bodySize,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DesktopMetrics.secondarySize,
                          color: colors.secondaryText,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DesktopIconButton(
                symbol: DesktopSymbol.importFile,
                tooltip: 'Import a file (${shortcutLabel('I')})',
                onPressed: () => openImport(context),
              ),
              DesktopIconButton(
                symbol: DesktopSymbol.add,
                tooltip: 'New item',
                onPressed: () => createItem(context, _filter),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: DesktopSearchField(
                      controller: _search,
                      focusNode: widget.searchFocus,
                      placeholder: 'Search items, key IDs, fingerprints',
                      onChanged: _onSearch,
                    ),
                  ),
                ),
              ),
              const DesktopSyncStatus(),
              DesktopIconButton(
                symbol: DesktopSymbol.lock,
                tooltip: 'Lock now (${shortcutLabel('L')})',
                onPressed: () => ref.read(vaultSessionProvider.notifier).lock(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The window's status bar: how many items the list holds, and that the vault is
/// end-to-end encrypted.
class ShellStatusBar extends ConsumerWidget {
  const ShellStatusBar({super.key, required this.section, required this.uri});

  final ShellSection section;
  final Uri uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.desktopColors;
    final session = ref.watch(vaultSessionProvider);
    final index = session is Unlocked ? session.index : null;
    final count = _describe(section, uri, index).count;
    final style = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bar,
        border: Border(top: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: SizedBox(
        height: DesktopMetrics.statusBarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (count != null) Text(_items(count), style: style),
              const Spacer(),
              Text('End-to-end encrypted', style: style),
              const SizedBox(width: 5),
              DesktopIcon(DesktopSymbol.lock, size: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// The vault branch on desktop: item list and detail side by side.
class VaultPanes extends StatelessWidget {
  /// The list pane's width until it becomes the N03 item table
  /// ([DesktopMetrics.tableWidth]): its tabs need this much.
  static const double listWidth = 420;

  const VaultPanes({super.key, required this.list, required this.detail});

  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: listWidth, child: list),
        VerticalDivider(width: 1, thickness: 0.5, color: colors.separator),
        Expanded(child: detail),
      ],
    );
  }
}
