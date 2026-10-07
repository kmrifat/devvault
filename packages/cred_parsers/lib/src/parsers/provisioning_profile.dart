import 'dart:typed_data';

import 'package:vault_core/vault_core.dart';

import '../der.dart';
import '../detect.dart';
import '../parse_result.dart';
import '../parsers.dart';
import '../plist.dart';
import '../x509.dart';
import 'common.dart';

/// Apple provisioning profiles (`.mobileprovision`, `.provisionprofile`):
/// an XML plist wrapped in CMS SignedData.
///
/// The CMS is only unwrapped to reach the plist. **Its signature is not
/// verified**, so nothing this parser reports says the profile is genuine,
/// trusted or issued by Apple; it reports what the plist says.
///
/// The expiry is the plist's `ExpirationDate` (SPEC §6.5).
class ProvisioningProfileParser implements CredentialParser {
  const ProvisioningProfileParser();

  /// `Name`.
  static const name = 'name';

  /// `UUID`.
  static const uuid = 'uuid';

  /// `TeamIdentifier`. A profile normally lists one team; if it lists
  /// several, all of them are given, one per line, and none is picked.
  static const teamId = 'team_id';

  /// `TeamName`.
  static const teamName = 'team_name';

  /// `AppIDName`: the App ID's name in the developer portal.
  static const appIdName = 'app_id_name';

  /// The bundle id from the entitlements' `application-identifier`, with
  /// its `<prefix>.` removed only when that prefix is one of the profile's
  /// `TeamIdentifier`s or `ApplicationIdentifierPrefix`es. Otherwise the
  /// raw value. A wildcard App ID (`TEAMID.*`) gives `*`.
  static const bundleId = 'bundle_id';

  /// The entitlements' `application-identifier` exactly as written (macOS
  /// profiles: `com.apple.application-identifier`).
  static const applicationIdentifier = 'application_identifier';

  /// `Platform`, joined with `, ` (e.g. `iOS, xrOS`).
  static const platform = 'platform';

  /// `CreationDate`, ISO-8601 UTC.
  static const creationDate = 'creation_date';

  /// `ExpirationDate`, ISO-8601 UTC. Also the result's `expiresAt`.
  static const expirationDate = 'expiration_date';

  /// The distribution kind, read from the keys Apple sets for it:
  ///
  /// 1. `ProvisionsAllDevices` is `true` → `Enterprise (In-House)`.
  /// 2. Otherwise, `ProvisionedDevices` is present and the entitlements'
  ///    `get-task-allow` is `true` → `Development`.
  /// 3. `ProvisionedDevices` is present and `get-task-allow` is `false` or
  ///    absent → `Ad Hoc`.
  /// 4. No `ProvisionedDevices` and `get-task-allow` `false` or absent →
  ///    `App Store`.
  ///
  /// Any other combination (e.g. `get-task-allow` without a device list)
  /// doesn't decide it, and the fact is left out. So is any profile whose
  /// `Platform` lists `OSX`: macOS profiles use these keys differently
  /// (a Developer ID profile also provisions all devices), so they don't
  /// say which kind a macOS profile is.
  static const profileType = 'profile_type';

  /// How many entries `ProvisionedDevices` has. Only present when the
  /// profile has that key. The device ids themselves aren't reported.
  static const deviceCount = 'device_count';

  /// The SHA-1 fingerprint of each `DeveloperCertificates` entry, upper-case
  /// colon hex as `openssl x509 -fingerprint -sha1` prints it, one per line,
  /// in file order. Entries that aren't X.509 certificates are skipped with
  /// a warning.
  static const developerCertificates = 'developer_certificates';

  /// [profileType] values.
  static const enterprise = 'Enterprise (In-House)';
  static const development = 'Development';
  static const adHoc = 'Ad Hoc';
  static const appStore = 'App Store';

