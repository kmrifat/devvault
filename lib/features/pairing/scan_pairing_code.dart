import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/pairing.dart';
import '../../shared/ui.dart';

/// Whether this device can scan a pairing QR (phones; desktops paste the
/// text instead).
bool get canScanPairingCode => switch (defaultTargetPlatform) {
  TargetPlatform.iOS || TargetPlatform.android => !kIsWeb,
  _ => false,
};

/// Opens the camera until a DevVault pairing QR is in view, and returns
/// its text (null if the user backs out). Other QR codes are ignored.
Future<String?> scanPairingCode(BuildContext context) => Navigator.of(context)
    .push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _ScanScreen(),
      ),
    );

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final text = code.rawValue;
      if (text != null && text.startsWith(Pairing.prefix)) {
        _done = true;
        Navigator.of(context).pop(text);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Scaffold(
      backgroundColor: bc.background,
      // Expand: without it the stack took the size of its one unpositioned
      // child, the header, and the camera filled only that strip.
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Where to hold the code.
          Center(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: bc.accent, width: 3),
                  borderRadius: BorderRadius.circular(BCRadius.xxl),
                ),
                child: const SizedBox.square(dimension: 240),
              ),
            ),
          ),
          // The header over a band of the background colour, so its text
          // reads over any picture.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bc.background.withValues(alpha: 0.85),
                    bc.background.withValues(alpha: 0),
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BCSpacing.md,
                    BCSpacing.md,
                    BCSpacing.md,
                    BCSpacing.xl,
                  ),
                  child: Row(
                    children: [
                      BCCloseButton(
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: BCSpacing.sm),
                      const Expanded(
                        child: BCText(
                          'Point the camera at the code on your other device',
                          weight: BCTextWeight.medium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
