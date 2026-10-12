import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../core/search_match.dart';
import '../../data/providers.dart';
import '../../data/search_query.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import '../vault/vault_item_row.dart' show itemStatus;

/// The phone's Search tab (design frames I2–I4).
///
/// With nothing typed it lists what the vault holds, to browse: item
/// types, apps, platforms, environments and tags, each with its count.
/// Typing (or picking one of those) lists the matching items, each with
/// the field that matched. Secret values are never searched.
///
/// On iPhone the field is in the tab bar's place, at the bottom
/// (`MobileShell`); elsewhere it sits under the title.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, required this.uri});

  final Uri uri;

  /// The field's placeholder, here and in the iPhone's search bar.
  static const placeholder = 'Search vault';

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with LargeTitleScroll {
  late final _field = TextEditingController(text: _query.q ?? '');

  SearchQuery get _query => SearchQuery.fromUri(widget.uri);

  @override
  void didUpdateWidget(SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final q = _query.q ?? '';
    if (q.trim() != _field.text.trim()) _field.text = q;
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _go(SearchQuery query) => context.go(query.location());

  /// A pick from Browse or a scope removed: the keyboard goes away, since
  /// it's the list that changed.
  void _pick(SearchQuery query) {
    FocusManager.instance.primaryFocus?.unfocus();
    _go(query);
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final session = ref.watch(vaultSessionProvider);
    if (session is! Unlocked) return const SizedBox.shrink();
    final index = session.index;
    final now = ref.watch(clockProvider)();
    final query = _query;
    final native = ref.watch(nativeBarsProvider);

    final slivers = <Widget>[
      if (native) ...[
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                MediaQuery.paddingOf(context).top + NativePhoneHeader.barHeight,
          ),
        ),
        const SliverToBoxAdapter(
          child: PhoneLargeTitle(
            'Search',
            subtitle: BCText(
              'Titles, bundle IDs, key IDs, file names and tags',
              type: BCTextType.bodySm,
              color: BCTextColor.muted,
            ),
          ),
        ),
      ] else ...[
        const BCSliverAppHeader(largeTitle: Text('Search')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Semantics(
              label: 'Search',
              child: BCSearchField(
                controller: _field,
                placeholder: SearchScreen.placeholder,
                onChanged: (q) => _go(query.withQ(q)),
                onClear: () => _go(query.withQ('')),
              ),
            ),
          ),
        ),
      ],
      if (query.isScoped)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ScopeChip(
                label: _scopeLabel(index, query),
                onRemove: () => _pick(query.unscoped),
              ),
            ),
          ),
        ),
      if (query.isBrowse)
        ..._browse(context, index)
      else
        ..._results(context, index, query, now),
      // Room for the tab bar or the search bar over the list.
      const SliverToBoxAdapter(child: SizedBox(height: 120)),
    ];

    return Scaffold(
      backgroundColor: bc.background,
      extendBodyBehindAppBar: native,
      appBar: native
          ? NativePhoneHeader(title: titleInBar ? 'Search' : '')
          : null,
      body: CustomScrollView(
        controller: titleScroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: slivers,
      ),
    );
  }

  /// Browse: what the vault holds, by type, app, platform, environment
  /// and tag. Only what exists is listed, with real counts.
  List<Widget> _browse(BuildContext context, VaultIndex index) {
    final items = index.all.toList();
    if (items.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: BCEmptyState(
              icon: Icon(LucideIcons.vault),
              title: 'Your vault is empty',
              description: 'Import a credential file to start.',
            ),
          ),
        ),
      ];
    }

    final byType = <String, int>{};
    for (final item in items) {
      byType.update(item.typeName, (n) => n + 1, ifAbsent: () => 1);
    }
    final known = [for (final type in ItemType.values) type.wireName];
    final types = byType.keys.toList()
      ..sort((a, b) {
        final ia = known.indexOf(a), ib = known.indexOf(b);
        if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
        if (ia >= 0) return -1;
        if (ib >= 0) return 1;
        return a.compareTo(b);
      });

    final apps = index.apps.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    int countFor(AppRecord app) => items.where((i) => i.appId == app.id).length;

    Map<String, int> counted(Iterable<String?> values) {
      final counts = <String, int>{};
      for (final value in values) {
        if (value == null) continue;
        counts.update(value, (n) => n + 1, ifAbsent: () => 1);
      }
      return Map.fromEntries(
        counts.entries.toList()
          ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
      );
    }

    final platforms = counted(items.map((i) => i.platform));
    final envs = counted(items.map((i) => i.environment));
    final tags = counted(items.expand((i) => i.tags));

    return [
      _section(
        'Types',
        Column(
          spacing: 8,
          children: [
            for (var i = 0; i < types.length; i += 2)
              Row(
                spacing: 8,
                children: [
                  for (final name in types.skip(i).take(2))
                    Expanded(
                      child: _TypeTile(
                        typeName: name,
                        count: byType[name]!,
                        onPressed: () => _pick(SearchQuery(type: name)),
                      ),
                    ),
                  if (i + 1 >= types.length) const Expanded(child: SizedBox()),
                ],
              ),
          ],
        ),
      ),
      if (apps.isNotEmpty)
        _section(
          'Apps',
          BCListGroup(
            children: [
              for (final app in apps)
                BCListGroupItem(
                  prefix: AppBadge(app: app, size: 28),
                  title: app.name,
                  suffix: _Count(countFor(app), chevron: true),
                  onPressed: () => _pick(SearchQuery(app: app.id)),
                ),
            ],
          ),
        ),
      if (platforms.isNotEmpty || envs.isNotEmpty || tags.isNotEmpty)
        _section(
          'Platforms, environments and tags',
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final MapEntry(:key, :value) in platforms.entries)
                _CountChip(
                  label: key,
                  count: value,
                  onPressed: () => _pick(SearchQuery(platform: key)),
                ),
              for (final MapEntry(:key, :value) in envs.entries)
                _CountChip(
                  label: key,
                  count: value,
                  onPressed: () => _pick(SearchQuery(env: key)),
                ),
              for (final MapEntry(:key, :value) in tags.entries)
                _CountChip(
                  label: '#$key',
                  count: value,
                  onPressed: () => _pick(SearchQuery(tag: key)),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _results(
    BuildContext context,
    VaultIndex index,
    SearchQuery query,
    DateTime now,
  ) {
    final results = query.apply(index);
    if (results.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: [
                  BCEmptyState(
                    icon: const Icon(LucideIcons.searchX),
                    title: 'No matches',
                    description: query.q == null
                        ? 'Nothing in the vault is in this group.'
                        : 'Nothing in the vault contains “${query.q!.trim()}”. '
                              'Search covers titles, types, apps, bundle IDs, '
                              'file names, tags and fields that aren’t secret.',
                  ),
                  const BCChip(
                    variant: BCChipVariant.secondary,
                    color: BCChipColor.defaultColor,
                    startContent: Icon(LucideIcons.lock, size: 14),
                    child: Text('Secret values are never searched'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }
    final q = query.q ?? '';
    return [
      _section(
        results.length == 1 ? '1 result' : '${results.length} results',
        BCListGroup(
          children: [
            for (final item in results)
              BCListGroupItem(
                prefix: TypeIconTile(type: item.type ?? ItemType.genericFile),
                content: _ResultText(
                  item: item,
                  match: SearchMatch.of(item, index.apps[item.appId], q),
                ),
                suffix:
                    itemStatus(item, now) ??
                    Icon(
                      LucideIcons.chevronRight,
                      size: 18,
                      color: context.bcTheme.separator,
                    ),
                onPressed: () => context.push(Routes.item(item.id)),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _section(String title, Widget child) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
    sliver: SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              header: true,
              child: BCText(
                title.toUpperCase(),
                type: BCTextType.bodyXs,
                weight: BCTextWeight.semibold,
                color: BCTextColor.muted,
              ),
            ),
          ),
          child,
        ],
      ),
    ),
  );

  static String _scopeLabel(VaultIndex index, SearchQuery query) {
    if (query.type case final type?) {
      return switch (ItemType.fromWireName(type)) {
        final t? => _TypeTile.shortLabel(t),
        null => type,
      };
    }
    if (query.app case final app?) return index.apps[app]?.name ?? 'App';
    if (query.tag case final tag?) return '#$tag';
    return query.platform ?? query.env ?? '';
  }
}

/// One type in Browse: its tile, a short plural name and how many items.
class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.typeName,
    required this.count,
    required this.onPressed,
  });

  final String typeName;
  final int count;
  final VoidCallback onPressed;

  static String shortLabel(ItemType type) => switch (type) {
    ItemType.appleAuthKey => 'Auth keys',
    ItemType.appleCertificate => 'Certificates',
    ItemType.provisioningProfile => 'Profiles',
    ItemType.androidKeystore => 'Keystores',
    ItemType.firebaseConfig => 'Firebase',
    ItemType.gcpServiceAccount => 'Accounts',
    ItemType.oauthClient => 'OAuth clients',
    ItemType.sshKey => 'SSH keys',
    ItemType.genericFile => 'Files',
    ItemType.genericSecret => 'Secrets',
    ItemType.secureNote => 'Notes',
  };

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final type = ItemType.fromWireName(typeName);
    final shape = BCShapes.continuous(BCRadius.xxl);
    return Semantics(
      button: true,
      label: '${type?.label ?? typeName}, $count',
      excludeSemantics: true,
      child: BCPressable(
        onPressed: onPressed,
        shape: shape,
        background: DecoratedBox(
          decoration: ShapeDecoration(color: bc.surface, shape: shape),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            spacing: 10,
            children: [
              TypeIconTile(type: type ?? ItemType.genericFile, size: 32),
              Expanded(
                child: BCText(
                  type == null ? typeName : shortLabel(type),
                  type: BCTextType.bodySm,
                  weight: BCTextWeight.medium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _Count(count),
            ],
          ),
        ),
      ),
    );
  }
}

/// A count at the end of a row, with a chevron when the row opens more.
class _Count extends StatelessWidget {
  const _Count(this.count, {this.chevron = false});

  final int count;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        BCText('$count', type: BCTextType.bodySm, color: BCTextColor.muted),
        if (chevron)
          Icon(
            LucideIcons.chevronRight,
            size: 18,
            color: context.bcTheme.separator,
          ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.onPressed,
  });

  final String label;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return BCChip(
      variant: BCChipVariant.secondary,
      color: BCChipColor.defaultColor,
      endContent: BCText(
        '$count',
        type: BCTextType.bodyXs,
        color: BCTextColor.muted,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// The scope picked from Browse, removable.
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Remove filter $label',
      excludeSemantics: true,
      child: BCChip(
        variant: BCChipVariant.soft,
        color: BCChipColor.accent,
        endContent: const Icon(LucideIcons.x, size: 14),
        onPressed: onRemove,
        child: Text(label),
      ),
    );
  }
}

