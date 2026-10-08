import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';

/// `DesktopScopeBar` (the vault table's All / Expiring / Files / Secrets):
/// every kit shows each scope and reports the one picked.
void main() {
  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      testWidgets('shows every scope and picks one', (tester) async {
        final log = <String>[];
        await pumpDesktop(
          tester,
          kit,
          Held<String>(
            initial: 'all',
            log: log,
            builder: (value, onChanged) => DesktopScopeBar<String>(
              value: value,
              onChanged: onChanged,
              choices: const [
                DesktopChoice('all', 'All'),
                DesktopChoice('files', 'Files'),
                DesktopChoice('secrets', 'Secrets'),
              ],
            ),
          ),
        );
        for (final label in ['All', 'Files', 'Secrets']) {
          expect(find.text(label), findsOneWidget, reason: label);
        }

        await tester.tap(find.text('Files'));
        await tester.pumpAndSettle();
        expect(log, ['files']);
        await tester.tap(find.text('Secrets'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();
        expect(log, ['files', 'secrets', 'all']);
      });
    });
  }

  testWidgets('macOS: the chosen scope is selected for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpDesktop(
      tester,
      DesktopKit.macos,
      DesktopScopeBar<int>(
        value: 2,
        onChanged: (_) {},
        choices: const [DesktopChoice(1, 'One'), DesktopChoice(2, 'Two')],
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Two')),
      isSemantics(
        label: 'Two',
        isButton: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('One')),
      isSemantics(
        label: 'One',
        isButton: true,
        isSelected: false,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });
}
