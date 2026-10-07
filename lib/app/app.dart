import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'layout.dart';
import 'router.dart';
import 'routes.dart';
import 'theme.dart';

class DevVaultApp extends StatefulWidget {
  const DevVaultApp({
    super.key,
    this.initialLocation = Routes.unlock,
    this.layout,
  });

  /// Where the app opens. Tests and `--dart-define=START=` set it.
  final String initialLocation;

  /// Overrides the platform's layout (tests render both).
  final AppLayout? layout;

  @override
  State<DevVaultApp> createState() => _DevVaultAppState();
}

class _DevVaultAppState extends State<DevVaultApp> {
  late final GoRouter _router = buildRouter(
    layout: widget.layout ?? AppLayout.current,
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DevVault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
