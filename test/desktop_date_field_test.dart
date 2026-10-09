import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart' show MacosIcon;

import 'pump_desktop.dart';

/// The desktop date field: a calendar to pick from, Clear, and typing, on
/// every kit.
void main() {
  group('parse', () {
    DesktopDateInput parse(String text) => DesktopDateField.parse(text);

    test('reads YYYY-MM-DD and the medium format', () {
      expect(parse('2027-03-01').date, DateTime(2027, 3, 1));
      expect(parse(' 2027-3-1 ').date, DateTime(2027, 3, 1));
      expect(parse('Mar 1, 2027').date, DateTime(2027, 3, 1));
      expect(parse('march 1 2027').date, DateTime(2027, 3, 1));
      expect(parse('3/1/2027').date, DateTime(2027, 3, 1));
    });

    test('empty is no date, not a problem', () {
      expect(parse('  '), (date: null, problem: null));
    });

    test('says what is wrong with text that is not a date', () {
      expect(parse('next year').problem, DesktopDateProblem.unreadable);
      expect(parse('2027-02-30').problem, DesktopDateProblem.noSuchDate);
      expect(parse('Feb 30, 2027').problem, DesktopDateProblem.noSuchDate);
      // Still being typed: a year has four digits.
      expect(parse('Mar 1, 202').problem, DesktopDateProblem.unreadable);
      expect(parse('Mar 1, 202').date, isNull);
    });
  });

  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      Finder calendarButton() => find.byIcon(DesktopSymbol.calendar.of(kit));

      testWidgets('shows the date in the medium format, or the placeholder', (
        tester,
      ) async {
        await pumpDesktop(tester, kit, _field([], initial: null));
        expect(_fieldText(tester), isEmpty);
        expect(find.text('No expiry date'), findsOneWidget);

        // A new field, not the empty one rebuilt.
        await tester.pumpWidget(const SizedBox());
        await pumpDesktop(
          tester,
          kit,
          _field([], initial: DateTime(2031, 3, 1)),
        );
        await tester.pumpAndSettle();
        expect(_fieldText(tester), 'Mar 1, 2031');
      });

      testWidgets('the calendar picks a date', (tester) async {
        final log = <DateTime?>[];
        await pumpDesktop(
          tester,
          kit,
          _field(log, initial: DateTime(2031, 3, 1)),
        );

        await tester.tap(calendarButton());
        await tester.pumpAndSettle();
        // Opening the calendar picks nothing.
        expect(log, isEmpty);
        await tester.tap(find.text('15').hitTestable().last);
        await tester.pumpAndSettle();
        expect(log, [DateTime(2031, 3, 15)]);
        expect(_fieldText(tester), 'Mar 15, 2031');
        // Picking closes it.
        expect(find.text('Clear'), findsNothing);
      });

      testWidgets('opening an empty field sets no date', (tester) async {
        final log = <DateTime?>[];
        await pumpDesktop(tester, kit, _field(log, initial: null));
        await tester.tap(calendarButton());
        await tester.pumpAndSettle();
        // Nothing to clear yet.
        expect(find.text('Clear'), findsNothing);
        expect(find.text('15'), findsWidgets);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        // Esc closes it.
        expect(find.text('15'), findsNothing);
        expect(log, isEmpty);
        expect(_fieldText(tester), isEmpty);
      });

      testWidgets('Clear empties the field', (tester) async {
        final log = <DateTime?>[];
        await pumpDesktop(
          tester,
          kit,
          _field(log, initial: DateTime(2031, 3, 1)),
        );
        await tester.tap(calendarButton());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(log, [null]);
        expect(_fieldText(tester), isEmpty);
      });

      testWidgets('takes a typed date and says when it is not one', (
        tester,
      ) async {
        final log = <DateTime?>[];
        final problems = <DesktopDateProblem?>[];
        await pumpDesktop(
          tester,
          kit,
          _field(log, initial: null, problems: problems),
        );
        final input = find.byType(EditableText);

        await tester.enterText(input, 'next year');
        expect(problems.last, DesktopDateProblem.unreadable);
        await tester.enterText(input, '2031-02-30');
        expect(problems.last, DesktopDateProblem.noSuchDate);
        expect(log, isEmpty);

        await tester.enterText(input, '2031-04-02');
        expect(problems.last, isNull);
        expect(log, [DateTime(2031, 4, 2)]);
        // The text stays as typed while the user types.
        expect(_fieldText(tester), '2031-04-02');

        await tester.enterText(input, 'Apr 3, 2031');
        expect(log.last, DateTime(2031, 4, 3));

        // Return tidies it into the shown format.
        await tester.enterText(input, '2031-4-5');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(log.last, DateTime(2031, 4, 5));
        expect(_fieldText(tester), 'Apr 5, 2031');

        // Emptying the field is no date.
        await tester.enterText(input, '');
        expect(log.last, isNull);
        expect(problems.last, isNull);
      });
    });
  }

  testWidgets('macOS: moving between months picks nothing', (tester) async {
    final log = <DateTime?>[];
    await pumpDesktop(
      tester,
      DesktopKit.macos,
      _field(log, initial: DateTime(2031, 3, 1)),
    );
    await tester.tap(find.byIcon(CupertinoIcons.calendar));
    await tester.pumpAndSettle();
    expect(find.text('Mar 2031'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is MacosIcon && w.icon == CupertinoIcons.arrowtriangle_right_fill,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Apr 2031'), findsOneWidget);
    expect(log, isEmpty);

    // A day in the month on show is a pick, even the 1st.
    await tester.tap(find.text('1').hitTestable().last);
    await tester.pumpAndSettle();
    expect(log, [DateTime(2031, 4, 1)]);
  });

  testWidgets('a disabled field opens no calendar', (tester) async {
    await pumpDesktop(
      tester,
      DesktopKit.macos,
      SizedBox(
        width: 220,
        child: DesktopDateField(
          value: DateTime(2031, 3, 1),
          enabled: false,
          onChanged: (_) => fail('changed'),
        ),
      ),
    );
    await tester.tap(find.byIcon(CupertinoIcons.calendar), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Mar 2031'), findsNothing);
  });
}

Widget _field(
  List<DateTime?> log, {
  required DateTime? initial,
  List<DesktopDateProblem?>? problems,
}) => Held<DateTime?>(
  initial: initial,
  log: log,
  builder: (value, onChanged) => SizedBox(
    width: 220,
    child: DesktopDateField(
      value: value,
      placeholder: 'No expiry date',
      onChanged: onChanged,
      onProblem: problems?.add,
    ),
  ),
);

String _fieldText(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;
