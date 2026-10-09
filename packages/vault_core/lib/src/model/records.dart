import 'dart:convert';

import 'package:meta/meta.dart';

import '../format/envelope.dart';
import '../format/format_error.dart';
import '../format/json_reader.dart';
import '../format/timestamps.dart';
import '../format/vault_header.dart' show sortKeys;
import '../sync/hlc.dart';
import 'app_identity.dart';
import 'item_type.dart';

/// Record schema this version writes (SPEC §6).
const int recordSchema = 1;

/// Where a field's value came from.
enum FieldSource {
  /// Parsed out of an attached file.
  file('file'),

  /// Typed in by the user.
  user('user');

  const FieldSource(this.wireName);
  final String wireName;

  static FieldSource parse(Object? value) => switch (value) {
    'file' => FieldSource.file,
    'user' => FieldSource.user,
    _ => throw const VaultFormatException('field source must be file or user'),
  };
}

/// One value on an item, with where it came from and whether it's secret.
@immutable
class ItemField {
  const ItemField({
    required this.value,
    required this.source,
    this.secret = false,
    this.unknownFields = const {},
  });

  final String value;
  final FieldSource source;

  /// Secret values are masked, never indexed for search, and only copied
  /// through the clipboard guard.
  final bool secret;

  final Map<String, Object?> unknownFields;

  static const _known = {'value', 'source', 'secret'};

  factory ItemField.fromJson(Object? json) {
    final r = JsonReader(json, 'field');
    return ItemField(
      value: r.string('value'),
      source: FieldSource.parse(r.value('source')),
      secret: r.boolean('secret'),
      unknownFields: r.unknown(_known),
    );
  }

  Map<String, Object?> toJson() => {
    ...unknownFields,
    'value': value,
    'source': source.wireName,
    if (secret) 'secret': true,
  };

  @override
  bool operator ==(Object other) =>
      other is ItemField &&
      other.value == value &&
      other.source == source &&
      other.secret == secret;

  @override
  int get hashCode => Object.hash(value, source, secret);

  /// Never prints the value: records end up in logs and error reports.
  @override
  String toString() =>
      'ItemField(${source.wireName}${secret ? ', secret' : ''})';
}

/// A file attached to an item. The bytes live in `blobs/<blobId>.enc`.
@immutable
class Attachment {
  Attachment({
    required this.blobId,
    required this.filename,
    required this.mime,
    required this.size,
    required this.sha256,
    this.unknownFields = const {},
  }) {
    if (!isCanonicalUuid(blobId)) {
      throw const VaultFormatException('attachment.blob_id is not a UUID');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const VaultFormatException('attachment.sha256 must be hex');
    }
    if (size < 0) {
      throw const VaultFormatException('attachment.size must be >= 0');
    }
  }

  final String blobId;
  final String filename;
  final String mime;
  final int size;

  /// Lowercase hex SHA-256 of the plaintext file. Export verifies it.
  final String sha256;

  final Map<String, Object?> unknownFields;

  static const _known = {'blob_id', 'filename', 'mime', 'size', 'sha256'};

  factory Attachment.fromJson(Object? json) {
    final r = JsonReader(json, 'attachment');
    return Attachment(
      blobId: r.string('blob_id'),
      filename: r.string('filename'),
      mime: r.string('mime'),
      size: r.integer('size'),
      sha256: r.string('sha256'),
      unknownFields: r.unknown(_known),
    );
  }

  Map<String, Object?> toJson() => {
    ...unknownFields,
    'blob_id': blobId,
    'filename': filename,
    'mime': mime,
    'size': size,
    'sha256': sha256,
  };

  @override
  bool operator ==(Object other) =>
      other is Attachment &&
      other.blobId == blobId &&
      other.filename == filename &&
      other.mime == mime &&
      other.size == size &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(blobId, filename, mime, size, sha256);
}

/// Fields every synced record carries.
abstract interface class SyncedRecord {
  String get id;
  Hlc get rev;
  String get deviceId;
  ObjectType get objectType;
  Map<String, Object?> toJson();
}

