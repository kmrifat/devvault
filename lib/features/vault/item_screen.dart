import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import 'item_detail_pane.dart';
import 'vault_actions.dart';

/// Design frame I5: one item on a phone, pushed from the list. Export
/// opens the share sheet there (ShareSheetSaver).
class ItemScreen extends ConsumerWidget {
  const ItemScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(vaultSessionProvider);
    final item = session is Unlocked ? session.index.items[itemId] : null;
    // The item's own header carries the title; the bar goes back and holds
    // Edit and ⋯. On iPhone the bar is UIKit's, and ⋯ its action sheet.
    return Scaffold(
      backgroundColor: context.bcTheme.background,
      appBar: ref.watch(nativeBarsProvider)
          ? NativePhoneHeader(
              title: '',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go(Routes.vault()),
              actions: [
                if (item != null && !item.isReadOnly)
                  NativeHeaderAction(
                    id: 'edit',
                    symbol: 'pencil',
                    label: 'Edit',
                    onPressed: () => editItem(context, item),
                  ),
                if (item != null)
                  NativeHeaderAction(
                    id: 'more',
                    symbol: 'ellipsis',
                    label: 'More actions',
                    onPressed: () => showItemMoreActions(context, ref, item),
                  ),
              ],
            )
          : BCAppHeader(
              variant: BCAppHeaderVariant.solid,
              actions: [
                if (item != null && !item.isReadOnly)
                  BCHeaderIconButton(
                    size: 48,
                    icon: const Icon(LucideIcons.pencil, semanticLabel: 'Edit'),
                    onPressed: () => editItem(context, item),
                  ),
                if (item != null)
                  BCMenu(
                    alignment: BCOverlayAlignment.end,
                    trigger: (context, controller) => BCHeaderIconButton(
                      size: 48,
                      icon: const Icon(
                        LucideIcons.ellipsis,
                        semanticLabel: 'More actions',
                      ),
                      onPressed: controller.toggle,
                    ),
                    children: [
                      if (!item.isReadOnly && item.attachments.isNotEmpty)
                        BCMenuItem(
                          title: 'Replace file…',
                          icon: const Icon(LucideIcons.fileUp),
                          onSelected: () => replaceFile(context, item),
                        ),
                      BCMenuItem(
                        title: 'Delete item…',
                        icon: const Icon(LucideIcons.trash2),
                        variant: BCMenuItemVariant.danger,
                        onSelected: () => deleteItem(context, ref, item),
                      ),
                    ],
                  ),
              ],
            ),
      body: ItemDetailPane(itemId: itemId),
    );
  }
}
