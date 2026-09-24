import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:win32/win32.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';

enum SeatingExportFormat {
  pdf,
  excel,
  word,
}

class SeatingExportRow {
  final String grNo;
  final String studentFullName;
  final String seatNumber;
  final String className;
  final String bookName;

  const SeatingExportRow({
    required this.grNo,
    required this.studentFullName,
    required this.seatNumber,
    required this.className,
    required this.bookName,
  });
}

class SeatingExportService {
  static bool _isUrdu(String text) {
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x0600 && code <= 0x06FF) return true;
    }
    return false;
  }

  static String _escapeCsv(dynamic val) {
    if (val == null) return '""';
    String str = val.toString().replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
    if (str.contains(',') || str.contains('"') || str.contains(';') || str.contains('\t')) {
      str = str.replaceAll('"', '""');
      return '"$str"';
    }
    return '"$str"';
  }

  static Future<Map<String, pw.Font>> _loadCustomFonts() async {
    pw.Font? urduFont;
    pw.Font? urduBold;
    try {
      urduFont = await PdfGoogleFonts.amiriRegular();
      urduBold = await PdfGoogleFonts.amiriBold();
    } catch (_) {
      try {
        final fontData = await rootBundle.load('assets/fonts/JameelNooriNastaleeq.ttf');
        urduFont = pw.Font.ttf(fontData);
        urduBold = urduFont;
      } catch (_) {}
    }

    pw.Font? robotoFont;
    pw.Font? robotoBold;
    try {
      robotoFont = await PdfGoogleFonts.robotoRegular();
      robotoBold = await PdfGoogleFonts.robotoBold();
    } catch (_) {
      try {
        robotoFont = await PdfGoogleFonts.poppinsRegular();
        robotoBold = await PdfGoogleFonts.poppinsBold();
      } catch (_) {}
    }

    urduFont ??= pw.Font.helvetica();
    urduBold ??= pw.Font.helveticaBold();
    robotoFont ??= pw.Font.helvetica();
    robotoBold ??= pw.Font.helveticaBold();

    return {
      'urdu': urduFont,
      'urduBold': urduBold,
      'roboto': robotoFont,
      'robotoBold': robotoBold,
    };
  }

  static pw.Widget _buildCell(
    String text, {
    pw.Font? urduFont,
    pw.Font? urduBold,
    pw.Font? robotoFont,
    pw.Font? robotoBold,
    bool isHeader = false,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor? color,
    bool bold = false,
    double? fontSize,
  }) {
    final safeText = text.replaceAll('—', '-');
    final isUr = _isUrdu(safeText);

    pw.Font? primaryFont;
    if (isUr) {
      primaryFont = (bold || isHeader) ? (urduBold ?? urduFont) : urduFont;
    } else {
      primaryFont = (bold || isHeader) ? (robotoBold ?? robotoFont) : robotoFont;
    }

    final fallbacks = <pw.Font>[
      if (isUr && robotoFont != null) robotoFont,
      if (!isUr && urduFont != null) urduFont,
    ];

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        safeText,
        textAlign: align,
        textDirection: isUr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        style: pw.TextStyle(
          font: primaryFont,
          fontFallback: fallbacks,
          fontSize: fontSize ?? (isHeader ? 9.5 : 9),
          fontWeight: (isHeader || bold) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.white : (color ?? PdfColors.black),
        ),
      ),
    );
  }

  /// Generates Word Document (.doc format with full Office Word styling)
  static String _generateWordDoc({
    required String examName,
    required String hallName,
    required String className,
    required String sessionDate,
    required String sessionTime,
    required String bookNames,
    required List<SeatingExportRow> rows,
  }) {
    final buffer = StringBuffer();
    buffer.write('''<html xmlns:o='urn:schemas-microsoft-com:office:office' xmlns:w='urn:schemas-microsoft-com:office:word' xmlns='http://www.w3.org/TR/REC-html40'>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title>Seating Plan - $examName</title>
<!--[if gte mso 9]>
<xml>
<w:WordDocument>
<w:View>Print</w:View>
<w:Zoom>100</w:Zoom>
<w:DoNotOptimizeForBrowser/>
</w:WordDocument>
</xml>
<![endif]-->
<style>
  body { font-family: 'Segoe UI', Tahoma, 'Jameel Noori Nastaleeq', Arial, sans-serif; margin: 30px; color: #111827; }
  .header-card { border: 2px solid #0D6B4E; background: #F0FDF4; padding: 18px; border-radius: 8px; margin-bottom: 24px; }
  .title { font-size: 22px; font-weight: bold; color: #0D6B4E; text-align: center; margin-bottom: 14px; }
  .meta-table { width: 100%; border: none; border-collapse: collapse; }
  .meta-table td { padding: 5px 8px; font-size: 13px; border: none; }
  .table { width: 100%; border-collapse: collapse; margin-top: 15px; }
  .table th { background-color: #0D6B4E; color: white; padding: 10px 12px; border: 1px solid #999; font-size: 13px; text-align: center; }
  .table td { padding: 9px 12px; border: 1px solid #d1d5db; font-size: 12.5px; }
  .table tr:nth-child(even) { background-color: #F9FAFB; }
  .center { text-align: center; }
  .bold { font-weight: bold; }
</style>
</head>
<body>
<div class='header-card'>
  <div class='title'>EXAM SEATING PLAN (امتحانی نشستوں کا منصوبہ)</div>
  <table class='meta-table'>
    <tr>
      <td><b>Exam Name (امتحان کا نام):</b> $examName</td>
      <td><b>Exam Hall (امتحانی ہال):</b> $hallName</td>
    </tr>
    <tr>
      <td><b>Class Name (کلاس کا نام):</b> $className</td>
      <td><b>Exam Book / Subject (کتاب / مضمون):</b> $bookNames</td>
    </tr>
    <tr>
      <td><b>Exam Date & Time (تاریخ اور وقت):</b> $sessionDate ($sessionTime)</td>
      <td><b>Total Students (کل طلباء):</b> ${rows.length}</td>
    </tr>
  </table>
</div>
<table class='table'>
  <thead>
    <tr>
      <th style='width: 20%;'>GR. No. (جی آر نمبر)</th>
      <th style='width: 60%; text-align: left;'>Student Full Name (طالب علم کا مکمل نام)</th>
      <th style='width: 20%;'>Seat Number (نشست نمبر)</th>
    </tr>
  </thead>
  <tbody>
''');
    for (final r in rows) {
      buffer.write('''    <tr>
      <td class='center'>${r.grNo}</td>
      <td>${r.studentFullName}</td>
      <td class='center bold'>${r.seatNumber}</td>
    </tr>
''');
    }
    buffer.write('''  </tbody>
</table>
</body>
</html>''');
    return buffer.toString();
  }

  /// Generates Excel CSV with UTF-8 BOM
  static String _generateExcelCsv({
    required String examName,
    required String hallName,
    required String className,
    required String sessionDate,
    required String sessionTime,
    required String bookNames,
    required List<SeatingExportRow> rows,
  }) {
    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // UTF-8 BOM
    buffer.writeln('EXAM SEATING PLAN (امتحانی نشستوں کا منصوبہ)');
    buffer.writeln('Exam Name:,${_escapeCsv(examName)}');
    buffer.writeln('Exam Hall:,${_escapeCsv(hallName)}');
    buffer.writeln('Class Name:,${_escapeCsv(className)}');
    buffer.writeln('Exam Date & Time:,${_escapeCsv("$sessionDate $sessionTime")}');
    buffer.writeln('Exam Book / Subject:,${_escapeCsv(bookNames)}');
    buffer.writeln('Total Students:,${rows.length}');
    buffer.writeln();
    buffer.writeln('GR. No.,Student Full Name,Seat Number');
    for (final r in rows) {
      buffer.writeln('${_escapeCsv(r.grNo)},${_escapeCsv(r.studentFullName)},${_escapeCsv(r.seatNumber)}');
    }
    return buffer.toString();
  }

  /// Generates PDF document
  static Future<Uint8List> _generatePdf({
    required String examName,
    required String hallName,
    required String className,
    required String sessionDate,
    required String sessionTime,
    required String bookNames,
    required List<SeatingExportRow> rows,
  }) async {
    final fonts = await _loadCustomFonts();
    final urduFont = fonts['urdu']!;
    final urduBold = fonts['urduBold']!;
    final robotoFont = fonts['roboto']!;
    final robotoBold = fonts['robotoBold']!;

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: robotoFont,
        bold: robotoBold,
        fontFallback: [urduFont, urduBold],
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.teal900,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'EXAM SEATING PLAN (امتحانی نشستوں کا منصوبہ)',
                      style: pw.TextStyle(
                        font: robotoBold,
                        color: PdfColors.white,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                      style: pw.TextStyle(
                        font: robotoFont,
                        color: PdfColors.white,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.teal50,
                  border: pw.Border.all(color: PdfColors.teal300, width: 1),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCell('Exam: $examName', bold: true, fontSize: 10.5, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell('Hall: $hallName', bold: true, fontSize: 10.5, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCell('Class: $className', bold: true, color: PdfColors.teal900, fontSize: 10.5, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell('Book / Subject: $bookNames', fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCell('Date & Time: $sessionDate ($sessionTime)', fontSize: 9.5, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell('Total Students: ${rows.length}', bold: true, fontSize: 10, robotoFont: robotoFont, robotoBold: robotoBold),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
            ],
          );
        },
        build: (pw.Context ctx) {
          return [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.8), // GR. No.
                1: const pw.FlexColumnWidth(5.0), // Student Full Name
                2: const pw.FlexColumnWidth(1.8), // Seat Number
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.teal800),
                  children: [
                    _buildCell('GR. No.', isHeader: true, align: pw.TextAlign.center, color: PdfColors.white, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                    _buildCell('Student Full Name (نام، ولدیت، قومیت)', isHeader: true, align: pw.TextAlign.left, color: PdfColors.white, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                    _buildCell('Seat Number', isHeader: true, align: pw.TextAlign.center, color: PdfColors.white, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                  ],
                ),
                ...rows.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final r = entry.value;
                  final rowColor = idx % 2 == 0 ? PdfColors.white : PdfColors.grey100;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: rowColor),
                    children: [
                      _buildCell(r.grNo, align: pw.TextAlign.center, fontSize: 9.5, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell(r.studentFullName, align: pw.TextAlign.left, bold: true, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell(r.seatNumber, align: pw.TextAlign.center, bold: true, color: PdfColors.teal900, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Opens the Export Dialog and handles file generation and saving
  static Future<void> showExportDialog({
    required BuildContext context,
    required String examName,
    required String hallName,
    required String sessionDate,
    required String sessionTime,
    required List<SeatingExportRow> allRows,
    String? initialSelectedClass,
  }) async {
    if (allRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No seating arrangement records available to export. Please generate seating first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Extract unique classes
    final Set<String> uniqueClasses = {};
    for (final r in allRows) {
      if (r.className.trim().isNotEmpty) {
        uniqueClasses.add(r.className.trim());
      }
    }
    final classList = uniqueClasses.toList()..sort();

    String selectedClass = (initialSelectedClass != null && uniqueClasses.contains(initialSelectedClass))
        ? initialSelectedClass
        : 'All Classes';
    SeatingExportFormat selectedFormat = SeatingExportFormat.pdf;
    String sortOption = 'seat'; // 'seat', 'gr', 'name'

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;

            // Count matching records
            final matchingCount = selectedClass == 'All Classes'
                ? allRows.length
                : allRows.where((r) => r.className.trim() == selectedClass).length;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: isDark ? const Color(0xFF1E1E34) : Colors.white,
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.file_download_outlined, color: AppTheme.primaryColor, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Export Seating Plan',
                                style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'نشستوں کا منصوبہ برآمد کریں (PDF, Excel, Word)',
                                style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Session Info Box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A44) : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Exam: $examName',
                                  style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'Hall: $hallName',
                                  style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Date & Time: $sessionDate ($sessionTime)',
                            style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 1. Select Class
                    Text(
                      '1. Select Class (کلاس کا انتخاب کریں):',
                      style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A44) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedClass,
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(
                              value: 'All Classes',
                              child: Text('All Classes / تمام کلاسیں (${allRows.length} Students)'),
                            ),
                            ...classList.map((c) {
                              final count = allRows.where((r) => r.className.trim() == c).length;
                              return DropdownMenuItem(
                                value: c,
                                child: Text('$c ($count Students)'),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedClass = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. Select File Format
                    Text(
                      '2. Select File Format (فائل کی قسم منتخب کریں):',
                      style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildFormatCard(
                          title: 'PDF Document',
                          sub: '.pdf (Printable)',
                          icon: Icons.picture_as_pdf_rounded,
                          color: const Color(0xFFDC2626),
                          isSelected: selectedFormat == SeatingExportFormat.pdf,
                          onTap: () => setDialogState(() => selectedFormat = SeatingExportFormat.pdf),
                          isDark: isDark,
                        ),
                        const SizedBox(width: 10),
                        _buildFormatCard(
                          title: 'Excel Sheet',
                          sub: '.csv (MS Excel)',
                          icon: Icons.table_chart_rounded,
                          color: const Color(0xFF16A34A),
                          isSelected: selectedFormat == SeatingExportFormat.excel,
                          onTap: () => setDialogState(() => selectedFormat = SeatingExportFormat.excel),
                          isDark: isDark,
                        ),
                        const SizedBox(width: 10),
                        _buildFormatCard(
                          title: 'Word Document',
                          sub: '.doc (MS Word)',
                          icon: Icons.description_rounded,
                          color: const Color(0xFF2563EB),
                          isSelected: selectedFormat == SeatingExportFormat.word,
                          onTap: () => setDialogState(() => selectedFormat = SeatingExportFormat.word),
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3. Sort Order
                    Text(
                      '3. Sort Order (ترتیب):',
                      style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildSortRadio('By Seat Number (نشست کے مطابق)', 'seat', sortOption, (v) {
                          setDialogState(() => sortOption = v);
                        }),
                        const SizedBox(width: 16),
                        _buildSortRadio('By GR. No. (جی آر نمبر)', 'gr', sortOption, (v) {
                          setDialogState(() => sortOption = v);
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: const Text('Cancel / منسوخ'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: matchingCount == 0
                              ? null
                              : () async {
                                  Navigator.pop(dialogCtx);
                                  await _executeExport(
                                    context: context,
                                    examName: examName,
                                    hallName: hallName,
                                    className: selectedClass,
                                    sessionDate: sessionDate,
                                    sessionTime: sessionTime,
                                    allRows: allRows,
                                    selectedFormat: selectedFormat,
                                    sortOption: sortOption,
                                  );
                                },
                          icon: const Icon(Icons.file_download_rounded, size: 18),
                          label: Text(
                            'Export ($matchingCount Students)',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildFormatCard({
    required String title,
    required String sub,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : (isDark ? const Color(0xFF2A2A44) : Colors.grey.shade50),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : (isDark ? Colors.white12 : Colors.grey.shade300),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTheme.getFontStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              Text(
                sub,
                style: AppTheme.getFontStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSortRadio(
    String label,
    String val,
    String current,
    ValueChanged<String> onChanged,
  ) {
    return InkWell(
      onTap: () => onChanged(val),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<String>(
            value: val,
            groupValue: current,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  static Future<void> _executeExport({
    required BuildContext context,
    required String examName,
    required String hallName,
    required String className,
    required String sessionDate,
    required String sessionTime,
    required List<SeatingExportRow> allRows,
    required SeatingExportFormat selectedFormat,
    required String sortOption,
  }) async {
    // 1. Filter rows
    List<SeatingExportRow> targetRows = (className == 'All Classes')
        ? List<SeatingExportRow>.from(allRows)
        : allRows.where((r) => r.className.trim() == className).toList();

    // 2. Sort rows
    if (sortOption == 'seat') {
      targetRows.sort((a, b) {
        final nA = int.tryParse(a.seatNumber.replaceAll(RegExp(r'\D'), '')) ?? 999999;
        final nB = int.tryParse(b.seatNumber.replaceAll(RegExp(r'\D'), '')) ?? 999999;
        return nA.compareTo(nB);
      });
    } else if (sortOption == 'gr') {
      targetRows.sort((a, b) {
        final gA = int.tryParse(a.grNo.replaceAll(RegExp(r'\D'), '')) ?? 999999;
        final gB = int.tryParse(b.grNo.replaceAll(RegExp(r'\D'), '')) ?? 999999;
        return gA.compareTo(gB);
      });
    }

    // Extract book names
    final Set<String> books = {};
    for (final r in targetRows) {
      if (r.bookName.trim().isNotEmpty) {
        books.add(r.bookName.trim());
      }
    }
    final bookNames = books.isEmpty ? 'All Scheduled Books' : books.join(', ');

    // 3. Prepare File details
    final cleanExam = examName.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '_');
    final cleanHall = hallName.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '_');
    final cleanClass = className.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '_');

    String ext = 'pdf';
    int defaultFilterIndex = 1;
    if (selectedFormat == SeatingExportFormat.excel) {
      ext = 'csv';
      defaultFilterIndex = 2;
    } else if (selectedFormat == SeatingExportFormat.word) {
      ext = 'doc';
      defaultFilterIndex = 3;
    }

    final defaultFileName = 'Seating_${cleanClass}_${cleanHall}_$cleanExam.$ext';
    String? savePath;
    SeatingExportFormat actualFormat = selectedFormat;

    if (Platform.isWindows) {
      final winResult = await _showWindowsSaveFileDialog(
        title: 'Save Seating Plan (PDF, Excel, Word)',
        defaultFileName: defaultFileName,
        initialFilterIndex: defaultFilterIndex,
      );
      if (winResult == null) return; // User cancelled

      String chosenPath = winResult.filePath;
      final extName = p.extension(chosenPath).toLowerCase();

      if (extName == '.pdf') {
        actualFormat = SeatingExportFormat.pdf;
      } else if (extName == '.csv' || extName == '.xlsx') {
        actualFormat = SeatingExportFormat.excel;
      } else if (extName == '.doc' || extName == '.docx') {
        actualFormat = SeatingExportFormat.word;
      } else {
        // If user typed without extension, append based on selected filter
        if (winResult.filterIndex == 1) {
          chosenPath += '.pdf';
          actualFormat = SeatingExportFormat.pdf;
        } else if (winResult.filterIndex == 2) {
          chosenPath += '.csv';
          actualFormat = SeatingExportFormat.excel;
        } else if (winResult.filterIndex == 3) {
          chosenPath += '.doc';
          actualFormat = SeatingExportFormat.word;
        }
      }
      savePath = chosenPath;
    } else {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Seating Plan',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'csv', 'doc'],
      );
      if (savePath == null) return;
      final extName = p.extension(savePath).toLowerCase();
      if (extName == '.csv' || extName == '.xlsx') {
        actualFormat = SeatingExportFormat.excel;
      } else if (extName == '.doc' || extName == '.docx') {
        actualFormat = SeatingExportFormat.word;
      } else {
        actualFormat = SeatingExportFormat.pdf;
      }
    }

    final actualSavePath = savePath;
    try {
      final file = File(actualSavePath);
      if (actualFormat == SeatingExportFormat.pdf) {
        final pdfBytes = await _generatePdf(
          examName: examName,
          hallName: hallName,
          className: className,
          sessionDate: sessionDate,
          sessionTime: sessionTime,
          bookNames: bookNames,
          rows: targetRows,
        );
        await file.writeAsBytes(pdfBytes);
      } else if (actualFormat == SeatingExportFormat.excel) {
        final csvContent = _generateExcelCsv(
          examName: examName,
          hallName: hallName,
          className: className,
          sessionDate: sessionDate,
          sessionTime: sessionTime,
          bookNames: bookNames,
          rows: targetRows,
        );
        await file.writeAsString(csvContent, encoding: utf8);
      } else if (actualFormat == SeatingExportFormat.word) {
        final docContent = _generateWordDoc(
          examName: examName,
          hallName: hallName,
          className: className,
          sessionDate: sessionDate,
          sessionTime: sessionTime,
          bookNames: bookNames,
          rows: targetRows,
        );
        await file.writeAsString(docContent, encoding: utf8);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Seating Plan saved successfully: ${file.path.split(Platform.pathSeparator).last}'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Open / کھولیں',
              textColor: Colors.white,
              onPressed: () async {
                try {
                  await launchUrl(Uri.file(actualSavePath));
                } catch (_) {
                  Process.run('explorer.exe', ['/select,', actualSavePath]);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _Win32SaveResult {
  final String filePath;
  final int filterIndex; // 1: PDF, 2: Excel, 3: Word, 4: All

  _Win32SaveResult({required this.filePath, required this.filterIndex});
}

class _Win32SaveArgs {
  final SendPort port;
  final String title;
  final String defaultName;
  final int initialFilterIndex;

  _Win32SaveArgs({
    required this.port,
    required this.title,
    required this.defaultName,
    required this.initialFilterIndex,
  });
}

void _runWin32SaveDialogInIsolate(_Win32SaveArgs args) {
  final openFileName = calloc<OPENFILENAME>();

  const filter =
      'PDF Document (*.pdf)\x00*.pdf\x00'
      'Excel Spreadsheet (*.csv;*.xlsx)\x00*.csv;*.xlsx\x00'
      'Word Document (*.doc;*.docx)\x00*.doc;*.docx\x00'
      'All Files (*.*)\x00*.*\x00\x00';

  final bufferSize = 8192;
  final fileBuffer = calloc<Uint16>(bufferSize);

  final units = args.defaultName.codeUnits;
  for (int i = 0; i < units.length && i < bufferSize - 1; i++) {
    fileBuffer[i] = units[i];
  }
  fileBuffer[units.length < bufferSize ? units.length : bufferSize - 1] = 0;

  openFileName.ref.lStructSize = sizeOf<OPENFILENAME>();
  openFileName.ref.lpstrFilter = filter.toNativeUtf16();
  openFileName.ref.nFilterIndex = args.initialFilterIndex;
  openFileName.ref.lpstrFile = fileBuffer.cast<Utf16>();
  openFileName.ref.nMaxFile = bufferSize;
  openFileName.ref.lpstrTitle = args.title.toNativeUtf16();
  openFileName.ref.Flags = OFN_EXPLORER | OFN_OVERWRITEPROMPT | OFN_NOCHANGEDIR;

  final result = GetSaveFileName(openFileName);
  if (result == 1) {
    final buffer = StringBuffer();
    final ptr = openFileName.ref.lpstrFile.cast<Uint16>();
    int i = 0;
    while (ptr[i] != 0) {
      buffer.writeCharCode(ptr[i]);
      i++;
    }
    final selectedPath = buffer.toString();
    final filterIndex = openFileName.ref.nFilterIndex;
    args.port.send(_Win32SaveResult(filePath: selectedPath, filterIndex: filterIndex));
  } else {
    args.port.send(null);
  }

  calloc.free(openFileName.ref.lpstrFilter);
  calloc.free(openFileName.ref.lpstrTitle);
  calloc.free(openFileName.ref.lpstrFile);
  calloc.free(openFileName);
}

Future<_Win32SaveResult?> _showWindowsSaveFileDialog({
  required String title,
  required String defaultFileName,
  required int initialFilterIndex,
}) async {
  final port = ReceivePort();
  await Isolate.spawn(
    _runWin32SaveDialogInIsolate,
    _Win32SaveArgs(
      port: port.sendPort,
      title: title,
      defaultName: defaultFileName,
      initialFilterIndex: initialFilterIndex,
    ),
  );
  final res = await port.first;
  return res as _Win32SaveResult?;
}

