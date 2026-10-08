import 'dart:io';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/app_settings.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/settings/change_password_dialog.dart';
import 'package:devvault/services/folder_revealer.dart';
import 'package:devvault/shared/desktop_ui.dart' show DesktopFormRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';
import 'toasts.dart';

class FakeRevealer implements FolderRevealer {
  final revealed = <String>[];

  @override
  bool get isSupported => true;

  @override
  Future<void> reveal(Directory folder) async => revealed.add(folder.path);
}

void main() {
  setUpAll(loadTestCrypto);

  group('AppSettings', () {
    test('round-trips through JSON', () {
      const settings = AppSettings(
        themeMode: ThemeMode.dark,
        autoLockAfter: null,
        clipboardClearAfter: Duration(seconds: 90),
      );
      expect(AppSettings.fromJson(settings.toJson()), settings);
    });

    test('keeps defaults for anything it doesn’t recognise', () {
      expect(AppSettings.fromJson('nonsense'), const AppSettings());
      expect(
        AppSettings.fromJson({
          'theme': 'purple',
          'auto_lock_seconds': 7,
          'clipboard_clear_seconds': 'soon',
        }),
        const AppSettings(),
      );
      // A missing key is the default; an explicit null is "never".
      expect(
        AppSettings.fromJson({}).autoLockAfter,
        AppSettings.defaultAutoLock,
      );
      expect(
        AppSettings.fromJson({'auto_lock_seconds': null}).autoLockAfter,
        isNull,
      );
    });

    test('saves and loads from the support folder', () async {
      final dir = Directory.systemTemp.createTempSync('devvault_settings_');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(AppSettings.load(dir), const AppSettings());
      const settings = AppSettings(themeMode: ThemeMode.light);
      await settings.save(dir);
      expect(AppSettings.load(dir), settings);
      AppSettings.fileIn(dir).writeAsStringSync('{broken');
      expect(AppSettings.load(dir), const AppSettings());
    });
  });

  group('screen', () {
    late FakeRevealer revealer;

    Future<void> open(
      WidgetTester tester, {
      String location = Routes.settingsSecurity,
    }) async {
      tester.view
        ..physicalSize = const Size(1440, 1100)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      revealer = FakeRevealer();
      await pumpUnlockedApp(
        tester,
        location: location,
        layout: AppLayout.desktop,
        overrides: [folderRevealerProvider.overrideWithValue(revealer)],
      );
    }

    AppSettings settings(WidgetTester tester) =>
        appContainer(tester).read(settingsProvider);

    Future<void> choose(
      WidgetTester tester,
      String current,
      String next,
    ) async {
      await tester.tap(find.text(current));
      await tester.pumpAndSettle();
      await tester.tap(find.text(next).last);
      await tester.pumpAndSettle();
    }

    testWidgets('appearance, auto-lock and clipboard choices apply', (
      tester,
    ) async {
      await open(tester, location: Routes.settings);

      // General: a segmented control.
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(settings(tester).themeMode, ThemeMode.dark);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      // Security is a tab, and a link.
      await tester.tap(find.text('Security'));
      await tester.pumpAndSettle();
      expect(
        GoRouter.of(tester.element(find.text('Lock after'))).state.uri
            .toString(),
        Routes.settingsSecurity,
      );
      // The tab swapped the pane in place: no screen pushed on top.
      expect(
        Navigator.of(tester.element(find.text('Lock after'))).canPop(),
        isFalse,
      );

      await choose(tester, '5 minutes', 'Never');
      expect(appContainer(tester).read(autoLockProvider), isNull);

      await choose(tester, '30 seconds', '10 seconds');
      expect(
        appContainer(tester).read(clipboardGuardProvider).clearAfter,
        const Duration(seconds: 10),
      );

      // Saved for next launch.
      final supportDir = appContainer(tester).read(appSupportDirProvider);
      for (
        var i = 0;
        i < 100 && AppSettings.load(supportDir) != settings(tester);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(AppSettings.load(supportDir), settings(tester));
    });

    testWidgets('shows the vault id and folder', (tester) async {
      await open(tester);
      final vault =
          (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;
      expect(find.text(vault.vaultId), findsOneWidget);
      expect(find.textContaining('Argon2id 8 MiB, 1 pass'), findsOneWidget);
      await tester.ensureVisible(find.text('Show in Finder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show in Finder'));
      await tester.pumpAndSettle();
      expect(revealer.revealed, [vault.store.root.path]);
    });

    group('change password', () {
      Finder field(String label) => find.descendant(
        of: find.ancestor(
          of: find.text('$label:'),
          matching: find.byType(DesktopFormRow),
        ),
        matching: find.byType(EditableText),
      );

      Future<void> fill(
        WidgetTester tester,
        String current,
        String next, [
        String? confirm,
      ]) async {
        await tester.enterText(field('Current password'), current);
        await tester.enterText(field('New password'), next);
        await tester.enterText(field('Confirm new password'), confirm ?? next);
        await tester.pump();
      }

      /// Submits and gives Argon2id real time until the dialog settles.
      Future<void> submit(WidgetTester tester) async {
        await tester.runAsync(() async {
          await tester.tap(find.text('Change Password'));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        // Rebuild first, so the busy label (if any) is on screen.
        await tester.pump();
        for (
          var i = 0;
          i < 300 && find.text('Changing…').evaluate().isNotEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      Future<void> openDialog(WidgetTester tester) async {
        await open(tester);
        await tester.tap(find.text('Change…'));
        await tester.pumpAndSettle();
        expect(find.byType(ChangePasswordForm), findsOneWidget);
      }

      testWidgets('checks the form before trying', (tester) async {
        await openDialog(tester);
        await fill(tester, '', 'abc');
        await submit(tester);
        expect(find.text('Enter your current password'), findsOneWidget);
        expect(find.text('Use at least 4 characters'), findsOneWidget);

        await fill(tester, testPassword, 'a brand new passphrase', 'typo');
        await submit(tester);
        expect(find.text("The passwords don't match"), findsOneWidget);

        await fill(tester, testPassword, testPassword);
        await submit(tester);
        expect(
          find.text('Choose a password you aren’t using now'),
          findsOneWidget,
        );
      });

      testWidgets('a wrong current password changes nothing', (tester) async {
        await openDialog(tester);
        final vault =
            (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;
        final before = await tester.runAsync(
          () => File('${vault.store.root.path}/vault.json').readAsString(),
        );
        await fill(tester, 'not my password at all', 'a brand new passphrase');
        await submit(tester);
        expect(find.text("That isn't your current password"), findsOneWidget);
        final after = await tester.runAsync(
          () => File('${vault.store.root.path}/vault.json').readAsString(),
        );
        expect(after, before);
      });

      testWidgets('rewrites only vault.json, and the new password unlocks', (
        tester,
      ) async {
        await openDialog(tester);
        final vault =
            (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;
        Future<Map<String, String>> snapshot() async => {
          for (final f
              in vault.store.root.listSync(recursive: true).whereType<File>())
            f.path: String.fromCharCodes(await f.readAsBytes()),
        };
        final before = (await tester.runAsync(snapshot))!;

        await fill(tester, testPassword, 'a brand new passphrase');
        await submit(tester);
        expect(find.byType(ChangePasswordForm), findsNothing);
        expect(find.text('Master password changed'), findsOneWidget);
        expectNoSecretInToasts(tester, [
          testPassword,
          'a brand new passphrase',
        ]);

        final after = (await tester.runAsync(snapshot))!;
        final changed = [
          for (final path in {...before.keys, ...after.keys})
            if (before[path] != after[path]) path.split('/').last,
        ];
        expect(changed, ['vault.json']);

        final notifier = appContainer(
          tester,
        ).read(vaultSessionProvider.notifier)..lock();
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => expectLater(
            notifier.unlock(testPassword),
            throwsA(isA<WrongPassword>()),
          ),
        );
        await tester.runAsync(() => notifier.unlock('a brand new passphrase'));
        expect(
          appContainer(tester).read(vaultSessionProvider),
          isA<Unlocked>(),
        );
        await tester.pumpAndSettle(const Duration(seconds: 10));
      });
    });
  });
}
