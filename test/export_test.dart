import 'dart:io';
import 'dart:typed_data';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/vault/item_detail_pane.dart';
import 'package:devvault/services/file_export.dart';
import 'package:devvault/services/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';
import 'toasts.dart';

/// Records what would have been written, or cancels.
class RecordingFileSaver implements FileSaver {
  bool cancel = false;
  Object? error;
  final saves = <({String fileName, Uint8List bytes, String mimeType})>[];

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    if (error case final e?) throw e;
    if (cancel) return false;
    // A copy: the exporter zeroes its buffer once the save returns.
    saves.add((
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      mimeType: mimeType,
    ));
    return true;
  }
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  setUpAll(loadTestCrypto);

  late RecordingFileSaver saver;

  Vault vaultOf(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;

  Finder saveButtons() => find.descendant(
    of: find.byType(ItemDetailPane),
    matching: find.text('Save as…'),
  );

  /// Opens an empty unlocked vault on the desktop layout.
  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    saver = RecordingFileSaver();
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      layout: AppLayout.desktop,
      overrides: [fileSaverProvider.overrideWithValue(saver)],
    );
  }

  /// Adds an item holding [files] (filename → bytes) and selects it.
  Future<Item> addItem(
    WidgetTester tester,
    Map<String, Uint8List> files, {
    String mime = 'application/octet-stream',
  }) async {
    final notifier = appContainer(tester).read(vaultSessionProvider.notifier);
    final item = await tester.runAsync(() async {
      final vault = vaultOf(tester);
      final attachments = [
        for (final MapEntry(:key, :value) in files.entries)
          await vault.addAttachment(value, filename: key, mime: mime),
      ];
      return notifier.saveItem(
        notifier
            .newItem(ItemType.genericFile, 'Files')
            .copyWith(attachments: attachments),
      );
    });
    GoRouter.of(tester.element(find.byType(ItemDetailPane)))
        .go(Routes.vault(item: item!.id));
    await tester.pumpAndSettle();
    return item;
  }

  /// Taps the [index]th "Save as…" and waits for the export to finish,
  /// which decrypts on a real event loop.
  Future<void> saveAs(WidgetTester tester, [int index = 0]) async {
    final button = saveButtons().at(index);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final before = saver.saves.length;
    await tester.tap(button);
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (saver.saves.length > before) break;
    }
  }

  Future<void> dismissToasts(WidgetTester tester) =>
      tester.pumpAndSettle(const Duration(seconds: 10));

  final keystore = Uint8List.fromList(List.generate(4099, (i) => i * 7 % 256));

  testWidgets('saves the original bytes under the original filename', (
    tester,
  ) async {
    await open(tester);
    final item = await addItem(tester, {
      'upload.jks': keystore,
    }, mime: 'application/x-java-keystore');
    final attachment = item.attachments.single;

    await saveAs(tester);
    final saved = saver.saves.single;
    expect(saved.fileName, 'upload.jks');
    expect(saved.mimeType, 'application/x-java-keystore');
    expect(saved.bytes, keystore);
    expect(hex(VaultCrypto.sha256(saved.bytes)), attachment.sha256);
    expect(find.text('Saved upload.jks'), findsOneWidget);
    await dismissToasts(tester);
  });

  testWidgets('the header Export button saves the first file', (tester) async {
    await open(tester);
    await addItem(tester, {'upload.jks': keystore});
    await tester.tap(
      find.descendant(
        of: find.byType(ItemDetailPane),
        matching: find.text('Export'),
      ),
    );
    for (var i = 0; i < 50 && saver.saves.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(saver.saves.single.fileName, 'upload.jks');
    expect(saver.saves.single.bytes, keystore);
    await dismissToasts(tester);
  });

  testWidgets('cancelling writes nothing and says nothing', (tester) async {
    await open(tester);
    await addItem(tester, {'upload.jks': keystore});
    saver.cancel = true;
    await saveAs(tester);
    await tester.pump();
    expect(saver.saves, isEmpty);
    expect(find.textContaining('Saved'), findsNothing);
    expect(find.textContaining('Couldn’t'), findsNothing);
    await dismissToasts(tester);
  });

  testWidgets('a sha256 mismatch writes nothing and says so', (tester) async {
    await open(tester);
    final item = await addItem(tester, {'upload.jks': keystore});
    final real = item.attachments.single;
    // The record claims different bytes than the blob holds.
    final tampered = Attachment(
      blobId: real.blobId,
      filename: real.filename,
      mime: real.mime,
      size: real.size,
      sha256: hex(VaultCrypto.sha256(Uint8List(4))),
    );
    final notifier = appContainer(tester).read(vaultSessionProvider.notifier);
    await tester.runAsync(
      () => notifier.saveItem(item.copyWith(attachments: [tampered])),
    );
    await tester.pumpAndSettle();

    await saveAs(tester);
    await tester.pump();
    expect(saver.saves, isEmpty);
    expect(find.text('Couldn’t export upload.jks'), findsOneWidget);
    await dismissToasts(tester);
  });

  testWidgets('a missing or swapped blob writes nothing and says so', (
    tester,
  ) async {
    await open(tester);
    final item = await addItem(tester, {
      'a.p12': keystore,
      'b.p12': Uint8List.fromList(keystore.reversed.toList()),
    });
    final [a, b] = item.attachments;
    final store = vaultOf(tester).store;
    await tester.runAsync(() async {
      // b's envelope under a's id: sealed for another slot, so it won't open.
      final other = (await store.read(ObjectType.blob, b.blobId))!;
      await store.delete(ObjectType.blob, a.blobId);
      await store.write(ObjectType.blob, a.blobId, other);
      await store.delete(ObjectType.blob, b.blobId);
    });

    await saveAs(tester, 0);
    await tester.pump();
    expect(find.text('Couldn’t export a.p12'), findsOneWidget);
    await dismissToasts(tester);
    await saveAs(tester, 1);
    await tester.pump();
    expect(find.text('Couldn’t export b.p12'), findsOneWidget);
    expect(saver.saves, isEmpty);
    await dismissToasts(tester);
  });

  testWidgets('a failed write says so without the error', (tester) async {
    await open(tester);
    await addItem(tester, {'upload.jks': keystore});
    saver.error = const FileSystemException('denied', '/secret/path');
    await saveAs(tester);
    await tester.pump();
    expect(find.text('Couldn’t save upload.jks'), findsOneWidget);
    expect(find.textContaining('/secret/path'), findsNothing);
    expect(find.textContaining('denied'), findsNothing);
    expectNoSecretInToasts(tester, ['/secret/path', 'denied']);
    await dismissToasts(tester);
  });

  testWidgets('every parser fixture exports byte for byte', (tester) async {
    await open(tester);
    final fixtures = await tester.runAsync(() async {
      final dir = Directory('packages/cred_parsers/test/fixtures');
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => !f.path.endsWith('README.md'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      return {
        for (final f in files)
          f.uri.pathSegments.last: Uint8List.fromList(await f.readAsBytes()),
      };
    });
    expect(fixtures, hasLength(greaterThan(20)));
    final item = await addItem(tester, fixtures!);

    for (final (i, attachment) in item.attachments.indexed) {
      await saveAs(tester, i);
      final saved = saver.saves.last;
      expect(saved.fileName, attachment.filename);
      expect(
        saved.bytes,
        fixtures[attachment.filename],
        reason: saved.fileName,
      );
      expect(hex(VaultCrypto.sha256(saved.bytes)), attachment.sha256);
    }
    expect(saver.saves, hasLength(fixtures.length));
    await dismissToasts(tester);
  });

  test('FileExport.matches checks both size and sha256', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    Attachment of({int? size, String? sha}) => Attachment(
      blobId: '00000000-0000-4000-8000-000000000002',
      filename: 'x',
      mime: 'application/octet-stream',
      size: size ?? 3,
      sha256: sha ?? hex(VaultCrypto.sha256(bytes)),
    );
    expect(FileExport.matches(bytes, of()), isTrue);
    expect(FileExport.matches(bytes, of(size: 4)), isFalse);
    expect(
      FileExport.matches(bytes, of(sha: hex(VaultCrypto.sha256([1, 2])))),
      isFalse,
    );
  });
}
