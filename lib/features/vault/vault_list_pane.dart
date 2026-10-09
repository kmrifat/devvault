import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/expiry.dart';
import '../../data/providers.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart';
import '../../shared/widgets/markdown_note.dart' show MarkdownNote;
import '../../shared/widgets/mono_text.dart';
import '../notes/notes.dart' show NoteView;
import 'desktop_item_type.dart';
import 'tree_drag.dart';
import 'vault_actions.dart';

/// Design frame N03's item table: what the sidebar selected, narrowed by
/// the All / Expiring / Files / Secrets scope bar and the search, sortable by
/// Name, Type and Expires, with the selected row filled with the accent.
/// Its title, path and count are in the window's toolbar.
///
/// Like the sidebar, it reads everything from [uri] and changes it by
/// navigating, so the selection is a link. Only the sort order is the
/// table's own.
///
/// Beyond the frame it keeps the kind filter (as a scope bar), the selected app's details
/// (store IDs, Edit app…, Delete app…), the Unreadable list and the empty
/// states. Files are imported by dropping them anywhere on the window.
class VaultListPane extends ConsumerStatefulWidget {
  const VaultListPane({super.key, required this.uri});

  final Uri uri;

  @override
  ConsumerState<VaultListPane> createState() => _VaultListPaneState();
}

/// The table's columns, which are also what it sorts by.
enum VaultColumn {
  name('Name'),
  type('Type'),
  expires('Expires');

  const VaultColumn(this.label);

  final String label;
}

class _VaultListPaneState extends ConsumerState<VaultListPane> {
  var _sortBy = VaultColumn.name;
  var _ascending = true;

  /// Clicking the sorted column reverses it; another column sorts by it,
  /// ascending.
  void _sort(VaultColumn column) => setState(() {
    _ascending = column == _sortBy ? !_ascending : true;
    _sortBy = column;
  });

  /// [items] (already in title order) sorted by the chosen column; ties
  /// keep title order. Undated items come after dated ones either way.
  List<Item> _sorted(List<Item> items) {
    if (_sortBy == VaultColumn.name) {
      return _ascending ? items : items.reversed.toList();
    }
    final order = {for (final (i, item) in items.indexed) item.id: i};
    int byKey(Item a, Item b) => switch (_sortBy) {
      VaultColumn.type => a.shortTypeLabel.toLowerCase().compareTo(
        b.shortTypeLabel.toLowerCase(),
      ),
      _ => switch ((a.expiresAt, b.expiresAt)) {
        (null, null) => 0,
        (null, _) => _ascending ? 1 : -1,
        (_, null) => _ascending ? -1 : 1,
        (final x?, final y?) => x.compareTo(y),
      },
    };
    return [...items]..sort((a, b) {
      final key = byKey(a, b) * (_ascending ? 1 : -1);
      return key != 0 ? key : order[a.id]!.compareTo(order[b.id]!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    if (session is! Unlocked) return const SizedBox.shrink();
    final index = session.index;
    final now = ref.watch(clockProvider)();
    final filter = VaultFilter.fromUri(widget.uri);
    final selected = widget.uri.queryParameters['item'];
    final shown = [
      for (final item in filter.apply(index))
        if (filter.kind.includes(item, now)) item,
    ];
    final quarantine = filter.view == VaultView.quarantine;
    final app = _selectedApp(filter, index);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (app != null)
          _AppDetails(
            app: app,
            itemCount: index.items.values
                .where((i) => i.appId == app.id)
                .length,
          ),
        if (!quarantine)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Center(
              child: DesktopScopeBar<VaultKind>(
                value: filter.kind,
                onChanged: (kind) =>
                    context.go(filter.withKind(kind).location(item: selected)),
                choices: [
                  for (final kind in VaultKind.values)
                    DesktopChoice(kind, kind.label),
                ],
              ),
            ),
          ),
        Expanded(
          child: quarantine
              ? _QuarantineList(slots: index.quarantined)
              : shown.isEmpty
              ? _Empty(filter: filter, vaultEmpty: index.items.isEmpty)
              : _ItemTable(
                  items: _sorted(shown),
                  sortBy: _sortBy,
                  ascending: _ascending,
                  onSort: _sort,
                  selected: selected,
                  now: now,
                  onSelect: (item) =>
                      context.go(filter.location(item: item.id)),
                ),
        ),
      ],
    );
  }
}

