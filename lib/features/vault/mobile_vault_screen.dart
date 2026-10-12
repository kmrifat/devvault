import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart'
    show LiquidGlassSegmentedControl;
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../core/expiry.dart';
import '../../data/providers.dart';
import '../../data/sync_controller.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import '../sync/sync_status_chip.dart';
import '../import/paste_secret_sheet.dart';
import '../notes/notes.dart' show PhoneNotesCard;
import 'vault_actions.dart';
import 'vault_item_row.dart';

/// Design frame I1: the vault on a phone. A large title that collapses,
/// the All / Expiring / Files / Secrets tabs, app chips, and the
/// items grouped by app. Tapping an item pushes its screen (B3).
///
/// Once any app has an organization, the apps are grouped under their
/// organization's heading (then "Personal" for the apps without one), and
/// organization chips come before the app chips.
///
/// Everything it shows comes from the `/vault` query, like the desktop
/// list, so back and forward keep the filters. With sync on, the sync line
/// sits under the title and pulling the list down syncs (P3-07). Search
/// is its own tab (`SearchScreen`).
class MobileVaultScreen extends ConsumerStatefulWidget {
  const MobileVaultScreen({super.key, required this.uri});

  final Uri uri;

  @override
  ConsumerState<MobileVaultScreen> createState() => _MobileVaultScreenState();
}

