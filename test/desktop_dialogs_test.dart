import 'package:devvault/shared/desktop_ui.dart';
import 'package:devvault/shared/widgets/confirm_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';

/// The desktop layer's dialog pieces (radio, spinner, floating panel, sheet
/// header, form errors) and the confirm dialog behave the same whichever
/// kit draws them.
void main() {
  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      testWidgets('a radio reports a click, and not when disabled', (
        tester,
      ) async {
        final log = <bool>[];
        await pumpDesktop(
          tester,
          kit,
          Held<bool>(
            initial: false,
            log: log,
            builder: (selected, onChanged) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DesktopRadio(
                  key: const Key('on'),
                  selected: selected,
                  onSelected: () => onChanged(true),
                  semanticLabel: 'Keep this one',
                ),
                DesktopRadio(
                  key: const Key('off'),
                  selected: false,
                  onSelected: null,
                ),
              ],
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('on')));
        await tester.pumpAndSettle();
        expect(log, [true]);
        await tester.tap(find.byKey(const Key('off')), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(log, [true]);
      });

      testWidgets('a spinner spins, named for screen readers', (tester) async {
        await pumpDesktop(
          tester,
          kit,
          const DesktopProgress(semanticLabel: 'Working'),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(DesktopProgress), findsOneWidget);
        expect(
          tester.getSize(find.byType(DesktopProgress)),
          const Size(16, 16),
        );
      });

      Future<Future<String?>> openPanel(WidgetTester tester) async {
        late Future<String?> result;
        await pumpDesktop(
          tester,
          kit,
          Builder(
            builder: (context) => DesktopButton(
              label: 'Open',
              onPressed: () => result = showDesktopPanel<String>(
                context,
                builder: (context) => DesktopPanel(
                  semanticLabel: 'Quick open',
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DesktopButton(
                      label: 'Pick',
                      onPressed: () => Navigator.of(context).pop('picked'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Pick'), findsOneWidget);
        return result;
      }

      testWidgets('a panel pops what is picked', (tester) async {
        final result = await openPanel(tester);
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();
        expect(await result, 'picked');
      });

      testWidgets('Escape closes a panel', (tester) async {
        final result = await openPanel(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(await result, isNull);
        expect(find.text('Pick'), findsNothing);
      });

      testWidgets('a click outside closes a panel', (tester) async {
        final result = await openPanel(tester);
        await tester.tapAt(const Offset(4, 590));
        await tester.pumpAndSettle();
        expect(await result, isNull);
        expect(find.text('Pick'), findsNothing);
      });

      testWidgets('a sheet shows its icon, message and form errors', (
        tester,
      ) async {
        await pumpDesktop(
          tester,
          kit,
          Builder(
            builder: (context) => DesktopButton(
              label: 'Open',
              onPressed: () => showDesktopSheet<void>(
                context,
                builder: (context) => DesktopSheet(
                  title: 'Change master password',
                  message: 'Your recovery key keeps working.',
                  icon: const DesktopIcon(DesktopSymbol.lock),
                  actions: const [],
                  child: const DesktopForm(
                    children: [
                      DesktopFormRow(
                        label: 'Current password',
                        note: 'The one you unlock with',
                        error: 'Enter your current password',
                        child: DesktopTextField(obscureText: true),
                      ),
                      DesktopFormRow(
                        label: 'New password',
                        note: 'At least 12 characters',
                        child: DesktopTextField(obscureText: true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Change master password'), findsOneWidget);
        expect(find.text('Your recovery key keeps working.'), findsOneWidget);
        expect(find.byType(DesktopIcon), findsOneWidget);
        // An error takes the note's place, in the danger colour.
        expect(find.text('The one you unlock with'), findsNothing);
        final error = tester.widget<Text>(
          find.text('Enter your current password'),
        );
        expect(error.style?.color, DesktopColors.light.danger);
        expect(find.text('At least 12 characters'), findsOneWidget);
      });

      for (final (label, confirm, expected) in [
        ('confirm resolves true', 'Delete', true),
        ('cancel resolves false', 'Cancel', false),
      ]) {
        testWidgets('confirm dialog: $label', (tester) async {
          late Future<bool> result;
          await pumpDesktop(
            tester,
            kit,
            Builder(
              builder: (context) => DesktopButton(
                label: 'Open',
                onPressed: () => result = showConfirmDialog(
                  context,
                  title: 'Delete item?',
                  message: 'A tombstone is synced to your other devices.',
                  confirmLabel: 'Delete',
                  destructive: true,
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(find.byType(DesktopSheet), findsOneWidget);
          expect(
            find.text('A tombstone is synced to your other devices.'),
            findsOneWidget,
          );
          await tester.tap(find.text(confirm));
          await tester.pumpAndSettle();
          expect(await result, expected);
          expect(find.byType(DesktopSheet), findsNothing);
        });
      }

      testWidgets('confirm dialog: Escape resolves false', (tester) async {
        late Future<bool> result;
        await pumpDesktop(
          tester,
          kit,
          Builder(
            builder: (context) => DesktopButton(
              label: 'Open',
              onPressed: () => result = showConfirmDialog(
                context,
                title: 'Turn off sync on this device?',
                message: 'This device stops syncing.',
                confirmLabel: 'Turn off',
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(await result, isFalse);
      });
    });
  }
}