/// The app the sidebar selected, when it selected just an app.
AppRecord? _selectedApp(VaultFilter filter, VaultIndex index) =>
    filter.platform == null &&
        filter.env == null &&
        filter.tag == null &&
        filter.view == null
    ? index.apps[filter.app]
    : null;

/// The selected app's organization and kind, when set, over its
/// identifiers (bundle IDs, package names, domains, URLs, repositories …),
/// with Edit app… and, under ⋯, Delete app…. The app's notes, when it has
/// any, fold out under them.
class _AppDetails extends ConsumerWidget {
  const _AppDetails({required this.app, required this.itemCount});

  final AppRecord app;
  final int itemCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.desktopColors;
    final ids = [for (final id in app.allIdentifiers) id.value];
    final about = [
      ?app.organization,
      if (app.kindName case final kind?)
        AppKind.fromWireName(kind)?.label ?? kind,
    ].join(' · ');
    final style = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.innerSeparator, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            _detailsRow(context, ref, about, ids, style),
            if (app.notes case final notes?)
              _AppNotes(key: ValueKey(app.id), notes: notes),
          ],
        ),
      ),
    );
  }

  Widget _detailsRow(
    BuildContext context,
    WidgetRef ref,
    String about,
    List<String> ids,
    TextStyle style,
  ) {
    final colors = context.desktopColors;
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              if (about.isNotEmpty)
                Text(
                  about,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(color: colors.text),
                ),
              if (ids.isEmpty)
                Text(
                  'No identifiers',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                )
              else
                MonoText(ids.join(' · '), middleEllipsis: true, style: style),
            ],
          ),
        ),
        DesktopButton(
          label: 'Edit app…',
          onPressed: () => editApp(context, app),
        ),
        DesktopPullDownButton(
          label: 'App actions',
          actions: [
            DesktopMenuAction(
              'Delete app…',
              () => deleteApp(context, ref, app, itemCount: itemCount),
              destructive: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// An app's notes over the item table: folded to their first line, or
/// shown in full (scrolling past a few lines), rendered as Markdown.
class _AppNotes extends StatefulWidget {
  const _AppNotes({super.key, required this.notes});

  final String notes;

  @override
  State<_AppNotes> createState() => _AppNotesState();
}

class _AppNotesState extends State<_AppNotes> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final style = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Row(
          spacing: 4,
          children: [
            DesktopIconButton(
              symbol: _open
                  ? DesktopSymbol.chevronDown
                  : DesktopSymbol.chevronRight,
              tooltip: _open ? 'Hide notes' : 'Show notes',
              size: 12,
              onPressed: () => setState(() => _open = !_open),
            ),
            Text('Notes', style: style.copyWith(fontWeight: FontWeight.w600)),
            if (!_open)
              Expanded(
                child: Text(
                  MarkdownNote.firstLine(widget.notes),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
          ],
        ),
        if (_open)
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: DesktopMetrics.notesPreviewMaxHeight,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
              child: NoteView(widget.notes),
            ),
          ),
      ],
    );
  }
}

/// The item table: a header that sorts, then one 40 pt row per item,
/// built lazily. Once a row is clicked the table has focus, and ↑/↓ move
/// the selection, scrolling it into view.
class _ItemTable extends StatefulWidget {
  const _ItemTable({
    required this.items,
    required this.sortBy,
    required this.ascending,
    required this.onSort,
    required this.selected,
    required this.now,
    required this.onSelect,
  });

  final List<Item> items;
  final VaultColumn sortBy;
  final bool ascending;
  final ValueChanged<VaultColumn> onSort;
  final String? selected;
  final DateTime now;
  final ValueChanged<Item> onSelect;

  @override
  State<_ItemTable> createState() => _ItemTableState();
}

class _ItemTableState extends State<_ItemTable> {
  final _focus = FocusNode(debugLabel: 'Vault table');
  final _scroll = ScrollController();

  /// Set by an arrow key, so only keyboard moves scroll the table; a link
  /// or click leaves it where it is.
  bool _moved = false;