class _MobileVaultScreenState extends ConsumerState<MobileVaultScreen>
    with LargeTitleScroll {
  VaultFilter get _filter => VaultFilter.fromUri(widget.uri);

  void _go(VaultFilter filter) => context.go(filter.location());

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final session = ref.watch(vaultSessionProvider);
    if (session is! Unlocked) return const SizedBox.shrink();
    final index = session.index;
    final now = ref.watch(clockProvider)();
    final filter = _filter;
    final items = [
      for (final item in filter.apply(index))
        if (filter.kind.includes(item, now)) item,
    ];
    final apps = index.apps.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Grouped by app unless one app is chosen: apps by name, then no app.
    // Once an app has an organization, apps go under an organization
    // heading (then Personal), and No app gets a heading of its own.
    final byOrg = index.orgGroups.isNotEmpty;
    final groups = <({String? heading, AppRecord? app, List<Item> items})>[];
    if (filter.app != null) {
      groups.add((heading: null, app: index.apps[filter.app], items: items));
    } else {
      final ordered = byOrg
          ? [
              for (final group in index.orgGroups)
                for (final node in group.apps) node.app!,
            ]
          : apps;
      String? lastHeading;
      for (final app in ordered) {
        final mine = items.where((i) => i.appId == app.id).toList();
        if (mine.isEmpty) continue;
        final heading = byOrg ? app.organization ?? 'Personal' : null;
        groups.add((
          heading: heading == lastHeading ? null : heading,
          app: app,
          items: mine,
        ));
        lastHeading = heading;
      }
      final none = items
          .where((i) => !index.apps.containsKey(i.appId))
          .toList();
      if (none.isNotEmpty) {
        groups.add((heading: byOrg ? 'No app' : null, app: null, items: none));
      }
    }
    final personal = apps.any((a) => a.organization == null);
    // One app chosen: its notes, if it has any, over its items.
    final appNotes = index.apps[filter.app]?.notes;
    // An organization chosen: its notes.
    final orgNotes =
        filter.app == null &&
            filter.org != null &&
            filter.org != VaultFilter.none
        ? organizationNotes(index, filter.org!)
        : null;

    final syncing = ref.watch(syncControllerProvider) is! SyncOff;

    // On iPhone the header is UIKit's, over the list (Scaffold below).
    final native = ref.watch(nativeBarsProvider);
    final summary = _Summary(count: index.all.length, syncing: syncing);
    final (expired, soon) = _expiryCounts(index.all, now);
    final list = CustomScrollView(
      controller: titleScroll,
      // Pull to refresh needs a list that scrolls even when it's short.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (native) ...[
          SliverToBoxAdapter(
            child: SizedBox(
              height:
                  MediaQuery.paddingOf(context).top +
                  NativePhoneHeader.barHeight,
            ),
          ),
          SliverToBoxAdapter(
            child: PhoneLargeTitle('Vault', subtitle: summary),
          ),
        ] else
          BCSliverAppHeader(
            largeTitle: const Text('Vault'),
            actions: [
              // 48 px: the touch-target minimum (bc_ui's default is 40).
              BCHeaderIconButton(
                size: 48,
                icon: const Icon(
                  LucideIcons.filePlus2,
                  semanticLabel: 'Import',
                ),
                onPressed: () => showPhoneImport(context),
              ),
              BCHeaderIconButton(
                size: 48,
                icon: const Icon(LucideIcons.plus, semanticLabel: 'New item'),
                onPressed: () => createItem(context, filter),
              ),
            ],
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, native ? 16 : 8, 16, 0),
          sliver: SliverList.list(
            children: [
              if (!native) ...[summary, const SizedBox(height: 12)],
              if (native)
                LiquidGlassSegmentedControl(
                  labels: [for (final kind in VaultKind.values) kind.label],
                  selectedIndex: filter.kind.index,
                  onValueChanged: (i) =>
                      _go(filter.withKind(VaultKind.values[i])),
                  height: 36,
                )
              else
                // Sized to their labels: four equal tabs don't fit a narrow
                // phone.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: BCTabs<VaultKind>(
                    value: filter.kind,
                    onValueChange: (kind) => _go(filter.withKind(kind)),
                    items: [
                      for (final kind in VaultKind.values)
                        BCTabItem(value: kind, label: kind.label),
                    ],
                  ),
                ),
              if (apps.isNotEmpty) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 8,
                    children: [
                      _AppChip(
                        label: 'All apps',
                        selected: filter.app == null && filter.org == null,
                        onPressed: () =>
                            _go(VaultFilter(kind: filter.kind, q: filter.q)),
                      ),
                      if (index.organizations.isNotEmpty)
                        for (final org in [
                          ...index.organizations,
                          if (personal) VaultFilter.none,
                        ])
                          _AppChip(
                            label: org == VaultFilter.none ? 'Personal' : org,
                            leading: Icon(
                              org == VaultFilter.none
                                  ? LucideIcons.user
                                  : LucideIcons.building2,
                              size: 16,
                            ),
                            selected: filter.org == org,
                            onPressed: () => _go(
                              VaultFilter(
                                org: org,
                                kind: filter.kind,
                                q: filter.q,
                              ),
                            ),
                          ),
                      for (final app in apps)
                        _AppChip(
                          label: app.name,
                          count: index.all
                              .where((i) => i.appId == app.id)
                              .length,
                          leading: AppBadge(app: app, size: 16),
                          selected: filter.app == app.id,
                          onPressed: () => _go(
                            VaultFilter(
                              app: app.id,
                              kind: filter.kind,
                              q: filter.q,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (expired + soon > 0 &&
                  filter.isAll &&
                  filter.kind == VaultKind.all) ...[
                const SizedBox(height: 16),
                _ExpiryCard(expired: expired, soon: soon),
              ],
              if (appNotes != null) ...[
                const SizedBox(height: 16),
                PhoneNotesCard(notes: appNotes, title: 'App notes'),
              ],
              if (orgNotes != null) ...[
                const SizedBox(height: 16),
                PhoneNotesCard(notes: orgNotes, title: 'Organization notes'),
              ],
            ],
          ),
        ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: BCEmptyState(
                icon: Icon(
                  index.items.isEmpty ? LucideIcons.vault : LucideIcons.searchX,
                ),
                title: index.items.isEmpty
                    ? 'Your vault is empty'
                    : filter.q != null
                    ? 'No matches'
                    : 'Nothing here',
                description: index.items.isEmpty
                    ? 'Import a credential file to start.'
                    : null,
              ),
            ),
          )
        else
          for (final (:heading, :app, items: groupItems) in groups) ...[
            if (heading != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 0),
                sliver: SliverToBoxAdapter(
                  child: Semantics(
                    header: true,
                    child: BCText(
                      heading,
                      type: BCTextType.h6,
                      weight: BCTextWeight.semibold,
                    ),
                  ),
                ),
              ),
            if (heading == null || app != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    spacing: 8,
                    children: [
                      AppBadge(app: app, size: 18),
                      BCText(
                        app?.name ?? 'No app',
                        type: BCTextType.bodySm,
                        weight: BCTextWeight.semibold,
                      ),
                      BCText(
                        groupItems.length == 1
                            ? '1 item'
                            : '${groupItems.length} items',
                        type: BCTextType.bodyXs,
                        color: BCTextColor.muted,
                      ),
                    ],
                  ),
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: _Group(
                  children: [
                    for (final item in groupItems)
                      VaultItemRow(
                        item: item,
                        selected: false,
                        now: now,
                        onTap: () => context.push(Routes.item(item.id)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        // Room for the floating bottom nav.
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );

    return Scaffold(
      backgroundColor: bc.background,
      extendBodyBehindAppBar: native,
      appBar: native
          ? NativePhoneHeader(
              title: titleInBar ? 'Vault' : '',
              actions: [
                NativeHeaderAction(
                  id: 'import',
                  symbol: 'square.and.arrow.down',
                  label: 'Import',
                  onPressed: () => showPhoneImport(context),
                ),
                NativeHeaderAction(
                  id: 'new',
                  symbol: 'plus',
                  label: 'New item',
                  onPressed: () => createItem(context, filter),
                ),
              ],
            )
          : null,
      body: syncing
          ? RefreshIndicator.adaptive(
              color: bc.accent,
              backgroundColor: bc.surface,
              onRefresh: () =>
                  ref.read(syncControllerProvider.notifier).syncNow(),
              child: list,
            )
          : list,
    );
  }
}

class _AppChip extends StatelessWidget {
  const _AppChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.leading,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final Widget? leading;

  /// How many items the chip's app holds, of every kind.
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: BCChip(
        size: BCChipSize.md,
        variant: selected ? BCChipVariant.soft : BCChipVariant.secondary,
        color: selected ? BCChipColor.accent : BCChipColor.defaultColor,
        startContent: leading,
        endContent: count == null
            ? null
            : BCText(
                '$count',
                type: BCTextType.bodyXs,
                color: BCTextColor.muted,
              ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

/// How many of [items] have expired, and how many expire within the
/// warning window, at [now].
(int, int) _expiryCounts(Iterable<Item> items, DateTime now) {
  var expired = 0, soon = 0;
  for (final item in items) {
    switch (ExpiryState.of(item, now)) {
      case ExpiryState.expired:
        expired++;
      case ExpiryState.soon:
        soon++;
      case ExpiryState.valid || ExpiryState.none:
        break;
    }
  }
  return (expired, soon);
}

/// The line under the title: how many items the vault holds and, with
/// sync on, its status.
class _Summary extends StatelessWidget {
  const _Summary({required this.count, required this.syncing});

  final int count;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        BCText(
          count == 1 ? '1 item' : '$count items',
          type: BCTextType.bodySm,
          color: BCTextColor.muted,
        ),
        if (syncing) const SyncStatusChip(),
      ],
    );
  }
}

/// What needs attention, over the list (design frame I1): how many items
/// have expired or expire soon. Opens the Expiry tab.
class _ExpiryCard extends StatelessWidget {
  const _ExpiryCard({required this.expired, required this.soon});

  final int expired;
  final int soon;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final shape = BCShapes.continuous(BCRadius.xxxl);
    final title = [
      if (expired > 0) '$expired expired',
      if (soon > 0) '$soon within ${ExpiryState.expiryWindow.inDays} days',
    ].join(' · ');
    return Semantics(
      button: true,
      label: '$title. Open Expiry',
      excludeSemantics: true,
      child: BCPressable(
        onPressed: () => context.go(Routes.expiry),
        shape: shape,
        background: DecoratedBox(
          decoration: ShapeDecoration(color: bc.warningSoft, shape: shape),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            spacing: 12,
            children: [
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: bc.warningSoftHover,
                  shape: const CircleBorder(),
                ),
                child: SizedBox.square(
                  dimension: 40,
                  child: Icon(
                    LucideIcons.clockAlert,
                    size: 20,
                    color: bc.warning,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    BCText(
                      title,
                      type: BCTextType.bodySm,
                      weight: BCTextWeight.semibold,
                      style: TextStyle(color: bc.warningSoftForeground),
                    ),
                    BCText(
                      'Dates read from files or set by you',
                      type: BCTextType.bodyXs,
                      style: TextStyle(color: bc.warningSoftForeground),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: bc.warningSoftForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rows in one rounded surface with inset hairlines, like the desktop list.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final shape = BCShapes.continuous(BCRadius.xxxl);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: bc.surface, shape: shape),
        child: Column(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 66),
                  child: Divider(height: 1, thickness: 1, color: bc.separator),
                ),
              child,
            ],
          ],
        ),
      ),
    );
  }
}