  @override
  Set<CredentialFormat> get formats => const {CredentialFormat.mobileProvision};

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) {
    final plist = parseXmlPlist(decodeUtf8(signedContent(input.bytes)));
    if (plist is! Map<String, Object>) {
      throw const FormatException('Profile plist is not a dictionary');
    }

    final entitlements = readMap(plist, 'Entitlements') ?? const {};
    final teams = readStrings(plist, 'TeamIdentifier');
    final prefixes = readStrings(plist, 'ApplicationIdentifierPrefix');
    final appIdentifier =
        readString(entitlements, 'application-identifier') ??
        readString(entitlements, 'com.apple.application-identifier');
    final platforms = readStrings(plist, 'Platform');
    final created = _readDate(plist, 'CreationDate');
    final expires = _readDate(plist, 'ExpirationDate');

    final devices = plist['ProvisionedDevices'];
    if (devices != null && devices is! List) {
      throw const FormatException('Unexpected value type for a known key');
    }
    final allDevices = _readBool(plist, 'ProvisionsAllDevices');
    final getTaskAllow = _readBool(entitlements, 'get-task-allow');

    final certs = plist['DeveloperCertificates'] ?? const <Object>[];
    if (certs is! List) {
      throw const FormatException('Unexpected value type for a known key');
    }
    final fingerprints = <String>[];
    var unreadable = 0;
    for (final Object? blob in certs) {
      try {
        if (blob is! Uint8List) throw const FormatException('not <data>');
        fingerprints.add(X509Certificate.parse(blob).sha1Fingerprint);
      } on FormatException {
        unreadable++;
      }
    }

    final facts = <String, ItemField>{};
    putFact(facts, name, readString(plist, 'Name'));
    putFact(facts, uuid, readString(plist, 'UUID'));
    putFact(facts, teamId, teams?.join('\n'));
    putFact(facts, teamName, readString(plist, 'TeamName'));
    putFact(facts, appIdName, readString(plist, 'AppIDName'));
    if (appIdentifier != null) {
      putFact(
        facts,
        bundleId,
        _bundleId(appIdentifier, {...?teams, ...?prefixes}),
      );
      putFact(facts, applicationIdentifier, appIdentifier);
    }
    putFact(facts, platform, platforms?.join(', '));
    putFact(
      facts,
      creationDate,
      created == null ? null : formatTimestamp(created),
    );
    putFact(
      facts,
      expirationDate,
      expires == null ? null : formatTimestamp(expires),
    );
    putFact(
      facts,
      profileType,
      _profileType(
        macOS: platforms?.contains('OSX') ?? false,
        allDevices: allDevices,
        hasDevices: devices != null,
        getTaskAllow: getTaskAllow,
      ),
    );
    if (devices is List) putFact(facts, deviceCount, '${devices.length}');
    if (fingerprints.isNotEmpty) {
      putFact(facts, developerCertificates, fingerprints.join('\n'));
    }

    return ParseResult(
      type: ItemType.provisioningProfile,
      format: format,
      facts: facts,
      expiresAt: expires,
      warnings: [
        if (unreadable > 0)
          '$unreadable of the developer certificates in this profile could '
              'not be read and are not listed.',
      ],
    );
  }

  /// The content of the CMS SignedData in [bytes]: ContentInfo → `[0]` →
  /// SignedData → encapContentInfo → `[0]` → OCTET STRING. A constructed
  /// (BER) OCTET STRING is reassembled from its chunks. The signature is
  /// not looked at.
  static Uint8List signedContent(Uint8List bytes) {
    final contentInfo = Asn1.parse(
      bytes,
      allowTrailing: true,
    ).expect(Asn1.tagSequence);
    if (contentInfo[0].oid != _oidSignedData) {
      throw const FormatException('Not CMS SignedData');
    }
    final signedData = contentInfo[1].explicit(0).expect(Asn1.tagSequence);
    final encap = signedData[2].expect(Asn1.tagSequence);
    if (encap[0].oid != _oidData) {
      throw const FormatException('CMS content is not data');
    }
    if (encap.children.length != 2) {
      throw const FormatException('CMS content is missing');
    }
    final out = BytesBuilder(copy: false);
    _octets(encap[1].explicit(0), out);
    if (out.length > maxConfigBytes) {
      throw const FormatException('File too large');
    }
    return out.takeBytes();
  }

  static void _octets(Asn1 value, BytesBuilder out) {
    if (value.tag == Asn1.tagOctetString) {
      out.add(value.octets);
    } else if (value.tag == Asn1.tagOctetString | 0x20) {
      for (final chunk in value.children) {
        _octets(chunk, out);
      }
    } else {
      throw const FormatException('CMS content is not an OCTET STRING');
    }
  }

  static String _bundleId(String appIdentifier, Set<String> prefixes) {
    final dot = appIdentifier.indexOf('.');
    if (dot <= 0) return appIdentifier;
    final rest = appIdentifier.substring(dot + 1);
    return prefixes.contains(appIdentifier.substring(0, dot)) && rest.isNotEmpty
        ? rest
        : appIdentifier;
  }

  /// See [profileType] for the rules.
  static String? _profileType({
    required bool macOS,
    required bool? allDevices,
    required bool hasDevices,
    required bool? getTaskAllow,
  }) {
    if (macOS) return null;
    if (allDevices == true) return enterprise;
    if (hasDevices) return getTaskAllow == true ? development : adHoc;
    if (getTaskAllow != true) return appStore;
    return null;
  }

  static bool? _readBool(Map<String, Object?> map, String key) {
    final value = map[key];
    return switch (value) {
      null => null,
      bool() => value,
      _ => throw const FormatException('Unexpected value type for a known key'),
    };
  }

  static DateTime? _readDate(Map<String, Object?> map, String key) {
    final value = map[key];
    return switch (value) {
      null => null,
      DateTime() => value,
      _ => throw const FormatException('Unexpected value type for a known key'),
    };
  }

  static const _oidSignedData = '1.2.840.113549.1.7.2';
  static const _oidData = '1.2.840.113549.1.7.1';
}
