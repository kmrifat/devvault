import 'package:test/test.dart';
import 'package:vault_s3/vault_s3.dart';

void main() {
  test('uses the R2 auto region', () {
    expect(autoRegion, 'auto');
  });
}
