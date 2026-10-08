import 'dart:convert';
import 'dart:typed_data';

import 'protocol.dart';

/// How the helper will use the values; shown to the user (PROTOCOL.md §5).
enum DeliveryMode {
  /// The values go back to the agent, and so to the AI model.
  reveal,

  /// The helper writes them to [Delivery.path].
  file,

  /// The helper runs [Delivery.command] with them as env vars.
  command,
}

class Delivery {
  const Delivery.reveal() : mode = DeliveryMode.reveal, target = null;
  const Delivery.file(String path) : mode = DeliveryMode.file, target = path;
  const Delivery.command(String command)
    : mode = DeliveryMode.command,
      target = command;

  final DeliveryMode mode;

  /// The file path or the command line; null for [DeliveryMode.reveal].
  final String? target;

  Map<String, Object?> toJson() => switch (mode) {
    DeliveryMode.reveal => {'mode': 'reveal'},
    DeliveryMode.file => {'mode': 'file', 'path': target},
    DeliveryMode.command => {'mode': 'command', 'command': target},
  };

  factory Delivery.fromJson(Object? json) {
    if (json is! Map) throw _bad('delivery');
    switch (json['mode']) {
      case 'reveal':
        return const Delivery.reveal();
      case 'file':
        final path = json['path'];
        if (path is! String || !path.startsWith('/') || path.length > 1024) {
          throw _bad('delivery.path must be an absolute path');
        }
        return Delivery.file(path);
      case 'command':
        final command = json['command'];
        if (command is! String ||
            command.trim().isEmpty ||
            command.length > 4096) {
          throw _bad('delivery.command');
        }
        return Delivery.command(command);
      default:
        throw _bad('delivery.mode');
    }
  }

  @override
  String toString() => 'Delivery(${mode.name})';
}

/// One item in a `request_secret`.
class SecretItemRequest {
  const SecretItemRequest({
    required this.id,
    this.fields,
    this.attachments,
    this.notes = false,
  });

  final String id;

  /// Field names; null for none, unless nothing at all is named.
  final List<String>? fields;

  /// Attachment ids (`blob_id`); null for none.
  final List<String>? attachments;

  final bool notes;

  /// Nothing named: the request is for every field (PROTOCOL.md §5).
  bool get wantsAllFields => fields == null && attachments == null && !notes;

  Map<String, Object?> toJson() => {
    'id': id,
    'fields': ?fields,
    'attachments': ?attachments,
    if (notes) 'notes': true,
  };

  factory SecretItemRequest.fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) throw _bad('items[].id');
    return SecretItemRequest(
      id: json['id'] as String,
      fields: _strings(json['fields'], 'items[].fields'),
      attachments: _strings(json['attachments'], 'items[].attachments'),
      notes: json['notes'] == true,
    );
  }

  @override
  String toString() => 'SecretItemRequest($id)';
}

/// The params of `request_secret`.
class SecretRequest {
  const SecretRequest({
    required this.reason,
    required this.delivery,
    required this.items,
  });

  /// Why the agent needs it, shown verbatim to the user.
  final String reason;
  final Delivery delivery;
  final List<SecretItemRequest> items;

  Map<String, Object?> toJson() => {
    'reason': reason,
    'delivery': delivery.toJson(),
    'items': [for (final item in items) item.toJson()],
  };

  factory SecretRequest.fromJson(Map<String, Object?> json) {
    final reason = json['reason'];
    if (reason is! String || reason.trim().isEmpty || reason.length > 500) {
      throw _bad('reason is required (at most 500 characters)');
    }
    final items = json['items'];
    if (items is! List || items.isEmpty || items.length > maxItemsPerRequest) {
      throw _bad('items must name 1 to $maxItemsPerRequest items');
    }
    return SecretRequest(
      reason: reason.trim(),
      delivery: Delivery.fromJson(json['delivery']),
      items: [for (final item in items) SecretItemRequest.fromJson(item)],
    );
  }

  @override
  String toString() =>
      'SecretRequest(${delivery.mode.name}, ${items.length} items)';
}

/// A decrypted attachment. Never printed.
class SecretAttachment {
  SecretAttachment({
    required this.id,
    required this.filename,
    required this.mime,
    required this.data,
  });

  final String id;
  final String filename;
  final String mime;
  final Uint8List data;

  Map<String, Object?> toJson() => {
    'id': id,
    'filename': filename,
    'mime': mime,
    'data': base64.encode(data),
  };

  factory SecretAttachment.fromJson(Object? json) {
    if (json is! Map) throw _bad('attachment');
    final id = json['id'], name = json['filename'], mime = json['mime'];
    final data = json['data'];
    if (id is! String ||
        name is! String ||
        mime is! String ||
        data is! String) {
      throw _bad('attachment');
    }
    return SecretAttachment(
      id: id,
      filename: name,
      mime: mime,
      data: base64.decode(data),
    );
  }

  @override
  String toString() => 'SecretAttachment($id, ${data.length} bytes)';
}

/// The values for one item. Never printed.
class SecretItem {
  SecretItem({
    required this.id,
    this.fields = const {},
    this.attachments = const [],
    this.notes,
  });

  final String id;
  final Map<String, String> fields;
  final List<SecretAttachment> attachments;
  final String? notes;

  Map<String, Object?> toJson() => {
    'id': id,
    'fields': fields,
    'attachments': [for (final a in attachments) a.toJson()],
    'notes': ?notes,
  };

  factory SecretItem.fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) throw _bad('items[].id');
    final fields = json['fields'] ?? const {};
    if (fields is! Map) throw _bad('items[].fields');
    final attachments = json['attachments'] ?? const [];
    if (attachments is! List) throw _bad('items[].attachments');
    final notes = json['notes'];
    return SecretItem(
      id: json['id'] as String,
      fields: {
        for (final MapEntry(:key, :value) in fields.entries)
          if (key is String && value is String) key: value,
      },
      attachments: [for (final a in attachments) SecretAttachment.fromJson(a)],
      notes: notes is String ? notes : null,
    );
  }

  /// Never prints a value: results pass through logs and error reports.
  @override
  String toString() =>
      'SecretItem($id, fields: ${fields.keys.join(', ')}, '
      '${attachments.length} attachments${notes == null ? '' : ', notes'})';
}

/// The result of `request_secret`.
class SecretResult {
  SecretResult(this.items);

  final List<SecretItem> items;

  Map<String, Object?> toJson() => {
    'items': [for (final item in items) item.toJson()],
  };

  factory SecretResult.fromJson(Map<String, Object?> json) {
    final items = json['items'];
    if (items is! List) throw _bad('items');
    return SecretResult([for (final item in items) SecretItem.fromJson(item)]);
  }

  @override
  String toString() => 'SecretResult(${items.length} items)';
}

List<String>? _strings(Object? json, String what) {
  if (json == null) return null;
  if (json is! List || json.any((e) => e is! String) || json.length > 100) {
    throw _bad(what);
  }
  return json.cast<String>().toList();
}

BridgeException _bad(String what) =>
    BridgeException(BridgeError.badRequest, what);
