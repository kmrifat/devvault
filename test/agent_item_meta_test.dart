import 'dart:convert';

import 'package:devvault/core/agent_item_meta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  test("a secure note's metadata never carries its body", () {
    const body = '# Billing runbook\n\nPage **oncall-zebra** first.';
    final note = Item.fromJson({
      'schema': 1,
      'id': '0d1c5e7a-2b3c-4d5e-8f60-718293a4b5c6',
      'type': ItemType.secureNote.wireName,
      'title': 'Billing runbook',
      'tags': <String>[],
      'fields': <String, Object?>{},
      'attachments': <Object?>[],
      'notes': body,
      'created_at': '2026-10-07T09:00:00Z',
      'updated_at': '2026-10-07T09:00:00Z',
      'rev': '001759827600000-00000-2530b979-e992-4aaf-8aac-52a2ce7abaf4',
      'device_id': '2530b979-e992-4aaf-8aac-52a2ce7abaf4',
      'conflict': null,
    });
    final meta = agentItemMeta(note, null);
    expect(meta['type'], 'secure_note');
    expect(meta['title'], 'Billing runbook');
    expect(meta['has_notes'], isTrue);
    expect(meta['attachments'], isEmpty);
    final text = jsonEncode(meta);
    expect(text, isNot(contains('oncall-zebra')));
    expect(text, isNot(contains('Page')));
  });
}
