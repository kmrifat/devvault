import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import 'providers.dart';
import 'vault_session.dart';

/// Where sync is, for the status chip.
sealed class SyncStatus {
  const SyncStatus();
}

/// No storage set up: the vault lives on this device only.
final class SyncOff extends SyncStatus {
  const SyncOff();
}

/// Up to date as of [lastSync] (null before the first sync this session).
final class SyncIdle extends SyncStatus {
  const SyncIdle({this.lastSync, this.conflicts = 0});

  final DateTime? lastSync;

  /// Items holding a conflict to resolve (D05).
  final int conflicts;
}

final class SyncRunning extends SyncStatus {
  const SyncRunning({this.lastSync});

  final DateTime? lastSync;
}

/// The storage couldn't be reached; changes stay local until it can.
final class SyncOffline extends SyncStatus {
  const SyncOffline({this.lastSync});

  final DateTime? lastSync;
}

/// Sync stopped on something the user has to look at (credentials, the
/// bucket, a vault that doesn't match).
final class SyncFailed extends SyncStatus {
  const SyncFailed(this.message, {this.lastSync});

  final String message;
  final DateTime? lastSync;
}

/// The configured storage, or null when sync is off. Sync settings (P2-09)
/// build it from the saved endpoint and the keychain credentials.
final storageBackendProvider = Provider<StorageBackend?>((ref) => null);

/// A short name for the storage in the status chip, such as `R2`.
final storageLabelProvider = Provider<String?>((ref) => null);

/// Runs sync and decides when (P2-08): on unlock, 2 s after an edit, every
/// 60 s while the app is in front, and on request (⌘R, the status chip).
/// Runs never overlap, and they take the session's write lock, so an edit
/// and a sync never touch the vault files at the same time.
class SyncController extends Notifier<SyncStatus> {
  static const editDelay = Duration(seconds: 2);
  static const interval = Duration(seconds: 60);
  static const retryAfterRace = Duration(seconds: 10);

  Timer? _soon;
  Timer? _periodic;
  Future<SyncReport?>? _running;
  bool _applyingSync = false;
  DateTime? _lastSync;

  /// What the last successful run did (notices for the user).
  SyncReport? lastReport;

  @override
  SyncStatus build() {
    final backend = ref.watch(storageBackendProvider);
    ref.onDispose(() {
      _soon?.cancel();
      _periodic?.cancel();
    });
    if (backend == null) return const SyncOff();

    ref.listen(vaultSessionProvider, (previous, next) {
      if (next is! Unlocked) {
        _soon?.cancel();
        return;
      }
      if (previous is! Unlocked) {
        _schedule(Duration.zero); // just unlocked
      } else if (!_applyingSync) {
        _schedule(editDelay); // an edit here
      }
    });
    _periodic = Timer.periodic(interval, (_) {
      final inFront =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (inFront) syncNow();
    });
    if (ref.read(vaultSessionProvider) is Unlocked) _schedule(Duration.zero);
    return const SyncIdle();
  }

  void _schedule(Duration delay) {
    _soon?.cancel();
    _soon = Timer(delay, syncNow);
  }

  /// Syncs now, or joins the run already going. Returns its report, or
  /// null when it didn't run (sync off, vault locked) or failed.
  Future<SyncReport?> syncNow() =>
      _running ??= _run().whenComplete(() => _running = null);

  Future<SyncReport?> _run() async {
    final backend = ref.read(storageBackendProvider);
    final session = ref.read(vaultSessionProvider);
    if (backend == null || session is! Unlocked) return null;
    final notifier = ref.read(vaultSessionProvider.notifier);
    state = SyncRunning(lastSync: _lastSync);
    try {
      final report = await notifier.exclusive(() async {
        final result = await SyncEngine(
          vault: session.vault,
          backend: backend,
          now: ref.read(clockProvider),
        ).sync();
        if (result.changedLocally) {
          _applyingSync = true;
          try {
            await notifier.reload();
          } finally {
            _applyingSync = false;
          }
        }
        return result;
      });
      lastReport = report;
      _lastSync = ref.read(clockProvider)();
      final current = ref.read(vaultSessionProvider);
      state = SyncIdle(
        lastSync: _lastSync,
        conflicts: current is Unlocked
            ? current.index.items.values.where((i) => i.conflict != null).length
            : 0,
      );
      return report;
    } on StorageUnavailable {
      state = SyncOffline(lastSync: _lastSync);
    } on StorageAccessDenied {
      state = SyncFailed(
        'The storage refused the access keys. Check them in Settings.',
        lastSync: _lastSync,
      );
    } on StorageNotFound {
      state = SyncFailed(
        'The bucket wasn’t found. Check the storage settings.',
        lastSync: _lastSync,
      );
    } on PreconditionFailed {
      state = SyncFailed(
        'Other devices kept changing the vault; trying again shortly.',
        lastSync: _lastSync,
      );
      _schedule(retryAfterRace);
    } on VaultKeyMismatch {
      state = SyncFailed(
        'The vault in this storage has a different key. Sync is paused so '
        'nothing is overwritten.',
        lastSync: _lastSync,
      );
    } on StateError {
      // Locked while syncing: nothing to report.
      state = SyncIdle(lastSync: _lastSync);
    }
    return null;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);