/// A typed credential record (SPEC §6.1).
@immutable
class Item implements SyncedRecord {
  Item({
    required this.id,
    required this.typeName,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.rev,
    required this.deviceId,
    this.appId,
    this.platform,
    this.environment,
    List<String> tags = const [],
    Map<String, ItemField> fields = const {},
    List<Attachment> attachments = const [],
    this.expiresAt,
    this.expiresSource,
    this.notes,
    this.conflict,
    this.schema = recordSchema,
    Map<String, Object?> unknownFields = const {},
  }) : tags = List.unmodifiable(tags),
       fields = Map.unmodifiable(fields),
       attachments = List.unmodifiable(attachments),
       unknownFields = Map.unmodifiable(unknownFields) {
    if (!isCanonicalUuid(id)) {
      throw const VaultFormatException('item.id is not a UUID');
    }
    if ((expiresAt == null) != (expiresSource == null)) {
      // SPEC §6.1: both present or both absent. There is no inferred expiry.
      throw const VaultFormatException(
        'item.expires_at and item.expires_source go together',
      );
    }
  }

  @override
  final String id;

  /// The wire name as stored. Kept even when this version doesn't know it.
  final String typeName;

  /// The known type, or `null` for a newer type shown as generic.
  ItemType? get type => ItemType.fromWireName(typeName);

  final String title;
  final String? appId;
  final String? platform;
  final String? environment;
  final List<String> tags;
  final Map<String, ItemField> fields;
  final List<Attachment> attachments;
  final DateTime? expiresAt;
  final ExpirySource? expiresSource;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  @override
  final Hlc rev;
  @override
  final String deviceId;

  /// The other side of an unresolved sync conflict (P2), kept as raw JSON.
  final Map<String, Object?>? conflict;

  final int schema;
  final Map<String, Object?> unknownFields;

  @override
  ObjectType get objectType => ObjectType.item;

  /// Written by a newer schema: shown, but never rewritten by this version
  /// so nothing it doesn't understand is lost.
  bool get isReadOnly => schema > recordSchema;

  static const _known = {
    'schema',
    'id',
    'type',
    'title',
    'app_id',
    'platform',
    'environment',
    'tags',
    'fields',
    'attachments',
    'expires_at',
    'expires_source',
    'notes',
    'created_at',
    'updated_at',
    'rev',
    'device_id',
    'conflict',
  };

  factory Item.fromJson(Object? json) {
    final r = JsonReader(json, 'item');
    final expiresSource = r.optionalString('expires_source');
    final source = expiresSource == null
        ? null
        : ExpirySource.fromWireName(expiresSource) ??
              (throw const VaultFormatException(
                'item.expires_source must be file or user',
              ));
    final conflict = r.value('conflict');
    if (conflict != null && conflict is! Map<String, Object?>) {
      throw const VaultFormatException('item.conflict must be an object');
    }
    return Item(
      schema: r.integer('schema'),
      id: r.string('id'),
      typeName: r.string('type'),
      title: r.string('title'),
      appId: r.optionalString('app_id'),
      platform: r.optionalString('platform'),
      environment: r.optionalString('environment'),
      tags: r.strings('tags'),
      fields: {
        for (final entry in r.map('fields').entries)
          entry.key: ItemField.fromJson(entry.value),
      },
      attachments: [
        for (final a in r.list('attachments')) Attachment.fromJson(a),
      ],
      expiresAt: r.optionalTimestamp('expires_at'),
      expiresSource: source,
      notes: r.optionalString('notes'),
      createdAt: r.timestamp('created_at'),
      updatedAt: r.timestamp('updated_at'),
      rev: Hlc.parse(r.value('rev')),
      deviceId: r.string('device_id'),
      conflict: conflict as Map<String, Object?>?,
      unknownFields: r.unknown(_known),
    );
  }

