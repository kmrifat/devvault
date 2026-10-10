import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/app_settings.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/updates.dart';
import 'package:devvault/services/link_opener.dart';
import 'package:devvault/services/updates.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_overrides.dart';

const running = AppVersion(1, 0, 0);

/// GitHub's answer for a release, trimmed to what matters plus a field the
/// app must ignore.
String releaseJson(
  String tag, {
  bool prerelease = false,
  bool draft = false,
  String published = '2026-10-12T08:30:00Z',
}) => jsonEncode({
  'tag_name': tag,
  'name': 'DevVault $tag',
  'draft': draft,
  'prerelease': prerelease,
  'published_at': published,
  'html_url': 'https://evil.example/download',
  'body': 'Notes',
});

/// Answers with [release] (or throws [failure]) and counts the requests.
class FakeReleases implements ReleaseSource {
  FakeReleases([this.release]);

  Release? release;
  UpdateCheckFailed? failure;
  int calls = 0;

  @override
  Future<Release> latest() async {
    calls++;
    if (failure case final f?) throw f;
    return release!;
  }
}

class FakeLinks implements LinkOpener {
  final opened = <Uri>[];

  @override
  Future<void> open(Uri link) async => opened.add(link);
}

class FakeInstaller implements UpdateInstaller {
  final installed = <Release>[];

  @override
  Future<void> install(Release release) async => installed.add(release);
}

final newer = Release(
  version: const AppVersion(1, 2, 0),
  publishedAt: DateTime.utc(2026, 10, 12, 8, 30),
);

