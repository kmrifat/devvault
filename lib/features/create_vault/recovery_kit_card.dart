import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../services/recovery_kit.dart';
import '../../shared/ui.dart';

/// The recovery key, shown large, with the ways to keep it: a PDF, a
/// printout, a text file or the clipboard (cleared after 30 s).
///
/// Used on a phone's first run and when the user makes a new kit from
/// Settings (P4-05); the desktop first run (N02) has its own layout and
/// shares the actions through [RecoveryKitActions]. Documents are built in
/// memory and handed straight to the save or print dialog; the PDF bytes
/// are wiped afterwards.
class RecoveryKitCard extends ConsumerStatefulWidget {
  const RecoveryKitCard({super.key, required this.kit});

  final RecoveryKitDocument kit;

  @override
  ConsumerState<RecoveryKitCard> createState() => _RecoveryKitCardState();
}

class _RecoveryKitCardState extends ConsumerState<RecoveryKitCard>
    with RecoveryKitActions {
  @override
  RecoveryKitDocument get kit => widget.kit;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return BCCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: BCSpacing.md,
        children: [
          Row(
            spacing: BCSpacing.sm,
            children: [
              Icon(LucideIcons.keyRound, size: 16, color: bc.accent),
              const BCText(
                'Recovery key',
                type: BCTextType.bodySm,
                weight: BCTextWeight.semibold,
              ),
              const Spacer(),
              Flexible(
                child: MonoText(
                  'vault ${widget.kit.vaultId}',
                  middleEllipsis: true,
                  style: TextStyle(
                    fontSize: BCTypography.sizeXs,
                    color: bc.muted,
                  ),
                ),
              ),
            ],
          ),
          Semantics(
            label: 'Recovery key',
            value: widget.kit.recoveryKey,
            child: SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: bc.background,
                  shape: BCShapes.continuous(BCRadius.xxl),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: _KeyGrid(groups: widget.kit.groups),
                ),
              ),
            ),
          ),
          Wrap(
            spacing: BCSpacing.sm,
            runSpacing: BCSpacing.sm,
            children: [
              BCButton(
                size: BCButtonSize.sm,
                isDisabled: kitBusy,
                onPressed: saveKitPdf,
                startContent: const Icon(LucideIcons.fileDown, size: 15),
                child: const Text('Save PDF'),
              ),
              BCButton(
                size: BCButtonSize.sm,
                variant: BCButtonVariant.secondary,
                isDisabled: kitBusy,
                onPressed: printKit,
                startContent: const Icon(LucideIcons.printer, size: 15),
                child: const Text('Print'),
              ),
              BCButton(
                size: BCButtonSize.sm,
                variant: BCButtonVariant.secondary,
                onPressed: saveKitText,
                startContent: const Icon(LucideIcons.fileText, size: 15),
                child: const Text('Save as text'),
              ),
              BCButton(
                size: BCButtonSize.sm,
                variant: BCButtonVariant.secondary,
                onPressed: copyKit,
                startContent: const Icon(LucideIcons.copy, size: 15),
                child: const Text('Copy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 14 groups of the recovery key: two rows of 7 when there's room,
/// rows of 4 on a phone.
class _KeyGrid extends StatelessWidget {
  const _KeyGrid({required this.groups});

  final List<String> groups;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 460 ? 7 : 4;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            for (var i = 0; i < groups.length; i += perRow)
              MonoText(
                groups.skip(i).take(perRow).join('  '),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: BCTypography.medium,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// What can be done with a recovery kit: copy the key (through the
/// clipboard guard, cleared after 30 s), save it as text or PDF, or print
/// it. Shared by [RecoveryKitCard] and the desktop recovery kit (N02).
///
/// PDFs are built in memory and handed straight to the save or print
/// dialog; their bytes are wiped afterwards. Feedback names the action,
/// never the key.
mixin RecoveryKitActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  RecoveryKitDocument get kit;

  /// A PDF is being made.
  bool kitBusy = false;

  void _toast(String title, {String? description, bool ok = true}) {
    showAppToast(
      context,
      BCToastData(
        title: title,
        description: description,
        variant: ok ? BCToastVariant.success : BCToastVariant.danger,
      ),
    );
  }

  Future<void> copyKit() async {
    await ref.read(clipboardGuardProvider).copySecret(kit.recoveryKey);
    if (mounted) {
      _toast(
        'Recovery key copied',
        description: 'It clears from the clipboard in 30 seconds.',
      );
    }
  }

  Future<void> saveKitText() async {
    final saved = await ref
        .read(fileSaverProvider)
        .save(
          fileName: '${RecoveryKitDocument.fileStem}.txt',
          bytes: kit.toTextBytes(),
          mimeType: 'text/plain',
        );
    if (mounted && saved) _toast('Recovery kit saved');
  }

  /// Builds the PDF, hands it to [use], then wipes the bytes.
  Future<void> _withPdf(Future<void> Function(Uint8List pdf) use) async {
    if (kitBusy) return;
    setState(() => kitBusy = true);
    Uint8List? pdf;
    try {
      pdf = await kit.toPdf(await RecoveryKitFonts.load());
      await use(pdf);
    } on Object {
      if (mounted) {
        _toast("Couldn't make the PDF", ok: false);
      }
    } finally {
      pdf?.fillRange(0, pdf.length, 0);
      if (mounted) setState(() => kitBusy = false);
    }
  }

  Future<void> saveKitPdf() => _withPdf((pdf) async {
    final saved = await ref
        .read(fileSaverProvider)
        .save(
          fileName: '${RecoveryKitDocument.fileStem}.pdf',
          bytes: pdf,
          mimeType: 'application/pdf',
        );
    if (mounted && saved) _toast('Recovery kit saved as PDF');
  });

  Future<void> printKit() => _withPdf((pdf) async {
    await ref
        .read(documentPrinterProvider)
        .printPdf(pdf, name: RecoveryKitDocument.fileStem);
  });
}
