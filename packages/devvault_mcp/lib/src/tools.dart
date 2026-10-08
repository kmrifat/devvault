import 'dart:convert';
import 'dart:io';

import 'package:agent_bridge/agent_bridge.dart';

import 'app_connection.dart';
import 'delivery.dart' as delivery;
import 'delivery.dart' show DeliveryError;

/// A tool's answer for the agent: text (JSON on success), or an error.
class ToolOutput {
  const ToolOutput(this.text, {this.isError = false});

  factory ToolOutput.json(Object? value) =>
      ToolOutput(const JsonEncoder.withIndent('  ').convert(value));

  final String text;
  final bool isError;
}

/// The tools `devvault-mcp` offers, independent of the MCP library
/// (ADR-0006): each takes the call's arguments and returns a
/// [ToolOutput]. Errors never carry a secret value.
class DevVaultTools {
  DevVaultTools(this.app);

  final AppConnection app;

  /// Text attachments up to this size come back as text from get_secret.
  static const maxTextAttachment = 64 * 1024;

  Future<ToolOutput> vaultStatus(Map<String, Object?> args) => _guard(() async {
    try {
      final status = await app.status();
      return ToolOutput.json({
        'app': 'running',
        'vault': status.state.wireName,
        'paired': status.paired,
      });
    } on AppUnavailable catch (e) {
      return ToolOutput.json({'app': 'unavailable', 'message': '$e'});
    }
  });

  Future<ToolOutput> listItems(Map<String, Object?> args) => _guard(() async {
    final items = await app.paired(
      (b) => b.list(
        query: _optional(args, 'query'),
        app: _optional(args, 'app'),
        platform: _optional(args, 'platform'),
        environment: _optional(args, 'environment'),
        type: _optional(args, 'type'),
        tag: _optional(args, 'tag'),
      ),
    );
    return ToolOutput.json({'count': items.length, 'items': items});
  });

  Future<ToolOutput> getItem(Map<String, Object?> args) => _guard(() async {
    final id = _required(args, 'id');
    return ToolOutput.json(await app.paired((b) => b.get(id)));
  });

  Future<ToolOutput> getSecret(Map<String, Object?> args) => _guard(() async {
    final request = SecretRequest(
      reason: _required(args, 'reason'),
      delivery: const Delivery.reveal(),
      items: [
        SecretItemRequest(
          id: _required(args, 'item_id'),
          fields: _strings(args, 'fields'),
          attachments: _strings(args, 'attachment_ids'),
          notes: args['notes'] == true,
        ),
      ],
    );
    final result = await app.paired((b) => b.requestSecret(request));
    final item = result.items.single;
    return ToolOutput.json({
      'id': item.id,
      'fields': item.fields,
      'notes': ?item.notes,
      if (item.attachments.isNotEmpty)
        'attachments': [
          for (final a in item.attachments) _attachmentForAgent(a),
        ],
    });
  });

  Future<ToolOutput> writeSecretFile(Map<String, Object?> args) =>
      _guard(() async {
        final path = _required(args, 'path');
        final field = _optional(args, 'field');
        final attachment = _optional(args, 'attachment_id');
        if ((field == null) == (attachment == null)) {
          throw const DeliveryError('name exactly one of field, attachment_id');
        }
        delivery.checkTarget(path, overwrite: args['overwrite'] == true);
        final request = SecretRequest(
          reason: _required(args, 'reason'),
          delivery: Delivery.file(path),
          items: [
            SecretItemRequest(
              id: _required(args, 'item_id'),
              fields: field == null ? null : [field],
              attachments: attachment == null ? null : [attachment],
            ),
          ],
        );
        final item = (await app.paired((b) => b.requestSecret(request)))
            .items
            .single;
        final bytes = field != null
            ? utf8.encode(item.fields[field]!)
            : item.attachments.single.data;
        // Checked again: the file may have appeared while the user decided.
        delivery.checkTarget(path, overwrite: args['overwrite'] == true);
        await delivery.writeSecretFile(path, bytes);
        return ToolOutput.json({
          'written': path,
          'bytes': bytes.length,
          'mode': '0600',
        });
      });

  Future<ToolOutput> writeEnvFile(Map<String, Object?> args) =>
      _guard(() async {
        final path = _required(args, 'path');
        final refs = _envRefs(args);
        delivery.checkTarget(path, overwrite: true);
        final values = await _values(
          refs,
          reason: _required(args, 'reason'),
          delivery: Delivery.file(path),
        );
        await delivery.writeEnvFile(path, values);
        return ToolOutput.json({
          'written': path,
          'variables': values.keys.toList(),
          'mode': '0600',
        });
      });

