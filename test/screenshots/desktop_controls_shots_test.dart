/// The desktop layer's controls in a sheet-style form
/// (docs/design/desktop.md › Controls), light and dark, drawn by each kit:
/// macOS, Windows (Fluent) and Linux (Yaru). The menus and the sheet are
/// shot in the macOS kit only; see harness.dart for how goldens are made.
@Tags(['golden'])
library;

import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter_test/flutter_test.dart';

import '../pump_desktop.dart';

void main() {
  testWidgets('desktop-combo-menu-macos-light', (tester) async {
    tester.view
      ..physicalSize = const Size(1120, 1040)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    // Real shadows, as in harness.dart (restored in the body).
    debugDisableShadows = false;
    try {
      await pumpDesktop(tester, DesktopKit.macos, const _Gallery());
      // Open the Environment combo box's suggestions.
      await tester.tap(find.byIcon(CupertinoIcons.chevron_down).last);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../screenshots/desktop-combo-menu-macos-light.png',
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
    }
  });

  testWidgets('desktop-popup-long-label-macos-light', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 640)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    debugDisableShadows = false;
    try {
      await pumpDesktop(tester, DesktopKit.macos, const _LongLabels());
      // Open the App pop-up's menu.
      await tester.tap(find.byType(DesktopPopup<String>).last);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../../screenshots/desktop-popup-long-label-macos-light.png',
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
    }
  });

  testWidgets('desktop-sheet-macos-light', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    debugDisableShadows = false;
    try {
      await pumpDesktop(
        tester,
        DesktopKit.macos,
        Builder(
          builder: (context) => DesktopButton(
            label: 'Open',
            onPressed: () => showDesktopSheet<void>(
              context,
              builder: (context) => DesktopSheet(
                title: 'Import AuthKey_R7KQ2M9XWP.p8',
                leadingAction: DesktopButton(
                  label: 'Delete',
                  kind: DesktopButtonKind.destructive,
                  onPressed: () {},
                ),
                actions: [
                  DesktopButton(label: 'Cancel', onPressed: () {}),
                  DesktopButton(
                    label: 'Add to Vault',
                    kind: DesktopButtonKind.primary,
                    onPressed: () {},
                  ),
                ],
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 14,
                  children: [
                    const DesktopGroupBox(
                      title: 'From the file',
                      child: Text('Key ID R7KQ2M9XWP · APNs auth key'),
                    ),
                    DesktopForm(
                      children: [
                        DesktopFormRow(
                          label: 'Name',
                          child: DesktopTextField(
                            controller: TextEditingController(
                              text: 'Kitchenly · APNs',
                            ),
                          ),
                        ),
                        DesktopFormRow(
                          label: 'Environment',
                          child: DesktopComboBox(
                            value: 'production',
                            suggestions: const ['development', 'production'],
                            onChanged: (_) {},
                          ),
                        ),
                      ],
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
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../screenshots/desktop-sheet-macos-light.png'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
    }
  });

  // Every kit, so the Windows and Linux controls can be reviewed too.
  // Yaru's controls are Material-sized, so its gallery is taller.
  for (final (kit, platform, height) in [
    (DesktopKit.macos, TargetPlatform.macOS, 1040.0),
    (DesktopKit.fluent, TargetPlatform.windows, 1040.0),
    (DesktopKit.yaru, TargetPlatform.linux, 1240.0),
  ]) {
    for (final brightness in Brightness.values) {
      final name = 'desktop-controls-${kit.name}-${brightness.name}';
      testWidgets(name, (tester) async {
        tester.view
          ..physicalSize = Size(1120, height)
          ..devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = platform;
        // Real shadows, as in harness.dart (restored in the body).
        debugDisableShadows = false;
        try {
          await pumpDesktop(
            tester,
            kit,
            const _Gallery(),
            brightness: brightness,
          );
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(_Gallery),
            matchesGoldenFile('../../screenshots/$name.png'),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
          debugDisableShadows = true;
        }
      });
    }
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return SizedBox(
      width: 512,
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
                label: 'Key ID',
                child: DesktopTextField(
                  mono: true,
                  controller: TextEditingController(text: 'R7KQ2M9XWP'),
                ),
              ),
              DesktopFormRow(
                label: 'Secret',
                child: DesktopTextField(
                  obscureText: true,
                  controller: TextEditingController(text: 'not-a-real-key'),
                ),
              ),
              DesktopFormRow(
                label: 'Platform',
                child: DesktopComboBox(
                  value: 'iOS',
                  suggestions: const ['iOS', 'Android', 'Web'],
                  onChanged: (_) {},
                ),
              ),
              DesktopFormRow(
                label: 'Environment',
                note: 'Pick one or type your own.',
                child: DesktopComboBox(
                  value: '',
                  placeholder: 'None',
                  suggestions: const ['dev', 'staging', 'prod'],
                  onChanged: (_) {},
                ),
              ),
              DesktopFormRow(
                label: 'Type',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DesktopPopup<String>(
                    value: 'p8',
                    onChanged: (_) {},
                    choices: const [
                      DesktopChoice('p8', 'APNs key (.p8)'),
                      DesktopChoice('secret', 'Generic secret'),
                    ],
                  ),
                ),
              ),
              DesktopFormRow(
                label: 'Tags',
                child: DesktopTokenField(
                  tokens: const ['ios', 'push'],
                  placeholder: 'Add a tag',
                  onChanged: (_) {},
                ),
              ),
              DesktopFormRow(
                label: 'Appearance',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DesktopSegmented<String>(
                    value: 'system',
                    onChanged: (_) {},
                    choices: const [
                      DesktopChoice('light', 'Light'),
                      DesktopChoice('dark', 'Dark'),
                      DesktopChoice('system', 'System'),
                    ],
                  ),
                ),
              ),
              DesktopFormRow(
                label: 'Touch ID',
                child: Row(
                  children: [
                    DesktopSwitch(value: true, onChanged: (_) {}),
                    const Spacer(),
                  ],
                ),
              ),
              DesktopFormRow(
                label: 'Auto-lock',
                child: DesktopCheckbox(
                  value: true,
                  label: 'Lock when the screen locks',
                  onChanged: (_) {},
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  DesktopButton(
                    label: 'Delete',
                    kind: DesktopButtonKind.destructive,
                    onPressed: () {},
                  ),
                  const Spacer(),
                  DesktopButton(label: 'Cancel', onPressed: () {}),
                  DesktopButton(
                    label: 'Add to Vault',
                    kind: DesktopButtonKind.primary,
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pop-ups whose choices are long "Organization › App" labels, as in the
/// explorer's Move to app… sheet: one sized to its choice, one filling its
/// form row.
class _LongLabels extends StatelessWidget {
  const _LongLabels();

  static const _choices = [
    DesktopChoice('', 'No app'),
    DesktopChoice('billing', 'Acme Corporation › Billing and Subscriptions'),
    DesktopChoice(
      'gateway',
      'Acme Corporation International Holdings › Payments Gateway '
          'Reconciliation Service (Production, EU West)',
    ),
    DesktopChoice('notes', 'Personal › Notes'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return SizedBox(
      width: 440,
      child: ColoredBox(
        color: colors.window,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: DesktopForm(
            children: [
              DesktopFormRow(
                label: 'Moved from',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DesktopPopup<String>(
                    value: 'billing',
                    onChanged: (_) {},
                    choices: _choices,
                  ),
                ),
              ),
              DesktopFormRow(
                label: 'App',
                child: DesktopPopup<String>(
                  value: 'gateway',
                  onChanged: (_) {},
                  choices: _choices,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
