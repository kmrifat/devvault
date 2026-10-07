import 'dart:io';

import 'package:devvault/app/app.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/data/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The fixed "now" every test sees: the day the project started.
final testNow = DateTime.utc(2026, 10, 7, 9);

const testDeviceId = '00000000-0000-4000-8000-000000000001';

/// Provider overrides shared by every app-level test: a fixed clock, a fixed
/// device id and a throwaway app support folder.
List<Override> testOverrides({Directory? supportDir}) => [
  clockProvider.overrideWithValue(() => testNow),
  deviceIdProvider.overrideWithValue(testDeviceId),
  appSupportDirProvider.overrideWithValue(
    supportDir ?? Directory.systemTemp.createTempSync('devvault_test_'),
  ),
];

/// The whole app, wired the way main() wires it but with [testOverrides].
Widget testApp({
  required String location,
  AppLayout? layout,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [...testOverrides(), ...overrides],
  child: DevVaultApp(initialLocation: location, layout: layout),
);
