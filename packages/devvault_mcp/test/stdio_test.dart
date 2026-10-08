@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'fake_app.dart';

/// Drives `bin/devvault_mcp.dart` the way an MCP client does: JSON-RPC
/// over stdin/stdout.
void main() {
  late FakeApp app;
  late Directory home;
  late Process process;
  late StreamIterator<String> lines;
  var nextId = 1;

  setUp(() async {
    app = await FakeApp.start();
    home = Directory.systemTemp.createTempSync('dvhome');
    process = await Process.start(
      Platform.resolvedExecutable,
      [
        'run',
        'bin/devvault_mcp.dart',
        '--socket',
        app.socketPath,
        '--no-launch',
      ],
      environment: {'HOME': home.path},
    );
    lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
  });

  tearDown(() async {
    process.kill();
    await process.exitCode;
    await app.stop();
    home.deleteSync(recursive: true);
  });

  Future<Map<String, Object?>> call(String method, [Map? params]) async {
    final id = nextId++;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    while (await lines.moveNext().timeout(const Duration(seconds: 60))) {
      final message = jsonDecode(lines.current) as Map<String, Object?>;
      if (message['id'] == id) return message;
    }
    fail('devvault-mcp closed stdout');
  }

  test('initialize, list the tools, call one', () async {
    final init = await call('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': {},
      'clientInfo': {'name': 'claude-code', 'version': '2.1'},
    });
    final server = (init['result'] as Map)['serverInfo'] as Map;
    expect(server['name'], 'devvault');
    process.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );

    final tools = await call('tools/list');
    final names = [
      for (final t in (tools['result'] as Map)['tools'] as List) t['name'],
    ];
    expect(names, [
      'vault_status',
      'list_items',
      'get_item',
      'get_secret',
      'write_secret_file',
      'write_env_file',
      'run_with_secrets',
    ]);

    final listed = await call('tools/call', {
      'name': 'list_items',
      'arguments': {'query': 'stripe'},
    });
    final result = listed['result'] as Map;
    expect(result['isError'], isNot(true));
    final text = ((result['content'] as List).single as Map)['text'] as String;
    expect(jsonDecode(text)['count'], 1);
    // Paired under the name the MCP client gave.
    expect(app.pairs, 1);
    final tokens = File('${home.path}/.config/devvault/agent-tokens.json');
    expect(jsonDecode(tokens.readAsStringSync()), {'claude-code': 'token-1'});

    final secret = await call('tools/call', {
      'name': 'get_secret',
      'arguments': {'item_id': itemId},
    });
    // reason is required by the schema.
    expect((secret['result'] as Map)['isError'], isTrue);
    expect(app.requests, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
