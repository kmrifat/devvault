import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../data/vault_filter.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';
import '../app_editor/app_editor.dart';
import '../export/export_attachment.dart';
import '../import/import_dialog.dart';
import '../item_editor/item_editor.dart';

/// Opens the import dialog (design frame D04) for files the user chooses.
Future<void> openImport(BuildContext context) => showImportDialog(context);

/// Saves [attachment] of [item] to a file the user picks, byte for byte
/// (P1-19, [exportAttachment]).
Future<void> exportFile(
  BuildContext context,
  WidgetRef ref,
  Item item,
  Attachment attachment,
) => exportAttachment(context, ref, item, attachment);

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

/// Opens the form for a new app and shows it once saved.
Future<void> createApp(BuildContext context) async {
  final id = await showAppEditor(context);
  if (id != null && context.mounted) context.go(Routes.vault(app: id));
}

/// Opens the form for [app].
Future<void> editApp(BuildContext context, AppRecord app) =>
    showAppEditor(context, app: app);

/// Asks, then deletes [app]. Its [itemCount] items stay in the vault,
/// under "No app".
Future<void> deleteApp(
  BuildContext context,
  WidgetRef ref,
  AppRecord app, {
  required int itemCount,
}) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Delete “${app.name}”?',
    message: itemCount == 0
        ? 'The app is removed from this vault.'
        : 'The app is removed, but its ${itemCount == 1 ? 'item stays' : '$itemCount items stay'} '
              'in the vault under “No app”.',
    confirmLabel: 'Delete app',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  await ref.read(vaultSessionProvider.notifier).deleteApp(app.id);
  if (!context.mounted) return;
  context.go(Routes.vault());
  BCToast.show(
    context,
    BCToastData(
      title: '“${app.name}” deleted',
      variant: BCToastVariant.success,
    ),
  );
}
