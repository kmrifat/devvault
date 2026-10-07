import 'dart:typed_data';

import 'package:cred_parsers/cred_parsers.dart';
import 'package:vault_core/vault_core.dart';

/// A file the user chose to import.
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  @override
  String toString() => 'PickedFile($name, ${bytes.length} bytes)';
}

/// A field the user must fill in before the file can be imported, because
/// the file doesn't say it and the item is useless without it.
class RequiredField {
  const RequiredField({
    required this.key,
    required this.label,
    required this.pattern,
    required this.hint,
    required this.error,
  });

  final String key;
  final String label;
  final RegExp pattern;
  final String hint;
  final String error;
}

/// What an Apple auth key is for. The file doesn't say, so the user picks.
enum KeyPurpose {
  appStoreConnect('App Store Connect API'),
  apns('APNs'),
  signInWithApple('Sign in with Apple');

  const KeyPurpose(this.label);
  final String label;
}

/// What the import dialog edits: the parsed file plus what only the user
/// knows. Kept apart from the widgets so its rules can be tested alone.
///
/// Facts from the file are never editable here, and nothing the user types
/// is ever stored as coming from the file.
class ImportDraft {
  ImportDraft(this.file, this.result) : title = _titleFrom(file.name);

  /// Field key for [purpose].
  static const purposeKey = 'purpose';

  static final _teamId = RegExp(r'^[A-Z0-9]{10}$');

  final PickedFile file;

  /// The latest parse of [file]. Replaced when the user supplies a
  /// password or picks an option.
  ParseResult result;

  /// Secrets typed so far, by [SecretRequest.key]. Saved on the item as the
  /// user's own secret fields when [keepSecrets] is set.
  final Map<String, String> secrets = {};
  bool keepSecrets = true;

  /// The option picked from [ParseResult.options], if any.
  String? choice;

  /// Values for [requiredFields], by key.
  final Map<String, String> userFields = {};
  KeyPurpose? purpose;

  String title;
  String? appId;
  String? platform;
  String? environment;

  ItemType get type => result.type;

  /// The original file's name without its extension, as a starting point
  /// the user can change. It names the item; it isn't a claim about the file.
  static String _titleFrom(String name) {
    final base = name.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  /// The fields this type needs that the file didn't provide.
  List<RequiredField> get requiredFields => [
    if (type == ItemType.appleAuthKey) ...[
      if (!result.facts.containsKey(AppleAuthKeyParser.keyId))
        RequiredField(
          key: AppleAuthKeyParser.keyId,
          label: 'Key ID',
          pattern: _teamId,
          hint: 'From App Store Connect, e.g. 2X9R4HXF34',
          error: 'A Key ID is 10 capital letters and digits',
        ),
      if (!result.facts.containsKey(CertificateFields.team))
        RequiredField(
          key: CertificateFields.team,
          label: 'Team ID',
          pattern: _teamId,
          hint: 'From your Apple Developer account, e.g. A1B2C3D4E5',
          error: 'A Team ID is 10 capital letters and digits',
        ),
    ],
  ];

  /// Whether the dialog offers [KeyPurpose].
  bool get asksPurpose => type == ItemType.appleAuthKey;

  /// Whether the file is ready to import: no password or option pending.
  bool get isReady => !result.needsSecrets && !result.needsChoice;

  /// Problems that stop the import, by `title` or a required field's key.
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (title.trim().isEmpty) errors['title'] = 'Give it a name';
    for (final field in requiredFields) {
      final value = (userFields[field.key] ?? '').trim();
      if (value.isEmpty) {
        errors[field.key] = '${field.label} is required';
      } else if (!field.pattern.hasMatch(value)) {
        errors[field.key] = field.error;
      }
    }
    return errors;
  }

  /// The fields to store: the file's facts as they are, then what the
  /// user typed, marked as theirs.
  Map<String, ItemField> get fields => {
    ...result.facts,
    for (final field in requiredFields)
      field.key: ItemField(
        value: userFields[field.key]!.trim(),
        source: FieldSource.user,
      ),
    if (asksPurpose && purpose != null)
      purposeKey: ItemField(value: purpose!.label, source: FieldSource.user),
    if (keepSecrets)
      for (final MapEntry(:key, :value) in secrets.entries)
        if (value.isNotEmpty && !result.facts.containsKey(key))
          key: ItemField(value: value, source: FieldSource.user, secret: true),
  };

  /// A new item for this file with [attachment]. Call [validate] first.
  Item toItem(
    Item Function(ItemType type, String title) newItem,
    Attachment attachment,
  ) {
    final start = newItem(type, title.trim());
    return _copy(
      start,
      fields: fields,
      attachments: [attachment],
      expiresAt: result.expiresAt,
      expiresSource: result.expiresAt == null ? null : ExpirySource.file,
      appId: appId,
      platform: platform,
      environment: environment,
    );
  }

  /// [existing] with this file in place of its old one: the old file's
  /// facts and expiry go, and what the user set on the item stays.
  Item replace(Item existing, Attachment attachment) {
    final kept = {
      for (final MapEntry(:key, :value) in existing.fields.entries)
        if (value.source == FieldSource.user) key: value,
    };
    final userExpiry = existing.expiresSource == ExpirySource.user;
    final fromFile = result.expiresAt;
    return _copy(
      existing,
      fields: {...kept, ...fields},
      attachments: [attachment],
      expiresAt: fromFile ?? (userExpiry ? existing.expiresAt : null),
      expiresSource: fromFile != null
          ? ExpirySource.file
          : userExpiry
          ? ExpirySource.user
          : null,
      appId: existing.appId,
      platform: existing.platform,
      environment: existing.environment,
    );
  }

  static Item _copy(
    Item start, {
    required Map<String, ItemField> fields,
    required List<Attachment> attachments,
    required DateTime? expiresAt,
    required ExpirySource? expiresSource,
    required String? appId,
    required String? platform,
    required String? environment,
  }) => Item(
    id: start.id,
    typeName: start.typeName,
    title: start.title,
    appId: appId,
    platform: platform,
    environment: environment,
    tags: start.tags,
    fields: fields,
    attachments: attachments,
    expiresAt: expiresAt,
    expiresSource: expiresSource,
    notes: start.notes,
    createdAt: start.createdAt,
    updatedAt: start.updatedAt,
    rev: start.rev,
    deviceId: start.deviceId,
    conflict: start.conflict,
    schema: start.schema,
    unknownFields: start.unknownFields,
  );

  /// Items that already hold a file with these exact bytes.
  static List<Item> duplicatesOf(String sha256, Iterable<Item> items) => [
    for (final item in items)
      if (item.attachments.any((a) => a.sha256 == sha256)) item,
  ];
}
