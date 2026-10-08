import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_bridge/agent_bridge.dart';
import 'package:test/test.dart';

const _id = '0b8f8d0e-4c1a-4f55-9a43-0d2c7c1e9b10';
const _secret = 'sk_live_THIS_MUST_NOT_PRINT';

void main() {
  group('SecretRequest', () {
    test('round-trips', () {
      final request = SecretRequest(
        reason: 'Deploy to TestFlight',
        delivery: const Delivery.file('/tmp/AuthKey.p8'),
        items: const [
          SecretItemRequest(id: _id, fields: ['private_key'], notes: true),
        ],
      );
      final back = SecretRequest.fromJson(
        jsonDecode(jsonEncode(request.toJson())) as Map<String, Object?>,
      );
      expect(back.reason, 'Deploy to TestFlight');
      expect(back.delivery.mode, DeliveryMode.file);
      expect(back.delivery.target, '/tmp/AuthKey.p8');
      expect(back.items.single.fields, ['private_key']);
      expect(back.items.single.notes, isTrue);
      expect(back.items.single.wantsAllFields, isFalse);
    });

    test('an item naming nothing wants every field', () {
      expect(const SecretItemRequest(id: _id).wantsAllFields, isTrue);
    });

    Map<String, Object?> valid() => {
      'reason': 'why',
      'delivery': {'mode': 'reveal'},
      'items': [
        {'id': _id},
      ],
    };

    for (final (name, change)
        in <(String, void Function(Map<String, Object?>))>[
          ('no reason', (m) => m.remove('reason')),
          ('blank reason', (m) => m['reason'] = '  '),
          ('long reason', (m) => m['reason'] = 'x' * 501),
          ('no items', (m) => m['items'] = []),
          ('too many items', (m) => m['items'] = List.filled(21, {'id': _id})),
          (
            'relative path',
            (m) => m['delivery'] = {'mode': 'file', 'path': 'a'},
          ),
          (
            'blank command',
            (m) => m['delivery'] = {'mode': 'command', 'command': ' '},
          ),
          ('unknown mode', (m) => m['delivery'] = {'mode': 'email'}),
          (
            'fields not strings',
            (m) => m['items'] = [
              {
                'id': _id,
                'fields': [1],
              },
            ],
          ),
        ]) {
      test('rejects $name', () {
        final json = valid();
        change(json);
        expect(
          () => SecretRequest.fromJson(json),
          throwsA(
            isA<BridgeException>().having(
              (e) => e.code,
              'code',
              BridgeError.badRequest,
            ),
          ),
        );
      });
    }
  });

  group('SecretResult', () {
    final result = SecretResult([
      SecretItem(
        id: _id,
        fields: {'api_key': _secret},
        attachments: [
          SecretAttachment(
            id: _id,
            filename: 'key.pem',
            mime: 'application/x-pem-file',
            data: Uint8List.fromList(utf8.encode(_secret)),
          ),
        ],
        notes: _secret,
      ),
    ]);

    test('round-trips', () {
      final back = SecretResult.fromJson(
        jsonDecode(jsonEncode(result.toJson())) as Map<String, Object?>,
      );
      final item = back.items.single;
      expect(item.fields, {'api_key': _secret});
      expect(utf8.decode(item.attachments.single.data), _secret);
      expect(item.notes, _secret);
    });

    test('never prints a value', () {
      final printed = [
        result.toString(),
        result.items.single.toString(),
        result.items.single.attachments.single.toString(),
      ].join();
      expect(printed, isNot(contains(_secret)));
      expect(printed, contains('api_key'));
    });
  });

  test('BridgeException round-trips and maps unknown codes to internal', () {
    final e = BridgeException.fromJson(
      const BridgeException(BridgeError.denied, 'no').toJson(),
    );
    expect(e.code, BridgeError.denied);
    expect(e.message, 'no');
    expect(
      BridgeException.fromJson({'code': 'what'}).code,
      BridgeError.internal,
    );
  });

  test('ClientInfo needs a short name', () {
    expect(ClientInfo.fromJson({'name': ' claude-code '}).name, 'claude-code');
    expect(
      () => ClientInfo.fromJson({'name': ''}),
      throwsA(isA<BridgeException>()),
    );
    expect(
      () => ClientInfo.fromJson({'name': 'x' * 65}),
      throwsA(isA<BridgeException>()),
    );
  });

  test('pairing tokens are 32 random bytes; the app keeps only a hash', () {
    final a = newPairingToken(), b = newPairingToken();
    expect(a, isNot(b));
    expect(base64Url.decode('$a='), hasLength(32));
    expect(tokenHash(a), matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(tokenHash(a), isNot(contains(a)));
  });

  test('socket paths stay under the 104-byte macOS limit', () {
    expect(
      socketPathForHome('/Users/rifat'),
      '/Users/rifat/Library/Containers/com.binarycastle.devvault/Data/tmp/dv.sock',
    );
    expect(
      socketPathInContainer(
        '/Users/rifat/Library/Containers/com.binarycastle.devvault/Data',
      ),
      socketPathForHome('/Users/rifat'),
    );
    expect(
      utf8.encode(socketPathForHome('/Users/a-long-user-name')).length,
      lessThan(104),
    );
  });
}
