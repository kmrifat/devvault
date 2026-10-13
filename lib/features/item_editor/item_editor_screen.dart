import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import 'item_draft.dart';
import 'item_editor.dart';

/// The item form as a page of its own on a phone (design frames I10 and
/// I11): a new item, placed where the user was looking, or an existing
/// one. It pops with the saved item's id, or nothing when cancelled.
class ItemEditorScreen extends ConsumerStatefulWidget {
  /// A new item, from the `/item/new` query: `type` (wire name), `app`,
  /// `platform`, `env`.
  const ItemEditorScreen.create({super.key, required this.query})
    : itemId = null;

  const ItemEditorScreen.edit({super.key, required String this.itemId})
    : query = const {};

  final String? itemId;
  final Map<String, String> query;

  @override
  ConsumerState<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends ConsumerState<ItemEditorScreen> {
  /// Made once: the form edits it in place.
  late final ItemDraft? _draft = _makeDraft();

  ItemDraft? _makeDraft() {
    final session = ref.read(vaultSessionProvider);
    if (widget.itemId case final id?) {
      final item = session is Unlocked ? session.index.items[id] : null;
      return item == null ? null : ItemDraft.edit(item);
    }
    final query = widget.query;
    return ItemDraft.create(
      ItemType.fromWireName(query['type'] ?? '') ?? ItemType.genericSecret,
      appId: query['app'],
      platform: query['platform'],
      environment: query['env'],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft == null) {
      return Scaffold(
        backgroundColor: context.bcTheme.background,
        appBar: const BCAppHeader(variant: BCAppHeaderVariant.solid),
        body: const Center(
          child: BCEmptyState(
            icon: Icon(LucideIcons.fileQuestion),
            title: 'This item isn’t in the vault',
            description: 'It may have been deleted on this or another device.',
          ),
        ),
      );
    }
    return ItemEditor(draft: draft);
  }
}
