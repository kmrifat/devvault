import 'dart:isolate';

import 'detect.dart';
import 'parse_result.dart';
import 'parsers/apple_auth_key.dart';
import 'parsers/firebase_config.dart';
import 'parsers/java_keystore.dart';
import 'parsers/oauth_client.dart';
import 'parsers/pem_bundle.dart';
import 'parsers/pkcs12.dart';
import 'parsers/provisioning_profile.dart';
import 'parsers/service_account.dart';
import 'parsers/ssh_private_key.dart';
import 'parsers/x509_certificate.dart';

/// Reads facts out of one or more [CredentialFormat]s.
///
/// Implementations may throw on malformed input; [CredentialParsers] turns
/// any exception into a generic file. They must not log or rethrow file
/// content.
abstract interface class CredentialParser {
  /// The formats this parser reads.
  Set<CredentialFormat> get formats;

  /// Parses [input], which [detectFormat] placed as [format].
  ParseResult parse(ParseInput input, CredentialFormat format);
}

/// Detects a file's format and runs the matching parser.
///
/// The contract is simple: [parse] never throws. Unknown input, a format
/// with no parser yet, or any exception inside a parser all come back as
/// [ParseResult.generic], with no invented fields.
class CredentialParsers {
  CredentialParsers(Iterable<CredentialParser> parsers)
    : _byFormat = {
        for (final parser in parsers)
          for (final format in parser.formats) format: parser,
      };

  /// The parsers DevVault ships. Formats are added here as their parsers
  /// land (P1-12…P1-17); until then they import as generic files.
  factory CredentialParsers.standard() => CredentialParsers(const [
    AppleAuthKeyParser(),
    X509CertificateParser(),
    JavaKeystoreParser(),
    FirebaseConfigParser(),
    ServiceAccountParser(),
    OAuthClientParser(),
    Pkcs12Parser(),
    PemBundleParser(),
    SshPrivateKeyParser(),
    ProvisioningProfileParser(),
  ]);

  final Map<CredentialFormat, CredentialParser> _byFormat;

  /// Formats that have a parser registered.
  Set<CredentialFormat> get supportedFormats => _byFormat.keys.toSet();

  ParseResult parse(ParseInput input) {
    final format = detectFormat(input.filename, input.bytes);
    final parser = _byFormat[format];
    if (format == CredentialFormat.unknown) {
      return ParseResult.generic();
    }
    if (parser == null) {
      return ParseResult.generic(
        format: format,
        warnings: [
          'DevVault can\'t read ${format.label} files yet. '
              'It was imported as a generic file.',
        ],
      );
    }
    try {
      final result = parser.parse(input, format);
      if (result.format != format) {
        return ParseResult.generic(
          format: format,
          warnings: [_unreadable(format)],
        );
      }
      return result;
    } catch (_) {
      // The error may quote the file, so it goes nowhere.
      return ParseResult.generic(
        format: format,
        warnings: [_unreadable(format)],
      );
    }
  }

  /// [parse] on a background isolate, so a large or hostile file can't
  /// stall the UI. Never throws.
  Future<ParseResult> parseInIsolate(ParseInput input) async {
    try {
      return await Isolate.run(() => parse(input));
    } catch (_) {
      return ParseResult.generic(
        format: detectFormat(input.filename, input.bytes),
        warnings: const [
          'The file could not be read. '
              'It was imported as a generic file.',
        ],
      );
    }
  }

  static String _unreadable(CredentialFormat format) =>
      'Detected as ${format.label} but could not be read. '
      'It was imported as a generic file.';
}
