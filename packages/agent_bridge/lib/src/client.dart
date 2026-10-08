import 'dart:async';
import 'dart:io';

import 'framing.dart';
import 'messages.dart';
import 'protocol.dart';

/// What `hello` returned.
class HelloResult {
  const HelloResult({
    required this.protocol,
    required this.appVersion,
    required this.paired,
    required this.state,
  });

  final int protocol;
  final String appVersion;
  final bool paired;
  final VaultState state;
}

/// The helper side of the bridge: one connection to the app.
class BridgeClient {
  BridgeClient._(this._socket) {
    decodeLines(_socket).listen(
      _onMessage,
      onError: (Object _) => _socket.destroy(),
      onDone: _fail,
      cancelOnError: true,
    );
    _socket.done.catchError((Object _) {}).whenComplete(_fail);
  }

  /// Connects to the app's socket at [path]. Throws [SocketException]
  /// when nothing listens there (the app isn't running, or AI agents are
  /// switched off).
  static Future<BridgeClient> connect(
    String path, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    ).timeout(timeout);
    return BridgeClient._(socket);
  }

  final Socket _socket;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final _done = Completer<void>();
  var _nextId = 1;

  /// Completes when the app closes the connection.
  Future<void> get done => _done.future;
  bool get isClosed => _done.isCompleted;

  /// Sends a request and waits for its result. Fails with the app's
  /// [BridgeException], or `internal` if the connection drops first.
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    if (isClosed) {
      return Future.error(_closedError);
    }
    final id = _nextId++;
    final completer = _pending[id] = Completer();
    _socket.add(encodeLine({'id': id, 'method': method, 'params': params}));
    return completer.future;
  }

  Future<HelloResult> hello(ClientInfo client, {String? token}) async {
    final r = await call('hello', {
      'protocol': protocolVersion,
      'client': client.toJson(),
      'token': ?token,
    });
    return HelloResult(
      protocol: r['protocol'] as int,
      appVersion: r['app_version'] as String? ?? '',
      paired: r['paired'] == true,
      state: VaultState.parse(r['state']),
    );
  }

  /// Asks the user to pair this client; returns the new token.
  Future<String> pair(ClientInfo client) async {
    final r = await call('pair', {'client': client.toJson()});
    final token = r['token'];
    if (token is! String) {
      throw const BridgeException(BridgeError.internal, 'no token');
    }
    return token;
  }

  Future<VaultState> status() async =>
      VaultState.parse((await call('status'))['state']);

  Future<List<Map<String, Object?>>> list({
    String? query,
    String? app,
    String? platform,
    String? environment,
    String? type,
    String? tag,
  }) async {
    final r = await call('list', {
      'query': ?query,
      'app': ?app,
      'platform': ?platform,
      'environment': ?environment,
      'type': ?type,
      'tag': ?tag,
    });
    return (r['items'] as List).cast<Map<String, Object?>>();
  }

  Future<Map<String, Object?>> get(String id) async =>
      (await call('get', {'id': id}))['item'] as Map<String, Object?>;

  Future<SecretResult> requestSecret(SecretRequest request) async =>
      SecretResult.fromJson(await call('request_secret', request.toJson()));

  Future<void> close() async {
    _socket.destroy();
    await done;
  }

  void _onMessage(Map<String, Object?> message) {
    final id = message['id'];
    final completer = id is int ? _pending.remove(id) : null;
    if (completer == null) return;
    final error = message['error'];
    if (error != null) {
      completer.completeError(BridgeException.fromJson(error));
      return;
    }
    final result = message['result'];
    completer.complete(
      result is Map<String, Object?> ? result : <String, Object?>{},
    );
  }

  void _fail() {
    for (final completer in _pending.values) {
      completer.completeError(_closedError);
    }
    _pending.clear();
    if (!_done.isCompleted) _done.complete();
  }

  static const _closedError = BridgeException(
    BridgeError.internal,
    'DevVault closed the connection',
  );
}
