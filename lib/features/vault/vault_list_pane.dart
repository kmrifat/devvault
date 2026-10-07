import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vault_core/vault_core.dart';

import '../../core/expiry.dart';
import '../../data/providers.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import 'vault_actions.dart';

/// Design frame D03's middle pane: what the sidebar selected, narrowed by
/// the All / Expiring / Files / Secrets tabs and the search, with the
/// selected item highlighted and an import drop zone at the bottom.
///
/// Like the sidebar, it reads everything from [uri] and changes it by
/// navigating, so the selection is a link.
class VaultListPane extends ConsumerWidget {
  const VaultListPane({super.key, required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(vaultSessionProvider);
    if (session is! Unlocked) return const SizedBox.shrink();
    final index = session.index;
    final now = ref.watch(clockProvider)();
    final filter = VaultFilter.fromUri(uri);
    final selected = uri.queryParameters['item'];
    final matching = filter.apply(index);
    final shown = [
      for (final item in matching)
        if (filter.kind.includes(item, now)) item,
    ];
    final quarantine = filter.view == VaultView.quarantine;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            filter: filter,
            apps: index.apps,
            count: quarantine ? index.quarantined.length : matching.length,
          ),
          if (!quarantine) ...[
            const SizedBox(height: 14),
            BCTabs<VaultKind>(
              fullWidth: true,
              value: filter.kind,
              onValueChange: (kind) =>
                  context.go(filter.withKind(kind).location(item: selected)),
              items: [
                for (final kind in VaultKind.values)
                  BCTabItem(value: kind, label: kind.label),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: quarantine
                ? _QuarantineList(slots: index.quarantined)
                : shown.isEmpty
                ? _Empty(filter: filter, vaultEmpty: index.items.isEmpty)
                : Align(
                    alignment: Alignment.topCenter,
                    child: _ItemList(
                      items: shown,
                      selected: selected,
                      now: now,
                      onSelect: (item) =>
                          context.go(filter.location(item: item.id)),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          const _DropZone(),
        ],
      ),
    );
  }
}

/// Where the list is (app › platform), what it is, how many, and Import.
class _Header extends StatelessWidget {
  const _Header({
    required this.filter,
    required this.apps,
    required this.count,
  });

  final VaultFilter filter;
  final Map<String, AppRecord> apps;
  final int count;

  String _appName(String id) =>
      id == VaultFilter.none ? 'No app' : apps[id]?.name ?? 'Unknown app';

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final app = filter.app;
    final platform = filter.platform;
    final crumbs = <String>[
      if (filter.view == null && filter.tag == null && app != null) ...[
        if (platform != null) _appName(app),
        if (platform != null && filter.env != null)
          VaultLabels.platform(platform == VaultFilter.none ? null : platform),
      ],
    ];
    final title = switch (filter) {
      VaultFilter(view: VaultView.conflicts) => 'Conflicts',
      VaultFilter(view: VaultView.quarantine) => 'Unreadable',
      VaultFilter(:final tag?) => '#$tag',
      VaultFilter(:final env?) => VaultLabels.environment(
        env == VaultFilter.none ? null : env,
      ),
      VaultFilter(platform: final platform?) => VaultLabels.platform(
        platform == VaultFilter.none ? null : platform,
      ),
      VaultFilter(:final app?) => _appName(app),
      _ => 'All items',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (crumbs.isNotEmpty) ...[
          Row(
            spacing: 6,
            children: [
              for (final (i, crumb) in crumbs.indexed) ...[
                if (i > 0)
                  Icon(LucideIcons.chevronRight, size: 13, color: bc.separator),
                Flexible(
                  child: BCText(
                    crumb,
                    type: BCTextType.bodySm,
                    color: BCTextColor.muted,
                    maxLines: 1,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ],
        Row(
          spacing: 10,
          children: [
            Expanded(
              child: Row(
                spacing: 10,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 24,
                        height: 1.2,
                        fontWeight: BCTypography.semiBold,
                        color: bc.foreground,
                      ),
                    ),
                  ),
                  BCChip(
                    size: BCChipSize.sm,
                    variant: BCChipVariant.secondary,
                    color: BCChipColor.defaultColor,
                    child: Text('$count'),
                  ),
                ],
              ),
            ),
            BCButton(
              size: BCButtonSize.sm,
              onPressed: () => openImport(context),
              startContent: const Icon(LucideIcons.filePlus2, size: 15),
              child: const Text('Import'),
            ),
            BCButton(
              size: BCButtonSize.sm,
              variant: BCButtonVariant.secondary,
              isIconOnly: true,
              onPressed: () => createItem(context, filter),
              child: const Icon(
                LucideIcons.plus,
                size: 16,
                semanticLabel: 'New item',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The rounded group of item rows, scrolling when it outgrows the pane.
class _ItemList extends StatelessWidget {
  const _ItemList({
    required this.items,
    required this.selected,
    required this.now,
    required this.onSelect,
  });

  final List<Item> items;
  final String? selected;
  final DateTime now;
  final ValueChanged<Item> onSelect;

  @override
  Widget build(BuildContext context) {
    return _Group(
      count: items.length,
      builder: (i) => _ItemRow(
        item: items[i],
        selected: items[i].id == selected,
        now: now,
        onTap: () => onSelect(items[i]),
      ),
    );
  }
}

/// bc_ui's list group look (one rounded surface, hairline separators) with
/// separators inset past the type icon, as in the design, and lazy rows.
class _Group extends StatelessWidget {
  const _Group({required this.count, required this.builder});

  final int count;
  final Widget Function(int index) builder;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final shape = BCShapes.continuous(BCRadius.xxxl);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: bc.surface, shape: shape),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: count,
          itemBuilder: (_, i) => builder(i),
          separatorBuilder: (_, _) => Padding(
            padding: const EdgeInsets.only(left: 66),
            child: Divider(height: 1, thickness: 1, color: bc.separator),
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    required this.item,
    required this.selected,
    required this.now,
    required this.onTap,
  });

  final Item item;
  final bool selected;
  final DateTime now;
  final VoidCallback onTap;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final item = widget.item;
    final file = item.attachments.firstOrNull?.filename;
    final typeLabel = item.type?.label ?? item.typeName;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${item.title}, $typeLabel',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ColoredBox(
            color: widget.selected
                ? bc.accentSoft
                : _hovered
                ? bc.surfaceHover
                : bc.surface.withValues(alpha: 0),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                spacing: 12,
                children: [
                  TypeIconTile(type: item.type ?? ItemType.genericFile),
                  Expanded(
                    child: Column(
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
                        if (file != null)
                          MonoText(
                            file,
                            middleEllipsis: true,
                            style: TextStyle(
                              fontSize: BCTypography.sizeXs,
                              color: bc.muted,
                            ),
                          )
                        else
                          BCText(
                            typeLabel,
                            type: BCTextType.bodyXs,
                            color: BCTextColor.muted,
                            maxLines: 1,
                          ),
                      ],
                    ),
                  ),
                  ?_trailing(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A conflict first, then the expiry: a chip when it needs attention,
  /// the month otherwise.
  Widget? _trailing(BuildContext context) {
    final item = widget.item;
    if (item.conflict != null) {
      return const BCChip(
        size: BCChipSize.sm,
        variant: BCChipVariant.secondary,
        color: BCChipColor.defaultColor,
        startContent: Icon(LucideIcons.gitMerge, size: 12),
        child: Text('Conflict'),
      );
    }
    final expiresAt = item.expiresAt;
    return switch (ExpiryState.of(item, widget.now)) {
      ExpiryState.none => null,
      ExpiryState.expired => const BCChip(
        size: BCChipSize.sm,
        variant: BCChipVariant.soft,
        color: BCChipColor.danger,
        child: Text('Expired'),
      ),
      ExpiryState.soon => BCChip(
        size: BCChipSize.sm,
        variant: BCChipVariant.soft,
        color: BCChipColor.warning,
        child: Text(daysLeft(expiresAt!, widget.now)),
      ),
      ExpiryState.valid => BCText(
        DateFormat.yMMM().format(expiresAt!.toLocal()),
        type: BCTextType.bodyXs,
        color: BCTextColor.muted,
      ),
    };
  }
}

/// Objects that failed to decrypt or parse. They stay on disk untouched;
/// another device or a backup may still have a good copy.
class _QuarantineList extends StatelessWidget {
  const _QuarantineList({required this.slots});

  final List<ObjectSlot> slots;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    if (slots.isEmpty) {
      return const BCEmptyState(
        icon: Icon(LucideIcons.shieldCheck),
        title: 'Everything is readable',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BCText(
          "These couldn't be decrypted on this device. They're left as they "
          'are on disk; another device or a backup may hold a good copy.',
          type: BCTextType.bodySm,
          color: BCTextColor.muted,
        ),
        const SizedBox(height: 14),
        Flexible(
          child: _Group(
            count: slots.length,
            builder: (i) => Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                spacing: 12,
                children: [
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: bc.dangerSoft,
                      shape: BCShapes.continuous(BCRadius.xl),
                    ),
                    child: SizedBox.square(
                      dimension: 40,
                      child: Icon(
                        LucideIcons.shieldAlert,
                        size: 20,
                        color: bc.dangerSoftForeground,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        BCText(
                          'Unreadable ${slots[i].type.wireName}',
                          weight: BCTextWeight.semibold,
                        ),
                        MonoText(
                          slots[i].objectId,
                          middleEllipsis: true,
                          style: TextStyle(
                            fontSize: BCTypography.sizeXs,
                            color: bc.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
    final (icon, title, description) = vaultEmpty && q == null
        ? (
            LucideIcons.vault,
            'Your vault is empty',
            'Import a credential file, or drop one below.',
          )
        : q != null
        ? (LucideIcons.searchX, 'No matches', 'Nothing here matches “$q”.')
        : (LucideIcons.layers, 'Nothing here', null);
    return Center(
      child: BCEmptyState(
        icon: Icon(icon),
        title: title,
        description: description,
      ),
    );
  }
}

/// Where files are dropped to import them (drag and drop lands with P1-18).
/// Clicking it opens the import dialog.
class _DropZone extends StatelessWidget {
  const _DropZone();

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final shape = BCShapes.continuous(
      BCRadius.xxxl,
      side: BorderSide(color: bc.border, width: 1.5),
    );
    return Semantics(
      button: true,
      label: 'Import a file',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => openImport(context),
          child: DecoratedBox(
            decoration: ShapeDecoration(shape: shape),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                spacing: 8,
                children: [
                  Icon(LucideIcons.download, size: 20, color: bc.muted),
                  const BCText(
                    'Drop a file to import',
                    type: BCTextType.bodySm,
                    weight: BCTextWeight.medium,
                  ),
                  MonoText(
                    '.p8 .p12 .cer .mobileprovision .jks .json .plist',
                    style: TextStyle(
                      fontSize: BCTypography.sizeXs,
                      color: bc.muted,
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
