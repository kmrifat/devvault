import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The GitHub repository DevVault is released from (ADR-0007).
const releaseRepo = 'kmrifat/devvault';

/// A release version: `major.minor.patch`, nothing else.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _plain = RegExp(r'^(\d{1,6})\.(\d{1,6})\.(\d{1,6})$');
  static final _tag = RegExp(r'^v(\d{1,6})\.(\d{1,6})\.(\d{1,6})$');

  /// The running app's version as the build reports it (`1.0.0`, from
  /// `version:` in pubspec.yaml). Null for anything else.
  static AppVersion? tryParse(String text) => _match(_plain, text);

  /// A release tag exactly as `release.yml` makes them (`v1.0.0`). Null
  /// for anything else, pre-release tags included.
  static AppVersion? tryParseTag(String tag) => _match(_tag, tag);

  static AppVersion? _match(RegExp pattern, String text) {
    final m = pattern.firstMatch(text);
    if (m == null) return null;
    return AppVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  String get tag => 'v$this';

  @override
  int compareTo(AppVersion other) => major != other.major
      ? major.compareTo(other.major)
      : minor != other.minor
      ? minor.compareTo(other.minor)
      : patch.compareTo(other.patch);

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// A published release, as GitHub describes it.
class Release {
  const Release({required this.version, this.publishedAt});

  final AppVersion version;

  /// When it was published, as GitHub says; null when it didn't say.
  final DateTime? publishedAt;

  /// The release page. Built here from the version, never taken from the
  /// response (ADR-0007 §2).
  Uri get page =>
      Uri.https('github.com', '/$releaseRepo/releases/tag/${version.tag}');

  Map<String, Object?> toJson() => {
    'version': '$version',
    'published_at': publishedAt?.toUtc().toIso8601String(),
  };

  static Release? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final version = json['version'];
    final parsed = version is String ? AppVersion.tryParse(version) : null;
    if (parsed == null) return null;
    final published = json['published_at'];
    return Release(
      version: parsed,
      publishedAt: published is String ? DateTime.tryParse(published) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Release &&
      other.version == version &&
      other.publishedAt == publishedAt;

  @override
  int get hashCode => Object.hash(version, publishedAt);
}

/// A check that couldn't get an answer. Says what went wrong in words fit
/// for the user; nothing from the response is in it.
class UpdateCheckFailed implements Exception {
  const UpdateCheckFailed(this.reason);

  final String reason;

  @override
  String toString() => 'UpdateCheckFailed: $reason';
}

/// Where the latest release comes from. Abstract so tests make no
/// requests.
abstract interface class ReleaseSource {
  /// The latest published release. Throws [UpdateCheckFailed].
  Future<Release> latest();
}

/// GitHub's latest release (ADR-0007 §2): one GET, which never returns
/// drafts or pre-releases, sending nothing but `User-Agent: DevVault`.
///
/// This file is the app's only network code outside `packages/vault_s3`
/// (test/tool/network_boundary_test.dart).
class GitHubReleaseSource implements ReleaseSource {
  /// [client] is for tests; the app uses its own.
  GitHubReleaseSource({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  void close() => _client.close();

  static final latestUrl = Uri.https(
    'api.github.com',
    '/repos/$releaseRepo/releases/latest',
  );

  /// A release's JSON is a few kilobytes; anything far larger isn't one.
  static const _maxBytes = 1 << 20;

  @override
  Future<Release> latest() async {
    final http.Response response;
    try {
      response = await _client
          .get(
            latestUrl,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'DevVault',
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const UpdateCheckFailed('GitHub didn’t answer in time.');
    } on Object {
      throw const UpdateCheckFailed('Couldn’t reach GitHub.');
    }
    if (response.statusCode == 404) {
      throw const UpdateCheckFailed('No release has been published yet.');
    }
    if (response.statusCode != 200) {
      throw UpdateCheckFailed('GitHub answered ${response.statusCode}.');
    }
    if (response.bodyBytes.length > _maxBytes) {
      throw const UpdateCheckFailed('GitHub’s answer wasn’t a release.');
    }
    final Object? body;
    try {
      body = json.decode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const UpdateCheckFailed('GitHub’s answer wasn’t a release.');
    }
    if (body is! Map<String, Object?> ||
        body['draft'] == true ||
        body['prerelease'] == true) {
      throw const UpdateCheckFailed('GitHub’s answer wasn’t a release.');
    }
    final tag = body['tag_name'];
    final version = tag is String ? AppVersion.tryParseTag(tag) : null;
    if (version == null) {
      throw const UpdateCheckFailed('The latest release has no version.');
    }
    final published = body['published_at'];
    return Release(
      version: version,
      publishedAt: published is String ? DateTime.tryParse(published) : null,
    );
  }
}

/// Installs a release in place: Sparkle on macOS (P6-04), App Installer
/// for the MSIX (P6-05). Where there is none, the app only links to the
/// release page.
abstract interface class UpdateInstaller {
  /// Hands over to the OS's updater, which checks the signature, asks the
  /// user and restarts the app. Throws [UpdateCheckFailed].
  Future<void> install(Release release);
}
