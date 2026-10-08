@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_bridge/agent_bridge.dart';
import 'package:devvault_mcp/devvault_mcp.dart';
import 'package:test/test.dart';

import 'fake_app.dart';

void main() {
  late FakeApp app;
  late Directory home;
  late TokenStore tokens;
  final connections = <AppConnection>[];

  setUp(() async {
    app = await FakeApp.start();
    home = Directory.systemTemp.createTempSync('dvhome');
    tokens = TokenStore.inHome(home.path);
  });

  tearDown(() async {
    for (final c in connections) {
      await c.close();
    }
    connections.clear();
    await app.stop();
    home.deleteSync(recursive: true);
  });

  DevVaultTools tools({String? socket, Future<void> Function()? launch}) {
    final connection = AppConnection(
      socketPath: socket ?? app.socketPath,
      tokens: tokens,
      client: () => const ClientInfo(name: 'claude-code'),
      launchApp: launch,
      launchWait: const Duration(seconds: 1),
    );
    connections.add(connection);
    return DevVaultTools(connection);
  }

  Map<String, Object?> json(ToolOutput out) {
    expect(out.isError, isFalse, reason: out.text);
    return jsonDecode(out.text) as Map<String, Object?>;
  }

  test('pairs once, keeps the token 0600, and reuses it', () async {
    final out = json(await tools().listItems({'query': 'stripe'}));
    expect(out['count'], 1);
    expect(app.pairs, 1);
    expect(tokens.tokenFor('claude-code'), 'token-1');
    final file = File('${home.path}/.config/devvault/agent-tokens.json');
    expect(file.statSync().mode & 0x1ff, 0x180);
    expect(file.parent.statSync().mode & 0x1ff, 0x1c0);

    json(await tools().listItems({}));
    expect(app.pairs, 1);
  });

  test('a revoked token is forgotten and pairing starts over', () async {
    await tokens.save('claude-code', 'revoked');
    json(await tools().listItems({}));
    expect(app.pairs, 1);
    expect(tokens.tokenFor('claude-code'), 'token-1');
  });

  test('vault_status needs no pairing', () async {
    final out = json(await tools().vaultStatus({}));
    expect(out, {'app': 'running', 'vault': 'locked', 'paired': false});
    expect(app.pairs, 0);
  });

  test('without the app: a clear error, after trying to start it', () async {
    var launched = 0;
    final t = tools(
      socket: '${home.path}/missing.sock',
      launch: () async => launched++,
    );
    final out = await t.listItems({});
    expect(out.isError, isTrue);
    expect(out.text, contains('Settings › AI Agents'));
    expect(launched, 1);
    final status = json(await t.vaultStatus({}));
    expect(status['app'], 'unavailable');
  });

  test('get_secret returns values, text attachments as text', () async {
    final out = json(
      await tools().getSecret({
        'item_id': itemId,
        'fields': ['value'],
        'attachment_ids': [blobId, 'text-blob'],
        'reason': 'Configure the webhook',
      }),
    );
    expect(out['fields'], {'value': stripeKey});
    final attachments = (out['attachments'] as List).cast<Map>();
    expect(attachments[0], isNot(contains('text')));
    expect(attachments[0]['note'], contains('write_secret_file'));
    expect(attachments[1]['text'], 'hello');
    final request = app.requests.single;
    expect(request.delivery.mode, DeliveryMode.reveal);
    expect(request.reason, 'Configure the webhook');
  });

  test('write_secret_file writes 0600 and never returns the value', () async {
    final path = '${home.path}/key.txt';
    final out = await tools().writeSecretFile({
      'item_id': itemId,
      'field': 'value',
      'path': path,
      'reason': 'CI needs the key',
    });
    expect(out.text, isNot(contains(stripeKey)));
    expect(json(out)['bytes'], stripeKey.length);
    expect(File(path).readAsStringSync(), stripeKey);
    expect(File(path).statSync().mode & 0x1ff, 0x180);
    expect(app.requests.single.delivery.target, path);

    final again = await tools().writeSecretFile({
      'item_id': itemId,
      'field': 'value',
      'path': path,
      'reason': 'again',
    });
    expect(again.isError, isTrue);
    expect(again.text, contains('overwrite'));
    expect(app.requests, hasLength(1)); // refused before asking
  });

  test('write_secret_file writes an attachment byte for byte', () async {
    final path = '${home.path}/upload.jks';
    json(
      await tools().writeSecretFile({
        'item_id': itemId,
        'attachment_id': blobId,
        'path': path,
        'reason': 'Sign the build',
      }),
    );
    expect(File(path).readAsBytesSync(), [0, 0xff, 0xfe, 1]);
  });

  test('write_env_file merges and returns names only', () async {
    final path = '${home.path}/.env';
    File(path).writeAsStringSync('PORT=1\n');
    final out = await tools().writeEnvFile({
      'path': path,
      'env': {'STRIPE_KEY': '$itemId#value'},
      'reason': 'Local dev',
    });
    expect(out.text, isNot(contains(stripeKey)));
    expect(json(out)['variables'], ['STRIPE_KEY']);
    expect(File(path).readAsStringSync(), 'PORT=1\nSTRIPE_KEY=$stripeKey\n');
  });

  test('run_with_secrets: one approval, output redacted', () async {
    final out = await tools().runWithSecrets({
      'command': r'echo "$STRIPE_KEY"; printf "%s" "$PEM"',
      'env': {'STRIPE_KEY': '$itemId#value', 'PEM': '$itemId#pem'},
      'reason': 'Smoke-test the key',
    });
    expect(out.text, isNot(contains(stripeKey)));
    expect(out.text, isNot(contains('MIGTAgEAMBMGByqGSM49AgEG')));
    final result = json(out);
    expect(result['exit_code'], 0);
    expect(result['stdout'], contains('[redacted:STRIPE_KEY]'));
    final request = app.requests.single;
    expect(request.items.single.fields, unorderedEquals(['value', 'pem']));
    expect(request.delivery.mode, DeliveryMode.command);
  });

  test('bad env refs are refused before asking', () async {
    for (final env in [
      {'1BAD': '$itemId#value'},
      {'OK': 'no-hash'},
      {'OK': '#value'},
    ]) {
      final out = await tools().runWithSecrets({
        'command': 'true',
        'env': env,
        'reason': 'x',
      });
      expect(out.isError, isTrue, reason: '$env');
    }
    expect(app.requests, isEmpty);
  });

  test('denied and timed out read as advice, not stack traces', () async {
    app.decision = BridgeError.denied;
    var out = await tools().getSecret({'item_id': itemId, 'reason': 'x'});
    expect(out.isError, isTrue);
    expect(out.text, contains('denied'));
    app.decision = BridgeError.timeout;
    out = await tools().getSecret({'item_id': itemId, 'reason': 'x'});
    expect(out.text, contains('2 minutes'));
    out = await tools().getItem({'id': 'nope'});
    expect(out.text, 'Not in the vault: nope.');
  });
}
