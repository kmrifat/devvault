import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';
import 'test_overrides.dart';

/// The lock screens' pieces (N00–N02) on every kit: the link, push buttons
/// with a symbol, and the compact lock window.
void main() {
  setUpAll(loadTestCrypto);

  // The whole lock flow, drawn by each OS's kit (Windows and Linux draw it
  // with their own controls; the goldens are macOS).
  for (final (route, vault, texts) in [
    (Routes.unlock, TestVault.locked, ['Unlock your vault']),
    (Routes.recover, TestVault.locked, ['Use your recovery key']),
    (Routes.create, TestVault.none, ['Create a master password', 'Continue']),
    (Routes.joinVault, TestVault.none, ['Join your vault', 'Find vaults']),
  ]) {
    testWidgets('$route draws on this kit', (tester) async {
      tester.view
        ..physicalSize = const Size(1100, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dir = await tester.runAsync(() => testSupportDir(vault));
      await tester.pumpWidget(
        testApp(location: route, supportDir: dir!, layout: AppLayout.desktop),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DesktopLockWindow), findsOneWidget);
      for (final text in texts) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.desktop());
  }

  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      testWidgets('a link runs its action, is a link, and is big enough', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        var taps = 0;
        await pumpDesktop(
          tester,
          kit,
          DesktopLink(label: 'Use your recovery key…', onPressed: () => taps++),
        );
        await tester.tap(find.text('Use your recovery key…'));
        await tester.pumpAndSettle();
        expect(taps, 1);

        final node = tester.getSemantics(find.text('Use your recovery key…'));
        final data = node.getSemanticsData();
        expect(data.label, contains('Use your recovery key…'));
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.flagsCollection.isLink, isTrue);
        expect(
          tester.getSize(find.byType(DesktopLink)).height,
          greaterThanOrEqualTo(24),
        );
        semantics.dispose();
      });

      testWidgets('a disabled link does nothing', (tester) async {
        await pumpDesktop(
          tester,
          kit,
          const DesktopLink(label: 'Back to unlock', onPressed: null),
        );
        await tester.tap(find.text('Back to unlock'), warnIfMissed: false);
        expect(find.text('Back to unlock'), findsOneWidget);
      });

      testWidgets('a push button can lead with a symbol', (tester) async {
        var taps = 0;
        await pumpDesktop(
          tester,
          kit,
          DesktopButton(
            label: 'Print…',
            icon: DesktopSymbol.printer,
            size: DesktopButtonSize.large,
            onPressed: () => taps++,
          ),
        );
        expect(find.byIcon(DesktopSymbol.printer.of(kit)), findsOneWidget);
        await tester.tap(find.text('Print…'));
        await tester.pumpAndSettle();
        expect(taps, 1);
      });

      testWidgets('the lock window lays out its parts', (tester) async {
        tester.view
          ..physicalSize = const Size(1100, 800)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpDesktop(
          tester,
          kit,
          DesktopLockWindow(
            step: 'Step 1 of 3',
            title: 'Create a master password',
            message: 'No one can reset or recover it for you.',
            footer: DesktopButton(
              label: 'Continue',
              kind: DesktopButtonKind.primary,
              onPressed: () {},
            ),
            children: const [
              DesktopLockBox(child: Text('Argon2id')),
              DesktopFieldMessage('Use at least 4 characters', indent: 120),
            ],
          ),
        );
        for (final text in [
          'Step 1 of 3',
          'Create a master password',
          'No one can reset or recover it for you.',
          'Argon2id',
          'Use at least 4 characters',
          'Continue',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        expect(
          tester.getSize(find.byType(DesktopLockWindow)).width,
          greaterThanOrEqualTo(DesktopMetrics.lockWidth),
        );
        expect(tester.takeException(), isNull);
      });
    });
  }

  test('every lock-screen symbol exists in each set', () {
    for (final symbol in [
      DesktopSymbol.fingerprint,
      DesktopSymbol.faceId,
      DesktopSymbol.submit,
      DesktopSymbol.keyDerivation,
      DesktopSymbol.encrypted,
      DesktopSymbol.savePdf,
      DesktopSymbol.saveText,
      DesktopSymbol.printer,
      DesktopSymbol.copy,
    ]) {
      for (final kit in DesktopKit.values) {
        expect(symbol.of(kit), isNotNull);
      }
    }
  });
}
