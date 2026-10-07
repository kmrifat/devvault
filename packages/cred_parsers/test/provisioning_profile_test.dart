import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cred_parsers/cred_parsers.dart';
import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

ParseResult parse(String name, [Uint8List? bytes]) =>
    CredentialParsers.standard().parse(
      ParseInput(filename: name, bytes: bytes ?? fixture(name)),
    );

Map<String, String> values(ParseResult result) => {
  for (final MapEntry(:key, :value) in result.facts.entries) key: value.value,
};

/// `openssl x509 -inform DER -in apple_development.cer -noout -fingerprint
/// -sha1`.
const devCertSha1 =
    '28:7D:5F:BF:40:5D:6F:E1:11:F1:70:7E:73:28:B3:9D:AF:E7:BF:82';

typedef P = ProvisioningProfileParser;

// A minimal DER/BER writer, so edge cases can be built without openssl.
// These profiles carry no signature at all, which the parser never reads.
List<int> _len(int n) {
  if (n < 0x80) return [n];
  final bytes = <int>[];
  for (var v = n; v > 0; v >>= 8) {
    bytes.insert(0, v & 0xFF);
  }
  return [0x80 | bytes.length, ...bytes];
}

List<int> tlv(int tag, List<int> content) => [
  tag,
  ..._len(content.length),
  ...content,
];
List<int> indefinite(int tag, List<List<int>> parts) => [
  tag,
  0x80,
  for (final p in parts) ...p,
  0,
  0,
];
List<int> oid(List<int> encoded) => tlv(0x06, encoded);
final signedDataOid = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 2]);
final dataOid = oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 1]);

/// ContentInfo(SignedData) around [eContent], which is the encoded
/// OCTET STRING (primitive or constructed).
Uint8List cms(List<int> eContent) => Uint8List.fromList(
  tlv(0x30, [
    ...signedDataOid,
    ...tlv(0xA0, [
      ...tlv(0x30, [
        ...tlv(0x02, [1]),
        ...tlv(0x31, []),
        ...tlv(0x30, [...dataOid, ...tlv(0xA0, eContent)]),
        ...tlv(0x31, []),
      ]),
    ]),
  ]),
);

/// A profile whose plist dict holds [body] (already-written XML).
Uint8List profile(String body) => cms(tlv(0x04, utf8.encode(plist(body))));