void main() {
  group('AppVersion', () {
    test('reads the build version and release tags strictly', () {
      expect(AppVersion.tryParse('1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParseTag('v1.2.3'), const AppVersion(1, 2, 3));
      for (final bad in ['1.2', 'v1.2.3', '1.2.3-beta', ' 1.2.3', '']) {
        expect(AppVersion.tryParse(bad), isNull, reason: bad);
      }
      for (final bad in [
        '1.2.3',
        'v1.2',
        'v1.2.3-rc.1',
        'v1.2.3+4',
        'release-1.2.3',
        'v1.2.3\n',
      ]) {
        expect(AppVersion.tryParseTag(bad), isNull, reason: bad);
      }
    });

    test('compares as three numbers', () {
      expect(const AppVersion(1, 10, 0) > const AppVersion(1, 9, 9), isTrue);
      expect(const AppVersion(2, 0, 0) > const AppVersion(1, 99, 99), isTrue);
      expect(const AppVersion(1, 0, 0) > const AppVersion(1, 0, 0), isFalse);
      expect(const AppVersion(1, 0, 0).tag, 'v1.0.0');
    });
  });

  group('GitHubReleaseSource', () {
    Future<Release> answer(
      int status,
      String body, {
      void Function(http.Request)? onRequest,
    }) => GitHubReleaseSource(
      client: MockClient((request) async {
        onRequest?.call(request);
        return http.Response(body, status);
      }),
    ).latest();

    test('asks GitHub for the latest release and sends nothing else', () async {
      late http.Request sent;
      final release = await answer(
        200,
        releaseJson('v1.2.0'),
        onRequest: (r) => sent = r,
      );
      expect(sent.method, 'GET');
      expect(
        sent.url.toString(),
        'https://api.github.com/repos/kmrifat/devvault/releases/latest',
      );
      expect(sent.headers, {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'DevVault',
      });
      expect(sent.body, isEmpty);
      expect(release.version, const AppVersion(1, 2, 0));
      expect(release.publishedAt, DateTime.utc(2026, 10, 12, 8, 30));
    });

    test('builds the release page itself, never from the answer', () async {
      final release = await answer(200, releaseJson('v1.2.0'));
      expect(
        release.page.toString(),
        'https://github.com/kmrifat/devvault/releases/tag/v1.2.0',
      );
    });

    test('refuses anything that isn’t a published release', () async {
      final cases = {
        'no release yet': (404, '{}'),
        'rate limited': (403, '{}'),
        'not JSON': (200, '<html>'),
        'a list': (200, '[]'),
        'a pre-release tag': (200, releaseJson('v1.2.0-rc.1')),
        'a loose tag': (200, releaseJson('1.2.0')),
        'flagged pre-release': (200, releaseJson('v1.2.0', prerelease: true)),
        'a draft': (200, releaseJson('v1.2.0', draft: true)),
      };
      for (final MapEntry(key: name, value: (status, body)) in cases.entries) {
        await expectLater(
          answer(status, body),
          throwsA(isA<UpdateCheckFailed>()),
          reason: name,
        );
      }
    });

    test('says what failed without repeating the answer', () async {
      for (final (status, body) in [
        (500, 'secret-looking body'),
        (200, '{"tag_name": "secret-looking"}'),
      ]) {
        try {
          await answer(status, body);
          fail('expected a failure');
        } on UpdateCheckFailed catch (e) {
          expect(e.reason, isNot(contains('secret')));
        }
      }
      final offline = GitHubReleaseSource(
        client: MockClient((_) => throw const SocketException('no route')),
      );
      await expectLater(
        offline.latest(),
        throwsA(
          isA<UpdateCheckFailed>().having(
            (e) => e.reason,
            'reason',
            'Couldn’t reach GitHub.',
          ),
        ),
      );
    });

    test('gives up after the timeout', () async {
      final slow = GitHubReleaseSource(
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(slow.latest(), throwsA(isA<UpdateCheckFailed>()));
    });
  });

  group('UpdateStatus', () {
    test('round-trips through JSON and ignores what it can’t read', () {
      final status = UpdateStatus(
        latest: newer,
        checkedAt: DateTime.utc(2026, 10, 12, 9),
        failedAt: DateTime.utc(2026, 10, 13, 9),
        failure: 'Couldn’t reach GitHub.',
        dismissed: const AppVersion(1, 2, 0),
      );
      final back = UpdateStatus.fromJson(status.toJson());
      expect(back.latest, newer);
      expect(back.checkedAt, status.checkedAt);
      expect(back.failedAt, status.failedAt);
      expect(back.failure, status.failure);
      expect(back.dismissed, status.dismissed);
      final junk = UpdateStatus.fromJson({
        'latest': {'version': 'v9'},
        'checked_at': 7,
        'dismissed': 'later',
      });
      expect(junk.latest, isNull);
      expect(junk.checkedAt, isNull);
      expect(junk.dismissed, isNull);
      expect(UpdateStatus.fromJson('nonsense').latest, isNull);
    });

    test('offers only a newer release', () {
      final status = UpdateStatus(latest: newer);
      expect(status.availableFor(running), newer);
      expect(status.availableFor(const AppVersion(1, 2, 0)), isNull);
      expect(status.availableFor(const AppVersion(1, 3, 0)), isNull);
    });
  });

  group('AppSettings.updateChecks', () {
    test('is unset until the user answers', () {
      expect(const AppSettings().updateChecks, isNull);
      expect(
        const AppSettings().toJson().containsKey('update_checks'),
        isFalse,
      );
      for (final on in [true, false]) {
        final settings = AppSettings(updateChecks: on);
        expect(AppSettings.fromJson(settings.toJson()), settings);
      }
      expect(
        AppSettings.fromJson({'update_checks': 'yes'}).updateChecks,
        isNull,
      );
    });
  });

  group('UpdatesNotifier', () {
    late Directory dir;
    late FakeReleases releases;
    late DateTime now;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('devvault_updates_');
      addTearDown(() => dir.deleteSync(recursive: true));
      releases = FakeReleases(newer);
      now = DateTime.utc(2026, 10, 12, 9);
    });

    ProviderContainer container({bool? checks, AppVersion? version = running}) {
      final c = ProviderContainer(
        overrides: [
          appSupportDirProvider.overrideWithValue(dir),
          clockProvider.overrideWithValue(() => now),
          initialSettingsProvider.overrideWithValue(
            AppSettings(updateChecks: checks),
          ),
          appVersionProvider.overrideWithValue(version),
          releaseSourceProvider.overrideWithValue(releases),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('makes no request while the setting is unset or off', () async {
      for (final checks in [null, false]) {
        final c = container(checks: checks);
        c.read(updatesProvider);
        await settle();
        await c.read(updatesProvider.notifier).checkIfDue();
        expect(releases.calls, 0, reason: '$checks');
      }
    });

    test('checks when turned on, then once a day', () async {
      final c = container(checks: false);
      c.read(updatesProvider);
      await settle();
      c.read(settingsProvider.notifier).setUpdateChecks(true);
      await settle();
      expect(releases.calls, 1);
      expect(c.read(updatesProvider).latest, newer);
      expect(c.read(updatesProvider).checkedAt, now);

      now = now.add(const Duration(hours: 23));
      await c.read(updatesProvider.notifier).checkIfDue();
      expect(releases.calls, 1);
      now = now.add(const Duration(hours: 1));
      await c.read(updatesProvider.notifier).checkIfDue();
      expect(releases.calls, 2);
    });

    test('checks at launch when the last check is a day old', () async {
      UpdateStatusFile(
        dir,
      ).save(UpdateStatus(checkedAt: now.subtract(const Duration(hours: 2))));
      final c = container(checks: true);
      c.read(updatesProvider);
      await settle();
      expect(releases.calls, 0);

      now = now.add(const Duration(days: 1));
      final later = container(checks: true);
      later.read(updatesProvider);
      await settle();
      expect(releases.calls, 1);
    });

    test(
      'a failure is recorded, and retried hours later, not hourly',
      () async {
        releases.failure = const UpdateCheckFailed('Couldn’t reach GitHub.');
        final c = container(checks: true);
        c.read(updatesProvider);
        await settle();
        final status = c.read(updatesProvider);
        expect(status.failedAt, now);
        expect(status.failure, 'Couldn’t reach GitHub.');
        expect(status.checkedAt, isNull);
        expect(releases.calls, 1);

        now = now.add(const Duration(hours: 1));
        await c.read(updatesProvider.notifier).checkIfDue();
        expect(releases.calls, 1);
        releases.failure = null;
        now = now.add(const Duration(hours: 6));
        await c.read(updatesProvider.notifier).checkIfDue();
        expect(releases.calls, 2);
        expect(c.read(updatesProvider).failedAt, isNull);
        expect(c.read(updatesProvider).failure, isNull);
      },
    );

    test('Check Now asks even with the setting off', () async {
      final c = container(checks: false);
      await c.read(updatesProvider.notifier).checkNow();
      expect(releases.calls, 1);
      // Saved for the next launch.
      expect(UpdateStatusFile(dir).load().latest, newer);
    });

    test('nothing without a running version', () async {
      final c = container(checks: true, version: null);
      c.read(updatesProvider);
      await settle();
      await c.read(updatesProvider.notifier).checkNow();
      expect(releases.calls, 0);
    });
  });

  group('desktop', () {
    late FakeLinks links;

    List<Override> overrides(
      FakeReleases releases, {
      UpdateInstaller? installer,
    }) => [
      appVersionProvider.overrideWithValue(running),
      releaseSourceProvider.overrideWithValue(releases),
      linkOpenerProvider.overrideWithValue(links = FakeLinks()),
      if (installer != null)
        updateInstallerProvider.overrideWithValue(installer),
    ];

    setUpAll(loadTestCrypto);

    testWidgets('asks once; Not Now stores off and asks nothing', (
      tester,
    ) async {
      final releases = FakeReleases(newer);
      await pumpUnlockedApp(
        tester,
        location: Routes.vaultRoot,
        layout: AppLayout.desktop,
        overrides: overrides(releases),
      );
      expect(
        find.textContaining('Check GitHub for new versions'),
        findsOneWidget,
      );
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();
      expect(appContainer(tester).read(settingsProvider).updateChecks, false);
      expect(
        find.textContaining('Check GitHub for new versions'),
        findsNothing,
      );
      expect(releases.calls, 0);
    });

    testWidgets('Check Daily checks, and a newer release shows', (
      tester,
    ) async {
      final releases = FakeReleases(newer);
      await pumpUnlockedApp(
        tester,
        location: Routes.vaultRoot,
        layout: AppLayout.desktop,
        overrides: overrides(releases),
      );
      await tester.tap(find.text('Check Daily'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(releases.calls, 1);
      expect(
        find.text('DevVault 1.2.0 is available. Published 12 Oct 2026.'),
        findsOneWidget,
      );
      await tester.tap(find.text('View Release'));
      expect(links.opened.single.toString(), newer.page.toString());

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.textContaining('is available'), findsNothing);
    });

    testWidgets('Update… hands the release to the installer', (tester) async {
      final installer = FakeInstaller();
      final releases = FakeReleases(newer);
      await pumpUnlockedApp(
        tester,
        location: Routes.vaultRoot,
        layout: AppLayout.desktop,
        overrides: overrides(releases, installer: installer),
      );
      await tester.tap(find.text('Check Daily'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update…'));
      expect(installer.installed, [newer]);
    });

    testWidgets('Settings › General: the switch, Check Now and the facts', (
      tester,
    ) async {
      final releases = FakeReleases(
        Release(version: running, publishedAt: DateTime.utc(2026, 10, 1)),
      );
      await pumpUnlockedApp(
        tester,
        location: Routes.settings,
        layout: AppLayout.desktop,
        overrides: overrides(releases),
      );
      expect(find.text('DevVault 1.0.0'), findsOneWidget);
      expect(find.text('Not checked yet.'), findsOneWidget);

      await tester.tap(find.text('Check Now'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(releases.calls, 1);
      // Checking by hand doesn't turn the daily check on.
      expect(appContainer(tester).read(settingsProvider).updateChecks, isNull);
      expect(
        find.textContaining('1.0.0 is the latest release.'),
        findsOneWidget,
      );

      releases.failure = const UpdateCheckFailed('Couldn’t reach GitHub.');
      await tester.tap(find.text('Check Now'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining('is the latest release'), findsNothing);
      expect(find.textContaining('Couldn’t reach GitHub.'), findsOneWidget);

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(appContainer(tester).read(settingsProvider).updateChecks, isTrue);
    });

    testWidgets('no strip and no rows where the version is unknown', (
      tester,
    ) async {
      await pumpUnlockedApp(
        tester,
        location: Routes.settings,
        layout: AppLayout.desktop,
      );
      expect(find.text('Check for updates'), findsNothing);
      expect(
        find.textContaining('Check GitHub for new versions'),
        findsNothing,
      );
    });
  });
}
