import 'dart:convert';

import 'package:test/test.dart';
import 'package:vault_s3/vault_s3.dart';

/// Examples published by AWS: the S3 "Signature Calculations for the
/// Authorization Header" examples, and the generic SigV4 test suite's
/// `get-vanilla` plus the IAM example from the SigV4 docs.
void main() {
  const s3Credentials = AwsCredentials(
    accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
    secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
  );
  final s3 = SigV4Signer(credentials: s3Credentials, region: 'us-east-1');
  final s3Time = DateTime.utc(2013, 5, 24);

  String signature(Map<String, String> headers) =>
      RegExp(r'Signature=([0-9a-f]{64})')
          .firstMatch(headers['authorization']!)!
          .group(1)!;

  String signedHeaders(Map<String, String> headers) =>
      RegExp(r'SignedHeaders=([^,]+)')
          .firstMatch(headers['authorization']!)!
          .group(1)!;

  group('S3 examples', () {
    test('GET object with a range', () {
      final headers = s3.sign(
        method: 'GET',
        uri: Uri.parse('https://examplebucket.s3.amazonaws.com/test.txt'),
        headers: {'Range': 'bytes=0-9'},
        now: s3Time,
      );
      expect(
        signedHeaders(headers),
        'host;range;x-amz-content-sha256;x-amz-date',
      );
      expect(
        signature(headers),
        'f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
      );
      expect(
        headers['authorization'],
        startsWith(
          'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/'
          'us-east-1/s3/aws4_request, ',
        ),
      );
    });

    test('PUT object', () {
      final body = utf8.encode('Welcome to Amazon S3.');
      final headers = s3.sign(
        method: 'PUT',
        uri: Uri.parse(
          'https://examplebucket.s3.amazonaws.com'
          '${SigV4Signer.encodePath(['test\$file.text'])}',
        ),
        headers: {
          'Date': 'Fri, 24 May 2013 00:00:00 GMT',
          'x-amz-storage-class': 'REDUCED_REDUNDANCY',
        },
        payloadHash: SigV4Signer.hexSha256(body),
        now: s3Time,
      );
      expect(
        headers['x-amz-content-sha256'],
        '44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072',
      );
      expect(
        signature(headers),
        '98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd',
      );
    });

    test('GET bucket lifecycle (a query key without a value)', () {
      final headers = s3.sign(
        method: 'GET',
        uri: Uri.parse('https://examplebucket.s3.amazonaws.com/?lifecycle'),
        now: s3Time,
      );
      expect(
        signature(headers),
        'fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543',
      );
    });

    test('list objects (query sorted by name)', () {
      final headers = s3.sign(
        method: 'GET',
        uri: Uri.parse(
          'https://examplebucket.s3.amazonaws.com/?prefix=J&max-keys=2',
        ),
        now: s3Time,
      );
      expect(
        signature(headers),
        '34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7',
      );
    });
  });

  group('SigV4 test suite', () {
    const credentials = AwsCredentials(
      accessKeyId: 'AKIDEXAMPLE',
      secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
    );
    final time = DateTime.utc(2015, 8, 30, 12, 36);

    test('get-vanilla', () {
      final headers =
          SigV4Signer(
            credentials: credentials,
            region: 'us-east-1',
            service: 'service',
          ).sign(
            method: 'GET',
            uri: Uri.parse('https://example.amazonaws.com/'),
            now: time,
          );
      expect(signedHeaders(headers), 'host;x-amz-date');
      expect(
        signature(headers),
        '5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31',
      );
    });

    test('IAM ListUsers from the SigV4 docs', () {
      final headers =
          SigV4Signer(
            credentials: credentials,
            region: 'us-east-1',
            service: 'iam',
          ).sign(
            method: 'GET',
            uri: Uri.parse(
              'https://iam.amazonaws.com/?Action=ListUsers&Version=2010-05-08',
            ),
            headers: {
              'Content-Type':
                  'application/x-www-form-urlencoded; charset=utf-8',
            },
            now: time,
          );
      expect(signedHeaders(headers), 'content-type;host;x-amz-date');
      expect(
        signature(headers),
        '5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7',
      );
    });
  });

  group('details', () {
    test('encodes the AWS way', () {
      expect(SigV4Signer.encode('a b/c~d*e'), 'a%20b%2Fc~d%2Ae');
      expect(SigV4Signer.encode('a/b', keepSlash: true), 'a/b');
      expect(SigV4Signer.encode('é'), '%C3%A9');
      expect(
        SigV4Signer.encodePath(['bucket', 'vault id', 'items', 'x.enc']),
        '/bucket/vault%20id/items/x.enc',
      );
    });

    test('a non-default port is part of the signed host', () {
      final headers = s3.sign(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:9000/bucket/key'),
        now: s3Time,
      );
      expect(headers['host'], '127.0.0.1:9000');
      final https = s3.sign(
        method: 'GET',
        uri: Uri.parse('https://example.com:443/key'),
        now: s3Time,
      );
      expect(https['host'], 'example.com');
    });

    test('R2 signs with the auto region', () {
      final headers =
          SigV4Signer(credentials: s3Credentials, region: autoRegion).sign(
            method: 'GET',
            uri: Uri.parse('https://acct.r2.cloudflarestorage.com/bucket/key'),
            now: s3Time,
          );
      expect(
        headers['authorization'],
        contains('/20130524/auto/s3/aws4_request'),
      );
    });

    test('session tokens are signed; secrets never printed', () {
      const temporary = AwsCredentials(
        accessKeyId: 'ASIAEXAMPLE',
        secretAccessKey: 'super-secret-key',
        sessionToken: 'token-123',
      );
      final headers = SigV4Signer(credentials: temporary, region: 'eu-west-1')
          .sign(
            method: 'GET',
            uri: Uri.parse('https://b.s3.amazonaws.com/k'),
            now: s3Time,
          );
      expect(headers['x-amz-security-token'], 'token-123');
      expect(signedHeaders(headers), contains('x-amz-security-token'));
      expect(headers.values.join(' '), isNot(contains('super-secret-key')));
      expect(temporary.toString(), isNot(contains('super-secret-key')));
    });
  });
}
