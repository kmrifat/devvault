import 'dart:convert';
import 'dart:io';

import 'secure_file.dart';

/// The pairing tokens this user's agents got from DevVault, one per
/// client name, in `~/.config/devvault/agent-tokens.json` (mode 0600, in
/// a 0700 folder). DevVault keeps only their hashes.
class TokenStore {
  TokenStore(this.file);

  /// The default place, under [home].
  factory TokenStore.inHome(String home) =>
      TokenStore(File('$home/.config/devvault/agent-tokens.json'));

  final File file;

  String? tokenFor(String client) => _read()[client];

  Future<void> save(String client, String token) async {
    final tokens = _read()..[client] = token;
    await _write(tokens);
  }

  Future<void> forget(String client) async {
    final tokens = _read();
    if (tokens.remove(client) != null) await _write(tokens);
  }

  Map<String, String> _read() {
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (key is String && value is String) key: value,
      };
    } on Object {
      return {};
    }
  }

  Future<void> _write(Map<String, String> tokens) async {
    await ensurePrivateDir(file.parent);
    await writePrivateFile(
      file,
      utf8.encode(const JsonEncoder.withIndent('  ').convert(tokens)),
    );
  }

  @override
  String toString() => 'TokenStore(${file.path})';
}
