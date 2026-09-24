import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' as fm;
import 'package:path_provider/path_provider.dart';

/// Generates printable ID card PDFs with QR codes.
/// Front: Photo placeholder, Name, Father, Class/Role, ID No.
/// Back: QR code + institution info.
class IdCardGenerator {
  static const double _cardWidth = 8.56 * PdfPageFormat.cm;
  static const double _cardHeight = 5.398 * PdfPageFormat.cm;
  static const _brandColor = PdfColor.fromInt(0xFF0D6B4E);
  static const _institutionName = 'Madarsa Management System';

  static bool _isUrdu(String text) {
    final RegExp urduRegExp = RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');
    return urduRegExp.hasMatch(text);
  }

  static Future<pw.ImageProvider> _renderUrduToImage(
    String text, {
    required double fontSize,
    fm.Color color = fm.Colors.black,
  }) async {
    // Shape the Arabic/Urdu text first
    final reshapedText = ArabicReshaper.instance.reshape(text);
    
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final textPainter = fm.TextPainter(
      text: fm.TextSpan(
        text: reshapedText,
        style: fm.TextStyle(
          fontFamily: 'JameelNooriNastaleeq',
          fontSize: fontSize * 3.0, // Scale up for high-res print quality
          color: color,
        ),
      ),
      textDirection: fm.TextDirection.rtl,
    );

    textPainter.layout();
    textPainter.paint(canvas, const ui.Offset(0, 0));

    final picture = recorder.endRecording();
    final width = textPainter.width.ceil();
    final height = textPainter.height.ceil();

    final imgWidth = width > 0 ? width : 1;
    final imgHeight = height > 0 ? height : 1;

    final img = await picture.toImage(imgWidth, imgHeight);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    return pw.MemoryImage(pngBytes);
  }

