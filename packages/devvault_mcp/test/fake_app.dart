import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agent_bridge/agent_bridge.dart';

const itemId = '0b8f8d0e-4c1a-4f55-9a43-0d2c7c1e9b10';
const blobId = '9a1c2b3d-4e5f-4a6b-8c7d-0e1f2a3b4c5d';
const stripeKey = 'sk_live_FAKE_STRIPE_KEY';
const pemText =
    '-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMGByqGSM49AgEG\n-----END PRIVATE KEY-----\n';

/// A stand-in for the DevVault app: a real [BridgeServer] with canned
/// answers, recording what it was asked.
class FakeApp {
  FakeApp._(this.dir, this.server);

  static Future<FakeApp> start() async {
    final dir = Directory.systemTemp.createTempSync('dvapp');
    late final FakeApp app;
    final server = await BridgeServer.bind(
      '${dir.path}/dv.sock',
      (call) => app._handle(call),
    );
    return app = FakeApp._(dir, server!);
  }

  final Directory dir;
  final BridgeServer server;

  String get socketPath => server.path;

  /// The token the app accepts; `pair` hands it out.
  String validToken = 'token-1';

  /// What the next `request_secret` answers: null to allow.
  BridgeError? decision;

  int pairs = 0;
  final List<SecretRequest> requests = [];

  Future<void> stop() async {
    await server.close();
    dir.deleteSync(recursive: true);
  }

  Future<Map<String, Object?>> _handle(BridgeCall call) async {
    switch (call.method) {
      case 'hello':
        call.session.paired = call.params['token'] == validToken;
        return {
          'protocol': protocolVersion,
          'app_version': '',
          'paired': call.session.paired,
          'state': 'unlocked',
        };
      case 'status':
        return {'state': 'locked'};
      case 'pair':
        pairs++;
        call.session.paired = true;
        return {'token': validToken};
      case 'list':
        return {
          'items': [
            {
              'id': itemId,
              'title': 'Stripe secret key',
              'query': call.params['query'],
            },
          ],
        };
      case 'get':
        throw BridgeException(BridgeError.notFound, '${call.params['id']}');
      case 'request_secret':
        final request = SecretRequest.fromJson(call.params);
        requests.add(request);
        if (decision case final error?) throw BridgeException(error);
        return SecretResult([
          for (final wanted in request.items)
            SecretItem(
              id: wanted.id,
              fields: {
                for (final f in wanted.fields ?? const ['value'])
                  f: f == 'pem' ? pemText : stripeKey,
              },
              attachments: [
                for (final a in wanted.attachments ?? const <String>[])
                  SecretAttachment(
                    id: a,
                    filename: a == blobId ? 'key.jks' : 'notes.txt',
                    mime: 'application/octet-stream',
                    data: a == blobId
                        ? Uint8List.fromList([0, 0xff, 0xfe, 1])
                        : Uint8List.fromList(utf8.encode('hello')),
                  ),
              ],
            ),
        ]).toJson();
      default:
        throw const BridgeException(BridgeError.badRequest);
    }
  }
}
