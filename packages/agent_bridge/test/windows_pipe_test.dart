@TestOn('windows')
library;

import 'dart:io';
import 'dart:math';

import 'package:agent_bridge/agent_bridge.dart';
import 'package:test/test.dart';

const _client = ClientInfo(name: 'test-agent', version: '1.0');

/// The bridge over a Windows named pipe (P5-11): the same sessions as over
/// a Unix socket, one server per name, nothing for a missing pipe.
void main() {
  late String name;
  late BridgeServer server;

  Future<Map<String, Object?>> handler(BridgeCall call) async {
    switch (call.method) {
      case 'hello':
        call.session.paired = true;
        return {
          'protocol': protocolVersion,
          'app_version': '0.1.0',
          'paired': true,
          'state': 'unlocked',
        };
      case 'echo':
        return call.params;
      default:
        throw const BridgeException(BridgeError.badRequest, 'unknown method');
    }
  }

  setUp(() async {
    name =
        '${pipeNameForCurrentUser()}-test-$pid-'
        '${Random().nextInt(1 << 30)}';
    server = (await BridgeServer.bind(name, handler))!;
  });

  tearDown(() => server.close());

  test('the pipe is named for the current user', () {
    expect(currentUserSid(), startsWith('S-1-'));
    expect(pipeNameForCurrentUser(), endsWith(currentUserSid()));
    expect(isPipeEndpoint(name), isTrue);
  });

  test('a session works as over a socket, large messages too', () async {
    final client = await BridgeClient.connect(name);
    addTearDown(client.close);
    final hello = await client.hello(_client);
    expect(hello.paired, isTrue);
    expect(hello.appVersion, '0.1.0');

    // Larger than the pipe's 64 KiB buffer, both ways.
    final big = 'x' * (1 << 20);
    final echoed = await client.call('echo', {'data': big});
    expect(echoed['data'], big);
  });

  test('several clients at once each get their own instance', () async {
    final clients = [
      for (var i = 0; i < 3; i++) await BridgeClient.connect(name),
    ];
    for (final client in clients) {
      addTearDown(client.close);
      expect((await client.hello(_client)).paired, isTrue);
    }
    expect(server.sessions, hasLength(3));
  });

  test('one server per name: a second one stands down', () async {
    expect(await BridgeServer.bind(name, handler), isNull);
  });

  test('closing the server ends its sessions', () async {
    final client = await BridgeClient.connect(name);
    await client.hello(_client);
    await server.close();
    await client.done.timeout(const Duration(seconds: 5));
    expect(client.isClosed, isTrue);
    // A fresh server for tearDown.
    server = (await BridgeServer.bind(name, handler))!;
  });

  test('nothing serves a missing pipe', () async {
    await expectLater(
      BridgeClient.connect('$name-missing'),
      throwsA(isA<PipeException>()),
    );
  });
}
