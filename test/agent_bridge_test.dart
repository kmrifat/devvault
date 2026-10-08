@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_bridge/agent_bridge.dart';
import 'package:devvault/data/agent_bridge.dart';
import 'package:devvault/data/agent_clients.dart';
import 'package:devvault/data/app_settings.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_overrides.dart';

const _agent = ClientInfo(name: 'claude-code', version: '2.1');

Matcher _fails(BridgeError code) =>
    throwsA(isA<BridgeException>().having((e) => e.code, 'code', code));

void main() {
  setUpAll(loadTestCrypto);

  late Directory supportDir;
  late String socketPath;
  late ProviderContainer c;
  final clients = <BridgeClient>[];

  AgentBridgeState bridge() => c.read(agentBridgeProvider);

  Future<void> start({
    TestVault vault = TestVault.sample,
    bool unlock = true,
    AppSettings settings = const AppSettings(agentsEnabled: true),
    Duration timeout = const Duration(seconds: 10),
  }) async {
    supportDir = await testSupportDir(vault);
    final sockets = Directory.systemTemp.createTempSync('ab');
    addTearDown(() => sockets.deleteSync(recursive: true));
    socketPath = '${sockets.path}/dv.sock';
    c = ProviderContainer(
      overrides: [
        ...testOverrides(supportDir: supportDir),
        initialSettingsProvider.overrideWithValue(settings),
        agentSocketPathProvider.overrideWithValue(socketPath),
        agentTimeoutProvider.overrideWithValue(timeout),
      ],
    );
    addTearDown(() async {
      for (final client in clients) {
        await client.close();
      }
      clients.clear();
      c.dispose();
    });
    if (unlock && vault != TestVault.none) {
      await c.read(vaultSessionProvider.notifier).unlock(testPassword);
    }
    c.listen(agentBridgeProvider, (_, _) {});
    if (settings.agentsEnabled) await until(() => bridge().listening);
  }

  Future<BridgeClient> connect() async {
    final client = await BridgeClient.connect(socketPath);
    clients.add(client);
    return client;
  }

  /// Answers the next prompt to appear, and returns it.
  Future<AgentPrompt> answerNext(AgentDecision decision) async {
    await until(() => bridge().prompts.isNotEmpty);
    final prompt = bridge().prompts.first;
    c.read(agentBridgeProvider.notifier).answer(prompt, decision);
    return prompt;
  }

  /// A connected, paired client.
  Future<(BridgeClient, String)> paired() async {
    final client = await connect();
    await client.hello(_agent);
    final token = client.pair(_agent);
    await answerNext(AgentDecision.allowOnce);
    return (client, await token);
  }

  Future<String> itemId(String title, {String? environment}) async {
    final index = (c.read(vaultSessionProvider) as Unlocked).index;
    return index.all
        .firstWhere(
          (i) =>
              i.title == title &&
              (environment == null || i.environment == environment),
        )
        .id;
  }

  group('serving', () {
    test('no socket while AI agents are off; one while on', () async {
      await start(settings: const AppSettings());
      expect(File(socketPath).existsSync(), isFalse);
      c.read(settingsProvider.notifier).setAgentsEnabled(true);
      await until(() => bridge().listening);
      expect(
        (await (await connect()).hello(_agent)).state,
        VaultState.unlocked,
      );
      c.read(settingsProvider.notifier).setAgentsEnabled(false);
      await until(() => !bridge().listening);
      expect(File(socketPath).existsSync(), isFalse);
    });

    test('stands down when another instance serves the socket', () async {
      final other = await BridgeServer.bind(
        '${Directory.systemTemp.createTempSync('ab').path}/dv.sock',
        (_) async => {},
      );
      addTearDown(() => other!.close());
      supportDir = await testSupportDir();
      c = ProviderContainer(
        overrides: [
          ...testOverrides(supportDir: supportDir),
          initialSettingsProvider.overrideWithValue(
            const AppSettings(agentsEnabled: true),
          ),
          agentSocketPathProvider.overrideWithValue(other!.path),
        ],
      );
      addTearDown(c.dispose);
      c.listen(agentBridgeProvider, (_, _) {});
      await until(() => bridge().otherInstance);
      expect(bridge().listening, isFalse);
    });
  });

  group('pairing', () {
    test('unpaired clients get nothing; an approved pair works', () async {
      await start();
      final client = await connect();
      expect((await client.hello(_agent)).paired, isFalse);
      await expectLater(client.list(), _fails(BridgeError.notPaired));
      final token = client.pair(_agent);
      final prompt = await answerNext(AgentDecision.allowOnce);
      expect(prompt, isA<PairPrompt>());
      expect(prompt.client, 'claude-code');
      expect(await token, isNotEmpty);
      expect(await client.list(), isNotEmpty);

      // Saved as a hash, never the token.
      final saved = AgentClientsFile(supportDir).load();
      expect(saved.single.name, 'claude-code');
      expect(saved.single.tokenHash, tokenHash(await token));
      final file = File('${supportDir.path}/agent_clients.json');
      expect(file.readAsStringSync(), isNot(contains(await token)));

      final again = await connect();
      expect((await again.hello(_agent, token: await token)).paired, isTrue);
      expect(bridge().activity.first.action, 'Paired');
    });

    test('a denied pair fails with denied', () async {
      await start();
      final client = await connect();
      await client.hello(_agent);
      final token = client.pair(_agent);
      await answerNext(AgentDecision.deny);
      await expectLater(token, _fails(BridgeError.denied));
      expect(bridge().clients, isEmpty);
    });

    test('revoking drops the connection and the token', () async {
      await start();
      final (client, token) = await paired();
      await c
          .read(agentBridgeProvider.notifier)
          .revoke(bridge().clients.single);
      await client.done.timeout(const Duration(seconds: 2));
      final again = await connect();
      expect((await again.hello(_agent, token: token)).paired, isFalse);
      await expectLater(again.list(), _fails(BridgeError.notPaired));
    });
  });

  group('metadata', () {
    test('lists facts only: no secret values, no notes', () async {
      await start();
      final (client, _) = await paired();
      final items = await client.list();
      expect(items, hasLength(12));
      final text = jsonEncode(items);
      for (final secret in [
        'kitchenly-store-pass',
        'kitchenly-key-pass',
        'AIzaSyD-sample-maps-key',
        'sk_live_sample',
        'Play App Signing',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      final keystore = items.firstWhere((i) => i['title'] == 'Upload keystore');
      expect(keystore['app'], containsPair('name', 'Kitchenly'));
      expect(keystore['expires_at'], '2051-01-14T00:00:00Z');
      expect(keystore['expires_source'], 'file');
      expect(keystore['has_notes'], isTrue);
      final fields = (keystore['fields'] as List).cast<Map>();
      expect(fields.firstWhere((f) => f['name'] == 'alias')['value'], 'upload');
      expect(
        fields.firstWhere((f) => f['name'] == 'store_password'),
        isNot(contains('value')),
      );
      final noExpiry = items.firstWhere((i) => i['title'] == 'Maps API key');
      expect(noExpiry, isNot(contains('expires_at')));
      expect(noExpiry, isNot(contains('expires_source')));
    });

    test('filters by app name, platform, type and query', () async {
      await start();
      final (client, _) = await paired();
      expect(await client.list(app: 'ledgerly'), hasLength(1));
      expect(await client.list(app: 'nope'), isEmpty);
      expect(await client.list(platform: 'ios'), hasLength(3));
      expect(await client.list(type: 'firebase_config'), hasLength(2));
      final found = await client.list(query: '7KQ2M9XH4D');
      expect(found.single['title'], 'APNs auth key');
      // Secret values are not searchable.
      expect(await client.list(query: 'sk_live_sample'), isEmpty);
    });

    test('get: one item, or not_found', () async {
      await start();
      final (client, _) = await paired();
      final id = await itemId('Stripe secret key');
      expect((await client.get(id))['title'], 'Stripe secret key');
      await expectLater(
        client.get('00000000-0000-4000-8000-00000000dead'),
        _fails(BridgeError.notFound),
      );
    });

    test('asks first when metadata without asking is off', () async {
      await start(
        settings: const AppSettings(
          agentsEnabled: true,
          agentMetadataWithoutAsking: false,
        ),
      );
      final (client, _) = await paired();
      final listed = client.list(query: 'stripe');
      final prompt = await answerNext(AgentDecision.allowForAWhile);
      expect((prompt as MetadataPrompt).what, 'items matching "stripe"');
      expect(await listed, hasLength(1));
      // Granted for a while: no second prompt.
      expect(await client.list(), hasLength(12));
      expect(bridge().prompts, isEmpty);
    });

    test('waits for unlock, with a banner, then answers', () async {
      await start(unlock: false);
      final client = await connect();
      expect((await client.hello(_agent)).state, VaultState.locked);
      final token = client.pair(_agent);
      await until(() => bridge().waits.isNotEmpty);
      expect(bridge().waits.single.client, 'claude-code');
      await c.read(vaultSessionProvider.notifier).unlock(testPassword);
      await answerNext(AgentDecision.allowOnce);
      await token;
      expect(bridge().waits, isEmpty);
      expect(await client.list(), hasLength(12));
    });

    test('no vault on this device', () async {
      await start(vault: TestVault.none);
      final client = await connect();
      expect((await client.hello(_agent)).state, VaultState.noVault);
      await expectLater(client.pair(_agent), _fails(BridgeError.noVault));
    });
  });

  group('request_secret', () {
    SecretRequest request(
      String id, {
      List<String>? fields,
      List<String>? attachments,
      bool notes = false,
      Delivery delivery = const Delivery.reveal(),
    }) => SecretRequest(
      reason: 'Sign the release build',
      delivery: delivery,
      items: [
        SecretItemRequest(
          id: id,
          fields: fields,
          attachments: attachments,
          notes: notes,
        ),
      ],
    );

    test('asks, then returns exactly what was approved', () async {
      await start();
      final (client, _) = await paired();
      final id = await itemId('Upload keystore');
      final item = (c.read(vaultSessionProvider) as Unlocked).index.items[id]!;
      final blob = item.attachments.single;
      final result = client.requestSecret(
        request(
          id,
          fields: ['store_password'],
          attachments: [blob.blobId],
          notes: true,
          delivery: const Delivery.file('/tmp/upload.jks'),
        ),
      );
      final prompt = await answerNext(AgentDecision.allowOnce) as SecretPrompt;
      expect(prompt.reason, 'Sign the release build');
      expect(prompt.delivery.target, '/tmp/upload.jks');
      expect(
        prompt.items.single.path,
        'Kitchenly › android › production › Upload keystore',
      );
      expect(prompt.items.single.names, [
        'store_password',
        'kitchenly-upload.jks',
        'Notes',
      ]);
      final values = (await result).items.single;
      expect(values.fields, {'store_password': 'kitchenly-store-pass'});
      expect(values.attachments.single.data, hasLength(2662));
      expect(values.notes, startsWith('Upload key for Play'));

      final logged = bridge().activity.first;
      expect(logged.action, 'Wrote file');
      expect(logged.outcome, 'Allowed once');
      expect(
        '${logged.detail}${logged.outcome}',
        isNot(contains('kitchenly-store-pass')),
      );
    });

    test('naming nothing returns every field', () async {
      await start();
      final (client, _) = await paired();
      final result = client.requestSecret(
        request(await itemId('Stripe secret key')),
      );
      await answerNext(AgentDecision.allowOnce);
      expect((await result).items.single.fields, {'value': 'sk_live_sample'});
    });

    test('once asks again; for a while does not, until lock', () async {
      await start();
      final (client, _) = await paired();
      final id = await itemId('Maps API key');

      var result = client.requestSecret(request(id));
      await answerNext(AgentDecision.allowOnce);
      await result;

      result = client.requestSecret(request(id));
      await answerNext(AgentDecision.allowForAWhile);
      await result;

      expect((await client.requestSecret(request(id))).items.single.fields, {
        'value': 'AIzaSyD-sample-maps-key',
      });
      expect(bridge().activity.first.outcome, 'Allowed earlier');

      c.read(vaultSessionProvider.notifier).lock();
      await c.read(vaultSessionProvider.notifier).unlock(testPassword);
      result = client.requestSecret(request(id));
      await answerNext(AgentDecision.allowOnce);
      await result;
    });

    test('deny fails with denied', () async {
      await start();
      final (client, _) = await paired();
      final result = client.requestSecret(
        request(await itemId('Stripe secret key')),
      );
      await answerNext(AgentDecision.deny);
      await expectLater(result, _fails(BridgeError.denied));
      expect(bridge().activity.first.outcome, 'Denied');
    });

    test('unknown names fail before anyone is asked', () async {
      await start();
      final (client, _) = await paired();
      final id = await itemId('Stripe secret key');
      await expectLater(
        client.requestSecret(request(id, fields: ['nope'])),
        _fails(BridgeError.notFound),
      );
      await expectLater(
        client.requestSecret(request(id, notes: true)),
        _fails(BridgeError.notFound),
      );
      expect(bridge().prompts, isEmpty);
    });

    test('locking closes the open prompt and denies', () async {
      await start();
      final (client, _) = await paired();
      final result = client.requestSecret(
        request(await itemId('Stripe secret key')),
      );
      await until(() => bridge().prompts.isNotEmpty);
      final prompt = bridge().prompts.single;
      c.read(vaultSessionProvider.notifier).lock();
      await expectLater(result, _fails(BridgeError.denied));
      expect(prompt.isClosed, isTrue);
      expect(bridge().prompts, isEmpty);
    });

    test('no answer in time fails with timeout', () async {
      await start(timeout: const Duration(milliseconds: 300));
      final (client, _) = await paired();
      // Pairing used the short timeout too; answered in time above.
      final result = client.requestSecret(
        request(await itemId('Stripe secret key')),
      );
      await expectLater(result, _fails(BridgeError.timeout));
      expect(bridge().prompts, isEmpty);
      expect(bridge().activity.first.outcome, 'No answer');
    });

    test('an agent that hangs up takes its prompt with it', () async {
      await start();
      final (client, _) = await paired();
      final result = expectLater(
        client.requestSecret(request(await itemId('Stripe secret key'))),
        throwsA(isA<BridgeException>()),
      );
      await until(() => bridge().prompts.isNotEmpty);
      await client.close();
      await result;
      await until(() => bridge().prompts.isEmpty);
    });
  });
}

/// Polls [condition] (real time) until it holds, or fails after 5 s.
Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for a condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