/// A result's title and, under it, the field that matched with the
/// matching text highlighted (or the type, when the title matched).
class _ResultText extends StatelessWidget {
  const _ResultText({required this.item, required this.match});

  final Item item;
  final SearchMatch? match;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final match = this.match;
    final valueStyle = match != null && match.mono
        ? AppText.mono(context, fontSize: BCTypography.sizeXs, color: bc.muted)
        : TextStyle(fontSize: BCTypography.sizeXs, color: bc.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 3,
      children: [
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            height: 1.2,
            fontWeight: BCTypography.semiBold,
            color: bc.foreground,
          ),
        ),
        if (match == null)
          BCText(
            item.type?.label ?? item.typeName,
            type: BCTextType.bodyXs,
            color: BCTextColor.muted,
            maxLines: 1,
          )
        else
          Row(
            spacing: 6,
            children: [
              BCText(
                match.label,
                type: BCTextType.bodyXs,
                color: BCTextColor.muted,
              ),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    style: valueStyle,
                    children: [
                      if (match.start case final start?) ...[
                        TextSpan(text: match.value.substring(0, start)),
                        TextSpan(
                          text: match.value.substring(start, match.end),
                          style: TextStyle(
                            color: bc.foreground,
                            backgroundColor: bc.accentSoft,
                          ),
                        ),
                        TextSpan(text: match.value.substring(match.end!)),
                      ] else
                        TextSpan(text: match.value),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
