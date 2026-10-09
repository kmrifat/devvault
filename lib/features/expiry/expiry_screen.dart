import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../core/expiry.dart';
import '../../data/providers.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop/desktop_theme.dart' show DesktopTheme;
import '../../shared/ui.dart';
import 'desktop_expiry_table.dart';

/// What the expiry dashboard shows, worked out from the vault's items:
/// expired, expiring within the window, later, and how many items have no
/// expiry date (a count only: there is nothing to list about them).
class ExpiryGroups {
  ExpiryGroups(Iterable<Item> items, DateTime now) {
    for (final item in items) {
      final status = ExpiryStatus.of(item, now);
      switch (status.state) {
        case ExpiryState.expired:
          expired.add((item, status));
        case ExpiryState.soon:
          soon.add((item, status));
        case ExpiryState.valid:
          later.add((item, status));
        case ExpiryState.none:
          noExpiry++;
      }
    }
    // Soonest first everywhere, so the longest-expired item leads.
    for (final group in [expired, soon, later]) {
      group.sort((a, b) => a.$2.expiresAt!.compareTo(b.$2.expiresAt!));
    }
  }

  final expired = <(Item, ExpiryStatus)>[];
  final soon = <(Item, ExpiryStatus)>[];
  final later = <(Item, ExpiryStatus)>[];
  int noExpiry = 0;
}

/// The expiry dashboard: a grouped table on desktop (design frame N06,
/// [DesktopExpiryTable]), the Expiry tab on phones. `?show=expired`
/// narrows it to the expired items, which is where the sidebar's "Expired"
/// row lands.
class ExpiryScreen extends ConsumerWidget {
  const ExpiryScreen({super.key, required this.uri, required this.desktop});

  final Uri uri;

  /// Items open in the vault's detail pane on desktop, as their own screen
  /// on phones.
  final bool desktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bc = context.bcTheme;
    final now = ref.watch(clockProvider)();
    final session = ref.watch(vaultSessionProvider);
    final items = session is Unlocked ? session.index.all : const <Item>[];
    final groups = ExpiryGroups(items, now);
    final onlyExpired = uri.queryParameters['show'] == 'expired';

    void open(Item item) => desktop
        ? context.go(Routes.vault(item: item.id))
        : context.push(Routes.item(item.id));

    if (DesktopTheme.maybeOf(context) != null) {
      return DesktopExpiryTable(
        groups: groups,
        apps: session is Unlocked ? session.index.apps : const {},
        now: now,
        empty: items.isEmpty,
        onlyExpired: onlyExpired,
        onOpen: open,
        onShowAll: () => context.go(Routes.expiry),
        onShowNoExpiry: () => context.go(Routes.vault()),
      );
    }

    final sections = <Widget>[
      if (groups.expired.isNotEmpty || onlyExpired)
        _Section(
          title: 'Expired',
          count: groups.expired.length,
          color: BCChipColor.danger,
          entries: groups.expired,
          now: now,
          onOpen: open,
          empty: 'Nothing has expired.',
        ),
      if (!onlyExpired) ...[
        if (groups.soon.isNotEmpty)
          _Section(
            title: 'Within 30 days',
            count: groups.soon.length,
            color: BCChipColor.warning,
            entries: groups.soon,
            now: now,
            onOpen: open,
          ),
        if (groups.later.isNotEmpty)
          _Section(
            title: 'Later',
            count: groups.later.length,
            color: BCChipColor.defaultColor,
            entries: groups.later,
            now: now,
            onOpen: open,
          ),
        if (groups.noExpiry > 0)
          _NoExpiry(
            count: groups.noExpiry,
            onPressed: () => context.go(Routes.vault()),
          ),
      ],
    ];

