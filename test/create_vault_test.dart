import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
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
    await tester.runAsync(() async {
      await tester.tap(find.text('Continue'));
      // Argon2id runs on a real isolate; give it real time.
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (appContainer(tester).read(pendingRecoveryKeyProvider) != null) {
          break;
        }
      }
    });
    await tester.pumpAndSettle();

    final c = appContainer(tester);
    expect(c.read(vaultSessionProvider), isA<Unlocked>());
    expect(c.read(pendingRecoveryKeyProvider), isNotNull);
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path,
      Routes.createRecoveryKit,
    );
  });
}
