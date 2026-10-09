import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/expiry.dart';
import '../../data/vault_filter.dart' show VaultLabels;
import '../../shared/desktop_ui.dart';
import '../../shared/widgets/provenance_label.dart' show ProvenanceLabel;
import 'expiry_screen.dart' show ExpiryGroups;

/// The expiry dashboard on desktop (design frame N06): one table, grouped
/// into Expired, Within 30 days and Later, with where each item lives and
/// where its date came from, then a count of the items with no expiry.
///
/// A row opens its item in the vault ([onOpen]). [onlyExpired] narrows it
/// to the Expired group (the sidebar's "Expired" row), with [onShowAll] to
/// widen it again.
class DesktopExpiryTable extends StatelessWidget {
  const DesktopExpiryTable({
    super.key,
    required this.groups,
    required this.apps,
    required this.now,
    required this.empty,
    required this.onlyExpired,
    required this.onOpen,
    required this.onShowAll,
    required this.onShowNoExpiry,
  });

  final ExpiryGroups groups;
  final Map<String, AppRecord> apps;
  final DateTime now;

  /// The vault holds no items at all.
  final bool empty;
  final bool onlyExpired;
  final ValueChanged<Item> onOpen;
  final VoidCallback onShowAll;
  final VoidCallback onShowNoExpiry;

  /// Time left as the Left column says it: "12 days", "5 months",
  /// "today", or "3 days ago" once it has passed.
  static String left(DateTime expiresAt, DateTime now) {
    final past = !expiresAt.isAfter(now);
    final span = past ? now.difference(expiresAt) : expiresAt.difference(now);
    final days = (span.inMinutes / (24 * 60)).ceil();
    final text = switch (days) {
      >= 730 => '${days ~/ 365} years',
      >= 60 => '${days ~/ 30} months',
      1 => '1 day',
      0 => 'today',
      _ => '$days days',
    };
    if (days == 0) return text;
    return past ? '$text ago' : text;
  }

  /// The window's status bar under this table: "6 dated · 36 without a
  /// date", or "1 expired" when [onlyExpired].
  static String status(ExpiryGroups groups, {required bool onlyExpired}) {
    if (onlyExpired) return '${groups.expired.length} expired';
    final dated =
        groups.expired.length + groups.soon.length + groups.later.length;
    return '$dated dated · ${groups.noExpiry} without a date';
  }

  /// The status bar's reminder state, from the Expiry reminders setting.
  static String reminders({required bool on}) =>
      on ? 'Reminders on · at most two per item' : 'Reminders off';

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    if (empty) return const _EmptyVault();

    final sections = <Widget>[
      if (!onlyExpired && groups.expired.isEmpty && groups.soon.isEmpty)
        const _AllClear(),
      if (groups.expired.isNotEmpty || onlyExpired)
        ..._group(
          _Group.expired,
          groups.expired,
          empty: 'Nothing has expired.',
        ),
      if (!onlyExpired) ...[
        ..._group(_Group.soon, groups.soon),
        ..._group(_Group.later, groups.later),
      ],
    ];

    return ColoredBox(
      color: colors.window,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onlyExpired) _FilterBar(onShowAll: onShowAll),
          const _HeaderRow(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...sections,
                if (!onlyExpired && groups.noExpiry > 0)
                  _NoExpiry(count: groups.noExpiry, onPressed: onShowNoExpiry),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A group's band, then its rows in alternating shades.
  List<Widget> _group(
    _Group group,
    List<(Item, ExpiryStatus)> entries, {
    String? empty,
  }) {
    if (entries.isEmpty && empty == null) return const [];
    return [
      _GroupBand(group: group, count: entries.length),
      if (entries.isEmpty)
        _MessageRow(empty!)
      else
        for (final (i, (item, status)) in entries.indexed)
          _ExpiryRow(
            item: item,
            status: status,
            where: _where(item),
            left: left(status.expiresAt!, now),
            group: group,
            zebra: i.isOdd,
            onTap: () => onOpen(item),
          ),
    ];
  }

  /// "Kitchenly › iOS": the item's app and platform, as far as it has them.
  String _where(Item item) => [
    ?apps[item.appId]?.name,
    if (item.platform != null) VaultLabels.platform(item.platform),
  ].join(' › ');
}

enum _Group {
  expired('Expired', DesktopSymbol.expired),
  soon('Within 30 days', DesktopSymbol.expiring),
  later('Later', DesktopSymbol.calendar);