  static pw.Widget _buildInfoLine({
    required String label,
    required String value,
    required pw.ImageProvider? valueImage,
    required pw.Font baseFont,
    required double fontSize,
  }) {
    if (valueImage != null) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.start,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            '$label: ',
            style: pw.TextStyle(
              font: baseFont,
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Image(valueImage, height: fontSize),
        ],
      );
    } else {
      return pw.Text(
        '$label: $value',
        style: pw.TextStyle(
          font: baseFont,
          fontSize: fontSize,
        ),
      );
    }
  }
  /// Generate student ID cards PDF and send to printer/preview.
  static Future<void> printStudentIdCards({
    required List<Map<String, String>> students,
    String? institutionName,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    
    final institution = institutionName ?? _institutionName;
    final cardPageFormat = PdfPageFormat(
      _cardWidth + 8,
      _cardHeight + 8,
      marginAll: 4,
    );

    // Pre-render institution name image if in Urdu
    pw.ImageProvider? institutionImage;
    if (_isUrdu(institution)) {
      institutionImage = await _renderUrduToImage(institution, fontSize: 10, color: fm.Colors.white);
    }

    // Pre-load all photo network images
    final List<pw.ImageProvider?> resolvedPhotos = [];
    for (final student in students) {
      final photoPath = student['photoPath'];
      if (photoPath != null && photoPath.isNotEmpty) {
        try {
          final imageUrl = 'http://127.0.0.1:3000$photoPath';
          final image = await networkImage(imageUrl);
          resolvedPhotos.add(image);
        } catch (e) {
          resolvedPhotos.add(null);
        }
      } else {
        resolvedPhotos.add(null);
      }
    }

    for (int i = 0; i < students.length; i++) {
      final student = students[i];
      final name = student['fullName'] ?? '';
      final father = student['fatherName'] ?? '';
      final className = student['className'] ?? '';
      final grNo = student['grNo'] ?? student['registrationNumber'] ?? '';
      final mobile = student['mobileNo'] ?? '';
      final qrData = 'STU:$grNo';
      final photoProvider = resolvedPhotos[i];

      // Pre-render Urdu texts to high-res images
      pw.ImageProvider? nameImage;
      if (_isUrdu(name)) {
        nameImage = await _renderUrduToImage(name, fontSize: 11, color: fm.Colors.black);
      }

      pw.ImageProvider? fatherImage;
      if (_isUrdu(father)) {
        fatherImage = await _renderUrduToImage(father, fontSize: 8, color: fm.Colors.black);
      }

      pw.ImageProvider? classImage;
      if (_isUrdu(className)) {
        classImage = await _renderUrduToImage(className, fontSize: 8, color: fm.Colors.black);
      }
      
      pw.ImageProvider? nameBackImage;
      if (_isUrdu(name)) {
        nameBackImage = await _renderUrduToImage(name, fontSize: 7, color: fm.Colors.white);
      }

      // Page 1: Front side
      pdf.addPage(
        pw.Page(
          pageFormat: cardPageFormat,
          build: (context) {
            return pw.Center(
              child: _buildFrontCard(
                name: name,
                father: father,
                classOrDesignationLabel: 'Class',
                classOrDesignationValue: className,
                idLabel: 'GR No',
                idValue: grNo,
                mobile: mobile,
                type: 'STUDENT',
                institution: institution,
                baseFont: font,
                boldFont: fontBold,
                photoProvider: photoProvider,
                nameImage: nameImage,
                fatherImage: fatherImage,
                classOrDesignationImage: classImage,
                institutionImage: institutionImage,
              ),
            );
          },
        ),
      );

      // Page 2: Back side
      pdf.addPage(
        pw.Page(
          pageFormat: cardPageFormat,
          build: (context) {
            return pw.Center(
              child: _buildBackCard(
                qrData: qrData,
                idLabel: 'GR No',
                idValue: grNo,
                name: name,
                institution: institution,
                baseFont: font,
                nameImage: nameBackImage,
                institutionImage: institutionImage,
              ),
            );
          },
        ),
      );
    }

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Student_ID_Cards.pdf');
  }

  /// Generate staff ID cards PDF and send to printer/preview.
  static Future<void> printStaffIdCards({
    required List<Map<String, String>> staffList,
    String? institutionName,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    
    final institution = institutionName ?? _institutionName;
    final cardPageFormat = PdfPageFormat(
      _cardWidth + 8,
      _cardHeight + 8,
      marginAll: 4,
    );

    // Pre-render institution name image if in Urdu
    pw.ImageProvider? institutionImage;
    if (_isUrdu(institution)) {
      institutionImage = await _renderUrduToImage(institution, fontSize: 10, color: fm.Colors.white);
    }

    // Pre-load all photo network images
    final List<pw.ImageProvider?> resolvedPhotos = [];
    for (final staff in staffList) {
      final photoPath = staff['photoPath'];
      if (photoPath != null && photoPath.isNotEmpty) {
        try {
          final imageUrl = 'http://127.0.0.1:3000$photoPath';
          final image = await networkImage(imageUrl);
          resolvedPhotos.add(image);
        } catch (e) {
          resolvedPhotos.add(null);
        }
      } else {
        resolvedPhotos.add(null);
      }
    }

    for (int i = 0; i < staffList.length; i++) {
      final staff = staffList[i];
      final name = staff['fullName'] ?? '';
      final father = staff['fatherName'] ?? '';
      final staffType = staff['staffType'] ?? '';
      final staffNo = staff['staffNo'] ?? '';
      final mobile = staff['mobileNo'] ?? '';
      final qrData = 'STF:$staffNo';
      final photoProvider = resolvedPhotos[i];

      // Pre-render Urdu texts to high-res images
      pw.ImageProvider? nameImage;
      if (_isUrdu(name)) {
        nameImage = await _renderUrduToImage(name, fontSize: 11, color: fm.Colors.black);
      }

      pw.ImageProvider? fatherImage;
      if (_isUrdu(father)) {
        fatherImage = await _renderUrduToImage(father, fontSize: 8, color: fm.Colors.black);
      }

      pw.ImageProvider? staffTypeImage;
      if (_isUrdu(staffType)) {
        staffTypeImage = await _renderUrduToImage(staffType, fontSize: 8, color: fm.Colors.black);
      }
      
      pw.ImageProvider? nameBackImage;
      if (_isUrdu(name)) {
        nameBackImage = await _renderUrduToImage(name, fontSize: 7, color: fm.Colors.white);
      }

      // Page 1: Front side
      pdf.addPage(
        pw.Page(
          pageFormat: cardPageFormat,
          build: (context) {
            return pw.Center(
              child: _buildFrontCard(
                name: name,
                father: father,
                classOrDesignationLabel: 'Designation',
                classOrDesignationValue: staffType,
                idLabel: 'Staff No',
                idValue: staffNo,
                mobile: mobile,
                type: 'STAFF',
                institution: institution,
                baseFont: font,
                boldFont: fontBold,
                photoProvider: photoProvider,
                nameImage: nameImage,
                fatherImage: fatherImage,
                classOrDesignationImage: staffTypeImage,
                institutionImage: institutionImage,
              ),
            );
          },
        ),
      );

      // Page 2: Back side
      pdf.addPage(
        pw.Page(
          pageFormat: cardPageFormat,
          build: (context) {
            return pw.Center(
              child: _buildBackCard(
                qrData: qrData,
                idLabel: 'Staff No',
                idValue: staffNo,
                name: name,
                institution: institution,
                baseFont: font,
                nameImage: nameBackImage,
                institutionImage: institutionImage,
              ),
            );
          },
        ),
      );
    }

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Staff_ID_Cards.pdf');
  }

  // ─── FRONT CARD ──────────────────────────────────────────────
  static pw.Widget _buildFrontCard({
    required String name,
    required String father,
    required String classOrDesignationLabel,
    required String classOrDesignationValue,
    required String idLabel,
    required String idValue,
    required String mobile,
    required String type,
    required String institution,
    required pw.Font baseFont,
    required pw.Font boldFont,
    pw.ImageProvider? photoProvider,
    pw.ImageProvider? nameImage,
    pw.ImageProvider? fatherImage,
    pw.ImageProvider? classOrDesignationImage,
    pw.ImageProvider? institutionImage,
  }) {
    return pw.Container(
      width: _cardWidth,
      height: _cardHeight,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _brandColor, width: 1.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          // Header bar
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            decoration: const pw.BoxDecoration(
              color: _brandColor,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(6),
                topRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Column(
              children: [
                institutionImage != null
                    ? pw.Image(institutionImage, height: 10)
                    : pw.Text(
                        institution,
                        style: pw.TextStyle(
                          font: boldFont,
                          color: PdfColors.white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '$type IDENTITY CARD',
                  style: pw.TextStyle(
                    font: boldFont,
                    color: PdfColor.fromInt(0xCCFFFFFF),
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          ),
          // Body
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(10),
              child: pw.Row(
                children: [
                  // Photo
                  pw.Container(
                    width: 55,
                    height: 65,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(4),
                      image: photoProvider != null
                          ? pw.DecorationImage(
                              image: photoProvider,
                              fit: pw.BoxFit.cover,
                            )
                          : null,
                    ),
                    child: photoProvider == null
                        ? pw.Center(
                            child: pw.Text(
                              'PHOTO',
                              style: pw.TextStyle(
                                font: baseFont,
                                fontSize: 7,
                                color: PdfColors.grey500,
                              ),
                            ),
                          )
                        : null,
                  ),
                  pw.SizedBox(width: 10),
                  // Info
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        nameImage != null
                            ? pw.Image(nameImage, height: 11)
                            : pw.Text(
                                name,
                                style: pw.TextStyle(
                                  font: boldFont,
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                maxLines: 1,
                              ),
                        pw.SizedBox(height: 3),
                        _buildInfoLine(
                          label: 'Father',
                          value: father,
                          valueImage: fatherImage,
                          baseFont: baseFont,
                          fontSize: 8,
                        ),
                        pw.SizedBox(height: 2),
                        _buildInfoLine(
                          label: classOrDesignationLabel,
                          value: classOrDesignationValue,
                          valueImage: classOrDesignationImage,
                          baseFont: baseFont,
                          fontSize: 8,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: pw.BoxDecoration(
                            color: _brandColor,
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                          child: pw.Text(
                            '$idLabel: $idValue',
                            style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                        if (mobile.isNotEmpty) ...[
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Mobile: $mobile',
                            style: pw.TextStyle(
                              font: baseFont,
                              fontSize: 7,
                            ),
                          ),
                        ],
                      ],
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

  // ─── BACK CARD ──────────────────────────────────────────────
  static pw.Widget _buildBackCard({
    required String qrData,
    required String idLabel,
    required String idValue,
    required String name,
    required String institution,
    required pw.Font baseFont,
    pw.ImageProvider? nameImage,
    pw.ImageProvider? institutionImage,
  }) {
    return pw.Container(
      width: _cardWidth,
      height: _cardHeight,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _brandColor, width: 1.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          // Header
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
              color: _brandColor,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(6),
                topRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Text(
              'SCAN FOR ATTENDANCE',
              style: pw.TextStyle(
                font: baseFont,
                color: PdfColors.white,
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.5,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          // QR Code
          pw.Expanded(
            child: pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrData,
                width: 80,
                height: 80,
              ),
            ),
          ),
          // Footer
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
            decoration: const pw.BoxDecoration(
              color: _brandColor,
              borderRadius: pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(6),
                bottomRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                nameImage != null
                    ? pw.Image(nameImage, height: 7)
                    : pw.Text(
                        name,
                        style: pw.TextStyle(
                          font: baseFont,
                          color: PdfColors.white,
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                pw.Text(
                  '$idLabel: $idValue',
                  style: pw.TextStyle(
                    font: baseFont,
                    color: PdfColor.fromInt(0xCCFFFFFF),
                    fontSize: 7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
