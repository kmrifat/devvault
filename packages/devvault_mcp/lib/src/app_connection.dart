import 'dart:async';
import 'dart:io';

import 'package:agent_bridge/agent_bridge.dart';

import 'token_store.dart';

/// DevVault isn't reachable: not running, or AI agents are off.
class AppUnavailable implements Exception {
  const AppUnavailable();

  @override
  String toString() =>
      "DevVault isn't running, or AI agents are off. Open DevVault, turn on "
      'Settings › AI Agents › Allow AI agents, and try again.';
}

/// The helper's connection to the DevVault app: connects on first use
/// (starting the app if it isn't running), introduces itself, pairs when
/// it has no token yet, and reconnects after the app restarts.
class AppConnection {
  AppConnection({
    required this.socketPath,
    required this.tokens,
    required this.client,
    this.launchApp,
    this.launchWait = const Duration(seconds: 30),
  });

  final String socketPath;
  final TokenStore tokens;

  /// Who this helper speaks for; read when connecting, because the MCP
  /// client only names itself in `initialize`.
  final ClientInfo Function() client;

  /// Starts DevVault; null to never start it.
  final Future<void> Function()? launchApp;
  final Duration launchWait;

  BridgeClient? _bridge;
  bool _paired = false;
  Future<BridgeClient>? _connecting;

  /// Runs [action] on a paired connection. A token DevVault no longer
  /// knows (revoked) is forgotten and pairing starts over, once.
  Future<T> paired<T>(Future<T> Function(BridgeClient bridge) action) async {
    for (var attempt = 0; ; attempt++) {
      final bridge = await _connect();
      try {
        if (!_paired) await _pair(bridge);
        return await action(bridge);
      } on BridgeException catch (e) {
        if (e.code != BridgeError.notPaired || attempt > 0) rethrow;
        _paired = false;
        await tokens.forget(client().name);
      }
    }
  }

  /// The app's state without pairing: `hello` only.
  Future<({VaultState state, bool paired})> status() async {
    final bridge = await _connect();
    final state = await bridge.status();
    return (state: state, paired: _paired);
  }

  Future<void> close() async {
    await _bridge?.close();
    _bridge = null;
  }

  Future<void> _pair(BridgeClient bridge) async {
    final name = client().name;
    final token = await bridge.pair(client());
    await tokens.save(name, token);
    _paired = true;
  }

  Future<BridgeClient> _connect() {
    final open = _bridge;
    if (open != null && !open.isClosed) return Future.value(open);
    return _connecting ??= _open().whenComplete(() => _connecting = null);
  }

  Future<BridgeClient> _open() async {
    final socket = await _reach();
    final info = client();
    final hello = await socket.hello(info, token: tokens.tokenFor(info.name));
    _paired = hello.paired;
    _bridge = socket;
    return socket;
  }

  /// Connects, starting DevVault and waiting for its socket if needed.
  Future<BridgeClient> _reach() async {
    try {
      return await BridgeClient.connect(socketPath);
    } on Object {
      final launch = launchApp;
      if (launch == null) throw const AppUnavailable();
      await launch();
    }
    final deadline = DateTime.now().add(launchWait);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        return await BridgeClient.connect(socketPath);
      } on Object {
        // Not up yet.
      }
    }
    throw const AppUnavailable();
  }
}

/// Starts DevVault on macOS (`open -b`), in the background.
Future<void> launchDevVault() async {
  if (!Platform.isMacOS) return;
  await Process.run('open', ['-g', '-b', appBundleId]);
}
