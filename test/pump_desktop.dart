import 'package:devvault/app/theme.dart';
import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/material.dart' show MaterialApp, Scaffold, ThemeMode;
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] the way a desktop screen sees it: inside the app's
/// MaterialApp, with a [DesktopTheme] for [kit] around the Navigator.
Future<void> pumpDesktop(
  WidgetTester tester,
  DesktopKit kit,
  Widget child, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      // Above the Navigator, as in the app, so menus and flyouts (pushed
      // as routes) get the kit's theme and strings too.
      builder: (context, navigator) =>
          DesktopTheme(kit: kit, child: navigator!),
      home: Scaffold(
        body: Center(
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Holds one value for a controlled widget under test, and records every
/// value the widget reported.
class Held<T> extends StatefulWidget {
  const Held({
    super.key,
    required this.initial,
    required this.builder,
    required this.log,
  });

  final T initial;
  final Widget Function(T value, ValueChanged<T> onChanged) builder;
  final List<T> log;

  @override
  State<Held<T>> createState() => _HeldState<T>();
}

class _HeldState<T> extends State<Held<T>> {
  late T _value = widget.initial;

  @override
  Widget build(BuildContext context) => widget.builder(_value, (v) {
    widget.log.add(v);
    setState(() => _value = v);
  });
}
