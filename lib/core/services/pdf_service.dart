import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../features/exams/data/models/exam_models.dart';
import '../../features/exams/data/algorithm/seating_models.dart';
import '../utils/grading_helper.dart';

class PdfService {
  /// Arabic/Urdu Unicode range: 0x0600 to 0x06FF
  static bool _isUrdu(String text) {
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x0600 && code <= 0x06FF) {
        return true;
      }
    }
    return false;
  }

  /// Hindi/Devanagari Unicode range: 0x0900 to 0x097F
  static bool _isHindi(String text) {
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x0900 && code <= 0x097F) {
        return true;
      }
    }
    return false;
  }

  /// Helper to load fonts asynchronously before PDF generation
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

  /// Generates a PDF for Seating Arrangement and launches printing.
  static Future<void> printSeating({
    required String examName,
    required ExamHall hall,
    required String date,
    required String time,
    required SeatingResult seating,
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

    // Map assignments by Row and Col for easy grid lookups
    final Map<String, SeatAssignment> gridMap = {};
    for (final assignment in seating.assignments) {
      gridMap['${assignment.seat.row}_${assignment.seat.col}'] = assignment;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildCell('SEATING ARRANGEMENT', isHeader: false, bold: true, color: PdfColors.blue900, fontSize: 16, robotoFont: robotoFont, robotoBold: robotoBold),
                    pw.SizedBox(height: 4),
                    _buildCell('Exam: $examName', isHeader: false, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    _buildCell('Hall: ${hall.name}', isHeader: false, bold: true, fontSize: 12, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                    pw.SizedBox(height: 4),
                    _buildCell('Date: $date | Time: $time', isHeader: false, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1.5, color: PdfColors.grey400),
            pw.SizedBox(height: 10),

            // Statistics Summary
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildStatBox('Total Capacity', '${hall.totalCapacity} seats', robotoFont: robotoFont, robotoBold: robotoBold),
                _buildStatBox('Students Placed', '${seating.placedCount}', robotoFont: robotoFont, robotoBold: robotoBold),
                _buildStatBox('Empty Seats', '${hall.totalCapacity - seating.placedCount}', robotoFont: robotoFont, robotoBold: robotoBold),
              ],
            ),
            pw.SizedBox(height: 20),

            // Seating Grid Layout
            _buildCell('Hall Grid Layout:', isHeader: false, bold: true, fontSize: 11, robotoFont: robotoFont, robotoBold: robotoBold),
            pw.SizedBox(height: 8),

            // Generate Grid Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: List.generate(hall.totalRows, (r) {
                return pw.TableRow(
                  children: List.generate(hall.totalColumns, (c) {
                    final seatNum = (r * hall.totalColumns) + c + 1;
                    final assignment = gridMap['${r + 1}_${c + 1}'];
                    final hasStudent = assignment != null;

                    return pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      height: 54,
                      color: hasStudent ? PdfColors.blue50 : PdfColors.grey100,
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildCell('S$seatNum', isHeader: false, bold: true, color: PdfColors.grey700, fontSize: 8, robotoFont: robotoFont),
                          if (hasStudent) ...[
                            _buildCell(
                              assignment.student.studentName,
                              isHeader: false,
                              bold: true,
                              fontSize: 8.5,
                              urduFont: urduFont,
                              urduBold: urduBold,
                              robotoFont: robotoFont,
                              robotoBold: robotoBold,
                            ),
                            _buildCell(
                              '${assignment.student.className} - ${assignment.student.bookName}',
                              isHeader: false,
                              color: PdfColors.grey600,
                              fontSize: 7,
                              urduFont: urduFont,
                              urduBold: urduBold,
                              robotoFont: robotoFont,
                              robotoBold: robotoBold,
                            ),
                          ] else ...[
                            pw.Center(
                              child: _buildCell('EMPTY', isHeader: false, color: PdfColors.grey400, fontSize: 8, robotoFont: robotoFont),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                );
              }),
            ),
          ];
        },
      ),
    );

    // List of student assignments (separate page, portrait, for easy search)
    if (seating.assignments.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            // Sort assignments by seat number
            final sorted = List<SeatAssignment>.from(seating.assignments)
              ..sort((a, b) => a.seat.seatNumber.compareTo(b.seat.seatNumber));

            return [
              _buildCell(
                'Student Seating List - ${hall.name}',
                isHeader: false,
                bold: true,
                color: PdfColors.blue900,
                fontSize: 14,
                urduFont: urduFont,
                urduBold: urduBold,
                robotoFont: robotoFont,
                robotoBold: robotoBold,
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue800),
                    children: [
                      _buildCell('Seat No.', isHeader: true, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('GR No.', isHeader: true, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('Student Name', isHeader: true, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('Class', isHeader: true, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('Subject/Book', isHeader: true, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                    ],
                  ),
                  ...sorted.map((a) {
                    return pw.TableRow(
                      children: [
                        _buildCell('Seat ${a.seat.seatNumber}', urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell(a.student.registrationNumber, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell(a.student.studentName, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell(a.student.className, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell(a.student.bookName, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      ],
                    );
                  }),
                ],
              ),
            ];
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Seating_Arrangement_${hall.name}.pdf',
    );
  }

  /// Generates a Class-Wise Seating List PDF (A4 Portrait) and directly opens OS Save/Share dialog
  static Future<void> exportClassSeatingPDF({
    required String examName,
    required String hallName,
    required List<Map<String, dynamic>> items,
    String? selectedClassName,
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

    // Filter/Group by class
    final Map<String, List<Map<String, dynamic>>> classGroups = {};
    for (final item in items) {
      final clsName = (item['className'] ?? 'Unknown Class').toString().trim();
      if (clsName.isEmpty) continue;
      if (selectedClassName != null &&
          selectedClassName.isNotEmpty &&
          selectedClassName != 'All Classes' &&
          selectedClassName != 'تمام کلاسیں') {
        if (clsName.toLowerCase() != selectedClassName.toLowerCase()) continue;
      }
      classGroups.putIfAbsent(clsName, () => []).add(item);
    }

    if (classGroups.isEmpty) return;

    for (final entry in classGroups.entries) {
      final className = entry.key;
      final classStudents = entry.value;

      // Sort by Roll Number numeric value ascending, then by Seat Number
      classStudents.sort((a, b) {
        final rAStr = (a['rollNumber'] ?? '').toString();
        final rBStr = (b['rollNumber'] ?? '').toString();
        final rA = int.tryParse(rAStr.replaceAll(RegExp(r'\D'), '')) ?? 999999;
        final rB = int.tryParse(rBStr.replaceAll(RegExp(r'\D'), '')) ?? 999999;
        if (rA != rB) return rA.compareTo(rB);
        final sA = int.tryParse((a['seatNumber'] ?? '').toString()) ?? 0;
        final sB = int.tryParse((b['seatNumber'] ?? '').toString()) ?? 0;
        return sA.compareTo(sB);
      });

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          header: (pw.Context context) {
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
                      _buildCell('EXAM SEATING LIST', bold: true, color: PdfColors.white, fontSize: 13, robotoFont: robotoFont),
                      _buildCell('Page ${context.pageNumber} of ${context.pagesCount}', color: PdfColors.white, fontSize: 9, robotoFont: robotoFont),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),
                // Heading Info Box: Exam Name, Hall Name, Class Name
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.teal50,
                    border: pw.Border.all(color: PdfColors.teal200, width: 1),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildCell('Exam: $examName', bold: true, fontSize: 11, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                          pw.SizedBox(height: 4),
                          _buildCell('Hall: $hallName', bold: true, fontSize: 11, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          _buildCell('Class: $className', bold: true, color: PdfColors.teal900, fontSize: 12, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                          pw.SizedBox(height: 4),
                          _buildCell('Total Students: ${classStudents.length}', fontSize: 9.5, robotoFont: robotoFont, robotoBold: robotoBold),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
              ],
            );
          },
          build: (pw.Context context) {
            return [
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.2), // Roll Number
                  1: const pw.FlexColumnWidth(1.5), // GR Number
                  2: const pw.FlexColumnWidth(3.5), // Full Name
                  3: const pw.FlexColumnWidth(1.5), // Seat Number
                },
                children: [
                  // Header Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.teal800),
                    children: [
                      _buildCell('Roll No.', isHeader: true, color: PdfColors.white, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('GR No.', isHeader: true, color: PdfColors.white, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('Full Name', isHeader: true, color: PdfColors.white, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('Seat No.', isHeader: true, color: PdfColors.white, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                    ],
                  ),
                  // Data Rows
                  ...classStudents.asMap().entries.map((e) {
                    final idx = e.key;
                    final s = e.value;
                    final rowColor = idx % 2 == 0 ? PdfColors.white : PdfColors.grey100;
                    final rollStr = (s['rollNumber'] ?? '').toString();
                    final grStr = (s['registrationNumber'] ?? '').toString();
                    final nameStr = (s['fullName'] ?? s['studentName'] ?? '-').toString();
                    final seatStr = (s['seatNumber'] ?? '-').toString();

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: rowColor),
                      children: [
                        _buildCell(rollStr.isEmpty ? '-' : rollStr, fontSize: 9.5, bold: true, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell(grStr.isEmpty ? '-' : grStr, fontSize: 9, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell(nameStr, fontSize: 9.5, bold: true, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell('Seat $seatStr', fontSize: 9.5, bold: true, color: PdfColors.teal900, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      ],
                    );
                  }),
                ],
              ),
            ];
          },
        ),
      );
    }

    final bytes = await pdf.save();
    final cleanHall = hallName.replaceAll(RegExp(r'[^\w\s\-]'), '');
    final cleanClass = (selectedClassName ?? 'All_Classes').replaceAll(RegExp(r'[^\w\s\-]'), '');
    final filename = 'Seating_List_${cleanClass}_${cleanHall}.pdf';

    try {
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Seating List PDF',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputPath != null && outputPath.trim().isNotEmpty) {
        final savePath = outputPath.endsWith('.pdf') ? outputPath : '$outputPath.pdf';
        final file = File(savePath);
        await file.writeAsBytes(bytes);
      }
    } catch (_) {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    }
  }

  /// Generates the raw PDF bytes for Exam Results (supports single class or all classes).
  static Future<Uint8List> generateResultsPdfBytes({
    required String examName,
    required String className,
    required List<Map<String, dynamic>> results,
    required List<GradingRule> gradingRules,
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

    // Group results by class if results has multiple classes or all classes
    final Map<String, List<Map<String, dynamic>>> classGroups = {};
    for (final r in results) {
      final cName = (r['class_name'] != null && r['class_name'].toString().trim().isNotEmpty)
          ? r['class_name'].toString().trim()
          : className;
      classGroups.putIfAbsent(cName, () => []).add(r);
    }

    for (final entry in classGroups.entries) {
      final groupClassName = entry.key;
      final classResults = List<Map<String, dynamic>>.from(entry.value);

      // Sort and calculate tie-aware ranks (equal total marks/percentage get equal rank)
      classResults.sort((a, b) {
        final obtA = ((a['total_obtained'] as num?) ?? 0).toDouble();
        final obtB = ((b['total_obtained'] as num?) ?? 0).toDouble();
        final cmpObt = obtB.compareTo(obtA);
        if (cmpObt != 0) return cmpObt;

        final pctA = ((a['percentage'] as num?) ?? 0).toDouble();
        final pctB = ((b['percentage'] as num?) ?? 0).toDouble();
        return pctB.compareTo(pctA);
      });

      for (int i = 0; i < classResults.length; i++) {
        if (i == 0) {
          classResults[i]['rank'] = 1;
        } else {
          final prev = classResults[i - 1];
          final curr = classResults[i];
          final prevObt = ((prev['total_obtained'] as num?) ?? 0).toDouble();
          final currObt = ((curr['total_obtained'] as num?) ?? 0).toDouble();
          final prevPct = ((prev['percentage'] as num?) ?? 0).toDouble();
          final currPct = ((curr['percentage'] as num?) ?? 0).toDouble();

          if ((prevObt - currObt).abs() < 0.01 && (prevPct - currPct).abs() < 0.01) {
            curr['rank'] = prev['rank'];
          } else {
            curr['rank'] = (prev['rank'] as int) + 1;
          }
        }
      }

      // Extract unique subjects across all students of this class
      final Set<String> subjectsSet = {};
      for (final r in classResults) {
        final List<dynamic> subjects = r['subjects'] as List<dynamic>? ?? [];
        for (final s in subjects) {
          if (s is ExamMark && s.bookName != null && s.bookName!.trim().isNotEmpty) {
            subjectsSet.add(s.bookName!.trim());
          }
        }
      }
      final sortedSubjects = subjectsSet.toList()..sort();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            // Compute summary stats
            final totalStudents = classResults.length;
            int passed = 0;
            double totalPercentageSum = 0;
            for (final r in classResults) {
              final p = (r['percentage'] is num ? (r['percentage'] as num).toDouble() : double.tryParse('${r['percentage']}')) ?? 0.0;
              totalPercentageSum += p;
              final absentCount = (r['absent_count'] is num ? (r['absent_count'] as num).toInt() : int.tryParse('${r['absent_count']}')) ?? 0;
              if (p >= 33.0 && absentCount == 0) {
                passed++;
              }
            }
            final avgPercentage = totalStudents > 0 ? totalPercentageSum / totalStudents : 0.0;

            return [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _buildCell('EXAM RESULTS & RANKINGS', isHeader: false, bold: true, color: PdfColors.purple900, fontSize: 16, robotoFont: robotoFont, robotoBold: robotoBold),
                      pw.SizedBox(height: 4),
                      _buildCell('Exam: $examName', isHeader: false, fontSize: 10, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _buildCell('Class: $groupClassName', isHeader: false, bold: true, fontSize: 12, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      pw.SizedBox(height: 4),
                      _buildCell('Date Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', isHeader: false, fontSize: 9, robotoFont: robotoFont, robotoBold: robotoBold),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1.5, color: PdfColors.grey400),
              pw.SizedBox(height: 10),

              // Summary Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildStatBox('Total Students', '$totalStudents', robotoFont: robotoFont, robotoBold: robotoBold),
                  _buildStatBox('Passed Students', '$passed / $totalStudents', robotoFont: robotoFont, robotoBold: robotoBold),
                  _buildStatBox('Average Percentage', '${avgPercentage.toStringAsFixed(1)}%', robotoFont: robotoFont, robotoBold: robotoBold),
                ],
              ),
              pw.SizedBox(height: 16),

              // Results Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.purple900),
                    children: [
                      _buildCell('Rank', isHeader: true, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('GR No.', isHeader: true, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('Student Name', isHeader: true, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                      ...sortedSubjects.map((sub) => _buildCell(sub, isHeader: true, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold)),
                      _buildCell('Total', isHeader: true, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('%', isHeader: true, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('Grade', isHeader: true, robotoFont: robotoFont, robotoBold: robotoBold),
                      _buildCell('Status', isHeader: true, robotoFont: robotoFont, robotoBold: robotoBold),
                    ],
                  ),
                  ...classResults.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final r = entry.value;
                    final percentage = (r['percentage'] is num ? (r['percentage'] as num).toDouble() : double.tryParse('${r['percentage']}')) ?? 0.0;
                    final totalObtained = (r['total_obtained'] is num ? (r['total_obtained'] as num).toDouble() : double.tryParse('${r['total_obtained']}')) ?? 0.0;
                    final totalMax = (r['total_max'] is num ? (r['total_max'] as num).toDouble() : double.tryParse('${r['total_max']}')) ?? 0.0;
                    final absentCount = (r['absent_count'] is num ? (r['absent_count'] as num).toInt() : int.tryParse('${r['absent_count']}')) ?? 0;
                    final isPass = percentage >= 33.0 && absentCount == 0;
                    final grade = GradingHelper.getGrade(percentage, gradingRules);
                    final rankStr = '#${r['rank'] ?? (idx + 1)}';

                    final bg = idx % 2 == 0 ? PdfColors.white : PdfColors.grey100;

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: bg),
                      children: [
                        _buildCell(rankStr, bold: true, align: pw.TextAlign.center, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell(r['registration_number'] ?? '-', robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell(r['full_name'] ?? r['student_name'] ?? 'Unknown', urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold),
                        ...sortedSubjects.map((sub) {
                          final mark = _getSubjectMarks(r['subjects'] as List<dynamic>? ?? [], sub);
                          return _buildCell(mark, align: pw.TextAlign.center, urduFont: urduFont, urduBold: urduBold, robotoFont: robotoFont, robotoBold: robotoBold);
                        }),
                        _buildCell('${totalObtained.toStringAsFixed(0)} / ${totalMax.toStringAsFixed(0)}', align: pw.TextAlign.center, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell('${percentage.toStringAsFixed(1)}%', align: pw.TextAlign.center, bold: true, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell(grade, align: pw.TextAlign.center, bold: true, color: isPass ? PdfColors.green800 : PdfColors.red800, robotoFont: robotoFont, robotoBold: robotoBold),
                        _buildCell(isPass ? 'PASS' : 'FAIL', align: pw.TextAlign.center, bold: true, color: isPass ? PdfColors.green800 : PdfColors.red800, robotoFont: robotoFont, robotoBold: robotoBold),
                      ],
                    );
                  }),
                ],
              ),
            ];
          },
        ),
      );
    }

    return pdf.save();
  }

  /// Saves the Exam Results PDF directly to a selected file destination
  static Future<String?> saveResultsPdf({
    required String examName,
    required String className,
    required List<Map<String, dynamic>> results,
    required List<GradingRule> gradingRules,
  }) async {
    final pdfBytes = await generateResultsPdfBytes(
      examName: examName,
      className: className,
      results: results,
      gradingRules: gradingRules,
    );

    final sanitizedClass = className.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final defaultFileName = 'Exam_Results_${sanitizedClass}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';

    String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Exam Results PDF',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (savePath == null) return null;

    if (!savePath.toLowerCase().endsWith('.pdf')) {
      savePath = '$savePath.pdf';
    }

    final file = File(savePath);
    await file.writeAsBytes(pdfBytes);
    return savePath;
  }

  // ── Helper Widgets for PDF ──────────────────────────────────────────

  static pw.Widget _buildStatBox(String label, String value, {pw.Font? robotoFont, pw.Font? robotoBold}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(font: robotoFont, fontSize: 8, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(font: robotoBold ?? robotoFont, fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCell(
    String text, {
    pw.Font? urduFont,
    pw.Font? urduBold,
    pw.Font? robotoFont,
    pw.Font? robotoBold,
    pw.Font? hindiFont,
    bool isHeader = false,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor? color,
    bool bold = false,
    double? fontSize,
  }) {
    // Replace non-ASCII Em Dash (U+2014) with standard ASCII hyphen '-'
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
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        safeText,
        textAlign: align,
        textDirection: isUr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        style: pw.TextStyle(
          font: primaryFont,
          fontFallback: fallbacks,
          fontSize: fontSize ?? (isHeader ? 8 : 7.5),
          fontWeight: (isHeader || bold) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.white : (color ?? PdfColors.black),
        ),
      ),
    );
  }

  static String _getSubjectMarks(List<dynamic> subjects, String subjectName) {
    for (final s in subjects) {
      if (s is ExamMark && s.bookName == subjectName) {
        if (s.isAbsent) return 'ABS';
        return s.marksObtained != null ? s.marksObtained!.toStringAsFixed(0) : '-';
      }
    }
    return '-';
  }
}
