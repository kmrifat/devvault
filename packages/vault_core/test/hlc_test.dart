import 'dart:math';

import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

void main() {
  const a = '00000000-0000-4000-8000-00000000000a';
  const b = '00000000-0000-4000-8000-00000000000b';
  final t0 = DateTime.utc(2026, 10, 7, 9);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('string form matches the spec and parses back', () {
    final clock = Hlc(1759827600000, 7, a);
    expect(clock.toString(), '001759827600000-00007-$a');
    expect(Hlc.parse(clock.toString()), clock);
  });

  test('rejects malformed revs', () {
    for (final bad in [
      '1759827600000-7-$a',
      '001759827600000-00007-NOT-A-UUID',
      '001759827600000-00007',
      42,
      null,
    ]) {
      expect(() => Hlc.parse(bad), throwsA(isA<VaultFormatException>()));
    }
  });

  test('ticks follow wall time when it moves forward', () {
    final c = Hlc.zero(a).tick(at(0));
    expect(c.wallMs, at(0).millisecondsSinceEpoch);
    expect(c.counter, 0);
    final d = c.tick(at(5));
    expect(d.wallMs, at(5).millisecondsSinceEpoch);
    expect(d.counter, 0);
  });

  test(
    'ticks within the same millisecond, or a clock going back, count up',
    () {
      final c = Hlc.zero(a).tick(at(100));
      final same = c.tick(at(100));
      final back = same.tick(at(50));
      expect(same.counter, 1);
      expect(back.counter, 2);
      expect(back.wallMs, c.wallMs);
      expect(c < same && same < back, isTrue);
    },
  );

  test('receiving a remote clock moves past both', () {
    final local = Hlc.zero(a).tick(at(100));
    final remote = Hlc(at(500).millisecondsSinceEpoch, 3, b);
    final next = local.receive(remote, at(200));
    expect(next > local && next > remote, isTrue);
    expect(next.deviceId, a);
    expect(next.wallMs, remote.wallMs);
    expect(next.counter, 4);
  });

  test('a counter overflow borrows a millisecond instead of wrapping', () {
    final full = Hlc(at(0).millisecondsSinceEpoch, Hlc.maxCounter, a);
    final next = full.tick(at(0));
    expect(next > full, isTrue);
    expect(next.counter, 0);
  });

  test('flags remote clocks more than a day ahead', () {
    expect(
      Hlc.isTooFarAhead(
        Hlc(at(0).add(const Duration(hours: 25)).millisecondsSinceEpoch, 0, b),
        at(0),
      ),
      isTrue,
    );
    expect(
      Hlc.isTooFarAhead(
        Hlc(at(0).add(const Duration(hours: 1)).millisecondsSinceEpoch, 0, b),
        at(0),
      ),
      isFalse,
    );
  });

  test('property: string order equals clock order, and clocks only grow', () {
    final random = Random(42);
    final devices = [a, b];
    final clocks = {for (final d in devices) d: Hlc.zero(d)};
    final seen = <Hlc>[];
    var wall = 0;
    for (var i = 0; i < 2000; i++) {
      // Wall time jitters forward and back, like real device clocks.
      wall += random.nextInt(7) - 2;
      final device = devices[random.nextInt(2)];
      final before = clocks[device]!;
      final Hlc after;
      if (seen.isNotEmpty && random.nextBool()) {
        final remote = seen[random.nextInt(seen.length)];
        after = before.receive(remote, at(wall));
        expect(after > remote, isTrue);
      } else {
        after = before.tick(at(wall));
      }
      expect(after > before, isTrue);
      clocks[device] = after;
      seen.add(after);
    }
    final byClock = [...seen]..sort();
    final byString = [...seen]
      ..sort((x, y) => x.toString().compareTo(y.toString()));
    expect(byString, byClock);
    expect(seen.toSet(), hasLength(seen.length), reason: 'all distinct');
  });
}
