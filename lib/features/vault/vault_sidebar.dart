import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../core/expiry.dart';
import '../../data/providers.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart';
import '../../shared/widgets/app_badge.dart';
import 'desktop_item_type.dart';
import 'explorer_tree.dart';
import 'tree_actions.dart';
import 'tree_drag.dart';
import 'vault_actions.dart';

/// Which part of the app the window shows, as the sidebar sees it.
enum ShellSection { vault, expiry, settings }

/// The window's source list (design frame N03): the vault, the smart lists
/// with counts (all items, expiring in 30 days, expired, conflicts), an
/// explorer of the vault's organizations, apps and items, tags, and a
/// footer with Settings and the auto-lock time.
///
/// The explorer works like a file explorer ([ExplorerTree]): Organization
/// › App › Item, every row with a context menu (New item…, Edit app…,
/// Move to…, Rename organization…, Delete …), and everything can be
/// rearranged by dragging: an item (here or from the list) onto an app,
/// "No app" or another item moves it to that app, and an app onto an
/// organization (or "Personal") moves it there. Clicking an organization
/// or app lists its items; clicking an item selects it.
///
/// The explorer works from the keyboard like a file explorer's: ↑/↓, Home
/// and End move a cursor; → opens a row or steps into it, ← closes it or
/// steps out; Enter or Space opens what the row lists; F2 renames or
/// edits; Delete (⌘⌫ on macOS) deletes; Shift-F10 or the menu key opens
/// the row's menu; typing jumps to a row by name. While something is
/// dragged, a closed organization or app opens when held over for a
/// moment.
///
/// It has no selection state of its own: what is selected is read from
/// [uri], and every row is a link, so back and forward and a reload all
/// keep the sidebar in step with the list.
class VaultSidebar extends ConsumerStatefulWidget {
  const VaultSidebar({
    super.key,
    required this.section,
    required this.uri,
    this.scrollController,
  });

  final ShellSection section;
  final Uri uri;

  /// macos_ui's sidebar hands one over; elsewhere the list makes its own.
  final ScrollController? scrollController;

  @override
  ConsumerState<VaultSidebar> createState() => _VaultSidebarState();
}

class _VaultSidebarState extends ConsumerState<VaultSidebar> {
  /// Organizations start open; these were closed by the user.
  final _collapsedOrgs = <String>{};

  /// Apps start closed unless they hold the selection; these were opened
  /// (true) or closed (false) by the user.
  final _appOpen = <String, bool>{};

  /// The explorer's rows as last built, top to bottom, for the keyboard.
  var _rows = <_NavRow>[];

  /// The row the keyboard cursor is on ([_NavRow.key]).
  String? _cursor;

  final _treeFocus = FocusNode(debugLabel: 'Explorer');

  /// Each row's context menu, to open it and scroll to it from the
  /// keyboard.
  final _menuKeys = <String, GlobalKey<DesktopContextMenuState>>{};

  /// The row a drag is held over, and the timer that opens it.
  String? _hoverKey;
  Timer? _hoverTimer;

  /// What was typed to jump to a row, and when it's forgotten.
  var _typed = '';
  Timer? _typedTimer;

  @override
  void initState() {
    super.initState();
    _treeFocus.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _treeFocus.dispose();
    _hoverTimer?.cancel();
    _typedTimer?.cancel();
    super.dispose();
  }

  /// Focus arriving from the keyboard puts the cursor on the selected row,
  /// or the first.
  void _focusChanged() {
    if (_treeFocus.hasFocus && !_rows.any((r) => r.key == _cursor)) {
      final selected = _rows.where((r) => r.selected).firstOrNull;
      _cursor = (selected ?? _rows.firstOrNull)?.key;
    }
    setState(() {});
  }

  VaultFilter get _filter => widget.section == ShellSection.vault
      ? VaultFilter.fromUri(widget.uri)
      : const VaultFilter();

