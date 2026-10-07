import 'package:cred_parsers/cred_parsers.dart';
import 'package:test/test.dart';

void main() {
  test('recognises the credential file types from the plan', () {
    expect(knownExtensions, containsAll(['p8', 'p12', 'mobileprovision', 'jks']));
  });
}
