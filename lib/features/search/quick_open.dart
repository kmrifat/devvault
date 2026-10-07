import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';

/// Opens quick-open (⌘K): type to find an item across the whole vault,
/// arrows to move, Enter to open. Resolves to the chosen item's id.
Future<String?> showQuickOpen(BuildContext context) => BCDialog.show<String>(
  context,
  isSwipeable: false,
  builder: (_) => const BCDialogContent(width: 560, child: QuickOpen()),
);

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
    final place = [
      if (app case final app?) app.name,
      if (item.platform != null) VaultLabels.platform(item.platform),
      if (item.environment != null) VaultLabels.environment(item.environment),
    ];
    final subtitle = [item.type?.label ?? item.typeName, ...place].join(' · ');
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
