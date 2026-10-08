import 'package:devvault/app/layout.dart';
import 'package:devvault/core/password_policy.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/shared/desktop_ui.dart'
    show DesktopButton, DesktopTextField;
import 'package:devvault/shared/ui.dart'
    show BCButton, BCSpinner, PasswordField;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> openCreate(
    WidgetTester tester, {
    AppLayout layout = AppLayout.mobile,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(testSupportDir);
    await tester.pumpWidget(
      testApp(location: Routes.create, supportDir: dir!, layout: layout),
    );
    await tester.pumpAndSettle();
  }

  /// The master password field is the first text field, the confirmation
  /// the second.
  Finder field(String label) =>
      find.byType(EditableText).at(label == 'Master password' ? 0 : 1);

  for (final layout in AppLayout.values) {
    group(layout.name, () {
      testWidgets('explains what is wrong before creating anything', (
        tester,
      ) async {
        await openCreate(tester, layout: layout);
        await tester.enterText(field('Master password'), 'abc');
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Use at least 4 characters'), findsOneWidget);

        await tester.enterText(
          field('Master password'),
          'a long master password',
        );
        await tester.enterText(
          field('Confirm password'),
          'a long master passwrod',
        );
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text("The passwords don't match"), findsOneWidget);
        expect(appContainer(tester).read(vaultSessionProvider), isA<NoVault>());
      });

      testWidgets('shows a strength estimate as you type', (tester) async {
        await openCreate(tester, layout: layout);
        await tester.enterText(
          field('Master password'),
          'correct horse battery staple',
        );
        await tester.pump();
        expect(find.text('Strong'), findsOneWidget);
        expect(find.text('28 characters · an estimate'), findsOneWidget);
      });

      testWidgets('a short password is allowed, with a warning', (
        tester,
      ) async {
        await openCreate(tester, layout: layout);
        await tester.enterText(field('Master password'), 'abcd');
        await tester.pump();
        expect(find.text('Weak'), findsOneWidget);
        expect(find.text(PasswordPolicy.shortWarning), findsOneWidget);
        // A warning, not an error: the policy allows it.
        expect(PasswordPolicy.problem('abcd'), isNull);
        expect(find.text('Use at least 4 characters'), findsNothing);
      });
    });
  }

  testWidgets('creates the vault and moves on to the recovery kit', (
    tester,
  ) async {
    await openCreate(tester);
    await tester.enterText(field('Master password'), 'a long master password');
    await tester.enterText(field('Confirm password'), 'a long master password');
    final controllers = [
      for (final f in tester.widgetList<PasswordField>(
        find.byType(PasswordField),
      ))
        f.controller,
    ];
    expect(controllers.map((c) => c.text), everyElement(isNotEmpty));

    // While Argon2id runs: progress, and nothing can be changed or sent
    // twice.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Creating vault…'), findsOneWidget);
    expect(find.byType(BCSpinner), findsOneWidget);
    expect(
      tester
          .widgetList<PasswordField>(find.byType(PasswordField))
          .map((f) => f.isDisabled),
      [true, true],
    );
    expect(
      tester
          .widget<BCButton>(
            find.ancestor(
              of: find.text('Creating vault…'),
              matching: find.byType(BCButton),
            ),
          )
          .isDisabled,
      isTrue,
    );

    // Argon2id runs on a real isolate: give it real time, and frames for
    // what follows it.
    for (
      var i = 0;
      i < 250 && appContainer(tester).read(pendingRecoveryKeyProvider) == null;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final c = appContainer(tester);
    expect(c.read(vaultSessionProvider), isA<Unlocked>());
    expect(c.read(pendingRecoveryKeyProvider), isNotNull);
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path,
      Routes.createRecoveryKit,
    );
    // The password isn't kept: the screen cleared its fields on the way out.
    expect(find.byType(PasswordField), findsNothing);
    expect(controllers.map((c) => c.text), everyElement(isEmpty));
  });

  testWidgets('desktop: creates the vault and moves on to the recovery kit', (
    tester,
  ) async {
    await openCreate(tester, layout: AppLayout.desktop);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.enterText(field('Master password'), 'a long master password');
    await tester.enterText(field('Confirm password'), 'a long master password');
    final controllers = [
      for (final f in tester.widgetList<DesktopTextField>(
        find.byType(DesktopTextField),
      ))
        f.controller!,
    ];
    expect(controllers, hasLength(2));
    expect(controllers.map((c) => c.text), everyElement(isNotEmpty));

    // While Argon2id runs: progress, and nothing can be changed or sent
    // twice.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Creating vault…'), findsOneWidget);
    expect(
      tester
          .widgetList<DesktopTextField>(find.byType(DesktopTextField))
          .map((f) => f.enabled),
      [false, false],
    );
    expect(
      tester
          .widget<DesktopButton>(
            find.widgetWithText(DesktopButton, 'Creating vault…'),
          )
          .onPressed,
      isNull,
    );

    for (
      var i = 0;
      i < 250 && appContainer(tester).read(pendingRecoveryKeyProvider) == null;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final c = appContainer(tester);
    expect(c.read(vaultSessionProvider), isA<Unlocked>());
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path,
      Routes.createRecoveryKit,
    );
    expect(find.text('Save your recovery key'), findsOneWidget);
    // The password isn't kept: the screen cleared its fields on the way out.
    expect(controllers.map((c) => c.text), everyElement(isEmpty));
  });

  testWidgets('desktop: links to joining a vault', (tester) async {
    await openCreate(tester, layout: AppLayout.desktop);
    await tester.tap(find.text('Join a vault from your bucket…'));
    await tester.pumpAndSettle();
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path,
      Routes.joinVault,
    );
  });
}
