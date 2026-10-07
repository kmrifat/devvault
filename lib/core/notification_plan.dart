import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:timezone/timezone.dart' as tz;
import 'package:vault_core/vault_core.dart';

import 'expiry.dart';

/// The two reminders an item can ever get.
enum ExpiryAlertKind {
  /// When the item enters the 30-day window.
  window('window'),

  /// On the day it expires.
  expiryDay('expiry_day');

  const ExpiryAlertKind(this.wireName);
  final String wireName;

  static ExpiryAlertKind? fromWireName(String name) =>
      values.where((k) => k.wireName == name).firstOrNull;
}

/// One reminder to hand to the OS: a fixed id, a fire time and its text.
/// The text names the item and its date, nothing else; titles aren't
/// secret, field values never appear.
@immutable
class PlannedAlert {
  const PlannedAlert({
    required this.itemId,
    required this.kind,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  final String itemId;
  final ExpiryAlertKind kind;

  /// 09:00 on a local calendar day, as a zoned instant.
  final tz.TZDateTime fireAt;
  final String title;
  final String body;

  /// Deterministic: the same item and kind always get the same id, so
  /// scheduling again replaces the earlier one instead of adding another.
  int get id => alertId(itemId, kind);

  @override
  bool operator ==(Object other) =>
      other is PlannedAlert &&
      other.itemId == itemId &&
      other.kind == kind &&
      other.fireAt.isAtSameMomentAs(fireAt) &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(itemId, kind, fireAt.millisecondsSinceEpoch);

  @override
  String toString() =>
      'PlannedAlert($itemId, ${kind.wireName}, ${fireAt.toIso8601String()})';
}

/// A stable notification id for [itemId] and [kind]: FNV-1a over
/// `<itemId>|<kind>`, kept to 31 bits (Android ids are signed 32-bit).
int alertId(String itemId, ExpiryAlertKind kind) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode('$itemId|${kind.wireName}')) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Reminders go out at this local time.
const int alertHour = 9;

/// What has been handed to the OS so far, per item: which kinds were
/// scheduled for when. Once a scheduled time has passed the reminder
/// counts as delivered and is never scheduled again for that item, even
/// if its date is edited later, so an item gets at most two reminders in
/// its life. Only [reset] (a replaced file, P4-04) or deleting the item
/// clears it.
///
/// Stored as plain JSON next to the settings; it holds item ids and
/// times, never titles or field values.
class AlertLedger {
  AlertLedger({
    Map<String, Set<ExpiryAlertKind>>? delivered,
    Map<String, Map<ExpiryAlertKind, DateTime>>? scheduled,
  }) : delivered = delivered ?? {},
       scheduled = scheduled ?? {};

  /// Item id → kinds that have fired (or were due while the app was shut).
  final Map<String, Set<ExpiryAlertKind>> delivered;

  /// Item id → kinds currently with the OS, and when they fire (UTC).
  final Map<String, Map<ExpiryAlertKind, DateTime>> scheduled;

  bool wasDelivered(String itemId, ExpiryAlertKind kind) =>
      delivered[itemId]?.contains(kind) ?? false;

  /// How many reminders [itemId] has had.
  int deliveredCount(String itemId) => delivered[itemId]?.length ?? 0;

  /// Forgets everything about [itemId]: its file was replaced, so it may
  /// warn again (P4-04).
  void reset(String itemId) {
    delivered.remove(itemId);
    scheduled.remove(itemId);
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'items': {
      for (final id in {...delivered.keys, ...scheduled.keys})
        id: {
          if (delivered[id]?.isNotEmpty ?? false)
            'delivered': [for (final k in delivered[id]!) k.wireName]..sort(),
          if (scheduled[id]?.isNotEmpty ?? false)
            'scheduled': {
              for (final MapEntry(:key, :value) in scheduled[id]!.entries)
                key.wireName: formatTimestamp(value),
            },
        },
    },
  };

