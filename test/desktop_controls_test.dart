import 'package:devvault/app/theme.dart' show AppColors;
import 'package:devvault/shared/desktop_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart'
    show DropdownButton, Icons, PopupMenuButton, Theme, ThemeData;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'pump_desktop.dart';

/// The desktop layer (ADR-0005): every control behaves the same whichever
/// kit draws it.
void main() {
  test('each desktop OS gets its own kit', () {
    expect(DesktopKit.forPlatform(TargetPlatform.macOS), DesktopKit.macos);
    expect(DesktopKit.forPlatform(TargetPlatform.windows), DesktopKit.fluent);
    expect(DesktopKit.forPlatform(TargetPlatform.linux), DesktopKit.yaru);
  });

  testWidgets('the theme follows the app brightness', (tester) async {
    late DesktopColors colors;
    final probe = Builder(
      builder: (context) {
        colors = context.desktopColors;
        return const SizedBox();
      },
    );
    await pumpDesktop(tester, DesktopKit.macos, probe);
    expect(colors, DesktopColors.light);
    await pumpDesktop(
      tester,
      DesktopKit.macos,
      probe,
      brightness: Brightness.dark,
    );
    await tester.pumpAndSettle();
    expect(colors, DesktopColors.dark);
  });

  testWidgets('Linux keeps the app theme extensions under Yaru', (
    tester,
  ) async {
    late ThemeData theme;
    await pumpDesktop(
      tester,
      DesktopKit.yaru,
      Builder(
        builder: (context) {
          theme = Theme.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(theme.extension<AppColors>(), isNotNull);
  });

  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      testWidgets('combo box takes typed text', (tester) async {
        final log = <String>[];
        await pumpDesktop(tester, kit, _combo(log, initial: ''));
        expect(_fieldText(tester), isEmpty);

        await tester.enterText(find.byType(EditableText), 'qa-eu');
        expect(log.last, 'qa-eu');
        expect(_fieldText(tester), 'qa-eu');
      });

      testWidgets('combo box picks a suggestion', (tester) async {
        final log = <String>[];
        await pumpDesktop(tester, kit, _combo(log, initial: 'dev'));
        expect(_fieldText(tester), 'dev');

        await tester.tap(_comboMenu(kit));
        await tester.pumpAndSettle();
        await tester.tap(find.text('staging').last);
        await tester.pumpAndSettle();
        expect(log, ['staging']);
        expect(_fieldText(tester), 'staging');
      });

      testWidgets('pop-up picks one of its choices', (tester) async {
        final log = <String>[];
        await pumpDesktop(
          tester,
          kit,
          Held<String?>(
            initial: 'ios',
            log: log,
            builder: (value, onChanged) => DesktopPopup<String>(
              value: value,
              onChanged: onChanged,
              choices: const [
                DesktopChoice('ios', 'iOS'),
                DesktopChoice('android', 'Android'),
              ],
            ),
          ),
        );
        await tester.tap(_popup(kit));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Android').last);
        await tester.pumpAndSettle();
        expect(log, ['android']);
        expect(find.text('Android'), findsOneWidget);
      });

      testWidgets('token field adds and removes tags', (tester) async {
        final log = <List<String>>[];
        await pumpDesktop(
          tester,
          kit,
          Held<List<String>>(
            initial: const ['ios'],
            log: log,
            builder: (value, onChanged) => SizedBox(
              width: 300,
              child: DesktopTokenField(tokens: value, onChanged: onChanged),
            ),
          ),
        );
        final input = find.byType(EditableText);

        // A comma adds the tag.
        await tester.enterText(input, 'prod,');
        await tester.pump();
        expect(log.last, ['ios', 'prod']);

        // So does Return; a tag already there isn't added twice.
        await tester.enterText(input, ' signing ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(log.last, ['ios', 'prod', 'signing']);
        await tester.enterText(input, 'ios');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(log, hasLength(2));

        // Backspace in the empty input removes the last tag.
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(log.last, ['ios', 'prod']);

        // A pill's × removes that tag.
        await tester.tap(find.byIcon(Icons.close).first);
        await tester.pump();
        expect(log.last, ['prod']);
      });

      testWidgets('segmented control picks a segment', (tester) async {
        final log = <String>[];
        await pumpDesktop(
          tester,
          kit,
          Held<String>(
            initial: 'system',
            log: log,
            builder: (value, onChanged) => DesktopSegmented<String>(
              value: value,
              onChanged: onChanged,
              choices: const [
                DesktopChoice('light', 'Light'),
                DesktopChoice('dark', 'Dark'),
                DesktopChoice('system', 'System'),
              ],
            ),
          ),
        );
        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        expect(log, ['dark']);
      });

      testWidgets('switch and checkbox toggle', (tester) async {
        final switches = <bool>[];
        final checks = <bool>[];
        await pumpDesktop(
          tester,
          kit,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Held<bool>(
                initial: false,
                log: switches,
                builder: (value, onChanged) =>
                    DesktopSwitch(value: value, onChanged: onChanged),
              ),
              Held<bool>(
                initial: false,
                log: checks,
                builder: (value, onChanged) => DesktopCheckbox(
                  value: value,
                  onChanged: onChanged,
                  label: 'Lock when the screen locks',
                ),
              ),
            ],
          ),
        );
        await tester.tap(find.byType(DesktopSwitch));
        await tester.pumpAndSettle();
        expect(switches, [true]);

        // The label toggles the box as well.
        await tester.tap(find.text('Lock when the screen locks'));
        await tester.pump();
        expect(checks, [true]);
      });

      testWidgets('buttons press, and do nothing when disabled', (
        tester,
      ) async {
        var pressed = 0;
        await pumpDesktop(
          tester,
          kit,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DesktopButton(label: 'Cancel', onPressed: () => pressed++),
              const DesktopButton(
                label: 'Add to Vault',
                kind: DesktopButtonKind.primary,
                onPressed: null,
              ),
            ],
          ),
        );
        await tester.tap(find.text('Cancel'));
        await tester.tap(find.text('Add to Vault'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(pressed, 1);
      });

      testWidgets('a secure field masks its text', (tester) async {
        await pumpDesktop(
          tester,
          kit,
          const SizedBox(
            width: 240,
            child: DesktopTextField(obscureText: true, placeholder: 'Secret'),
          ),
        );
        await tester.enterText(find.byType(EditableText), 'hunter2');
        await tester.pump();
        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.obscureText, isTrue);
        expect(field.autocorrect, isFalse);
      });
    });
  }
}

Widget _combo(List<String> log, {required String initial}) => SizedBox(
  width: 260,
  child: Held<String>(
    initial: initial,
    log: log,
    builder: (value, onChanged) => DesktopComboBox(
      value: value,
      onChanged: onChanged,
      placeholder: 'Environment',
      suggestions: const ['dev', 'staging', 'prod'],
    ),
  ),
);

String _fieldText(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

Finder _comboMenu(DesktopKit kit) => switch (kit) {
  DesktopKit.macos => find.byIcon(CupertinoIcons.chevron_down),
  DesktopKit.fluent => find.byType(fl.IconButton),
  DesktopKit.yaru => find.byType(PopupMenuButton<String>),
};

Finder _popup(DesktopKit kit) => switch (kit) {
  DesktopKit.macos => find.byType(mac.MacosPopupButton<String>),
  DesktopKit.fluent => find.byType(fl.ComboBox<String>),
  DesktopKit.yaru => find.byType(DropdownButton<String>),
};