  const _Group(this.title, this.symbol);

  final String title;
  final DesktopSymbol symbol;
}

/// The table's columns: Name and Date from share what's left, two to
/// one; the rest are fixed.
abstract final class _Columns {
  static const double type = 170;
  static const double where = 170;
  static const double expires = 120;
  static const double left = 110;
  static const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 16);

  static Widget row(List<Widget> cells) {
    Widget fixed(double width, Widget child) =>
        SizedBox(width: width, child: child);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(flex: 2, child: cells[0]),
          const SizedBox(width: 12),
          fixed(type, cells[1]),
          fixed(where, cells[2]),
          fixed(expires, cells[3]),
          fixed(left, cells[4]),
          Expanded(child: cells[5]),
        ],
      ),
    );
  }
}

/// One line of cell text, cut with an ellipsis.
class _Cell extends StatelessWidget {
  const _Cell(this.text, {required this.style});

  final String text;
  final TextStyle style;

  // Aligned rather than stretched, so the text is only as wide as it is.
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    ),
  );
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final style = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      fontWeight: FontWeight.w500,
      color: colors.secondaryText,
    );
    Widget cell(String text) => _Cell(text, style: style);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bar,
        border: Border(bottom: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: SizedBox(
        height: DesktopMetrics.tableHeaderHeight,
        child: _Columns.row([
          cell('Name'),
          cell('Type'),
          cell('Where'),
          // Soonest first: the order the rows are in, with the item
          // table's sort symbol (not a glyph the OS font may lack).
          Semantics(
            label: 'Expires, soonest first',
            excludeSemantics: true,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 3,
                children: [
                  Flexible(
                    child: Text(
                      'Expires',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  DesktopIcon(
                    DesktopSymbol.sortAscending,
                    size: 10,
                    color: colors.secondaryText,
                  ),
                ],
              ),
            ),
          ),
          cell('Left'),
          cell('Date from'),
        ]),
      ),
    );
  }
}

/// "Showing expired items only", with Show All.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.onShowAll});

  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(
          bottom: BorderSide(color: colors.innerSeparator, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Showing expired items only.',
                style: TextStyle(
                  fontSize: DesktopMetrics.cellSize,
                  color: colors.secondaryText,
                ),
              ),
            ),
            DesktopButton(label: 'Show All', onPressed: onShowAll),
          ],
        ),
      ),
    );
  }
}

/// A group's heading band: "⊗ Expired · 1", tinted by how urgent it is.
class _GroupBand extends StatelessWidget {
  const _GroupBand({required this.group, required this.count});

