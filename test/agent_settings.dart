import 'dart:io';

import 'package:devvault/data/agent_bridge.dart';
import 'package:devvault/data/agent_clients.dart';
import 'package:devvault/data/providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'test_overrides.dart';

/// Two clients paired before the test starts.
final sampleClients = [
  PairedClient(
    tokenHash: 'a' * 64,
    name: 'claude-code',
    pairedAt: DateTime.utc(2026, 10, 1, 9),
    lastSeen: testNow,
  ),
  PairedClient(
    tokenHash: 'b' * 64,
    name: 'cursor',
    pairedAt: DateTime.utc(2026, 10, 3, 14),
  ),
];

final sampleActivity = [
  AgentActivity(
    at: testNow,
    client: 'claude-code',
    action: 'Wrote file',
    detail: 'Upload keystore',
    outcome: 'Allowed once',
  ),
  AgentActivity(
    at: testNow.subtract(const Duration(minutes: 4)),
    client: 'claude-code',
    action: 'Listed',
    detail: 'items matching "kitchenly"',
    outcome: 'Allowed without asking',
  ),
  AgentActivity(
    at: testNow.subtract(const Duration(minutes: 9)),
    client: 'cursor',
    action: 'Revealed',
    detail: 'Stripe secret key',
    outcome: 'Denied',
  ),
];

/// Settings › AI Agents with [sampleClients] already paired. [supported]
/// gives it a socket path (macOS); agents stay off, so nothing binds.
List<Override> agentSettingsOverrides({bool supported = true}) => [
  agentClientsFileProvider.overrideWithValue(_Clients()),
  if (supported) ...[
    agentSocketPathProvider.overrideWithValue('/nonexistent/dv.sock'),
    agentHelperPathProvider.overrideWithValue(
      '/Applications/DevVault.app/Contents/Helpers/devvault-mcp',
    ),
  ],
];

class _Clients extends AgentClientsFile {
  _Clients() : super(Directory.systemTemp);

  @override
  List<PairedClient> load() => sampleClients;

  @override
  Future<void> save(List<PairedClient> clients) async {}
}
