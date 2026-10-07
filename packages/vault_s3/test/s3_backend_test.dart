import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vault_core/storage_conformance.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

const _credentials = AwsCredentials(
  accessKeyId: 'AKIDTEST',
  secretAccessKey: 'test-secret-do-not-print',
);

void main() {
  final config = S3Config(
    endpoint: Uri.parse('http://127.0.0.1:9000'),
    bucket: 'devvault',
  );

  /// A backend over [handler], with instant retries and a captured log.
  (S3Backend, List<String>) backend(
    Future<http.Response> Function(http.Request request) handler, {
    int maxAttempts = 3,
  }) {
    final log = <String>[];
    return (
      S3Backend(
        config: config,
        credentials: _credentials,
        client: MockClient(handler),
        clock: () => DateTime.utc(2026, 10, 7),
        maxAttempts: maxAttempts,
        backoff: (_) => Duration.zero,
        onLog: log.add,
      ),
      log,
    );
  }

  http.Response ok({String body = '', String etag = '"e1"'}) =>
      http.Response(body, 200, headers: {'etag': etag});

  http.Response error(int status, String code) => http.Response(
    '<?xml version="1.0"?><Error><Code>$code</Code><Message>m</Message></Error>',
    status,
  );

  group('addressing', () {
    test('path-style and virtual-host URLs', () {
      expect(
        config.url(key: 'v1/items/a b.enc').toString(),
        'http://127.0.0.1:9000/devvault/v1/items/a%20b.enc',
      );
      expect(
        config.url(query: {'list-type': '2', 'prefix': 'v1/'}).toString(),
        'http://127.0.0.1:9000/devvault?list-type=2&prefix=v1%2F',
      );
      final virtual = S3Config(
        endpoint: Uri.parse('https://s3.eu-west-1.amazonaws.com'),
        bucket: 'mybucket',
        region: 'eu-west-1',
        pathStyle: false,
      );
      expect(
        virtual.url(key: 'v1/vault.json').toString(),
        'https://mybucket.s3.eu-west-1.amazonaws.com/v1/vault.json',
      );
    });

    test('R2 preset', () {
      final r2 = S3Config.r2(accountId: 'acct', bucket: 'vault');
      expect(r2.region, 'auto');
      expect(r2.pathStyle, isTrue);
      expect(
        r2.url(key: 'k').toString(),
        'https://acct.r2.cloudflarestorage.com/vault/k',
      );
    });
  });

  group('requests', () {
    test(
      'a conditional create sends If-None-Match and a signed body hash',
      () async {
        late http.Request seen;
        final (s3, _) = backend((request) async {
          seen = request;
          return ok(etag: '"abc"');
        });
        final body = Uint8List.fromList(utf8.encode('ciphertext'));
        final etag = await s3.put(
          'v1/items/x.enc',
          body,
          condition: const WriteCondition.ifAbsent(),
        );
        expect(etag, '"abc"');
        expect(seen.method, 'PUT');
        expect(seen.url.path, '/devvault/v1/items/x.enc');
        expect(seen.headers['if-none-match'], '*');
        expect(
          seen.headers['x-amz-content-sha256'],
          SigV4Signer.hexSha256(body),
        );
        expect(
          seen.headers['authorization'],
          allOf(
            startsWith(
              'AWS4-HMAC-SHA256 Credential=AKIDTEST/20261007/us-east-1/s3/',
            ),
            contains('if-none-match'),
          ),
        );
        expect(seen.bodyBytes, body);
      },
    );

    test('If-Match on writes and deletes', () async {
      final seen = <http.Request>[];
      final (s3, _) = backend((request) async {
        seen.add(request);
        return request.method == 'DELETE' ? http.Response('', 204) : ok();
      });
      await s3.put(
        'k',
        Uint8List(1),
        condition: const WriteCondition.ifMatch('"e0"'),
      );
      await s3.delete('k', ifMatch: '"e1"');
      expect(seen.map((r) => r.method), ['PUT', 'HEAD', 'DELETE']);
      expect(
        seen.where((r) => r.method != 'HEAD').map((r) => r.headers['if-match']),
        ['"e0"', '"e1"'],
      );
    });

    test(
      'a conditional delete at a stale etag never sends the DELETE',
      () async {
        final seen = <String>[];
        final (s3, _) = backend((request) async {
          seen.add(request.method);
          return ok(etag: '"newer"');
        });
        await expectLater(
          s3.delete('k', ifMatch: '"older"'),
          throwsA(isA<PreconditionFailed>()),
        );
        expect(seen, ['HEAD']);
      },
    );

    test('If-Match on a vanished key is a lost race', () async {
      final (s3, _) = backend((_) async => error(404, 'NoSuchKey'));
      await expectLater(
        s3.put(
          'k',
          Uint8List(1),
          condition: const WriteCondition.ifMatch('"e"'),
        ),
        throwsA(isA<PreconditionFailed>()),
      );
      await expectLater(
        s3.delete('k', ifMatch: '"e"'),
        throwsA(isA<PreconditionFailed>()),
      );
    });

    test(
      'a missing object reads as null; a missing bucket is an error',
      () async {
        final (s3, _) = backend(
          (request) async => request.url.path.endsWith('/gone.enc')
              ? error(404, 'NoSuchKey')
              : error(404, 'NoSuchBucket'),
        );
        expect(await s3.get('gone.enc'), isNull);
        await expectLater(s3.get('other.enc'), throwsA(isA<StorageNotFound>()));
        await expectLater(s3.list('v1/'), throwsA(isA<StorageNotFound>()));
      },
    );

    test('lists every page, sorted, with XML entities decoded', () async {
      final tokens = <String?>[];
      final (s3, _) = backend((request) async {
        final token = request.url.queryParameters['continuation-token'];
        tokens.add(token);
        return token == null
            ? http.Response(
                _listXml(['v1/items/b.enc', 'v1/items/a.enc'], next: 'tok&2'),
                200,
              )
            : http.Response(_listXml(['v1/vault.json']), 200);
      });
      final objects = await s3.list('v1/');
      expect(tokens, [null, 'tok&2']);
      expect(objects.map((o) => o.key), [
        'v1/items/a.enc',
        'v1/items/b.enc',
        'v1/vault.json',
      ]);
      expect(objects.first.etag, '"etag-v1/items/a.enc"');
      expect(objects.first.size, 14);
    });
  });

  group('errors and retries', () {
    test('412 is a lost race, at once', () async {
      var calls = 0;
      final (s3, _) = backend((_) async {
        calls++;
        return error(412, 'PreconditionFailed');
      });
      await expectLater(
        s3.put(
          'k',
          Uint8List(1),
          condition: const WriteCondition.ifMatch('"x"'),
        ),
        throwsA(isA<PreconditionFailed>()),
      );
      expect(calls, 1);
    });

    test('409 is retried, then reported as a lost race', () async {
      var calls = 0;
      final (s3, log) = backend((_) async {
        calls++;
        return error(409, 'ConditionalRequestConflict');
      });
      await expectLater(
        s3.put('k', Uint8List(1), condition: const WriteCondition.ifAbsent()),
        throwsA(isA<PreconditionFailed>()),
      );
      expect(calls, 3);
      expect(log.last, contains('(try 3)'));
    });

    test('throttling and server errors are retried until they clear', () async {
      final statuses = [503, 429, 200];
      final (s3, log) = backend((_) async {
        final status = statuses.removeAt(0);
        return status == 200 ? ok() : error(status, 'SlowDown');
      });
      expect(await s3.put('k', Uint8List(1)), '"e1"');
      expect(log, hasLength(3));
    });

    test('a network that stays down is StorageUnavailable', () async {
      final (s3, _) = backend((_) async => throw const SocketException('down'));
      await expectLater(
        s3.get('k'),
        throwsA(
          isA<StorageUnavailable>().having(
            (e) => e.isRetryable,
            'retryable',
            true,
          ),
        ),
      );
    });

    test('403 is access denied, not retried', () async {
      var calls = 0;
      final (s3, _) = backend((_) async {
        calls++;
        return error(403, 'SignatureDoesNotMatch');
      });
      await expectLater(
        s3.list(''),
        throwsA(
          isA<StorageAccessDenied>().having(
            (e) => e.message,
            'message',
            contains('SignatureDoesNotMatch'),
          ),
        ),
      );
      expect(calls, 1);
    });

    test('the log has no bodies, headers or credentials', () async {
      final (s3, log) = backend((_) async => ok());
      await s3.put(
        'v1/items/x.enc',
        Uint8List.fromList(utf8.encode('payload-bytes')),
      );
      expect(log.single, matches(RegExp(r'^PUT v1/items/x\.enc 200 \d+ms$')));
      final all = log.join('\n');
      for (final leak in ['payload-bytes', 'AKIDTEST', 'test-secret', 'AWS4']) {
        expect(all, isNot(contains(leak)));
      }
    });
  });

  // Runs against a real S3-compatible store when one is configured, e.g.
  // MinIO in CI (see .github/workflows/s3.yml):
  //   S3_TEST_ENDPOINT=http://127.0.0.1:9000 S3_TEST_BUCKET=devvault
  //   S3_TEST_ACCESS_KEY=… S3_TEST_SECRET_KEY=… [S3_TEST_REGION=us-east-1]
  final env = Platform.environment;
  final endpoint = env['S3_TEST_ENDPOINT'];
  test(
    'conforms against a real bucket',
    () async {
      final s3 = S3Backend(
        config: S3Config(
          endpoint: Uri.parse(endpoint!),
          bucket: env['S3_TEST_BUCKET']!,
          region: env['S3_TEST_REGION'] ?? 'us-east-1',
          pathStyle: env['S3_TEST_VIRTUAL_HOST'] == null,
        ),
        credentials: AwsCredentials(
          accessKeyId: env['S3_TEST_ACCESS_KEY']!,
          secretAccessKey: env['S3_TEST_SECRET_KEY']!,
        ),
      );
      addTearDown(s3.close);
      final failures = await checkStorageConformance(
        s3,
        prefix: 'conformance-${DateTime.now().microsecondsSinceEpoch}',
        // More than one ListObjectsV2 page (1,000 keys).
        listCount: 1005,
      );
      expect(failures, isEmpty, reason: failures.join('\n'));
    },
    skip: endpoint == null ? 'S3_TEST_ENDPOINT not set' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

String _listXml(List<String> keys, {String? next}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>devvault</Name>
  <IsTruncated>${next != null}</IsTruncated>
  ${next == null ? '' : '<NextContinuationToken>${next.replaceAll('&', '&amp;')}</NextContinuationToken>'}
  ${keys.map((k) => '<Contents><Key>$k</Key><ETag>&quot;etag-$k&quot;</ETag><Size>${k.length}</Size></Contents>').join()}
</ListBucketResult>''';
