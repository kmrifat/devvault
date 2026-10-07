import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import '../item_editor/item_editor.dart';

/// Opens the import dialog (design frame D04).
///
/// The dialog arrives with P1-18 (`showImportDialog` in
/// `lib/features/import/import_dialog.dart`); until then this says so.
Future<void> openImport(BuildContext context) async {
  BCToast.show(
    context,
    const BCToastData(
      title: 'Import is on its way',
      description: 'Importing files arrives in the next update.',
    ),
  );
}

/// Saves [attachment] of [item] to a file the user picks, byte for byte.
///
/// Byte-exact export arrives with P1-19 (`exportAttachment` in
/// `lib/features/export/export_attachment.dart`); until then this says so.
Future<void> exportFile(
  BuildContext context,
  WidgetRef ref,
  Item item,
  Attachment attachment,
) async {
  BCToast.show(
    context,
    BCToastData(
      title: 'Export is on its way',
      description: 'Saving ${attachment.filename} arrives in the next update.',
    ),
  );
}

/// Opens the form for a new item, placed where [filter] is looking, and
/// selects it once saved.
Future<void> createItem(BuildContext context, VaultFilter filter) async {
  String? place(String? value) => value == VaultFilter.none ? null : value;
  final id = await showItemEditor(
    context,
    app: place(filter.app),
    platform: place(filter.platform),
    env: place(filter.env),
  );
  if (id != null && context.mounted) context.go(filter.location(item: id));
}

/// Opens the form for [item].
Future<void> editItem(BuildContext context, Item item) =>
    showItemEditor(context, item: item);

/// Asks, then deletes [item] and clears the selection.
Future<void> deleteItem(BuildContext context, WidgetRef ref, Item item) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Delete “${item.title}”?',
    message: item.attachments.isEmpty
        ? 'It will be removed from this vault, and from your other devices '
              'when they sync.'
        : 'It and its files will be removed from this vault, and from your '
              'other devices when they sync.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  final location = GoRouterState.of(context).uri;
  await ref.read(vaultSessionProvider.notifier).deleteItem(item.id);
  if (!context.mounted) return;
  context.go(VaultFilter.fromUri(location).location());
  BCToast.show(
    context,
    BCToastData(
      title: '“${item.title}” deleted',
      variant: BCToastVariant.success,
    ),
  );
}
