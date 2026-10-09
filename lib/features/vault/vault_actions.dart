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
import 'organization_sheet.dart';

/// Opens the import dialog (design frame D04) for files the user chooses.
Future<void> openImport(BuildContext context) => showImportDialog(context);

/// Swaps [item]'s file for a new one, keeping the item (P4-04).
Future<void> replaceFile(BuildContext context, Item item) =>
    showReplaceFileDialog(context, item);

/// Saves [attachment] of [item] to a file the user picks, byte for byte
/// (P1-19, [exportAttachment]).
Future<void> exportFile(
  BuildContext context,
  WidgetRef ref,
  Item item,
  Attachment attachment,
) => exportAttachment(context, ref, item, attachment);

/// Opens the form for a new item, placed where [filter] is looking (or in
/// [app], when given), and selects it once saved.
Future<void> createItem(
  BuildContext context,
  VaultFilter filter, {
  String? app,
}) async {
  String? place(String? value) => value == VaultFilter.none ? null : value;
  final id = await showItemEditor(
    context,
    app: app ?? place(filter.app),
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

/// Opens the form for a new app, in [organization] when started from one,
/// and shows it once saved.
Future<void> createApp(BuildContext context, {String? organization}) async {
  final id = await showAppEditor(context, organization: organization);
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

/// Moves [item] to [place] in the tree (dropped on a sidebar row), with
/// Undo in the toast. Nothing else about the item changes.
Future<void> moveItem(
  BuildContext context,
  WidgetRef ref,
  Item item,
  TreePlace place,
) async {
  final session = ref.read(vaultSessionProvider);
  if (session is! Unlocked) return;
  // As stored now: a sync may have changed it since the drag began.
  final current = session.index.items[item.id];
  if (current == null || current.isReadOnly) return;
  if (place.holds(current, session.index)) return;
  final notifier = ref.read(vaultSessionProvider.notifier);
  final from = TreePlace.of(current);
  final to = place.label(session.index);
  final saved = await notifier.saveItem(place.applyTo(current));
  if (!context.mounted) return;
  BCToast.show(
    context,
    BCToastData(
      title: '“${current.title}” moved to $to',
      variant: BCToastVariant.success,
      actionLabel: 'Undo',
      onAction: () async {
        final current = ref.read(vaultSessionProvider);
        final now = current is Unlocked ? current.index.items[saved.id] : null;
        if (now != null) await notifier.saveItem(from.applyTo(now));
      },
    ),
  );
}

/// Moves [app] into [organization], or out of its own when null
/// ("Personal"), with Undo in the toast.
Future<void> moveApp(
  BuildContext context,
  WidgetRef ref,
  AppRecord app,
  String? organization,
) async {
  final session = ref.read(vaultSessionProvider);
  if (session is! Unlocked) return;
  // As stored now: a sync may have changed it since the drag began.
  final current = session.index.apps[app.id];
  if (current == null || current.organization == organization) return;
  final notifier = ref.read(vaultSessionProvider.notifier);
  final from = current.organization;
  // An empty string clears it.
  final saved = await notifier.saveApp(
    current.copyWith(organization: organization ?? ''),
  );
  if (!context.mounted) return;
  BCToast.show(
    context,
    BCToastData(
      title: organization == null
          ? '“${current.name}” moved out of $from'
          : '“${current.name}” moved to $organization',
      variant: BCToastVariant.success,
      actionLabel: 'Undo',
      onAction: () async {
        final current = ref.read(vaultSessionProvider);
        final now = current is Unlocked ? current.index.apps[saved.id] : null;
        if (now != null) {
          await notifier.saveApp(now.copyWith(organization: from ?? ''));
        }
      },
    ),
  );
}

/// Asks for a new name for [organization], then renames it: its records
/// and every app that names it. A name another organization already has
/// merges the two.
Future<void> renameOrganization(
  BuildContext context,
  WidgetRef ref,
  String organization,
) async {
  final name = await showOrganizationSheet(context, organization: organization);
  if (name == null || name == organization || !context.mounted) return;
  if (ref.read(vaultSessionProvider) is! Unlocked) return;
  await ref
      .read(vaultSessionProvider.notifier)
      .renameOrganization(organization, name);
  if (!context.mounted) return;
  final location = VaultFilter.fromUri(GoRouterState.of(context).uri);
  if (location.org == organization) {
    context.go(VaultFilter(org: name).withQuery(location.q).location());
  }
  BCToast.show(
    context,
    BCToastData(
      title: '“$organization” renamed to “$name”',
      variant: BCToastVariant.success,
    ),
  );
}

/// Asks for a name, then creates an organization with no apps, ready for
/// apps to be dragged in, and lists it. A name the vault already has just
/// lists that organization.
Future<void> createOrganization(BuildContext context, WidgetRef ref) async {
  final name = await showOrganizationSheet(context);
  if (name == null || !context.mounted) return;
  final session = ref.read(vaultSessionProvider);
  if (session is! Unlocked) return;
  if (!session.index.organizations.contains(name)) {
    final notifier = ref.read(vaultSessionProvider.notifier);
    await notifier.saveOrganization(notifier.newOrganization(name));
    if (!context.mounted) return;
  }
  context.go(Routes.vault(org: name));
}

/// Asks, then deletes [organization]. Its [appCount] apps and their items
/// stay, under Personal.
Future<void> deleteOrganization(
  BuildContext context,
  WidgetRef ref,
  String organization, {
  required int appCount,
}) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Delete “$organization”?',
    message: appCount == 0
        ? 'The organization is removed from this vault.'
        : 'The organization is removed, but its '
              '${appCount == 1 ? 'app stays' : '$appCount apps stay'}, with '
              'their items, under Personal.',
    confirmLabel: 'Delete organization',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  await ref
      .read(vaultSessionProvider.notifier)
      .deleteOrganization(organization);
  if (!context.mounted) return;
  if (VaultFilter.fromUri(GoRouterState.of(context).uri).org == organization) {
    context.go(Routes.vault());
  }
  BCToast.show(
    context,
    BCToastData(
      title: '“$organization” deleted',
      variant: BCToastVariant.success,
    ),
  );
}
