import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../core/expiry.dart';
import '../../data/providers.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';

/// Which part of the app the window shows, as the sidebar sees it.
enum ShellSection { vault, expiry, settings }

/// Design frame D03's sidebar: the vault, smart filters (all items,
/// expiring, expired, conflicts), the App → Platform → Environment tree
/// with item counts, tags, and Settings at the bottom.
///
/// It has no selection state of its own: what is selected is read from
/// [uri], and every row is a link, so back and forward and a reload all
/// keep the sidebar in step with the list.
class VaultSidebar extends ConsumerStatefulWidget {
  const VaultSidebar({super.key, required this.section, required this.uri});

  final ShellSection section;
  final Uri uri;

  static const double width = 264;

  @override
  ConsumerState<VaultSidebar> createState() => _VaultSidebarState();
}

class _VaultSidebarState extends ConsumerState<VaultSidebar> {
  /// Apps start open; these were closed by the user.
  final _collapsedApps = <String>{};

  /// Platforms start closed unless they hold the selection; these were
  /// opened (true) or closed (false) by the user.
  final _platformOpen = <String, bool>{};

  VaultFilter get _filter => widget.section == ShellSection.vault
      ? VaultFilter.fromUri(widget.uri)
      : const VaultFilter();

  /// Opens [filter] in the vault list, keeping the current search.
  void _show(VaultFilter filter) =>
      context.go(filter.withQuery(_filter.q).location());

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final session = ref.watch(vaultSessionProvider);
    final index = session is Unlocked ? session.index : null;
    final now = ref.watch(clockProvider)();
    final filter = _filter;
    final section = widget.section;
    final expiredSelected =
        section == ShellSection.expiry &&
        widget.uri.queryParameters['show'] == 'expired';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bc.background,
        border: Border(right: BorderSide(color: bc.border)),
      ),
      child: SizedBox(
        width: VaultSidebar.width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VaultCard(count: index?.items.length ?? 0),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _NavRow(
                      icon: LucideIcons.layers,
                      label: 'All items',
                      trailing: _Count(index?.items.length ?? 0),
                      selected: section == ShellSection.vault && filter.isAll,
                      onTap: () => _show(const VaultFilter()),
                    ),
                    _NavRow(
                      icon: LucideIcons.clockAlert,
                      label: 'Expiring soon',
                      trailing: _Badge(
                        index?.countExpiring(ExpiryState.soon, now) ?? 0,
                        BCChipColor.warning,
                      ),
                      selected:
                          section == ShellSection.expiry && !expiredSelected,
                      onTap: () => context.go(Routes.expiryShowing()),
                    ),
                    _NavRow(
                      icon: LucideIcons.circleX,
                      label: 'Expired',
                      trailing: _Badge(
                        index?.countExpiring(ExpiryState.expired, now) ?? 0,
                        BCChipColor.danger,
                      ),
                      selected: expiredSelected,
                      onTap: () =>
                          context.go(Routes.expiryShowing(expired: true)),
                    ),
                    if (index != null && _conflicts(index) > 0)
                      _NavRow(
                        icon: LucideIcons.gitMerge,
                        label: 'Conflicts',
                        trailing: _Badge(
                          _conflicts(index),
                          BCChipColor.defaultColor,
                        ),
                        selected: filter.view == VaultView.conflicts,
                        onTap: () =>
                            _show(const VaultFilter(view: VaultView.conflicts)),
                      ),
                    if (index != null && index.quarantined.isNotEmpty)
                      _NavRow(
                        icon: LucideIcons.shieldAlert,
                        label: 'Unreadable',
                        trailing: _Badge(
                          index.quarantined.length,
                          BCChipColor.danger,
                        ),
                        selected: filter.view == VaultView.quarantine,
                        onTap: () => _show(
                          const VaultFilter(view: VaultView.quarantine),
                        ),
                      ),
                    const SizedBox(height: 18),
                    const _SectionLabel('Apps'),
                    if (index == null || index.tree.isEmpty)
                      const _Hint('Items you add are grouped here by app')
                    else
                      for (final node in index.tree) ..._appRows(node, filter),
                    if (index != null && index.tagCounts.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const _SectionLabel('Tags'),
                      _Tags(
                        tags: index.tagCounts.keys.toList(),
                        selected: section == ShellSection.vault
                            ? filter.tag
                            : null,
                        onSelected: (tag) => _show(VaultFilter(tag: tag)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: BCSpacing.sm),
              _NavRow(
                icon: LucideIcons.settings,
                label: 'Settings',
                selected: section == ShellSection.settings,
                onTap: () => context.go(Routes.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static int _conflicts(VaultIndex index) =>
      index.items.values.where((i) => i.conflict != null).length;

  /// Whether the tree node at [app] / [platform] / [env] is the selection.
  bool _isSelected(
    VaultFilter filter, {
    required String app,
    String? platform,
    String? env,
  }) =>
      widget.section == ShellSection.vault &&
      filter.tag == null &&
      filter.view == null &&
      filter.app == app &&
      filter.platform == platform &&
      filter.env == env;

  List<Widget> _appRows(AppNode node, VaultFilter filter) {
    final appKey = node.app?.id ?? VaultFilter.none;
    final open = !_collapsedApps.contains(appKey);
    return [
      _TreeRow(
        depth: 0,
        expanded: open,
        onToggle: () => setState(
          () =>
              open ? _collapsedApps.add(appKey) : _collapsedApps.remove(appKey),
        ),
        leading: AppBadge(app: node.app),
        label: node.app?.name ?? 'No app',
        count: node.count,
        selected: _isSelected(filter, app: appKey),
        onTap: () {
          setState(() => _collapsedApps.remove(appKey));
          _show(VaultFilter(app: appKey));
        },
      ),
      if (open)
        for (final platform in node.platforms)
          ..._platformRows(appKey, platform, filter),
    ];
  }

  List<Widget> _platformRows(
    String appKey,
    PlatformNode node,
    VaultFilter filter,
  ) {
    final platformKey = node.platform ?? VaultFilter.none;
    final key = '$appKey/$platformKey';
    final holdsSelection =
        filter.app == appKey && filter.platform == platformKey;
    final open = _platformOpen[key] ?? holdsSelection;
    final bc = context.bcTheme;
    return [
      _TreeRow(
        depth: 1,
        expanded: open,
        onToggle: () => setState(() => _platformOpen[key] = !open),
        leading: Icon(_platformIcon(node.platform), size: 15, color: bc.muted),
        label: VaultLabels.platform(node.platform),
        count: node.count,
        selected: _isSelected(filter, app: appKey, platform: platformKey),
        onTap: () {
          setState(() => _platformOpen[key] = true);
          _show(VaultFilter(app: appKey, platform: platformKey));
        },
      ),
      if (open)
        for (final MapEntry(key: env, value: count)
            in node.environments.entries)
          _TreeRow(
            depth: 2,
            leading: _EnvDot(env),
            label: VaultLabels.environment(env),
            count: count,
            selected: _isSelected(
              filter,
              app: appKey,
              platform: platformKey,
              env: env ?? VaultFilter.none,
            ),
            onTap: () => _show(
              VaultFilter(
                app: appKey,
                platform: platformKey,
                env: env ?? VaultFilter.none,
              ),
            ),
          ),
    ];
  }

  static IconData _platformIcon(String? platform) => switch (platform) {
    'ios' || 'macos' => LucideIcons.apple,
    'android' => LucideIcons.smartphone,
    'web' => LucideIcons.globe,
    'server' => LucideIcons.server,
    'windows' || 'linux' => LucideIcons.monitor,
    _ => LucideIcons.box,
  };
}

/// The vault this window shows, with its size. One vault per device in
/// v1, so there's nothing to switch to yet.
class _VaultCard extends StatelessWidget {
  const _VaultCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: bc.surface,
        shape: BCShapes.continuous(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          spacing: 10,
          children: [
            DecoratedBox(
              decoration: ShapeDecoration(
                color: bc.accentSoft,
                shape: BCShapes.continuous(BCRadius.xl),
              ),
              child: SizedBox.square(
                dimension: 36,
                child: Icon(LucideIcons.vault, size: 18, color: bc.accent),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  const BCText(
                    'DevVault',
                    type: BCTextType.bodySm,
                    weight: BCTextWeight.semibold,
                  ),
                  BCText(
                    '$count ${count == 1 ? 'item' : 'items'} · this device',
                    type: BCTextType.bodyXs,
                    color: BCTextColor.muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row's hover and selection background, and its tap and semantics.
class _RowSurface extends StatefulWidget {
  const _RowSurface({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.height,
    required this.padding,
    required this.child,
    this.expanded,
  });

  final String label;

  /// Whether a tree row is open; null for rows that don't open.
  final bool? expanded;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final EdgeInsets padding;
  final Widget child;

  @override
  State<_RowSurface> createState() => _RowSurfaceState();
}

class _RowSurfaceState extends State<_RowSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final color = widget.selected
        ? bc.accentSoft
        : _hovered
        ? bc.surface
        : null;
    return Semantics(
      button: true,
      selected: widget.selected,
      expanded: widget.expanded,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: widget.height,
            padding: widget.padding,
            decoration: ShapeDecoration(
              color: color ?? bc.background.withValues(alpha: 0),
              shape: BCShapes.continuous(14),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A top-level destination: icon, label and a count or badge.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final color = selected ? bc.accent : bc.foreground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _RowSurface(
        label: label,
        selected: selected,
        onTap: onTap,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          spacing: 12,
          children: [
            Icon(icon, size: 18, color: color),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BCTypography.textSm.copyWith(
                  color: color,
                  fontWeight: selected
                      ? BCTypography.semiBold
                      : BCTypography.medium,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A row of the App → Platform → Environment tree. [depth] 0 and 1 rows
/// have a disclosure chevron when [onToggle] is set.
class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.depth,
    required this.leading,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.expanded = false,
    this.onToggle,
  });

  final int depth;
  final Widget leading;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final indent = switch (depth) {
      0 => 12.0,
      1 => 36.0,
      _ => 68.0,
    };
    final chevronSize = depth == 0 ? 14.0 : 13.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _RowSurface(
        label: '$label, $count ${count == 1 ? 'item' : 'items'}',
        expanded: onToggle == null ? null : expanded,
        selected: selected,
        onTap: onTap,
        height: depth == 0 ? 36 : 34,
        padding: EdgeInsets.only(left: indent, right: 12),
        child: Row(
          spacing: 10,
          children: [
            if (onToggle != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Icon(
                  expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: chevronSize,
                  color: bc.muted,
                ),
              ),
            leading,
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BCTypography.textSm.copyWith(
                  color: selected ? bc.accent : bc.foreground,
                  fontWeight: selected
                      ? BCTypography.semiBold
                      : depth == 0
                      ? BCTypography.medium
                      : BCTypography.regular,
                ),
              ),
            ),
            _Count(count, selected: selected),
          ],
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
    final bc = context.bcTheme;
    final color = switch (environment?.toLowerCase()) {
      'production' || 'prod' => bc.success,
      'staging' => bc.warning,
      'development' || 'dev' => bc.accent,
      _ => bc.muted,
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 7),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.count, {this.selected = false});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Text(
      '$count',
      style: BCTypography.textXs.copyWith(
        color: selected ? bc.accent : bc.muted,
      ),
    );
  }
}

/// A count that needs attention; nothing when it's zero.
class _Badge extends StatelessWidget {
  const _Badge(this.count, this.color);

  final int count;
  final BCChipColor color;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return BCChip(
      size: BCChipSize.sm,
      variant: color == BCChipColor.defaultColor
          ? BCChipVariant.secondary
          : BCChipVariant.soft,
      color: color,
      child: Text('$count'),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: BCText(
        text,
        type: BCTextType.bodySm,
        weight: BCTextWeight.medium,
        color: BCTextColor.muted,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: BCText(text, type: BCTextType.bodyXs, color: BCTextColor.muted),
    );
  }
}

/// Every tag in the vault; one can be selected to filter the list.
class _Tags extends StatelessWidget {
  const _Tags({
    required this.tags,
    required this.selected,
    required this.onSelected,
  });

  final List<String> tags;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: BCTagGroup<String>(
        // Multiple mode so tapping the selected tag reports it as removed;
        // the sidebar still keeps one tag at a time.
        selectionMode: BCTagGroupSelectionMode.multiple,
        selectedValues: {?selected},
        onSelectionChange: (values) =>
            onSelected(values.difference({?selected}).firstOrNull),
        items: [for (final tag in tags) BCTagItem(value: tag, label: tag)],
      ),
    );
  }
}