  /// Reads what it recognises; anything malformed is dropped rather than
  /// stopping the app.
  factory AlertLedger.fromJson(Object? json) {
    final ledger = AlertLedger();
    if (json is! Map || json['version'] != 1 || json['items'] is! Map) {
      return ledger;
    }
    for (final MapEntry(:key, :value) in (json['items'] as Map).entries) {
      if (key is! String || value is! Map) continue;
      final kinds = {
        for (final name in (value['delivered'] as List?) ?? const [])
          if (name is String) ?ExpiryAlertKind.fromWireName(name),
      };
      if (kinds.isNotEmpty) ledger.delivered[key] = kinds;
      final pending = <ExpiryAlertKind, DateTime>{};
      if (value['scheduled'] case final Map s) {
        for (final MapEntry(key: name, value: at) in s.entries) {
          final kind = name is String
              ? ExpiryAlertKind.fromWireName(name)
              : null;
          final time = at is String ? DateTime.tryParse(at)?.toUtc() : null;
          if (kind != null && time != null) pending[kind] = time;
        }
      }
      if (pending.isNotEmpty) ledger.scheduled[key] = pending;
    }
    return ledger;
  }
}

/// What to tell the OS to bring it in line with the plan.
@immutable
class AlertChanges {
  const AlertChanges({required this.schedule, required this.cancel});

  /// Reminders to schedule (new, or moved: same id, so they replace).
  final List<PlannedAlert> schedule;

  /// Ids of reminders to withdraw.
  final List<int> cancel;

