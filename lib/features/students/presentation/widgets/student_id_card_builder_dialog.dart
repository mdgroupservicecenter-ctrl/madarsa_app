import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_constants.dart';
import '../../data/models/student_model.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';

/// Interactive ID Card Template Builder
/// Users can upload their own template image and drag student details onto it.
/// Supports single student and bulk (multiple students) modes.
class StudentIdCardBuilderDialog extends StatefulWidget {
  final Student student;
  final List<Student>? bulkStudents;
  final List<Student>? allStudents;

  const StudentIdCardBuilderDialog({
    super.key,
    required this.student,
    this.bulkStudents,
    this.allStudents,
  });

  /// Open for a single student
  static void show(BuildContext context, Student student, {List<Student>? allStudents}) {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess('students_id_card') && !license.hasFeatureAccess('students_id_card_print')) {
      UpgradePlanDialog.show(context, highlightModule: 'ID Card Builder & Designer');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentIdCardBuilderDialog(
          student: student,
          allStudents: allStudents,
        ),
      ),
    );
  }

  /// Open for bulk printing — designs template using first student as preview,
  /// then prints all students with that template.
  static void showBulk(BuildContext context, List<Student> students, {List<Student>? allStudents}) {
    if (students.isEmpty) return;
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess('students_id_card') && !license.hasFeatureAccess('students_id_card_print')) {
      UpgradePlanDialog.show(context, highlightModule: 'ID Card Printing');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudentIdCardBuilderDialog(
          student: students.first,
          bulkStudents: students,
          allStudents: allStudents ?? students,
        ),
      ),
    );
  }

  @override
  State<StudentIdCardBuilderDialog> createState() =>
      _StudentIdCardBuilderDialogState();
}

// ─── Element configuration for each draggable field ────────────────
class _FieldConfig {
  String label;
  String displayText;
  bool visible;
  double x; // normalized 0..1
  double y; // normalized 0..1
  double fontSize;
  Color color;
  bool bold;
  bool isPhoto;
  bool isQr;
  bool isSignature;
  bool isStamp;
  double photoWidth;
  double photoHeight;
  String side; // 'front' or 'back'
  bool isCombinedName; // true for full name, false for only name
  bool isCombinedAddress; // true for full combined address, false for only address
  bool isRoundPhoto;   // true for circular, false for rectangular
  double textWidthMm;  // text box width in mm
  double textHeightMm; // text box height in mm

  _FieldConfig({
    required this.label,
    required this.displayText,
    this.visible = true,
    required this.x,
    required this.y,
    this.fontSize = 12.0,
    this.color = Colors.black,
    this.bold = false,
    this.isPhoto = false,
    this.isQr = false,
    this.isSignature = false,
    this.isStamp = false,
    this.photoWidth = 60,
    this.photoHeight = 75,
    this.side = 'front',
    this.isCombinedName = false,
    this.isCombinedAddress = false,
    this.isRoundPhoto = false,
    this.textWidthMm = 40.0,
    this.textHeightMm = 10.0,
  });
}

