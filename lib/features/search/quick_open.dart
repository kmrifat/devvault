import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart';
import '../../shared/ui.dart';
import '../vault/desktop_item_type.dart' show DesktopTypeTile;

/// Opens quick-open (⌘K): type to find an item across the whole vault,
/// arrows to move, Enter to open. Resolves to the chosen item's id.
///
/// On desktop it floats near the top of the window, like Spotlight; on
/// phones it is a bc_ui dialog.
Future<String?> showQuickOpen(BuildContext context) {
  if (DesktopTheme.maybeOf(context) != null) {
    return showDesktopPanel<String>(context, builder: (_) => const QuickOpen());
  }
  return BCDialog.show<String>(
    context,
    isSwipeable: false,
    builder: (_) => const BCDialogContent(width: 560, child: QuickOpen()),
  );
}

/// The quick-open panel: a search field over the vault's searchable
/// metadata (never secrets or notes) and the best matches.
class QuickOpen extends ConsumerStatefulWidget {
  const QuickOpen({super.key});

  /// How many matches are listed.
  static const maxResults = 8;

  @override
  ConsumerState<QuickOpen> createState() => _QuickOpenState();
}

class _QuickOpenState extends ConsumerState<QuickOpen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  int _highlight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// With no query, the most recently changed items.
  List<Item> _results(VaultIndex index) {
    final query = _query.text.trim();
    if (query.isEmpty) {
      return (index.all.toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
          .take(QuickOpen.maxResults)
          .toList();
    }
    return index.filter(query: query).take(QuickOpen.maxResults).toList();
  }

  KeyEventResult _onKey(List<Item> results, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown && results.isNotEmpty) {
      setState(() => _highlight = (_highlight + 1) % results.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && results.isNotEmpty) {
      setState(
        () => _highlight = (_highlight - 1 + results.length) % results.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && results.isNotEmpty) {
      Navigator.of(context).pop(results[_highlight].id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionProvider);
    if (session is! Unlocked) return const SizedBox.shrink();
    final index = session.index;
    final results = _results(index);
    if (_highlight >= results.length) _highlight = 0;
    final empty = _query.text.trim().isEmpty;
    if (DesktopTheme.maybeOf(context) != null) {
      return _desktop(context, index, results, empty: empty);
    }

    return Focus(
      onKeyEvent: (_, event) => _onKey(results, event),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BCSearchField(
            controller: _query,
            focusNode: _focus,
            placeholder: 'Open an item…',
            onChanged: (_) => setState(() => _highlight = 0),
            onSubmitted: (_) {
              if (results.isNotEmpty) {
                Navigator.of(context).pop(results[_highlight].id);
              }
            },
          ),
          const SizedBox(height: BCSpacing.md),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: BCSpacing.lg),
              child: BCText(
                empty ? 'The vault is empty' : 'No matches',
                align: TextAlign.center,
                color: BCTextColor.muted,
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: BCSpacing.xs),
              child: BCText(
                empty ? 'Recently changed' : 'Items',
                type: BCTextType.bodyXs,
                color: BCTextColor.muted,
              ),
            ),
            for (final (i, item) in results.indexed)
              _ResultRow(
                item: item,
                app: index.apps[item.appId],
                highlighted: i == _highlight,
                onHover: () => setState(() => _highlight = i),
                onTap: () => Navigator.of(context).pop(item.id),
              ),
          ],
          const SizedBox(height: BCSpacing.sm),
          const BCText(
            '↑↓ to move · Enter to open · Esc to close. Secrets and notes '
            'aren’t searched.',
            type: BCTextType.bodyXs,
            color: BCTextColor.muted,
            align: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Desktop: a Spotlight-style panel. The search field on top, the
  /// matches under it, the keys along the bottom.
  Widget _desktop(
    BuildContext context,
    VaultIndex index,
    List<Item> results, {
    required bool empty,
  }) {
    final colors = context.desktopColors;
    final secondary = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    final line = Container(height: 0.5, color: colors.innerSeparator);
    return DesktopPanel(
      semanticLabel: 'Quick open',
      child: Focus(
        onKeyEvent: (_, event) => _onKey(results, event),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: DesktopSearchField(
                controller: _query,
                focusNode: _focus,
                placeholder: 'Open an item…',
                onChanged: (_) => setState(() => _highlight = 0),
              ),
            ),
            line,
            if (results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  empty ? 'The vault is empty' : 'No matches',
                  textAlign: TextAlign.center,
                  style: secondary.copyWith(fontSize: DesktopMetrics.bodySize),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                      child: Text(
                        empty ? 'Recently changed' : 'Items',
                        style: secondary.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (final (i, item) in results.indexed)
                      _DesktopResultRow(
                        item: item,
                        subtitle: _subtitle(item, index.apps[item.appId]),
                        highlighted: i == _highlight,
                        onHover: () => setState(() => _highlight = i),
                        onTap: () => Navigator.of(context).pop(item.id),
                      ),
                  ],
                ),
              ),
            line,
            ColoredBox(
              color: colors.bar,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                child: Text(
                  '↑↓ to move · Enter to open · Esc to close. Secrets and '
                  'notes aren’t searched.',
                  style: secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A result's second line: its type, then where it belongs.
String _subtitle(Item item, AppRecord? app) => [
  item.type?.label ?? item.typeName,
  if (app case final app?) app.label,
  if (item.platform != null) VaultLabels.platform(item.platform),
  if (item.environment != null) VaultLabels.environment(item.environment),
].join(' · ');

class _DesktopResultRow extends StatelessWidget {
  const _DesktopResultRow({
    required this.item,
    required this.subtitle,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final Item item;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final text = highlighted ? colors.onAccent : colors.text;
    return Semantics(
      button: true,
      selected: highlighted,
      label: '${item.title}, $subtitle',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: highlighted ? colors.accent : null,
              borderRadius: const BorderRadius.all(
                Radius.circular(DesktopMetrics.menuRadius),
              ),
            ),
            child: SizedBox(
              height: DesktopMetrics.tableRowHeight + 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  spacing: 10,
                  children: [
                    DesktopTypeTile(
                      type: item.type,
                      size: DesktopMetrics.toolbarSearchHeight,
                      selected: highlighted,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 1,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: DesktopMetrics.bodySize,
                              fontWeight: FontWeight.w500,
                              color: text,
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: DesktopMetrics.secondarySize,
                              color: highlighted
                                  ? colors.onAccent
                                  : colors.secondaryText,
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
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.item,
    required this.app,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final Item item;
  final AppRecord? app;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final subtitle = _subtitle(item, app);
    return Semantics(
      button: true,
      selected: highlighted,
      label: '${item.title}, $subtitle',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: highlighted
                  ? bc.accentSoft
                  : bc.background.withValues(alpha: 0),
              shape: BCShapes.continuous(BCRadius.xxl),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                spacing: 12,
                children: [
                  TypeIconTile(
                    type: item.type ?? ItemType.genericFile,
                    size: 32,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        BCText(
                          item.title,
                          weight: BCTextWeight.medium,
                          maxLines: 1,
                        ),
                        BCText(
                          subtitle,
                          type: BCTextType.bodyXs,
                          color: BCTextColor.muted,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  if (highlighted)
                    Icon(LucideIcons.cornerDownLeft, size: 14, color: bc.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
