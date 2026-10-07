import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';

import 'app/theme.dart';

// Temporary entry point that shows the theme. M0-07 replaces it with the
// real app shell (router, providers, lock gate).
void main() => runApp(const DevVaultApp());

class DevVaultApp extends StatelessWidget {
  const DevVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DevVault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _ThemePreview(),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: BCCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BCText('DevVault', type: BCTextType.h4),
                const SizedBox(height: BCSpacing.xs),
                const BCText(
                  'Local-first vault for developer credentials',
                  type: BCTextType.bodySm,
                  color: BCTextColor.muted,
                ),
                const SizedBox(height: BCSpacing.md),
                const BCInput(placeholder: 'Master password', obscureText: true),
                const SizedBox(height: BCSpacing.md),
                Text('AuthKey_7X2K9QH4LM.p8', style: AppText.mono(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