  /// Opens [filter] in the vault list, keeping the current search.
  void _show(VaultFilter filter) =>
      context.go(filter.withQuery(_filter.q).location());

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final session = ref.watch(vaultSessionProvider);
    final index = session is Unlocked ? session.index : null;
    final now = ref.watch(clockProvider)();
    final filter = _filter;
    final section = widget.section;
    final expiredSelected =
        section == ShellSection.expiry &&
        widget.uri.queryParameters['show'] == 'expired';
    final conflicts = index == null ? 0 : _conflicts(index);

    // Material for the kits' button ink; the sidebar paints no background
    // itself, so macOS's vibrancy shows through.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VaultHeader(count: index?.items.length ?? 0),
          Expanded(
            child: Focus(
              focusNode: _treeFocus,
              onKeyEvent: _onKey,
              child: ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                children: [
                  _SourceRow(
                    icon: DesktopSymbol.allItems,
                    iconColor: colors.accentIcon,
                    label: 'All items',
                    count: index?.items.length ?? 0,
                    selected: section == ShellSection.vault && filter.isAll,
                    onTap: () => _show(const VaultFilter()),
                  ),
                  _SourceRow(
                    icon: DesktopSymbol.expiring,
                    iconColor: colors.warning,
                    label: 'Expiring in 30 days',
                    count: index?.countExpiring(ExpiryState.soon, now) ?? 0,
                    selected:
                        section == ShellSection.expiry && !expiredSelected,
                    onTap: () => context.go(Routes.expiryShowing()),
                  ),
                  _SourceRow(
                    icon: DesktopSymbol.expired,
                    iconColor: colors.danger,
                    label: 'Expired',
                    count: index?.countExpiring(ExpiryState.expired, now) ?? 0,
                    selected: expiredSelected,
                    onTap: () =>
                        context.go(Routes.expiryShowing(expired: true)),
                  ),
                  if (conflicts > 0)
                    _SourceRow(
                      icon: DesktopSymbol.conflicts,
                      iconColor: colors.conflict,
                      label: 'Conflicts',
                      count: conflicts,
                      selected: filter.view == VaultView.conflicts,
                      onTap: () =>
                          _show(const VaultFilter(view: VaultView.conflicts)),
                    ),
                  if (index != null && index.quarantined.isNotEmpty)
                    _SourceRow(
                      icon: DesktopSymbol.unreadable,
                      iconColor: colors.danger,
                      label: 'Unreadable',
                      count: index.quarantined.length,
                      selected: filter.view == VaultView.quarantine,
                      onTap: () =>
                          _show(const VaultFilter(view: VaultView.quarantine)),
                    ),
                  _SectionLabel(
                    'Apps',
                    menu: [
                      DesktopMenuAction(
                        'New organization…',
                        () => createOrganization(context, ref),
                      ),
                      DesktopMenuAction('New app…', () => createApp(context)),
                      DesktopMenuAction(
                        'New item…',
                        () => createItem(context, const VaultFilter()),
                      ),
                    ],
                    action: DesktopIconButton(
                      symbol: DesktopSymbol.add,
                      tooltip: 'New app',
                      size: 12,
                      onPressed: () => createApp(context),
                    ),
                  ),
                  ..._explorer(index, filter, now),
                  if (index != null && index.tagCounts.isNotEmpty) ...[
                    const _SectionLabel('Tags'),
                    for (final MapEntry(key: tag, value: count)
                        in index.tagCounts.entries)
                      _SourceRow(
                        icon: DesktopSymbol.tag,
                        label: tag,
                        count: count,
                        selected:
                            section == ShellSection.vault && filter.tag == tag,
                        // Clicking the selected tag again shows everything.
                        onTap: () => _show(
                          section == ShellSection.vault && filter.tag == tag
                              ? const VaultFilter()
                              : VaultFilter(tag: tag),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          _Footer(selected: section == ShellSection.settings),
        ],
      ),
    );
  }

  static int _conflicts(VaultIndex index) =>
      index.items.values.where((i) => i.conflict != null).length;

  /// The item selected in the list, if any.
  String? get _selectedItem => widget.section == ShellSection.vault
      ? widget.uri.queryParameters['item']
      : null;

  /// Whether the organization [org] or app [app] is what the list shows,
  /// with no item selected (a selected item is the selection instead).
  bool _isSelected(VaultFilter filter, {String? org, String? app}) =>
      widget.section == ShellSection.vault &&
      _selectedItem == null &&
      filter.tag == null &&
      filter.view == null &&
      filter.platform == null &&
      filter.env == null &&
      filter.org == org &&
      filter.app == app;

  List<Widget> _explorer(VaultIndex? index, VaultFilter filter, DateTime now) {
    _rows = [];
    if (index == null) return const [];
    final tree = ExplorerTree.of(index);
    if (tree.isEmpty) {
      return const [_Hint('Items you add are grouped here by app')];
    }
    final selectedApp = index.items[_selectedItem]?.appId;
    final openApp = selectedApp != null && index.apps.containsKey(selectedApp)
        ? selectedApp
        : _selectedItem != null && index.items.containsKey(_selectedItem)
        ? VaultFilter.none
        : filter.app;
    final shown = filter.apply(index).map((i) => i.id).toSet();
    final rows = _TreeContext(
      index: index,
      filter: filter,
      now: now,
      openApp: openApp,
      shown: shown,
    );
    return [
      if (tree.orgs.isEmpty)
        for (final node in tree.apps) ..._appRows(node, rows, parent: null)
      else
        for (final org in tree.orgs) ..._orgRows(org, rows),
      if (tree.noApp.isNotEmpty) ..._noAppRows(tree.noApp, rows),
    ];
  }

  /// An organization ("Personal" for apps without one) and, while open,
  /// its apps one level in. Dropping an app on it moves the app there.
  List<Widget> _orgRows(ExplorerOrg group, _TreeContext tree) {
    final org = group.name;
    final orgKey = org ?? VaultFilter.none;
    final open = !_collapsedOrgs.contains(orgKey);
    // An organization with one app: a new item goes in that app.
    final onlyApp = group.apps.length == 1 ? group.apps.single.app : null;
    final key = 'org:$orgKey';
    void setOpen(bool on) => setState(
      () => on ? _collapsedOrgs.remove(orgKey) : _collapsedOrgs.add(orgKey),
    );
    void show() {
      setState(() => _collapsedOrgs.remove(orgKey));
      _show(VaultFilter(org: orgKey));
    }

    final selected = _isSelected(tree.filter, org: orgKey);
    _rows.add(
      _NavRow(
        key: key,
        label: org ?? 'Personal',
        selected: selected,
        open: group.apps.isEmpty ? null : open,
        setOpen: setOpen,
        activate: show,
        rename: org == null
            ? null
            : () => renameOrganization(context, ref, org),
        delete: org == null
            ? null
            : () => deleteOrganization(
                context,
                ref,
                org,
                appCount: group.apps.length,
              ),
      ),
    );
    return [
      DragTarget<AppRecord>(
        onWillAcceptWithDetails: (d) => d.data.organization != org,
        onAcceptWithDetails: (d) => moveApp(context, ref, d.data, org),
        builder: (context, candidates, _) => _openOnHover(
          key,
          closed: !open && group.apps.isNotEmpty,
          open: () => _collapsedOrgs.remove(orgKey),
          child: _SourceRow(
            menuKey: _menuKey(key),
            focused: _hasCursor(key),
            dropHover: candidates.isNotEmpty,
            menu: [
              if (group.apps.isNotEmpty)
                DesktopMenuAction(
                  'New item…',
                  () => createItem(
                    context,
                    VaultFilter(org: orgKey),
                    app: onlyApp?.id,
                  ),
                ),
              DesktopMenuAction(
                'New app…',
                () => createApp(context, organization: org),
              ),
              if (org != null) ...[
                DesktopMenuAction(
                  'Rename organization…',
                  () => renameOrganization(context, ref, org),
                  startsGroup: true,
                ),
                DesktopMenuAction(
                  'Delete organization…',
                  () => deleteOrganization(
                    context,
                    ref,
                    org,
                    appCount: group.apps.length,
                  ),
                  destructive: true,
                  startsGroup: true,
                ),
              ],
            ],
            tree: true,
            expanded: open,
            onToggle: group.apps.isEmpty ? null : () => setOpen(!open),
            icon: org == null
                ? DesktopSymbol.person
                : DesktopSymbol.organization,
            label: org ?? 'Personal',
            count: group.count,
            selected: selected,
            onTap: _clicked(key, show),
          ),
        ),
      ),
      if (open)
        for (final node in group.apps)
          ..._appRows(node, tree, parent: key, depth: 1),
    ];
  }

  /// An app and, while open, its items. It drags onto an organization, and
  /// takes items dropped on it.
  List<Widget> _appRows(
    ExplorerApp node,
    _TreeContext tree, {
    required String? parent,
    int depth = 0,
  }) {
    final app = node.app;
    final open = _appOpen[app.id] ?? tree.openApp == app.id;
    final organization = app.organization;
    final key = 'app:${app.id}';
    void show() {
      setState(() => _appOpen[app.id] = true);
      _show(VaultFilter(app: app.id));
    }

    final selected = _isSelected(tree.filter, app: app.id);
    _rows.add(
      _NavRow(
        key: key,
        parent: parent,
        label: app.name,
        selected: selected,
        open: node.items.isEmpty ? null : open,
        setOpen: (on) => setState(() => _appOpen[app.id] = on),
        activate: show,
        rename: () => editApp(context, app),
        delete: () =>
            deleteApp(context, ref, app, itemCount: node.items.length),
      ),
    );
    final row = _itemTarget(
      TreePlace(app: app.id),
      (hover) => _openOnHover(
        key,
        closed: !open && node.items.isNotEmpty,
        open: () => _appOpen[app.id] = true,
        child: _SourceRow(
          menuKey: _menuKey(key),
          focused: _hasCursor(key),
          dropHover: hover,
          menu: [
            DesktopMenuAction(
              'New item…',
              () => createItem(context, VaultFilter(app: app.id)),
            ),
            DesktopMenuAction(
              'Edit app…',
              () => editApp(context, app),
              startsGroup: true,
            ),
            DesktopMenuAction(
              'Move to organization…',
              () => moveAppTo(context, ref, app),
            ),
            if (organization != null)
              DesktopMenuAction(
                'Remove from $organization',
                () => moveApp(context, ref, app, null),
              ),
            DesktopMenuAction(
              'Delete app…',
              () => deleteApp(context, ref, app, itemCount: node.items.length),
              destructive: true,
              startsGroup: true,
            ),
          ],
          tree: true,
          depth: depth,
          expanded: open,
          onToggle: node.items.isEmpty
              ? null
              : () => setState(() => _appOpen[app.id] = !open),
          leading: AppBadge(app: app, size: 14),
          label: app.name,
          count: node.items.length,
          selected: selected,
          onTap: _clicked(key, show),
        ),
      ),
    );
    return [
      TreeDraggable<AppRecord>(
        data: app,
        feedback: DragChip(
          label: app.name,
          leading: AppBadge(app: app, size: 14),
        ),
        child: row,
      ),
      if (open)
        for (final item in node.items)
          _itemRow(item, app.id, tree, parent: key, depth: depth + 1),
    ];
  }

  /// "No app" and, while open, the items without one.
  List<Widget> _noAppRows(List<Item> items, _TreeContext tree) {
    const app = VaultFilter.none;
    const key = 'app:$app';
    final open = _appOpen[app] ?? tree.openApp == app;
    void show() {
      setState(() => _appOpen[app] = true);
      _show(const VaultFilter(app: app));
    }

    final selected = _isSelected(tree.filter, app: app);
    _rows.add(
      _NavRow(
        key: key,
        label: 'No app',
        selected: selected,
        open: open,
        setOpen: (on) => setState(() => _appOpen[app] = on),
        activate: show,
      ),
    );
    return [
      _itemTarget(
        const TreePlace(app: app),
        (hover) => _openOnHover(
          key,
          closed: !open,
          open: () => _appOpen[app] = true,
          child: _SourceRow(
            menuKey: _menuKey(key),
            focused: _hasCursor(key),
            dropHover: hover,
            menu: [
              DesktopMenuAction(
                'New item…',
                () => createItem(context, const VaultFilter(app: app)),
              ),
            ],
            tree: true,
            expanded: open,
            onToggle: () => setState(() => _appOpen[app] = !open),
            leading: const AppBadge(app: null, size: 14),
            label: 'No app',
            count: items.length,
            selected: selected,
            onTap: _clicked(key, show),
          ),
        ),
      ),
      if (open)
        for (final item in items)
          _itemRow(item, app, tree, parent: key, depth: 1),
    ];
  }

  /// An item, by its type's icon, with its platform and environment at the
  /// trailing edge. Clicking selects it, in the list as it is when the list
  /// shows it, else in its app's. It drags like a list row, and an item
  /// dropped on it moves to its app.
  Widget _itemRow(
    Item item,
    String appKey,
    _TreeContext tree, {
    required String parent,
    required int depth,
  }) {
    final key = 'item:${item.id}';
    void select() {
      final filter = tree.filter;
      final listed =
          tree.shown.contains(item.id) && filter.kind.includes(item, tree.now);
      context.go(
        (listed ? filter : VaultFilter(app: appKey)).location(item: item.id),
      );
    }

    final selected = _selectedItem == item.id;
    _rows.add(
      _NavRow(
        key: key,
        parent: parent,
        label: item.title,
        selected: selected,
        activate: select,
        rename: item.isReadOnly ? null : () => editItem(context, item),
        delete: () => deleteItem(context, ref, item),
      ),
    );
    final row = _itemTarget(
      TreePlace(app: appKey),
      (hover) => _SourceRow(
        menuKey: _menuKey(key),
        focused: _hasCursor(key),
        dropHover: hover,
        menu: itemMenu(context, ref, item),
        tree: true,
        depth: depth,
        icon: item.typeSymbol,
        label: item.title,
        description: [
          if (item.platform case final p?) VaultLabels.platform(p),
          if (item.environment case final e?) VaultLabels.environment(e),
        ].join(', '),
        trailing: _ItemPlace(item),
        selected: selected,
        onTap: _clicked(key, select),
      ),
    );
    return item.isReadOnly
        ? row
        : TreeDraggable<Item>(
            data: item,
            feedback: DragChip(
              label: item.title,
              leading: DesktopIcon(
                item.typeSymbol,
                size: 14,
                color: context.desktopColors.secondaryText,
              ),
            ),
            child: row,
          );
  }

  /// [row], built with whether an item is being dragged over it; dropping
  /// the item moves it to [place]. An item already there, or one this
  /// version can't write, isn't taken.
  Widget _itemTarget(TreePlace place, Widget Function(bool hover) row) =>
      DragTarget<Item>(
        onWillAcceptWithDetails: (d) {
          final session = ref.read(vaultSessionProvider);
          return session is Unlocked &&
              !d.data.isReadOnly &&
              !place.holds(d.data, session.index);
        },
        onAcceptWithDetails: (d) => moveItem(context, ref, d.data, place),
        builder: (context, candidates, _) => row(candidates.isNotEmpty),
      );

  /// [child], which opens with [open] when something dragged is held over
  /// it for a moment while it is [closed], so a drop can go deeper. It
  /// never takes the drop itself: it sits inside the row's own drop
  /// target, and a drag tries the innermost target first.
  Widget _openOnHover(
    String key, {
    required bool closed,
    required VoidCallback open,
    required Widget child,
  }) => DragTarget<Object>(
    onWillAcceptWithDetails: (_) {
      if (closed) {
        _hoverTimer?.cancel();
        _hoverKey = key;
        _hoverTimer = Timer(_openOnHoverDelay, () {
          if (mounted && _hoverKey == key) setState(open);
          _hoverKey = null;
        });
      }
      return false;
    },
    onLeave: (_) {
      if (_hoverKey != key) return;
      _hoverTimer?.cancel();
      _hoverKey = null;
    },
    builder: (context, candidates, rejected) => child,
  );

  GlobalKey<DesktopContextMenuState> _menuKey(String key) =>
      _menuKeys[key] ??= GlobalKey(debugLabel: key);

  /// Whether the keyboard cursor is on [key] and the explorer has focus.
  bool _hasCursor(String key) => _cursor == key && _treeFocus.hasPrimaryFocus;

  /// A click on row [key]: the cursor moves there too, as in a file
  /// explorer, then [action] runs.
  VoidCallback _clicked(String key, VoidCallback action) => () {
    _cursor = key;
    _treeFocus.requestFocus();
    action();
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Not the keys of an open row menu, which sits under the tree.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = _rows;
    if (rows.isEmpty) return KeyEventResult.ignored;
    final at = rows.indexWhere((r) => r.key == _cursor);
    final row = at == -1 ? null : rows[at];
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;

    void moveTo(int i) {
      final next = rows[i.clamp(0, rows.length - 1)];
      setState(() => _cursor = next.key);
      final target = _menuKeys[next.key]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: i > at
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    }

    if (row == null) {
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.end) {
        moveTo(rows.length - 1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.home) {
        moveTo(0);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final command = keyboard.isMetaPressed || keyboard.isControlPressed;
    if (key == LogicalKeyboardKey.arrowDown) {
      moveTo(at + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      moveTo(at - 1);
    } else if (key == LogicalKeyboardKey.home) {
      moveTo(0);
    } else if (key == LogicalKeyboardKey.end) {
      moveTo(rows.length - 1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (row.open == false) {
        row.setOpen!(true);
      } else if (row.open == true &&
          at + 1 < rows.length &&
          rows[at + 1].parent == row.key) {
        moveTo(at + 1);
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (row.open == true) {
        row.setOpen!(false);
      } else if (row.parent case final parent?) {
        moveTo(rows.indexWhere((r) => r.key == parent));
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      row.activate();
    } else if (key == LogicalKeyboardKey.f2) {
      row.rename?.call();
    } else if (key == LogicalKeyboardKey.delete ||
        (key == LogicalKeyboardKey.backspace && keyboard.isMetaPressed)) {
      row.delete?.call();
    } else if (key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 && keyboard.isShiftPressed)) {
      _menuKeys[row.key]?.currentState?.open();
    } else if (event.character case final typed?
        when !command && typed.trim().isNotEmpty) {
      _typeAhead(typed, at, moveTo);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Moves to the next row whose name starts with what was just typed:
  /// from the cursor's row while a name is being typed, after it for a
  /// new first letter, wrapping around.
  void _typeAhead(String typed, int at, void Function(int) moveTo) {
    _typedTimer?.cancel();
    _typedTimer = Timer(_typeAheadPause, () => _typed = '');
    final first = _typed.isEmpty;
    _typed += typed.toLowerCase();
    final rows = _rows;
    for (var n = first ? 1 : 0; n <= rows.length; n++) {
      final i = (at + n) % rows.length;
      if (rows[i].label.toLowerCase().startsWith(_typed)) {
        moveTo(i);
        return;
      }
    }
  }
}

/// How long something dragged is held over a closed row before it opens.
const _openOnHoverDelay = Duration(milliseconds: 700);

/// The pause after which typing starts a new name to jump to.
const _typeAheadPause = Duration(seconds: 1);

/// One explorer row, as the keyboard sees it.
class _NavRow {
  const _NavRow({
    required this.key,
    required this.label,
    required this.selected,
    required this.activate,
    this.parent,
    this.open,
    this.setOpen,
    this.rename,
    this.delete,
  });

  /// `org:…`, `app:…` or `item:…`.
  final String key;
  final String label;
  final bool selected;

  /// The row it's under, for ←.
  final String? parent;

  /// Whether it's open; null for rows that don't open.
  final bool? open;
  final ValueChanged<bool>? setOpen;

  /// What clicking it does: list or select it.
  final VoidCallback activate;

  /// F2 and Delete; null where there's nothing to rename or delete.
  final VoidCallback? rename;
  final VoidCallback? delete;
}

/// What the explorer's rows need from one build.
class _TreeContext {
  const _TreeContext({
    required this.index,
    required this.filter,
    required this.now,
    required this.openApp,
    required this.shown,
  });

  final VaultIndex index;
  final VaultFilter filter;
  final DateTime now;

  /// The app (or "No app") that holds the selection, open unless closed.
  final String? openApp;

  /// The ids the list shows before its tab narrows them.
  final Set<String> shown;
}

/// An item's platform symbol and environment dot, when it has them.
class _ItemPlace extends StatelessWidget {
  const _ItemPlace(this.item);

  final Item item;

  static DesktopSymbol _platformSymbol(String platform) => switch (platform) {
    'ios' || 'macos' => DesktopSymbol.platformApple,
    'android' => DesktopSymbol.platformAndroid,
    'web' => DesktopSymbol.platformWeb,
    'server' => DesktopSymbol.platformServer,
    'windows' || 'linux' => DesktopSymbol.platformDesktop,
    _ => DesktopSymbol.platformOther,
  };

  @override
  Widget build(BuildContext context) {
    final platform = item.platform;
    final env = item.environment;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        if (platform != null)
          DesktopIcon(
            _platformSymbol(platform),
            size: 11,
            color: context.desktopColors.tertiaryText,
          ),
        if (env != null) _EnvDot(env),
      ],
    );
  }
}

/// The vault this window shows, with its size. One vault per device in
/// v1, so there's nothing to switch to yet.
class _VaultHeader extends StatelessWidget {
  const _VaultHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        spacing: 10,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: const BorderRadius.all(
                Radius.circular(DesktopMetrics.menuRadius),
              ),
            ),
            child: SizedBox.square(
              dimension: 28,
              child: DesktopIcon(
                DesktopSymbol.lock,
                size: 15,
                color: colors.onAccent,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DevVault',
                  style: TextStyle(
                    fontSize: DesktopMetrics.bodySize,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                Text(
                  '$count ${count == 1 ? 'item' : 'items'} · this device',
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One source-list row: a disclosure chevron on tree rows that open, an
/// icon (or [leading]), the label and a count. The selected row is filled
/// with the accent colour.
class _SourceRow extends StatefulWidget {
  const _SourceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.icon,
    this.iconColor,
    this.leading,
    this.tree = false,
    this.depth = 0,
    this.expanded = false,
    this.onToggle,
    this.menu = const [],
    this.dropHover = false,
    this.description,
    this.trailing,
    this.focused = false,
    this.menuKey,
  });

  final DesktopSymbol? icon;
  final Color? iconColor;
  final Widget? leading;
  final String label;

  /// Shown at the trailing edge; null shows nothing.
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  /// A row of the (Organization ›) App › Item tree, [depth] levels deep.
  final bool tree;
  final int depth;
  final bool expanded;

  /// Set on tree rows that open and close.
  final VoidCallback? onToggle;

  /// The row's context menu; empty for none.
  final List<DesktopMenuAction> menu;

  /// Something dragged over the row would be taken if dropped: the row is
  /// outlined in the accent colour.
  final bool dropHover;

  /// Said after the label to screen readers (an item's platform and
  /// environment, which [trailing] shows as symbols).
  final String? description;

  /// Shown at the trailing edge instead of a count.
  final Widget? trailing;

  /// The keyboard cursor is on it: a focus ring in the accent colour.
  final bool focused;

  /// Opens [menu] from the keyboard.
  final GlobalKey<DesktopContextMenuState>? menuKey;

  @override
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final selected = widget.selected;
    final icon = widget.icon;
    final onToggle = widget.onToggle;
    final count = widget.count;
    final tree = widget.tree;
    final countLabel = count == null
        ? ''
        : ', $count ${count == 1 ? 'item' : 'items'}';
    return Semantics(
      button: true,
      selected: selected,
      expanded: onToggle == null ? null : widget.expanded,
      label: [
        tree ? '${widget.label}$countLabel' : widget.label,
        if (widget.description case final d? when d.isNotEmpty) d,
      ].join(', '),
      onTap: widget.onTap,
      excludeSemantics: true,
      child: DesktopContextMenu(
        key: widget.menuKey,
        actions: widget.menu,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Container(
              height: DesktopMetrics.sidebarRowHeight,
              padding: EdgeInsets.only(
                left: tree ? 2.0 + widget.depth * 14 : 6,
                right: 8,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? colors.selection
                    : _hovered || widget.dropHover
                    ? colors.innerSeparator
                    : null,
                borderRadius: const BorderRadius.all(
                  Radius.circular(DesktopMetrics.menuRadius),
                ),
              ),
              // Drawn over the row, so the ring doesn't move its content.
              foregroundDecoration:
                  widget.dropHover || (widget.focused && !selected)
                  ? BoxDecoration(
                      border: Border.all(color: colors.accent, width: 2),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(DesktopMetrics.menuRadius),
                      ),
                    )
                  : null,
              child: Row(
                spacing: 6,
                children: [
                  // Tree rows keep the chevron's column, so labels line up
                  // by depth whether or not the row opens.
                  if (tree)
                    SizedBox(
                      width: 12,
                      child: onToggle == null
                          ? null
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onToggle,
                              child: DesktopIcon(
                                widget.expanded
                                    ? DesktopSymbol.chevronDown
                                    : DesktopSymbol.chevronRight,
                                size: 10,
                                color: selected
                                    ? colors.onSelection
                                    : colors.tertiaryText,
                              ),
                            ),
                    ),
                  SizedBox(
                    width: 16,
                    child: Center(
                      child:
                          widget.leading ??
                          (icon == null
                              ? null
                              : DesktopIcon(
                                  icon,
                                  size: 14,
                                  color: selected
                                      ? colors.onSelection
                                      : widget.iconColor ??
                                            colors.secondaryText,
                                )),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesktopMetrics.bodySize,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected ? colors.onSelection : colors.text,
                      ),
                    ),
                  ),
                  if (widget.trailing case final trailing?)
                    trailing
                  else if (count != null)
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: DesktopMetrics.secondarySize,
                        color: selected
                            ? colors.onSelection
                            : colors.secondaryText,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The environment's colour: production green, staging amber, development
/// blue, anything else grey.
class _EnvDot extends StatelessWidget {
  const _EnvDot(this.environment);

  final String? environment;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final color = switch (environment?.toLowerCase()) {
      'production' || 'prod' => colors.success,
      'staging' => colors.warning,
      'development' || 'dev' => colors.accentIcon,
      _ => colors.tertiaryText,
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 7),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.action, this.menu = const []});

  final String text;
  final Widget? action;

  /// The section's context menu; empty for none.
  final List<DesktopMenuAction> menu;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 2, 2),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            Expanded(
              child: DesktopContextMenu(
                actions: menu,
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
            if (action != null)
              SizedBox.square(
                dimension: 24,
                child: Semantics(container: true, child: action),
              ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: DesktopMetrics.secondarySize,
          color: context.desktopColors.secondaryText,
        ),
      ),
    );
  }
}

/// Settings, and how long the vault stays open while idle.
class _Footer extends ConsumerWidget {
  const _Footer({required this.selected});

  final bool selected;

  /// "1m", "5m", "1h"; "Off" when idle never locks.
  static String _lockLabel(Duration? after) => switch (after) {
    null => 'Off',
    Duration(inMinutes: final m) when m < 60 => '${m}m',
    Duration(:final inHours) => '${inHours}h',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.desktopColors;
    final after = ref.watch(settingsProvider.select((s) => s.autoLockAfter));
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: _SourceRow(
              icon: DesktopSymbol.settings,
              label: 'Settings',
              selected: selected,
              onTap: () => context.go(Routes.settings),
            ),
          ),
          Semantics(
            label: after == null
                ? 'Auto-lock is off'
                : 'Locks after ${_lockLabel(after)} idle',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 6),
              child: Row(
                spacing: 3,
                children: [
                  DesktopIcon(DesktopSymbol.timer, size: 11),
                  Text(
                    _lockLabel(after),
                    style: TextStyle(
                      fontSize: DesktopMetrics.secondarySize,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
