import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vault_s3/vault_s3.dart';

/// The AWS SigV4 test suite, from awslabs/aws-c-auth
/// (tests/aws-signing-test-suite/v4, Apache-2.0; see the LICENSE and NOTICE
/// beside it). Every case runs through [SigV4Signer] with header signing
/// and must give the suite's signature, except where the suite expects what
/// S3 signing deliberately doesn't do; those are skipped with the reason.
void main() {
  final root = Directory('test/aws-sigv4-test-suite');
  final cases = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('the suite is here', () => expect(cases, hasLength(38)));

  for (final dir in cases) {
    final name = dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    String read(String file) => File('${dir.path}/$file').readAsStringSync();

    final context = jsonDecode(read('context.json')) as Map<String, Object?>;
    final request = _Request.parse(read('request.txt'));
    final expectedPath = read('header-canonical-request.txt').split('\n')[1];
    final s3Path = _encodeOnce(request.path);

    final String? skip;
    if (context['omit_session_token'] == true) {
      skip = 'the session token is added after signing; S3 signs it';
    } else if (request.path.split('/').any((s) => s == '.' || s == '..')) {
      skip =
          'a "." or ".." path segment: StorageKeys keeps them out of every '
          'key, so DevVault never signs one';
    } else if (expectedPath != s3Path) {
      skip = 'expects the path normalised ($expectedPath); S3 signs it as is';
    } else {
      skip = null;
    }

    test(name, skip: skip, () {
      final credentials = context['credentials']! as Map<String, Object?>;
      final signer = SigV4Signer(
        credentials: AwsCredentials(
          accessKeyId: credentials['access_key_id']! as String,
          secretAccessKey: credentials['secret_access_key']! as String,
          sessionToken: credentials['token'] as String?,
        ),
        region: context['region']! as String,
        service: context['service']! as String,
      );
      final payloadHash = SigV4Signer.hexSha256(utf8.encode(request.body));
      final headers = signer.sign(
        method: request.method,
        uri: Uri.parse(
          'https://${request.headers['host']}$s3Path'
          '${request.query.isEmpty ? '' : '?${request.query}'}',
        ),
        headers: {
          for (final MapEntry(:key, :value) in request.headers.entries)
            if (key != 'host' && key != 'x-amz-date') key: value,
          // What the signer adds itself for service s3, DevVault's only one.
          if (context['sign_body'] == true) 'x-amz-content-sha256': payloadHash,
        },
        payloadHash: payloadHash,
        now: DateTime.parse(context['timestamp']! as String),
      );
      final authorization = headers['authorization']!;
      final signedHeaders = RegExp(r'SignedHeaders=([^,]+)')
          .firstMatch(authorization)!
          .group(1);
      expect(
        signedHeaders,
        read('header-canonical-request.txt').split('\n').reversed.skip(1).first,
      );
      expect(
        RegExp(r'Signature=(\w+)').firstMatch(authorization)!.group(1),
        read('header-signature.txt').trim(),
      );
    });
  }
}

/// The path as S3 signs it: each segment encoded once.
String _encodeOnce(String path) =>
    path.split('/').map((s) => SigV4Signer.encode(s)).join('/');

/// A request.txt: the request line, headers (folded lines kept, repeated
/// names joined with commas, as HTTP allows) and the body.
class _Request {
  _Request(this.method, this.path, this.query, this.headers, this.body);

  factory _Request.parse(String text) {
    final blank = text.indexOf('\n\n');
    final head = (blank == -1 ? text : text.substring(0, blank)).split('\n');
    final body = blank == -1 ? '' : text.substring(blank + 2);
    final line = head.first;
    final target = line.substring(line.indexOf(' ') + 1, line.lastIndexOf(' '));
    final q = target.indexOf('?');
    final headers = <String, String>{};
    String? last;
    for (final raw in head.skip(1)) {
      if (raw.isEmpty) continue;
      if (raw.startsWith(' ') || raw.startsWith('\t')) {
        headers[last!] = '${headers[last]}\n$raw';
        continue;
      }
      final colon = raw.indexOf(':');
      final key = raw.substring(0, colon).toLowerCase();
      final value = raw.substring(colon + 1);
      headers[key] = headers.containsKey(key)
          ? '${headers[key]},$value'
          : value;
      last = key;
    }
    return _Request(
      line.substring(0, line.indexOf(' ')),
      q == -1 ? target : target.substring(0, q),
      q == -1 ? '' : target.substring(q + 1),
      headers,
      body,
    );
  }

  final String method;
  final String path;
  final String query;
  final Map<String, String> headers;
  final String body;
}
