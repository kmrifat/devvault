import 'dart:io';

import 'package:bc_ui/bc_ui.dart';
import 'package:cred_parsers/cred_parsers.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/expiry.dart';
import 'package:devvault/core/notification_plan.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/import/import_dialog.dart';
import 'package:devvault/features/import/import_draft.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/services/file_import.dart';
import 'package:devvault/shared/widgets/password_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

const _fixtures = 'packages/cred_parsers/test/fixtures';

PickedFile fixture(String name) =>
    PickedFile(name: name, bytes: File('$_fixtures/$name').readAsBytesSync());

ParseResult parse(PickedFile f, [Map<String, String> secrets = const {}]) =>
    CredentialParsers.standard().parse(
      ParseInput(filename: f.name, bytes: f.bytes, secrets: secrets),
    );

class _Opener implements FileOpener {
  final queue = <PickedFile>[];

  @override
  Future<List<PickedFile>> pick() async =>
      queue.isEmpty ? const [] : [queue.removeAt(0)];
}

void main() {
  setUpAll(loadTestCrypto);

  Item existing(
    ItemType type, {
    Map<String, ItemField> fields = const {},
    DateTime? expiresAt,
    ExpirySource? source,
  }) => Item(
    id: '00000000-0000-4000-8000-0000000000e1',
    typeName: type.wireName,
    title: 'Release signing',
    appId: 'app-1',
    platform: 'ios',
    environment: 'production',
    tags: const ['release'],
    fields: fields,
    attachments: [
      Attachment(
        blobId: '00000000-0000-4000-8000-0000000000b1',
        filename: 'old.cer',
        mime: 'application/octet-stream',
        size: 1,
        sha256: 'a' * 64,
      ),
    ],
    expiresAt: expiresAt,
    expiresSource: source,
    notes: 'Kept in 1Password too',
    createdAt: testNow,
    updatedAt: testNow,
    rev: Hlc.zero(testDeviceId),
    deviceId: testDeviceId,
  );
  final newFile = Attachment(
    blobId: '00000000-0000-4000-8000-0000000000b2',
    filename: 'apple_development.cer',
    mime: 'application/octet-stream',
    size: 2,
    sha256: 'b' * 64,
  );

  group('ImportDraft.replace', () {
    test('keeps the item, swaps the file, its facts and its expiry', () {
      final file = fixture('apple_development.cer');
      final target = existing(
        ItemType.appleCertificate,
        fields: {
          'sha1': const ItemField(value: 'OLD', source: FieldSource.file),
          'gone': const ItemField(value: 'x', source: FieldSource.file),
          'portal_note': const ItemField(
            value: 'renewed by Sam',
            source: FieldSource.user,
          ),
        },
        expiresAt: DateTime.utc(2026, 10, 12),
        source: ExpirySource.file,
      );
      final draft = ImportDraft(file, parse(file), replacing: target);
      expect(draft.fitsReplaced, isTrue);
      expect(draft.title, 'Release signing');
      final replaced = draft.replace(target, newFile);
      expect(replaced.id, target.id);
      expect(replaced.title, target.title);
      expect(replaced.tags, ['release']);
      expect(replaced.appId, 'app-1');
      expect(replaced.platform, 'ios');
      expect(replaced.environment, 'production');
      expect(replaced.notes, 'Kept in 1Password too');
      expect(replaced.attachments, [newFile]);
      expect(replaced.fields['portal_note']!.value, 'renewed by Sam');
      expect(replaced.fields['gone'], isNull);
      expect(replaced.fields['sha1']!.value, isNot('OLD'));
      expect(replaced.expiresAt, DateTime.utc(2027, 10, 7, 13, 29, 20));
      expect(replaced.expiresSource, ExpirySource.file);
      expect(
        ExpiryState.of(replaced, testNow),
        ExpiryState.valid,
        reason: 'the warning clears',
      );
    });

    test('a date the user set survives a file that states none', () {
      final file = fixture('google-services.json');
      final target = existing(
        ItemType.firebaseConfig,
        expiresAt: DateTime.utc(2027),
        source: ExpirySource.user,
      );
      final r = ImportDraft(
        file,
        parse(file),
        replacing: target,
      ).replace(target, newFile);
      expect(r.expiresAt, DateTime.utc(2027));
      expect(r.expiresSource, ExpirySource.user);

      // A date the old file stated goes with the old file.
      final fromFile = existing(
        ItemType.firebaseConfig,
        expiresAt: DateTime.utc(2027),
        source: ExpirySource.file,
      );
      final r2 = ImportDraft(
        file,
        parse(file),
        replacing: fromFile,
      ).replace(fromFile, newFile);
      expect(r2.expiresAt, isNull);
      expect(r2.expiresSource, isNull);
    });

    test('only a file of the same kind fits', () {
      final p8 = fixture('AuthKey_TESTKEY123.p8');
      final cert = existing(ItemType.appleCertificate);
      expect(ImportDraft(p8, parse(p8), replacing: cert).fitsReplaced, isFalse);
      expect(
        ImportDraft(
          p8,
          parse(p8),
          replacing: existing(ItemType.appleAuthKey),
        ).fitsReplaced,
        isTrue,
      );
    });

    test('fields the user already gave the item aren’t asked again', () {
      final p8 = fixture('AuthKey_TESTKEY123.p8');
      final withTeam = existing(
        ItemType.appleAuthKey,
        fields: {
          'team_id': const ItemField(
            value: 'TESTTEAM01',
            source: FieldSource.user,
          ),
        },
      );
      final draft = ImportDraft(p8, parse(p8), replacing: withTeam);
      expect(draft.requiredFields, isEmpty);
      expect(draft.validate(), isEmpty);
      expect(
        draft.replace(withTeam, newFile).fields['team_id']!.value,
        'TESTTEAM01',
      );

      final without = existing(ItemType.appleAuthKey);
      final asks = ImportDraft(p8, parse(p8), replacing: without);
      expect([for (final f in asks.requiredFields) f.key], ['team_id']);
      expect(asks.validate().keys, ['team_id']);
      // An unanswered required field is simply absent, never a crash.
      expect(asks.fields.containsKey('team_id'), isFalse);
    });
  });

  group('Replace file… in the app', () {
    late _Opener opener;

    Future<void> open(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1440, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      opener = _Opener();
      await pumpUnlockedApp(
        tester,
        location: Routes.vault(),
        vault: TestVault.sample,
        layout: AppLayout.desktop,
        overrides: [fileOpenerProvider.overrideWithValue(opener)],
      );
    }

    VaultIndex index(WidgetTester tester) =>
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

    Future<void> settle(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 1000 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(done(), isTrue, reason: 'never finished');
      await tester.pumpAndSettle();
    }

    Future<Item> keystore(WidgetTester tester) async =>
        index(tester).all.firstWhere((i) => i.title == 'Upload keystore');

    Future<void> replaceWith(WidgetTester tester, PickedFile file) async {
      final item = await keystore(tester);
      GoRouter.of(tester.element(find.byType(VaultListPane)))
          .go(Routes.vault(item: item.id));
      await tester.pumpAndSettle();
      opener.queue.add(file);
      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace file…'));
      await tester.pump();
      await settle(
        tester,
        () =>
            find.byType(ImportDialog).evaluate().isNotEmpty &&
            find.byType(BCSpinner).evaluate().isEmpty,
      );
    }

    testWidgets('keeps the item, takes the new file and expiry, warns again', (
      tester,
    ) async {
      await open(tester);
      // Make the keystore expire in 5 days, with its window reminder sent.
      final before = await keystore(tester);
      await tester.runAsync(
        () => appContainer(tester)
            .read(vaultSessionProvider.notifier)
            .saveItem(
              before.copyWith(
                expiresAt: testNow.add(const Duration(days: 5)),
                expiresSource: ExpirySource.file,
              ),
            ),
      );
      final ledgerFile = appContainer(tester).read(alertLedgerFileProvider);
      ledgerFile.save(
        AlertLedger(
          delivered: {
            before.id: {ExpiryAlertKind.window},
          },
        ),
      );
      expect(ExpiryState.of(await keystore(tester), testNow), ExpiryState.soon);

      await replaceWith(tester, fixture('test.jks'));
      expect(find.text('Replace file'), findsWidgets);
      expect(
        find.textContaining('Replaces the file of “Upload keystore”'),
        findsOneWidget,
      );
      // The JKS needs its store password first.
      await tester.enterText(
        find.descendant(
          of: find.byType(PasswordField),
          matching: find.byType(EditableText),
        ),
        'test-password',
      );
      await tester.pump();
      await tester.tap(find.text('Unlock file'));
      await settle(tester, () => find.text('Details').evaluate().isNotEmpty);
      expect(find.text('Name'), findsNothing); // the item keeps its own

      await tester.tap(
        find.descendant(
          of: find.byType(ImportDialog),
          matching: find.widgetWithText(BCButton, 'Replace file'),
        ),
      );
      await settle(
        tester,
        () =>
            index(tester).items[before.id]!.attachments.single.filename ==
            'test.jks',
      );

      final after = index(tester).items[before.id]!;
      expect(after.id, before.id);
      expect(after.title, 'Upload keystore');
      expect(after.tags, before.tags);
      expect(after.appId, before.appId);
      expect(after.platform, before.platform);
      expect(after.environment, before.environment);
      expect(after.expiresSource, ExpirySource.file);
      expect(after.expiresAt!.year, greaterThan(2030));
      expect(ExpiryState.of(after, testNow), ExpiryState.valid);
      expect(after.fields['store_password']!.source, FieldSource.user);
      expect(index(tester).all, hasLength(12));
      // The reminders start over.
      expect(
        ledgerFile.load().wasDelivered(before.id, ExpiryAlertKind.window),
        isFalse,
      );
      expect(find.text('File replaced'), findsOneWidget);
    });

    testWidgets('a file of another kind can’t replace it', (tester) async {
      await open(tester);
      await replaceWith(tester, fixture('AuthKey_TESTKEY123.p8'));
      expect(
        find.textContaining('Choose a file of the same kind'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ImportDialog),
          matching: find.widgetWithText(BCButton, 'Replace file'),
        ),
        findsNothing,
      );
    });

    testWidgets('the same file again says so', (tester) async {
      await open(tester);
      final item = await keystore(tester);
      final bytes = await tester.runAsync(() async {
        final session =
            appContainer(tester).read(vaultSessionProvider) as Unlocked;
        return session.vault.readAttachment(item.attachments.single);
      });
      await replaceWith(
        tester,
        PickedFile(name: 'kitchenly-upload.jks', bytes: bytes!),
      );
      expect(find.textContaining('already has'), findsOneWidget);
    });
  });
}
