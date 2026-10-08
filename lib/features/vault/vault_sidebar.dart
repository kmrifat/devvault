import 'package:flutter/material.dart' show Material, MaterialType;
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
import 'vault_actions.dart';

/// Which part of the app the window shows, as the sidebar sees it.
enum ShellSection { vault, expiry, settings }

/// The window's source list (design frame N03): the vault, the smart lists
/// with counts (all items, expiring in 30 days, expired, conflicts), the
/// App › Platform › Environment tree, tags, and a footer with Settings and
/// the auto-lock time.
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
                  selected: section == ShellSection.expiry && !expiredSelected,
                  onTap: () => context.go(Routes.expiryShowing()),
                ),
                _SourceRow(
                  icon: DesktopSymbol.expired,
                  iconColor: colors.danger,
                  label: 'Expired',
                  count: index?.countExpiring(ExpiryState.expired, now) ?? 0,
                  selected: expiredSelected,
                  onTap: () => context.go(Routes.expiryShowing(expired: true)),
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
                  action: DesktopIconButton(
                    symbol: DesktopSymbol.add,
                    tooltip: 'New app',
                    size: 12,
                    onPressed: () => createApp(context),
                  ),
                ),
                if (index == null || index.tree.isEmpty)
                  const _Hint('Items you add are grouped here by app')
                else
                  for (final node in index.tree) ..._appRows(node, filter),
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
          _Footer(selected: section == ShellSection.settings),
        ],
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
      _SourceRow(
        tree: true,
        expanded: open,
        onToggle: () => setState(
          () =>
              open ? _collapsedApps.add(appKey) : _collapsedApps.remove(appKey),
        ),
        leading: AppBadge(app: node.app, size: 14),
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
    return [
      _SourceRow(
        tree: true,
        depth: 1,
        expanded: open,
        onToggle: () => setState(() => _platformOpen[key] = !open),
        icon: _platformSymbol(node.platform),
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
          _SourceRow(
            tree: true,
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

  static DesktopSymbol _platformSymbol(String? platform) => switch (platform) {
    'ios' || 'macos' => DesktopSymbol.platformApple,
    'android' => DesktopSymbol.platformAndroid,
    'web' => DesktopSymbol.platformWeb,
    'server' => DesktopSymbol.platformServer,
    'windows' || 'linux' => DesktopSymbol.platformDesktop,
    _ => DesktopSymbol.platformOther,
  };
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
  });

  final DesktopSymbol? icon;
  final Color? iconColor;
  final Widget? leading;
  final String label;

  /// Shown at the trailing edge; null shows nothing.
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  /// A row of the App › Platform › Environment tree, [depth] levels deep.
  final bool tree;
  final int depth;
  final bool expanded;

  /// Set on tree rows that open and close.
  final VoidCallback? onToggle;

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
      label: tree ? '${widget.label}$countLabel' : widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
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
                  ? colors.accent
                  : _hovered
                  ? colors.innerSeparator
                  : null,
              borderRadius: const BorderRadius.all(
                Radius.circular(DesktopMetrics.menuRadius),
              ),
            ),
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
                                  ? colors.onAccent
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
                                    ? colors.onAccent
                                    : widget.iconColor ?? colors.secondaryText,
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
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? colors.onAccent : colors.text,
                    ),
                  ),
                ),
                if (count != null)
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: DesktopMetrics.secondarySize,
                      color: selected ? colors.onAccent : colors.secondaryText,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
  const _SectionLabel(this.text, {this.action});

  final String text;
  final Widget? action;

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
              child: Text(
                text,
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
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
