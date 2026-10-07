import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'envelope.dart';
import 'format_error.dart';
import 'kdf_params.dart';
import 'timestamps.dart';

/// `vault.json`, the vault's only plaintext object (SPEC §4).
@immutable
class VaultHeader {
  VaultHeader({
    required this.vaultId,
    required this.createdAt,
    required this.kdf,
    required Uint8List wrappedVkPassword,
    required Uint8List wrappedVkRecovery,
    required this.vkId,
    this.vaultType = personal,
    Map<String, Object?> unknownFields = const {},
  }) : wrappedVkPassword = Uint8List.fromList(wrappedVkPassword),
       wrappedVkRecovery = Uint8List.fromList(wrappedVkRecovery),
       unknownFields = Map.unmodifiable(unknownFields) {
    if (!isCanonicalUuid(vaultId)) {
      throw const VaultFormatException('vault_id is not a lowercase UUID');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(vkId)) {
      throw const VaultFormatException('vk_id must be 32 bytes of hex');
    }
  }

  static const String format = 'devvault';
  static const String personal = 'personal';
  static const String fileName = 'vault.json';

  final String vaultId;
  final String vaultType;
  final DateTime createdAt;
  final KdfParams kdf;
  final Uint8List wrappedVkPassword;
  final Uint8List wrappedVkRecovery;

  /// Keyed BLAKE2b fingerprint of the vault key (SPEC §4.4).
  final String vkId;

  /// Fields this version doesn't know, kept so a rewrite doesn't drop them.
  final Map<String, Object?> unknownFields;

  static const _known = {
    'format',
    'format_version',
    'vault_type',
    'vault_id',
    'created_at',
    'kdf',
    'wrapped_vk_password',
    'wrapped_vk_recovery',
    'vk_id',
  };

  /// Parses `vault.json`. Rejects other formats, unknown versions and
  /// out-of-bounds KDF parameters before anything is derived.
  factory VaultHeader.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const VaultFormatException('vault.json is not JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const VaultFormatException('vault.json must be an object');
    }
    final Map<String, Object?> json = decoded;
    if (json['format'] != format) {
      throw const VaultFormatException('not a DevVault vault');
    }
    final version = json['format_version'];
    if (version != Envelope.formatVersion) {
      throw UnsupportedFormatVersion(version);
    }
    String string(String field) {
      final value = json[field];
      if (value is! String) {
        throw VaultFormatException('$field must be a string');
      }
      return value;
    }

    Uint8List bytes(String field) {
      try {
        return base64.decode(string(field));
      } on FormatException {
        throw VaultFormatException('$field is not base64');
      }
    }

    return VaultHeader(
      vaultId: string('vault_id'),
      vaultType: string('vault_type'),
      createdAt: parseTimestamp(json['created_at'], 'created_at'),
      kdf: KdfParams.fromJson(json['kdf']),
      wrappedVkPassword: bytes('wrapped_vk_password'),
      wrappedVkRecovery: bytes('wrapped_vk_recovery'),
      vkId: string('vk_id'),
      unknownFields: {
        for (final entry in json.entries)
          if (!_known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  Map<String, Object?> toJson() => {
    ...unknownFields,
    'format': format,
    'format_version': Envelope.formatVersion,
    'vault_type': vaultType,
    'vault_id': vaultId,
    'created_at': formatTimestamp(createdAt),
    'kdf': kdf.toJson(),
    'wrapped_vk_password': base64.encode(wrappedVkPassword),
    'wrapped_vk_recovery': base64.encode(wrappedVkRecovery),
    'vk_id': vkId,
  };

  /// Pretty, key-sorted JSON so diffs and hand inspection stay readable.
  String toJsonString() =>
      '${const JsonEncoder.withIndent('  ').convert(sortKeys(toJson()))}\n';

  VaultHeader copyWith({
    KdfParams? kdf,
    Uint8List? wrappedVkPassword,
    Uint8List? wrappedVkRecovery,
    String? vkId,
  }) => VaultHeader(
    vaultId: vaultId,
    vaultType: vaultType,
    createdAt: createdAt,
    kdf: kdf ?? this.kdf,
    wrappedVkPassword: wrappedVkPassword ?? this.wrappedVkPassword,
    wrappedVkRecovery: wrappedVkRecovery ?? this.wrappedVkRecovery,
    vkId: vkId ?? this.vkId,
    unknownFields: unknownFields,
  );
}

/// The vault was written by a newer (or unknown) version of the format.
class UnsupportedFormatVersion extends VaultFormatException {
  UnsupportedFormatVersion(this.version)
    : super('format_version $version is not supported');

  final Object? version;
}

/// [value] with every map's keys sorted, recursively.
Object? sortKeys(Object? value) => switch (value) {
  Map() => {
    for (final key in (value.keys.cast<String>().toList()..sort()))
      key: sortKeys(value[key]),
  },
  List() => [for (final item in value) sortKeys(item)],
  _ => value,
};
