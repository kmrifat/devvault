import 'dart:io';

import 'package:bc_ui/bc_ui.dart';
import 'package:cred_parsers/cred_parsers.dart';
import 'package:devvault/app/desktop_shell.dart' show ShellToolbar;
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:devvault/features/import/import_dialog.dart';
import 'package:devvault/features/import/import_draft.dart';
import 'package:devvault/features/import/place_fields.dart'
    show placeSuggestions, typedPlace;
import 'package:devvault/features/vault/desktop_item_type.dart'
    show DesktopTypeTile;
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/services/file_import.dart';
import 'package:devvault/shared/desktop_ui.dart'
    show
        DesktopButton,
        DesktopCheckbox,
        DesktopPopup,
        DesktopProgress,
        DesktopScrollView,
        DesktopTokenField;
import 'package:devvault/shared/widgets/type_icon_tile.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';
import 'toasts.dart';

const _fixtures = 'packages/cred_parsers/test/fixtures';

PickedFile fixture(String name, {String? as}) => PickedFile(
  name: as ?? name,
  bytes: File('$_fixtures/$name').readAsBytesSync(),
);

/// Hands the dialog whatever files the test queues up.
class FakeFileOpener implements FileOpener {
  final queue = <List<PickedFile>>[];

  @override
  Future<List<PickedFile>> pick() async =>
      queue.isEmpty ? const [] : queue.removeAt(0);
}

ParseResult parse(PickedFile file, [Map<String, String> secrets = const {}]) =>
    CredentialParsers.standard().parse(
      ParseInput(filename: file.name, bytes: file.bytes, secrets: secrets),
    );

