import '../../../../core/utils/urdu_number_helper.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart'
    show BuildContext, Color, Colors, ScaffoldMessenger, SnackBar, Text, TextAlign;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../data/models/designer_template_model.dart';
import '../../data/models/sample_document_data.dart';

class UniversalPdfExporter {
  /// Loads custom fonts for rendering Urdu Nastaleeq, Arabic, and English
  static Future<Map<String, pw.Font>> _loadFonts() async {
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

  static bool _containsUrdu(String text) {
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x0600 && code <= 0x06FF) return true;
    }
    return false;
  }

  static PdfColor _toPdfColor(dynamic color) {
    if (color == null) return PdfColors.black;
    if (color is Color) {
      if (color == Colors.transparent) return PdfColors.white;
      return PdfColor(color.r, color.g, color.b, color.a);
    }
    return PdfColors.black;
  }

  static String _resolveElementText(DesignerElement el, Map<String, String>? dynamicData) {
    String str = el.text;
    if (el.tokenKey != null && el.tokenKey!.isNotEmpty) {
      if (dynamicData != null && dynamicData.containsKey(el.tokenKey)) {
        str = dynamicData[el.tokenKey]!;
      } else {
        str = SampleDocumentData.resolveTokens(el.tokenKey!);
      }
    } else {
      str = SampleDocumentData.resolveTokens(str);
    }
    if (el.showTitlePrefix && el.titlePrefix.isNotEmpty) {
      str = '${el.titlePrefix} $str';
    }
    if (el.tokenKey != null && (el.tokenKey!.contains('gr_no') || el.tokenKey!.contains('barcode'))) {
      return str;
    }
    return UrduNumberHelper.convertDigits(str, 'ur');
  }

  /// Builds a single card or document page widget for a specific side ('front' or 'back')
  static pw.Widget _buildPageSide(
    DesignerTemplate template,
    String side,
    Map<String, String>? dynamicData,
    Map<String, pw.Font> fonts,
    double widthPt,
    double heightPt,
  ) {
    final elements = template.elements
        .where((e) => e.isVisible && (e.side == side || template.preset == CanvasPreset.a4Portrait || template.preset == CanvasPreset.a4Landscape))
        .toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    final isFront = side == 'front';
    final bgPath = isFront ? template.backgroundImageFrontPath : template.backgroundImageBackPath;
    final useBgImg = isFront ? template.useFrontTemplate : template.useBackTemplate;

    pw.MemoryImage? bgImage;
    if (useBgImg && bgPath != null && bgPath.isNotEmpty) {
      final file = File(bgPath);
      if (file.existsSync()) {
        try {
          bgImage = pw.MemoryImage(file.readAsBytesSync());
        } catch (_) {}
      }
    }

    return pw.Container(
      width: widthPt,
      height: heightPt,
      decoration: pw.BoxDecoration(
        color: template.isTransparentPageBg ? null : (template.isGradient ? null : _toPdfColor(template.backgroundColor)),
        gradient: (!template.isTransparentPageBg && template.isGradient)
            ? pw.LinearGradient(
                begin: pw.Alignment.topLeft,
                end: pw.Alignment.bottomRight,
                colors: [_toPdfColor(template.backgroundColor), _toPdfColor(template.backgroundColor2)],
              )
            : null,
        borderRadius: pw.BorderRadius.circular(template.borderRadius * 0.75),
        border: (!template.isTransparentPageBg && template.borderWidth > 0)
            ? pw.Border.all(color: _toPdfColor(template.borderColor), width: template.borderWidth)
            : null,
        image: bgImage != null ? pw.DecorationImage(image: bgImage, fit: pw.BoxFit.cover) : null,
      ),
      child: pw.Stack(
        children: elements.map((el) {
          final elLeft = el.xRatio * widthPt;
          final elTop = el.yRatio * heightPt;
          final elWidth = el.widthRatio * widthPt;
          final elHeight = el.heightRatio * heightPt;

          return pw.Positioned(
            left: elLeft,
            top: elTop,
            child: pw.SizedBox(
              width: elWidth,
              height: elHeight,
              child: _buildPdfElement(el, dynamicData, fonts, elWidth, elHeight),
            ),
          );
        }).toList(),
      ),
    );
  }

  static pw.Widget _buildPdfElement(
    DesignerElement el,
    Map<String, String>? dynamicData,
    Map<String, pw.Font> fonts,
    double elWidth,
    double elHeight,
  ) {
    switch (el.type) {
      case DesignerElementType.text:
      case DesignerElementType.token:
        final str = _resolveElementText(el, dynamicData);
        final isUrdu = _containsUrdu(str);
        final font = isUrdu
            ? (el.fontWeight.value >= 600 ? fonts['urduBold']! : fonts['urdu']!)
            : (el.fontWeight.value >= 600 ? fonts['robotoBold']! : fonts['roboto']!);

        pw.TextAlign align;
        switch (el.textAlign) {
          case TextAlign.left:
            align = pw.TextAlign.left;
            break;
          case TextAlign.right:
            align = pw.TextAlign.right;
            break;
          case TextAlign.center:
          default:
            align = pw.TextAlign.center;
            break;
        }

        return pw.Container(
          alignment: align == pw.TextAlign.right
              ? pw.Alignment.centerRight
              : (align == pw.TextAlign.left ? pw.Alignment.centerLeft : pw.Alignment.center),
          decoration: el.backgroundColor != null
              ? pw.BoxDecoration(
                  color: _toPdfColor(el.backgroundColor),
                  borderRadius: pw.BorderRadius.circular(el.borderRadius * 0.75),
                  border: el.borderWidth > 0 ? pw.Border.all(color: _toPdfColor(el.borderColor), width: el.borderWidth) : null,
                )
              : null,
          child: pw.Text(
            str,
            textDirection: isUrdu ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            textAlign: align,
            style: pw.TextStyle(
              font: font,
              fontSize: el.fontSize,
              color: _toPdfColor(el.color),
              decoration: el.isUnderline ? pw.TextDecoration.underline : null,
            ),
          ),
        );

      case DesignerElementType.photo:
        pw.MemoryImage? photoImg;
        if (el.imagePath != null && el.imagePath!.isNotEmpty) {
          final f = File(el.imagePath!);
          if (f.existsSync()) {
            try {
              photoImg = pw.MemoryImage(f.readAsBytesSync());
            } catch (_) {}
          }
        }
        if (photoImg != null) {
          if (el.isRoundPhoto || el.isCircular) {
            return pw.ClipOval(
              child: pw.Image(photoImg, width: elWidth, height: elHeight, fit: pw.BoxFit.cover),
            );
          }
          return pw.Container(
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(el.borderRadius * 0.75),
              border: el.borderWidth > 0 ? pw.Border.all(color: _toPdfColor(el.borderColor), width: el.borderWidth) : null,
            ),
            child: pw.Image(photoImg, width: elWidth, height: elHeight, fit: pw.BoxFit.cover),
          );
        }
        return pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfColors.grey300,
            borderRadius: pw.BorderRadius.circular(el.isRoundPhoto ? elWidth / 2 : el.borderRadius * 0.75),
            border: pw.Border.all(color: _toPdfColor(el.borderColor ?? Colors.grey.shade400), width: el.borderWidth > 0 ? el.borderWidth : 1.0),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text('PHOTO', style: pw.TextStyle(font: fonts['robotoBold'], fontSize: 10, color: PdfColors.grey700)),
        );

      case DesignerElementType.qrCode:
        final qrPayload = dynamicData?['{{student.gr_no}}'] != null
            ? 'GR:${dynamicData!['{{student.gr_no}}']}\nName:${dynamicData['{{student.name}}'] ?? ''}'
            : (el.text.isNotEmpty ? el.text : 'MADARSA_VERIFICATION_PASS');
        return pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: qrPayload,
            width: elWidth,
            height: elHeight,
            color: _toPdfColor(el.color),
          ),
        );

      case DesignerElementType.barcode:
        final barcodeData = dynamicData?['{{student.gr_no}}'] ?? (el.text.isNotEmpty ? el.text : '1045268');
        return pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: barcodeData,
            width: elWidth,
            height: elHeight,
            color: _toPdfColor(el.color),
            drawText: true,
          ),
        );

      case DesignerElementType.table:
        return _buildPdfTable(el, fonts, elWidth);

      case DesignerElementType.signature:
      case DesignerElementType.stamp:
        pw.MemoryImage? img;
        if (el.imagePath != null && el.imagePath!.isNotEmpty) {
          final f = File(el.imagePath!);
          if (f.existsSync()) {
            try {
              img = pw.MemoryImage(f.readAsBytesSync());
            } catch (_) {}
          }
        }
        if (img != null) {
          return pw.Image(img, fit: pw.BoxFit.contain);
        }
        return pw.Container(
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _toPdfColor(el.color), style: pw.BorderStyle.dashed),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            el.type == DesignerElementType.signature ? 'Authorized Signature' : 'Official Seal / Stamp',
            style: pw.TextStyle(font: fonts['roboto'], fontSize: 9, color: _toPdfColor(el.color)),
          ),
        );

      case DesignerElementType.dividerLine:
        return pw.Center(
          child: pw.Container(
            height: el.borderWidth > 0 ? el.borderWidth : 1.5,
            color: _toPdfColor(el.color),
          ),
        );

      case DesignerElementType.gradingScale:
        return _buildPdfGradingScale(el, fonts, elWidth);

      case DesignerElementType.shape:
      case DesignerElementType.logo:
        return pw.Container(
          decoration: pw.BoxDecoration(
            color: el.backgroundColor != null ? _toPdfColor(el.backgroundColor) : null,
            borderRadius: pw.BorderRadius.circular(el.isCircular ? elWidth / 2 : el.borderRadius * 0.75),
            border: el.borderWidth > 0 ? pw.Border.all(color: _toPdfColor(el.borderColor), width: el.borderWidth) : null,
          ),
        );
    }
  }

  static pw.Widget _buildPdfGradingScale(DesignerElement el, Map<String, pw.Font> fonts, double elWidth) {
    const rules = [
      ('ممتاز (Distinction)', '90% – 100%'),
      ('جید جداً (First Class)', '75% – 89%'),
      ('جید (Second Class)', '60% – 74%'),
      ('مقبول (Pass)', '33% – 59%'),
      ('راسب (Fail)', '< 33%'),
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.all(3),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _toPdfColor(el.color), width: 0.8),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            color: _toPdfColor(el.color),
            child: pw.Text(
              'پیمانہ درجات (Grading Scale)',
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: fonts['urduBold'], fontSize: 8, color: PdfColors.white),
            ),
          ),
          pw.SizedBox(height: 2),
          ...rules.map((r) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1, horizontal: 2),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(r.$1, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: fonts['urdu'], fontSize: 7)),
                  pw.Text(r.$2, style: pw.TextStyle(font: fonts['roboto'], fontSize: 7)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfTable(DesignerElement el, Map<String, pw.Font> fonts, double elWidth) {
    final cfg = el.tableConfig ?? {};
    final subjects = List<Map<String, dynamic>>.from(cfg['subjects'] as List<dynamic>? ?? []);
    final cols = List<Map<String, dynamic>>.from(cfg['columns'] as List<dynamic>? ?? []);
    final isTransHdr = cfg['transparentHeader'] == true;
    final isTransRows = cfg['transparentRows'] == true;
    final headerBg = isTransHdr ? null : (cfg['headerBg'] != null ? PdfColor.fromInt(cfg['headerBg'] as int) : PdfColors.teal800);
    final headerTextColor = isTransHdr ? PdfColors.black : (cfg['headerTextColor'] != null ? PdfColor.fromInt(cfg['headerTextColor'] as int) : PdfColors.white);
    final rowTextColor = cfg['rowTextColor'] != null ? PdfColor.fromInt(cfg['rowTextColor'] as int) : PdfColors.black;
    final gridColor = cfg['gridColor'] != null ? PdfColor.fromInt(cfg['gridColor'] as int) : PdfColors.grey400;
    final gridWidth = (cfg['gridWidth'] as num?)?.toDouble() ?? 0.8;
    final altRowBg = (isTransRows || cfg['alternateRowColors'] == false) ? null : const PdfColor(0.97, 0.98, 0.99);

    final visibleCols = cols.isEmpty
        ? [
            {'id': 'col1', 'title': 'نمبر شمار', 'width': 30.0, 'align': 'center', 'visible': true},
            {'id': 'col2', 'title': 'کتاب کا نام / مضمون', 'width': 90.0, 'align': 'right', 'visible': true},
            {'id': 'col3', 'title': 'کل نمبر', 'width': 35.0, 'align': 'center', 'visible': true},
            {'id': 'col4', 'title': 'کامیابی', 'width': 35.0, 'align': 'center', 'visible': true},
            {'id': 'col5', 'title': 'حاصل نمبر', 'width': 35.0, 'align': 'center', 'visible': true},
            {'id': 'col6', 'title': 'کیفیت / گریڈ', 'width': 45.0, 'align': 'center', 'visible': true},
          ]
        : cols.where((c) => c['visible'] != false).toList();

    return pw.Table(
      border: pw.TableBorder.all(color: gridColor, width: gridWidth),
      children: [
        // Table Header
        pw.TableRow(
          decoration: headerBg != null ? pw.BoxDecoration(color: headerBg) : null,
          children: visibleCols.map((c) {
            return _tableHeaderCell(c['title']?.toString() ?? '', fonts['urduBold']!, headerTextColor);
          }).toList(),
        ),
        // Table Rows
        ...List.generate(subjects.length, (idx) {
          final s = subjects[idx];
          final isAlt = idx % 2 == 1;
          final isAbsent = s['isAbsent'] == true;
          final maxM = (s['max'] as num?)?.toDouble() ?? 100.0;
          final obtM = (s['obtained'] as num?)?.toDouble() ?? 0.0;
          final passM = (s['pass'] as num?)?.toDouble() ?? 33.0;
          final isFail = !isAbsent && passM > 0 && obtM < passM;

          return pw.TableRow(
            decoration: (isAlt && altRowBg != null) ? pw.BoxDecoration(color: altRowBg) : null,
            children: visibleCols.map((c) {
              final id = c['id'];
              if (id == 'col1') {
                return _tableDataCell('${idx + 1}', fonts['roboto']!, rowTextColor, pw.TextAlign.center);
              } else if (id == 'col2') {
                return _tableDataCell(s['name']?.toString() ?? '', fonts['urdu']!, rowTextColor, pw.TextAlign.right, textDir: pw.TextDirection.rtl);
              } else if (id == 'col3') {
                return _tableDataCell('${maxM.toInt()}', fonts['roboto']!, rowTextColor, pw.TextAlign.center);
              } else if (id == 'col4') {
                return _tableDataCell('${passM.toInt()}', fonts['roboto']!, rowTextColor, pw.TextAlign.center);
              } else if (id == 'col5') {
                final text = isAbsent ? 'غائب' : '${obtM.toInt()}';
                final color = (isAbsent || isFail) ? PdfColors.red : rowTextColor;
                return _tableDataCell(text, fonts['robotoBold']!, color, pw.TextAlign.center, textDir: isAbsent ? pw.TextDirection.rtl : pw.TextDirection.ltr);
              } else if (id == 'col6') {
                final grade = s['grade']?.toString() ?? '';
                final color = (isAbsent || isFail) ? PdfColors.red : rowTextColor;
                return _tableDataCell(grade, fonts['urduBold']!, color, pw.TextAlign.center, textDir: pw.TextDirection.rtl);
              }
              return _tableDataCell(s[id]?.toString() ?? '', fonts['roboto']!, rowTextColor, pw.TextAlign.center);
            }).toList(),
          );
        }),
      ],
    );
  }

  static pw.Widget _tableHeaderCell(String text, pw.Font font, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: font, fontSize: 9.5, color: color),
      ),
    );
  }

  static pw.Widget _tableDataCell(String text, pw.Font font, PdfColor color, pw.TextAlign align, {pw.TextDirection textDir = pw.TextDirection.ltr}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
      child: pw.Text(
        text,
        textDirection: textDir,
        textAlign: align,
        style: pw.TextStyle(font: font, fontSize: 9, color: color),
      ),
    );
  }

  /// Generates a complete Vector PDF document for printing or export
  static Future<Uint8List> generatePdf(
    DesignerTemplate template, {
    Map<String, String>? dynamicData,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    final pageWidthPt = template.widthMm * PdfPageFormat.mm;
    final pageHeightPt = template.heightMm * PdfPageFormat.mm;
    final pageFormat = PdfPageFormat(pageWidthPt, pageHeightPt, marginAll: 0);

    // Front Side
    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (_) => _buildPageSide(template, 'front', dynamicData, fonts, pageWidthPt, pageHeightPt),
      ),
    );

    // Back Side if has back elements or back background
    final hasBackElements = template.elements.any((e) => e.side == 'back' && e.isVisible);
    if (hasBackElements || template.useBackTemplate) {
      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (_) => _buildPageSide(template, 'back', dynamicData, fonts, pageWidthPt, pageHeightPt),
        ),
      );
    }

    return pdf.save();
  }

  /// Generates Multi-Card Bulk Grid PDF on standard A4 paper (8 ID cards / page with cutting marks)
  static Future<Uint8List> generateBulkGridPdf(
    DesignerTemplate template,
    List<Map<String, String>> records,
  ) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    const a4Format = PdfPageFormat.a4; // 210 x 297 mm
    final cardW = template.widthMm * PdfPageFormat.mm;
    final cardH = template.heightMm * PdfPageFormat.mm;

    // 8 cards per A4 page (2 columns x 4 rows)
    const cardsPerPage = 8;
    final totalPages = (records.length / cardsPerPage).ceil();

    for (int pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final startIndex = pageIdx * cardsPerPage;
      final endIndex = (startIndex + cardsPerPage).clamp(0, records.length);
      final pageRecords = records.sublist(startIndex, endIndex);

      pdf.addPage(
        pw.Page(
          pageFormat: a4Format,
          margin: const pw.EdgeInsets.all(12 * PdfPageFormat.mm),
          build: (_) {
            return pw.Wrap(
              spacing: 6 * PdfPageFormat.mm,
              runSpacing: 6 * PdfPageFormat.mm,
              children: pageRecords.map((data) {
                return pw.Container(
                  width: cardW,
                  height: cardH,
                  child: _buildPageSide(template, 'front', data, fonts, cardW, cardH),
                );
              }).toList(),
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  /// Direct print dialog
  static Future<void> printDirectly(
    BuildContext context,
    DesignerTemplate template, {
    Map<String, String>? dynamicData,
  }) async {
    try {
      final bytes = await generatePdf(template, dynamicData: dynamicData);
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: '${template.name}.pdf',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Bulk print dialog
  static Future<void> printBulkGridDirectly(
    BuildContext context,
    DesignerTemplate template,
    List<Map<String, String>> records,
  ) async {
    try {
      final bytes = await generateBulkGridPdf(template, records);
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: '${template.name}_Bulk_Sheet.pdf',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk print error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Print entire class batch (1 page per student)
  static Future<void> printClassBatchDirectly(
    BuildContext context,
    DesignerTemplate template,
    List<Map<String, String>> recordsList,
  ) async {
    try {
      final fonts = await _loadFonts();
      final pdf = pw.Document();
      final pageWidthPt = template.widthMm * PdfPageFormat.mm;
      final pageHeightPt = template.heightMm * PdfPageFormat.mm;
      final pageFormat = PdfPageFormat(pageWidthPt, pageHeightPt, marginAll: 0);

      for (final record in recordsList) {
        // Front Side
        pdf.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.zero,
            build: (_) => _buildPageSide(template, 'front', record, fonts, pageWidthPt, pageHeightPt),
          ),
        );

        // Back Side if exists
        final hasBack = template.elements.any((e) => e.side == 'back') ||
            template.useBackTemplate ||
            (template.backgroundImageBackPath != null && template.backgroundImageBackPath!.isNotEmpty);
        if (hasBack) {
          pdf.addPage(
            pw.Page(
              pageFormat: pageFormat,
              margin: pw.EdgeInsets.zero,
              build: (_) => _buildPageSide(template, 'back', record, fonts, pageWidthPt, pageHeightPt),
            ),
          );
        }
      }

      final bytes = await pdf.save();
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: '${template.name}_Class_Batch.pdf',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Class batch print error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Save PDF to file
  static Future<void> exportAndSavePdf(
    BuildContext context,
    DesignerTemplate template, {
    Map<String, String>? dynamicData,
  }) async {
    try {
      final bytes = await generatePdf(template, dynamicData: dynamicData);
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Document PDF',
        fileName: '${template.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (savePath != null) {
        final f = File(savePath);
        await f.writeAsBytes(bytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document exported successfully: ${p.basename(savePath)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
