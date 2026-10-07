import 'dart:io';
import 'dart:typed_data';

import 'package:cred_parsers/src/der.dart';
import 'package:test/test.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  test('reads a certificate fixture', () {
    final cert = Asn1.parse(File('test/fixtures/cert.cer').readAsBytesSync());
    expect(cert.tag, Asn1.tagSequence);
    expect(cert.children, hasLength(3));
    final tbs = cert[0];
    expect(tbs[0].explicit(0).smallInteger, 2); // v3
    final validity = tbs[4];
    expect(validity[1].time.isAfter(validity[0].time), isTrue);
    expect(validity[0].time.isUtc, isTrue);
  });

  test('integers, including negative and multi-byte', () {
    expect(Asn1.parse(bytes([0x02, 0x01, 0x00])).integer, BigInt.zero);
    expect(Asn1.parse(bytes([0x02, 0x01, 0x7F])).integer, BigInt.from(127));
    expect(
      Asn1.parse(bytes([0x02, 0x02, 0x00, 0x80])).integer,
      BigInt.from(128),
    );
    expect(Asn1.parse(bytes([0x02, 0x01, 0xFF])).integer, BigInt.from(-1));
  });

  test('object identifiers', () {
    final ec = bytes([0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]);
    expect(Asn1.parse(ec).oid, '1.2.840.10045.2.1');
    expect(
      () => Asn1.parse(bytes([0x06, 0x01, 0x86])).oid,
      throwsFormatException,
    );
  });

  test('UTCTime pivots at 1950 and GeneralizedTime is read as is', () {
    DateTime t(int tag, String s) =>
        Asn1.parse(bytes([tag, s.length, ...s.codeUnits])).time;
    expect(
      t(Asn1.tagUtcTime, '491231235959Z'),
      DateTime.utc(2049, 12, 31, 23, 59, 59),
    );
    expect(t(Asn1.tagUtcTime, '500101000000Z'), DateTime.utc(1950));
    expect(
      t(Asn1.tagGeneralizedTime, '20360101120000Z'),
      DateTime.utc(2036, 1, 1, 12),
    );
    expect(() => t(Asn1.tagUtcTime, '491331235959Z'), throwsFormatException);
    expect(() => t(Asn1.tagUtcTime, '4912312359Z'), throwsFormatException);
  });

  test('indefinite lengths (BER) are read, with nested values', () {
    final value = Asn1.parse(
      bytes([
        0x30, 0x80, //
        0x02, 0x01, 0x03,
        0xA0, 0x80, 0x04, 0x01, 0xAB, 0x00, 0x00,
        0x00, 0x00,
      ]),
    );
    expect(value.children, hasLength(2));
    expect(value[0].integer, BigInt.from(3));
    expect(value[1].explicit(0).octets, [0xAB]);
    expect(value.encoded, hasLength(14));
  });

  test('malformed input throws FormatException, never anything else', () {
    for (final input in [
      <int>[],
      [0x30],
      [0x30, 0x05, 0x02, 0x01],
      [0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF],
      [0x30, 0x85, 0, 0, 0, 0, 1],
      [0x04, 0x80, 0x00, 0x00],
      [0x30, 0x80, 0x02, 0x01, 0x00],
      [0x1F, 0x81, 0x00],
      [0x02, 0x01, 0x00, 0xFF],
      [
        for (var i = 0; i < 100; i++) ...[0x30, 0x80],
      ],
    ]) {
      expect(
        () => Asn1.parse(bytes(input)).children,
        throwsFormatException,
        reason: '$input',
      );
    }
  });

  test('accessors check the tag', () {
    final octets = Asn1.parse(bytes([0x04, 0x01, 0x00]));
    expect(() => octets.integer, throwsFormatException);
    expect(() => octets.oid, throwsFormatException);
    expect(() => octets.children, throwsFormatException);
    expect(() => octets.string, throwsFormatException);
    expect(() => Asn1.parse(bytes([0x30, 0x00]))[0], throwsFormatException);
  });

  test('PEM blocks are decoded by label', () {
    final pem = File('test/fixtures/cert.pem').readAsStringSync();
    final blocks = decodePem(pem);
    expect(blocks.single.label, 'CERTIFICATE');
    expect(
      blocks.single.bytes,
      File('test/fixtures/cert.cer').readAsBytesSync(),
    );
    expect(
      () => decodePem('-----BEGIN X-----\n!!!\n-----END X-----'),
      throwsFormatException,
    );
    expect(decodePem('no pem here'), isEmpty);
  });
}
