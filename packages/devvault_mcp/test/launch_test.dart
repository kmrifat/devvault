import 'dart:io';

import 'package:agent_bridge/agent_bridge.dart';
import 'package:devvault_mcp/devvault_mcp.dart';
import 'package:test/test.dart';

/// Where the helper looks for the app, and how it starts it (ADR-0006,
/// P5-11).
void main() {
  group('defaultSocketPath', () {
    test('macOS: the socket in the app container', () {
      expect(
        defaultSocketPath({'HOME': '/Users/a'}, macOS: true),
        socketPathForHome('/Users/a'),
      );
    });

    test(r'Linux: the socket in $XDG_RUNTIME_DIR', () {
      expect(
        defaultSocketPath({'XDG_RUNTIME_DIR': '/run/user/1000'}, linux: true),
        '/run/user/1000/devvault.sock',
      );
    });

    test(r'Linux without $XDG_RUNTIME_DIR, and Windows: none', () {
      expect(defaultSocketPath({'HOME': '/home/a'}, linux: true), isNull);
      expect(defaultSocketPath({'XDG_RUNTIME_DIR': ''}, linux: true), isNull);
      expect(defaultSocketPath({'HOME': r'C:\Users\a'}), isNull);
    });
  });

  group('linuxLaunchCommand', () {
    test('from an AppImage: the AppImage', () {
      expect(
        linuxLaunchCommand({'APPIMAGE': '/opt/DevVault.AppImage'}, '/tmp/x'),
        ['/opt/DevVault.AppImage'],
      );
    });

    test('from the release bundle: the app beside the helper', () async {
      final dir = await Directory.systemTemp.createTemp('devvault_launch_');
      addTearDown(() => dir.delete(recursive: true));
      final helper = '${dir.path}/devvault-mcp';
      expect(linuxLaunchCommand({}, helper), isNull);
      await File('${dir.path}/devvault').writeAsString('');
      expect(linuxLaunchCommand({}, helper), ['${dir.path}/devvault']);
    });
  });

  group('Windows', () {
    test('tokens live under %APPDATA%', () {
      final store = TokenStore.forUser({
        'APPDATA': r'C:\Users\a\AppData\Roaming',
      }, windows: true);
      expect(
        store?.file.path,
        r'C:\Users\a\AppData\Roaming\DevVault\agent-tokens.json',
      );
      expect(TokenStore.forUser({}, windows: true), isNull);
      expect(
        TokenStore.forUser({'HOME': '/home/a'})?.file.path,
        '/home/a/.config/devvault/agent-tokens.json',
      );
    });

    test('the app is devvault.exe beside the helper', () async {
      final dir = await Directory.systemTemp.createTemp('devvault_win_');
      addTearDown(() => dir.delete(recursive: true));
      final helper = '${dir.path}\\devvault-mcp.exe';
      expect(windowsLaunchCommand(helper), isNull);
      await File('${dir.path}\\devvault.exe').writeAsString('');
      expect(windowsLaunchCommand(helper), ['${dir.path}\\devvault.exe']);
    }, testOn: 'windows');
  });
}
