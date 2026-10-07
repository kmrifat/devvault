import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] inside a themed app, the minimum a bc_ui widget needs:
/// `context.bcTheme` throws without a BCTheme, and BCToast needs its
/// provider.
Future<void> pumpBC(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      builder: (context, child) => BCToastProvider(child: child!),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}
