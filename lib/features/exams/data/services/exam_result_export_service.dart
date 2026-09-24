import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/pdf_service.dart';
import '../../../../core/utils/grading_helper.dart';
import '../models/exam_models.dart';

class ExamResultExportService {
  /// Escapes CSV fields for Excel compatibility
  static String _escapeCsv(dynamic val) {
    if (val == null) return '""';
    String str = val.toString().replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
    if (str.contains(',') || str.contains('"') || str.contains(';') || str.contains('\t')) {
      str = str.replaceAll('"', '""');
      return '"$str"';
    }
    return '"$str"';
  }

  /// Exports Exam Results directly to Excel / CSV file with UTF-8 BOM
  static Future<String?> exportResultsToExcel({
    required String examName,
    required String className,
    required List<Map<String, dynamic>> results,
    required List<GradingRule> gradingRules,
  }) async {
    if (results.isEmpty) return null;

    // Process and ensure tie-aware ranking per class
    final Map<String, List<Map<String, dynamic>>> classGroups = {};
    for (final r in results) {
      final cName = (r['class_name'] != null && r['class_name'].toString().trim().isNotEmpty)
          ? r['class_name'].toString().trim()
          : className;
      classGroups.putIfAbsent(cName, () => []).add(Map<String, dynamic>.from(r));
    }

    final List<Map<String, dynamic>> processedResults = [];
    for (final entry in classGroups.entries) {
      final group = entry.value;
      group.sort((a, b) {
        final obtA = ((a['total_obtained'] as num?) ?? 0).toDouble();
        final obtB = ((b['total_obtained'] as num?) ?? 0).toDouble();
        final cmpObt = obtB.compareTo(obtA);
        if (cmpObt != 0) return cmpObt;

        final pctA = ((a['percentage'] as num?) ?? 0).toDouble();
        final pctB = ((b['percentage'] as num?) ?? 0).toDouble();
        return pctB.compareTo(pctA);
      });

      for (int i = 0; i < group.length; i++) {
        if (i == 0) {
          group[i]['rank'] = 1;
        } else {
          final prev = group[i - 1];
          final curr = group[i];
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
      processedResults.addAll(group);
    }

    final StringBuffer buffer = StringBuffer();
    // UTF-8 BOM for Excel to display Urdu, Arabic, and English characters properly
    buffer.write('\uFEFF');

    // Extract unique subjects across all students
    final Set<String> subjectsSet = {};
    for (final r in processedResults) {
      final List<dynamic> subjects = r['subjects'] as List<dynamic>? ?? [];
      for (final s in subjects) {
        if (s is ExamMark && s.bookName != null && s.bookName!.trim().isNotEmpty) {
          subjectsSet.add(s.bookName!.trim());
        }
      }
    }
    final sortedSubjects = subjectsSet.toList()..sort();

    // Title & Info Rows
    buffer.writeln([
      _escapeCsv('EXAM RESULTS & RANKINGS'),
      _escapeCsv(''),
      _escapeCsv(''),
      _escapeCsv('Exam: $examName'),
      _escapeCsv('Class: $className'),
      _escapeCsv('Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
    ].join(','));
    buffer.writeln(''); // Empty line

    // Header Row
    final List<String> headers = [
      'Rank',
      'GR No',
      'Student Name',
      'Class',
      ...sortedSubjects,
      'Total Marks Obtained',
      'Total Max Marks',
      'Percentage (%)',
      'Grade',
      'Status',
    ];
    buffer.writeln(headers.map(_escapeCsv).join(','));

    // Data Rows
    for (int idx = 0; idx < processedResults.length; idx++) {
      final r = processedResults[idx];
      final rank = r['rank'] ?? (idx + 1);
      final grNo = r['registration_number'] ?? r['gr_no'] ?? '-';
      final studentName = r['full_name'] ?? r['student_name'] ?? 'Unknown';
      final cName = r['class_name'] ?? className;
      final percentage = (r['percentage'] is num ? (r['percentage'] as num).toDouble() : double.tryParse('${r['percentage']}')) ?? 0.0;
      final totalObtained = (r['total_obtained'] is num ? (r['total_obtained'] as num).toDouble() : double.tryParse('${r['total_obtained']}')) ?? 0.0;
      final totalMax = (r['total_max'] is num ? (r['total_max'] as num).toDouble() : double.tryParse('${r['total_max']}')) ?? 0.0;
      final absentCount = (r['absent_count'] is num ? (r['absent_count'] as num).toInt() : int.tryParse('${r['absent_count']}')) ?? 0;
      final isPass = percentage >= 33.0 && absentCount == 0;
      final grade = GradingHelper.getGrade(percentage, gradingRules);

      final List<dynamic> subjectsList = r['subjects'] as List<dynamic>? ?? [];
      final Map<String, String> subjectMarksMap = {};
      for (final s in subjectsList) {
        if (s is ExamMark) {
          final bName = (s.bookName ?? '').trim();
          if (s.isAbsent) {
            subjectMarksMap[bName] = 'Absent';
          } else if (s.marksObtained != null) {
            subjectMarksMap[bName] = s.marksObtained!.toStringAsFixed(0);
          } else {
            subjectMarksMap[bName] = '-';
          }
        }
      }

      final List<String> row = [
        '$rank',
        '$grNo',
        studentName,
        cName,
        ...sortedSubjects.map((sub) => subjectMarksMap[sub] ?? '-'),
        totalObtained.toStringAsFixed(0),
        totalMax.toStringAsFixed(0),
        percentage.toStringAsFixed(1),
        grade,
        isPass ? 'PASS' : 'FAIL',
      ];

      buffer.writeln(row.map(_escapeCsv).join(','));
    }

    final sanitizedClass = className.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final defaultFileName = 'Exam_Results_${sanitizedClass}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';

    String? savePath;
    if (kIsWeb) {
      return null;
    } else {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Exam Results (Excel / CSV)',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (savePath == null) return null;

      if (!savePath.toLowerCase().endsWith('.csv') && !savePath.toLowerCase().endsWith('.xlsx')) {
        savePath = '$savePath.csv';
      }
    }

    final file = File(savePath);
    await file.writeAsString(buffer.toString(), encoding: utf8);
    return savePath;
  }

  /// Directly saves PDF Result Sheet to user's desired directory using FilePicker
  static Future<String?> saveResultsPdfDirect({
    required String examName,
    required String className,
    required List<Map<String, dynamic>> results,
    required List<GradingRule> gradingRules,
  }) async {
    try {
      final pdfBytes = await PdfService.generateResultsPdfBytes(
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
    } catch (e, stack) {
      debugPrint('Error saving PDF in saveResultsPdfDirect: $e\n$stack');
      rethrow;
    }
  }
}
