@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:agent_bridge/agent_bridge.dart';
import 'package:test/test.dart';

const _client = ClientInfo(name: 'test-agent', version: '1.0');
const _token = 'the-token';

Matcher _fails(BridgeError code) =>
    throwsA(isA<BridgeException>().having((e) => e.code, 'code', code));

void main() {
  late Directory dir;
  late String path;
  late BridgeServer server;
  final calls = <String>[];
  Completer<void>? gate;

  /// A minimal app: `hello` pairs with [_token], `pair` always succeeds.
  Future<Map<String, Object?>> handler(BridgeCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'hello':
        call.session.paired = call.params['token'] == _token;
        return {
          'protocol': protocolVersion,
          'app_version': '0.1.0',
          'paired': call.session.paired,
          'state': 'unlocked',
        };
      case 'pair':
        call.session.paired = true;
        return {'token': _token};
      case 'status':
        return {'state': 'locked'};
      case 'wait':
        await gate!.future;
        return {};
      case 'secret_crash':
        throw StateError('contains sk_live_SECRET');
      default:
        throw const BridgeException(BridgeError.badRequest, 'unknown method');
    }
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('ab');
    path = '${dir.path}/dv.sock';
    calls.clear();
    server = (await BridgeServer.bind(path, handler))!;
  });

  tearDown(() async {
    await server.close();
    dir.deleteSync(recursive: true);
  });

  test('hello first; unpaired sessions get only hello, pair, status', () async {
    final client = await BridgeClient.connect(path);
    await expectLater(client.status(), _fails(BridgeError.badRequest));
    final hello = await client.hello(_client);
    expect(hello.paired, isFalse);
    expect(hello.state, VaultState.unlocked);
    expect(await client.status(), VaultState.locked);
    await expectLater(client.list(), _fails(BridgeError.notPaired));
    expect(await client.pair(_client), _token);
    await expectLater(
      client.list(),
      _fails(BridgeError.badRequest),
    ); // reaches handler
    await client.close();
  });

  test('a valid token in hello pairs the session', () async {
    final client = await BridgeClient.connect(path);
    expect((await client.hello(_client, token: _token)).paired, isTrue);
    expect(server.sessions.single.client!.name, 'test-agent');
    expect(server.sessions.single.paired, isTrue);
    await client.close();
  });

  test('a protocol it does not speak fails', () async {
    final client = await BridgeClient.connect(path);
    await expectLater(
      client.call('hello', {'protocol': 99, 'client': _client.toJson()}),
      _fails(BridgeError.unsupportedProtocol),
    );
    await client.close();
  });

  test('handler crashes become internal, without their message', () async {
    final client = await BridgeClient.connect(path);
    await client.hello(_client, token: _token);
    try {
      await client.call('secret_crash');
      fail('should throw');
    } on BridgeException catch (e) {
      expect(e.code, BridgeError.internal);
      expect(e.message, isNot(contains('SECRET')));
    }
    await client.close();
  });

  test('more than 8 waiting requests are busy', () async {
    gate = Completer();
    final client = await BridgeClient.connect(path);
    await client.hello(_client, token: _token);
    final waiting = [for (var i = 0; i < 8; i++) client.call('wait')];
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await expectLater(client.call('wait'), _fails(BridgeError.busy));
    gate!.complete();
    await Future.wait(waiting);
    await client.close();
  });

  test('closing the client completes session.closed', () async {
    final client = await BridgeClient.connect(path);
    await client.hello(_client);
    final session = server.sessions.single;
    await client.close();
    await session.closed.timeout(const Duration(seconds: 2));
    expect(session.isClosed, isTrue);
  });

  test('closing the session fails the requests still waiting', () async {
    gate = Completer();
    final client = await BridgeClient.connect(path);
    await client.hello(_client, token: _token);
    final waiting = client.call('wait');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    server.sessions.single.close();
    expect(waiting, _fails(BridgeError.internal));
    await client.done.timeout(const Duration(seconds: 2));
    gate!.complete();
  });

  test('a second server finds the live one and stands down', () async {
    expect(await BridgeServer.bind(path, handler), isNull);
  });

  test('a stale socket file is replaced', () async {
    await server.close();
    // Leave a socket file behind with nothing listening, as a crash does.
    final stale = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    await stale.close();
    if (!File(path).existsSync()) {
      File(path).writeAsStringSync('');
    }
    server = (await BridgeServer.bind(path, handler))!;
    final client = await BridgeClient.connect(path);
    expect((await client.hello(_client)).paired, isFalse);
    await client.close();
  });

  test('close removes the socket file', () async {
    await server.close();
    expect(File(path).existsSync(), isFalse);
    server = (await BridgeServer.bind(path, handler))!;
  });

  test('connect fails when nothing listens', () async {
    await server.close();
    await expectLater(
      BridgeClient.connect(path),
      throwsA(isA<SocketException>()),
    );
    server = (await BridgeServer.bind(path, handler))!;
  });
}
