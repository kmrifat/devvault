import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'external_ui.dart';

/// The recovery kit as a document the user keeps: plain text or a one-page
/// PDF. Built in memory only. Nothing is written anywhere except where the
/// user saves it, or handed to the print dialog.
class RecoveryKitDocument {
  const RecoveryKitDocument({
    required this.recoveryKey,
    required this.vaultId,
    required this.created,
  });

  /// The key as shown: 14 groups joined by `-`.
  final String recoveryKey;
  final String vaultId;
  final DateTime created;

  static const fileStem = 'DevVault Recovery Key';

  static const _advice = [
    'This key unlocks your vault and lets you set a new master password.',
    'Keep it offline: a password manager, a printed copy or a safe.',
    "Don't store it inside DevVault itself.",
  ];

  String get _date => DateFormat.yMMMMd().format(created);

  List<String> get groups => recoveryKey.split('-');

  String toText() =>
      'DevVault recovery key\n'
      '\n'
      '$recoveryKey\n'
      '\n'
      'Vault: $vaultId\n'
      'Created: $_date\n'
      '\n'
      '${_advice.join('\n')}\n';

  Uint8List toTextBytes() => Uint8List.fromList(utf8.encode(toText()));

  /// A single A4 page: the key large in a monospaced face, the vault id,
  /// the date and what the key is for.
  Future<Uint8List> toPdf(RecoveryKitFonts fonts) {
    final doc = pw.Document(
      title: fileStem,
      author: 'DevVault',
      creator: 'DevVault',
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );
    final rows = [
      for (var i = 0; i < groups.length; i += 7)
        groups.skip(i).take(7).join('  '),
    ];
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(56),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'DevVault recovery kit',
              style: pw.TextStyle(font: fonts.bold, fontSize: 24),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Created $_date',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 32),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Recovery key',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  for (final row in rows)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Text(
                        row,
                        style: pw.TextStyle(
                          font: fonts.mono,
                          fontSize: 17,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Vault $vaultId',
              style: pw.TextStyle(
                font: fonts.mono,
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 32),
            for (final line in _advice)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(line, style: const pw.TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}

/// The app's own fonts, embedded in the PDF so it looks like the app and
/// needs nothing from the system.
class RecoveryKitFonts {
  const RecoveryKitFonts({
    required this.regular,
    required this.bold,
    required this.mono,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font mono;

  static Future<RecoveryKitFonts> load() async {
    Future<pw.Font> font(String file) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
    return RecoveryKitFonts(
      regular: await font('Inter-Regular.ttf'),
      bold: await font('Inter-SemiBold.ttf'),
      mono: await font('JetBrainsMono-Medium.ttf'),
    );
  }
}

/// Hands a PDF to the system print dialog. Abstract so tests don't print.
abstract interface class DocumentPrinter {
  /// Returns `false` if the user cancelled or there's nothing to print on.
  Future<bool> printPdf(Uint8List bytes, {required String name});
}

class SystemDocumentPrinter implements DocumentPrinter {
  const SystemDocumentPrinter();

  @override
  Future<bool> printPdf(Uint8List bytes, {required String name}) =>
      ExternalUi.run(
        () => Printing.layoutPdf(onLayout: (_) async => bytes, name: name),
      );
}
