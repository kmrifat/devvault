import 'package:vault_core/vault_core.dart';

import '../detect.dart';
import '../parse_result.dart';
import '../parsers.dart';
import '../plist.dart';
import 'common.dart';

/// Reads Firebase app configs: Android `google-services.json` and iOS
/// `GoogleService-Info.plist`. Neither states an expiry (SPEC §6.5).
///
/// A `google-services.json` can list several Android apps. With one, its
/// facts are reported. With several, the result carries the project facts
/// plus one [ParseOption] per app (id = `mobilesdk_app_id`, label = package
/// name); parse again with [ParseInput.choice] to add that app's facts.
///
/// Firebase API keys identify the project and are not secrets (Google
/// ships them inside every app), so [apiKey] is not marked secret.
class FirebaseConfigParser implements CredentialParser {
  const FirebaseConfigParser();

  /// `project_info.project_id` / `PROJECT_ID`.
  static const projectId = 'project_id';

  /// `project_info.project_number` (JSON only).
  static const projectNumber = 'project_number';

  /// `project_info.storage_bucket` / `STORAGE_BUCKET`.
  static const storageBucket = 'storage_bucket';

  /// `project_info.firebase_url` / `DATABASE_URL`.
  static const databaseUrl = 'database_url';

  /// The app's Firebase id: `client_info.mobilesdk_app_id` /
  /// `GOOGLE_APP_ID`.
  static const appId = 'app_id';

  /// `android_client_info.package_name` (JSON only).
  static const packageName = 'package_name';

  /// `BUNDLE_ID` (plist only).
  static const bundleId = 'bundle_id';

  /// `api_key[].current_key` / `API_KEY`. Not secret.
  static const apiKey = 'api_key';

  /// `GCM_SENDER_ID` (plist only).
  static const gcmSenderId = 'gcm_sender_id';

  /// `CLIENT_ID` (plist only): the app's OAuth client id.
  static const clientId = 'client_id';

  /// `REVERSED_CLIENT_ID` (plist only).
  static const reversedClientId = 'reversed_client_id';

  @override
  Set<CredentialFormat> get formats => const {
    CredentialFormat.googleServicesJson,
    CredentialFormat.googleServiceInfoPlist,
  };

  @override
  ParseResult parse(ParseInput input, CredentialFormat format) =>
      switch (format) {
        CredentialFormat.googleServicesJson => _parseJson(input),
        CredentialFormat.googleServiceInfoPlist => _parsePlist(input),
        _ => throw ArgumentError.value(format, 'format'),
      };

  ParseResult _parseJson(ParseInput input) {
    final json = decodeJsonObject(input.bytes);
    final project = readMap(json, 'project_info');
    final clientList = json['client'];
    if (project == null || clientList is! List) {
      throw const FormatException('Not a google-services.json');
    }

    final facts = <String, ItemField>{};
    putFact(facts, projectId, readString(project, 'project_id'));
    putFact(facts, projectNumber, readString(project, 'project_number'));
    putFact(facts, storageBucket, readString(project, 'storage_bucket'));
    putFact(facts, databaseUrl, readString(project, 'firebase_url'));

    final clients = [for (final c in clientList) _Client.read(c)];
    final warnings = <String>[];
    if (clients.isEmpty) warnings.add('This file lists no apps.');

    final options = clients.length > 1
        ? [
            for (final c in clients)
              ParseOption(id: c.appId, label: c.packageName ?? c.appId),
          ]
        : const <ParseOption>[];
    if (options.map((o) => o.id).toSet().length != options.length) {
      throw const FormatException('Duplicate app ids');
    }

    _Client? client;
    if (clients.length == 1) {
      client = clients.single;
    } else if (input.choice != null) {
      client = clients.where((c) => c.appId == input.choice).firstOrNull;
      if (client == null) {
        warnings.add('The chosen app is not in this file.');
      }
    }
    if (client != null) {
      putFact(facts, appId, client.appId);
      putFact(facts, packageName, client.packageName);
      putFact(facts, apiKey, client.apiKey);
      if (client.apiKeyCount > 1) {
        warnings.add(
          'This app lists ${client.apiKeyCount} API keys; '
          'none was recorded.',
        );
      }
    }

    if (facts.isEmpty) throw const FormatException('No facts');
    return ParseResult(
      type: ItemType.firebaseConfig,
      format: CredentialFormat.googleServicesJson,
      facts: facts,
      warnings: warnings,
      options: options,
      chosen: options.isEmpty ? null : client?.appId,
    );
  }

  ParseResult _parsePlist(ParseInput input) {
    final plist = parseXmlPlist(decodeUtf8(input.bytes));
    if (plist is! Map<String, Object>) {
      throw const FormatException('Expected a dictionary');
    }
    String? string(String key) {
      final value = plist[key];
      if (value == null) return null;
      if (value is! String) {
        throw const FormatException('Unexpected value type for a known key');
      }
      return value.isEmpty ? null : value;
    }

    final facts = <String, ItemField>{};
    putFact(facts, projectId, string('PROJECT_ID'));
    putFact(facts, appId, string('GOOGLE_APP_ID'));
    putFact(facts, bundleId, string('BUNDLE_ID'));
    putFact(facts, apiKey, string('API_KEY'));
    putFact(facts, gcmSenderId, string('GCM_SENDER_ID'));
    putFact(facts, storageBucket, string('STORAGE_BUCKET'));
    putFact(facts, databaseUrl, string('DATABASE_URL'));
    putFact(facts, clientId, string('CLIENT_ID'));
    putFact(facts, reversedClientId, string('REVERSED_CLIENT_ID'));
    if (facts.isEmpty) throw const FormatException('No Firebase keys');

    return ParseResult(
      type: ItemType.firebaseConfig,
      format: CredentialFormat.googleServiceInfoPlist,
      facts: facts,
    );
  }
}

/// One entry of `google-services.json`'s `client` array.
class _Client {
  _Client(this.appId, this.packageName, this.apiKey, this.apiKeyCount);

  factory _Client.read(Object? entry) {
    if (entry is! Map<String, Object?>) {
      throw const FormatException('Malformed client entry');
    }
    final info = readMap(entry, 'client_info');
    final appId = info == null ? null : readString(info, 'mobilesdk_app_id');
    if (info == null || appId == null) {
      throw const FormatException('Client without an app id');
    }
    final android = readMap(info, 'android_client_info');

    final keyList = entry['api_key'];
    final keys = <String>{};
    if (keyList != null) {
      if (keyList is! List) {
        throw const FormatException('Unexpected value type for a known key');
      }
      for (final k in keyList) {
        if (k is! Map<String, Object?>) {
          throw const FormatException('Malformed api_key entry');
        }
        final key = readString(k, 'current_key');
        if (key != null) keys.add(key);
      }
    }

    return _Client(
      appId,
      android == null ? null : readString(android, 'package_name'),
      keys.length == 1 ? keys.single : null,
      keys.length,
    );
  }

  final String appId;
  final String? packageName;

  /// The app's API key when the file lists exactly one distinct key.
  final String? apiKey;
  final int apiKeyCount;
}
