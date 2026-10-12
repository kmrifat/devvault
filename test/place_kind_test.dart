import 'package:devvault/features/import/place_fields.dart';
import 'package:flutter_test/flutter_test.dart';

/// A platform or environment field reads a suggested value by its name and
/// keeps anything else exactly as typed (P7-05).
void main() {
  test('suggested values read by their names', () {
    expect(PlaceKind.platform.label('ios'), 'iOS');
    expect(PlaceKind.platform.label('android'), 'Android');
    expect(PlaceKind.environment.label('production'), 'Production');
    expect(PlaceKind.platform.label(null), '');
  });

  test('any other value reads as typed, never recased', () {
    expect(PlaceKind.platform.label('tvOS'), 'tvOS');
    expect(PlaceKind.environment.label('qa-eu'), 'qa-eu');
  });

  test('a suggestion\'s name stores its value; other text as typed', () {
    expect(PlaceKind.platform.value('iOS'), 'ios');
    expect(PlaceKind.platform.value(' Android '), 'android');
    expect(PlaceKind.environment.value('Staging'), 'staging');
    expect(PlaceKind.platform.value('android'), 'android');
    expect(PlaceKind.environment.value('qa-eu'), 'qa-eu');
    expect(PlaceKind.environment.value('Prod'), 'Prod');
    expect(PlaceKind.platform.value('  '), isNull);
  });

  test('suggestions are the spec\'s names, then values already used', () {
    expect(PlaceKind.environment.suggestions(['qa-eu', 'production', null]), [
      'Production',
      'Staging',
      'Development',
      'qa-eu',
    ]);
  });
}
