import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/designer_template_model.dart';

class DesignerTemplateRepository {
  static const String _storageKey = 'universal_designer_templates_v1';

  /// Fetch all templates (starter templates + user saved templates)
  Future<List<DesignerTemplate>> getAllTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    final List<DesignerTemplate> userTemplates = [];

    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        for (final item in decoded) {
          userTemplates.add(DesignerTemplate.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    // Combine user saved templates with built-in starters
    final all = <DesignerTemplate>[];
    all.addAll(userTemplates);

    // If no user template exists for a starter, provide default starters
    for (final starter in getStarterTemplates()) {
      if (!all.any((t) => t.id == starter.id)) {
        all.add(starter);
      }
    }

    return all;
  }

  /// Save or update a template
  Future<void> saveTemplate(DesignerTemplate template) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAllTemplates();
    final index = all.indexWhere((t) => t.id == template.id);

    template.updatedAt = DateTime.now();

    if (index >= 0) {
      all[index] = template;
    } else {
      all.insert(0, template);
    }

    final jsonStr = jsonEncode(all.map((t) => t.toJson()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }

  /// Delete a template by ID
  Future<void> deleteTemplate(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAllTemplates();
    all.removeWhere((t) => t.id == id);
    final jsonStr = jsonEncode(all.map((t) => t.toJson()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }

  /// Built-in Starter Templates for all major document types
  static List<DesignerTemplate> getStarterTemplates() {
    return [
      _buildStudentIdCardStarter(),
      _buildStaffIdCardStarter(),
      _buildResultCardStarter(),
      _buildCertificateStarter(),
      _buildFeeReceiptStarter(),
      _buildPurchaseInvoiceStarter(),
      _buildLibraryCardStarter(),
    ];
  }

  // ─────────────────────────────────────────────────────────────
  // 1. Starter: Student ID Card (Horizontal CR80: 85.6 x 53.98mm)
  // ─────────────────────────────────────────────────────────────
  static DesignerTemplate _buildStudentIdCardStarter() {
    return DesignerTemplate(
      id: 'starter_student_id_horizontal',
      name: 'معیاری طالب علم شناختی کارڈ (Standard Student ID)',
      documentType: DocumentType.studentIdCard,
      preset: CanvasPreset.cr80Horizontal,
      widthMm: 85.6,
      heightMm: 53.98,
      backgroundColor: const Color(0xFFF9FBFC),
      elements: [
        // Top Header Banner
        DesignerElement(
          id: 's_hdr_bg',
          type: DesignerElementType.shape,
          shapeType: 'rectangle',
          xRatio: 0.0,
          yRatio: 0.0,
          widthRatio: 1.0,
          heightRatio: 0.22,
          backgroundColor: const Color(0xFF0D5C3A), // Dark Emerald
          zIndex: 0,
        ),
        // Madarsa Name in Header
        DesignerElement(
          id: 's_hdr_title',
          type: DesignerElementType.token,
          tokenKey: '{{madarsa.name}}',
          text: 'جامعہ اسلامیہ دارالعلوم',
          xRatio: 0.05,
          yRatio: 0.03,
          widthRatio: 0.9,
          heightRatio: 0.16,
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Student Photo
        DesignerElement(
          id: 's_photo',
          type: DesignerElementType.photo,
          xRatio: 0.05,
          yRatio: 0.26,
          widthRatio: 0.25,
          heightRatio: 0.52,
          borderColor: const Color(0xFF0D5C3A),
          borderWidth: 1.5,
          borderRadius: 6,
          zIndex: 1,
        ),
        // Student Full Name
        DesignerElement(
          id: 's_name',
          type: DesignerElementType.token,
          tokenKey: '{{student.name}}',
          text: 'محمد زید بن خالد انصاری',
          xRatio: 0.33,
          yRatio: 0.26,
          widthRatio: 0.62,
          heightRatio: 0.14,
          color: const Color(0xFF0D5C3A),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // GR Number
        DesignerElement(
          id: 's_gr',
          type: DesignerElementType.token,
          tokenKey: '{{student.gr_no}}',
          text: 'جی آر: GR-1045',
          xRatio: 0.33,
          yRatio: 0.42,
          widthRatio: 0.30,
          heightRatio: 0.11,
          color: Colors.black87,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Class Name
        DesignerElement(
          id: 's_class',
          type: DesignerElementType.token,
          tokenKey: '{{student.class_name}}',
          text: 'درجہ: رابعہ (عالمیت)',
          xRatio: 0.64,
          yRatio: 0.42,
          widthRatio: 0.31,
          heightRatio: 0.11,
          color: Colors.black87,
          fontSize: 9.5,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Father Name
        DesignerElement(
          id: 's_father',
          type: DesignerElementType.token,
          tokenKey: '{{student.father_name}}',
          text: 'والد: خالد احمد انصاری',
          xRatio: 0.33,
          yRatio: 0.54,
          widthRatio: 0.62,
          heightRatio: 0.11,
          color: Colors.black87,
          fontSize: 9,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Guardian Phone
        DesignerElement(
          id: 's_phone',
          type: DesignerElementType.token,
          tokenKey: '{{student.phone}}',
          text: 'موبائل: +91 98234 56789',
          xRatio: 0.33,
          yRatio: 0.66,
          widthRatio: 0.35,
          heightRatio: 0.11,
          color: Colors.black87,
          fontSize: 8.5,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // QR Code
        DesignerElement(
          id: 's_qr',
          type: DesignerElementType.qrCode,
          tokenKey: '{{student.gr_no}}',
          text: 'GR-1045',
          xRatio: 0.74,
          yRatio: 0.55,
          widthRatio: 0.21,
          heightRatio: 0.30,
          zIndex: 1,
        ),
        // Bottom Footer Bar
        DesignerElement(
          id: 's_ftr_bg',
          type: DesignerElementType.shape,
          shapeType: 'rectangle',
          xRatio: 0.0,
          yRatio: 0.88,
          widthRatio: 1.0,
          heightRatio: 0.12,
          backgroundColor: const Color(0xFFE2E8F0),
          zIndex: 0,
        ),
        // Footer Address text
        DesignerElement(
          id: 's_ftr_txt',
          type: DesignerElementType.token,
          tokenKey: '{{madarsa.address}}',
          text: 'قاسم العلوم روڈ، گجرات، ہند',
          xRatio: 0.05,
          yRatio: 0.89,
          widthRatio: 0.90,
          heightRatio: 0.10,
          color: Colors.black54,
          fontSize: 7.5,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. Starter: Staff ID Card (Vertical CR80: 53.98 x 85.6mm)
  // ─────────────────────────────────────────────────────────────
  static DesignerTemplate _buildStaffIdCardStarter() {
    return DesignerTemplate(
      id: 'starter_staff_id_vertical',
      name: 'ملازم و اساتذہ شناختی کارڈ (Staff ID Card Vertical)',
      documentType: DocumentType.staffIdCard,
      preset: CanvasPreset.cr80Vertical,
      widthMm: 53.98,
      heightMm: 85.6,
      backgroundColor: Colors.white,
      elements: [
        // Top Header Curved
        DesignerElement(
          id: 'st_hdr',
          type: DesignerElementType.shape,
          shapeType: 'rectangle',
          xRatio: 0.0,
          yRatio: 0.0,
          widthRatio: 1.0,
          heightRatio: 0.18,
          backgroundColor: const Color(0xFF1E3A8A), // Navy Blue
          zIndex: 0,
        ),
        // Madarsa Name
        DesignerElement(
          id: 'st_hdr_title',
          type: DesignerElementType.token,
          tokenKey: '{{madarsa.name}}',
          text: 'جامعہ اسلامیہ دارالعلوم',
          xRatio: 0.05,
          yRatio: 0.04,
          widthRatio: 0.90,
          heightRatio: 0.10,
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Staff Photo
        DesignerElement(
          id: 'st_photo',
          type: DesignerElementType.photo,
          xRatio: 0.28,
          yRatio: 0.19,
          widthRatio: 0.44,
          heightRatio: 0.26,
          borderColor: const Color(0xFF1E3A8A),
          borderWidth: 2.0,
          borderRadius: 8.0,
          zIndex: 1,
        ),
        // Staff Name
        DesignerElement(
          id: 'st_name',
          type: DesignerElementType.token,
          tokenKey: '{{staff.name}}',
          text: 'مولانا عبد الرحیم قاسمی',
          xRatio: 0.05,
          yRatio: 0.47,
          widthRatio: 0.90,
          heightRatio: 0.08,
          color: const Color(0xFF1E3A8A),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Designation
        DesignerElement(
          id: 'st_desig',
          type: DesignerElementType.token,
          tokenKey: '{{staff.designation}}',
          text: 'استاذ حدیث و فقہ',
          xRatio: 0.05,
          yRatio: 0.55,
          widthRatio: 0.90,
          heightRatio: 0.06,
          color: const Color(0xFFB45309), // Amber 700
          fontSize: 10,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Department
        DesignerElement(
          id: 'st_dept',
          type: DesignerElementType.token,
          tokenKey: '{{staff.department}}',
          text: 'شعبہ: عالیہ و تخصص',
          xRatio: 0.05,
          yRatio: 0.62,
          widthRatio: 0.90,
          heightRatio: 0.05,
          color: Colors.black87,
          fontSize: 9,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Staff ID
        DesignerElement(
          id: 'st_id',
          type: DesignerElementType.token,
          tokenKey: '{{staff.id}}',
          text: 'آئی ڈی: STF-042',
          xRatio: 0.05,
          yRatio: 0.68,
          widthRatio: 0.90,
          heightRatio: 0.05,
          color: Colors.black54,
          fontSize: 8.5,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Barcode
        DesignerElement(
          id: 'st_barcode',
          type: DesignerElementType.barcode,
          tokenKey: '{{staff.id}}',
          text: 'STF-042',
          xRatio: 0.15,
          yRatio: 0.74,
          widthRatio: 0.70,
          heightRatio: 0.10,
          zIndex: 1,
        ),
        // Authorized Sign
        DesignerElement(
          id: 'st_sign',
          type: DesignerElementType.signature,
          text: 'دستخط مہتمم / ناظم تعلیمات',
          xRatio: 0.10,
          yRatio: 0.86,
          widthRatio: 0.80,
          heightRatio: 0.08,
          color: Colors.black87,
          fontSize: 8,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. Starter: Official Result Card / Marksheet (A4 Portrait)
  // ─────────────────────────────────────────────────────────────
  static DesignerTemplate _buildResultCardStarter() {
    return DesignerTemplate(
      id: 'starter_result_card_a4',
      name: 'کشف الدرجات و نتیجہ کارڈ (Official Marksheet A4)',
      documentType: DocumentType.resultCard,
      preset: CanvasPreset.a4Portrait,
      widthMm: 210.0,
      heightMm: 297.0,
      backgroundColor: Colors.white,
      elements: [
        // Ornate Outer Frame
        DesignerElement(
          id: 'rc_frame',
          type: DesignerElementType.shape,
          shapeType: 'rectangle',
          xRatio: 0.03,
          yRatio: 0.02,
          widthRatio: 0.94,
          heightRatio: 0.96,
          borderColor: const Color(0xFF0F3814),
          borderWidth: 2.5,
          borderRadius: 8,
          zIndex: 0,
        ),
        // Bismillah
        DesignerElement(
          id: 'rc_bismillah',
          type: DesignerElementType.text,
          text: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
          xRatio: 0.20,
          yRatio: 0.035,
          widthRatio: 0.60,
          heightRatio: 0.03,
          color: const Color(0xFF0F3814),
          fontSize: 15,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Madarsa Name
        DesignerElement(
          id: 'rc_madarsa_name',
          type: DesignerElementType.token,
          tokenKey: '{{madarsa.name}}',
          text: 'جامعہ اسلامیہ دارالعلوم',
          xRatio: 0.10,
          yRatio: 0.065,
          widthRatio: 0.80,
          heightRatio: 0.045,
          color: const Color(0xFF0F3814),
          fontSize: 22,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Document Title
        DesignerElement(
          id: 'rc_title',
          type: DesignerElementType.text,
          text: 'کشف الدرجات برائے سالانہ امتحان (MARKSHEET)',
          xRatio: 0.20,
          yRatio: 0.115,
          widthRatio: 0.60,
          heightRatio: 0.035,
          backgroundColor: const Color(0xFF0F3814),
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          borderRadius: 4,
          zIndex: 1,
        ),
        // Student Information Box
        DesignerElement(
          id: 'rc_student_box',
          type: DesignerElementType.shape,
          shapeType: 'rectangle',
          xRatio: 0.06,
          yRatio: 0.165,
          widthRatio: 0.88,
          heightRatio: 0.11,
          backgroundColor: const Color(0xFFF8FAFC),
          borderColor: Colors.grey.shade300,
          borderWidth: 1.0,
          borderRadius: 6,
          zIndex: 0,
        ),
        // Info: Student Name
        DesignerElement(
          id: 'rc_st_name',
          type: DesignerElementType.token,
          tokenKey: '{{student.name}}',
          text: 'نام طالب علم: محمد زید بن خالد انصاری',
          xRatio: 0.52,
          yRatio: 0.175,
          widthRatio: 0.40,
          heightRatio: 0.04,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Info: GR No
        DesignerElement(
          id: 'rc_st_gr',
          type: DesignerElementType.token,
          tokenKey: '{{student.gr_no}}',
          text: 'جی آر نمبر: GR-1045',
          xRatio: 0.08,
          yRatio: 0.175,
          widthRatio: 0.38,
          heightRatio: 0.04,
          fontSize: 12,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Info: Class
        DesignerElement(
          id: 'rc_st_class',
          type: DesignerElementType.token,
          tokenKey: '{{student.class_name}}',
          text: 'جماعت: درجہ رابعہ (عالمیت)',
          xRatio: 0.52,
          yRatio: 0.225,
          widthRatio: 0.40,
          heightRatio: 0.04,
          fontSize: 12,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Info: Roll No
        DesignerElement(
          id: 'rc_st_roll',
          type: DesignerElementType.token,
          tokenKey: '{{student.roll_no}}',
          text: 'رول نمبر: 25',
          xRatio: 0.08,
          yRatio: 0.225,
          widthRatio: 0.38,
          heightRatio: 0.04,
          fontSize: 12,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Dynamic Subjects Table
        DesignerElement(
          id: 'rc_table',
          type: DesignerElementType.table,
          text: 'جدول درجات و کتب (Subject Marks Table)',
          xRatio: 0.06,
          yRatio: 0.29,
          widthRatio: 0.88,
          heightRatio: 0.42,
          borderColor: const Color(0xFF0F3814),
          borderWidth: 1.0,
          zIndex: 1,
        ),
        // Result Summary Box
        DesignerElement(
          id: 'rc_summary_box',
          type: DesignerElementType.shape,
          shapeType: 'rectangle',
          xRatio: 0.06,
          yRatio: 0.73,
          widthRatio: 0.88,
          heightRatio: 0.11,
          backgroundColor: const Color(0xFFECFDF5), // Soft green
          borderColor: const Color(0xFF059669),
          borderWidth: 1.5,
          borderRadius: 6,
          zIndex: 0,
        ),
        // Summary Details
        DesignerElement(
          id: 'rc_sum_total',
          type: DesignerElementType.token,
          tokenKey: '{{exam.obtained_marks}}',
          text: 'کل نمبرات: 542 / 600   |   فیصد: 90.33%',
          xRatio: 0.45,
          yRatio: 0.75,
          widthRatio: 0.45,
          heightRatio: 0.06,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF065F46),
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        DesignerElement(
          id: 'rc_sum_grade',
          type: DesignerElementType.token,
          tokenKey: '{{exam.grade}}',
          text: 'نتیجہ: ممتاز (A+ First Position)',
          xRatio: 0.08,
          yRatio: 0.75,
          widthRatio: 0.35,
          heightRatio: 0.06,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF065F46),
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Signatures Bar
        DesignerElement(
          id: 'rc_sign_examiner',
          type: DesignerElementType.signature,
          text: 'دستخط ممتحن (Examiner)',
          xRatio: 0.10,
          yRatio: 0.88,
          widthRatio: 0.25,
          heightRatio: 0.06,
          fontSize: 11,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        DesignerElement(
          id: 'rc_stamp_seal',
          type: DesignerElementType.stamp,
          text: 'مہر مدرسہ (Official Seal)',
          xRatio: 0.40,
          yRatio: 0.86,
          widthRatio: 0.20,
          heightRatio: 0.09,
          fontSize: 10,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        DesignerElement(
          id: 'rc_sign_principal',
          type: DesignerElementType.signature,
          text: 'دستخط مہتمم / صدر مدرس',
          xRatio: 0.65,
          yRatio: 0.88,
          widthRatio: 0.25,
          heightRatio: 0.06,
          fontSize: 11,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 4. Starter: Certificate & Sanad (A4 Landscape: 297 x 210mm)
  // ─────────────────────────────────────────────────────────────
  static DesignerTemplate _buildCertificateStarter() {
    return DesignerTemplate(
      id: 'starter_certificate_a4_landscape',
      name: 'سند الفراغ و تحسینی سرٹیفکیٹ (Certificate / Sanad A4 Landscape)',
      documentType: DocumentType.certificate,
      preset: CanvasPreset.a4Landscape,
      widthMm: 297.0,
      heightMm: 210.0,
      backgroundColor: const Color(0xFFFFFDF8), // Parchment Warm White
      elements: [
        // Outer Decorative Border
        DesignerElement(
          id: 'c_outer_border',
          type: DesignerElementType.shape,
          shapeType: 'rectangle',
          xRatio: 0.03,
          yRatio: 0.04,
          widthRatio: 0.94,
          heightRatio: 0.92,
          borderColor: const Color(0xFF996515), // Golden Bronze
          borderWidth: 3.5,
          borderRadius: 8,
          zIndex: 0,
        ),
        // Inner Thin Border
        DesignerElement(
          id: 'c_inner_border',
          type: DesignerElementType.shape,
          shapeType: 'rectangle',
          xRatio: 0.04,
          yRatio: 0.055,
          widthRatio: 0.92,
          heightRatio: 0.89,
          borderColor: const Color(0xFFD4AF37), // Light Gold
          borderWidth: 1.0,
          zIndex: 0,
        ),
        // Bismillah
        DesignerElement(
          id: 'c_bismillah',
          type: DesignerElementType.text,
          text: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
          xRatio: 0.25,
          yRatio: 0.08,
          widthRatio: 0.50,
          heightRatio: 0.07,
          color: const Color(0xFF0F3814),
          fontSize: 18,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Madarsa Name
        DesignerElement(
          id: 'c_madarsa',
          type: DesignerElementType.token,
          tokenKey: '{{madarsa.name}}',
          text: 'جامعہ اسلامیہ دارالعلوم',
          xRatio: 0.15,
          yRatio: 0.16,
          widthRatio: 0.70,
          heightRatio: 0.09,
          color: const Color(0xFF0F3814),
          fontSize: 24,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Sanad Title
        DesignerElement(
          id: 'c_title',
          type: DesignerElementType.token,
          tokenKey: '{{cert.title}}',
          text: 'سَنَدُ الْفَرَاغْ فِي دَرْسِ نِظَامِي (عَالِمِيَّت)',
          xRatio: 0.20,
          yRatio: 0.27,
          widthRatio: 0.60,
          heightRatio: 0.09,
          color: const Color(0xFF996515),
          fontSize: 20,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Certifying Text Body
        DesignerElement(
          id: 'c_body',
          type: DesignerElementType.text,
          text: 'تصدیق کی جاتی ہے کہ عزیز گرامی القدر محترم',
          xRatio: 0.20,
          yRatio: 0.38,
          widthRatio: 0.60,
          heightRatio: 0.06,
          fontSize: 14,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Student Name
        DesignerElement(
          id: 'c_name',
          type: DesignerElementType.token,
          tokenKey: '{{student.name}}',
          text: 'محمد زید بن خالد احمد انصاری',
          xRatio: 0.15,
          yRatio: 0.44,
          widthRatio: 0.70,
          heightRatio: 0.09,
          color: const Color(0xFF0F3814),
          fontSize: 22,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Achievement Text
        DesignerElement(
          id: 'c_desc',
          type: DesignerElementType.text,
          text: 'نے جامعہ ہذا کے نصابِ تعلیم کے تمام درجات و امتحانات میں بفضلہٖ تعالیٰ کامیابی حاصل کر کے درجۂ علیا کی تکمیل فرمائی ہے۔',
          xRatio: 0.10,
          yRatio: 0.54,
          widthRatio: 0.80,
          heightRatio: 0.12,
          fontSize: 13.5,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Serial No & Date
        DesignerElement(
          id: 'c_serial',
          type: DesignerElementType.token,
          tokenKey: '{{cert.serial_no}}',
          text: 'سند نمبر: SANAD-2025-089',
          xRatio: 0.65,
          yRatio: 0.68,
          widthRatio: 0.25,
          heightRatio: 0.05,
          fontSize: 10,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        DesignerElement(
          id: 'c_date',
          type: DesignerElementType.token,
          tokenKey: '{{cert.issue_date}}',
          text: 'بتاریخ: ١٥ شوال المکرم ١٤٤٦ھ / ٢٠٢٥ء',
          xRatio: 0.10,
          yRatio: 0.68,
          widthRatio: 0.35,
          heightRatio: 0.05,
          fontSize: 10,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Gold Seal in Center
        DesignerElement(
          id: 'c_seal',
          type: DesignerElementType.stamp,
          text: 'مہر جامعہ',
          xRatio: 0.43,
          yRatio: 0.72,
          widthRatio: 0.14,
          heightRatio: 0.18,
          borderColor: const Color(0xFFD4AF37),
          borderWidth: 2,
          isCircular: true,
          zIndex: 1,
        ),
        // Signatures
        DesignerElement(
          id: 'c_sign_principal',
          type: DesignerElementType.signature,
          text: 'دستخط مہتمم جامعہ',
          xRatio: 0.70,
          yRatio: 0.80,
          widthRatio: 0.22,
          heightRatio: 0.10,
          fontSize: 12,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        DesignerElement(
          id: 'c_sign_teacher',
          type: DesignerElementType.signature,
          text: 'دستخط صدر المدرسین',
          xRatio: 0.08,
          yRatio: 0.80,
          widthRatio: 0.22,
          heightRatio: 0.10,
          fontSize: 12,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 5. Starter: Fee Collection Receipt (A5 Landscape: 210 x 148mm)
  // ─────────────────────────────────────────────────────────────
  static DesignerTemplate _buildFeeReceiptStarter() {
    return DesignerTemplate(
      id: 'starter_fee_receipt_a5',
      name: 'فیس وصولی رسید (Fee Collection Receipt A5)',
      documentType: DocumentType.feeReceipt,
      preset: CanvasPreset.a5Landscape,
      widthMm: 210.0,
      heightMm: 148.0,
      backgroundColor: Colors.white,
      elements: [
        // Header
        DesignerElement(
          id: 'f_hdr',
          type: DesignerElementType.token,
          tokenKey: '{{madarsa.name}}',
          text: 'جامعہ اسلامیہ دارالعلوم - شعبہ مالیات و فیس رسید',
          xRatio: 0.05,
          yRatio: 0.04,
          widthRatio: 0.90,
          heightRatio: 0.10,
          color: const Color(0xFF0F3814),
          fontSize: 16,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Receipt No & Date
        DesignerElement(
          id: 'f_rec_no',
          type: DesignerElementType.token,
          tokenKey: '{{fee.receipt_no}}',
          text: 'رسید نمبر: RCP-2025-0348',
          xRatio: 0.65,
          yRatio: 0.15,
          widthRatio: 0.30,
          heightRatio: 0.07,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        DesignerElement(
          id: 'f_month',
          type: DesignerElementType.token,
          tokenKey: '{{fee.month_year}}',
          text: 'ماہ: مارچ ٢٠٢٥ء',
          xRatio: 0.05,
          yRatio: 0.15,
          widthRatio: 0.30,
          heightRatio: 0.07,
          fontSize: 11,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Student Info
        DesignerElement(
          id: 'f_st_name',
          type: DesignerElementType.token,
          tokenKey: '{{student.name}}',
          text: 'نام طالب علم: محمد زید بن خالد انصاری  |  جی آر: GR-1045',
          xRatio: 0.05,
          yRatio: 0.23,
          widthRatio: 0.90,
          heightRatio: 0.07,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Table of Fee heads
        DesignerElement(
          id: 'f_table',
          type: DesignerElementType.table,
          text: 'تفصیل فیس (Fee Breakdown Table)',
          xRatio: 0.05,
          yRatio: 0.32,
          widthRatio: 0.90,
          heightRatio: 0.38,
          borderColor: const Color(0xFF0F3814),
          borderWidth: 1.0,
          zIndex: 1,
        ),
        // Total Amount Box
        DesignerElement(
          id: 'f_total_box',
          type: DesignerElementType.token,
          tokenKey: '{{fee.amount_paid}}',
          text: 'کل ادا شدہ رقم: ₹ 2,500 (نقدی)',
          xRatio: 0.50,
          yRatio: 0.73,
          widthRatio: 0.45,
          heightRatio: 0.10,
          backgroundColor: const Color(0xFFE2E8F0),
          color: const Color(0xFF0F3814),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          borderRadius: 4,
          zIndex: 1,
        ),
        // Cashier Signature
        DesignerElement(
          id: 'f_sign',
          type: DesignerElementType.signature,
          text: 'دستخط وصول کنندہ (خازن)',
          xRatio: 0.05,
          yRatio: 0.82,
          widthRatio: 0.35,
          heightRatio: 0.12,
          fontSize: 10.5,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 6. Starter: Purchase / Store Invoice (A5 Portrait: 148 x 210mm)
  // ─────────────────────────────────────────────────────────────
  static DesignerTemplate _buildPurchaseInvoiceStarter() {
    return DesignerTemplate(
      id: 'starter_purchase_bill_a5',
      name: 'خرید و فروخت انوائس بل (Store & Purchase Bill A5)',
      documentType: DocumentType.purchaseBill,
      preset: CanvasPreset.a5Portrait,
      widthMm: 148.0,
      heightMm: 210.0,
      backgroundColor: Colors.white,
      elements: [
        // Title
        DesignerElement(
          id: 'b_title',
          type: DesignerElementType.token,
          tokenKey: '{{madarsa.name}}',
          text: 'جامعہ دارالعلوم - شعبہ مطبخ و کتب خانہ (بل انوائس)',
          xRatio: 0.05,
          yRatio: 0.03,
          widthRatio: 0.90,
          heightRatio: 0.08,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          color: const Color(0xFF1E3A8A),
          zIndex: 1,
        ),
        // Invoice details
        DesignerElement(
          id: 'b_inv_no',
          type: DesignerElementType.token,
          tokenKey: '{{bill.invoice_no}}',
          text: 'انوائس نمبر: INV-2025-0112',
          xRatio: 0.50,
          yRatio: 0.12,
          widthRatio: 0.45,
          heightRatio: 0.05,
          fontSize: 10,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        DesignerElement(
          id: 'b_party',
          type: DesignerElementType.token,
          tokenKey: '{{bill.party_name}}',
          text: 'خریدار / دکاندار: مکتبہ رحمانیہ کتب خانہ',
          xRatio: 0.05,
          yRatio: 0.18,
          widthRatio: 0.90,
          heightRatio: 0.05,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Item Table
        DesignerElement(
          id: 'b_table',
          type: DesignerElementType.table,
          text: 'تفصیل اشیاء (Itemized Table)',
          xRatio: 0.05,
          yRatio: 0.25,
          widthRatio: 0.90,
          heightRatio: 0.45,
          borderColor: Colors.grey.shade400,
          borderWidth: 1.0,
          zIndex: 1,
        ),
        // Grand Total Box
        DesignerElement(
          id: 'b_total',
          type: DesignerElementType.token,
          tokenKey: '{{bill.grand_total}}',
          text: 'کل قابل ادا رقم: ₹ 14,850',
          xRatio: 0.45,
          yRatio: 0.73,
          widthRatio: 0.50,
          heightRatio: 0.08,
          backgroundColor: const Color(0xFFEFF6FF),
          color: const Color(0xFF1E3A8A),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          borderRadius: 4,
          zIndex: 1,
        ),
        // Signature
        DesignerElement(
          id: 'b_sign',
          type: DesignerElementType.signature,
          text: 'دستخط انچارج / ناظم',
          xRatio: 0.05,
          yRatio: 0.85,
          widthRatio: 0.40,
          heightRatio: 0.08,
          fontSize: 10,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 7. Starter: Library Card / Ticket (CR80 Horizontal: 85.6 x 53.98mm)
  // ─────────────────────────────────────────────────────────────
  static DesignerTemplate _buildLibraryCardStarter() {
    return DesignerTemplate(
      id: 'starter_library_card_cr80',
      name: 'لائبریری ممبرشپ کارڈ (Library Membership Card)',
      documentType: DocumentType.libraryCard,
      preset: CanvasPreset.cr80Horizontal,
      widthMm: 85.6,
      heightMm: 53.98,
      backgroundColor: const Color(0xFFF0FDF4), // Mint Green
      elements: [
        // Header
        DesignerElement(
          id: 'l_hdr',
          type: DesignerElementType.shape,
          shapeType: 'rectangle',
          xRatio: 0.0,
          yRatio: 0.0,
          widthRatio: 1.0,
          heightRatio: 0.22,
          backgroundColor: const Color(0xFF166534), // Forest Green
          zIndex: 0,
        ),
        DesignerElement(
          id: 'l_title',
          type: DesignerElementType.text,
          text: 'دارالکتب و کتب خانہ - لائبریری کارڈ',
          xRatio: 0.05,
          yRatio: 0.04,
          widthRatio: 0.90,
          heightRatio: 0.15,
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
        // Student Name
        DesignerElement(
          id: 'l_name',
          type: DesignerElementType.token,
          tokenKey: '{{student.name}}',
          text: 'نام ممبر: محمد زید انصاری',
          xRatio: 0.05,
          yRatio: 0.27,
          widthRatio: 0.60,
          heightRatio: 0.13,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Card No
        DesignerElement(
          id: 'l_card_no',
          type: DesignerElementType.token,
          tokenKey: '{{lib.card_no}}',
          text: 'کارڈ نمبر: LIB-058',
          xRatio: 0.66,
          yRatio: 0.27,
          widthRatio: 0.29,
          heightRatio: 0.13,
          fontSize: 10,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Valid Upto
        DesignerElement(
          id: 'l_valid',
          type: DesignerElementType.token,
          tokenKey: '{{lib.valid_upto}}',
          text: 'میعاد: 31/12/2025',
          xRatio: 0.05,
          yRatio: 0.42,
          widthRatio: 0.45,
          heightRatio: 0.11,
          fontSize: 9,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Book Limit
        DesignerElement(
          id: 'l_limit',
          type: DesignerElementType.token,
          tokenKey: '{{lib.book_limit}}',
          text: 'حد کتاب: 2 کتب (14 یوم)',
          xRatio: 0.52,
          yRatio: 0.42,
          widthRatio: 0.43,
          heightRatio: 0.11,
          fontSize: 9,
          textAlign: TextAlign.right,
          zIndex: 1,
        ),
        // Barcode
        DesignerElement(
          id: 'l_barcode',
          type: DesignerElementType.barcode,
          tokenKey: '{{lib.card_no}}',
          text: 'LIB-058',
          xRatio: 0.15,
          yRatio: 0.58,
          widthRatio: 0.70,
          heightRatio: 0.22,
          zIndex: 1,
        ),
        // Footer Sign
        DesignerElement(
          id: 'l_sign',
          type: DesignerElementType.signature,
          text: 'دستخط ناظم کتب خانہ',
          xRatio: 0.25,
          yRatio: 0.83,
          widthRatio: 0.50,
          heightRatio: 0.13,
          fontSize: 8.5,
          textAlign: TextAlign.center,
          zIndex: 1,
        ),
      ],
    );
  }
}
