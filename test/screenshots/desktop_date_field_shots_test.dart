/// The desktop date field with its calendar open, drawn by the macOS kit,
/// light and dark. Goldens cover the macOS kit only (ADR-0005); see
/// harness.dart for how they're made.
@Tags(['golden'])
library;

import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter_test/flutter_test.dart';

import '../pump_desktop.dart';

void main() {
  for (final brightness in Brightness.values) {
    final name = 'desktop-date-picker-macos-${brightness.name}';
    testWidgets(name, (tester) async {
      tester.view
        ..physicalSize = const Size(1000, 720)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      // Real shadows, as in harness.dart (restored in the body).
      debugDisableShadows = false;
      try {
        await pumpDesktop(
          tester,
          DesktopKit.macos,
          const _Form(),
          brightness: brightness,
        );
        await tester.tap(find.byIcon(CupertinoIcons.calendar));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../../screenshots/$name.png'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
        debugDisableShadows = true;
      }
    });
  }
}

class _Form extends StatelessWidget {
  const _Form();

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 420,
        child: ColoredBox(
          color: colors.window,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: DesktopForm(
              children: [
                DesktopFormRow(
                  label: 'Name',
                  child: DesktopTextField(
                    controller: TextEditingController(text: 'Kitchenly · APNs'),
                  ),
                ),
                DesktopFormRow(
                  label: 'Expires',
                  note: 'Set by you · leave empty for no expiry',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 160,
                      // A date far from today, so the calendar shows no
                      // "today" and the image doesn't change with the date.
                      child: DesktopDateField(
                        value: DateTime(2031, 3, 14),
                        placeholder: 'No expiry date',
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
