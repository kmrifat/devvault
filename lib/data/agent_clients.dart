import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// An AI agent client the user allowed to connect (P5-04). Only the hash
/// of its token is kept: the token itself lives with the helper, in
/// `~/.config/devvault/agent-token`.
@immutable
class PairedClient {
  const PairedClient({
    required this.tokenHash,
    required this.name,
    required this.pairedAt,
    this.lastSeen,
  });

  /// Lowercase hex SHA-256 of the token; also the client's identity here.
  final String tokenHash;

  /// What the client called itself when it paired, e.g. `claude-code`.
  final String name;
  final DateTime pairedAt;
  final DateTime? lastSeen;

  PairedClient seenAt(DateTime time) => PairedClient(
    tokenHash: tokenHash,
    name: name,
    pairedAt: pairedAt,
    lastSeen: time,
  );

  Map<String, Object?> toJson() => {
    'token_sha256': tokenHash,
    'name': name,
    'paired_at': pairedAt.toUtc().toIso8601String(),
    if (lastSeen != null) 'last_seen': lastSeen!.toUtc().toIso8601String(),
  };

  static PairedClient? fromJson(Object? json) {
    if (json is! Map) return null;
    final hash = json['token_sha256'], name = json['name'];
    final paired = DateTime.tryParse('${json['paired_at']}');
    if (hash is! String || name is! String || paired == null) return null;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return null;
    return PairedClient(
      tokenHash: hash,
      name: name,
      pairedAt: paired,
      lastSeen: DateTime.tryParse('${json['last_seen']}'),
    );
  }

  @override
  String toString() => 'PairedClient($name)';
}

/// The paired clients on disk: `<app support>/agent_clients.json`. Not a
/// secret (hashes of random tokens), not synced: pairing is per device.
class AgentClientsFile {
  const AgentClientsFile(this.supportDir);

  final Directory supportDir;

  File get _file => File('${supportDir.path}/agent_clients.json');

  /// The saved clients; none when the file is missing or unreadable.
  List<PairedClient> load() {
    try {
      if (!_file.existsSync()) return const [];
      final json = jsonDecode(_file.readAsStringSync());
      if (json is! Map || json['clients'] is! List) return const [];
      return [
        for (final entry in json['clients'] as List)
          ?PairedClient.fromJson(entry),
      ];
    } on Object {
      return const [];
    }
  }

  /// Writes atomically (temp file, then rename).
  Future<void> save(List<PairedClient> clients) async {
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'clients': [for (final c in clients) c.toJson()],
      }),
      flush: true,
    );
    await temp.rename(_file.path);
  }
}
