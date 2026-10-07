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
