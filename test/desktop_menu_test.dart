import 'package:devvault/app/app_menus.dart';
import 'package:devvault/app/desktop_commands.dart';
import 'package:devvault/app/desktop_shell.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/app/theme.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/material.dart'
    show MaterialApp, PlatformProvidedMenuItemType, Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_overrides.dart';

/// The desktop menu bar (design doc › Menu bar).
void main() {
  setUpAll(loadTestCrypto);

  List<DesktopMenu> menus({
    required bool macos,
    bool unlocked = true,
    bool syncing = true,
    DesktopCommands? commands,
    List<String>? log,
  }) => AppMenus.menus(
    macos: macos,
    unlocked: unlocked,
    syncing: syncing,
    go: (location) => log?.add('go $location'),
    lock: () => log?.add('lock'),
    syncNow: () => log?.add('sync'),
    about: () => log?.add('about'),
    commands: commands ?? DesktopCommands(),
  );

  DesktopMenuItem item(List<DesktopMenu> menus, String menu, String label) =>
      menus
          .firstWhere((m) => m.label == menu)
          .entries
          .whereType<DesktopMenuItem>()
          .firstWhere((i) => i.label == label);

  DesktopCommands bound(List<String> log) => DesktopCommands()
    ..bind(
      find: () => log.add('find'),
      newItem: () => log.add('new'),
      importFile: () => log.add('import'),
      quickOpen: () => log.add('quick open'),
    );

  group('menus', () {
    test('macOS: the app menu, the Edit commands and the Window menu', () {
      final m = menus(macos: true);
      expect(m.map((m) => m.label), [
        'DevVault',
        'File',
        'Edit',
        'View',
        'Vault',
        'Window',
      ]);
      final app = m.first.entries;
      expect(
        app.whereType<DesktopMenuProvided>().map((p) => p.type),
        containsAll([
          PlatformProvidedMenuItemType.about,
          PlatformProvidedMenuItemType.quit,
        ]),
      );
      expect(
        item(m, 'DevVault', 'Settings…').shortcut?.trigger,
        LogicalKeyboardKey.comma,
      );
      for (final label in ['Undo', 'Cut', 'Copy', 'Paste', 'Select All']) {
        expect(item(m, 'Edit', label).onSelected, isNotNull, reason: label);
      }
      expect(item(m, 'File', 'Import…').shortcut?.meta, isTrue);
    });

    test('Windows and Linux: Settings and Quit in File, About in Help', () {
      final log = <String>[];
      final m = menus(macos: false, log: log);
      expect(m.map((m) => m.label), ['File', 'Edit', 'View', 'Vault', 'Help']);
      expect(item(m, 'File', 'Quit').onSelected, isNotNull);
      item(m, 'File', 'Settings').onSelected!();
      item(m, 'Help', 'About DevVault').onSelected!();
      expect(log, ['go ${Routes.settings}', 'about']);
      final import = item(m, 'File', 'Import…').shortcut!;
      expect((import.control, import.meta), (true, false));
      // Text fields keep their own copy and paste there.
      expect(
        m.firstWhere((m) => m.label == 'Edit').entries,
        everyElement(
          isA<DesktopMenuItem>().having((i) => i.label, 'label', 'Find'),
        ),
      );
    });

    test('while locked, everything that needs the vault is disabled', () {
      final log = <String>[];
      final m = menus(
        macos: true,
        unlocked: false,
        commands: bound(log),
        log: log,
      );
      for (final (menu, label) in [
        ('DevVault', 'Settings…'),
        ('File', 'New Item'),
        ('File', 'Import…'),
        ('Edit', 'Find'),
        ('View', 'Quick Open'),
        ('Vault', 'Sync Now'),
        ('Vault', 'Lock'),
        ('Vault', 'Expiry'),
      ]) {
        expect(item(m, menu, label).onSelected, isNull, reason: label);
      }
      // Editing still works in the password field.
      expect(item(m, 'Edit', 'Paste').onSelected, isNotNull);
    });

    test('unlocked, the items run the window commands', () {
      final log = <String>[];
      final m = menus(macos: true, commands: bound(log), log: log);
      for (final (menu, label) in [
        ('File', 'New Item'),
        ('File', 'Import…'),
        ('Edit', 'Find'),
        ('View', 'Quick Open'),
        ('Vault', 'Sync Now'),
        ('Vault', 'Lock'),
        ('Vault', 'Expiry'),
      ]) {
        item(m, menu, label).onSelected!();
      }
      expect(log, [
        'new',
        'import',
        'find',
        'quick open',
        'sync',
        'lock',
        'go ${Routes.expiry}',
      ]);
    });

    test('Sync Now is off while sync is', () {
      final m = menus(macos: true, syncing: false);
      expect(item(m, 'Vault', 'Sync Now').onSelected, isNull);
    });
  });

  testWidgets('macOS: the menus go to the system menu bar and run from it', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.menu,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.menu,
        null,
      ),
    );
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => DesktopTheme(
          kit: DesktopKit.macos,
          nativeWindow: true,
          child: Builder(
            builder: (context) => DesktopMenuBar(
              menus: menus(macos: true, commands: bound(log), log: log),
              child: child!,
            ),
          ),
        ),
        home: const Scaffold(),
      ),
    );
    await tester.pump();

    final set = calls.lastWhere((c) => c.method == 'Menu.setMenus');
    final top = ((set.arguments as Map)['0'] as List).cast<Map>();
    expect(top.map((m) => m['label']), [
      'DevVault',
      'File',
      'Edit',
      'View',
      'Vault',
      'Window',
    ]);
    Map<dynamic, dynamic>? find(List<Map> items, String label) {
      for (final i in items) {
        if (i['label'] == label) return i;
        final found = find(((i['children'] as List?) ?? []).cast<Map>(), label);
        if (found != null) return found;
      }
      return null;
    }

    final import = find(top, 'Import…')!;
    expect(import['enabled'], isTrue);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.menu.name,
      SystemChannels.menu.codec.encodeMethodCall(
        MethodCall('Menu.selectedCallback', import['id']),
      ),
      (_) {},
    );
    expect(log, ['import']);
  });

  for (final kit in [DesktopKit.fluent, DesktopKit.yaru]) {
    testWidgets('${kit.name}: a menu bar along the top of the window', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => DesktopTheme(
            kit: kit,
            child: Builder(
              builder: (context) => DesktopMenuBar(
                menus: menus(macos: false, commands: bound(log), log: log),
                child: child!,
              ),
            ),
          ),
          home: const Scaffold(),
        ),
      );
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      expect(find.text('Ctrl+I'), findsOneWidget);
      await tester.tap(find.text('Import…'));
      await tester.pumpAndSettle();
      expect(log, ['import']);
    });
  }

  testWidgets('the vault window binds its commands while it is open', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      vault: TestVault.sample,
      layout: AppLayout.desktop,
    );
    final commands = DesktopCommands.maybeOf(
      tester.element(find.byType(DesktopShell)),
    )!;
    expect(commands.find, isNotNull);

    commands.find!();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'vault search');

    appContainer(tester).read(vaultSessionProvider.notifier).lock();
    await tester.pumpAndSettle();
    expect(commands.find, isNull);
    expect(commands.importFile, isNull);
  });
}
