import 'dart:math';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

const _id = '00000000-0000-4000-8000-000000000042';
final _t0 = DateTime.utc(2026, 10, 7, 9);

/// A clock per device, so every edit gets a unique, ordered rev.
class _Device {
  _Device(this.id) : clock = Hlc.zero(id);
  final String id;
  Hlc clock;
  int ms = 0;

  Hlc tick() {
    ms += 1000;
    return clock = clock.tick(_t0.add(Duration(milliseconds: ms)));
  }

  /// [item] as edited by this device.
  Item edit(Item item, Item Function(Item) change) {
    final changed = change(item);
    return _restamp(changed, tick(), id);
  }
}

Item _restamp(Item i, Hlc rev, String device) =>
    Item.fromJson({...i.toJson(), 'rev': rev.toString(), 'device_id': device});

ItemField _f(String v, {bool secret = false}) =>
    ItemField(value: v, source: FieldSource.user, secret: secret);

Item _base(_Device d) => _restamp(
  Item(
    id: _id,
    typeName: ItemType.androidKeystore.wireName,
    title: 'Upload keystore',
    createdAt: _t0,
    updatedAt: _t0,
    rev: Hlc.zero(d.id),
    deviceId: d.id,
    tags: ['release'],
    fields: {'alias': _f('upload'), 'store_password': _f('pw-0', secret: true)},
  ),
  d.tick(),
  d.id,
);

Item _withFields(Item i, Map<String, ItemField> fields) => Item.fromJson({
  ...i.toJson(),
  'fields': {for (final e in fields.entries) e.key: e.value.toJson()},
});