String plist(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<plist version="1.0"><dict>$body</dict></plist>\n';

String strings(String key, List<String> values) =>
    '<key>$key</key><array>'
    '${values.map((v) => '<string>$v</string>').join()}</array>';

String entitlements(String appId, {bool? getTaskAllow, String? key}) =>
    '<key>Entitlements</key><dict>'
    '<key>${key ?? 'application-identifier'}</key><string>$appId</string>'
    '${getTaskAllow == null ? '' : '<key>get-task-allow</key><$getTaskAllow/>'}'
    '</dict>';

const devices =
    '<key>ProvisionedDevices</key><array><string>a</string></array>';

void main() {
  group('fixtures', () {
    test('development: devices and get-task-allow', () {
      final result = parse('development.mobileprovision');
      expect(result.type, ItemType.provisioningProfile);
      expect(result.format, CredentialFormat.mobileProvision);
      expect(result.isGeneric, isFalse);
      expect(result.warnings, isEmpty);
      expect(values(result), {
        P.name: 'DevVault Test Development',
        P.uuid: '00000000-0000-4000-8000-000000000001',
        P.teamId: 'TESTTEAM01',
        P.teamName: 'DevVault Tests',
        P.appIdName: 'DevVault Test App',
        P.bundleId: 'com.example.devvault',
        P.applicationIdentifier: 'TESTTEAM01.com.example.devvault',
        P.platform: 'iOS, xrOS, visionOS',
        P.creationDate: '2026-10-07T00:00:00Z',
        P.expirationDate: '2027-10-07T00:00:00Z',
        P.profileType: 'Development',
        P.deviceCount: '3',
        P.developerCertificates: devCertSha1,
      });
      expect(result.expiresAt, DateTime.utc(2027, 10, 7));
      expect(
        result.facts.values.every((f) => f.source == FieldSource.file),
        isTrue,
      );
      expect(result.facts.values.any((f) => f.secret), isFalse);
    });

    test('ad hoc: devices without get-task-allow', () {
      final facts = values(parse('adhoc.mobileprovision'));
      expect(facts[P.profileType], 'Ad Hoc');
      expect(facts[P.deviceCount], '3');
      expect(facts[P.name], 'DevVault Test Ad Hoc');
    });

    test('app store: no devices, no get-task-allow', () {
      final facts = values(parse('appstore.mobileprovision'));
      expect(facts[P.profileType], 'App Store');
      expect(facts, isNot(contains(P.deviceCount)));
    });

    test('enterprise: ProvisionsAllDevices', () {
      final facts = values(parse('enterprise.mobileprovision'));
      expect(facts[P.profileType], 'Enterprise (In-House)');
      expect(facts, isNot(contains(P.deviceCount)));
    });

    test('wildcard App ID keeps the *', () {
      final facts = values(parse('wildcard.mobileprovision'));
      expect(facts[P.bundleId], '*');
      expect(facts[P.applicationIdentifier], 'TESTTEAM01.*');
      expect(facts[P.profileType], 'Development');
    });

    test('BER: indefinite lengths and a chunked OCTET STRING', () {
      final ber = parse('development-ber.mobileprovision');
      final der = parse('development.mobileprovision');
      expect(ber.type, ItemType.provisioningProfile);
      expect(ber.facts, der.facts);
      expect(ber.expiresAt, der.expiresAt);
    });

    test('the existing minimal profiles, DER and BER', () {
      for (final name in ['test.mobileprovision', 'ber.mobileprovision']) {
        final result = parse(name);
        expect(result.type, ItemType.provisioningProfile, reason: name);
        expect(values(result), {
          P.name: 'DevVault Test Profile',
          // No device list and no get-task-allow.
          P.profileType: 'App Store',
        }, reason: name);
        expect(result.expiresAt, isNull, reason: name);
      }
    });

    test('the developer certificate SHA-1 matches openssl', () {
      final cert = X509Certificate.parse(fixture('apple_development.cer'));
      expect(cert.sha1Fingerprint, devCertSha1);
    });
  });

  test('never claims the profile was verified', () {
    final banned = RegExp(r'valid|verif|signed by apple', caseSensitive: false);
    final results = [
      for (final name in [
        'development.mobileprovision',
        'development-ber.mobileprovision',
        'adhoc.mobileprovision',
        'appstore.mobileprovision',
        'enterprise.mobileprovision',
        'wildcard.mobileprovision',
        'test.mobileprovision',
      ])
        parse(name),
      parse(
        'x.mobileprovision',
        profile(
          '<key>DeveloperCertificates</key><array><data>AAAA</data></array>',
        ),
      ),
    ];
    for (final result in results) {
      for (final MapEntry(:key, :value) in result.facts.entries) {
        expect(key, isNot(matches(banned)));
        expect(value.value, isNot(matches(banned)));
      }
      for (final warning in result.warnings) {
        expect(warning, isNot(matches(banned)));
      }
    }
  });

  group('plist rules', () {
    test('the prefix is kept unless it is the team or app id prefix', () {
      final other = values(
        parse(
          'x.mobileprovision',
          profile(
            '${strings('TeamIdentifier', ['TESTTEAM01'])}'
            '${entitlements('OTHERTEAM9.com.example.app')}',
          ),
        ),
      );
      expect(other[P.bundleId], 'OTHERTEAM9.com.example.app');

      final legacyPrefix = values(
        parse(
          'x.mobileprovision',
          profile(
            '${strings('TeamIdentifier', ['TESTTEAM01'])}'
            '${strings('ApplicationIdentifierPrefix', ['LEGACYPFX1'])}'
            '${entitlements('LEGACYPFX1.com.example.app')}',
          ),
        ),
      );
      expect(legacyPrefix[P.bundleId], 'com.example.app');

      final noTeam = values(
        parse('x.mobileprovision', profile(entitlements('A.b'))),
      );
      expect(noTeam[P.bundleId], 'A.b');
    });

    test('several teams are all listed, none picked', () {
      final facts = values(
        parse(
          'x.mobileprovision',
          profile(strings('TeamIdentifier', ['TEAMAAAAAA', 'TEAMBBBBBB'])),
        ),
      );
      expect(facts[P.teamId], 'TEAMAAAAAA\nTEAMBBBBBB');
    });

    test('get-task-allow without devices does not decide the type', () {
      final facts = values(
        parse(
          'x.mobileprovision',
          profile(entitlements('T.x', getTaskAllow: true)),
        ),
      );
      expect(facts, isNot(contains(P.profileType)));
    });

    test('ProvisionsAllDevices wins over a device list', () {
      final facts = values(
        parse(
          'x.mobileprovision',
          profile(
            '$devices<key>ProvisionsAllDevices</key><true/>'
            '${entitlements('T.x', getTaskAllow: true)}',
          ),
        ),
      );
      expect(facts[P.profileType], 'Enterprise (In-House)');
      expect(facts[P.deviceCount], '1');
    });

    test('macOS profiles get no type; their app id key is read', () {
      final facts = values(
        parse(
          'x.mobileprovision',
          profile(
            '${strings('Platform', ['OSX'])}'
            '${strings('TeamIdentifier', ['TESTTEAM01'])}'
            '<key>ProvisionsAllDevices</key><true/>'
            '${entitlements('TESTTEAM01.com.example.mac', key: 'com.apple.application-identifier')}',
          ),
        ),
      );
      expect(facts, isNot(contains(P.profileType)));
      expect(facts[P.bundleId], 'com.example.mac');
      expect(facts[P.platform], 'OSX');
    });

    test('a developer certificate that is not X.509 is skipped', () {
      final cert = base64.encode(fixture('apple_development.cer'));
      final result = parse(
        'x.mobileprovision',
        profile(
          '<key>DeveloperCertificates</key><array>'
          '<data>AAAA</data><data>$cert</data></array>',
        ),
      );
      expect(result.type, ItemType.provisioningProfile);
      expect(values(result)[P.developerCertificates], devCertSha1);
      expect(result.warnings.single, contains('1 of the developer'));
    });

    test('nested BER chunks are joined in order', () {
      final text = utf8.encode(
        plist('<key>Name</key><string>Chunked</string>'),
      );
      final a = text.sublist(0, 10);
      final b = text.sublist(10, 50);
      final c = text.sublist(50);
      final bytes = cms(
        indefinite(0x24, [
          tlv(0x04, a),
          indefinite(0x24, [tlv(0x04, b)]),
          tlv(0x04, c),
        ]),
      );
      expect(values(parse('x.mobileprovision', bytes))[P.name], 'Chunked');
    });
  });

  group('unreadable profiles are generic and never throw', () {
    void expectGeneric(Uint8List bytes) {
      final result = parse('x.mobileprovision', bytes);
      expect(result.isGeneric, isTrue);
      expect(result.facts, isEmpty);
      expect(result.expiresAt, isNull);
    }

    test('truncated', () {
      final bytes = fixture('development.mobileprovision');
      for (var cut = 0; cut < bytes.length; cut += 7) {
        final result = parse(
          'x.mobileprovision',
          Uint8List.sublistView(bytes, 0, cut),
        );
        // A cut past the plist leaves a readable profile; otherwise generic.
        if (!result.isGeneric) {
          expect(result.facts[P.name]!.value, 'DevVault Test Development');
        }
      }
      expectGeneric(Uint8List.sublistView(bytes, 0, bytes.length ~/ 3));
    });

    test('a corrupt plist', () {
      expectGeneric(cms(tlv(0x04, utf8.encode('<plist><dict><key>'))));
      expectGeneric(profile('<key>Name</key><integer>x</integer>'));
    });

    test('a known key with the wrong type', () {
      expectGeneric(profile('<key>Name</key><array/>'));
      expectGeneric(profile('<key>ExpirationDate</key><string>x</string>'));
      expectGeneric(
        profile('<key>ProvisionsAllDevices</key><string>1</string>'),
      );
    });

    test('a plist that is not a dictionary', () {
      expectGeneric(
        cms(tlv(0x04, utf8.encode('<plist><array></array></plist>'))),
      );
    });

    test('content that is not data, or not an OCTET STRING', () {
      expectGeneric(
        Uint8List.fromList(
          tlv(0x30, [
            ...signedDataOid,
            ...tlv(0xA0, [
              ...tlv(0x30, [
                ...tlv(0x02, [1]),
                ...tlv(0x31, []),
                ...tlv(0x30, [
                  ...signedDataOid,
                  ...tlv(0xA0, tlv(0x04, utf8.encode(plist('')))),
                ]),
              ]),
            ]),
          ]),
        ),
      );
      expectGeneric(cms(tlv(0x0C, utf8.encode(plist('')))));
    });
  });
}
