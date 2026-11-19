import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'reports.dart';

/// A4 PDF of one report, drawn from the same sections as the screen.
Future<Uint8List> buildReportPdf({
  required ReportData data,
  required String gymName,
  required String periodLabel,
  required String generatedOn,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Geist_400Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Geist_700Bold.ttf'),
  );
  final muted = PdfColor.fromInt(0xFF6B6E75);
  final bar = PdfColor.fromInt(0xFF2A2C31);
  final loss = PdfColor.fromInt(0xFFC0392B);
  final line = PdfColor.fromInt(0xFFDDDDDD);
  final document = pw.Document(
    title: '${data.kind.title} · $periodLabel',
    author: gymName,
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  pw.Widget section(ReportSection section) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.SizedBox(height: 14),
      pw.Text(section.title, style: pw.TextStyle(font: bold, fontSize: 13)),
      if (section.note != null)
        pw.Text(section.note!, style: pw.TextStyle(color: muted, fontSize: 9)),
      pw.SizedBox(height: 6),
      if (section.isEmpty && section.empty != null)
        pw.Text(section.empty!, style: pw.TextStyle(color: muted)),
      if (section.figures.isNotEmpty)
        pw.Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            for (final figure in section.figures)
              pw.SizedBox(
                width: 110,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      figure.value,
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 14,
                        color: figure.warn ? loss : null,
                      ),
                    ),
                    pw.Text(
                      figure.label,
                      style: pw.TextStyle(color: muted, fontSize: 9),
                    ),
                  ],
                ),
              ),
          ],
        ),
      for (final item in section.bars)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 110,
                child: pw.Text(
                  item.label,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.Expanded(
                child: pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Container(
                    height: 8,
                    width: 220 * item.fraction + 1,
                    color: item.negative ? loss : bar,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 80,
                child: pw.Text(
                  item.value,
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
        ),
      for (final row in section.rows)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.5)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(row.title, style: const pw.TextStyle(fontSize: 10)),
                    if (row.subtitle != null)
                      pw.Text(
                        row.subtitle!,
                        style: pw.TextStyle(color: muted, fontSize: 8),
                      ),
                  ],
                ),
              ),
              pw.Text(
                row.trailing,
                style: pw.TextStyle(font: bold, fontSize: 10),
              ),
            ],
          ),
        ),
    ],
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Text(
              '${data.kind.title} · $gymName',
              style: pw.TextStyle(color: muted, fontSize: 8),
            ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated $generatedOn with MuscleDesk',
            style: pw.TextStyle(color: muted, fontSize: 8),
          ),
          pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(color: muted, fontSize: 8),
          ),
        ],
      ),
      build: (_) => [
        pw.Text(gymName, style: pw.TextStyle(color: muted)),
        pw.Text(data.kind.title, style: pw.TextStyle(font: bold, fontSize: 22)),
        pw.Text(
          [
            periodLabel,
            if (data.allBranches)
              'All branches: ${data.branchNames.join(', ')}',
          ].join(' · '),
          style: pw.TextStyle(color: muted),
        ),
        for (final item in reportSections(data)) section(item),
      ],
    ),
  );
  return document.save();
}
