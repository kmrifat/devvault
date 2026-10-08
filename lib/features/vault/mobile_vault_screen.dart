import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../data/sync_controller.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import '../sync/sync_status_chip.dart';
import 'vault_actions.dart';
import 'vault_list_pane.dart';

/// Design frame B2: the vault on a phone. A large title that collapses,
/// search, the All / Expiring / Files / Secrets tabs, app chips, and the
/// items grouped by app. Tapping an item pushes its screen (B3).
///
/// Everything it shows comes from the `/vault` query, like the desktop
/// list, so back and forward keep the filters. With sync on, the sync line
/// sits under the search and pulling the list down syncs (P3-07).
class MobileVaultScreen extends ConsumerStatefulWidget {
  const MobileVaultScreen({super.key, required this.uri});

  final Uri uri;

  @override
  ConsumerState<MobileVaultScreen> createState() => _MobileVaultScreenState();
}

class _MobileVaultScreenState extends ConsumerState<MobileVaultScreen> {
  late final _search = TextEditingController(text: _filter.q ?? '');

  VaultFilter get _filter => VaultFilter.fromUri(widget.uri);

  @override
  void didUpdateWidget(MobileVaultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final q = _filter.q ?? '';
    if (q.trim() != _search.text.trim()) _search.text = q;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
    final groups = <(AppRecord?, List<Item>)>[];
    if (filter.app != null) {
      groups.add((index.apps[filter.app], items));
    } else {
      for (final app in apps) {
        final mine = items.where((i) => i.appId == app.id).toList();
        if (mine.isNotEmpty) groups.add((app, mine));
      }
      final none = items
          .where((i) => !index.apps.containsKey(i.appId))
          .toList();
      if (none.isNotEmpty) groups.add((null, none));
    }

    final syncing = ref.watch(syncControllerProvider) is! SyncOff;

    final list = CustomScrollView(
      // Pull to refresh needs a list that scrolls even when it's short.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        BCSliverAppHeader(
          largeTitle: const Text('Vault'),
          actions: [
            // 48 px: the touch-target minimum (bc_ui's default is 40).
            BCHeaderIconButton(
              size: 48,
              icon: const Icon(LucideIcons.filePlus2, semanticLabel: 'Import'),
              onPressed: () => openImport(context),
            ),
            BCHeaderIconButton(
              size: 48,
              icon: const Icon(LucideIcons.plus, semanticLabel: 'New item'),
              onPressed: () => createItem(context, filter),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList.list(
            children: [
              Semantics(
                label: 'Search',
                child: BCSearchField(
                  controller: _search,
                  placeholder: 'Search items, bundle IDs, key IDs',
                  onChanged: (q) => _go(filter.withQuery(q)),
                  onClear: () => _go(filter.withQuery('')),
                ),
              ),
              if (syncing) ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SyncStatusChip(),
                ),
              ],
              const SizedBox(height: 12),
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
                        selected: filter.app == null,
                        onPressed: () =>
                            _go(VaultFilter(kind: filter.kind, q: filter.q)),
                      ),
                      for (final app in apps)
                        _AppChip(
                          label: app.name,
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
          for (final (app, groupItems) in groups) ...[
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
                      weight: BCTextWeight.medium,
                      color: BCTextColor.muted,
                    ),
                  ],
                ),
              ),
            ),
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
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: BCChip(
        size: BCChipSize.md,
        variant: selected ? BCChipVariant.soft : BCChipVariant.secondary,
        color: selected ? BCChipColor.accent : BCChipColor.defaultColor,
        startContent: leading,
        onPressed: onPressed,
        child: Text(label),
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