void main() {
  setUpAll(loadTestCrypto);

  group('ImportDraft', () {
    var counter = 0;
    Item fresh(ItemType type, String title) => Item(
      id: '00000000-0000-4000-8000-${(++counter).toString().padLeft(12, '0')}',
      typeName: type.wireName,
      title: title,
      createdAt: testNow,
      updatedAt: testNow,
      rev: Hlc.zero(testDeviceId),
      deviceId: testDeviceId,
    );
    final attachment = Attachment(
      blobId: '00000000-0000-4000-8000-0000000000aa',
      filename: 'f',
      mime: 'application/octet-stream',
      size: 1,
      sha256: 'a' * 64,
    );

    test('a renamed .p8 needs its Key ID and Team ID typed in', () {
      final file = fixture('AuthKey_TESTKEY123.p8', as: 'my key.p8');
      final draft = ImportDraft(file, parse(file));
      expect(draft.type, ItemType.appleAuthKey);
      expect(draft.title, 'my key');
      expect(
        [for (final f in draft.requiredFields) f.key],
        ['key_id', 'team_id'],
      );
      expect(draft.validate().keys, containsAll(['key_id', 'team_id']));

      draft.userFields['key_id'] = 'abc';
      draft.userFields['team_id'] = 'TESTTEAM01';
      expect(draft.validate(), {
        'key_id': 'A Key ID is 10 capital letters and digits',
      });
    });

    test('Apple’s filename gives the Key ID, so only the Team ID is asked', () {
      final file = fixture('AuthKey_TESTKEY123.p8');
      final draft = ImportDraft(file, parse(file));
      expect([for (final f in draft.requiredFields) f.key], ['team_id']);
    });

    test('file facts stay the file’s, typed values are the user’s', () {
      final file = fixture('AuthKey_TESTKEY123.p8');
      final draft = ImportDraft(file, parse(file))
        ..userFields['team_id'] = ' TESTTEAM01 '
        ..purpose = KeyPurpose.apns;
      final item = draft.toItem(fresh, attachment);
      expect(item.fields['key_id']!.source, FieldSource.file);
      expect(item.fields['key_algorithm']!.source, FieldSource.file);
      expect(
        item.fields['team_id'],
        const ItemField(value: 'TESTTEAM01', source: FieldSource.user),
      );
      expect(item.fields['purpose']!.value, 'APNs');
      expect(item.fields['purpose']!.source, FieldSource.user);
      expect(item.attachments, [attachment]);
      expect(item.expiresAt, isNull);
      expect(item.expiresSource, isNull);
    });

    test('a password the user typed is kept as their secret, if they want', () {
      final file = fixture('cert.p12');
      final draft = ImportDraft(
        file,
        parse(file, {'password': 'test-password'}),
      )..secrets['password'] = 'test-password';
      final item = draft.toItem(fresh, attachment);
      expect(
        item.fields['password'],
        const ItemField(
          value: 'test-password',
          source: FieldSource.user,
          secret: true,
        ),
      );
      expect(item.expiresSource, ExpirySource.file);
      expect(item.expiresAt, draft.result.expiresAt);

      draft.keepSecrets = false;
      expect(draft.toItem(fresh, attachment).fields['password'], isNull);
    });

    test('an unreadable file is a generic file with nothing invented', () {
      final file = PickedFile(
        name: 'notes.p12',
        bytes: Uint8List.fromList('not a p12'.codeUnits),
      );
      final draft = ImportDraft(file, parse(file));
      expect(draft.type, ItemType.genericFile);
      expect(draft.requiredFields, isEmpty);
      final item = draft.toItem(fresh, attachment);
      expect(item.fields, isEmpty);
      expect(item.expiresAt, isNull);
    });

    test('Replace swaps the file and its facts, keeping the user’s', () {
      final file = fixture('apple_development.cer');
      final draft = ImportDraft(file, parse(file));
      final existing = fresh(ItemType.appleCertificate, 'Old cert').copyWith(
        appId: 'app-1',
        tags: ['ios'],
        fields: {
          'sha1': const ItemField(value: 'OLD', source: FieldSource.file),
          'old_fact': const ItemField(value: 'gone', source: FieldSource.file),
          'note': const ItemField(value: 'mine', source: FieldSource.user),
        },
        expiresAt: DateTime.utc(2020),
        expiresSource: ExpirySource.file,
      );
      final replaced = draft.replace(existing, attachment);
      expect(replaced.id, existing.id);
      expect(replaced.title, 'Old cert');
      expect(replaced.appId, 'app-1');
      expect(replaced.tags, ['ios']);
      expect(replaced.fields['note']!.value, 'mine');
      expect(replaced.fields['old_fact'], isNull);
      expect(replaced.fields['sha1']!.value, isNot('OLD'));
      expect(replaced.expiresAt, draft.result.expiresAt);
      expect(replaced.attachments, [attachment]);
    });

    test('combo boxes suggest SPEC values, then the vault’s own', () {
      expect(
        placeSuggestions(
          ['production', 'staging'],
          ['qa', null, 'production', ' ', 'beta', 'qa'],
        ),
        ['production', 'staging', 'beta', 'qa'],
      );
      // Stored as typed, or nothing; never a default.
      expect(typedPlace('  watchos '), 'watchos');
      expect(typedPlace('   '), isNull);
    });

    test('tags go on a new item; a replaced one keeps its own', () {
      final file = fixture('google-services.json');
      final draft = ImportDraft(file, parse(file))..tags = ['firebase'];
      expect(draft.toItem(fresh, attachment).tags, ['firebase']);
      final existing = fresh(
        ItemType.firebaseConfig,
        'Old',
      ).copyWith(tags: ['mine']);
      expect(draft.replace(existing, attachment).tags, ['mine']);
    });

    test('duplicates are found by sha256', () {
      final a = fresh(
        ItemType.genericFile,
        'a',
      ).copyWith(attachments: [attachment]);
      final b = fresh(ItemType.genericFile, 'b');
      expect(ImportDraft.duplicatesOf('a' * 64, [a, b]), [a]);
      expect(ImportDraft.duplicatesOf('b' * 64, [a, b]), isEmpty);
    });
  });

  // Real KDFs (PKCS#12, JCEKS) and file I/O for every fixture: the
  // timeout leaves room for a loaded machine.
  test('every fixture imports, and its bytes come back unchanged', () async {
    final dir = await testSupportDir(TestVault.locked);
    final store = findVault(Directory('${dir.path}/vaults'))!;
    final vault = await Vault.unlock(
      crypto: testCrypto,
      store: store,
      password: testPassword,
      deviceId: testDeviceId,
      now: () => testNow,
    );
    final parsers = CredentialParsers.standard();
    final names = Directory(_fixtures)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n != 'README.md')
        .toList();
    expect(names.length, greaterThan(20));

    for (final name in names) {
      final file = fixture(name);
      var result = parsers.parse(ParseInput(filename: name, bytes: file.bytes));
      final draft = ImportDraft(file, result);
      // Answer every prompt the way a user with the right passwords would.
      for (var round = 0; round < 3 && !draft.isReady; round++) {
        for (final request in result.secretsNeeded) {
          draft.secrets[request.key] = 'test-password';
        }
        if (result.needsChoice) draft.choice = result.options.first.id;
        result = draft.result = parsers.parse(
          ParseInput(
            filename: name,
            bytes: file.bytes,
            secrets: draft.secrets,
            choice: draft.choice,
          ),
        );
      }
      for (final field in draft.requiredFields) {
        draft.userFields[field.key] = 'TESTTEAM01';
      }
      expect(draft.validate(), isEmpty, reason: name);
      for (final MapEntry(:key, :value) in result.facts.entries) {
        expect(value.source, FieldSource.file, reason: '$name $key');
      }

      final attachment = await vault.addAttachment(file.bytes, filename: name);
      final saved = await vault.putItem(
        draft.toItem(
          (type, title) => vault.newItem(type: type, title: title),
          attachment,
        ),
      );
      expect(
        await vault.readAttachment(saved.attachments.single),
        file.bytes,
        reason: name,
      );
      if (result.isGeneric) {
        expect(saved.typeName, ItemType.genericFile.wireName, reason: name);
      }
    }
    final contents = await vault.loadAll();
    expect(contents.items, hasLength(names.length));
    expect(contents.quarantined, isEmpty);
    vault.lock();
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('dialog', () {
    late FakeFileOpener opener;

    Future<void> open(
      WidgetTester tester, {
      Size window = const Size(1440, 1400),
    }) async {
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      opener = FakeFileOpener();
      await pumpUnlockedApp(
        tester,
        location: Routes.vault(),
        layout: AppLayout.desktop,
        overrides: [fileOpenerProvider.overrideWithValue(opener)],
      );
    }

    VaultIndex index(WidgetTester tester) =>
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

    GoRouter router(WidgetTester tester) =>
        GoRouter.of(tester.element(find.byType(VaultListPane)));

    Finder input(Finder within) =>
        find.descendant(of: within, matching: find.byType(EditableText));

    Finder field(String key) => find.byKey(ValueKey('import-field-$key'));

    Finder secret(String key) => find.byKey(ValueKey('import-secret-$key'));

    /// The sheet's default action (N04 says "Add to Vault").
    Finder addButton() => find.descendant(
      of: find.byType(ImportDialog),
      matching: find.widgetWithText(DesktopButton, 'Add to Vault'),
    );

    /// Lets the isolate parse or the vault write behind the dialog finish,
    /// until [done].
    Future<void> settle(
      WidgetTester tester,
      bool Function() done, {
      bool andSettle = true,
    }) async {
      for (var i = 0; i < 1000 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(done(), isTrue, reason: 'never finished');
      if (andSettle) await tester.pumpAndSettle();
    }

    Future<void> startImport(WidgetTester tester, PickedFile file) async {
      opener.queue.add([file]);
      await tester.tap(
        find.descendant(
          of: find.byType(ShellToolbar),
          matching: find.bySemanticsLabel(RegExp('^Import a file')),
        ),
      );
      await tester.pump();
      await settle(
        tester,
        () => find.byType(ImportDialog).evaluate().isNotEmpty,
        andSettle: false,
      );
      await settle(
        tester,
        () => find.byType(DesktopProgress).evaluate().isEmpty,
        andSettle: false,
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapImport(WidgetTester tester, bool Function() done) async {
      await tester.ensureVisible(addButton());
      await tester.pumpAndSettle();
      await tester.tap(addButton());
      await tester.pump();
      await settle(tester, done);
    }

    testWidgets('on a phone (B4): sheet pickers and one Add to vault button', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      opener = FakeFileOpener()..queue.add([fixture('AuthKey_TESTKEY123.p8')]);
      await pumpUnlockedApp(
        tester,
        location: Routes.vault(),
        layout: AppLayout.mobile,
        overrides: [fileOpenerProvider.overrideWithValue(opener)],
      );
      await tester.tap(find.bySemanticsLabel('Import').first);
      await tester.pumpAndSettle();
      // B4a: a file or a secret.
      await tester.tap(find.text('Pick a file'));
      await tester.pump();
      await settle(
        tester,
        () => find.byType(ImportDialog).evaluate().isNotEmpty,
        andSettle: false,
      );
      await settle(tester, () => find.byType(BCSpinner).evaluate().isEmpty);

      Finder inSheet(Finder f) =>
          find.descendant(of: find.byType(ImportDialog), matching: f);
      // One full-width action; the sheet's close button cancels.
      expect(inSheet(find.widgetWithText(BCButton, 'Add to vault')), findsOne);
      expect(
        tester
            .widget<BCButton>(
              inSheet(find.widgetWithText(BCButton, 'Add to vault')),
            )
            .fullWidth,
        isTrue,
      );
      expect(inSheet(find.text('Cancel')), findsNothing);
      expect(inSheet(find.text('Import')), findsNothing);

      // Pickers open as bottom sheets.
      expect(
        tester
            .widgetList<BCSelect<String>>(
              inSheet(find.byType(BCSelect<String>)),
            )
            .map((s) => s.presentation),
        everyElement(BCSelectPresentation.bottomSheet),
      );
      final environment = inSheet(find.byType(BCSelect<String>)).last;
      await tester.ensureVisible(environment);
      await tester.pumpAndSettle();
      await tester.tap(environment);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Production').last);
      await tester.pumpAndSettle();

      await tester.enterText(input(field('team_id')), 'TESTTEAM01');
      await tester.pump();
      final add = inSheet(find.widgetWithText(BCButton, 'Add to vault'));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pump();
      await settle(tester, () => index(tester).all.isNotEmpty);

      final item = index(tester).all.single;
      expect(item.typeName, ItemType.appleAuthKey.wireName);
      expect(item.environment, 'production');
      expect(item.fields['team_id']!.value, 'TESTTEAM01');
      expect(find.byType(ImportDialog), findsNothing);
    });

    testWidgets('a .p8: facts from the file, required fields from the user', (
      tester,
    ) async {
      await open(tester);
      await startImport(tester, fixture('AuthKey_TESTKEY123.p8'));

      expect(find.text('Import AuthKey_TESTKEY123.p8'), findsOneWidget);
      // The type tile is the desktop layer's, not bc_ui's.
      expect(
        tester
            .widget<DesktopTypeTile>(
              find.descendant(
                of: find.byType(ImportDialog),
                matching: find.byType(DesktopTypeTile),
              ),
            )
            .type,
        ItemType.appleAuthKey,
      );
      expect(find.byType(TypeIconTile), findsNothing);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('TESTKEY123'), findsOneWidget);
      expect(find.text('EC P-256'), findsOneWidget);
      expect(find.text('Team ID:'), findsOneWidget);
      expect(find.text('Required · not in the file'), findsOneWidget);
      // The filename gave the Key ID, so it isn't asked for.
      expect(find.text('Key ID:'), findsNothing);
      // Nothing is chosen for the user.
      expect(find.text('Not set'), findsOneWidget);
      expect(find.textContaining('No expiry date in the file'), findsOneWidget);

      // Importing without the Team ID says what's missing.
      await tester.tap(addButton());
      await tester.pumpAndSettle();
      expect(find.text('Team ID is required'), findsOneWidget);
      expect(index(tester).all, isEmpty);
      await tester.enterText(input(field('team_id')), 'TESTTEAM01');
      await tester.pump();
      // Pick APNs. (macos_ui draws its menu rows in the test font, which
      // is too wide for them, so pick through the pop-up's callback.)
      final usedFor = find.ancestor(
        of: find.text('Not set'),
        matching: find.byType(DesktopPopup<String>),
      );
      expect(
        tester
            .widget<DesktopPopup<String>>(usedFor)
            .choices
            .map((c) => c.label),
        ['Not set', 'App Store Connect API', 'APNs', 'Sign in with Apple'],
      );
      tester.widget<DesktopPopup<String>>(usedFor).onChanged!('apns');
      await tester.pumpAndSettle();
      await tapImport(tester, () => index(tester).all.isNotEmpty);

      final item = index(tester).all.single;
      expect(item.title, 'AuthKey_TESTKEY123');
      expect(item.typeName, ItemType.appleAuthKey.wireName);
      expect(item.fields['key_id']!.source, FieldSource.file);
      expect(item.fields['team_id']!.source, FieldSource.user);
      expect(item.fields['purpose']!.value, 'APNs');
      // Nothing the user left empty is filled in for them.
      expect(item.appId, isNull);
      expect(item.platform, isNull);
      expect(item.environment, isNull);
      expect(item.tags, isEmpty);
      expect(item.attachments.single.filename, 'AuthKey_TESTKEY123.p8');
      expect(find.byType(ImportDialog), findsNothing);
      expect(router(tester).state.uri.queryParameters['item'], item.id);
      expect(find.text('File imported'), findsOneWidget);
    });

    testWidgets('the app pop-up names an app with its organization', (
      tester,
    ) async {
      await open(tester);
      final notifier = appContainer(tester).read(vaultSessionProvider.notifier);
      final billing = await tester.runAsync(
        () => notifier.saveApp(
          notifier.newApp('Billing API').copyWith(organization: 'Acme Corp'),
        ),
      );
      await tester.runAsync(() => notifier.saveApp(notifier.newApp('Pantry')));
      await tester.pumpAndSettle();
      await startImport(tester, fixture('google-services.json'));

      final apps = find.ancestor(
        of: find.text('No app'),
        matching: find.byType(DesktopPopup<String>),
      );
      expect(
        tester.widget<DesktopPopup<String>>(apps).choices.map((c) => c.label),
        ['No app', 'Acme Corp › Billing API', 'Pantry'],
      );
      tester.widget<DesktopPopup<String>>(apps).onChanged!(billing!.id);
      await tester.pumpAndSettle();
      await tapImport(tester, () => index(tester).all.isNotEmpty);
      expect(index(tester).all.single.appId, billing.id);
    });

    testWidgets('platform and environment take any value; tags are tokens', (
      tester,
    ) async {
      await open(tester);
      await startImport(tester, fixture('google-services.json'));
      Finder inSheet(Finder f) =>
          find.descendant(of: find.byType(ImportDialog), matching: f);

      // Platform: typed, not in the suggestions, stored as typed.
      await tester.enterText(
        input(find.byKey(const ValueKey('import-platform'))),
        '  watchos ',
      );
      // Environment: picked from SPEC §6.1's suggestions.
      await tester.tap(find.bySemanticsLabel('Environment suggestions'));
      await tester.pumpAndSettle();
      expect(find.text('development'), findsOneWidget);
      await tester.tap(find.text('staging').last);
      await tester.pumpAndSettle();
      // Tags: Return makes each one a token.
      final tags = input(inSheet(find.byType(DesktopTokenField)));
      await tester.enterText(tags, 'firebase');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(tags, 'ci');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // One typed without Return is kept on import.
      await tester.enterText(tags, ' crashlytics ');

      await tapImport(tester, () => index(tester).all.isNotEmpty);
      final item = index(tester).all.single;
      expect(item.platform, 'watchos');
      expect(item.environment, 'staging');
      expect(item.tags, ['firebase', 'ci', 'crashlytics']);
      expect(item.appId, isNull);
    });

    testWidgets('a .p12 asks for its password and says when it is wrong', (
      tester,
    ) async {
      await open(tester);
      await startImport(tester, fixture('legacy.p12'));
      expect(find.text('Password:'), findsOneWidget);
      expect(find.text('Details'), findsNothing);

      await tester.enterText(input(secret('password')), 'nope');
      await tester.pump();
      await tester.tap(find.text('Unlock file'));
      await settle(
        tester,
        () => find
            .text("That password didn't open the file.")
            .evaluate()
            .isNotEmpty,
      );

      await tester.enterText(input(secret('password')), 'test-password');
      await tester.pump();
      await tester.tap(find.text('Unlock file'));
      await settle(tester, () => find.text('Details').evaluate().isNotEmpty);
      expect(find.text('Apple Development'), findsOneWidget);
      expect(find.text('Keep the password with the item'), findsOneWidget);

      await tapImport(tester, () => index(tester).all.isNotEmpty);
      await settle(
        tester,
        () => find.text('File imported').evaluate().isNotEmpty,
      );
      expectNoSecretInToasts(tester, ['test-password', 'nope']);
      final item = index(tester).all.single;
      expect(item.typeName, ItemType.appleCertificate.wireName);
      expect(item.expiresSource, ExpirySource.file);
      expect(item.fields['password']!.secret, isTrue);
      expect(item.fields['password']!.source, FieldSource.user);
    });

    // WALK-04: a .p12's long details box pushed the expiry and the
    // Keep-password checkbox under the buttons, with nothing showing that
    // the sheet scrolls.
    for (final (window, fits) in [
      // The default window: the details box scrolls on its own, so the
      // rest of the sheet fits.
      (const Size(1280, 800), true),
      // A shorter one: the content between the title and the buttons
      // scrolls.
      (const Size(1280, 600), false),
    ]) {
      final size = '${window.width.round()}×${window.height.round()}';
      testWidgets('at $size a .p12 sheet keeps its buttons and shows every '
          'row', (tester) async {
        await open(tester, window: window);
        await startImport(tester, fixture('legacy.p12'));
        await tester.enterText(input(secret('password')), 'test-password');
        await tester.pump();
        await tester.tap(find.text('Unlock file'));
        await settle(tester, () => find.text('Details').evaluate().isNotEmpty);

        Finder inSheet(Finder finder) =>
            find.descendant(of: find.byType(ImportDialog), matching: finder);
        ScrollPosition position(Finder view) => tester
            .state<ScrollableState>(
              // The view's own, not a text field's inside it.
              find
                  .descendant(of: view, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        void fullyIn(Finder finder, Rect area) {
          final rect = tester.getRect(finder);
          expect(
            rect.top >= area.top - 0.5 &&
                rect.bottom <= area.bottom + 0.5 &&
                rect.left >= area.left - 0.5 &&
                rect.right <= area.right + 0.5,
            isTrue,
            reason:
                '${finder.describeMatch(Plurality.one)} at $rect is cut '
                'by $area',
          );
          expect(finder.hitTestable(), findsOneWidget);
        }

        Future<void> wheel(Finder over, double dy) async {
          final mouse = TestPointer(1, PointerDeviceKind.mouse);
          await tester.sendEventToBinding(mouse.hover(tester.getCenter(over)));
          await tester.sendEventToBinding(mouse.scroll(Offset(0, dy)));
          await tester.pumpAndSettle();
        }

        // The sheet's content, then the details box inside it.
        final views = inSheet(find.byType(DesktopScrollView));
        expect(views, findsNWidgets(2));
        final content = views.first;
        final details = views.last;
        final area = tester.getRect(content);

        // The buttons sit below the content, whole, in the window.
        for (final label in ['Cancel', 'Add to Vault']) {
          final button = inSheet(find.widgetWithText(DesktopButton, label));
          fullyIn(button, Offset.zero & window);
          expect(tester.getRect(button).top, greaterThanOrEqualTo(area.bottom));
        }

        // The details box holds a few rows and scrolls to the rest.
        final facts = parse(fixture('legacy.p12'), {
          'password': 'test-password',
        }).facts;
        expect(position(details).maxScrollExtent, greaterThan(0));
        final last = inSheet(find.text(facts.values.last.value));
        expect(last.hitTestable(), findsNothing);
        await wheel(details, 1000);
        fullyIn(last, tester.getRect(details));

        final expiry = inSheet(find.textContaining('Expires '));
        final keep = inSheet(find.byType(DesktopCheckbox));
        if (fits) {
          expect(position(content).maxScrollExtent, 0);
        } else {
          // The rest is a scroll away: over the form, not the box.
          expect(position(content).maxScrollExtent, greaterThan(0));
          expect(expiry.hitTestable(), findsNothing);
          await wheel(inSheet(find.text('Name:')), 1000);
        }
        fullyIn(expiry, area);
        fullyIn(keep, area);
      });
    }

    testWidgets('an unknown file imports as a generic file', (tester) async {
      await open(tester);
      await startImport(
        tester,
        PickedFile(
          name: 'notes.txt',
          bytes: Uint8List.fromList('hello'.codeUnits),
        ),
      );
      expect(find.text('Details'), findsNothing);
      expect(find.textContaining('Generic File'), findsOneWidget);
      await tapImport(tester, () => index(tester).all.isNotEmpty);
      final item = index(tester).all.single;
      expect(item.typeName, ItemType.genericFile.wireName);
      expect(item.fields, isEmpty);
    });

    testWidgets('the same file twice offers open, replace or import anyway', (
      tester,
    ) async {
      await open(tester);
      final file = fixture('google-services.json');
      await startImport(tester, file);
      await tapImport(tester, () => index(tester).all.isNotEmpty);
      index(tester).all.single;

      await startImport(tester, file);
      expect(find.textContaining('already in your vault'), findsOneWidget);
      expect(find.text('Open existing'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);

      await tester.tap(find.text('Import anyway'));
      await tester.pumpAndSettle();
      await tapImport(tester, () => index(tester).all.length == 2);

      final before = {for (final i in index(tester).all) i.id: i.rev};
      bool replacedOne() =>
          index(tester).all.where((i) => i.rev > before[i.id]!).length == 1;
      await startImport(tester, file);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      // Replace opens the replace form for that item; nothing changes yet.
      expect(find.text('Replace file'), findsWidgets);
      expect(find.text('Name:'), findsNothing);
      expect(replacedOne(), isFalse);
      await tester.tap(
        find.descendant(
          of: find.byType(ImportDialog),
          matching: find.widgetWithText(DesktopButton, 'Replace file'),
        ),
      );
      await settle(tester, replacedOne);
      expect(find.byType(ImportDialog), findsNothing);
      expect(index(tester).all, hasLength(2));
      expect(index(tester).items.keys, containsAll(before.keys));

      await startImport(tester, file);
      await tester.tap(find.text('Open existing'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportDialog), findsNothing);
      expect(index(tester).all, hasLength(2));
      expect(router(tester).state.uri.queryParameters['item'], isNotNull);
    });

    testWidgets('⌘I opens the importer too', (tester) async {
      await open(tester);
      opener.queue.add([fixture('test.jks')]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await settle(
        tester,
        () => find.text('Store password:').evaluate().isNotEmpty,
      );
      expect(find.byType(ImportDialog), findsOneWidget);
    });

    testWidgets('dropping a file on the window imports it', (tester) async {
      await open(tester);
      final target = tester.widget<DropTarget>(find.byType(DropTarget));
      final at = (localPosition: Offset.zero, globalPosition: Offset.zero);

      target.onDragEntered!(
        DropEventDetails(
          localPosition: at.localPosition,
          globalPosition: at.globalPosition,
        ),
      );
      await tester.pump();
      expect(find.text('Drop to import'), findsOneWidget);

      final file = fixture('google-services.json');
      target.onDragDone!(
        DropDoneDetails(
          files: [
            DropItemFile.fromData(file.bytes, path: '/Users/me/${file.name}'),
            DropItemDirectory('/tmp/folder', const []),
          ],
          localPosition: at.localPosition,
          globalPosition: at.globalPosition,
        ),
      );
      await settle(tester, () => find.text('Project ID').evaluate().isNotEmpty);
      expect(find.text('Drop to import'), findsNothing);
      expect(find.byType(ImportDialog), findsOneWidget);
      await tapImport(tester, () => index(tester).all.isNotEmpty);
      expect(index(tester).all.single.typeName, 'firebase_config');
    });

    testWidgets('cancelling the file picker does nothing', (tester) async {
      await open(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(ShellToolbar),
          matching: find.bySemanticsLabel(RegExp('^Import a file')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ImportDialog), findsNothing);
      expect(index(tester).all, isEmpty);
    });
  });
}
