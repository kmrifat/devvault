import 'package:devvault/features/pairing/scan_pairing_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'pump_bc.dart';

/// The pairing-code scanner (phones): the camera fills the screen. It
/// filled only the header's strip at the top before, because the stack
/// took its one unpositioned child's size.
void main() {
  testWidgets('the camera view fills the screen, under the header', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpBC(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => scanPairingCode(context),
          child: const Text('Scan'),
        ),
      ),
    );
    await tester.tap(find.text('Scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.getSize(find.byType(MobileScanner)), const Size(390, 844));
    expect(
      find.text('Point the camera at the code on your other device'),
      findsOneWidget,
    );
  });
}