  @override
  void didUpdateWidget(_ItemTable old) {
    super.didUpdateWidget(old);
    if (old.selected == widget.selected || !_moved) return;
    _moved = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  /// Scrolls just enough to show the selected row.
  void _reveal() {
    final at = widget.items.indexWhere((i) => i.id == widget.selected);
    if (at == -1 || !_scroll.hasClients) return;
    final position = _scroll.position;
    const extent = DesktopMetrics.tableRowHeight;
    final top = at * extent;
    final bottom = top + extent;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(bottom - position.viewportDimension);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _move(int by) {
    final items = widget.items;
    final at = items.indexWhere((i) => i.id == widget.selected);
    final next = at == -1
        ? (by > 0 ? 0 : items.length - 1)
        : (at + by).clamp(0, items.length - 1);
    if (next == at) return;
    _moved = true;
    widget.onSelect(items[next]);
  }

  /// [row], which drags [item] to a sidebar row to move it there. An item
  /// this version can't write stays put.
  Widget _draggable(Item item, Widget row) => item.isReadOnly
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

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          sortBy: widget.sortBy,
          ascending: widget.ascending,
          onSort: widget.onSort,
        ),
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1),
            },
            child: Focus(
              focusNode: _focus,
              child: ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.zero,
                itemExtent: DesktopMetrics.tableRowHeight,
                itemCount: items.length,
                itemBuilder: (_, i) => _draggable(
                  items[i],
                  VaultTableRow(
                    item: items[i],
                    zebra: i.isOdd,
                    selected: items[i].id == widget.selected,
                    now: widget.now,
                    onTap: () {
                      _focus.requestFocus();
                      widget.onSelect(items[i]);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lays out a header or row: the name, then the fixed Type and Expires
/// columns.
Widget _columns({
  required Widget name,
  required Widget type,
  required Widget expires,
}) => Padding(
  padding: const EdgeInsets.only(left: 12, right: 4),
  child: Row(
    children: [
      Expanded(child: name),
      const SizedBox(width: 8),
      SizedBox(width: DesktopMetrics.tableTypeColumnWidth, child: type),
      SizedBox(width: DesktopMetrics.tableExpiresColumnWidth, child: expires),
    ],
  ),
);

/// The table header: a sort button per column, the sorted one with an
/// arrow for its direction.
class _Header extends StatelessWidget {
  const _Header({
    required this.sortBy,
    required this.ascending,
    required this.onSort,
  });

  final VaultColumn sortBy;
  final bool ascending;
  final ValueChanged<VaultColumn> onSort;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    Widget cell(VaultColumn column) {
      final sorted = column == sortBy;
      return Semantics(
        button: true,
        label: column.label,
        value: sorted
            ? (ascending ? 'sorted ascending' : 'sorted descending')
            : null,
        onTap: () => onSort(column),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSort(column),
          child: SizedBox(
            height: DesktopMetrics.tableHeaderHeight,
            child: Row(
              spacing: 3,
              children: [
                Flexible(
                  child: Text(
                    column.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DesktopMetrics.secondarySize,
                      fontWeight: FontWeight.w600,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
                if (sorted)
                  DesktopIcon(
                    ascending
                        ? DesktopSymbol.sortAscending
                        : DesktopSymbol.sortDescending,
                    size: 10,
                    color: colors.secondaryText,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bar,
        border: Border(
          bottom: BorderSide(color: colors.innerSeparator, width: 0.5),
        ),
      ),
      child: _columns(
        name: cell(VaultColumn.name),
        type: cell(VaultColumn.type),
        expires: cell(VaultColumn.expires),
      ),
    );
  }
}

/// One item in the table: its type icon, title and file name (or type),
/// the type, and when it expires: a badge when that needs attention, the
/// month otherwise. A conflict shows instead of the expiry.
class VaultTableRow extends StatelessWidget {
  const VaultTableRow({
    super.key,
    required this.item,
    required this.zebra,
    required this.selected,
    required this.now,
    required this.onTap,
  });

  final Item item;

  /// Every other row is shaded.
  final bool zebra;
  final bool selected;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final file = item.attachments.firstOrNull?.filename;
    final text = selected ? colors.onAccent : colors.text;
    final secondary = selected ? colors.onAccent : colors.secondaryText;
    final small = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: secondary,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: '${item.title}, ${item.typeLabel}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ColoredBox(
          color: selected
              ? colors.accent
              : zebra
              ? colors.zebra
              : colors.window,
          child: _columns(
            name: Row(
              spacing: 7,
              children: [
                SizedBox(
                  width: 16,
                  child: DesktopIcon(
                    item.typeSymbol,
                    size: 14,
                    color: secondary,
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DesktopMetrics.bodySize,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: text,
                        ),
                      ),
                      if (file != null)
                        MonoText(file, middleEllipsis: true, style: small)
                      else
                        Text(
                          item.typeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            type: Text(
              item.shortTypeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small,
            ),
            expires: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _expires(colors, small),
            ),
          ),
        ),
      ),
    );
  }

  /// A conflict first, then the expiry.
  Widget _expires(DesktopColors colors, TextStyle style) {
    if (item.conflict != null) {
      return ItemBadge(
        'Conflict',
        background: colors.conflictBadge,
        foreground: colors.onConflictBadge,
      );
    }
    final expiresAt = item.expiresAt;
    return switch (ExpiryState.of(item, now)) {
      ExpiryState.none => ExcludeSemantics(child: Text('—', style: style)),
      ExpiryState.expired => ItemBadge(
        'Expired',
        background: colors.dangerBadge,
        foreground: colors.onDangerBadge,
      ),
      ExpiryState.soon => ItemBadge(
        daysLeft(expiresAt!, now),
        background: colors.warningBadge,
        foreground: colors.onWarningBadge,
      ),
      ExpiryState.valid => Text(
        DateFormat.yMMM().format(expiresAt!.toLocal()),
        maxLines: 1,
        style: style,
      ),
    };
  }
}

/// A small status pill in the table: days left, Expired, Conflict.
class ItemBadge extends StatelessWidget {
  const ItemBadge(
    this.label, {
    super.key,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.tokenRadius),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: DesktopMetrics.secondarySize,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

/// Objects that failed to decrypt or parse. They stay on disk untouched;
/// another device or a backup may still have a good copy.
class _QuarantineList extends StatelessWidget {
  const _QuarantineList({required this.slots});

  final List<ObjectSlot> slots;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    if (slots.isEmpty) {
      return const _Message(
        symbol: DesktopSymbol.check,
        title: 'Everything is readable',
      );
    }
    final small = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            "These couldn't be decrypted on this device. They're left as they "
            'are on disk; another device or a backup may hold a good copy.',
            style: small,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.innerSeparator, width: 0.5),
            ),
          ),
          child: const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemExtent: DesktopMetrics.tableRowHeight,
            itemCount: slots.length,
            itemBuilder: (_, i) => ColoredBox(
              color: i.isOdd ? colors.zebra : colors.window,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  spacing: 7,
                  children: [
                    SizedBox(
                      width: 16,
                      child: DesktopIcon(
                        DesktopSymbol.unreadable,
                        size: 14,
                        color: colors.danger,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unreadable ${slots[i].type.wireName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: DesktopMetrics.bodySize,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              color: colors.text,
                            ),
                          ),
                          MonoText(
                            slots[i].objectId,
                            middleEllipsis: true,
                            style: small,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter, required this.vaultEmpty});

  final VaultFilter filter;
  final bool vaultEmpty;

  @override
  Widget build(BuildContext context) {
    final q = filter.q;
    if (vaultEmpty && q == null) {
      return _Message(
        symbol: DesktopSymbol.importFile,
        title: 'Your vault is empty',
        description:
            'Import a credential file, or drop one anywhere on this window.',
        action: DesktopButton(
          label: 'Import',
          kind: DesktopButtonKind.primary,
          onPressed: () => openImport(context),
        ),
      );
    }
    if (q != null) {
      return _Message(
        symbol: DesktopSymbol.search,
        title: 'No matches',
        description: 'Nothing here matches “$q”.',
      );
    }
    return const _Message(
      symbol: DesktopSymbol.allItems,
      title: 'Nothing here',
    );
  }
}

/// A centred icon, title, description and optional action, for empty
/// lists.
class _Message extends StatelessWidget {
  const _Message({
    required this.symbol,
    required this.title,
    this.description,
    this.action,
  });

  final DesktopSymbol symbol;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final description = this.description;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            DesktopIcon(symbol, size: 28, color: colors.secondaryText),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DesktopMetrics.bodySize,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
            if (description != null)
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize,
                  color: colors.secondaryText,
                ),
              ),
            if (action != null) ...[const SizedBox(height: 6), action!],
          ],
        ),
      ),
    );
  }
}
