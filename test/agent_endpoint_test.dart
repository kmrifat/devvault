import 'dart:io';

import 'package:devvault/services/agent_socket.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where AI agents reach the app on Linux (P5-11, ADR-0006).
void main() {
  late Directory runtime;

  setUp(() async {
    runtime = await Directory.systemTemp.createTemp('devvault_runtime_');
    addTearDown(() => runtime.delete(recursive: true));
  });

  Future<void> chmod(String mode, String path) async =>
      expect((await Process.run('chmod', [mode, path])).exitCode, 0);

  test(r'the socket is in $XDG_RUNTIME_DIR when only its owner can open '
      'it', () async {
    await chmod('700', runtime.path);
    final endpoint = AgentEndpoint.linux({
      'XDG_RUNTIME_DIR': runtime.path,
    }, '/opt/devvault/devvault');
    expect(endpoint?.socket, '${runtime.path}/devvault.sock');
    expect(endpoint?.helper, isNull, reason: 'no helper in this "bundle"');
  });

  test('a runtime directory others can open, or none, turns agents '
      'off', () async {
    await chmod('755', runtime.path);
    expect(
      AgentEndpoint.linux({'XDG_RUNTIME_DIR': runtime.path}, '/x/devvault'),
      isNull,
    );
    expect(AgentEndpoint.linux({}, '/x/devvault'), isNull);
  });

  test('the helper: the AppImage with --mcp, or the one in the '
      'bundle', () async {
    await chmod('700', runtime.path);
    final appImage = AgentEndpoint.linux({
      'XDG_RUNTIME_DIR': runtime.path,
      'APPIMAGE': '/home/a/devvault-linux-x64.AppImage',
    }, '/tmp/.mount_x/usr/lib/devvault/devvault');
    expect(appImage?.helper, '/home/a/devvault-linux-x64.AppImage');
    expect(appImage?.helperArgs, ['--mcp']);

    final bundle = await Directory.systemTemp.createTemp('devvault_bundle_');
    addTearDown(() => bundle.delete(recursive: true));
    await File('${bundle.path}/devvault-mcp').writeAsString('');
    final tarball = AgentEndpoint.linux({
      'XDG_RUNTIME_DIR': runtime.path,
    }, '${bundle.path}/devvault');
    expect(tarball?.helper, '${bundle.path}/devvault-mcp');
    expect(tarball?.helperArgs, isEmpty);
  });

  test('macOS: only the sandboxed app serves agents', () {
    expect(AgentEndpoint.macOS({'HOME': '/Users/a'}, '/x'), isNull);
    final endpoint = AgentEndpoint.macOS({
      'HOME': '/Users/a/Library/Containers/com.binarycastle.devvault/Data',
    }, '/Applications/DevVault.app/Contents/MacOS/DevVault');
    expect(
      endpoint?.helper,
      '/Applications/DevVault.app/Contents/Helpers/devvault-mcp',
    );
  });
}
