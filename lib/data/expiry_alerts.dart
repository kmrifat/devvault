import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notification_plan.dart';
import 'providers.dart';
import 'vault_session.dart';

/// Keeps the OS's expiry reminders in line with the vault (P4-03).
///
/// Runs [alertDebounceProvider] (2 s) after the last change to the open
/// vault or to the setting, so a burst of edits reschedules once. Only works while the
/// vault is open (the items are needed); what's scheduled stays with the
/// OS after it locks, which is the point. The rules, and the at-most-two
/// promise, live in `core/notification_plan.dart`.
class ExpiryAlerts extends Notifier<void> {
  Timer? _timer;
  bool _askedPermission = false;
  Future<void> _running = Future.value();

  @override
  void build() {
    ref.listen(vaultSessionProvider, (_, next) {
      if (next is Unlocked) _later();
    });
    ref.listen(
      settingsProvider.select((s) => s.expiryReminders),
      (_, _) => _later(),
    );
    ref.onDispose(() => _timer?.cancel());
    if (ref.read(vaultSessionProvider) is Unlocked) _later();
  }

  void _later() {
    _timer?.cancel();
    _timer = Timer(
      ref.read(alertDebounceProvider),
      () => _running = _running.then((_) => sync()),
    );
  }

  /// Brings the OS in line now. Errors are swallowed: a reminder that
  /// fails to schedule is still counted, which only ever means fewer.
  Future<void> sync() async {
    final session = ref.read(vaultSessionProvider);
    if (session is! Unlocked) return;
    final scheduler = ref.read(alertSchedulerProvider);
    final file = ref.read(alertLedgerFileProvider);
    final now = ref.read(clockProvider)().toUtc();
    final ledger = file.load();

    final List<int> cancel;
    final List<PlannedAlert> schedule;
    if (ref.read(settingsProvider).expiryReminders) {
      final changes = syncAlerts(
        ledger,
        session.index.all,
        now,
        scheduler.location,
      );
      cancel = changes.cancel;
      schedule = changes.schedule;
    } else {
      cancel = withdrawAlerts(ledger, now);
      schedule = const [];
    }
    try {
      file.save(ledger);
    } on Object {
      return; // Without a ledger on disk, schedule nothing new.
    }
    if (schedule.isNotEmpty && !_askedPermission) {
      _askedPermission = true;
      await scheduler.requestPermission();
    }
    for (final id in cancel) {
      try {
        await scheduler.cancel(id);
      } on Object {
        // Already gone.
      }
    }
    for (final alert in schedule) {
      try {
        await scheduler.schedule(alert);
      } on Object {
        // Counted anyway; never retried into a third reminder.
      }
    }
  }

  /// The item's file was replaced: it may warn again (P4-04).
  void reset(String itemId) {
    final file = ref.read(alertLedgerFileProvider);
    final ledger = file.load()..reset(itemId);
    file.save(ledger);
    _later();
  }
}

final expiryAlertsProvider = NotifierProvider<ExpiryAlerts, void>(
  ExpiryAlerts.new,
);