class _StudentIdCardBuilderDialogState
    extends State<StudentIdCardBuilderDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _isPrinting = false;

  // ─── Template backgrounds ──────────────────────────────
  File? _frontTemplateFile;
  File? _backTemplateFile;
  File? _signatureFile; // Principal Signature file
  File? _stampFile;     // Stamp file
  bool _useFrontTemplate = false;
  bool _useBackTemplate = false;
  bool _previewingFront = true;
  int _currentMobileTabIndex = 0; // Active mobile tab index
  final FocusNode _keyboardFocusNode = FocusNode(); // Keyboard navigation focus node

  double _cardWidthMm = 54.0;
  double _cardHeightMm = 85.6;
  bool get _isPortrait => _cardWidthMm <= _cardHeightMm;
  double _borderRadius = 12.0;
  Color _bgColor1 = const Color(0xFF0D6B4E);
  Color _bgColor2 = const Color(0xFF063A2A);
  Color _borderColor = const Color(0xFFFFD700);
  double _borderWidth = 1.5;
  bool _isGradient = true;

  // ─── Fields ───────────────────────────────────────────
  late Map<String, _FieldConfig> _fields;
  String? _selectedFieldKey;

  // ─── Canvas size (proportional to custom card size) ───
  double get _canvasWidth => _cardWidthMm * (300.0 / 54.0);

  // ─── Class Filtering & Student Pool ───
  String? _selectedClassFilter;
  late Student _currentPreviewStudent;

  List<Student> get _availablePool {
    return widget.allStudents ?? widget.bulkStudents ?? [widget.student];
  }

  List<String> get _availableClasses {
    final classes = _availablePool
        .map((s) => s.className ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return classes;
  }

  List<Student> get _effectiveStudents {
    if (_selectedClassFilter == null || _selectedClassFilter == 'ALL') {
      return widget.bulkStudents ?? _availablePool;
    }
    return _availablePool.where((s) => s.className == _selectedClassFilter).toList();
  }

  bool get _isBulkMode => _effectiveStudents.length > 1;

  void _updatePreviewStudent(Student s) {
    setState(() {
      _currentPreviewStudent = s;
      if (_fields.containsKey('name')) {
        _fields['name']!.displayText = _getStudentNameDisplay(s, _fields['name']!.isCombinedName);
      }
      if (_fields.containsKey('father')) _fields['father']!.displayText = s.fatherName ?? '-';
      if (_fields.containsKey('grand_father')) _fields['grand_father']!.displayText = s.grandFatherName ?? '-';
      if (_fields.containsKey('surname')) _fields['surname']!.displayText = s.surname ?? '-';
      if (_fields.containsKey('gr_no')) _fields['gr_no']!.displayText = s.grNo ?? s.registrationNumber;
      if (_fields.containsKey('class')) _fields['class']!.displayText = s.className ?? 'N/A';
      if (_fields.containsKey('dob')) _fields['dob']!.displayText = s.dateOfBirth ?? '-';
      if (_fields.containsKey('village')) _fields['village']!.displayText = s.village ?? '-';
      if (_fields.containsKey('taluka')) _fields['taluka']!.displayText = s.taluka ?? '-';
      if (_fields.containsKey('district')) _fields['district']!.displayText = s.district ?? '-';
      if (_fields.containsKey('state')) _fields['state']!.displayText = s.state ?? '-';
    });
  }

  @override
  void initState() {
    super.initState();
    _currentPreviewStudent = widget.student;
    _initFields();
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _initFields() {
    final s = _currentPreviewStudent;
    _fields = {
      'institution': _FieldConfig(
        label: 'Institution Name',
        displayText: 'MADARSA AL-HIDAYAH',
        x: 0.05,
        y: 0.03,
        fontSize: 13,
        color: Colors.black,
        bold: true,
        side: 'front',
      ),
      'photo': _FieldConfig(
        label: 'Student Photo',
        displayText: '',
        x: 0.30,
        y: 0.14,
        fontSize: 12,
        color: Colors.black,
        isPhoto: true,
        photoWidth: 65,
        photoHeight: 80,
        side: 'front',
      ),
      'name': _FieldConfig(
        label: 'Student Name',
        displayText: s.fullName,
        x: 0.05,
        y: 0.52,
        fontSize: 14,
        color: Colors.black,
        bold: true,
        side: 'front',
      ),
      'father': _FieldConfig(
        label: 'Father Name',
        displayText: s.fatherName ?? '-',
        x: 0.05,
        y: 0.59,
        fontSize: 11,
        color: Colors.black,
        side: 'front',
      ),
      'grand_father': _FieldConfig(
        label: 'Grandfather Name',
        displayText: s.grandFatherName ?? '-',
        x: 0.05,
        y: 0.62,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'surname': _FieldConfig(
        label: 'Surname',
        displayText: s.surname ?? '-',
        x: 0.05,
        y: 0.64,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'gr_no': _FieldConfig(
        label: 'GR Number',
        displayText: s.grNo ?? s.registrationNumber,
        x: 0.05,
        y: 0.66,
        fontSize: 11,
        color: Colors.black,
        bold: true,
        side: 'front',
      ),
      'class': _FieldConfig(
        label: 'Class / Darja',
        displayText: s.className ?? 'N/A',
        x: 0.05,
        y: 0.73,
        fontSize: 11,
        color: Colors.black,
        side: 'front',
      ),
      'roll_number': _FieldConfig(
        label: 'Roll Number',
        displayText: s.rollNumber ?? '-',
        x: 0.55,
        y: 0.73,
        fontSize: 11,
        color: Colors.black,
        side: 'front',
      ),
      'dob': _FieldConfig(
        label: 'Date of Birth',
        displayText: s.dateOfBirth ?? '-',
        x: 0.05,
        y: 0.80,
        fontSize: 11,
        color: Colors.black,
        side: 'front',
      ),
      'village': _FieldConfig(
        label: 'Village',
        displayText: s.village ?? '-',
        x: 0.05,
        y: 0.85,
        fontSize: 11,
        color: Colors.black,
        side: 'front',
      ),
      'taluka': _FieldConfig(
        label: 'Taluka',
        displayText: s.taluka ?? '-',
        x: 0.05,
        y: 0.88,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'district': _FieldConfig(
        label: 'District',
        displayText: s.district ?? '-',
        x: 0.05,
        y: 0.90,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'state': _FieldConfig(
        label: 'State',
        displayText: s.state ?? '-',
        x: 0.05,
        y: 0.92,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'pin_code': _FieldConfig(
        label: 'Pin Code',
        displayText: s.pinCode ?? '-',
        x: 0.05,
        y: 0.94,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'address': _FieldConfig(
        label: 'Address',
        displayText: s.address ?? '-',
        x: 0.05,
        y: 0.95,
        fontSize: 10,
        color: Colors.black,
        visible: false,
        side: 'front',
        isCombinedAddress: false,
      ),
      'mobile': _FieldConfig(
        label: 'Mobile Number',
        displayText: s.mobileNo ?? '-',
        x: 0.05,
        y: 0.96,
        fontSize: 10,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'aadhaar': _FieldConfig(
        label: 'Aadhaar Number',
        displayText: s.aadhaarNo ?? '-',
        x: 0.05,
        y: 0.70,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'gender': _FieldConfig(
        label: 'Gender',
        displayText: s.gender ?? '-',
        x: 0.05,
        y: 0.75,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'category': _FieldConfig(
        label: 'Category',
        displayText: s.category ?? '-',
        x: 0.05,
        y: 0.77,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'admission_type': _FieldConfig(
        label: 'Admission Type',
        displayText: s.admissionType ?? '-',
        x: 0.05,
        y: 0.79,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'admission_date': _FieldConfig(
        label: 'Admission Date',
        displayText: s.admissionDate ?? '-',
        x: 0.05,
        y: 0.81,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'admission_date_h': _FieldConfig(
        label: 'Admission Date (Hijri)',
        displayText: s.admissionDateH ?? '-',
        x: 0.05,
        y: 0.83,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'monthly_fees': _FieldConfig(
        label: 'Monthly Fees',
        displayText: s.monthlyFees != null ? s.monthlyFees!.toStringAsFixed(0) : '-',
        x: 0.05,
        y: 0.84,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'age': _FieldConfig(
        label: 'Age',
        displayText: s.nowAge ?? s.admissionTimeAge ?? '-',
        x: 0.05,
        y: 0.86,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'qr': _FieldConfig(
        label: 'QR Code',
        displayText: '',
        x: 0.35,
        y: 0.30,
        fontSize: 12,
        color: Colors.black,
        isQr: true,
        photoWidth: 70,
        photoHeight: 70,
        side: 'back',
      ),
      'signature': _FieldConfig(
        label: 'Principal Signature',
        displayText: '',
        x: 0.10,
        y: 0.85,
        fontSize: 12,
        color: Colors.black,
        isSignature: true,
        photoWidth: 70,
        photoHeight: 35,
        visible: false,
        side: 'front',
      ),
      'stamp': _FieldConfig(
        label: 'Stamp',
        displayText: '',
        x: 0.60,
        y: 0.85,
        fontSize: 12,
        color: Colors.black,
        isStamp: true,
        photoWidth: 50,
        photoHeight: 50,
        visible: false,
        side: 'front',
      ),
      'custom_text_1': _FieldConfig(
        label: 'Custom Text 1',
        displayText: 'Custom Text 1',
        x: 0.10,
        y: 0.70,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'custom_text_2': _FieldConfig(
        label: 'Custom Text 2',
        displayText: 'Custom Text 2',
        x: 0.10,
        y: 0.75,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
      'custom_text_3': _FieldConfig(
        label: 'Custom Text 3',
        displayText: 'Custom Text 3',
        x: 0.10,
        y: 0.80,
        fontSize: 11,
        color: Colors.black,
        visible: false,
        side: 'front',
      ),
    };
  }

  // ─── Template pickers ─────────────────────────────────
  Future<void> _pickTemplate({required bool isFront}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        if (isFront) {
          _frontTemplateFile = File(result.files.single.path!);
          _useFrontTemplate = true;
        } else {
          _backTemplateFile = File(result.files.single.path!);
          _useBackTemplate = true;
        }
      });
    }
  }

  void _removeTemplate({required bool isFront}) {
    setState(() {
      if (isFront) {
        _frontTemplateFile = null;
        _useFrontTemplate = false;
      } else {
        _backTemplateFile = null;
        _useBackTemplate = false;
      }
    });
  }



  // ─── Render Urdu text to image for high-res Nastaleeq in PDF ───
  Future<pw.Widget> _buildPdfText(
    String text,
    _FieldConfig f,
    double scaleFactor,
    pw.Font font,
    pw.Font fontBold,
  ) async {
    final pdfFontSize = f.fontSize * scaleFactor;
    final pdfColor = PdfColor.fromInt(f.color.value);

    pw.Widget resultWidget;

    if (_isUrdu(text)) {
      try {
        final reshapedText = ArabicReshaper.instance.reshape(text);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);

        final textPainter = TextPainter(
          text: TextSpan(
            text: reshapedText,
            style: TextStyle(
              fontFamily: 'JameelNooriNastaleeq',
              fontSize: pdfFontSize * 3.0, // Scale up for high-res print
              color: f.color,
            ),
          ),
          textDirection: TextDirection.rtl,
        );

        textPainter.layout();
        textPainter.paint(canvas, const Offset(0, 0));

        final picture = recorder.endRecording();
        final width = textPainter.width.ceil();
        final height = textPainter.height.ceil();
        final imgWidth = width > 0 ? width : 1;
        final imgHeight = height > 0 ? height : 1;

        final img = await picture.toImage(imgWidth, imgHeight);
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
        final pngBytes = byteData!.buffer.asUint8List();

        final pdfImage = pw.MemoryImage(pngBytes);
        resultWidget = pw.Image(
          pdfImage,
          width: width / 3.0,
          height: height / 3.0,
        );
      } catch (e) {
        // Fallback to standard PDF text if rendering fails
        resultWidget = pw.Text(
          text,
          style: pw.TextStyle(
            font: f.bold ? fontBold : font,
            fontSize: pdfFontSize,
            color: pdfColor,
          ),
        );
      }
    } else {
      resultWidget = pw.Text(
        text,
        style: pw.TextStyle(
          font: f.bold ? fontBold : font,
          fontSize: pdfFontSize,
          color: pdfColor,
        ),
      );
    }

    return pw.Container(
      width: f.textWidthMm * PdfPageFormat.mm,
      height: f.textHeightMm * PdfPageFormat.mm,
      child: resultWidget,
    );
  }

  bool _isUrdu(String text) {
    final RegExp urduRegExp = RegExp(
        r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');
    return urduRegExp.hasMatch(text);
  }

  String _getStudentNameDisplay(Student s, bool isCombined) {
    if (!isCombined) {
      return s.fullName;
    }
    final nameLower = s.fullName.toLowerCase();
    final fatherLower = (s.fatherName ?? '').trim().toLowerCase();
    final surnameLower = (s.surname ?? '').trim().toLowerCase();

    String combined = s.fullName;
    
    if (s.fatherName != null && s.fatherName!.trim().isNotEmpty) {
      if (!nameLower.contains(fatherLower)) {
        combined += ' ${s.fatherName!.trim()}';
      }
    }

    if (s.surname != null && s.surname!.trim().isNotEmpty) {
      final currentCombinedLower = combined.toLowerCase();
      if (!currentCombinedLower.contains(surnameLower)) {
        combined += ' ${s.surname!.trim()}';
      }
    }
    
    return combined.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _getStudentFullAddressDisplay(Student s, bool isCombined) {
    if (!isCombined) {
      return s.address ?? '-';
    }
    final parts = <String>[];
    if (s.address != null && s.address!.trim().isNotEmpty) parts.add(s.address!.trim());
    if (s.village != null && s.village!.trim().isNotEmpty) parts.add(s.village!.trim());
    if (s.taluka != null && s.taluka!.trim().isNotEmpty && s.taluka!.trim().toUpperCase() != 'NA') {
      parts.add(s.taluka!.trim());
    }
    if (s.district != null && s.district!.trim().isNotEmpty) parts.add(s.district!.trim());
    if (s.state != null && s.state!.trim().isNotEmpty) parts.add(s.state!.trim());
    if (s.pinCode != null && s.pinCode!.trim().isNotEmpty) parts.add(s.pinCode!.trim());

    return parts.isNotEmpty ? parts.join(', ') : '-';
  }

  // ─── Save PDF directly to location ──────────────────────
  Future<void> _printCard() async {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess('students_id_card_print')) {
      UpgradePlanDialog.show(context, highlightModule: 'ID Card Printing');
      return;
    }

    if (_isPrinting) return;
    setState(() => _isPrinting = true);

    try {
      final pdfDoc = pw.Document();
      final pageFormat = PdfPageFormat(
        _cardWidthMm * PdfPageFormat.mm,
        _cardHeightMm * PdfPageFormat.mm,
        marginAll: 0.0,
      );

      final students = _effectiveStudents;

      // ─── 1. Load fonts ───
      pw.Font font;
      pw.Font fontBold;
      try {
        font = await PdfGoogleFonts.notoSansRegular();
        fontBold = await PdfGoogleFonts.notoSansBold();
      } catch (_) {
        font = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
      }

      // ─── 2. Load template background images ───
      pw.ImageProvider? frontTemplateImage;
      if (_useFrontTemplate && _frontTemplateFile != null && await _frontTemplateFile!.exists()) {
        try {
          final bytes = await _frontTemplateFile!.readAsBytes();
          frontTemplateImage = pw.MemoryImage(bytes);
        } catch (_) {}
      }
      pw.ImageProvider? backTemplateImage;
      if (_useBackTemplate && _backTemplateFile != null && await _backTemplateFile!.exists()) {
        try {
          final bytes = await _backTemplateFile!.readAsBytes();
          backTemplateImage = pw.MemoryImage(bytes);
        } catch (_) {}
      }

      // ─── 3. Pre-fetch student photos concurrently ───
      final baseUrl = ApiConstants.baseUrl.replaceAll('/api', '');
      final resolvedPhotos = await Future.wait(
        students.map((st) async {
          if (st.photoPath != null && st.photoPath!.isNotEmpty) {
            try {
              final imageUrl = '$baseUrl${st.photoPath}';
              return await networkImage(imageUrl);
            } catch (_) {
              return null;
            }
          }
          return null;
        }),
      );

      final pdfW = _cardWidthMm * PdfPageFormat.mm;
      final pdfH = _cardHeightMm * PdfPageFormat.mm;
      final scaleFactor = pdfW / _canvasWidth;

      final pdfBgColor1 = PdfColor.fromInt(_bgColor1.value);
      final pdfBgColor2 = PdfColor.fromInt(_bgColor2.value);
      final pdfBorderColor = PdfColor.fromInt(_borderColor.value);

      // Pre-read signature & stamp bytes safely
      Uint8List? signatureBytes;
      if (_signatureFile != null && await _signatureFile!.exists()) {
        try {
          signatureBytes = await _signatureFile!.readAsBytes();
        } catch (_) {}
      }

      Uint8List? stampBytes;
      if (_stampFile != null && await _stampFile!.exists()) {
        try {
          stampBytes = await _stampFile!.readAsBytes();
        } catch (_) {}
      }

      // ─── 4. Build page loop for each student ───
      for (int i = 0; i < students.length; i++) {
        final s = students[i];
        final photoProvider = resolvedPhotos[i];

        final Map<String, String> frontTexts = {
          'institution': _fields['institution']?.displayText ?? 'MADARSA AL-HIDAYAH',
          'name': _getStudentNameDisplay(s, _fields['name']?.isCombinedName ?? false),
          'father': s.fatherName ?? '-',
          'grand_father': s.grandFatherName ?? '-',
          'surname': s.surname ?? '-',
          'gr_no': s.grNo ?? s.registrationNumber,
          'class': s.className ?? 'N/A',
          'dob': s.dateOfBirth ?? '-',
          'village': s.village ?? '-',
          'taluka': s.taluka ?? '-',
          'district': s.district ?? '-',
          'state': s.state ?? '-',
          'pin_code': s.pinCode ?? '-',
          'address': _getStudentFullAddressDisplay(s, _fields['address']?.isCombinedAddress ?? false),
          'mobile': s.mobileNo ?? '-',
          'aadhaar': s.aadhaarNo ?? '-',
          'gender': s.gender ?? '-',
          'category': s.category ?? '-',
          'admission_type': s.admissionType ?? '-',
          'admission_date': s.admissionDate ?? '-',
          'admission_date_h': s.admissionDateH ?? '-',
          'monthly_fees': s.monthlyFees != null ? s.monthlyFees!.toStringAsFixed(0) : '-',
          'age': s.nowAge ?? s.admissionTimeAge ?? '-',
        };

        final qrPayload = 'GR:${s.grNo ?? s.registrationNumber}\nName:${s.fullName}\nClass:${s.className ?? "N/A"}';

        Future<pw.Widget> buildCardSide(String targetSide) async {
          final isFront = targetSide == 'front';
          final bgImage = isFront ? frontTemplateImage : backTemplateImage;

          pw.Widget background;
          if (bgImage != null) {
            background = pw.Image(bgImage, width: pdfW, height: pdfH, fit: pw.BoxFit.fill);
          } else {
            background = pw.Container(
              width: pdfW,
              height: pdfH,
              decoration: pw.BoxDecoration(
                color: pdfBgColor1,
                borderRadius: pw.BorderRadius.circular(_borderRadius * scaleFactor),
                border: pw.Border.all(
                  color: pdfBorderColor,
                  width: _borderWidth * scaleFactor,
                ),
                gradient: _isGradient
                    ? pw.LinearGradient(
                        colors: [pdfBgColor1, pdfBgColor2],
                        begin: pw.Alignment.topLeft,
                        end: pw.Alignment.bottomRight,
                      )
                    : null,
              ),
            );
          }

          final List<pw.Widget> children = [background];

          for (final entry in _fields.entries) {
            final f = entry.value;
            if (f.side != targetSide || !f.visible) continue;

            final posX = f.x * pdfW;
            final posY = f.y * pdfH;

            pw.Widget elementWidget;

            if (f.isPhoto) {
              elementWidget = pw.Container(
                width: f.photoWidth * scaleFactor,
                height: (f.isRoundPhoto ? f.photoWidth : f.photoHeight) * scaleFactor,
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  shape: f.isRoundPhoto ? pw.BoxShape.circle : pw.BoxShape.rectangle,
                  borderRadius: f.isRoundPhoto ? null : pw.BorderRadius.circular(6 * scaleFactor),
                  border: pw.Border.all(color: pdfBorderColor, width: 1 * scaleFactor),
                  image: photoProvider != null
                      ? pw.DecorationImage(image: photoProvider, fit: pw.BoxFit.cover)
                      : null,
                ),
              );
            } else if (f.isQr) {
              elementWidget = pw.Container(
                width: f.photoWidth * scaleFactor,
                height: f.photoHeight * scaleFactor,
                color: PdfColors.white,
                padding: pw.EdgeInsets.all(3 * scaleFactor),
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrPayload,
                  color: PdfColor.fromInt(f.color.value),
                ),
              );
            } else if (f.isSignature) {
              elementWidget = signatureBytes != null
                  ? pw.Image(pw.MemoryImage(signatureBytes),
                      width: f.photoWidth * scaleFactor,
                      height: f.photoHeight * scaleFactor,
                      fit: pw.BoxFit.contain)
                  : pw.Container(
                      width: f.photoWidth * scaleFactor,
                      height: f.photoHeight * scaleFactor,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                      ),
                      child: pw.Center(child: pw.Text('No Sig', style: const pw.TextStyle(fontSize: 8))),
                    );
            } else if (f.isStamp) {
              elementWidget = stampBytes != null
                  ? pw.Image(pw.MemoryImage(stampBytes),
                      width: f.photoWidth * scaleFactor,
                      height: f.photoHeight * scaleFactor,
                      fit: pw.BoxFit.contain)
                  : pw.Container(
                      width: f.photoWidth * scaleFactor,
                      height: f.photoHeight * scaleFactor,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                      ),
                      child: pw.Center(child: pw.Text('No Stamp', style: const pw.TextStyle(fontSize: 8))),
                    );
            } else {
              final text = frontTexts[entry.key] ?? f.displayText;
              elementWidget = await _buildPdfText(text, f, scaleFactor, font, fontBold);
            }

            children.add(
              pw.Positioned(
                left: posX,
                top: posY,
                child: elementWidget,
              ),
            );
          }

          return pw.Stack(children: children);
        }

        // Add Front Page
        final frontCardWidget = await buildCardSide('front');
        pdfDoc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (pw.Context ctx) {
              return pw.FullPage(
                ignoreMargins: true,
                child: frontCardWidget,
              );
            },
          ),
        );

        // Add Back Page
        final backCardWidget = await buildCardSide('back');
        pdfDoc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (pw.Context ctx) {
              return pw.FullPage(
                ignoreMargins: true,
                child: backCardWidget,
              );
            },
          ),
        );
      }

      final pdfBytes = await pdfDoc.save();

      if (!mounted) return;
      final fileName = _isBulkMode
          ? (_selectedClassFilter != null
              ? 'ID_Cards_Class_${_selectedClassFilter}_${students.length}_Students.pdf'
              : 'ID_Cards_${students.length}_Students.pdf')
          : 'ID_Card_${_currentPreviewStudent.fullName.replaceAll(' ', '_')}.pdf';

      // Open Windows / OS "Save As" file dialog directly
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ID Card PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputFile != null) {
        String finalPath = outputFile;
        if (!finalPath.toLowerCase().endsWith('.pdf')) {
          finalPath += '.pdf';
        }
        final file = File(finalPath);
        await file.writeAsBytes(pdfBytes);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ PDF saved successfully: $finalPath'),
            backgroundColor: const Color(0xFF0D6B4E),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save PDF failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  // ─── Build a single draggable field on the canvas ─────
  Widget _buildField(String key, double cw, double ch) {
    final f = _fields[key];
    if (f == null || !f.visible) return const SizedBox.shrink();
    
    // Only display fields that belong to the currently previewed side
    if (f.side != (_previewingFront ? 'front' : 'back')) return const SizedBox.shrink();

    final isSelected = _selectedFieldKey == key;
    final left = f.x * cw;
    final top = f.y * ch;

    // Scale factor for font and image assets based on card width
    final double mmToPx = cw / _cardWidthMm;
    final double previewScale = mmToPx / (300.0 / 54.0);

    Widget child;
    if (f.isPhoto) {
      final w = f.photoWidth * previewScale;
      final h = (f.isRoundPhoto ? f.photoWidth : f.photoHeight) * previewScale;
      child = Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(25),
          shape: f.isRoundPhoto ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: f.isRoundPhoto ? null : BorderRadius.circular(6 * previewScale),
          border: Border.all(
            color: isSelected
                ? Colors.cyan
                : Colors.white.withAlpha(60),
            width: isSelected ? 2 : 1,
          ),
          image: _currentPreviewStudent.photoPath != null &&
                  _currentPreviewStudent.photoPath!.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(
                    '${ApiConstants.baseUrl.replaceAll("/api", "")}${_currentPreviewStudent.photoPath}',
                  ),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: _currentPreviewStudent.photoPath == null ||
                _currentPreviewStudent.photoPath!.isEmpty
            ? Icon(Icons.person_rounded,
                color: Colors.white38, size: w * 0.5)
            : null,
      );
    } else if (f.isQr) {
      final qrPayload =
          'GR:${_currentPreviewStudent.grNo ?? _currentPreviewStudent.registrationNumber}\n'
          'Name:${_currentPreviewStudent.fullName}\n'
          'Class:${_currentPreviewStudent.className ?? "N/A"}';
      final w = f.photoWidth * previewScale;
      final h = f.photoHeight * previewScale;
      child = Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4 * previewScale),
          border: Border.all(
            color: isSelected ? Colors.cyan : Colors.transparent,
            width: isSelected ? 2 : 0,
          ),
        ),
        padding: EdgeInsets.all(3 * previewScale),
        child: QrImageView(
          data: qrPayload,
          version: QrVersions.auto,
          size: w - (6 * previewScale),
          gapless: false,
          eyeStyle: QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: f.color,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: f.color,
          ),
        ),
      );
    } else if (f.isSignature) {
      final w = f.photoWidth * previewScale;
      final h = f.photoHeight * previewScale;
      child = Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.cyan : Colors.grey.shade400,
            width: isSelected ? 2 : 1,
          ),
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(4 * previewScale),
          image: _signatureFile != null
              ? DecorationImage(
                  image: FileImage(_signatureFile!),
                  fit: BoxFit.contain,
                )
              : null,
        ),
        child: _signatureFile == null
            ? Center(
                child: Text(
                  'Signature',
                  style: TextStyle(fontSize: 8 * previewScale, color: Colors.grey),
                ),
              )
            : null,
      );
    } else if (f.isStamp) {
      final w = f.photoWidth * previewScale;
      final h = f.photoHeight * previewScale;
      child = Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.cyan : Colors.grey.shade400,
            width: isSelected ? 2 : 1,
          ),
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(4 * previewScale),
          image: _stampFile != null
              ? DecorationImage(
                  image: FileImage(_stampFile!),
                  fit: BoxFit.contain,
                )
              : null,
        ),
        child: _stampFile == null
            ? Center(
                child: Text(
                  'Stamp',
                  style: TextStyle(fontSize: 8 * previewScale, color: Colors.grey),
                ),
              )
            : null,
      );
    } else {
      String text = f.displayText;
      if (key == 'name') {
        text = _getStudentNameDisplay(_currentPreviewStudent, f.isCombinedName);
      } else if (key == 'address') {
        text = _getStudentFullAddressDisplay(_currentPreviewStudent, f.isCombinedAddress);
      }
      child = Container(
        width: f.textWidthMm * (cw / _cardWidthMm),
        height: f.textHeightMm * (ch / _cardHeightMm),
        padding: EdgeInsets.symmetric(horizontal: 2 * previewScale, vertical: 1 * previewScale),
        decoration: isSelected
            ? BoxDecoration(
                border: Border.all(color: Colors.cyan, width: 1.5),
                borderRadius: BorderRadius.circular(3 * previewScale),
              )
            : null,
        child: Text(
          text,
          style: TextStyle(
            fontSize: f.fontSize * previewScale,
            fontWeight: f.bold ? FontWeight.bold : FontWeight.normal,
            color: f.color,
            height: 1.2,
          ),
        ),
      );
    }

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _selectedFieldKey = key;
            final isDesktop = MediaQuery.of(context).size.width >= 700;
            if (!isDesktop && _currentMobileTabIndex != 3) {
              _currentMobileTabIndex = 3;
            }
          });
        },
        onPanUpdate: (d) {
          setState(() {
            f.x = (f.x + d.delta.dx / cw).clamp(0.0, 0.95);
            f.y = (f.y + d.delta.dy / ch).clamp(0.0, 0.95);
            _selectedFieldKey = key;
          });
        },
        child: child,
      ),
    );
  }

  // ─── Canvas (the ID card visual) ──────────────────────
  Widget _buildCanvas(double cw, double ch) {
    Widget background;
    final useTemplate = _previewingFront ? _useFrontTemplate : _useBackTemplate;
    final templateFile = _previewingFront ? _frontTemplateFile : _backTemplateFile;

    if (useTemplate && templateFile != null) {
      background = ClipRRect(
        borderRadius: BorderRadius.circular(_borderRadius),
        child: Image.file(
          templateFile,
          width: cw,
          height: ch,
          fit: BoxFit.cover,
        ),
      );
    } else {
      background = Container(
        width: cw,
        height: ch,
        decoration: BoxDecoration(
          color: _bgColor1,
          borderRadius: BorderRadius.circular(_borderRadius),
          border: Border.all(color: _borderColor, width: _borderWidth),
          gradient: _isGradient
              ? LinearGradient(
                  colors: [_bgColor1, _bgColor2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _selectedFieldKey = null),
      child: SizedBox(
        width: cw,
        height: ch,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            background,
            ..._fields.keys.map((k) => _buildField(k, cw, ch)),
          ],
        ),
      ),
    );
  }



  Widget _buildFieldsTab(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('📝 ID Card Fields (Add / Remove)'),
        const SizedBox(height: 6),
        Text(
          '💡 Checkbox tick karke ID Card me field add ya remove karein. '
          'Canvas par drag karke position set karein.',
          style: AppTheme.getFontStyle(
              fontSize: 11,
              color: Colors.blue.shade400,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        ..._fields.entries.map((entry) {
          final key = entry.key;
          final f = entry.value;
          final isSelected = _selectedFieldKey == key;
          return _buildFieldTile(key, f, isSelected, isDark);
        }),
      ],
    );
  }

  Widget _buildSettingsPanel(bool isDark) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100,
            child: TabBar(
              indicatorColor: const Color(0xFF0D6B4E),
              indicatorWeight: 3,
              labelColor: isDark ? const Color(0xFF00FFCC) : const Color(0xFF0D6B4E),
              unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              tabs: const [
                Tab(icon: Icon(Icons.playlist_add_check_rounded, size: 18), text: 'Fields (Add/Remove)'),
                Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'Card Settings'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldsTab(isDark),
                      if (_selectedFieldKey != null &&
                          _fields.containsKey(_selectedFieldKey)) ...[
                        const Divider(height: 28),
                        _buildSelectedFieldEditor(isDark),
                      ],
                    ],
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCardSettingsOnlyTab(isDark),
                      if (_selectedFieldKey != null &&
                          _fields.containsKey(_selectedFieldKey)) ...[
                        const Divider(height: 28),
                        _buildSelectedFieldEditor(isDark),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardSettingsOnlyTab(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section 1: Template Upload ──
        _sectionTitle('📷 Template Images'),
        const SizedBox(height: 10),
        
        Text('Front Side Template:', style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
        const SizedBox(height: 4),
        _buildTemplatePickerItem(
          useTemplate: _useFrontTemplate,
          templateFile: _frontTemplateFile,
          onPick: () => _pickTemplate(isFront: true),
          onRemove: () => _removeTemplate(isFront: true),
          isDark: isDark,
        ),
        const SizedBox(height: 12),

        Text('Back Side Template:', style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
        const SizedBox(height: 4),
        _buildTemplatePickerItem(
          useTemplate: _useBackTemplate,
          templateFile: _backTemplateFile,
          onPick: () => _pickTemplate(isFront: false),
          onRemove: () => _removeTemplate(isFront: false),
          isDark: isDark,
        ),
        const Divider(height: 28),

        // ── Section 2: Card Settings (Orientation & Dimensions) ──
        _sectionTitle('🎨 Card Settings'),
        const SizedBox(height: 10),
        _buildSlider('Card Width (mm)', _cardWidthMm, 30, 200, (v) {
          setState(() => _cardWidthMm = v);
        }),
        _buildSlider('Card Height (mm)', _cardHeightMm, 30, 200, (v) {
          setState(() => _cardHeightMm = v);
        }),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          spacing: 6,
          runSpacing: 4,
          children: [
            Text('Orientation:',
                style: AppTheme.getFontStyle(fontSize: (10.5 * _getUiScale(context)).clamp(8.5, 12.0), fontWeight: FontWeight.w600, color: textColor)),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.all(2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _cardWidthMm = 54.0;
                        _cardHeightMm = 85.6;
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: (8 * _getUiScale(context)).clamp(5.0, 10.0), vertical: (3.5 * _getUiScale(context)).clamp(2.0, 4.0)),
                      decoration: BoxDecoration(
                        color: _isPortrait ? const Color(0xFF0D6B4E) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Portrait',
                        style: TextStyle(
                          fontSize: (9.5 * _getUiScale(context)).clamp(7.5, 11.0),
                          fontWeight: FontWeight.bold,
                          color: _isPortrait ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _cardWidthMm = 85.6;
                        _cardHeightMm = 54.0;
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: (8 * _getUiScale(context)).clamp(5.0, 10.0), vertical: (3.5 * _getUiScale(context)).clamp(2.0, 4.0)),
                      decoration: BoxDecoration(
                        color: !_isPortrait ? const Color(0xFF0D6B4E) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Landscape',
                        style: TextStyle(
                          fontSize: (9.5 * _getUiScale(context)).clamp(7.5, 11.0),
                          fontWeight: FontWeight.bold,
                          color: !_isPortrait ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!_useFrontTemplate || !_useBackTemplate) ...[
          const SizedBox(height: 10),
          _buildColorRow('BG Color 1', _bgColor1,
              (c) => setState(() => _bgColor1 = c)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Gradient:',
                  style: AppTheme.getFontStyle(fontSize: 12, color: textColor)),
              const Spacer(),
              Switch(
                value: _isGradient,
                activeColor: const Color(0xFF0D6B4E),
                onChanged: (v) => setState(() => _isGradient = v),
              ),
            ],
          ),
          if (_isGradient)
            _buildColorRow('BG Color 2', _bgColor2,
                (c) => setState(() => _bgColor2 = c)),
          const SizedBox(height: 8),
          _buildColorRow('Border Color', _borderColor,
              (c) => setState(() => _borderColor = c)),
          _buildSlider('Border Width', _borderWidth, 0, 4,
              (v) => setState(() => _borderWidth = v)),
          _buildSlider('Border Radius', _borderRadius, 0, 24,
              (v) => setState(() => _borderRadius = v)),
        ],
      ],
    );
  }

  Widget _buildTextSettingsOnlyTab(bool isDark) {
    if (_selectedFieldKey != null && _fields.containsKey(_selectedFieldKey)) {
      return _buildSelectedFieldEditor(isDark);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_rounded, size: 28, color: isDark ? Colors.cyan.shade300 : const Color(0xFF0D6B4E)),
            const SizedBox(height: 10),
            Text(
              'No Element Selected',
              style: AppTheme.getFontStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Canvas par kisi bhi text/photo par tap karein ya Layers tab se select karein text & size edit karne ke liye.',
              textAlign: TextAlign.center,
              style: AppTheme.getFontStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Field list tile ──────────────────────────────────
  Widget _buildFieldTile(
      String key, _FieldConfig f, bool isSelected, bool isDark) {
    final uiScale = _getUiScale(context);
    final tileFontSize = (12 * uiScale).clamp(9.5, 13.0);
    final pillFontSize = (8.5 * uiScale).clamp(7.0, 10.0);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selectedFieldKey = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 4),
        padding: EdgeInsets.symmetric(horizontal: (8 * uiScale).clamp(6.0, 10.0), vertical: (6 * uiScale).clamp(4.0, 8.0)),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? Colors.cyan.withAlpha(20)
                  : Colors.blue.shade50)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: Colors.cyan.withAlpha(100))
              : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: (20 * uiScale).clamp(16.0, 24.0),
              height: (20 * uiScale).clamp(16.0, 24.0),
              child: Checkbox(
                value: f.visible,
                onChanged: (val) =>
                    setState(() => f.visible = val ?? true),
                activeColor: const Color(0xFF0D6B4E),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              f.isPhoto
                  ? Icons.photo_camera_rounded
                  : f.isQr
                      ? Icons.qr_code_2_rounded
                      : Icons.text_fields_rounded,
              size: (15 * uiScale).clamp(12.0, 16.0),
              color: isSelected ? Colors.cyan : Colors.grey,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                f.label,
                style: TextStyle(
                  fontSize: tileFontSize,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? Colors.cyan
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Front/Back inline side switch
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  width: 0.8,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        f.side = 'front';
                        _previewingFront = true;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: EdgeInsets.symmetric(horizontal: (5 * uiScale).clamp(4.0, 7.0), vertical: 2.5),
                      decoration: BoxDecoration(
                        color: f.side == 'front'
                            ? const Color(0xFF0D6B4E)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Front',
                        style: TextStyle(
                          fontSize: pillFontSize,
                          fontWeight: FontWeight.bold,
                          color: f.side == 'front' ? Colors.white : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        f.side = 'back';
                        _previewingFront = false;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: EdgeInsets.symmetric(horizontal: (5 * uiScale).clamp(4.0, 7.0), vertical: 2.5),
                      decoration: BoxDecoration(
                        color: f.side == 'back'
                            ? const Color(0xFF0D6B4E)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Back',
                        style: TextStyle(
                          fontSize: pillFontSize,
                          fontWeight: FontWeight.bold,
                          color: f.side == 'back' ? Colors.white : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.edit_rounded, size: 13, color: Colors.cyan),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Selected field properties editor ─────────────────
  Widget _buildSelectedFieldEditor(bool isDark) {
    final f = _fields[_selectedFieldKey!]!;
    final uiScale = _getUiScale(context);
    final labelFontSize = (10.5 * uiScale).clamp(8.5, 12.0);
    final pillFontSize = (9.5 * uiScale).clamp(7.5, 11.0);

    return Container(
      padding: EdgeInsets.all((10 * uiScale).clamp(6.0, 12.0)),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.cyan.withAlpha(10)
            : Colors.blue.shade50.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.cyan.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded,
                  size: (16 * uiScale).clamp(12.0, 18.0), color: Colors.cyan.shade300),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Editing: ${f.label}',
                    style: AppTheme.getFontStyle(
                        fontSize: (11.5 * uiScale).clamp(9.0, 13.0),
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.cyan : const Color(0xFF0D6B4E)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text('Card Side:', style: AppTheme.getFontStyle(fontSize: labelFontSize, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          f.side = 'front';
                          _previewingFront = true;
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: (8 * uiScale).clamp(5.0, 10.0), vertical: (3.5 * uiScale).clamp(2.0, 4.0)),
                        decoration: BoxDecoration(
                          color: f.side == 'front' ? const Color(0xFF0D6B4E) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Front',
                          style: TextStyle(
                            fontSize: pillFontSize,
                            fontWeight: FontWeight.bold,
                            color: f.side == 'front' ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          f.side = 'back';
                          _previewingFront = false;
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: (8 * uiScale).clamp(5.0, 10.0), vertical: (3.5 * uiScale).clamp(2.0, 4.0)),
                        decoration: BoxDecoration(
                          color: f.side == 'back' ? const Color(0xFF0D6B4E) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Back',
                          style: TextStyle(
                            fontSize: pillFontSize,
                            fontWeight: FontWeight.bold,
                            color: f.side == 'back' ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ─ Text editing (for text fields) ─
          if (!f.isPhoto && !f.isQr && !f.isSignature && !f.isStamp) ...[
            if (_selectedFieldKey == 'name') ...[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text('Name Format:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => f.isCombinedName = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: !f.isCombinedName ? const Color(0xFF0D6B4E) : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Only Name',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: !f.isCombinedName ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => f.isCombinedName = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: f.isCombinedName ? const Color(0xFF0D6B4E) : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Full Name',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: f.isCombinedName ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (_selectedFieldKey == 'address') ...[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text('Address Format:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => f.isCombinedAddress = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: !f.isCombinedAddress ? const Color(0xFF0D6B4E) : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Address Only',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: !f.isCombinedAddress ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => f.isCombinedAddress = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: f.isCombinedAddress ? const Color(0xFF0D6B4E) : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Full Address',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: f.isCombinedAddress ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            TextFormField(
              key: ValueKey('editor_text_$_selectedFieldKey'),
              initialValue: f.displayText,
              decoration: InputDecoration(
                labelText: 'Display Text',
                labelStyle: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                isDense: true,
              ),
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
              onChanged: (v) => setState(() => f.displayText = v),
            ),
            const SizedBox(height: 8),
            _buildSlider('Font Size', f.fontSize, 8, 24,
                (v) => setState(() => f.fontSize = v)),
            Row(
              children: [
                Text('Bold:',
                    style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
                const Spacer(),
                Switch(
                  value: f.bold,
                  activeColor: const Color(0xFF0D6B4E),
                  onChanged: (v) => setState(() => f.bold = v),
                ),
              ],
            ),
            _buildColorRow('Text Color', f.color,
                (c) => setState(() => f.color = c)),
            const SizedBox(height: 6),
            _buildSlider('Box Width (mm)', f.textWidthMm, 5.0, _cardWidthMm,
                (v) => setState(() => f.textWidthMm = v)),
            _buildSlider('Box Height (mm)', f.textHeightMm, 2.0, _cardHeightMm,
                (v) => setState(() => f.textHeightMm = v)),
          ],

          // ─ Photo size ─
          if (f.isPhoto) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text('Photo Shape:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => f.isRoundPhoto = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: !f.isRoundPhoto ? const Color(0xFF0D6B4E) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Rectangle',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: !f.isRoundPhoto ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => f.isRoundPhoto = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: f.isRoundPhoto ? const Color(0xFF0D6B4E) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Round',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: f.isRoundPhoto ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSlider('Photo Width', f.photoWidth, 30, 120,
                (v) => setState(() => f.photoWidth = v)),
            if (!f.isRoundPhoto)
              _buildSlider('Photo Height', f.photoHeight, 30, 150,
                  (v) => setState(() => f.photoHeight = v)),
          ],

          // ─ QR size & color ─
          if (f.isQr) ...[
            _buildSlider('QR Size', f.photoWidth, 30, 100, (v) {
              setState(() {
                f.photoWidth = v;
                f.photoHeight = v;
              });
            }),
            _buildColorRow('QR Color', f.color,
                (c) => setState(() => f.color = c)),
          ],

          // ─ Principal Signature ─
          if (f.isSignature) ...[
            _buildSlider('Width', f.photoWidth, 30, 150,
                (v) => setState(() => f.photoWidth = v)),
            _buildSlider('Height', f.photoHeight, 15, 100,
                (v) => setState(() => f.photoHeight = v)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                      );
                      if (result != null && result.files.single.path != null) {
                        setState(() {
                          _signatureFile = File(result.files.single.path!);
                        });
                      }
                    },
                    icon: const Icon(Icons.upload_file_rounded, size: 16),
                    label: Text(_signatureFile == null ? 'Upload Signature PNG' : 'Change Signature'),
                  ),
                ),
                if (_signatureFile != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_rounded, color: Colors.red),
                    onPressed: () => setState(() => _signatureFile = null),
                  ),
                ],
              ],
            ),
          ],

          // ─ Stamp ─
          if (f.isStamp) ...[
            _buildSlider('Width', f.photoWidth, 30, 150,
                (v) => setState(() => f.photoWidth = v)),
            _buildSlider('Height', f.photoHeight, 30, 150,
                (v) => setState(() => f.photoHeight = v)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                      );
                      if (result != null && result.files.single.path != null) {
                        setState(() {
                          _stampFile = File(result.files.single.path!);
                        });
                      }
                    },
                    icon: const Icon(Icons.upload_file_rounded, size: 16),
                    label: Text(_stampFile == null ? 'Upload Stamp PNG' : 'Change Stamp'),
                  ),
                ),
                if (_stampFile != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_rounded, color: Colors.red),
                    onPressed: () => setState(() => _stampFile = null),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 6),
          // Position sliders in mm
          _buildSlider('X Position (mm)', f.x * _cardWidthMm, 0.0, _cardWidthMm, (v) {
            setState(() => f.x = v / _cardWidthMm);
          }),
          _buildSlider('Y Position (mm)', f.y * _cardHeightMm, 0.0, _cardHeightMm, (v) {
            setState(() => f.y = v / _cardHeightMm);
          }),
        ],
      ),
    );
  }

  // ─── Dynamic UI scaling helper for Builder Page Controls ───
  double _getUiScale(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 600) return 1.0;
    return (w / 380.0).clamp(0.68, 1.0);
  }

  Widget _sectionTitle(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiScale = _getUiScale(context);
    return Text(
      text,
      style: AppTheme.getFontStyle(
        fontSize: (13.5 * uiScale).clamp(10.0, 15.0),
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    final isMmValue = label.contains('(mm)');
    double step = 1.0;
    if (label.contains('Position (mm)')) {
      step = 0.5; // 0.5 mm steps for precise positioning
    } else if (label.contains('Position')) {
      step = 0.01;
    }
    final val = value.clamp(min, max);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white70 : Colors.black87;
    final accentColor = const Color(0xFF0D6B4E);
    final valueTextColor = isDark ? const Color(0xFF00FFCC) : const Color(0xFF0D6B4E);
    final uiScale = _getUiScale(context);

    final labelFontSize = (10.5 * uiScale).clamp(8.5, 12.0);
    final inputWidth = (54 * uiScale).clamp(40.0, 62.0);
    final btnIconSize = (14 * uiScale).clamp(11.0, 16.0);
    final btnPadding = (5 * uiScale).clamp(3.0, 6.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: AppTheme.getFontStyle(
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Direct Editable Size Number Badge
              SizedBox(
                width: inputWidth,
                height: 22,
                child: TextFormField(
                  key: ValueKey('slider_edit_${label}_${val.toStringAsFixed(1)}'),
                  initialValue: isMmValue || label.contains('Position')
                      ? val.toStringAsFixed(1)
                      : val.toStringAsFixed(0),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: AppTheme.getFontStyle(
                    fontSize: (9.5 * uiScale).clamp(8.0, 11.0),
                    fontWeight: FontWeight.bold,
                    color: valueTextColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    filled: true,
                    fillColor: isDark
                        ? accentColor.withAlpha(40)
                        : accentColor.withAlpha(15),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(5),
                      borderSide: BorderSide(color: accentColor, width: 1.2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(5),
                      borderSide: BorderSide(
                        color: accentColor.withAlpha(60),
                        width: 0.8,
                      ),
                    ),
                  ),
                  onFieldSubmitted: (inputStr) {
                    final parsed = double.tryParse(inputStr);
                    if (parsed != null) {
                      onChanged(parsed.clamp(min, max));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              // PixelLab-style Minus Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    final nv = (val - step).clamp(min, max);
                    onChanged(nv);
                  },
                  child: Container(
                    padding: EdgeInsets.all(btnPadding),
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(30),
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withAlpha(60)),
                    ),
                    child: Icon(Icons.remove_rounded, size: btnIconSize, color: valueTextColor),
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2.5,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: (5.5 * uiScale).clamp(4.0, 7.0)),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: (10 * uiScale).clamp(7.0, 12.0)),
                    activeTrackColor: accentColor,
                    inactiveTrackColor: isDark ? Colors.white24 : Colors.grey.shade300,
                    thumbColor: valueTextColor,
                  ),
                  child: Slider(
                    value: val,
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ),
              // PixelLab-style Plus Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    final nv = (val + step).clamp(min, max);
                    onChanged(nv);
                  },
                  child: Container(
                    padding: EdgeInsets.all(btnPadding),
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(30),
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withAlpha(60)),
                    ),
                    child: Icon(Icons.add_rounded, size: btnIconSize, color: valueTextColor),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatePickerItem({
    required bool useTemplate,
    required File? templateFile,
    required VoidCallback onPick,
    required VoidCallback onRemove,
    required bool isDark,
  }) {
    if (useTemplate && templateFile != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.green.withAlpha(20) : Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withAlpha(60)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                templateFile.path.split(Platform.pathSeparator).last,
                style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16, color: Colors.red),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    } else {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.upload_file_rounded, size: 16),
          label: const Text('Upload Template Image', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      );
    }
  }

  Widget _buildColorRow(
      String label, Color current, ValueChanged<Color> onSelected) {
    final colors = [
      Colors.white,
      Colors.black,
      const Color(0xFF00FFCC),
      const Color(0xFF0D6B4E),
      const Color(0xFFFFD700),
      const Color(0xFF1B3B6F),
      const Color(0xFFF12711),
      const Color(0xFFF5AF19),
      const Color(0xFF9C27B0),
      const Color(0xFF00B0FF),
      Colors.white70,
      Colors.grey,
      Colors.brown.shade700,
      const Color(0xFF212121),
    ];

    final hexString = '#${current.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(label,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: colors.map((c) {
                      final sel = current.value == c.value;
                      return GestureDetector(
                        onTap: () => onSelected(c),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: sel ? Colors.cyan : Colors.grey.shade400,
                              width: sel ? 2.5 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Custom Hex Color Code input
          Padding(
            padding: const EdgeInsets.only(left: 80),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: current,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextFormField(
                      initialValue: hexString,
                      key: ValueKey(current), // Force rebuild on color change
                      decoration: InputDecoration(
                        hintText: '#00FFCC',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (val) {
                        try {
                          final cleanHex = val.replaceAll('#', '').trim();
                          if (cleanHex.length == 6) {
                            final parsed = int.parse('FF$cleanHex', radix: 16);
                            onSelected(Color(parsed));
                          } else if (cleanHex.length == 8) {
                            final parsed = int.parse(cleanHex, radix: 16);
                            onSelected(Color(parsed));
                          }
                        } catch (_) {}
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Main build ───────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;

    Widget bodyWidget;
    if (isWide) {
      bodyWidget = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left: Canvas ──
          Expanded(
            flex: 6,
            child: _buildCanvasArea(isDark),
          ),
          VerticalDivider(
              width: 1,
              color: isDark ? Colors.white10 : Colors.grey.shade300),
          // ── Right: Settings ──
          Expanded(
            flex: 4,
            child: Container(
              color: isDark
                  ? const Color(0xFF111122)
                  : Colors.white,
              child: _buildSettingsPanel(isDark),
            ),
          ),
        ],
      );
    } else {
      // ── PixelLab-style Mobile Editor Layout ──
      bodyWidget = Column(
        children: [
          // ── Canvas Area (takes max space) ──
          Expanded(child: _buildCanvasArea(isDark)),
          // ── Bottom Contextual Toolbar ──
          _buildMobileBottomToolbar(isDark),
        ],
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0A18) : Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: isWide ? null : 48,
        backgroundColor:
            isDark ? const Color(0xFF1A1A2E) : Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'ID Card Builder',
            style: AppTheme.getFontStyle(
                fontSize: isWide ? 17 : 14, fontWeight: FontWeight.bold),
          ),
        ),
        titleSpacing: isWide ? null : 0,
        actions: [
          if (_availableClasses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white24 : const Color(0xFF0D6B4E).withAlpha(40),
                    width: 1.0,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedClassFilter,
                    isDense: true,
                    alignment: Alignment.centerLeft,
                    icon: Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 18,
                      color: isDark ? const Color(0xFF00FFCC) : const Color(0xFF0D6B4E),
                    ),
                    style: TextStyle(
                      fontSize: (11.5 * _getUiScale(context)).clamp(9.5, 12.5),
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF00FFCC) : const Color(0xFF0D6B4E),
                    ),
                    dropdownColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    onChanged: (val) {
                      setState(() {
                        _selectedClassFilter = val;
                        final effective = _effectiveStudents;
                        if (effective.isNotEmpty) {
                          _updatePreviewStudent(effective.first);
                        }
                      });
                    },
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'All Classes (${_availablePool.length})',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      ..._availableClasses.map((cName) {
                        final cnt = _availablePool.where((s) => s.className == cName).length;
                        return DropdownMenuItem<String?>(
                          value: cName,
                          child: Text(
                            '$cName ($cnt)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          if (isWide) ...[
            TextButton.icon(
              onPressed: () => setState(() => _previewingFront = !_previewingFront),
              icon: Icon(
                _previewingFront ? Icons.flip_to_front_rounded : Icons.flip_to_back_rounded,
                size: 18,
                color: isDark ? const Color(0xFF00FFCC) : const Color(0xFF0D6B4E),
              ),
              label: Text(
                _previewingFront ? 'Front Side' : 'Back Side',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFF00FFCC) : const Color(0xFF0D6B4E),
                ),
              ),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _isPrinting ? null : _printCard,
              icon: _isPrinting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(
                _isPrinting ? 'Saving PDF...' : 'Save PDF',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D6B4E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reset All Fields',
              onPressed: () => setState(() {
                _initFields();
                _selectedFieldKey = null;
              }),
            ),
            const SizedBox(width: 8),
          ] else ...[
            IconButton(
              icon: Icon(
                _previewingFront ? Icons.flip_to_front_rounded : Icons.flip_to_back_rounded,
                size: 18,
                color: const Color(0xFF0D6B4E),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: _previewingFront ? 'Showing Front Side' : 'Showing Back Side',
              onPressed: () => setState(() => _previewingFront = !_previewingFront),
            ),
            IconButton(
              icon: Icon(Icons.print_rounded, size: 18,
                color: _isPrinting ? Colors.grey : const Color(0xFF0D6B4E)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Print PDF',
              onPressed: _isPrinting ? null : _printCard,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Reset',
              onPressed: () => setState(() {
                _initFields();
                _selectedFieldKey = null;
              }),
            ),
          ],
        ],
      ),
      body: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) {
            if (_selectedFieldKey == null) return;
            final f = _fields[_selectedFieldKey];
            if (f == null) return;

            final double stepX = 0.5 / _cardWidthMm;
            final double stepY = 0.5 / _cardHeightMm;

            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              setState(() {
                f.x = (f.x - stepX).clamp(0.0, 0.95);
              });
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              setState(() {
                f.x = (f.x + stepX).clamp(0.0, 0.95);
              });
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              setState(() {
                f.y = (f.y - stepY).clamp(0.0, 0.95);
              });
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              setState(() {
                f.y = (f.y + stepY).clamp(0.0, 0.95);
              });
            }
          }
        },
        child: bodyWidget,
      ),
    );
  }

  // ─── PixelLab-style bottom toolbar for mobile ─────────
  Widget _buildMobileBottomToolbar(bool isDark) {
    final barBg = isDark ? const Color(0xFF141428) : const Color(0xFFF0F0F0);
    final panelBg = isDark ? const Color(0xFF111122) : Colors.white;
    final accent = const Color(0xFF0D6B4E);
    final dimColor = isDark ? Colors.white54 : Colors.black54;

    String panelTitle = '';
    IconData panelIcon = Icons.tune_rounded;
    if (_currentMobileTabIndex == 1) {
      panelTitle = 'Fields / Layers';
      panelIcon = Icons.layers_rounded;
    } else if (_currentMobileTabIndex == 2) {
      panelTitle = 'Card Settings';
      panelIcon = Icons.tune_rounded;
    } else if (_currentMobileTabIndex == 3) {
      panelTitle = _selectedFieldKey != null 
          ? 'Element: ${_fields[_selectedFieldKey]?.label}' 
          : 'Text / Element Settings';
      panelIcon = Icons.text_format_rounded;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double iconSize = (constraints.maxWidth * 0.05).clamp(16.0, 20.0);
        final double iconPadding = (constraints.maxWidth * 0.015).clamp(6.0, 9.0);

        return Container(
          decoration: BoxDecoration(
            color: barBg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(40),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Expandable settings/fields panel ──
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: _currentMobileTabIndex == 0
                    ? const SizedBox.shrink()
                    : Container(
                        height: 160,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: panelBg,
                          border: Border(
                            top: BorderSide(
                              color: accent.withAlpha(40),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            // ── Panel drag handle & title ──
                            GestureDetector(
                              onTap: () => setState(() => _currentMobileTabIndex = 0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                color: isDark ? Colors.white.withAlpha(5) : Colors.black.withAlpha(5),
                                child: Row(
                                  children: [
                                    Icon(panelIcon, size: 15, color: accent),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          panelTitle,
                                          style: AppTheme.getFontStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: dimColor),
                                  ],
                                ),
                              ),
                            ),
                            Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                            // ── Panel content ──
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(10),
                                child: _currentMobileTabIndex == 1
                                    ? _buildFieldsTab(isDark)
                                    : _currentMobileTabIndex == 2
                                        ? _buildCardSettingsOnlyTab(isDark)
                                        : _buildTextSettingsOnlyTab(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              // ── Compact Icon-Only Strip (No Text Below Icons) ──
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 1. Layers / Fields
                      _buildToolbarIconOnly(Icons.layers_rounded, 1, iconSize, iconPadding, accent, dimColor, isDark),
                      // 2. Card Settings
                      _buildToolbarIconOnly(Icons.tune_rounded, 2, iconSize, iconPadding, accent, dimColor, isDark),
                      // 3. Text / Element Settings
                      _buildToolbarIconOnly(Icons.text_format_rounded, 3, iconSize, iconPadding, accent, dimColor, isDark),
                      // 4. Front / Back Toggle
                      _buildToolbarActionOnly(
                        _previewingFront ? Icons.flip_to_front_rounded : Icons.flip_to_back_rounded,
                        iconSize,
                        iconPadding,
                        accent,
                        isDark,
                        () => setState(() => _previewingFront = !_previewingFront),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbarIconOnly(IconData icon, int index, double iconSize, double padding, Color accent, Color dimColor, bool isDark) {
    final isActive = _currentMobileTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() {
        _currentMobileTabIndex = _currentMobileTabIndex == index ? 0 : index;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: isActive ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? accent : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: isActive ? Colors.white : dimColor,
        ),
      ),
    );
  }

  Widget _buildToolbarActionOnly(IconData icon, double iconSize, double padding, Color accent, bool isDark, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Icon(icon, size: iconSize, color: accent),
      ),
    );
  }

  Widget _buildCanvasArea(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0D0D17) : Colors.grey.shade200,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxW = (constraints.maxWidth - 24).clamp(50.0, 1200.0);
          final double maxH = (constraints.maxHeight - 24).clamp(50.0, 1200.0);

          final double cardRatio = _cardWidthMm / _cardHeightMm;
          
          double cw = maxW;
          double ch = cw / cardRatio;

          if (ch > maxH) {
            ch = maxH;
            cw = ch * cardRatio;
          }

          return Center(
            child: Container(
              width: cw,
              height: ch,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_borderRadius + 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_borderRadius),
                child: _buildCanvas(cw, ch),
              ),
            ),
          );
        },
      ),
    );
  }
}