  final _Group group;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final (fill, ink) = switch (group) {
      _Group.expired => (colors.dangerBadge, colors.danger),
      _Group.soon => (colors.warningBadge, colors.onWarningBadge),
      _Group.later => (colors.zebra, colors.text),
    };
    return Semantics(
      header: true,
      label: '${group.title}, $count ${count == 1 ? 'item' : 'items'}',
      excludeSemantics: true,
      child: ColoredBox(
        color: fill,
        child: SizedBox(
          height: DesktopMetrics.tableHeaderHeight + 2,
          child: Padding(
            padding: _Columns.padding,
            child: Row(
              spacing: 6,
              children: [
                DesktopIcon(group.symbol, size: 12, color: ink),
                Text(
                  '${group.title} · $count',
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One item: name, type, where it lives, when it expires, how long is
/// left and where the date came from. The whole row opens the item.
class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({
    required this.item,
    required this.status,
    required this.where,
    required this.left,
    required this.group,
    required this.zebra,
    required this.onTap,
  });

  final Item item;
  final ExpiryStatus status;
  final String where;
  final String left;
  final _Group group;
  final bool zebra;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final type = item.type ?? ItemType.genericFile;
    final expiresAt = status.expiresAt!;
    final date = DateFormat('d MMM y').format(expiresAt.toLocal());
    final source = ProvenanceLabel.textFor(status.source);
    final expired = status.state == ExpiryState.expired;
    final secondary = TextStyle(
      fontSize: DesktopMetrics.cellSize,
      color: colors.secondaryText,
    );
    final leftStyle = switch (group) {
      _Group.expired => secondary.copyWith(
        color: colors.danger,
        fontWeight: FontWeight.w600,
      ),
      _Group.soon => secondary.copyWith(
        color: colors.onWarningBadge,
        fontWeight: FontWeight.w600,
      ),
      _Group.later => secondary,
    };
    return Semantics(
      button: true,
      label:
          '${item.title}, ${type.label}, '
          '${where.isEmpty ? '' : '$where, '}'
          '${expired ? 'expired' : 'expires'} $date, $left, '
          '${source.toLowerCase()}',
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ColoredBox(
            color: zebra ? colors.zebra : colors.window,
            child: SizedBox(
              height: DesktopMetrics.expiryRowHeight,
              child: _Columns.row([
                _Cell(
                  item.title,
                  style: TextStyle(
                    fontSize: DesktopMetrics.bodySize,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                _Cell(type.label, style: secondary),
                _Cell(where, style: secondary),
                _Cell(date, style: secondary.copyWith(color: colors.text)),
                _Cell(left, style: leftStyle),
                _Cell(source, style: secondary),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of secondary text in the table (an empty group).
class _MessageRow extends StatelessWidget {
  const _MessageRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return SizedBox(
      height: DesktopMetrics.expiryRowHeight,
      child: Padding(
        padding: _Columns.padding,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            text,
            style: TextStyle(
              fontSize: DesktopMetrics.cellSize,
              color: colors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

/// Nothing expired or due within 30 days.
class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return SizedBox(
      height: DesktopMetrics.expiryRowHeight,
      child: Padding(
        padding: _Columns.padding,
        child: Row(
          spacing: 6,
          children: [
            DesktopIcon(DesktopSymbol.success, size: 13, color: colors.success),
            Text(
              'Nothing expired or expiring in the next 30 days.',
              style: TextStyle(
                fontSize: DesktopMetrics.cellSize,
                color: colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The items with no expiry date: a count, since there's no date to list.
/// It opens the vault, where they are.
class _NoExpiry extends StatelessWidget {
  const _NoExpiry({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final text =
        'No expiry · ${count == 1 ? '1 item' : '$count items'}. Nothing in '
        '${count == 1 ? 'its file gives' : 'their files gives'} a date, and '
        'none was entered.';
    return Semantics(
      button: true,
      label: text,
      onTap: onPressed,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.innerSeparator, width: 0.5),
              ),
            ),
            child: SizedBox(
              height: DesktopMetrics.expiryRowHeight,
              child: Padding(
                padding: _Columns.padding,
                child: Row(
                  spacing: 6,
                  children: [
                    DesktopIcon(DesktopSymbol.noExpiry, size: 13),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DesktopMetrics.cellSize,
                          color: colors.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An empty vault: what will show up here.
class _EmptyVault extends StatelessWidget {
  const _EmptyVault();

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return ColoredBox(
      color: colors.window,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              DesktopIcon(DesktopSymbol.calendar, size: 28),
              const SizedBox(height: 4),
              Text(
                'Nothing to track yet',
                style: TextStyle(
                  fontSize: DesktopMetrics.bodySize,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
              Text(
                'Import a certificate, profile or keystore and its expiry '
                'date shows up here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: DesktopMetrics.cellSize,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
