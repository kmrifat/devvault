import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:vault_core/vault_core.dart';

import 'detect.dart';

/// A file handed to the parsers, plus any secrets the user has typed in
/// for it so far (keyed by [SecretRequest.key]) and the option they picked
/// when the file offered several ([ParseResult.options]).
@immutable
class ParseInput {
  ParseInput({
    required this.filename,
    required this.bytes,
    Map<String, String> secrets = const {},
    this.choice,
  }) : secrets = Map.unmodifiable(secrets);

  /// The original filename, with or without a directory.
  final String filename;
  final Uint8List bytes;

  /// Passwords the user supplied, e.g. `{'password': '…'}` for a `.p12`.
  final Map<String, String> secrets;

  /// The [ParseOption.id] the user picked, or `null` if they haven't.
  final String? choice;

  /// Never prints the bytes, the secrets or the choice.
  @override
  String toString() =>
      'ParseInput($filename, ${bytes.length} bytes, '
      '${secrets.length} secret(s)${choice != null ? ', choice' : ''})';
}

/// A secret the parser needs before it can read more of the file, such as
/// a `.p12` password or a keystore's store password.
@immutable
class SecretRequest {
  const SecretRequest({
    required this.key,
    required this.label,
    this.rejected = false,
  });

  /// Key to put the answer under in [ParseInput.secrets].
  final String key;

  /// What to ask the user for, e.g. "Store password".
  final String label;

  /// `true` when a value was supplied and the file rejected it.
  final bool rejected;

  @override
  bool operator ==(Object other) =>
      other is SecretRequest &&
      other.key == key &&
      other.label == label &&
      other.rejected == rejected;

  @override
  int get hashCode => Object.hash(key, label, rejected);

  @override
  String toString() => 'SecretRequest($key${rejected ? ', rejected' : ''})';
}

/// One of several things a file describes, of which the user picks one,
/// such as an app in a multi-client `google-services.json`. Both values
/// come from the file. Not a secret: secrets go through [SecretRequest].
@immutable
class ParseOption {
  const ParseOption({required this.id, required this.label});

  /// What to put in [ParseInput.choice] to pick this option.
  final String id;

  /// What to show the user, e.g. an Android package name.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is ParseOption && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  /// Never prints the id or label: they are file contents.
  @override
  String toString() => 'ParseOption';
}

/// What a parser read out of a file.
///
/// Every fact comes from the file itself ([FieldSource.file]) and so does
/// [expiresAt]: a parser reports what is there and leaves the rest empty.
/// The constructor enforces this, so a parser can't hand back a guess.
@immutable
class ParseResult {
  ParseResult({
    required this.type,
    required this.format,
    Map<String, ItemField> facts = const {},
    List<SecretRequest> secretsNeeded = const [],
    DateTime? expiresAt,
    List<String> warnings = const [],
    List<ParseOption> options = const [],
    this.chosen,
  }) : facts = Map.unmodifiable(facts),
       secretsNeeded = List.unmodifiable(secretsNeeded),
       expiresAt = expiresAt?.toUtc(),
       warnings = List.unmodifiable(warnings),
       options = List.unmodifiable(options) {
    for (final MapEntry(:key, :value) in facts.entries) {
      if (value.source != FieldSource.file) {
        throw ArgumentError.value(key, 'facts', 'must come from the file');
      }
    }
    final ids = {for (final option in options) option.id};
    if (ids.length != options.length) {
      throw ArgumentError('option ids must be unique');
    }
    if (chosen != null && !ids.contains(chosen)) {
      throw ArgumentError('chosen must be one of the options');
    }
    if (type == ItemType.genericSecret) {
      throw ArgumentError.value(type, 'type', 'a file is never a typed secret');
    }
  }

  /// The fallback for anything that can't be read: a generic file with no
  /// facts. [warnings] say why, without quoting the file.
  ParseResult.generic({
    CredentialFormat format = CredentialFormat.unknown,
    List<String> warnings = const [],
  }) : this(type: ItemType.genericFile, format: format, warnings: warnings);

  /// The item type to import as.
  final ItemType type;

  /// What the file was detected as. Can differ from [type] when a known
  /// format couldn't be read and fell back to a generic file.
  final CredentialFormat format;

  /// Field key → value, all with [FieldSource.file].
  final Map<String, ItemField> facts;

  /// Secrets to ask the user for, then parse again with them.
  final List<SecretRequest> secretsNeeded;

  /// Expiry read from the file (always UTC), or `null` if the file doesn't
  /// state one. Its source is always `file`.
  final DateTime? expiresAt;

  /// Problems worth showing the user. Never contain secret values.
  final List<String> warnings;

  /// The things this file describes when there is more than one, for the
  /// user to pick from; empty when there is nothing to choose. Parse again
  /// with [ParseInput.choice] set to get the chosen one's facts.
  final List<ParseOption> options;

  /// The [ParseOption.id] the facts describe, or `null` when nothing has
  /// been chosen (or the user's choice isn't in the file).
  final String? chosen;

  bool get isGeneric => type == ItemType.genericFile;
  bool get needsSecrets => secretsNeeded.isNotEmpty;

  /// The file offers several [options] and none has been chosen yet.
  bool get needsChoice => options.isNotEmpty && chosen == null;

  /// Lists fact keys and counts only; values may be secret.
  @override
  String toString() =>
      'ParseResult(${type.wireName}, ${format.name}, '
      'facts: ${facts.keys.toList()}, '
      'secretsNeeded: ${secretsNeeded.map((s) => s.key).toList()}, '
      'expiresAt: ${expiresAt?.toIso8601String()}, '
      'warnings: ${warnings.length}, '
      'options: ${options.length}${chosen != null ? ', chosen' : ''})';
}
