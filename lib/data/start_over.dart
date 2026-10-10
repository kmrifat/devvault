import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../core/notification_plan.dart';
import 'agent_bridge.dart';
import 'providers.dart';
import 'sync_setup.dart';
import 'vault_session.dart';

/// Start over (P1-25): the master password and the recovery key are both
/// gone, so nothing can open this device's vault. Erases it and everything
/// this device kept for it, and the app goes to create.
///
/// Erased: the vault folder and its working folders (storage settings and
/// sync bookkeeping), the storage keys in the keychain, the key behind
/// biometrics, the pending expiry reminders and their ledger, and the
/// paired AI agents. Kept: the app's settings, and anything in a bucket.
/// The bucket copy lives under the vault's own id, so a new vault can use
/// the same bucket, and another device that can still unlock the old one
/// keeps working.
class StartOver {
  StartOver(this._ref);

  final Ref _ref;

  /// Where the locked vault syncs, read from its storage settings on this
  /// device (no secret), or `null` when it doesn't.
  SyncedCopy? syncedCopy() {
    final session = _ref.read(vaultSessionProvider);
    if (session is! Locked) return null;
    final root = session.store.root;
    final file = File(
      '${SyncStateStore(session.store).root.path}/storage.json',
    );
    try {
      if (!file.existsSync()) return null;
      final settings = SyncSettings.fromJson(
        json.decode(file.readAsStringSync()) as Map<String, Object?>,
      );
      final vaultId = root.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      return SyncedCopy(
        bucket: settings.bucket,
        prefix: '${settings.rootPrefix}$vaultId/',
      );
    } on Object {
      return null;
    }
  }

  /// Erases the locked vault. Throws [StateError] when it isn't locked.
  Future<void> call() async {
    final session = _ref.read(vaultSessionProvider);
    if (session is! Locked) {
      throw StateError('Only a locked vault can be erased');
    }
    final vaultId = session.store.root.uri.pathSegments.lastWhere(
      (s) => s.isNotEmpty,
    );

    // Each step is best effort: what's left behind belongs to a vault that
    // no longer exists here, and nothing reads it once the folder is gone.
    await _withdrawReminders();
    try {
      await _ref.read(agentBridgeProvider.notifier).revokeAll();
    } on Object {
      // Revoke them by hand in Settings › AI Agents.
    }
    try {
      await _ref
          .read(credentialStoreProvider)
          .delete(SyncSetupNotifier.credentialKey(vaultId));
    } on Object {
      // Stored under the old vault id; a new vault never reads it.
    }
    await _ref.read(vaultSessionProvider.notifier).eraseLocked();
  }

  /// Cancels the reminders still to come and forgets the rest: they name
  /// items of the erased vault.
  Future<void> _withdrawReminders() async {
    final file = _ref.read(alertLedgerFileProvider);
    final scheduler = _ref.read(alertSchedulerProvider);
    final now = _ref.read(clockProvider)().toUtc();
    for (final id in withdrawAlerts(file.load(), now)) {
      try {
        await scheduler.cancel(id);
      } on Object {
        // Already gone.
      }
    }
    try {
      file.save(AlertLedger());
    } on Object {
      // A stale ledger only holds ids of items that no longer exist.
    }
  }
}

/// Where an erased vault's encrypted copy stays: [prefix] in [bucket].
class SyncedCopy {
  const SyncedCopy({required this.bucket, required this.prefix});

  final String bucket;
  final String prefix;
}

final startOverProvider = Provider<StartOver>(StartOver.new);