  @override
  Map<String, Object?> toJson() => {
    ...unknownFields,
    'schema': schema,
    'id': id,
    'type': typeName,
    'title': title,
    'app_id': appId,
    'platform': platform,
    'environment': environment,
    'tags': tags,
    'fields': {for (final e in fields.entries) e.key: e.value.toJson()},
    'attachments': [for (final a in attachments) a.toJson()],
    'expires_at': expiresAt == null ? null : formatTimestamp(expiresAt!),
    'expires_source': expiresSource?.wireName,
    'notes': notes,
    'created_at': formatTimestamp(createdAt),
    'updated_at': formatTimestamp(updatedAt),
    'rev': rev.toString(),
    'device_id': deviceId,
    'conflict': conflict,
  };

  /// A copy with changes. Expiry is set and cleared as a pair; to clear it,
  /// pass `clearExpiry: true`.
  Item copyWith({
    String? title,
    String? appId,
    String? platform,
    String? environment,
    List<String>? tags,
    Map<String, ItemField>? fields,
    List<Attachment>? attachments,
    DateTime? expiresAt,
    ExpirySource? expiresSource,
    bool clearExpiry = false,
    String? notes,
    DateTime? updatedAt,
    Hlc? rev,
    String? deviceId,
  }) => Item(
    id: id,
    typeName: typeName,
    title: title ?? this.title,
    appId: appId ?? this.appId,
    platform: platform ?? this.platform,
    environment: environment ?? this.environment,
    tags: tags ?? this.tags,
    fields: fields ?? this.fields,
    attachments: attachments ?? this.attachments,
    expiresAt: clearExpiry ? null : expiresAt ?? this.expiresAt,
    expiresSource: clearExpiry ? null : expiresSource ?? this.expiresSource,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    rev: rev ?? this.rev,
    deviceId: deviceId ?? this.deviceId,
    conflict: conflict,
    schema: schema,
    unknownFields: unknownFields,
  );

  /// Never prints titles, notes or field values.
  @override
  String toString() => 'Item($id, $typeName)';
}

/// An app that items belong to (SPEC §6.2): a mobile, web or desktop app,
/// a backend service, a CLI … anything the user keeps credentials for.
///
/// The constructor normalizes what it is given, the same way for a record
/// read from disk and one built in the UI: [organization] and identifier
/// values are trimmed, empty ones dropped, and duplicates within a kind
/// dropped (the first is kept). Bundle IDs and package names passed in
/// [identifiers] move to [bundleIds] / [packageNames], so they are always
/// written where older clients read them.
@immutable
class AppRecord implements SyncedRecord {
  AppRecord({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.rev,
    required this.deviceId,
    String? organization,
    String? kindName,
    List<String> bundleIds = const [],
    List<String> packageNames = const [],
    List<AppIdentifier> identifiers = const [],
    String? notes,
    this.iconBlobId,
    this.schema = recordSchema,
    Map<String, Object?> unknownFields = const {},
  }) : organization = _trimmed(organization),
       notes = _trimmed(notes),
       kindName = _trimmed(kindName),
       bundleIds = _legacy(bundleIds, identifiers, IdentifierKind.bundleId),
       packageNames = _legacy(
         packageNames,
         identifiers,
         IdentifierKind.packageName,
       ),
       identifiers = _others(identifiers),
       unknownFields = Map.unmodifiable(unknownFields) {
    if (!isCanonicalUuid(id)) {
      throw const VaultFormatException('app.id is not a UUID');
    }
  }

  @override
  final String id;
  final String name;

  /// Who the app is for (an employer, a client), as the user typed it.
  /// Null when not set; never defaulted or inferred.
  final String? organization;

  /// The stored `kind` ([AppKind.wireName]), kept even when this version
  /// doesn't know it. Null when not set; never inferred.
  final String? kindName;

  /// Apple bundle IDs (`bundle_ids`).
  final List<String> bundleIds;

  /// Android package names (`package_names`).
  final List<String> packageNames;

  /// Every other identifier (`identifiers`): domains, URLs, repositories …
  /// Never holds a bundle ID or package name.
  final List<AppIdentifier> identifiers;

  /// The user's note about the app, as Markdown (CommonMark) text. Null
  /// when not set. Not secret, but never indexed for search or logged.
  final String? notes;

