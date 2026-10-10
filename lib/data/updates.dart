import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/updates.dart';
import 'providers.dart';

/// What this device knows about DevVault releases (ADR-0007): the latest
/// one the last successful check found, when that was, and the last
/// failure after it. Nothing here is a guess: no check, no release.
class UpdateStatus {
  const UpdateStatus({
    this.latest,
    this.checkedAt,
    this.failedAt,
    this.failure,
    this.dismissed,
    this.checking = false,
  });

  /// The latest published release, from the last successful check.
  final Release? latest;

  /// When a check last succeeded.
  final DateTime? checkedAt;

  /// When a check last failed, if that was after the last success, and
  /// why ([UpdateCheckFailed.reason]).
  final DateTime? failedAt;
  final String? failure;

  /// The version whose banner the user put off with *Later*.
  final AppVersion? dismissed;

  /// Whether a check is running now.
  final bool checking;

  /// [latest] when it is newer than [running].
  Release? availableFor(AppVersion running) {
    final release = latest;
    return release != null && release.version > running ? release : null;
  }

  UpdateStatus copyWith({
    Release? latest,
    DateTime? checkedAt,
    DateTime? Function()? failedAt,
    String? Function()? failure,
    AppVersion? dismissed,
    bool? checking,
  }) => UpdateStatus(
    latest: latest ?? this.latest,
    checkedAt: checkedAt ?? this.checkedAt,
    failedAt: failedAt == null ? this.failedAt : failedAt(),
    failure: failure == null ? this.failure : failure(),
    dismissed: dismissed ?? this.dismissed,
    checking: checking ?? this.checking,
  );

  Map<String, Object?> toJson() => {
    'latest': latest?.toJson(),
    'checked_at': checkedAt?.toUtc().toIso8601String(),
    'failed_at': failedAt?.toUtc().toIso8601String(),
    'failure': failure,
    'dismissed': dismissed?.toString(),
  };

  /// Reads what it recognises; anything else is as if never checked.
  factory UpdateStatus.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const UpdateStatus();
    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    final dismissed = json['dismissed'];
    final failure = json['failure'];
    return UpdateStatus(
      latest: Release.fromJson(json['latest']),
      checkedAt: time(json['checked_at']),
      failedAt: time(json['failed_at']),
      failure: failure is String ? failure : null,
      dismissed: dismissed is String ? AppVersion.tryParse(dismissed) : null,
    );
  }
}

/// [UpdateStatus] on disk, next to the settings (`updates.json`).
class UpdateStatusFile {
  UpdateStatusFile(Directory supportDir)
    : _file = File('${supportDir.path}/updates.json');

  final File _file;

  UpdateStatus load() {
    try {
      return UpdateStatus.fromJson(jsonDecode(_file.readAsStringSync()));
    } on Object {
      return const UpdateStatus();
    }
  }

  /// Temp file, then rename, as the settings do.
  void save(UpdateStatus status) {
    final tmp = File('${_file.path}.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(status.toJson()),
      flush: true,
    );
    tmp.renameSync(_file.path);
  }
}

/// Checks for new releases: once a day while *Check for updates* is on,
/// and whenever the user asks. With the setting unset or off it makes no
/// request until the user presses *Check Now*.
class UpdatesNotifier extends Notifier<UpdateStatus> {
  /// How often an automatic check runs.
  static const interval = Duration(hours: 24);

  /// How long an automatic check waits after a failure before trying
  /// again, so an offline machine doesn't ask every hour.
  static const retryAfterFailure = Duration(hours: 6);

  /// How often the app looks at whether a check is due, for an app left
  /// open for days.
  static const tick = Duration(hours: 1);

  @override
  UpdateStatus build() {
    final status = ref.read(updateStatusFileProvider).load();
    // Nothing to compare against: no checks at all (phones, tests).
    if (ref.watch(appVersionProvider) == null) return status;
    final timer = Timer.periodic(tick, (_) => checkIfDue());
    ref.onDispose(timer.cancel);
    ref.listen(
      settingsProvider.select((s) => s.updateChecks),
      (_, on) => checkIfDue(),
    );
    scheduleMicrotask(checkIfDue);
    return status;
  }

  DateTime _now() => ref.read(clockProvider)();

  /// Checks if the setting is on and the last check is old enough.
  Future<void> checkIfDue() async {
    if (ref.read(settingsProvider).updateChecks != true) return;
    final now = _now();
    final checked = state.checkedAt;
    if (checked != null && now.difference(checked) < interval) return;
    final failed = state.failedAt;
    if (failed != null && now.difference(failed) < retryAfterFailure) return;
    await checkNow();
  }

  /// One request to the release source, now.
  Future<void> checkNow() async {
    if (state.checking || ref.read(appVersionProvider) == null) return;
    state = state.copyWith(checking: true);
    UpdateStatus next;
    try {
      final release = await ref.read(releaseSourceProvider).latest();
      next = state.copyWith(
        latest: release,
        checkedAt: _now(),
        failedAt: () => null,
        failure: () => null,
        checking: false,
      );
    } on UpdateCheckFailed catch (e) {
      next = state.copyWith(
        failedAt: () => _now(),
        failure: () => e.reason,
        checking: false,
      );
    }
    if (!ref.mounted) return;
    state = next;
    _save();
  }

  /// *Later*: no banner for this release; Settings still shows it.
  void dismiss(AppVersion version) {
    state = state.copyWith(dismissed: version);
    _save();
  }

  void _save() {
    // Best effort, as the settings: a failed write only means the next
    // launch checks again.
    try {
      ref.read(updateStatusFileProvider).save(state);
    } on Object {
      // Ignored.
    }
  }
}

final updatesProvider = NotifierProvider<UpdatesNotifier, UpdateStatus>(
  UpdatesNotifier.new,
);
