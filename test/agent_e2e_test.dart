@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devvault/data/agent_bridge.dart';
import 'package:devvault/data/app_settings.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_overrides.dart';
import 'wait_until.dart';

/// End to end (P5-10): the real `devvault-mcp` process, spoken to over
/// stdio the way Claude Code does, against the app's bridge serving the
/// sample vault. The user's answers come from the test, as taps would.
void main() {
  setUpAll(loadTestCrypto);

  late ProviderContainer c;
  late Process helper;
  late StreamIterator<String> out;
  late Directory home;
  var nextId = 1;

  setUp(() async {
    final support = await testSupportDir(TestVault.sample);
    final sockets = Directory.systemTemp.createTempSync('ab');
    home = Directory.systemTemp.createTempSync('dvhome');
    addTearDown(() {
      sockets.deleteSync(recursive: true);
      home.deleteSync(recursive: true);
    });
    final socket = '${sockets.path}/dv.sock';
    c = ProviderContainer(
      overrides: [
        ...testOverrides(supportDir: support),
        initialSettingsProvider.overrideWithValue(
          const AppSettings(agentsEnabled: true),
        ),
        agentSocketPathProvider.overrideWithValue(socket),
      ],
    );
    addTearDown(c.dispose);
    await c.read(vaultSessionProvider.notifier).unlock(testPassword);
    c.listen(agentBridgeProvider, (_, _) {});
    await until(() => c.read(agentBridgeProvider).listening);

    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    helper = await Process.start(
      flutterRoot == null ? 'dart' : '$flutterRoot/bin/dart',
      [
        'run',
        'packages/devvault_mcp/bin/devvault_mcp.dart',
        '--socket',
        socket,
        '--no-launch',
      ],
      environment: {'HOME': home.path},
    );
    addTearDown(() async {
      helper.kill();
      await helper.exitCode;
    });
    out = StreamIterator(
      helper.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
  });

  Future<Map<String, Object?>> rpc(String method, [Map? params]) async {
    final id = nextId++;
    helper.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    while (await out.moveNext().timeout(const Duration(seconds: 90))) {
      final message = jsonDecode(out.current) as Map<String, Object?>;
      if (message['id'] == id) return message['result'] as Map<String, Object?>;
    }
    fail('devvault-mcp exited');
  }

  /// Calls [tool]; returns (isError, text).
  Future<(bool, String)> tool(String tool, Map<String, Object?> args) async {
    final result = await rpc('tools/call', {'name': tool, 'arguments': args});
    final text = ((result['content'] as List).single as Map)['text'] as String;
    return (result['isError'] == true, text);
  }

  /// Answers the next prompt as the user would.
  Future<AgentPrompt> answer(AgentDecision decision) async {
    // The first one waits for `dart run` to build the helper.
    await until(
      () => c.read(agentBridgeProvider).prompts.isNotEmpty,
      within: const Duration(seconds: 90),
    );
    final prompt = c.read(agentBridgeProvider).prompts.first;
    c.read(agentBridgeProvider.notifier).answer(prompt, decision);
    return prompt;
  }

  test('pair, list, reveal, deny, write, lock', () async {
    await rpc('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': {},
      'clientInfo': {'name': 'claude-code', 'version': '2.1'},
    });
    helper.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );

    // First use pairs: the user allows "claude-code".
    final listing = tool('list_items', {'query': 'stripe'});
    final pair = await answer(AgentDecision.allowOnce);
    expect(pair, isA<PairPrompt>());
    expect(pair.client, 'claude-code');
    final (listError, listText) = await listing;
    expect(listError, isFalse);
    expect(listText, isNot(contains('sk_live_sample')));
    final items = (jsonDecode(listText)['items'] as List).cast<Map>();
    final stripe = items.single['id'] as String;

    // Reveal, allowed once.
    final reveal = tool('get_secret', {
      'item_id': stripe,
      'reason': 'Check the webhook signature',
    });
    final asked = await answer(AgentDecision.allowOnce) as SecretPrompt;
    expect(asked.reason, 'Check the webhook signature');
    final (revealError, revealText) = await reveal;
    expect(revealError, isFalse);
    expect(jsonDecode(revealText)['fields'], {'value': 'sk_live_sample'});

    // Denied: the agent is told, and nothing is written.
    final envPath = '${home.path}/.env';
    final denied = tool('write_env_file', {
      'path': envPath,
      'env': {'STRIPE_KEY': '$stripe#value'},
      'reason': 'Local dev',
    });
    await answer(AgentDecision.deny);
    final (deniedError, deniedText) = await denied;
    expect(deniedError, isTrue);
    expect(deniedText, contains('denied'));
    expect(File(envPath).existsSync(), isFalse);

    // Allowed: written 0600, and the value never comes back.
    final written = tool('write_env_file', {
      'path': envPath,
      'env': {'STRIPE_KEY': '$stripe#value'},
      'reason': 'Local dev',
    });
    await answer(AgentDecision.allowOnce);
    final (writeError, writeText) = await written;
    expect(writeError, isFalse);
    expect(writeText, isNot(contains('sk_live_sample')));
    expect(File(envPath).readAsStringSync(), 'STRIPE_KEY=sk_live_sample\n');
    expect(File(envPath).statSync().mode & 0x1ff, 0x180);

    // Locked: status says so.
    c.read(vaultSessionProvider.notifier).lock();
    final (_, statusText) = await tool('vault_status', {});
    expect(jsonDecode(statusText)['vault'], 'locked');

    // The activity list kept what happened, and no value.
    final log = c.read(agentBridgeProvider).activity;
    expect(log.map((a) => a.outcome), contains('Denied'));
    for (final entry in log) {
      expect(
        '${entry.action}${entry.detail}${entry.outcome}',
        isNot(contains('sk_live_sample')),
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
