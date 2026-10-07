import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/notification_plan.dart';

/// Hands expiry reminders to the operating system. Abstract so tests can
/// watch what would be scheduled without the OS.
abstract interface class AlertScheduler {
  /// The time zone reminders are planned in (the device's).
  tz.Location get location;

  /// Asks for permission to show notifications, once, when there is first
  /// something to show. Returns whether they may be shown.
  Future<bool> requestPermission();

  /// Schedules [alert]. Scheduling an id again replaces it.
  Future<void> schedule(PlannedAlert alert);

  Future<void> cancel(int id);
}

/// Does nothing: used when the OS can't be reached (and as the default in
/// tests).
class NoAlertScheduler implements AlertScheduler {
  NoAlertScheduler([tz.Location? location]) : location = location ?? tz.UTC;

  @override
  final tz.Location location;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule(PlannedAlert alert) async {}

  @override
  Future<void> cancel(int id) async {}
}

/// [AlertScheduler] over flutter_local_notifications.
///
/// macOS, iOS, Android and Windows keep scheduled notifications with the
/// OS, so they fire with DevVault closed (Android re-arms them after a
/// reboot, inexactly: a few minutes after 09:00 is fine). Linux has no
/// scheduling there, so on Linux a reminder fires only while DevVault is
/// running; the ledger still counts it, which keeps the at-most-two rule.
class LocalAlertScheduler implements AlertScheduler {
  LocalAlertScheduler._(this._plugin, this.location);

  /// Loads the time zone database, finds the device's zone and starts the
  /// plugin. Falls back to [NoAlertScheduler] if any of that fails, so a
  /// missing notification service never stops the app from opening.
  static Future<AlertScheduler> init() async {
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      final location = tz.getLocation(zone.identifier);
      tz.setLocalLocation(location);
      final plugin = FlutterLocalNotificationsPlugin();
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'DevVault',
            appUserModelId: 'BinaryCastle.DevVault',
            guid: '4c7b7654-2e8c-49b8-acf5-bb8942a2c8cb',
          ),
        ),
      );
      return LocalAlertScheduler._(plugin, location);
    } on Object {
      return NoAlertScheduler();
    }
  }

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  final tz.Location location;

  /// Linux only: reminders waiting for their time while the app runs.
  final _timers = <int, Timer>{};

  static bool get _osSchedules => switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.fuchsia => false,
    _ => true,
  };

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'expiry',
      'Expiry reminders',
      channelDescription:
          'When a credential enters its last 30 days, and on the day it '
          'expires.',
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  @override
  Future<bool> requestPermission() async {
    try {
      return switch (defaultTargetPlatform) {
        TargetPlatform.iOS =>
          await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true) ??
              false,
        TargetPlatform.macOS =>
          await _plugin
                  .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true) ??
              false,
        TargetPlatform.android =>
          await _plugin
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >()
                  ?.requestNotificationsPermission() ??
              false,
        _ => true,
      };
    } on Object {
      return false;
    }
  }

  @override
  Future<void> schedule(PlannedAlert alert) async {
    if (_osSchedules) {
      await _plugin.zonedSchedule(
        id: alert.id,
        title: alert.title,
        body: alert.body,
        scheduledDate: alert.fireAt,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return;
    }
    _timers.remove(alert.id)?.cancel();
    final wait = alert.fireAt.difference(DateTime.now());
    if (wait.isNegative) return;
    _timers[alert.id] = Timer(wait, () {
      _timers.remove(alert.id);
      _plugin.show(
        id: alert.id,
        title: alert.title,
        body: alert.body,
        notificationDetails: _details,
      );
    });
  }

  @override
  Future<void> cancel(int id) async {
    _timers.remove(id)?.cancel();
    await _plugin.cancel(id: id);
  }
}

/// Where the [AlertLedger] lives: `<app support>/notifications.json`, next
/// to the settings and outside any vault. It holds item ids and times
/// only. Reads and writes are synchronous: the file is tiny.
class AlertLedgerFile {
  AlertLedgerFile(Directory supportDir)
    : _file = File('${supportDir.path}/notifications.json');

  final File _file;

  AlertLedger load() {
    try {
      return AlertLedger.fromJson(jsonDecode(_file.readAsStringSync()));
    } on Object {
      return AlertLedger();
    }
  }

  /// Writes a temporary file and renames it over the old one, so a crash
  /// mid-write never leaves half a ledger.
  void save(AlertLedger ledger) {
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(ledger.toJson()),
      flush: true,
    );
    tmp.renameSync(_file.path);
  }
}
