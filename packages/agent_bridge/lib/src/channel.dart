import 'dart:async';
import 'dart:io';

import 'windows_pipe.dart';

/// One connection between the helper and the app: bytes each way. A Unix
/// domain socket on macOS and Linux, a named pipe on Windows (PROTOCOL.md
/// §1); the protocol above it is the same.
abstract interface class BridgeChannel {
  /// What the other end sends.
  Stream<List<int>> get input;

  void add(List<int> bytes);

  /// Ends the connection at once.
  void destroy();

  /// Completes when the connection has ended, from either side.
  Future<void> get done;
}

/// The app's end: connections as they come in.
abstract interface class BridgeListener {
  Stream<BridgeChannel> get connections;

  /// Stops accepting, and removes the socket file where there is one.
  Future<void> close();
}

/// Whether [endpoint] names a Windows named pipe (`\\.\pipe\…`) rather
/// than a socket file.
bool isPipeEndpoint(String endpoint) => endpoint.startsWith(r'\\.\pipe\');

/// Connects to the app at [endpoint]. Throws when nothing serves it.
Future<BridgeChannel> connectChannel(String endpoint, Duration timeout) async {
  if (isPipeEndpoint(endpoint)) return connectPipe(endpoint, timeout);
  final socket = await Socket.connect(
    InternetAddress(endpoint, type: InternetAddressType.unix),
    0,
  ).timeout(timeout);
  return SocketChannel(socket);
}

/// Serves [endpoint], or returns null when another live process does.
Future<BridgeListener?> listenChannel(String endpoint) async {
  if (isPipeEndpoint(endpoint)) return bindPipe(endpoint);
  return _SocketListener.bind(endpoint);
}

/// A [BridgeChannel] over a `dart:io` socket.
class SocketChannel implements BridgeChannel {
  SocketChannel(this._socket);

  final Socket _socket;

  @override
  Stream<List<int>> get input => _socket;

  @override
  void add(List<int> bytes) => _socket.add(bytes);

  @override
  void destroy() => _socket.destroy();

  @override
  Future<void> get done => _socket.done.catchError((Object _) {});
}

class _SocketListener implements BridgeListener {
  _SocketListener(this._path, this._server);

  /// Binds [path]. A stale socket left by a crash is removed first; one
  /// that answers belongs to another live process, so this returns null.
  static Future<_SocketListener?> bind(String path) async {
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
    return _SocketListener(path, await ServerSocket.bind(address, 0));
  }

  final String _path;
  final ServerSocket _server;

  @override
  Stream<BridgeChannel> get connections => _server.map(SocketChannel.new);

  @override
  Future<void> close() async {
    await _server.close();
    try {
      File(_path).deleteSync();
    } on FileSystemException {
      // Already gone.
    }
  }
}