  bool get isEmpty => schedule.isEmpty && cancel.isEmpty;
}

/// The reminders [items] should have from [now] on, in [location]'s local
/// time, given what [ledger] says was already sent.
///
/// For an item with an expiry date (and only `expires_at` counts):
/// - **window**: the first 09:00 local at or after the moment it enters
///   the 30-day window, or the next 09:00 if it is already inside;
/// - **expiry day**: 09:00 local on the day it expires.
///
/// Nothing is planned in the past, nothing already delivered is planned
/// again, and the window reminder is dropped when it would not come
/// before the expiry-day one. So each item has at most one of each kind.
List<PlannedAlert> planAlerts(
  Iterable<Item> items,
  DateTime now,
  tz.Location location,
  AlertLedger ledger,
) {
  final plan = <PlannedAlert>[];
  for (final item in items) {
    final status = ExpiryStatus.of(item, now);
    final expiresAt = status.expiresAt;
    if (expiresAt == null) continue;

    final localExpiry = tz.TZDateTime.from(expiresAt, location);
    final dayAlert = tz.TZDateTime(
      location,
      localExpiry.year,
      localExpiry.month,
      localExpiry.day,
      alertHour,
    );
    final entersWindow = expiresAt.subtract(ExpiryState.expiryWindow);
    final windowAlert = _nineAtOrAfter(
      entersWindow.isAfter(now) ? entersWindow : now,
      location,
    );

    final date = _dateLabel(localExpiry);
    if (!ledger.wasDelivered(item.id, ExpiryAlertKind.window) &&
        windowAlert.isAfter(now) &&
        windowAlert.isBefore(dayAlert) &&
        windowAlert.isBefore(expiresAt)) {
      plan.add(
        PlannedAlert(
          itemId: item.id,
          kind: ExpiryAlertKind.window,
          fireAt: windowAlert,
          title: '“${item.title}” expires soon',
          body: 'It expires on $date.',
        ),
      );
    }
    if (!ledger.wasDelivered(item.id, ExpiryAlertKind.expiryDay) &&
        dayAlert.isAfter(now)) {
      plan.add(
        PlannedAlert(
          itemId: item.id,
          kind: ExpiryAlertKind.expiryDay,
          fireAt: dayAlert,
          title: dayAlert.isBefore(expiresAt)
              ? '“${item.title}” expires today'
              : '“${item.title}” has expired',
          body: dayAlert.isBefore(expiresAt)
              ? 'It expires at ${_timeLabel(localExpiry)} today.'
              : 'It expired at ${_timeLabel(localExpiry)} today.',
        ),
      );
    }
  }
  return plan;
}

/// Brings [ledger] up to date at [now] and works out what to tell the OS
/// so that [items] get their reminders in [location]'s local time.
///
/// In this order, which is what keeps the at-most-two promise:
/// 1. anything the ledger had scheduled for a time that has passed counts
///    as delivered (the OS showed it while we weren't looking, or tried
///    to), and items no longer in the vault are forgotten;
/// 2. the plan is made against that up-to-date ledger;
/// 3. it is compared with what is still scheduled: new or moved reminders
///    are scheduled (same id, so they replace), ones no longer planned are
///    cancelled.
///
/// The ledger is updated to match, so it can be saved as it stands.
AlertChanges syncAlerts(
  AlertLedger ledger,
  Iterable<Item> items,
  DateTime now,
  tz.Location location,
) {
  // 1. What fired since last time; what's gone.
  for (final MapEntry(key: itemId, value: kinds)
      in ledger.scheduled.entries.toList()) {
    for (final MapEntry(key: kind, value: at) in kinds.entries.toList()) {
      if (!at.isAfter(now)) {
        (ledger.delivered[itemId] ??= {}).add(kind);
        kinds.remove(kind);
      }
    }
    if (kinds.isEmpty) ledger.scheduled.remove(itemId);
  }
  final cancel = forgetMissing(ledger, {for (final i in items) i.id});

  // 2. The plan, against what has really been delivered.
  final plan = planAlerts(items, now, location, ledger);

  // 3. Make the OS match it.
  final wanted = {for (final a in plan) (a.itemId, a.kind): a};
  for (final MapEntry(key: itemId, value: kinds)
      in ledger.scheduled.entries.toList()) {
    for (final kind in kinds.keys.toList()) {
      if (!wanted.containsKey((itemId, kind))) {
        cancel.add(alertId(itemId, kind));
        kinds.remove(kind);
      }
    }
    if (kinds.isEmpty) ledger.scheduled.remove(itemId);
  }
  final schedule = <PlannedAlert>[];
  for (final alert in plan) {
    // Never twice, whatever a caller does with the plan.
    if (ledger.wasDelivered(alert.itemId, alert.kind)) continue;
    final at = alert.fireAt.toUtc();
    final current = ledger.scheduled[alert.itemId]?[alert.kind];
    if (current == null || !current.isAtSameMomentAs(at)) {
      schedule.add(alert);
      (ledger.scheduled[alert.itemId] ??= {})[alert.kind] = at;
    }
  }
  return AlertChanges(schedule: schedule, cancel: cancel);
}

/// Reminders are switched off: whatever already fired counts as
/// delivered, everything still pending is withdrawn. Returns the ids to
/// cancel. What was delivered stays delivered, so switching back on never
/// repeats a reminder.
List<int> withdrawAlerts(AlertLedger ledger, DateTime now) {
  final cancel = <int>[];
  for (final MapEntry(key: itemId, value: kinds) in ledger.scheduled.entries) {
    for (final MapEntry(key: kind, value: at) in kinds.entries) {
      if (at.isAfter(now)) {
        cancel.add(alertId(itemId, kind));
      } else {
        (ledger.delivered[itemId] ??= {}).add(kind);
      }
    }
  }
  ledger.scheduled.clear();
  return cancel;
}

/// Forgets items that are gone from the vault, cancelling their pending
/// reminders. Returns the ids to cancel.
List<int> forgetMissing(AlertLedger ledger, Set<String> itemIds) {
  final cancel = <int>[];
  for (final id in {...ledger.delivered.keys, ...ledger.scheduled.keys}) {
    if (itemIds.contains(id)) continue;
    for (final kind in ledger.scheduled[id]?.keys ?? <ExpiryAlertKind>[]) {
      cancel.add(alertId(id, kind));
    }
    ledger.reset(id);
  }
  return cancel;
}

tz.TZDateTime _nineAtOrAfter(DateTime instant, tz.Location location) {
  final local = tz.TZDateTime.from(instant, location);
  final nine = tz.TZDateTime(
    location,
    local.year,
    local.month,
    local.day,
    alertHour,
  );
  if (!nine.isBefore(local)) return nine;
  return tz.TZDateTime(
    location,
    local.year,
    local.month,
    local.day + 1,
    alertHour,
  );
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dateLabel(tz.TZDateTime d) =>
    '${_months[d.month - 1]} ${d.day}, ${d.year}';

String _timeLabel(tz.TZDateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
