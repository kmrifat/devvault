import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cred_parsers/cred_parsers.dart';
import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

final parsers = CredentialParsers.standard();

ParseResult parseFixture(String name, {String? choice}) => parsers.parse(
  ParseInput(filename: name, bytes: fixture(name), choice: choice),
);

ParseResult parseText(String name, String text, {String? choice}) =>
    parsers.parse(
      ParseInput(
        filename: name,
        bytes: Uint8List.fromList(utf8.encode(text)),
        choice: choice,
      ),
    );

/// Field key → value, for compact expectations.
Map<String, String> values(ParseResult r) => {
  for (final MapEntry(:key, :value) in r.facts.entries) key: value.value,
};

/// Keys of the facts marked secret.
Set<String> secretKeys(ParseResult r) => {
  for (final MapEntry(:key, :value) in r.facts.entries)
    if (value.secret) key,
};

const oauthInstalled =
    'client_secret_000000000000-test.apps.googleusercontent.com.json';
const oauthWeb =
    'client_secret_000000000000-web.apps.googleusercontent.com.json';

void main() {
  test('the standard registry reads every Google format', () {
    expect(
      parsers.supportedFormats,
      containsAll([
        CredentialFormat.googleServicesJson,
        CredentialFormat.googleServiceInfoPlist,
        CredentialFormat.serviceAccountJson,
        CredentialFormat.oauthClientJson,
      ]),
    );
  });

  test('no Google config reports an expiry or a source but the file', () {
    for (final name in [
      'google-services.json',
      'google-services.multi.json',
      'GoogleService-Info.plist',
      'service-account.json',
      oauthInstalled,
      oauthWeb,
    ]) {
      final r = parseFixture(name);
      expect(r.isGeneric, isFalse, reason: name);
      expect(r.expiresAt, isNull, reason: name);
      expect(r.secretsNeeded, isEmpty, reason: name);
      for (final fact in r.facts.values) {
        expect(fact.source, FieldSource.file, reason: name);
      }
    }
  });

  group('google-services.json', () {
    test('a single app reports project and app facts', () {
      final r = parseFixture('google-services.json');
      expect(r.type, ItemType.firebaseConfig);
      expect(r.format, CredentialFormat.googleServicesJson);
      expect(values(r), {
        FirebaseConfigParser.projectId: 'devvault-test',
        FirebaseConfigParser.projectNumber: '000000000000',
        FirebaseConfigParser.storageBucket: 'devvault-test.appspot.com',
        FirebaseConfigParser.appId: '1:000000000000:android:0000000000000000',
        FirebaseConfigParser.packageName: 'dev.devvault.test',
        FirebaseConfigParser.apiKey: 'TEST-NOT-A-REAL-KEY',
      });
      expect(secretKeys(r), isEmpty, reason: 'Firebase API keys are public');
      expect(r.options, isEmpty);
      expect(r.chosen, isNull);
      expect(r.needsChoice, isFalse);
      expect(r.warnings, isEmpty);
    });

    group('several apps', () {
      const app1 = '1:000000000000:android:1111111111111111';
      const app2 = '1:000000000000:android:2222222222222222';
      const project = {
        FirebaseConfigParser.projectId: 'devvault-test',
        FirebaseConfigParser.projectNumber: '000000000000',
        FirebaseConfigParser.storageBucket: 'devvault-test.appspot.com',
        FirebaseConfigParser.databaseUrl:
            'https://devvault-test-default-rtdb.firebaseio.com',
      };

      test('offer each app and report only project facts', () {
        final r = parseFixture('google-services.multi.json');
        expect(r.type, ItemType.firebaseConfig);
        expect(r.options, const [
          ParseOption(id: app1, label: 'dev.devvault.app'),
          ParseOption(id: app2, label: 'dev.devvault.app.staging'),
        ]);
        expect(r.needsChoice, isTrue);
        expect(r.chosen, isNull);
        expect(values(r), project);
        expect(r.warnings, isEmpty);
      });

      test('a choice adds that app\'s facts', () {
        final r = parseFixture('google-services.multi.json', choice: app2);
        expect(r.chosen, app2);
        expect(r.needsChoice, isFalse);
        expect(r.options, hasLength(2));
        expect(values(r), {
          ...project,
          FirebaseConfigParser.appId: app2,
          FirebaseConfigParser.packageName: 'dev.devvault.app.staging',
          FirebaseConfigParser.apiKey: 'TEST-NOT-A-REAL-KEY-2',
        });
      });

      test('a choice not in the file is a warning, not a guess', () {
        final r = parseFixture(
          'google-services.multi.json',
          choice: '1:000000000000:android:9999999999999999',
        );
        expect(r.isGeneric, isFalse);
        expect(r.chosen, isNull);
        expect(r.needsChoice, isTrue);
        expect(values(r), project);
        expect(r.warnings.single, contains('not in this file'));
      });

      test('a choice is ignored when there is only one app', () {
        final r = parseFixture('google-services.json', choice: app1);
        expect(r.chosen, isNull);
        expect(
          r.facts[FirebaseConfigParser.appId]!.value,
          '1:000000000000:android:0000000000000000',
        );
      });
    });

    test('a client without a package name is labelled by its app id', () {
      final r = parseText('google-services.json', '''
{"project_info": {"project_id": "p"},
 "client": [
   {"client_info": {"mobilesdk_app_id": "1:0:android:a"}},
   {"client_info": {"mobilesdk_app_id": "1:0:android:b",
                    "android_client_info": {"package_name": "b.app"}}}
 ]}''');
      expect(r.options.map((o) => o.label), ['1:0:android:a', 'b.app']);
    });

    test('several API keys for one app are not picked from', () {
      final r = parseText('google-services.json', '''
{"project_info": {"project_id": "p"},
 "client": [{"client_info": {"mobilesdk_app_id": "1:0:android:a"},
             "api_key": [{"current_key": "K1"}, {"current_key": "K2"}]}]}''');
      expect(r.facts, isNot(contains(FirebaseConfigParser.apiKey)));
      expect(r.warnings.single, contains('2 API keys'));
      expect(r.warnings.single, isNot(contains('K1')));
    });

    test('no apps reports the project and says so', () {
      final r = parseText(
        'google-services.json',
        '{"project_info": {"project_id": "p", "project_number": 123}, '
            '"client": []}',
      );
      expect(values(r), {
        FirebaseConfigParser.projectId: 'p',
        FirebaseConfigParser.projectNumber: '123',
      });
      expect(r.warnings.single, contains('no apps'));
    });

    test('malformed files fall back to a generic file', () {
      for (final text in [
        // A client with no app id.
        '{"project_info": {"project_id": "p"}, "client": [{}]}',
        // Two clients with the same app id.
        '{"project_info": {}, "client": ['
            '{"client_info": {"mobilesdk_app_id": "a"}},'
            '{"client_info": {"mobilesdk_app_id": "a"}}]}',
        // A known key with the wrong type.
        '{"project_info": {"project_id": ["p"]}, "client": []}',
        // Nothing to report.
        '{"project_info": {}, "client": []}',
      ]) {
        final r = parseText('google-services.json', text);
        expect(r.isGeneric, isTrue, reason: text);
        expect(r.format, CredentialFormat.googleServicesJson);
        expect(r.facts, isEmpty);
      }
    });
  });

  group('GoogleService-Info.plist', () {
    test('reports the Firebase keys', () {
      final r = parseFixture('GoogleService-Info.plist');
      expect(r.type, ItemType.firebaseConfig);
      expect(r.format, CredentialFormat.googleServiceInfoPlist);
      expect(values(r), {
        FirebaseConfigParser.projectId: 'devvault-test',
        FirebaseConfigParser.appId: '1:000000000000:ios:0000000000000000',
        FirebaseConfigParser.bundleId: 'dev.devvault.test',
        FirebaseConfigParser.apiKey: 'TEST-NOT-A-REAL-KEY',
        FirebaseConfigParser.gcmSenderId: '000000000000',
        FirebaseConfigParser.storageBucket: 'devvault-test.appspot.com',
        FirebaseConfigParser.clientId:
            '000000000000-ios.apps.googleusercontent.com',
        FirebaseConfigParser.reversedClientId:
            'com.googleusercontent.apps.000000000000-ios',
      });
      expect(secretKeys(r), isEmpty);
      expect(r.options, isEmpty);
    });

    test('a binary plist is detected but imports as a generic file', () {
      const name = 'GoogleService-Info.binary.plist';
      expect(
        detectFormat(name, fixture(name)),
        CredentialFormat.googleServiceInfoPlist,
      );
      final r = parseFixture(name);
      expect(r.isGeneric, isTrue);
      expect(r.format, CredentialFormat.googleServiceInfoPlist);
      expect(r.facts, isEmpty);
      expect(r.warnings.single, contains('could not be read'));
    });

    test('a plist with no Firebase keys, or odd types, is generic', () {
      for (final body in [
        '<dict><key>OTHER</key><string>x</string></dict>',
        '<array><string>x</string></array>',
        '<dict><key>GOOGLE_APP_ID</key><integer>1</integer></dict>',
      ]) {
        final r = parseText(
          'GoogleService-Info.plist',
          '<?xml version="1.0"?><plist>$body</plist>',
        );
        expect(r.isGeneric, isTrue, reason: body);
        expect(r.facts, isEmpty);
      }
    });
  });

  group('service-account JSON', () {
    test('reports the account and keeps the private key secret', () {
      final r = parseFixture('service-account.json');
      expect(r.type, ItemType.gcpServiceAccount);
      expect(r.format, CredentialFormat.serviceAccountJson);
      expect(values(r), {
        ServiceAccountParser.projectId: 'devvault-test',
        ServiceAccountParser.clientEmail:
            'test@devvault-test.iam.gserviceaccount.com',
        ServiceAccountParser.clientId: '000000000000000000000',
        ServiceAccountParser.privateKeyId:
            '0000000000000000000000000000000000000000',
        ServiceAccountParser.privateKey:
            '-----BEGIN PRIVATE KEY-----\nTEST-NOT-A-REAL-KEY\n'
            '-----END PRIVATE KEY-----\n',
      });
      expect(secretKeys(r), {ServiceAccountParser.privateKey});
      expect(r.toString(), isNot(contains('TEST-NOT-A-REAL-KEY')));
    });

    test('missing fields stay missing', () {
      final r = parseText(
        'key.json',
        '{"type": "service_account", "client_email": "a@b.test", '
            '"private_key": ""}',
      );
      expect(values(r), {ServiceAccountParser.clientEmail: 'a@b.test'});
    });
  });

  group('OAuth client JSON', () {
    test('an installed client', () {
      final r = parseFixture(oauthInstalled);
      expect(r.type, ItemType.oauthClient);
      expect(r.format, CredentialFormat.oauthClientJson);
      expect(values(r), {
        OAuthClientParser.clientType: 'installed',
        OAuthClientParser.clientId:
            '000000000000-test.apps.googleusercontent.com',
        OAuthClientParser.clientSecret: 'TEST-NOT-A-REAL-SECRET',
        OAuthClientParser.projectId: 'devvault-test',
        OAuthClientParser.redirectUris: 'http://localhost',
      });
      expect(secretKeys(r), {OAuthClientParser.clientSecret});
    });

    test('a web client lists its URIs one per line', () {
      final r = parseFixture(oauthWeb);
      expect(values(r), {
        OAuthClientParser.clientType: 'web',
        OAuthClientParser.clientId:
            '000000000000-web.apps.googleusercontent.com',
        OAuthClientParser.clientSecret: 'TEST-NOT-A-REAL-SECRET',
        OAuthClientParser.projectId: 'devvault-test',
        OAuthClientParser.redirectUris:
            'https://devvault.test/oauth/callback\n'
            'http://localhost:8080/callback',
        OAuthClientParser.javascriptOrigins: 'https://devvault.test',
      });
      expect(secretKeys(r), {OAuthClientParser.clientSecret});
    });

    test('both client kinds at once is not picked from', () {
      final r = parseText(
        'client_secret_x.json',
        '{"installed": {"client_id": "a"}, "web": {"client_id": "b"}}',
      );
      expect(r.isGeneric, isTrue);
      expect(r.format, CredentialFormat.oauthClientJson);
    });

    test('a non-string redirect URI is a malformed file', () {
      final r = parseText(
        'client_secret_x.json',
        '{"web": {"client_id": "a", "redirect_uris": [1]}}',
      );
      expect(r.isGeneric, isTrue);
      expect(r.facts, isEmpty);
    });
  });

  group('choice API', () {
    test('ParseResult rejects duplicate option ids and unknown choices', () {
      const a = ParseOption(id: 'a', label: 'A');
      expect(
        () => ParseResult(
          type: ItemType.firebaseConfig,
          format: CredentialFormat.googleServicesJson,
          options: const [
            a,
            ParseOption(id: 'a', label: 'B'),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => ParseResult(
          type: ItemType.firebaseConfig,
          format: CredentialFormat.googleServicesJson,
          options: const [a],
          chosen: 'b',
        ),
        throwsArgumentError,
      );
    });

    test('options are unmodifiable', () {
      final r = parseFixture('google-services.multi.json');
      expect(
        () => r.options.add(const ParseOption(id: 'x', label: 'x')),
        throwsUnsupportedError,
      );
    });

    test('toString never prints option ids, labels or the choice', () {
      final r = parseFixture(
        'google-services.multi.json',
        choice: '1:000000000000:android:1111111111111111',
      );
      final printed = [
        r.toString(),
        r.options.first.toString(),
        ParseInput(
          filename: 'google-services.json',
          bytes: Uint8List(0),
          choice: '1:000000000000:android:1111111111111111',
        ).toString(),
      ].join();
      expect(printed, isNot(contains('1111111111111111')));
      expect(printed, isNot(contains('dev.devvault.app')));
      expect(r.toString(), contains('options: 2, chosen'));
    });

    test('the choice survives the trip to an isolate', () async {
      const app2 = '1:000000000000:android:2222222222222222';
      final r = await parsers.parseInIsolate(
        ParseInput(
          filename: 'google-services.multi.json',
          bytes: fixture('google-services.multi.json'),
          choice: app2,
        ),
      );
      expect(r.chosen, app2);
      expect(r.facts[FirebaseConfigParser.appId]!.value, app2);
    });
  });
}