  final String? iconBlobId;
  final DateTime createdAt;
  final DateTime updatedAt;
  @override
  final Hlc rev;
  @override
  final String deviceId;
  final int schema;
  final Map<String, Object?> unknownFields;

  /// The known kind, or `null` when not set or newer than this version.
  AppKind? get kind => AppKind.fromWireName(kindName);

  /// Every identifier in one list: bundle IDs, then package names, then
  /// the rest in their stored order.
  List<AppIdentifier> get allIdentifiers => [
    for (final id in bundleIds) AppIdentifier.of(IdentifierKind.bundleId, id),
    for (final id in packageNames)
      AppIdentifier.of(IdentifierKind.packageName, id),
    ...identifiers,
  ];

  /// What a picker shows: "Acme Corp › Billing API", or just the name.
  String get label =>
      organization == null ? name : '$organization \u203a $name';

  @override
  ObjectType get objectType => ObjectType.app;

  bool get isReadOnly => schema > recordSchema;

  static String? _trimmed(String? text) {
    final value = text?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// [values] plus the [identifiers] of [kind], trimmed, without empties
  /// or repeats.
  static List<String> _legacy(
    List<String> values,
    List<AppIdentifier> identifiers,
    IdentifierKind kind,
  ) => List.unmodifiable({
    for (final value in [
      ...values,
      for (final id in identifiers)
        if (id.kindName.trim() == kind.wireName) id.value,
    ])
      if (value.trim() case final v when v.isNotEmpty) v,
  });

  /// The identifiers that aren't bundle IDs or package names, trimmed,
  /// without empties or repeats within a kind.
  static List<AppIdentifier> _others(List<AppIdentifier> identifiers) {
    final seen = <AppIdentifier>{};
    for (final id in identifiers) {
      final kind = id.kindName.trim();
      final value = id.value.trim();
      if (kind.isEmpty || value.isEmpty) continue;
      if (IdentifierKind.fromWireName(kind)?.isLegacy ?? false) continue;
      final trimmed = kind == id.kindName && value == id.value
          ? id
          : AppIdentifier(kind, value, unknownFields: id.unknownFields);
      seen.add(trimmed);
    }
    return List.unmodifiable(seen);
  }

  static const _known = {
    'schema',
    'id',
    'name',
    'organization',
    'kind',
    'bundle_ids',
    'package_names',
    'identifiers',
    'notes',
    'icon_blob_id',
    'created_at',
    'updated_at',
    'rev',
    'device_id',
  };

  factory AppRecord.fromJson(Object? json) {
    final r = JsonReader(json, 'app');
    return AppRecord(
      schema: r.integer('schema'),
      id: r.string('id'),
      name: r.string('name'),
      organization: r.optionalString('organization'),
      kindName: r.optionalString('kind'),
      bundleIds: r.strings('bundle_ids'),
      packageNames: r.strings('package_names'),
      identifiers: [
        for (final entry in r.list('identifiers'))
          AppIdentifier.fromJson(entry),
      ],
      notes: r.optionalString('notes'),
      iconBlobId: r.optionalString('icon_blob_id'),
      createdAt: r.timestamp('created_at'),
      updatedAt: r.timestamp('updated_at'),
      rev: Hlc.parse(r.value('rev')),
      deviceId: r.string('device_id'),
      unknownFields: r.unknown(_known),
    );
  }

  /// `organization`, `kind`, `identifiers` and `notes` are left out when
  /// not set, so an app that uses none of them encodes exactly as before
  /// they existed.
  @override
  Map<String, Object?> toJson() => {
    ...unknownFields,
    'schema': schema,
    'id': id,
    'name': name,
    'organization': ?organization,
    'kind': ?kindName,
    'bundle_ids': bundleIds,
    'package_names': packageNames,
    if (identifiers.isNotEmpty)
      'identifiers': [for (final i in identifiers) i.toJson()],
    'notes': ?notes,
    'icon_blob_id': iconBlobId,
    'created_at': formatTimestamp(createdAt),
    'updated_at': formatTimestamp(updatedAt),
    'rev': rev.toString(),
    'device_id': deviceId,
  };

  /// A copy with changes. [identifiers] replaces every identifier, bundle
  /// IDs and package names included; to clear [organization], the kind or
  /// [notes], pass an empty string.
  AppRecord copyWith({
    String? name,
    String? organization,
    String? kindName,
    List<AppIdentifier>? identifiers,
    String? notes,
    String? iconBlobId,
    DateTime? updatedAt,
    Hlc? rev,
    String? deviceId,
  }) => AppRecord(
    id: id,
    name: name ?? this.name,
    organization: organization ?? this.organization,
    kindName: kindName ?? this.kindName,
    bundleIds: identifiers == null ? bundleIds : const [],
    packageNames: identifiers == null ? packageNames : const [],
    identifiers: identifiers ?? this.identifiers,
    notes: notes ?? this.notes,
    iconBlobId: iconBlobId ?? this.iconBlobId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    rev: rev ?? this.rev,
    deviceId: deviceId ?? this.deviceId,
    schema: schema,
    unknownFields: unknownFields,
  );

  /// Never prints the name, identifiers or notes.
  @override
  String toString() => 'AppRecord($id)';
}

/// What a tombstone deletes.
enum TombstoneKind {
  item('item'),
  app('app');

