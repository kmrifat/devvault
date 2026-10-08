import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/shared/ui.dart'
    show BCButton, BCSpinner, PasswordField;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> openCreate(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(testSupportDir);
    await tester.pumpWidget(testApp(location: Routes.create, supportDir: dir!));
    await tester.pumpAndSettle();
  }

  /// The master password field is the first text field, the confirmation
  /// the second.
  Finder field(String label) =>
      find.byType(EditableText).at(label == 'Master password' ? 0 : 1);

  testWidgets('explains what is wrong before creating anything', (
    tester,
  ) async {
    await openCreate(tester);
    await tester.enterText(field('Master password'), 'too short');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 12 characters'), findsOneWidget);

    await tester.enterText(field('Master password'), 'a long master password');
    await tester.enterText(field('Confirm password'), 'a long master passwrod');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text("The passwords don't match"), findsOneWidget);
    expect(appContainer(tester).read(vaultSessionProvider), isA<NoVault>());
  });

  testWidgets('shows a strength estimate as you type', (tester) async {
    await openCreate(tester);
    await tester.enterText(
      field('Master password'),
      'correct horse battery staple',
    );
    await tester.pump();
    expect(find.text('Strong'), findsOneWidget);
    expect(find.text('28 characters · an estimate'), findsOneWidget);
  });

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
}
