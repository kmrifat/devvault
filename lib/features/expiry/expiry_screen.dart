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
class ExpiryScreen extends ConsumerStatefulWidget {
  const ExpiryScreen({super.key, required this.uri, required this.desktop});

  final Uri uri;

  /// Items open in the vault's detail pane on desktop, as their own screen
  /// on phones.
  final bool desktop;

  @override
  ConsumerState<ExpiryScreen> createState() => _ExpiryScreenState();
}

class _ExpiryScreenState extends ConsumerState<ExpiryScreen>
    with LargeTitleScroll {
  @override
  Widget build(BuildContext context) {
    final desktop = widget.desktop;
    final uri = widget.uri;
    final bc = context.bcTheme;
    final now = ref.watch(clockProvider)();
    final session = ref.watch(vaultSessionProvider);
    final items = session is Unlocked ? session.index.all : const <Item>[];
    final apps = session is Unlocked
        ? session.index.apps
        : const <String, AppRecord>{};
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
          apps: apps,
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
            apps: apps,
            now: now,
            onOpen: open,
          ),
        if (groups.later.isNotEmpty)
          _Section(
            title: 'Later',
            count: groups.later.length,
            color: BCChipColor.defaultColor,
            entries: groups.later,
            apps: apps,
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

    // On iPhone the title is large, in the page, and moves into UIKit's
    // header (with Show all) once it scrolls under it.
    final native = !desktop && ref.watch(nativeBarsProvider);
    const facts = BCText(
      'Every date here was read from a file or entered by you. '
      'Nothing is guessed.',
      type: BCTextType.bodySm,
      color: BCTextColor.muted,
    );
    return Scaffold(
      backgroundColor: bc.background,
      extendBodyBehindAppBar: native,
      appBar: native
          ? NativePhoneHeader(
              title: titleInBar ? 'Expiry' : '',
              actions: [
                if (onlyExpired)
                  NativeHeaderAction(
                    id: 'all',
                    label: 'Show all',
                    onPressed: () => context.go(Routes.expiry),
                  ),
              ],
            )
          : null,
      body: SingleChildScrollView(
        controller: titleScroll,
        padding: desktop
            ? const EdgeInsets.fromLTRB(32, 24, 32, 32)
            : EdgeInsets.fromLTRB(
                native ? 0 : 16,
                native
                    ? MediaQuery.paddingOf(context).top +
                          NativePhoneHeader.barHeight
                    : 16,
                native ? 0 : 16,
                120,
              ),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (native)
                  const PhoneLargeTitle('Expiry', subtitle: facts)
                else ...[
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
                  facts,
                ],
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 64, 16, 0),
                    child: BCEmptyState(
                      icon: Icon(LucideIcons.calendarCheck2),
                      title: 'Nothing to track yet',
                      description:
                          'Import a certificate, profile or keystore and its '
                          'expiry date shows up here.',
                    ),
                  )
                else
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: native ? 16 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!onlyExpired)
                          _Summary(
                            expired: groups.expired.length,
                            soon: groups.soon.length,
                            later: groups.later.length,
                          ),
                        if (!onlyExpired &&
                            groups.expired.isEmpty &&
                            groups.soon.isEmpty)
                          const _AllClear(),
                        ...sections,
                      ],
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

/// How many items have expired, expire within 30 days and later
/// (design frame I6), over the groups.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.expired,
    required this.soon,
    required this.later,
  });

  final int expired;
  final int soon;
  final int later;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    Widget tile(int count, String label, Color background, Color foreground) =>
        Expanded(
          child: Semantics(
            label: '$count $label',
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: background,
                shape: BCShapes.continuous(BCRadius.xxl),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: BCTypography.size2xl,
                        height: 1.2,
                        fontWeight: BCTypography.bold,
                        color: foreground,
                      ),
                    ),
                    BCText(
                      label,
                      type: BCTextType.bodyXs,
                      weight: BCTextWeight.medium,
                      style: TextStyle(color: foreground),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        spacing: BCSpacing.sm,
        children: [
          tile(expired, 'Expired', bc.dangerSoft, bc.dangerSoftForeground),
          tile(
            soon,
            'In ${ExpiryState.expiryWindow.inDays} days',
            bc.warningSoft,
            bc.warningSoftForeground,
          ),
          tile(later, 'Later', bc.surface, bc.foreground),
        ],
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
    required this.apps,
    required this.now,
    required this.onOpen,
    this.empty,
  });

  final String title;
  final int count;
  final BCChipColor color;
  final List<(Item, ExpiryStatus)> entries;
  final Map<String, AppRecord> apps;
  final DateTime now;
  final ValueChanged<Item> onOpen;

  /// Shown instead of rows when there are none.
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final dot = switch (color) {
      BCChipColor.danger => bc.danger,
      BCChipColor.warning => bc.warning,
      _ => bc.separator,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Semantics(
            header: true,
            label: '$title, $count',
            excludeSemantics: true,
            child: Row(
              spacing: BCSpacing.sm,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  child: const SizedBox.square(dimension: 8),
                ),
                BCText(
                  title.toUpperCase(),
                  type: BCTextType.bodyXs,
                  weight: BCTextWeight.semibold,
                  color: BCTextColor.muted,
                ),
              ],
            ),
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
                  app: apps[item.appId],
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

/// One item: what it is, which app, where the date came from, and when
/// it expires and how far off that is (design frame I6).
class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({
    required this.item,
    required this.app,
    required this.status,
    required this.now,
    required this.onTap,
  });

  final Item item;
  final AppRecord? app;
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
    final bc = context.bcTheme;
    final expiresAt = status.expiresAt!;
    final type = item.type ?? ItemType.genericFile;
    final date = DateFormat.yMMMd().format(expiresAt.toLocal());
    final when = relative(expiresAt, now);
    final source = ProvenanceLabel.textFor(status.source);
    final whenColor = switch (status.state) {
      ExpiryState.expired => bc.dangerSoftForeground,
      ExpiryState.soon => bc.warningSoftForeground,
      _ => bc.muted,
    };
    return Semantics(
      button: true,
      label:
          '${item.title}, ${type.label}, '
          '${status.state == ExpiryState.expired ? 'expired' : 'expires'} '
          '$date, $when, '
          '${source.toLowerCase()}',
      excludeSemantics: true,
      child: BCListGroupItem(
        onPressed: onTap,
        prefix: TypeIconTile(type: type),
        content: Row(
          spacing: BCSpacing.md,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  BCText(
                    item.title,
                    weight: BCTextWeight.semibold,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    spacing: 4,
                    children: [
                      Icon(
                        status.source == ExpirySource.user
                            ? LucideIcons.userPen
                            : LucideIcons.fileCheck,
                        size: 12,
                        color: bc.muted,
                      ),
                      Flexible(
                        child: BCText(
                          [?app?.name, source.toLowerCase()].join(' · '),
                          type: BCTextType.bodyXs,
                          color: BCTextColor.muted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 2,
              children: [
                BCText(
                  date,
                  type: BCTextType.bodySm,
                  weight: BCTextWeight.medium,
                ),
                BCText(
                  when,
                  type: BCTextType.bodyXs,
                  weight: BCTextWeight.medium,
                  style: TextStyle(color: whenColor),
                ),
              ],
            ),
          ],
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
