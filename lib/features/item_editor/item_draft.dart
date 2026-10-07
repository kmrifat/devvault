import 'package:vault_core/vault_core.dart';

import '../../core/format.dart';
import '../../core/item_templates.dart';

/// One field row in the item form.
class DraftField {
  DraftField({
    this.name = '',
    this.value = '',
    this.secret = false,
    this.source = FieldSource.user,
  }) : _storedKey = null,
       _storedName = null;

  /// A stored or suggested field under [storedKey], shown by its label.
  DraftField.stored(
    String storedKey, {
    this.value = '',
    this.secret = false,
    this.source = FieldSource.user,
  }) : _storedKey = storedKey,
       _storedName = Format.fieldLabel(storedKey),
       name = Format.fieldLabel(storedKey);

  String name;
  String value;
  bool secret;

  /// Fields read from a file are shown but can't be changed or removed:
  /// the app only keeps facts it can trace back to the file.
  final FieldSource source;
  final String? _storedKey;
  final String? _storedName;

  bool get fromFile => source == FieldSource.file;

  /// The key it's stored under: the stored one while the name is
  /// unchanged (so "SHA-1" stays `sha1`), otherwise the name in snake_case
  /// ("API key" → `api_key`).
  String get key => _storedKey != null && name == _storedName
      ? _storedKey
      : DraftField.keyFor(name);

  static String keyFor(String name) => name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

/// What the item form edits, before it becomes an [Item].
///
/// Kept apart from the widgets so the rules (required title, unique field
/// names, file facts untouched, a typed-in expiry marked as the user's) can
/// be tested on their own.
class ItemDraft {
  ItemDraft._({
    required this.type,
    required this.title,
    required this.appId,
    required this.platform,
    required this.environment,
    required this.tags,
    required this.expiresAt,
    required this.expiryFromFile,
    required this.notes,
    required this.fields,
    this.base,
  });

  /// A new item of [type], placed where the user is looking.
  factory ItemDraft.create(
    ItemType type, {
    String? appId,
    String? platform,
    String? environment,
  }) => ItemDraft._(
    type: type,
    title: '',
    appId: appId,
    platform: platform,
    environment: environment,
    tags: '',
    expiresAt: null,
    expiryFromFile: false,
    notes: '',
    fields: [
      for (final t in ItemTemplates.fieldsFor(type))
        DraftField.stored(t.key, secret: t.secret),
    ],
  );

  /// [item] as it stands, ready to edit.
  factory ItemDraft.edit(Item item) => ItemDraft._(
    base: item,
    type: item.type ?? ItemType.genericFile,
    title: item.title,
    appId: item.appId,
    platform: item.platform,
    environment: item.environment,
    tags: item.tags.join(', '),
    expiresAt: item.expiresAt,
    expiryFromFile: item.expiresSource == ExpirySource.file,
    notes: item.notes ?? '',
    fields: [
      for (final MapEntry(:key, :value) in item.fields.entries)
        DraftField.stored(
          key,
          value: value.value,
          secret: value.secret,
          source: value.source,
        ),
    ],
  );

  /// The item being edited; null when creating one.
  final Item? base;
  ItemType type;
  String title;
  String? appId;
  String? platform;
  String? environment;

  /// Comma-separated, as typed.
  String tags;
  DateTime? expiresAt;

  /// The expiry was read from the file and can't be changed here.
  final bool expiryFromFile;
  String notes;
  final List<DraftField> fields;

  bool get isNew => base == null;

  /// Switches a new item's type, swapping the suggested fields for the new
  /// type's but keeping any the user has filled in.
  void changeType(ItemType next) {
    if (!isNew || next == type) return;
    type = next;
    fields.removeWhere((f) => f.value.isEmpty);
    final names = {for (final f in fields) f.key};
    for (final t in ItemTemplates.fieldsFor(next)) {
      if (!names.contains(t.key)) {
        fields.add(DraftField.stored(t.key, secret: t.secret));
      }
    }
  }

  List<String> get tagList => [
    ...{
      for (final tag in tags.split(','))
        if (tag.trim().isNotEmpty) tag.trim(),
    },
  ];

  /// Problems that stop saving, by what they're about: `title` or the
  /// index of a field row as a string.
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (title.trim().isEmpty) errors['title'] = 'Give it a name';
    final seen = <String>{};
    for (final (i, field) in fields.indexed) {
      if (field.fromFile || _isBlank(field)) continue;
      if (field.key.isEmpty) {
        errors['$i'] = 'Name this field';
      } else if (!seen.add(field.key)) {
        errors['$i'] = 'Another field has this name';
      }
    }
    return errors;
  }

  /// The item to save: a fresh one from [newItem] when creating, else the
  /// edited copy of [base]. Empty rows are dropped. Call [validate] first.
  Item toItem(Item Function(ItemType type, String title) newItem) {
    final start = base ?? newItem(type, title.trim());
    final kept = <String, ItemField>{
      for (final field in fields)
        if (field.fromFile)
          field.key: start.fields[field.key]!
        else if (!_isBlank(field))
          field.key: ItemField(
            value: field.value,
            source: FieldSource.user,
            secret: field.secret,
          ),
    };
    final userExpiry = expiryFromFile ? null : expiresAt;
    return Item(
      id: start.id,
      typeName: start.typeName,
      title: title.trim(),
      appId: appId,
      platform: platform,
      environment: environment,
      tags: tagList,
      fields: kept,
      attachments: start.attachments,
      expiresAt: expiryFromFile ? start.expiresAt : userExpiry,
      expiresSource: expiryFromFile
          ? ExpirySource.file
          : userExpiry == null
          ? null
          : ExpirySource.user,
      notes: notes.trim().isEmpty ? null : notes,
      createdAt: start.createdAt,
      updatedAt: start.updatedAt,
      rev: start.rev,
      deviceId: start.deviceId,
      conflict: start.conflict,
      schema: start.schema,
      unknownFields: start.unknownFields,
    );
  }

  static bool _isBlank(DraftField f) =>
      f.name.trim().isEmpty && f.value.isEmpty;
}
