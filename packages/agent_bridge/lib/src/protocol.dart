import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The protocol version this package speaks (PROTOCOL.md).
const int protocolVersion = 1;

/// The app's bundle id; its sandbox container holds the socket.
const String appBundleId = 'com.binarycastle.devvault';

/// A line longer than this closes the connection (PROTOCOL.md §2).
const int maxLineBytes = 48 * 1024 * 1024;

/// How long a request waits for the user before failing with `timeout`.
const Duration userTimeout = Duration(seconds: 120);

/// How many requests may wait for the user on one connection.
const int maxPendingPerConnection = 8;

/// How many items one `request_secret` may name.
const int maxItemsPerRequest = 20;

/// Methods a connection may call before it is paired.
const Set<String> unpairedMethods = {'hello', 'pair', 'status'};

/// The socket as the helper sees it, outside the sandbox.
String socketPathForHome(String home) =>
    '$home/Library/Containers/$appBundleId/Data/tmp/dv.sock';

/// The socket as the sandboxed app sees it: `$HOME` is the container.
String socketPathInContainer(String containerHome) =>
    '$containerHome/tmp/dv.sock';

/// Error codes on the wire (PROTOCOL.md §6).
enum BridgeError {
  badRequest('bad_request'),
  unsupportedProtocol('unsupported_protocol'),
  notPaired('not_paired'),
  disabled('disabled'),
  noVault('no_vault'),
  notFound('not_found'),
  denied('denied'),
  timeout('timeout'),
  busy('busy'),
  internal('internal');

  const BridgeError(this.wireName);

  final String wireName;

  static BridgeError parse(Object? wire) => values.firstWhere(
    (e) => e.wireName == wire,
    orElse: () => BridgeError.internal,
  );
}

/// A protocol error. [message] is for people and must never hold a secret.
class BridgeException implements Exception {
  const BridgeException(this.code, [this.message = '']);

  final BridgeError code;
  final String message;

  Map<String, Object?> toJson() => {'code': code.wireName, 'message': message};

  factory BridgeException.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final message = map['message'];
    return BridgeException(
      BridgeError.parse(map['code']),
      message is String ? message : '',
    );
  }

  @override
  String toString() =>
      'BridgeException(${code.wireName}${message.isEmpty ? '' : ': $message'})';
}

/// The vault state reported by `hello` and `status`.
enum VaultState {
  noVault('no_vault'),
  locked('locked'),
  unlocked('unlocked');

  const VaultState(this.wireName);

  final String wireName;

  static VaultState parse(Object? wire) => values.firstWhere(
    (e) => e.wireName == wire,
    orElse: () =>
        throw const BridgeException(BridgeError.badRequest, 'unknown state'),
  );
}

/// Who is on the other end of a connection, as it introduced itself.
class ClientInfo {
  const ClientInfo({required this.name, this.version = ''});

  final String name;
  final String version;

  Map<String, Object?> toJson() => {'name': name, 'version': version};

  factory ClientInfo.fromJson(Object? json) {
    if (json is! Map || json['name'] is! String) {
      throw const BridgeException(BridgeError.badRequest, 'client.name');
    }
    final name = (json['name'] as String).trim();
    if (name.isEmpty || name.length > 64) {
      throw const BridgeException(BridgeError.badRequest, 'client.name');
    }
    final version = json['version'];
    return ClientInfo(
      name: name,
      version: version is String && version.length <= 32 ? version : '',
    );
  }

  @override
  String toString() => 'ClientInfo($name $version)';
}

/// A new pairing token: 32 random bytes, base64url without padding.
String newPairingToken([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => r.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// What the app stores for a token: lowercase hex SHA-256.
String tokenHash(String token) => sha256.convert(utf8.encode(token)).toString();
