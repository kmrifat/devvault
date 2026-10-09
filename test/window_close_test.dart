import 'package:devvault/app/window_close.dart';
import 'package:devvault/data/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps running only with agents on, where supported, if wanted', () {
    const on = AppSettings(agentsEnabled: true);
    expect(keepsRunningWhenClosed(on, supported: true), isTrue);
    expect(keepsRunningWhenClosed(on, supported: false), isFalse);
    expect(
      keepsRunningWhenClosed(const AppSettings(), supported: true),
      isFalse,
    );
    expect(
      keepsRunningWhenClosed(
        on.copyWith(keepRunningWhenClosed: false),
        supported: true,
      ),
      isFalse,
    );
  });

  test('the setting defaults on and round-trips', () {
    expect(const AppSettings().keepRunningWhenClosed, isTrue);
    expect(AppSettings.fromJson({}).keepRunningWhenClosed, isTrue);
    final off = const AppSettings().copyWith(keepRunningWhenClosed: false);
    expect(AppSettings.fromJson(off.toJson()).keepRunningWhenClosed, isFalse);
  });
}
