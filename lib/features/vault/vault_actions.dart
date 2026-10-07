import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../shared/ui.dart';

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
