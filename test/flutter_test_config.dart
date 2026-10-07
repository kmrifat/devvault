import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file in `test/`.
///
/// Every test renders with the fonts the app bundles (Inter, JetBrains Mono,
/// Lucide icons) rather than the test font, whose square glyphs are far
/// wider: layouts that fit on screen (tab bars, toolbars) would otherwise
/// overflow in tests only.
///
/// Golden screenshots differ by faint anti-aliasing along text edges between
/// Macs (CPU, macOS version), so an exact match fails on CI for no visible
/// reason. [TolerantGoldenComparator] ignores those faint shifts but still
/// fails on anything a person could see.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = TolerantGoldenComparator(
      comparator.basedir.resolve('golden_test.dart'),
    );
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadAppFonts();
  await testMain();
}

Future<void> _loadAppFonts() async {
  final manifest = json.decode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// Compares goldens per pixel: a pixel only counts as changed when one of
/// its channels moves by at least [strongDelta] (out of 255), and the
/// image fails when more than [maxStrongPixels] pixels changed.
///
/// Measured on this project: anti-aliasing drift between a local Mac and the
/// CI runner moves ~460 pixels, all but one by less than 64. Changing a
/// single letter of a label moves ~90 pixels by 64 or more.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile);

  static const int strongDelta = 64;
  static const int maxStrongPixels = 8;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final goldenBytes = Uint8List.fromList(await getGoldenBytes(golden));
    if (await strongPixelChanges(imageBytes, goldenBytes) <= maxStrongPixels) {
      return true;
    }
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      goldenBytes,
    );
    try {
      throw FlutterError(await generateFailureOutput(result, golden, basedir));
    } finally {
      result.dispose();
    }
  }

  /// Number of pixels whose largest channel change is at least
  /// [strongDelta]. Images of different sizes count as entirely changed.
  static Future<int> strongPixelChanges(Uint8List a, Uint8List b) async {
    final pixelsA = await _rgba(a);
    final pixelsB = await _rgba(b);
    if (pixelsA.width != pixelsB.width || pixelsA.height != pixelsB.height) {
      return pixelsA.width * pixelsA.height;
    }
    var changed = 0;
    for (var i = 0; i < pixelsA.bytes.length; i += 4) {
      for (var c = 0; c < 4; c++) {
        if ((pixelsA.bytes[i + c] - pixelsB.bytes[i + c]).abs() >=
            strongDelta) {
          changed++;
          break;
        }
      }
    }
    return changed;
  }

  static Future<({int width, int height, Uint8List bytes})> _rgba(
    Uint8List png,
  ) async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = (
      width: image.width,
      height: image.height,
      bytes: data!.buffer.asUint8List(),
    );
    image.dispose();
    codec.dispose();
    return result;
  }
}
