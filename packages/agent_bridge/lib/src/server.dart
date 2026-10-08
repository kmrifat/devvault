import 'dart:async';
import 'dart:io';

import 'framing.dart';
import 'protocol.dart';

/// One connection, as the app sees it. The app's handler sets [paired].
class BridgeSession {
  BridgeSession._(this.id);

  /// Unique for this server, for the app's bookkeeping.
  final int id;

  /// Set by a successful `hello`.
  ClientInfo? client;

  /// Set by the handler once `hello` carried a valid token or `pair` was
  /// approved. Until then only `hello`, `pair` and `status` are allowed.
  bool paired = false;

  /// The hash of the token this session proved, so a revoke can find it.
  String? tokenHash;

  bool _greeted = false;
  final _closed = Completer<void>();
  void Function()? _drop;

  /// Completes when the connection ends; waiting requests should give up.
  Future<void> get closed => _closed.future;
  bool get isClosed => _closed.isCompleted;

  /// Drops the connection, e.g. after its token was revoked.
  void close() => _drop?.call();

  @override
  String toString() => 'BridgeSession($id, ${client?.name})';
}

/// A request that passed the session rules, for the app to answer.
class BridgeCall {
  BridgeCall(this.session, this.method, this.params);

  final BridgeSession session;
  final String method;
  final Map<String, Object?> params;

  @override
  String toString() => 'BridgeCall($method)';
}

/// Answers a call with a result, or throws a [BridgeException]. Any other
/// exception becomes `internal`, without its message: it might hold data.
typedef BridgeHandler = Future<Map<String, Object?>> Function(BridgeCall call);

/// The app side of the bridge: owns the socket and the session rules
/// (PROTOCOL.md §1–3) and passes every valid call to a [BridgeHandler].
class BridgeServer {
  BridgeServer._(this.path, this._socket, this._handler) {
    _socket.listen(_serve);
  }

  /// Binds [path], or returns null when another live process serves it.
  /// A stale socket left by a crash is removed first.
  static Future<BridgeServer?> bind(String path, BridgeHandler handler) async {
    final address = InternetAddress(path, type: InternetAddressType.unix);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      try {
        final probe = await Socket.connect(
          address,
          0,
        ).timeout(const Duration(seconds: 1));
        probe.destroy();
        return null;
      } on Object {
        File(path).deleteSync();
      }
    }
    Directory(File(path).parent.path).createSync(recursive: true);
    final socket = await ServerSocket.bind(address, 0);
    return BridgeServer._(path, socket, handler);
  }

  final String path;
  final ServerSocket _socket;
  final BridgeHandler _handler;
  final Set<BridgeSession> _sessions = {};
  var _nextId = 1;

  /// Open connections.
  Iterable<BridgeSession> get sessions => _sessions;

  /// Closes the socket and every connection, and removes the socket file.
  Future<void> close() async {
    await _socket.close();
    for (final session in _sessions.toList()) {
      session.close();
    }
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // Already gone.
    }
  }

  void _serve(Socket socket) {
    final session = BridgeSession._(_nextId++);
    _sessions.add(session);
    var pending = 0;
    session._drop = socket.destroy;

    void send(Map<String, Object?> message) {
      if (session.isClosed) return;
      try {
        socket.add(encodeLine(message));
      } on StateError {
        // Closed while the answer was on its way.
      }
    }

    Future<void> answer(Object? id, Object? method, Object? params) async {
      try {
        if (id is! int || method is! String) {
          throw const BridgeException(BridgeError.badRequest, 'id, method');
        }
        if (params != null && params is! Map<String, Object?>) {
          throw const BridgeException(BridgeError.badRequest, 'params');
        }
        final args = (params as Map<String, Object?>?) ?? const {};
        if (!session._greeted && method != 'hello') {
          throw const BridgeException(BridgeError.badRequest, 'hello first');
        }
        if (!session.paired && !unpairedMethods.contains(method)) {
          throw const BridgeException(BridgeError.notPaired);
        }
        if (method == 'hello') _greet(session, args);
        if (pending >= maxPendingPerConnection) {
          throw const BridgeException(BridgeError.busy);
        }
        pending++;
        try {
          final result = await _handler(BridgeCall(session, method, args));
          if (method == 'hello') session._greeted = true;
          send({'id': id, 'result': result});
        } finally {
          pending--;
        }
      } on BridgeException catch (e) {
        send({'id': id is int ? id : null, 'error': e.toJson()});
      } on Object {
        send({
          'id': id is int ? id : null,
          'error': const BridgeException(BridgeError.internal).toJson(),
        });
      }
    }

    decodeLines(socket).listen(
      (message) => answer(message['id'], message['method'], message['params']),
      onError: (Object _) => socket.destroy(),
      onDone: socket.destroy,
      cancelOnError: true,
    );
    socket.done.catchError((Object _) {}).whenComplete(() {
      _sessions.remove(session);
      if (!session._closed.isCompleted) session._closed.complete();
    });
  }

  static void _greet(BridgeSession session, Map<String, Object?> params) {
    if (params['protocol'] != protocolVersion) {
      throw BridgeException(
        BridgeError.unsupportedProtocol,
        'this DevVault speaks protocol $protocolVersion',
      );
    }
    session.client = ClientInfo.fromJson(params['client']);
  }
}
