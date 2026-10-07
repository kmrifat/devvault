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
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(BCSpacing.md),
              child: Row(
                children: [
                  BCCloseButton(onPressed: () => Navigator.of(context).pop()),
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
        ],
      ),
    );
  }
}
