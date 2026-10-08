import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';

/// The progress spinner is drawn by each kit, at the size asked for, and
/// says what is happening to screen readers.
void main() {
  for (final kit in DesktopKit.values) {
    testWidgets('${kit.name}: a spinner of the given size, labelled', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpDesktop(
        tester,
        kit,
        const DesktopProgress(size: 20, semanticLabel: 'Reading the file'),
      );
      // It never settles (indeterminate), so pump a few frames only.
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getSize(find.byType(DesktopProgress)),
        const Size.square(20),
      );
      expect(find.bySemanticsLabel('Reading the file'), findsOneWidget);
      semantics.dispose();
    });
  }
}