    return Scaffold(
      backgroundColor: bc.background,
      body: SingleChildScrollView(
        padding: desktop
            ? const EdgeInsets.fromLTRB(32, 24, 32, 32)
            : const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: BCText('Expiry', type: BCTextType.h2),
                    ),
                    if (onlyExpired)
                      BCButton(
                        size: BCButtonSize.sm,
                        variant: BCButtonVariant.ghost,
                        onPressed: () => context.go(Routes.expiry),
                        child: const Text('Show all'),
                      ),
                  ],
                ),
                const SizedBox(height: BCSpacing.xs),
                const BCText(
                  'Every date here was read from a file or entered by you. '
                  'Nothing is guessed.',
                  type: BCTextType.bodySm,
                  color: BCTextColor.muted,
                ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 64),
                    child: BCEmptyState(
                      icon: Icon(LucideIcons.calendarCheck2),
                      title: 'Nothing to track yet',
                      description:
                          'Import a certificate, profile or keystore and its '
                          'expiry date shows up here.',
                    ),
                  )
                else ...[
                  if (!onlyExpired &&
                      groups.expired.isEmpty &&
                      groups.soon.isEmpty)
                    const _AllClear(),
                  ...sections,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.count,
    required this.color,
    required this.entries,
    required this.now,
    required this.onOpen,
    this.empty,
  });

  final String title;
  final int count;
  final BCChipColor color;
  final List<(Item, ExpiryStatus)> entries;
  final DateTime now;
  final ValueChanged<Item> onOpen;

  /// Shown instead of rows when there are none.
  final String? empty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 28, 6, 8),
          child: Row(
            spacing: BCSpacing.sm,
            children: [
              BCText(
                title,
                type: BCTextType.bodySm,
                weight: BCTextWeight.medium,
                color: BCTextColor.muted,
              ),
              BCChip(
                size: BCChipSize.sm,
                variant: BCChipVariant.soft,
                color: color,
                child: Text('$count'),
              ),
            ],
          ),
        ),
        if (entries.isEmpty && empty != null)
          BCListGroup(children: [BCListGroupItem(title: empty)])
        else
          BCListGroup(
            children: [
              for (final (item, status) in entries)
                _ExpiryRow(
                  item: item,
                  status: status,
                  now: now,
                  onTap: () => onOpen(item),
                ),
            ],
          ),
      ],
    );
  }
}

/// One item: what it is, when it expires, how far off that is, and where
/// the date came from.
class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({
    required this.item,
    required this.status,
    required this.now,
    required this.onTap,
  });

  final Item item;
  final ExpiryStatus status;
  final DateTime now;
  final VoidCallback onTap;

  /// "in 12 days", "today", "3 days ago", "in 2 years" (see [timeLeft],
  /// [timeAgo]).
  static String relative(DateTime expiresAt, DateTime now) =>
      expiresAt.isAfter(now)
      ? 'in ${timeLeft(expiresAt, now)}'
      : timeAgo(expiresAt, now);

  @override
  Widget build(BuildContext context) {
    final expiresAt = status.expiresAt!;
    final type = item.type ?? ItemType.genericFile;
    final file = item.attachments.firstOrNull?.filename;
    final date = DateFormat.yMMMd().format(expiresAt.toLocal());
    final when = relative(expiresAt, now);
    return Semantics(
      button: true,
      label:
          '${item.title}, ${type.label}, '
          '${status.state == ExpiryState.expired ? 'expired' : 'expires'} '
          '$date, $when, '
          '${ProvenanceLabel.textFor(status.source).toLowerCase()}',
      excludeSemantics: true,
      child: BCListGroupItem(
        onPressed: onTap,
        prefix: TypeIconTile(type: type, size: 36),
        content: LayoutBuilder(
          builder: (context, constraints) {
            final name = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                BCText(item.title, weight: BCTextWeight.semibold, maxLines: 2),
                if (file != null)
                  MonoText(file, middleEllipsis: true)
                else
                  BCText(
                    type.label,
                    type: BCTextType.bodyXs,
                    color: BCTextColor.muted,
                  ),
              ],
            );
            final source = ProvenanceLabel(source: status.source);
            final relative = BCText(
              when,
              type: BCTextType.bodyXs,
              color: BCTextColor.muted,
            );
            // Phones: the date goes under the name, so the name keeps the
            // width.
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: BCSpacing.sm,
                children: [
                  name,
                  Wrap(
                    spacing: BCSpacing.sm,
                    runSpacing: BCSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      BCText(date, type: BCTextType.bodySm),
                      relative,
                      source,
                    ],
                  ),
                ],
              );
            }
            return Row(
              spacing: BCSpacing.md,
              children: [
                Expanded(child: name),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: 4,
                  children: [
                    BCText(date, type: BCTextType.bodySm),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: BCSpacing.sm,
                      children: [relative, source],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Items with no expiry date: a count, since there's no date to show.
class _NoExpiry extends StatelessWidget {
  const _NoExpiry({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: BCListGroup(
        children: [
          BCListGroupItem(
            prefix: const Icon(LucideIcons.calendar),
            title: count == 1
                ? '1 item has no expiry date'
                : '$count items have no expiry date',
            description:
                'Their files don’t state one. You can add a date when you '
                'edit an item, if you know it.',
            suffix: const Icon(LucideIcons.chevronRight, size: 16),
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: BCListGroup(
        children: [
          BCListGroupItem(
            prefix: Icon(
              LucideIcons.circleCheck,
              color: context.bcTheme.success,
            ),
            title: 'Nothing expired or expiring soon',
            description: 'Nothing expires in the next 30 days.',
          ),
        ],
      ),
    );
  }
}