  Future<ToolOutput> runWithSecrets(Map<String, Object?> args) => _guard(
    () async {
      final command = _required(args, 'command');
      // Always absolute and always shown: the user approves where it
      // runs as well as what runs.
      final cwd = Directory(_optional(args, 'cwd') ?? Directory.current.path)
          .absolute
          .path;
      if (!cwd.startsWith('/') || !Directory(cwd).existsSync()) {
        throw const DeliveryError("cwd doesn't exist");
      }
      final seconds = args['timeout_seconds'];
      final timeout = Duration(
        seconds: seconds is int ? seconds.clamp(1, 3600) : 300,
      );
      final refs = _envRefs(args);
      final values = await _values(
        refs,
        reason: _required(args, 'reason'),
        delivery: Delivery.command(
          command,
          cwd: cwd,
          env: {
            for (final MapEntry(key: name, value: (id, field)) in refs.entries)
              name: '$id#$field',
          },
        ),
      );
      final result = await delivery.runWithSecrets(
        command,
        env: values,
        cwd: cwd,
        timeout: timeout,
      );
      return ToolOutput.json({
        ...result.toJson(),
        'note':
            'Secret values in the output were replaced with '
            '[redacted:NAME].',
      });
    },
  );

  /// Fetches the values [refs] point at, in one approval.
  Future<Map<String, String>> _values(
    Map<String, (String, String)> refs, {
    required String reason,
    required Delivery delivery,
  }) async {
    final fieldsById = <String, Set<String>>{};
    for (final (id, field) in refs.values) {
      (fieldsById[id] ??= {}).add(field);
    }
    final request = SecretRequest(
      reason: reason,
      delivery: delivery,
      items: [
        for (final MapEntry(key: id, value: fields) in fieldsById.entries)
          SecretItemRequest(id: id, fields: fields.toList()),
      ],
    );
    final result = await app.paired((b) => b.requestSecret(request));
    final byId = {for (final item in result.items) item.id: item};
    return {
      for (final MapEntry(key: name, value: (id, field)) in refs.entries)
        name: byId[id]!.fields[field]!,
    };
  }

  /// `env`: `{"NAME": "<item id>#<field>"}`.
  static Map<String, (String, String)> _envRefs(Map<String, Object?> args) {
    final env = args['env'];
    if (env is! Map || env.isEmpty) {
      throw const DeliveryError('env must map variable names to item#field');
    }
    return {
      for (final MapEntry(:key, :value) in env.entries)
        _envName(key): _ref(value),
    };
  }

  static String _envName(Object? name) {
    if (name is! String || !delivery.isEnvName(name)) {
      throw DeliveryError('not a variable name: $name');
    }
    return name;
  }

  static (String, String) _ref(Object? ref) {
    final parts = ref is String ? ref.split('#') : const <String>[];
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw DeliveryError('expected "<item id>#<field>", got $ref');
    }
    return (parts[0], parts[1]);
  }

  Map<String, Object?> _attachmentForAgent(SecretAttachment a) {
    final base = {'id': a.id, 'filename': a.filename, 'mime': a.mime};
    if (a.data.length <= maxTextAttachment) {
      try {
        return {...base, 'text': utf8.decode(a.data)};
      } on FormatException {
        // Binary: fall through.
      }
    }
    return {
      ...base,
      'size': a.data.length,
      'note': 'Not shown: binary or larger than 64 KiB. Use write_secret_file.',
    };
  }

  static String _required(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! String || value.trim().isEmpty) {
      throw DeliveryError('$key is required');
    }
    return value;
  }

  static String? _optional(Map<String, Object?> args, String key) {
    final value = args[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  static List<String>? _strings(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! List) return null;
    return value.whereType<String>().toList();
  }

  /// Turns failures into errors the agent can act on.
  static Future<ToolOutput> _guard(Future<ToolOutput> Function() run) async {
    try {
      return await run();
    } on AppUnavailable catch (e) {
      return ToolOutput('$e', isError: true);
    } on DeliveryError catch (e) {
      return ToolOutput(e.message, isError: true);
    } on BridgeException catch (e) {
      return ToolOutput(_explain(e), isError: true);
    } on FileSystemException catch (e) {
      return ToolOutput(
        "Couldn't write ${e.path}: ${e.osError?.message ?? e.message}",
        isError: true,
      );
    } on Object {
      // Not passed on: it might hold data.
      return const ToolOutput('Something went wrong.', isError: true);
    }
  }

  static String _explain(BridgeException e) => switch (e.code) {
    BridgeError.denied =>
      e.message.isEmpty
          ? "The user denied this in DevVault. Don't ask again unless they "
                'tell you to.'
          : 'Not allowed: ${e.message}.',
    BridgeError.timeout =>
      'Nobody answered in DevVault within 2 minutes. Ask the user to look '
          'at DevVault, then try again.',
    BridgeError.notFound => 'Not in the vault: ${e.message}.',
    BridgeError.noVault => "DevVault has no vault on this computer yet.",
    BridgeError.disabled => 'AI agents were turned off in DevVault.',
    BridgeError.notPaired => "DevVault didn't accept this client.",
    BridgeError.badRequest => 'Bad request: ${e.message}.',
    BridgeError.unsupportedProtocol =>
      'This devvault-mcp and DevVault are different versions: ${e.message}.',
    BridgeError.busy => 'Too many requests are waiting in DevVault.',
    BridgeError.internal =>
      'DevVault stopped answering${e.message.isEmpty ? '' : ': ${e.message}'}.',
  };
}
