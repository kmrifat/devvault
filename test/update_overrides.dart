import 'dart:io';

import 'package:devvault/data/app_settings.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/updates.dart';
import 'package:devvault/services/updates.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'test_overrides.dart';

/// What the last checks found, without a file or a request.
class SeenUpdates extends UpdateStatusFile {
  SeenUpdates(this.status) : super(Directory.systemTemp);

  final UpdateStatus status;

  @override
  UpdateStatus load() => status;

  @override
  void save(UpdateStatus status) {}
}

/// Update checks (ADR-0007) on DevVault 1.0.0: [latest] as the last check
/// two hours ago found it.
List<Override> updateOverrides({
  bool? checks,
  AppVersion latest = const AppVersion(1, 0, 0),
}) => [
  appVersionProvider.overrideWithValue(const AppVersion(1, 0, 0)),
  initialSettingsProvider.overrideWithValue(AppSettings(updateChecks: checks)),
  updateStatusFileProvider.overrideWithValue(
    SeenUpdates(
      UpdateStatus(
        latest: Release(
          version: latest,
          publishedAt: DateTime.utc(2026, 10, 6, 14),
        ),
        checkedAt: testNow.subtract(const Duration(hours: 2)),
      ),
    ),
  ),
];
