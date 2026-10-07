import 'dart:io';

import 'package:uuid/uuid.dart';

/// This device's id, stamped on every record it writes (`device_id`) so sync
/// can tell devices apart.
///
/// Created once and kept in [directory] (the app support folder). It is not
/// secret and not synced. A reinstall gets a new id, which is fine: ids only
/// need to be distinct, not stable forever.
Future<String> loadOrCreateDeviceId(Directory directory) async {
  final file = File('${directory.path}${Platform.pathSeparator}device_id');
  if (await file.exists()) {
    final id = (await file.readAsString()).trim();
    if (Uuid.isValidUUID(fromString: id)) return id;
  }
  final id = const Uuid().v4();
  await directory.create(recursive: true);
  await file.writeAsString(id, flush: true);
  return id;
}
