import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/storage_conformance.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  test(
    'a store that ignores conditions conforms behind VerifyingBackend',
    () async {
      const caps = StorageCapabilities(
        conditionalCreate: false,
        conditionalUpdate: false,
        conditionalDelete: true,
      );
      expect(await checkStorageConformance(_IgnoresConditions()), isNotEmpty);
      expect(
        await checkStorageConformance(
          VerifyingBackend(_IgnoresConditions(), caps),
        ),
        isEmpty,
      );
    },
  );

  test('conditions the store enforces pass straight through', () async {
    final inner = MemoryBackend();
    final verifying = VerifyingBackend(inner, StorageCapabilities.full);
    await verifying.put(
      'k',
      Uint8List(1),
      condition: const WriteCondition.ifAbsent(),
    );
    expect(inner.log, ['put k']);
  });

  test('warnings say what is at risk; full support has none', () {
    expect(StorageCapabilities.full.isRaceFree, isTrue);
    expect(StorageCapabilities.full.warnings, isEmpty);
    const minio = StorageCapabilities(
      conditionalCreate: true,
      conditionalUpdate: true,
      conditionalDelete: false,
    );
    expect(minio.isRaceFree, isFalse);
    expect(minio.warnings.single, contains('ignores conditions on deletes'));
    expect(StorageCapabilities.fromJson(minio.toJson()), minio);
  });
}

class _IgnoresConditions extends MemoryBackend {
  @override
  Future<String> put(
    String key,
    Uint8List bytes, {
    WriteCondition condition = const WriteCondition.always(),
  }) => super.put(key, bytes);
}
