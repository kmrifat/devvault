// Desktop UI spike (not shipped): the same TablePlus-style vault screen,
// built with each OS's native-looking UI kit, to compare look and feel and
// to check each kit builds and runs on every desktop OS.
//
//   flutter run -d macos -t lib/spike/desktop_spike.dart
//   flutter run -d macos -t lib/spike/desktop_spike.dart --dart-define=KIT=fluent
//
// KIT is macos, fluent or yaru; by default the one native to the OS.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart' show MacosWindowUtilsConfig;

import 'fluent_spike.dart';
import 'macos_spike.dart';
import 'yaru_spike.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const chosen = String.fromEnvironment('KIT');
  final kit = chosen.isNotEmpty
      ? chosen
      : Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
      ? 'fluent'
      : 'yaru';
  if (kit == 'macos' && Platform.isMacOS) {
    await const MacosWindowUtilsConfig().apply();
  }
  runApp(switch (kit) {
    'fluent' => const FluentSpikeApp(),
    'yaru' => const YaruSpikeApp(),
    _ => const MacosSpikeApp(),
  });
}