  const TombstoneKind(this.wireName);
  final String wireName;
}

/// A deletion marker (SPEC §6.4). Its id is the deleted record's id.
@immutable
class Tombstone implements SyncedRecord {
  Tombstone({
    required this.id,
    required this.kind,
    required this.deletedAt,
    required this.rev,
    required this.deviceId,
    this.schema = recordSchema,
    Map<String, Object?> unknownFields = const {},
  }) : unknownFields = Map.unmodifiable(unknownFields) {
    if (!isCanonicalUuid(id)) {
      throw const VaultFormatException('tombstone.id is not a UUID');
    }
  }

  @override
  final String id;
  final TombstoneKind kind;
  final DateTime deletedAt;
  @override
  final Hlc rev;
  @override
  final String deviceId;
  final int schema;
  final Map<String, Object?> unknownFields;

  @override
  ObjectType get objectType => ObjectType.tombstone;

  static const _known = {
    'schema',
    'id',
    'kind',
    'deleted_at',
    'rev',
    'device_id',
  };

  factory Tombstone.fromJson(Object? json) {
    final r = JsonReader(json, 'tombstone');
    final kind = switch (r.value('kind')) {
      'item' => TombstoneKind.item,
      'app' => TombstoneKind.app,
      _ => throw const VaultFormatException(
        'tombstone.kind must be item or app',
      ),
    };
    return Tombstone(
      schema: r.integer('schema'),
      id: r.string('id'),
      kind: kind,
      deletedAt: r.timestamp('deleted_at'),
      rev: Hlc.parse(r.value('rev')),
      deviceId: r.string('device_id'),
      unknownFields: r.unknown(_known),
    );
  }

  @override
  Map<String, Object?> toJson() => {
    ...unknownFields,
    'schema': schema,
    'id': id,
    'kind': kind.wireName,
    'deleted_at': formatTimestamp(deletedAt),
    'rev': rev.toString(),
    'device_id': deviceId,
  };

  @override
  String toString() => 'Tombstone($id, ${kind.wireName})';
}

/// The JSON bytes a record is encrypted as: compact, keys sorted.
List<int> encodeRecord(SyncedRecord record) =>
    utf8.encode(jsonEncode(sortKeys(record.toJson())));

/// Decodes the plaintext of an object of [type].
SyncedRecord decodeRecord(ObjectType type, List<int> plaintext) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(plaintext));
  } on FormatException {
    throw VaultFormatException('${type.wireName} is not UTF-8 JSON');
  }
  return switch (type) {
    ObjectType.item => Item.fromJson(json),
    ObjectType.app => AppRecord.fromJson(json),
    ObjectType.tombstone => Tombstone.fromJson(json),
    _ => throw ArgumentError.value(type, 'type', 'not a JSON record'),
  };
}
