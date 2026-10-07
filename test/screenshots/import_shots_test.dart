@Tags(['golden'])
library;

import 'dart:io';

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/features/import/import_dialog.dart';
import 'package:devvault/features/import/import_draft.dart';
import 'package:devvault/services/file_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Always offers the same file, as if the user picked it.
class _PickOne implements FileOpener {
  const _PickOne(this.name);

  final String name;

  @override
  Future<List<PickedFile>> pick() async => [
    PickedFile(
      name: name,
      bytes: File('packages/cred_parsers/test/fixtures/$name')
          .readAsBytesSync(),
    ),
  ];
}

void main() {
  setUpAll(loadAppFonts);

  /// Opens the import dialog on [name] and waits for it to be read (the
  /// parse runs on an isolate, which needs real time).
  Future<void> importFile(WidgetTester tester) async {
    await tester.tap(find.text('Import').first);
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find.text('Used for').evaluate().isNotEmpty) break;
    }
    expect(find.byType(ImportDialog), findsOneWidget);
  }

  final overrides = [
    fileOpenerProvider.overrideWithValue(
      const _PickOne('AuthKey_TESTKEY123.p8'),
    ),
  ];

  shot(
    'D04-import',
    Routes.vault(),
    sample: true,
    overrides: overrides,
    interact: importFile,
  );
  shot(
    'D04-import-light',
    Routes.vault(),
    sample: true,
    overrides: overrides,
    interact: importFile,
    brightness: Brightness.light,
  );
}