void main() {
  final a = _Device('00000000-0000-4000-8000-00000000000a');
  final b = _Device('00000000-0000-4000-8000-00000000000b');

  group('mergeItems', () {
    test('one side unchanged: the other wins, no conflict', () {
      final base = _base(a);
      final remote = b.edit(base, (i) => i.copyWith(title: 'Renamed'));
      final r1 = mergeItems(base: base, local: base, remote: remote);
      expect(r1.value.title, 'Renamed');
      expect(r1.conflicted, isFalse);
      final r2 = mergeItems(base: base, local: remote, remote: base);
      expect(r2.value, same(remote));
    });

    test('different fields changed on each side are both kept', () {
      final base = _base(a);
      final local = a.edit(base, (i) => i.copyWith(title: 'Play upload key'));
      final remote = b.edit(
        base,
        (i) => _withFields(i, {
          ...i.fields,
          'store_password': _f('pw-b', secret: true),
        }),
      );
      final r = mergeItems(base: base, local: local, remote: remote);
      expect(r.conflicted, isFalse);
      expect(r.value.title, 'Play upload key');
      expect(r.value.fields['store_password']!.value, 'pw-b');
      expect(r.value.conflict, isNull);
      expect(r.value.rev, remote.rev > local.rev ? remote.rev : local.rev);
    });

    test(
      'the same field changed differently: local kept, remote in conflict',
      () {
        final base = _base(a);
        final local = a.edit(
          base,
          (i) => _withFields(i, {
            ...i.fields,
            'store_password': _f('pw-a', secret: true),
          }),
        );
        final remote = b.edit(
          base,
          (i) => _withFields(i, {
            ...i.fields,
            'store_password': _f('pw-b', secret: true),
          }),
        );
        final r = mergeItems(base: base, local: local, remote: remote);
        expect(r.conflicted, isTrue);
        expect(r.value.fields['store_password']!.value, 'pw-a');
        final conflict = Conflict.of(r.value);
        expect(
          conflict.versions.single.fields['store_password']!.value,
          'pw-b',
        );
        expect(conflict.versions.single.rev, remote.rev);
        expect(conflict.versions.single.conflict, isNull);
      },
    );

    test('an edited field beats a removed one', () {
      final base = _base(a);
      final local = a.edit(
        base,
        (i) => _withFields(i, {'alias': i.fields['alias']!}),
      );
      final remote = b.edit(
        base,
        (i) => _withFields(i, {
          ...i.fields,
          'store_password': _f('pw-new', secret: true),
        }),
      );
      final r = mergeItems(base: base, local: local, remote: remote);
      expect(r.value.fields['store_password']!.value, 'pw-new');
      expect(r.conflicted, isFalse);
    });

    test('a removal on one side, no change on the other: removed', () {
      final base = _base(a);
      final local = a.edit(
        base,
        (i) => _withFields(i, {'alias': i.fields['alias']!}),
      );
      final remote = b.edit(base, (i) => i.copyWith(title: 'T'));
      final r = mergeItems(base: base, local: local, remote: remote);
      expect(r.value.fields.keys, ['alias']);
    });

    test('tags merge as sets, attachments as a union', () {
      final base = _base(a);
      Attachment att(String id) => Attachment(
        blobId: '00000000-0000-4000-8000-0000000000$id',
        filename: '$id.bin',
        mime: 'application/octet-stream',
        size: 1,
        sha256: '0' * 64,
      );
      final local = a.edit(
        base,
        (i) => i.copyWith(tags: ['ci'], attachments: [att('a1')]),
      );
      final remote = b.edit(
        base,
        (i) =>
            i.copyWith(tags: ['release', 'signing'], attachments: [att('b1')]),
      );
      final r = mergeItems(base: base, local: local, remote: remote);
      // local removed "release"; remote added "signing"; both kept "ci"?
      expect(r.value.tags, ['ci', 'signing']);
      expect(r.value.attachments.map((x) => x.filename), ['a1.bin', 'b1.bin']);
      expect(r.conflicted, isFalse);
    });

    test('no base (joining): differences are conflicts, nothing lost', () {
      final x = _base(a);
      final remote = b.edit(x, (i) => i.copyWith(title: 'Theirs'));
      final local = a.edit(x, (i) => i.copyWith(title: 'Mine'));
      final r = mergeItems(local: local, remote: remote);
      expect(r.value.title, 'Mine');
      expect(Conflict.of(r.value).versions.single.title, 'Theirs');
    });

    test('conflicts accumulate across merges', () {
      final base = _base(a);
      final c = _Device('00000000-0000-4000-8000-00000000000c');
      final local = a.edit(base, (i) => i.copyWith(title: 'A'));
      final remote1 = b.edit(base, (i) => i.copyWith(title: 'B'));
      final first = mergeItems(base: base, local: local, remote: remote1).value;
      final saved = _restamp(first, a.tick(), a.id);
      final remote2 = c.edit(base, (i) => i.copyWith(title: 'C'));
      final second = mergeItems(base: base, local: saved, remote: remote2);
      expect(Conflict.of(second.value).versions.map((v) => v.title).toSet(), {
        'B',
        'C',
      });
    });
  });

  group('resolveDeletion', () {
    Tombstone tomb(_Device d) => Tombstone(
      id: _id,
      kind: TombstoneKind.item,
      deletedAt: _t0,
      rev: d.tick(),
      deviceId: d.id,
    );

    test('an edit beats a delete, and the delete is recorded', () {
      final base = _base(a);
      final edited = a.edit(base, (i) => i.copyWith(title: 'Edited'));
      final kept = resolveDeletion(
        base: base,
        live: edited,
        tombstone: tomb(b),
      );
      expect(kept!.title, 'Edited');
      expect(Conflict.of(kept).deletions.single['device_id'], b.id);
    });

    test('an unchanged item is deleted', () {
      final base = _base(a);
      expect(
        resolveDeletion(base: base, live: base, tombstone: tomb(b)),
        isNull,
      );
    });
  });

  group('mergeApps', () {
    AppRecord app(_Device d, String name, List<String> ids) => AppRecord(
      id: '00000000-0000-4000-8000-0000000000a1',
      name: name,
      bundleIds: ids,
      createdAt: _t0,
      updatedAt: _t0,
      rev: d.tick(),
      deviceId: d.id,
    );

    test('name: the changed side wins; identifiers merge as sets', () {
      final base = app(a, 'Kitchenly', ['com.k.app']);
      final local = app(a, 'Kitchenly', ['com.k.app', 'com.k.widget']);
      final remote = app(b, 'Kitchenly Pro', ['com.k.app']);
      final merged = mergeApps(base: base, local: local, remote: remote);
      expect(merged.name, 'Kitchenly Pro');
      expect(merged.bundleIds, ['com.k.app', 'com.k.widget']);
    });

    test('organization and kind: the changed side wins; other identifiers '
        'merge as sets per kind', () {
      final domain = AppIdentifier.of(IdentifierKind.domain, 'k.example');
      final repo = AppIdentifier.of(IdentifierKind.repository, 'gh/k/app');
      final url = AppIdentifier.of(IdentifierKind.url, 'https://k.example');
      final base = app(a, 'Kitchenly', []).copyWith(identifiers: [domain]);
      final local = base.copyWith(
        organization: 'Acme',
        identifiers: [domain, repo],
        rev: a.tick(),
      );
      final remote = base.copyWith(
        kindName: AppKind.web.wireName,
        identifiers: [url],
        rev: b.tick(),
        deviceId: b.id,
      );
      final merged = mergeApps(base: base, local: local, remote: remote);
      expect(merged.organization, 'Acme');
      expect(merged.kind, AppKind.web);
      // The remote side removed the domain; the local side added the repo.
      expect(merged.identifiers, [repo, url]);
    });

    test('notes: the changed side wins; on a clash the local note stays', () {
      final base = app(a, 'Kitchenly', []).copyWith(notes: 'Base');
      final remote = base.copyWith(
        notes: '**Remote**',
        rev: b.tick(),
        deviceId: b.id,
      );
      final renamed = base.copyWith(name: 'Kitchenly Pro', rev: a.tick());
      final merged = mergeApps(base: base, local: renamed, remote: remote);
      expect(merged.name, 'Kitchenly Pro');
      expect(merged.notes, '**Remote**');

      final local = base.copyWith(notes: '_Local_', rev: a.tick());
      final clash = mergeApps(base: base, local: local, remote: remote);
      expect(clash.notes, '_Local_');

      final cleared = base.copyWith(notes: '', rev: a.tick());
      final unchanged = base.copyWith(name: 'K', rev: b.tick(), deviceId: b.id);
      expect(
        mergeApps(base: base, local: cleared, remote: unchanged).notes,
        isNull,
      );
    });
  });

  group('mergeOrganizations', () {
    OrganizationRecord org(_Device d, String name) => OrganizationRecord(
      id: '00000000-0000-4000-8000-0000000000b1',
      name: name,
      createdAt: _t0,
      updatedAt: _t0,
      rev: d.tick(),
      deviceId: d.id,
    );

    test('name: the changed side wins', () {
      final base = org(a, 'Acme');
      final remote = base.copyWith(name: 'Acme Corp', rev: b.tick());
      final local = base.copyWith(rev: a.tick());
      expect(
        mergeOrganizations(base: base, local: local, remote: remote).name,
        'Acme Corp',
      );
      expect(
        mergeOrganizations(base: base, local: remote, remote: local).name,
        'Acme Corp',
      );
    });

    test('on a clash, or without a base, the local name stays', () {
      final base = org(a, 'Acme');
      final local = base.copyWith(name: 'Acme Labs', rev: a.tick());
      final remote = base.copyWith(name: 'Acme Corp', rev: b.tick());
      final merged = mergeOrganizations(
        base: base,
        local: local,
        remote: remote,
      );
      expect(merged.name, 'Acme Labs');
      expect(merged.rev, remote.rev > local.rev ? remote.rev : local.rev);
      expect(
        mergeOrganizations(local: local, remote: remote).name,
        'Acme Labs',
      );
    });

    test('one side unchanged since the base: the other is taken whole', () {
      final base = org(a, 'Acme');
      final remote = OrganizationRecord.fromJson({
        ...base.toJson(),
        'name': 'Acme Corp',
        'colour': 'teal',
        'rev': b.tick().toString(),
      });
      final merged = mergeOrganizations(
        base: base,
        local: base,
        remote: remote,
      );
      expect(merged, same(remote));
    });
  });

  group('property: no secret is ever dropped', () {
    // Random concurrent edits of one item on two devices. Every secret
    // value either side wrote (changed from the base) must survive the
    // merge: in the merged fields or in a kept conflict version.
    test('two devices, 2,000 random edit pairs', () {
      final random = Random(7);
      for (var round = 0; round < 2000; round++) {
        final base = _randomItem(random, a);
        final local = a.edit(base, (i) => _randomEdit(random, i, 'a$round'));
        final remote = b.edit(base, (i) => _randomEdit(random, i, 'b$round'));
        final merged = mergeItems(
          base: base,
          local: local,
          remote: remote,
        ).value;
        _expectSecretsKept(base, [local, remote], merged, 'round $round');
      }
    });

    // Three devices editing and syncing through one remote copy in random
    // order. Every merge keeps concurrent secrets, and after everyone syncs
    // twice more all three hold the same item.
    test('three devices converge', () {
      final random = Random(11);
      for (var run = 0; run < 200; run++) {
        final devices = [
          _Device('00000000-0000-4000-8000-0000000000d1'),
          _Device('00000000-0000-4000-8000-0000000000d2'),
          _Device('00000000-0000-4000-8000-0000000000d3'),
        ];
        var remoteCopy = _base(devices[0]);
        final local = {for (final d in devices) d: remoteCopy};
        final base = {for (final d in devices) d: remoteCopy};

        void sync(_Device d) {
          final dirty = local[d]!.rev != base[d]!.rev;
          if (remoteCopy.rev == base[d]!.rev) {
            if (dirty) remoteCopy = local[d]!; // fast-forward push
          } else if (dirty) {
            final merged = mergeItems(
              base: base[d],
              local: local[d]!,
              remote: remoteCopy,
            ).value;
            _expectSecretsKept(
              base[d]!,
              [local[d]!, remoteCopy],
              merged,
              'run $run',
            );
            remoteCopy = _restamp(merged, d.tick(), d.id);
          }
          local[d] = remoteCopy;
          base[d] = remoteCopy;
        }

        for (var step = 0; step < 30; step++) {
          final d = devices[random.nextInt(3)];
          if (random.nextBool()) {
            local[d] = d.edit(
              local[d]!,
              (i) => _randomEdit(random, i, '$run-$step'),
            );
          } else {
            sync(d);
          }
        }
        for (var i = 0; i < 2; i++) {
          devices.forEach(sync);
        }
        final finals = devices
            .map((d) => local[d]!.toJson().toString())
            .toSet();
        expect(finals, hasLength(1), reason: 'run $run did not converge');
      }
    });
  });
}

