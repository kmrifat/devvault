import 'dart:io';
import 'dart:typed_data';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/vault/item_screen.dart';
import 'package:devvault/features/vault/mobile_vault_screen.dart';
import 'package:devvault/services/share_sheet_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  group('ShareSheetSaver', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('share_test_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('the file exists only while the sheet is open', () async {
      String? sharedPath;
      List<int>? sharedBytes;
      final saver = ShareSheetSaver(
        tempRoot: temp,
        share: (path, name, mime) async {
          sharedPath = path;
          sharedBytes = File(path).readAsBytesSync();
          expect(name, 'upload.jks');
          expect(mime, 'application/x-java-keystore');
          return true;
        },
      );
      final ok = await saver.save(
        fileName: 'upload.jks',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'application/x-java-keystore',
      );
      expect(ok, isTrue);
      expect(sharedBytes, [1, 2, 3]);
      expect(File(sharedPath!).existsSync(), isFalse);
      expect(temp.listSync(), isEmpty);
    });

    test('dismissing still cleans up, and says so', () async {
      final saver = ShareSheetSaver(
        tempRoot: temp,
        share: (_, _, _) async => false,
      );
      expect(await saver.save(fileName: 'x.p8', bytes: Uint8List(4)), isFalse);
      expect(temp.listSync(), isEmpty);
    });

    test('a failed share still cleans up', () async {
      final saver = ShareSheetSaver(
        tempRoot: temp,
        share: (_, _, _) async => throw StateError('no sheet'),
      );
      await expectLater(
        saver.save(fileName: 'x.p8', bytes: Uint8List(4)),
        throwsStateError,
      );
      expect(temp.listSync(), isEmpty);
    });

    test('sweep removes copies an earlier crash left', () {
      Directory('${temp.path}/devvault-share-abc').createSync();
      File('${temp.path}/devvault-share-abc/key.p8').writeAsStringSync('x');
      Directory('${temp.path}/someone-else').createSync();
      ShareSheetSaver.sweep(temp);
      expect(temp.listSync().map((e) => e.path.split('/').last), [
        'someone-else',
      ]);
    });
  });

  group('screen', () {
    late Directory temp;
    late List<List<int>> shared;

    Future<void> open(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 1800 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      temp = Directory.systemTemp.createTempSync('share_screen_');
      addTearDown(() => temp.deleteSync(recursive: true));
      shared = [];
      await pumpUnlockedApp(
        tester,
        location: Routes.vault(),
        vault: TestVault.sample,
        layout: AppLayout.mobile,
        overrides: [
          fileSaverProvider.overrideWithValue(
            ShareSheetSaver(
              tempRoot: temp,
              share: (path, _, _) async {
                shared.add(File(path).readAsBytesSync());
                return true;
              },
            ),
          ),
        ],
      );
      await tester.tap(
        find.descendant(
          of: find.byType(MobileVaultScreen),
          matching: find.text('Upload keystore'),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder inItem(String text) =>
        find.descendant(of: find.byType(ItemScreen), matching: find.text(text));

    testWidgets('shows the item in its compact layout', (tester) async {
      await open(tester);
      expect(find.byType(ItemScreen), findsOneWidget);
      expect(inItem('Upload keystore'), findsWidgets);
      expect(inItem('Android Keystore'), findsOneWidget);
      expect(inItem('Kitchenly · Android · Production'), findsOneWidget);
      expect(inItem('Store password'), findsOneWidget);
      expect(find.textContaining('kitchenly-store-pass'), findsNothing);
      expect(inItem('Export'), findsOneWidget);
    });

    testWidgets('export goes through the share sheet, byte for byte', (
      tester,
    ) async {
      await open(tester);
      final file = (appContainer(tester).read(vaultSessionProvider) as Unlocked)
          .index
          .all
          .firstWhere((i) => i.title == 'Upload keystore')
          .attachments
          .single;
      await tester.tap(inItem('Export'));
      for (
        var i = 0;
        i < 300 && (shared.isEmpty || temp.listSync().isNotEmpty);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(shared, hasLength(1));
      expect(shared.single, hasLength(file.size));
      expect(temp.listSync(), isEmpty);
      await tester.pumpAndSettle(const Duration(seconds: 10));
    });
  });
}
