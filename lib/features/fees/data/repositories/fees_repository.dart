import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/database_helper.dart';
import '../models/fee_models.dart';

class FeesRepository {
  final ApiClient _apiClient;

  FeesRepository(this._apiClient);

  Future<List<StudentFeeSummary>> getStudentFeeSummaries() async {
    try {
      final response = await _apiClient.get('/fees/students');
      final List data = response.data ?? [];
      return data.map((json) => StudentFeeSummary.fromJson(json)).toList();
    } catch (e) {
      try {
        final db = await DatabaseHelper().database;
        final students = await db.query('students', orderBy: 'class_name ASC, full_name ASC');
        final payments = await db.rawQuery(
          "SELECT student_id, fee_type, SUM(amount) as paid_amount FROM fees WHERE (LOWER(status) = 'paid' OR LOWER(status) = 'completed' OR status IS NULL OR status = '') GROUP BY student_id, fee_type",
        );
        final payMap = <String, Map<String, double>>{};
        for (final p in payments) {
          final sId = p['student_id']?.toString() ?? '';
          final fType = (p['fee_type']?.toString() ?? 'Tuition Fee').toLowerCase().trim();
          final amt = (p['paid_amount'] as num?)?.toDouble() ?? 0.0;
          payMap.putIfAbsent(sId, () => {})[fType] = (payMap[sId]![fType] ?? 0.0) + amt;
        }

        return students.map((s) {
          final sId = s['id']?.toString() ?? '';
          final sPay = payMap[sId] ?? {};
          final structureStr = s['fee_structure']?.toString();
          List<StudentFeeHeadItem> heads = [];
          if (structureStr != null && structureStr.trim().isNotEmpty && structureStr != 'null') {
            try {
              final decoded = jsonDecode(structureStr);
              if (decoded is List) {
                heads = decoded.map((item) {
                  final name = item['fee_type_name']?.toString() ?? item['fee_type']?.toString() ?? 'Fee';
                  final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
                  final origAmt = (item['original_amount'] as num?)?.toDouble() ?? amt;
                  final discAmt = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
                  final discTag = item['discount_tag']?.toString();
                  final billing = item['billing_type']?.toString() ?? 'monthly';
                  final months = (item['months_count'] as num?)?.toInt() ?? 12;
                  final expected = billing == 'monthly' ? amt * months : amt;
                  final paid = sPay[name.toLowerCase().trim()] ?? 0.0;
                  return StudentFeeHeadItem(
                    feeTypeId: item['fee_type_id']?.toString(),
                    feeTypeName: name,
                    amount: amt,
                    originalAmount: origAmt,
                    discountAmount: discAmt,
                    discountTag: discTag,
                    billingType: billing,
                    monthsCount: months,
                    totalExpected: expected,
                    totalPaid: paid,
                    totalPending: (expected - paid).clamp(0.0, double.infinity),
                  );
                }).toList();
              }
            } catch (_) {}
          }

          final monthly = (s['monthly_fees'] as num?)?.toDouble() ?? 0.0;
          final admission = (s['admission_fee'] as num?)?.toDouble() ?? 0.0;
          final book = (s['book_fee'] as num?)?.toDouble() ?? 0.0;

          if (heads.isEmpty) {
            final tPaid = sPay['tuition fee'] ?? sPay['monthly fee'] ?? sPay['fee'] ?? 0.0;
            final aPaid = sPay['admission fee'] ?? sPay['admission'] ?? 0.0;
            final bPaid = sPay['book fee'] ?? sPay['books'] ?? 0.0;
            heads.add(StudentFeeHeadItem(
              feeTypeName: 'Tuition Fee',
              amount: monthly,
              billingType: 'monthly',
              monthsCount: 12,
              totalExpected: monthly * 12,
              totalPaid: tPaid,
              totalPending: (monthly * 12 - tPaid).clamp(0.0, double.infinity),
            ));
            if (admission > 0) {
              heads.add(StudentFeeHeadItem(
                feeTypeName: 'Admission Fee',
                amount: admission,
                billingType: 'one_time',
                monthsCount: 1,
                totalExpected: admission,
                totalPaid: aPaid,
                totalPending: (admission - aPaid).clamp(0.0, double.infinity),
              ));
            }
            if (book > 0) {
              heads.add(StudentFeeHeadItem(
                feeTypeName: 'Book Fee',
                amount: book,
                billingType: 'yearly',
                monthsCount: 1,
                totalExpected: book,
                totalPaid: bPaid,
                totalPending: (book - bPaid).clamp(0.0, double.infinity),
              ));
            }
          }

          final totalExpected = heads.fold<double>(0.0, (sum, h) => sum + h.totalExpected);
          final totalPaid = heads.fold<double>(0.0, (sum, h) => sum + h.totalPaid);
          final totalPending = (totalExpected - totalPaid).clamp(0.0, double.infinity);
          double totalDisc = (s['contributor_amount'] as num?)?.toDouble() ?? 0.0;
          if (totalDisc <= 0 && heads.isNotEmpty) {
            totalDisc = heads.fold<double>(0.0, (sum, h) => sum + (h.discountAmount ?? 0.0));
          }

          return StudentFeeSummary(
            id: sId,
            grNo: s['gr_no']?.toString(),
            fullName: s['full_name']?.toString() ?? '',
            fatherName: s['father_name']?.toString(),
            surname: s['surname']?.toString(),
            className: s['class_name']?.toString(),
            monthlyFees: monthly,
            admissionFee: admission,
            bookFee: book,
            contributorAmount: (s['contributor_amount'] as num?)?.toDouble(),
            totalDiscount: totalDisc,
            totalExpected: totalExpected,
            totalPaid: totalPaid,
            totalPending: totalPending,
            mobileNo: s['mobile_no']?.toString(),
            feeHeads: heads,
          );
        }).toList();
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<List<FeePayment>> getStudentPayments(String studentId, {String? grNo}) async {
    final Map<String, FeePayment> map = {};

    // 1. Fetch from local SQLite first (instantaneous)
    try {
      final db = await DatabaseHelper().database;
      final whereClause = (grNo != null && grNo.trim().isNotEmpty)
          ? '(student_id = ? OR student_id = ?)'
          : 'student_id = ?';
      final whereArgs = (grNo != null && grNo.trim().isNotEmpty)
          ? [studentId, grNo.trim()]
          : [studentId];

      final rows = await db.query(
        'fees',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'COALESCE(created_at, payment_date) DESC, payment_date DESC',
      );
      for (final r in rows) {
        final p = FeePayment.fromJson(r);
        if (p.id.isNotEmpty) map[p.id] = p;
      }
    } catch (_) {}

    // 2. Fetch from API with short 1.5s timeout (so offline server never lags)
    try {
      final response = await _apiClient.dio.get(
        '/fees/student/$studentId',
        options: Options(
          sendTimeout: const Duration(milliseconds: 1500),
          receiveTimeout: const Duration(milliseconds: 1500),
        ),
      );
      final List data = response.data ?? [];
      final apiPayments = data.map((json) => FeePayment.fromJson(json)).toList();
      
      try {
        final db = await DatabaseHelper().database;
        for (final p in apiPayments) {
          if (p.id.isNotEmpty) {
            map[p.id] = p;
            await db.insert('fees', {
              'id': p.id,
              'student_id': p.studentId,
              'amount': p.amount,
              'payment_date': p.paymentDate,
              'fee_type': p.feeType,
              'status': p.status,
              'receipt_no': p.receiptNo,
              'remarks': p.remarks,
              'created_at': p.createdAt ?? p.paymentDate,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      } catch (_) {
        for (final p in apiPayments) {
          if (p.id.isNotEmpty) map[p.id] = p;
        }
      }
    } catch (_) {}

    final list = map.values.toList();
    list.sort((a, b) {
      final dtA = a.createdAt ?? a.paymentDate ?? '';
      final dtB = b.createdAt ?? b.paymentDate ?? '';
      return dtB.compareTo(dtA);
    });
    return list;
  }

  Future<List<Map<String, dynamic>>> getAllFeePayments() async {
    try {
      final db = await DatabaseHelper().database;
      final rows = await db.rawQuery('''
        SELECT f.id, f.student_id, f.amount, f.payment_date, f.fee_type, f.status,
               f.receipt_no, f.remarks, f.created_at,
               s.full_name as student_name, s.gr_no, s.class_name
        FROM fees f
        LEFT JOIN students s ON (f.student_id = s.id OR f.student_id = s.gr_no)
        ORDER BY COALESCE(f.created_at, f.payment_date) DESC, f.payment_date DESC
      ''');
      return rows;
    } catch (_) {
      return [];
    }
  }

  Future<FeePayment> payFee({
    required String studentId,
    required double amount,
    required String feeType,
    String? remarks,
    String? receiptNo,
  }) async {
    FeePayment? payment;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final todayStr = nowIso.split('T')[0];

    try {
      final response = await _apiClient.post(
        '/fees/pay',
        data: {
          'student_id': studentId,
          'amount': amount,
          'fee_type': feeType,
          'remarks': remarks,
          'receipt_no': receiptNo,
          'payment_date': todayStr,
        },
      );
      payment = FeePayment.fromJson(response.data);
    } catch (_) {
      // Offline fallback: create local FeePayment
      payment = FeePayment(
        id: 'fee_${now.millisecondsSinceEpoch}',
        studentId: studentId,
        amount: amount,
        paymentDate: todayStr,
        feeType: feeType,
        status: 'Paid',
        receiptNo: receiptNo,
        remarks: remarks,
        createdAt: nowIso,
      );
    }

    // Always cache into local SQLite fees table
    try {
      final db = await DatabaseHelper().database;
      await db.insert('fees', {
        'id': payment.id,
        'student_id': payment.studentId,
        'amount': payment.amount,
        'payment_date': payment.paymentDate ?? todayStr,
        'fee_type': payment.feeType,
        'status': payment.status.isNotEmpty ? payment.status : 'Paid',
        'receipt_no': payment.receiptNo ?? receiptNo,
        'remarks': remarks,
        'created_at': payment.createdAt ?? nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}

    return payment;
  }

  // ─── Fee Types CRUD ────────────────────────────────────────────
  Future<List<FeeType>> getFeeTypes() async {
    try {
      final response = await _apiClient.get('/fees/fee-types');
      final List data = response.data ?? [];
      return data.map((json) => FeeType.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<FeeType> addFeeType(
    String name, {
    String billingType = 'monthly',
    int defaultMonths = 12,
    double defaultAmount = 0.0,
  }) async {
    try {
      final response = await _apiClient.post(
        '/fees/fee-types',
        data: {
          'name': name,
          'billing_type': billingType,
          'default_months': defaultMonths,
          'default_amount': defaultAmount,
        },
      );
      return FeeType.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateFeeType(
    String id,
    String name, {
    String? billingType,
    int? defaultMonths,
    double? defaultAmount,
  }) async {
    try {
      final data = <String, dynamic>{'name': name};
      if (billingType != null) data['billing_type'] = billingType;
      if (defaultMonths != null) data['default_months'] = defaultMonths;
      if (defaultAmount != null) data['default_amount'] = defaultAmount;
      await _apiClient.put('/fees/fee-types/$id', data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteFeeType(String id) async {
    try {
      await _apiClient.delete('/fees/fee-types/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── Donations ─────────────────────────────────────────────────
  Future<List<Donation>> getDonations() async {
    try {
      final response = await _apiClient.get('/fees/donations');
      final List data = response.data ?? [];
      return data.map((json) => Donation.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<Donation> recordDonation({
    String? receiptNo,
    String? donorName,
    String? donorPhone,
    String? village,
    String? taluka,
    String? district,
    String? state,
    String? country,
    String? pinCode,
    required double amount,
    required String donationType,
    required String paymentMethod,
    String? paymentDate,
  }) async {
    try {
      final response = await _apiClient.post(
        '/fees/donations',
        data: {
          'receipt_no': receiptNo,
          'donor_name': donorName,
          'donor_phone': donorPhone,
          'village': village,
          'taluka': taluka,
          'district': district,
          'state': state,
          'country': country ?? 'India',
          'pin_code': pinCode,
          'amount': amount,
          'donation_type': donationType,
          'payment_method': paymentMethod,
          'payment_date': paymentDate,
        },
      );
      return Donation.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  // ─── Donation Types CRUD ───────────────────────────────────────
  Future<List<DonationType>> getDonationTypes() async {
    try {
      final response = await _apiClient.get('/fees/donation-types');
      final List data = response.data ?? [];
      return data.map((json) => DonationType.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<DonationType> addDonationType(String name) async {
    try {
      final response = await _apiClient.post(
        '/fees/donation-types',
        data: {'name': name},
      );
      return DonationType.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateDonationType(String id, String name) async {
    try {
      await _apiClient.put('/fees/donation-types/$id', data: {'name': name});
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteDonationType(String id) async {
    try {
      await _apiClient.delete('/fees/donation-types/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── Delete Fee Payment ─────────────────────────────────────────
  Future<void> deleteFeePayment(String id) async {
    // 1. Delete from SQLite immediately
    try {
      final db = await DatabaseHelper().database;
      await db.delete('fees', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}

    // 2. Delete from API
    try {
      await _apiClient.delete('/fees/payment/$id');
    } catch (_) {}
  }

  // ─── Delete Donation ────────────────────────────────────────────
  Future<void> deleteDonation(String id) async {
    // 1. Delete from SQLite immediately
    try {
      final db = await DatabaseHelper().database;
      await db.delete('donations', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}

    // 2. Delete from API
    try {
      await _apiClient.delete('/fees/donations/$id');
    } catch (_) {}
  }
}