Item _randomItem(Random random, _Device d) {
  final base = _base(d);
  return _withFields(base, {
    for (var i = 0; i < random.nextInt(4); i++)
      'k$i': _f('v$i', secret: random.nextBool()),
    ...base.fields,
  });
}

Item _randomEdit(Random random, Item item, String tag) {
  final fields = Map.of(item.fields);
  switch (random.nextInt(5)) {
    case 0: // change a value
      if (fields.isNotEmpty) {
        final key = fields.keys.elementAt(random.nextInt(fields.length));
        fields[key] = _f('$key-$tag', secret: fields[key]!.secret);
      }
    case 1: // remove a field
      if (fields.isNotEmpty) {
        fields.remove(fields.keys.elementAt(random.nextInt(fields.length)));
      }
    case 2: // add a secret
      fields['new-${random.nextInt(3)}'] = _f('secret-$tag', secret: true);
    case 3: // retitle
      return item.copyWith(title: 'title-$tag');
    case 4: // retag
      return item.copyWith(tags: [...item.tags, 'tag-${random.nextInt(4)}']);
  }
  return _withFields(item, fields);
}

void _expectSecretsKept(
  Item base,
  List<Item> sides,
  Item merged,
  String where,
) {
  final keptValues = {
    for (final f in merged.fields.values) f.value,
    for (final v in Conflict.of(merged).versions)
      for (final f in v.fields.values) f.value,
  };
  for (final side in sides) {
    for (final MapEntry(:key, :value) in side.fields.entries) {
      if (!value.secret || base.fields[key] == value) continue;
      expect(
        keptValues,
        contains(value.value),
        reason: '$where: secret $key=${value.value} was dropped',
      );
    }
  }
}
