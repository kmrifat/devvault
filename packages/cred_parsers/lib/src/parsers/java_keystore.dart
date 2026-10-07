import 'package:vault_core/vault_core.dart';

import '../detect.dart';
import '../java_keystore.dart';
import '../parse_result.dart';
import '../parsers.dart';
import '../x509.dart';

/// Android signing keystores in the Java formats: JKS (`FEEDFEED`) and
/// JCEKS (`CECECECE`). PKCS#12 keystores go through the PKCS#12 parser.
///
/// Aliases and certificates are stored in clear, so they are always read,
/// with or without a password. The store password is checked against the
/// file's integrity digest and the key password by unlocking the private
/// key; each has its own [SecretRequest], so the two errors stay apart.
/// Passwords are never facts: the app keeps what the user typed itself.
///
/// Certificate facts and the expiry come from the leaf certificate of the
/// keystore's private key. When it holds several keys the user picks the
/// alias, so nothing is chosen for them.
class JavaKeystoreParser implements CredentialParser {
  const JavaKeystoreParser();

  /// `JKS` or `JCEKS`.
  static const storeType = 'store_type';

  /// Number of entries of any kind.
  static const entryCount = 'entry_count';

  /// The alias of the keystore's only private key.
  static const alias = 'alias';

  /// Every alias in file order, comma-separated. Left out when the
  /// keystore is a single private key ([alias] says it all).
  static const aliases = 'aliases';

  /// Certificates in the private key's chain.
  static const chainLength = 'chain_length';

  /// [SecretRequest] key for the store password.
  static const storePassword = 'store_password';

  /// [SecretRequest] key for the key password. When it's not given, the
  /// store password is tried, as Android's tooling uses the same one.
  static const keyPassword = 'key_password';

  @override
  Set<CredentialFormat> get formats => const {
    CredentialFormat.jks,
    CredentialFormat.jceks,
  };

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) {
    final keystore = JavaKeystore.decode(input.bytes);
    final expected = format == CredentialFormat.jks
        ? JavaKeystoreType.jks
        : JavaKeystoreType.jceks;
    if (keystore.type != expected) {
      throw const FormatException('keystore type does not match');
    }

    final entries = keystore.entries;
    final keys = [
      for (final e in entries)
        if (e.kind == KeystoreEntryKind.privateKey) e,
    ];
    final primary = keys.length == 1 ? keys.single : null;
    final warnings = <String>[];

    final facts = <String, ItemField>{
      storeType: _fact(keystore.type.label),
      entryCount: _fact('${entries.length}'),
      if (primary != null) alias: _fact(primary.alias),
      if (primary == null || entries.length > 1)
        aliases: _fact(entries.map((e) => e.alias).join(', ')),
    };

    DateTime? expiresAt;
    if (primary != null) {
      facts[chainLength] = _fact('${primary.chain.length}');
      final leaf = primary.chain.firstOrNull;
      if (leaf != null && leaf.type == 'X.509') {
        try {
          final cert = X509Certificate.parse(leaf.encoded);
          facts.addAll(certificateFacts(cert));
          expiresAt = cert.notAfter;
        } on FormatException {
          warnings.add(
            'The certificate for "${primary.alias}" could not be read.',
          );
        }
      }
    } else if (keys.isEmpty) {
      warnings.add('This keystore has no private key, so it can\'t sign.');
    } else {
      warnings.add(
        'This keystore holds ${keys.length} keys '
        '(${keys.map((k) => k.alias).join(', ')}). Choose the alias you '
        'sign with; certificate details are read for a single key only.',
      );
    }

    return ParseResult(
      type: ItemType.androidKeystore,
      format: format,
      facts: facts,
      expiresAt: expiresAt,
      secretsNeeded: _checkPasswords(input, keystore, keys, warnings),
      warnings: warnings,
    );
  }

  /// The store password first, then the key password(s). Adds warnings
  /// for what a single [SecretRequest] can't say.
  static List<SecretRequest> _checkPasswords(
    ParseInput input,
    JavaKeystore keystore,
    List<KeystoreEntry> keys,
    List<String> warnings,
  ) {
    final store = input.secrets[storePassword];
    if (store == null || !keystore.checkStorePassword(store)) {
      return [
        SecretRequest(
          key: storePassword,
          label: 'Store password',
          rejected: store != null,
        ),
      ];
    }
    if (keys.isEmpty) return const [];

    final supplied = input.secrets[keyPassword];
    final candidate = supplied ?? store;
    final opened = <String>[];
    final refused = <String>[];
    final unchecked = <String>[];
    for (final key in keys) {
      switch (keystore.checkKeyPassword(key, candidate)) {
        case KeyPasswordCheck.correct:
          opened.add(key.alias);
        case KeyPasswordCheck.wrong:
          refused.add(key.alias);
        case KeyPasswordCheck.unsupported:
          unchecked.add(key.alias);
      }
    }

    if (unchecked.isNotEmpty) {
      warnings.add(
        'DevVault can\'t check the key password for '
        '${unchecked.join(', ')}: the key uses an unknown protection.',
      );
    }
    if (refused.isEmpty) return const [];
    if (opened.isEmpty) {
      return [
        SecretRequest(
          key: keyPassword,
          label: 'Key password',
          rejected: supplied != null,
        ),
      ];
    }
    final which = supplied == null ? 'store password' : 'key password';
    warnings.add(
      'The $which opens the key for ${opened.join(', ')} '
      'but not for ${refused.join(', ')}.',
    );
    return const [];
  }

  static ItemField _fact(String value) =>
      ItemField(value: value, source: FieldSource.file);
}
