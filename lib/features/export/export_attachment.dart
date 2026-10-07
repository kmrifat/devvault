import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/providers.dart';
import '../../data/vault_session.dart';
import '../../services/file_export.dart';
import '../../shared/ui.dart';

/// Saves [attachment] of [item] to a file the user picks, byte for byte
/// and under its original filename (P1-19).
///
/// The bytes are checked against the sha256 recorded at import before
/// anything is written; a mismatch writes nothing and says so. Toasts name
/// the file only, never its contents.
Future<void> exportAttachment(
  BuildContext context,
  WidgetRef ref,
  Item item,
  Attachment attachment,
) async {
  final session = ref.read(vaultSessionProvider);
  if (session is! Unlocked) return;
  final outcome = await ref
      .read(fileExportProvider)
      .export(session.vault, attachment);
  if (!context.mounted) return;
  final name = attachment.filename;
  final toast = switch (outcome) {
    ExportOutcome.saved => BCToastData(
      title: 'Saved $name',
      variant: BCToastVariant.success,
    ),
    ExportOutcome.cancelled => null,
    ExportOutcome.corrupt => BCToastData(
      title: 'Couldn’t export $name',
      description:
          'The stored copy doesn’t match the file that was imported, so '
          'nothing was saved.',
      variant: BCToastVariant.danger,
    ),
    ExportOutcome.failed => BCToastData(
      title: 'Couldn’t save $name',
      description: 'Try another folder.',
      variant: BCToastVariant.danger,
    ),
  };
  if (toast != null) BCToast.show(context, toast);
}
