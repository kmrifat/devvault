import 'dart:io';

import 'package:devvault/services/device_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('device_id_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('creates a UUID on first launch and keeps it', () async {
    final first = await loadOrCreateDeviceId(dir);
    expect(Uuid.isValidUUID(fromString: first), isTrue);
    expect(await loadOrCreateDeviceId(dir), first);
  });

  test('creates the folder if it does not exist yet', () async {
    final nested = Directory('${dir.path}/not/there/yet');
    final id = await loadOrCreateDeviceId(nested);
    expect(File('${nested.path}/device_id').readAsStringSync(), id);
  });

  test('replaces a corrupted id file', () async {
    File('${dir.path}/device_id').writeAsStringSync('garbage');
    final id = await loadOrCreateDeviceId(dir);
    expect(Uuid.isValidUUID(fromString: id), isTrue);
    expect(File('${dir.path}/device_id').readAsStringSync(), id);
  });
}
