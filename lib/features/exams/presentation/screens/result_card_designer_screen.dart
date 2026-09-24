import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../students/data/models/student_model.dart';
import '../../../students/data/repositories/student_repository.dart';
import '../../../../core/network/api_client.dart';
import '../../data/models/exam_models.dart';
import '../../../../core/utils/grading_helper.dart';
import '../../../../core/utils/urdu_number_helper.dart';
import 'package:hijri/hijri_calendar.dart';

/// Mutable Config for Table Subject Rows (with own TextEditingControllers)
class _SubjectRowConfig {
  String id;
  String bookName;
  double maxMarks;
  double marksObtained;
  bool isAbsent;
  String gradeName;
  String minPass;
  int tableGroup;

  final TextEditingController bookNameCtrl;
  final TextEditingController maxMarksCtrl;
  final TextEditingController obtainedCtrl;
  final TextEditingController gradeCtrl;
  final TextEditingController minPassCtrl;

  _SubjectRowConfig({
    required this.id,
    required this.bookName,
    this.maxMarks = 100.0,
    this.marksObtained = 85.0,
    this.isAbsent = false,
    this.gradeName = 'اجود',
    this.minPass = '33',
    this.tableGroup = 1,
  })  : bookNameCtrl = TextEditingController(text: bookName),
        maxMarksCtrl = TextEditingController(text: maxMarks.toStringAsFixed(0)),
        obtainedCtrl = TextEditingController(text: marksObtained.toStringAsFixed(0)),
        gradeCtrl = TextEditingController(text: gradeName),
        minPassCtrl = TextEditingController(text: minPass);

  void dispose() {
    bookNameCtrl.dispose();
    maxMarksCtrl.dispose();
    obtainedCtrl.dispose();
    gradeCtrl.dispose();
    minPassCtrl.dispose();
  }
}

/// Column definition for dynamic table rendering
class _ColDef {
  final String key;
  final int flex;
  final String title;
  _ColDef(this.key, this.flex, this.title);
}

class ResultCardDesignerScreen extends StatefulWidget {
  final Student? student;
  final List<Student>? allStudents;
  final List<Map<String, dynamic>>? examResults;

  const ResultCardDesignerScreen({
    super.key,
    this.student,
    this.allStudents,
    this.examResults,
  });

  static void navigate(
    BuildContext context,
    Student student, {
    List<Student>? allStudents,
    List<Map<String, dynamic>>? examResults,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultCardDesignerScreen(
          student: student,
          allStudents: allStudents,
          examResults: examResults,
        ),
      ),
    );
  }

  @override
  State<ResultCardDesignerScreen> createState() =>
      _ResultCardDesignerScreenState();
}

class _FieldConfig {
  String id;
  String label;
  String titlePrefix;
  String rawValue;
  bool showTitlePrefix;
  double x;
  double y;
  double fontSize;
  String fontFamily;
  Color color;
  bool bold;
  bool visible;
  String side;
  bool isPhoto;
  bool isSignature;
  bool isStamp;
  bool isTable;
  bool isCustomText;
  bool isCombinedName;
  bool isCombinedAddress;
  bool showDivisionInClass;
  double widthMm;
  double heightMm;
  double photoWidth;
  double photoHeight;

  _FieldConfig({
    required this.id,
    required this.label,
    required this.titlePrefix,
    required this.rawValue,
    this.showTitlePrefix = true,
    required this.x,
    required this.y,
    this.fontSize = 11.0,
    this.fontFamily = 'Segoe UI',
    this.color = const Color(0xFF0F172A),
    this.bold = false,
    this.visible = true,
    this.side = 'front',
    this.isPhoto = false,
    this.isSignature = false,
    this.isStamp = false,
    this.isTable = false,
    this.isCustomText = false,
    this.isCombinedName = false,
    this.isCombinedAddress = false,
    this.showDivisionInClass = true,
    this.widthMm = 80.0,
    this.heightMm = 14.0,
    this.photoWidth = 60,
    this.photoHeight = 70,
  });

  String get displayText {
    if (!showTitlePrefix || titlePrefix.isEmpty) return rawValue;
    return '$titlePrefix$rawValue';
  }
}

class _ResultCardDesignerScreenState extends State<ResultCardDesignerScreen> {
  void _loadRealStudentsFromApi() async {
    try {
      final repo = StudentRepository(ApiClient());
      final studentsData = await repo.getAllStudents();
      if (studentsData.isNotEmpty && mounted) {
        setState(() {
          _studentsList = studentsData;
          _studentIndex = 0;
          _currentStudent = _studentsList[0];
          _updateFieldsForCurrentStudent();
        });
      }
    } catch (_) {}
  }
  late Student _currentStudent;
  late List<Student> _studentsList;
  int _studentIndex = 0;
  String? _selectedClassFilter;

  String _selectedPaperPreset = 'A4';
  double _pageWidthMm = 210.0;
  double _pageHeightMm = 297.0;
  bool _isLandscape = false;
  double _zoomScale = 1.0;
  final TransformationController _transformationController = TransformationController();

  double _borderRadius = 8.0;
  Color _pageBgColor = Colors.white;
  bool _isTransparentPageBg = false;
  Color _pageBorderColor = const Color(0xFF0F766E);
  double _pageBorderWidth = 2.5;
  bool _showGridOverlay = false;

  Color _headerBannerBg = const Color(0xFF0D6B4E);
  bool _isTransparentHeaderBg = false;

  File? _uploadedTemplateImageFront;
  File? _uploadedTemplateImageBack;
  bool _useUploadedTemplate = false;
  String _pdfPrintSide = 'both';

  // ─── Advanced Table Font & Typography Suite ───
  String _tableFontFamily = 'Segoe UI';
  String _tableUrduFontFamily = 'Jameel Noori Nastaleeq';
  double _tableScaleFactor = 100.0;

  String _cardLanguage = 'en';

  void _applyCardLanguage(String langCode) {
    _cardLanguage = langCode;

    final Map<String, Map<String, String>> langDict = {
      'ur': {
        'sub_header': 'سالانہ امتحان کا رزلٹ کارڈ',
        'name': 'طالب علم کا نام: ',
        'student_name': 'طالب علم کا نام: ',
        'full_name': 'طالب علم کا نام: ',
        'father': 'والد کا نام: ',
        'surname': 'خاندان: ',
        'class': 'جماعت: ',
        'total_students': 'کلاس کے کل طلباء: ',
        'gr_no': 'ایس. آر. نمبر: ',
        'dob': 'تاریخ پیدائش: ',
        'card_date': 'تاریخ: ',
        'card_hijri_date': 'مطابق: ',
        'address': 'پتہ: ',
        'full_address': 'مکمل پتہ: ',
        'mobile_no': 'موبائل نمبر: ',
        'total_marks': 'کل نمبر: ',
        'percentage': 'فیصد: ',
        'overall_grade': 'مجموعی گریڈ: ',
        'position_rank': 'مقام: ',
        'result_status': 'نتیجہ: ',
        'total_absent': 'کل غیر حاضر: ',
        'grading_scale_title': 'گریڈنگ پیمانہ',
        'footer_note': 'یہ ایک باضابطہ کمپیوٹرائزڈ رزلٹ کارڈ ہے۔',
        'col1': 'نمبر شمار',
        'col2': 'کتاب کا نام',
        'col3': 'کل نمبرات',
        'col4': 'کم نمبرات',
        'col5': 'حاصل نمبرات',
        'col6': 'گریڈ',
        'teacher_sign': 'استاد کے دستخط',
        'principal_sign': 'پرنسپل کے دستخط',
        'stamp': 'مہر',
        'grade_distinction': 'ممتاز',
        'grade_high': 'جید',
        'grade_average': 'مقبول',
        'grade_pass': 'پاس',
        'grade_fail': 'راسب',
      },
      'en': {
        'sub_header': 'OFFICIAL MARKSHEET',
        'name': 'Student name: ',
        'student_name': 'Student name: ',
        'full_name': 'Student name: ',
        'father': 'Father name: ',
        'surname': 'Surname: ',
        'class': 'Class: ',
        'total_students': 'Total class students: ',
        'gr_no': 'S.R. no.: ',
        'dob': 'Date of birth: ',
        'card_date': 'Date: ',
        'card_hijri_date': 'Hijri Date: ',
        'address': 'Address: ',
        'full_address': 'Full Address: ',
        'mobile_no': 'Mobile number: ',
        'total_marks': 'Total marks: ',
        'percentage': 'Percentage: ',
        'overall_grade': 'Overall grade: ',
        'position_rank': 'Rank: ',
        'result_status': 'Result: ',
        'total_absent': 'Total absent: ',
        'grading_scale_title': 'Grading scale',
        'footer_note': 'This is an official computer-generated Marksheet.',
        'col1': 'S.R. no.',
        'col2': 'Book name',
        'col3': 'Max mark',
        'col4': 'Min mark',
        'col5': 'Obtained mark',
        'col6': 'Grade',
        'teacher_sign': 'Teacher signature',
        'principal_sign': 'Principal signature',
        'stamp': 'Stamp',
        'grade_distinction': 'Distinction',
        'grade_high': 'High Marks',
        'grade_average': 'Average',
        'grade_pass': 'Pass',
        'grade_fail': 'Fail',
      },
      'hi': {
        'sub_header': 'वार्षिक परीक्षा परिणाम पत्र',
        'name': 'छात्र का नाम: ',
        'student_name': 'छात्र का नाम: ',
        'full_name': 'छात्र का नाम: ',
        'father': 'पिता का नाम: ',
        'surname': 'उपनाम: ',
        'class': 'कक्षा: ',
        'total_students': 'कक्षा के कुल छात्र: ',
        'gr_no': 'एस. आर. नं.: ',
        'dob': 'जन्म तिथि: ',
        'card_date': 'दिनांक: ',
        'card_hijri_date': 'हिजरी दिनांक: ',
        'address': 'पता: ',
        'full_address': 'पूरा पता: ',
        'mobile_no': 'मोबाइल नंबर: ',
        'total_marks': 'कुल अंक: ',
        'percentage': 'प्रतिशत: ',
        'overall_grade': 'कुल ग्रेड: ',
        'position_rank': 'स्थान: ',
        'result_status': 'परिणाम: ',
        'total_absent': 'कुल अनुपस्थित: ',
        'grading_scale_title': 'ग्रेडिंग पैमाना',
        'footer_note': 'यह एक आधिकारिक कंप्यूटरीकृत परिणाम पत्र है।',
        'col1': 'एस. आर. नं.',
        'col2': 'पुस्तक का नाम',
        'col3': 'अधिकतम अंक',
        'col4': 'न्यूनतम अंक',
        'col5': 'प्राप्तांक',
        'col6': 'ग्रेड',
        'teacher_sign': 'शिक्षक के हस्ताक्षर',
        'principal_sign': 'प्रधानाचार्य के हस्ताक्षर',
        'stamp': 'मोहर',
        'grade_distinction': 'विशेष योग्यता',
        'grade_high': 'प्रथम श्रेणी',
        'grade_average': 'द्वितीय श्रेणी',
        'grade_pass': 'उत्तीर्ण',
        'grade_fail': 'अनुत्तीर्ण',
      },
      'gu': {
        'sub_header': 'વાર્ષિક પરીક્ષા પરિણામ પત્રક',
        'name': 'વિદ્યાર્થીનું નામ: ',
        'student_name': 'વિદ્યાર્થીનું નામ: ',
        'full_name': 'વિદ્યાર્થીનું નામ: ',
        'father': 'પિતાનું નામ: ',
        'surname': 'અટક: ',
        'class': 'ધોરણ: ',
        'total_students': 'વર્ગના કુલ વિદ્યાર્થીઓ: ',
        'gr_no': 'એસ. આર. નંબર: ',
        'dob': 'જન્મ તારીખ: ',
        'card_date': 'તારીખ: ',
        'card_hijri_date': 'હિજરી તારીખ: ',
        'address': 'સરનામું: ',
        'full_address': 'સંપૂર્ણ સરનામું: ',
        'mobile_no': 'મોબાઈલ નંબર: ',
        'total_marks': 'કુલ ગુણ: ',
        'percentage': 'ટકાવારી: ',
        'overall_grade': 'એકંદર ગ્રેડ: ',
        'position_rank': 'ક્રમ: ',
        'result_status': 'પરિણામ: ',
        'total_absent': 'કુલ ગેરહાજર: ',
        'grading_scale_title': 'ગ્રેડિંગ સ્કેલ',
        'footer_note': 'આ એક સત્તાવાર કમ્પ્યુટર જનરેટ કરેલ પરિણામ પત્રક છે.',
        'col1': 'એસ. આર. નંબર',
        'col2': 'પુસ્તકનું નામ',
        'col3': 'મહત્તમ ગુણ',
        'col4': 'ન્યૂનતમ ગુણ',
        'col5': 'મેળવેલ ગુણ',
        'col6': 'ગ્રેડ',
        'teacher_sign': 'શિક્ષકની સહી',
        'principal_sign': 'આચાર્યની સહી',
        'stamp': 'સિક્કો',
        'grade_distinction': 'વિશિષ્ટતા',
        'grade_high': 'પ્રથમ વર્ગ',
        'grade_average': 'દ્વિતીય વર્ગ',
        'grade_pass': 'ઉત્તીર્ણ',
        'grade_fail': 'અનુત્તીર્ણ',
      },
      'ar': {
        'sub_header': 'بطاقة نتائج الامتحان السنوي',
        'name': 'اسم الطالب: ',
        'student_name': 'اسم الطالب: ',
        'full_name': 'اسم الطالب: ',
        'father': 'اسم الأب: ',
        'surname': 'اللقب: ',
        'class': 'الصف: ',
        'total_students': 'إجمالي طالب الفصل: ',
        'gr_no': 'الرقم التسلسلي: ',
        'dob': 'تاريخ الميلاد: ',
        'card_date': 'التاريخ: ',
        'card_hijri_date': 'الموافق: ',
        'address': 'العنوان: ',
        'full_address': 'العنوان الكامل: ',
        'mobile_no': 'رقم الهاتف المحمول: ',
        'total_marks': 'المجموع الكلي: ',
        'percentage': 'النسبة المئوية: ',
        'overall_grade': 'التقدير العام: ',
        'position_rank': 'المرتبة: ',
        'result_status': 'النتيجة: ',
        'total_absent': 'إجمالي الغائبين: ',
        'grading_scale_title': 'مقياس الدرجات',
        'footer_note': 'هذا كشف درجات إلكتروني رسمي.',
        'col1': 'الرقم التسلسلي',
        'col2': 'اسم الكتاب',
        'col3': 'الحد الأقصى للدرجات',
        'col4': 'الحد الأدنى للدرجات',
        'col5': 'الدرجات المحصلة',
        'col6': 'الدرجة',
        'teacher_sign': 'توقيع المعلم',
        'principal_sign': 'توقيع المدير',
        'stamp': 'الختم',
        'grade_distinction': 'ممتاز',
        'grade_high': 'جيد جداً',
        'grade_average': 'مقبول',
        'grade_pass': 'ناجح',
        'grade_fail': 'راسب',
      },
      'bn': {
        'sub_header': 'বার্ষিক পরীক্ষার ফলাফল কার্ড',
        'name': 'শিক্ষার্থীর নাম: ',
        'student_name': 'শিক্ষার্থীর নাম: ',
        'full_name': 'শিক্ষার্থীর নাম: ',
        'father': 'বাবার নাম: ',
        'surname': 'পদবী: ',
        'class': 'শ্রেণী: ',
        'total_students': 'শ্রেণীর মোট শিক্ষার্থী: ',
        'gr_no': 'এস. আর. নম্বর: ',
        'dob': 'জন্ম তারিখ: ',
        'card_date': 'তারিখ: ',
        'card_hijri_date': 'হিজরী তারিখ: ',
        'address': 'ঠিকানা: ',
        'full_address': 'সম্পূর্ণ ঠিকানা: ',
        'mobile_no': 'মোবাইল নম্বর: ',
        'total_marks': 'মোট নম্বর: ',
        'percentage': 'শতকরা: ',
        'overall_grade': 'সামগ্রিক গ্রেড: ',
        'position_rank': 'র‍্যাঙ্ক: ',
        'result_status': 'ফলাফল: ',
        'total_absent': 'মোট অনুপস্থিত: ',
        'grading_scale_title': 'গ্রেডিং স্কেল',
        'footer_note': 'এটি একটি সরকারি কম্পিউটারাইজড রেজাল্ট কার্ড।',
        'col1': 'এস. আর. নম্বর',
        'col2': 'বইয়ের নাম',
        'col3': 'সর্বোচ্চ নম্বর',
        'col4': 'সর্বনিম্ন নম্বর',
        'col5': 'প্রাপ্ত নম্বর',
        'col6': 'গ্রেড',
        'teacher_sign': 'শিক্ষকের স্বাক্ষর',
        'principal_sign': 'প্রধান শিক্ষকের স্বাক্ষর',
        'stamp': 'সীল',
        'grade_distinction': 'কৃতিত্ব',
        'grade_high': 'উচ্চ নম্বর',
        'grade_average': 'সাধারণ',
        'grade_pass': 'পাস',
        'grade_fail': 'ফেল',
      },
    };

    final dict = langDict[langCode] ?? langDict['en']!;

    for (final key in [
      'name', 'father', 'surname', 'class', 'total_students', 'gr_no', 'dob', 'address',
      'total_marks', 'percentage', 'overall_grade', 'position_rank',
      'result_status', 'total_absent', 'grading_scale_title', 'footer_note', 'mobile_no',
      'teacher_sign', 'principal_sign', 'stamp', 'sub_header', 'card_date', 'card_hijri_date'
    ]) {
      if (_fieldsMap.containsKey(key) && dict.containsKey(key)) {
        _fieldsMap[key]!.titlePrefix = dict[key]!;
        if (key == 'grading_scale_title' || key == 'sub_header' || key == 'footer_note' || key == 'teacher_sign' || key == 'principal_sign' || key == 'stamp') {
          _fieldsMap[key]!.rawValue = dict[key]!;
        }
      }
    }

    // Use full_name / full_address prefix when combined mode is ON
    if (_fieldsMap.containsKey('name') && (_fieldsMap['name']!.isCombinedName) && dict.containsKey('full_name')) {
      _fieldsMap['name']!.titlePrefix = dict['full_name']!;
    }
    if (_fieldsMap.containsKey('address') && (_fieldsMap['address']!.isCombinedAddress) && dict.containsKey('full_address')) {
      _fieldsMap['address']!.titlePrefix = dict['full_address']!;
    }

    if (dict.containsKey('grade_distinction')) {
      _distinctionLabel = dict['grade_distinction']!;
      _distinctionLabelCtrl.text = dict['grade_distinction']!;
    }
    if (dict.containsKey('grade_high')) {
      _highMarkLabel = dict['grade_high']!;
      _highMarkLabelCtrl.text = dict['grade_high']!;
    }
    if (dict.containsKey('grade_average')) {
      _averageMarkLabel = dict['grade_average']!;
      _averageMarkLabelCtrl.text = dict['grade_average']!;
    }
    if (dict.containsKey('grade_pass')) {
      _passMarkLabel = dict['grade_pass']!;
      _passMarkLabelCtrl.text = dict['grade_pass']!;
    }
    if (dict.containsKey('grade_fail')) {
      _failMarkLabel = dict['grade_fail']!;
      _failMarkLabelCtrl.text = dict['grade_fail']!;
    }



    if (langCode == 'ur') {
      _tableFontFamily = 'Jameel Noori Nastaleeq';
      _tableUrduFontFamily = 'Jameel Noori Nastaleeq';
      for (final colKey in ['col1', 'col2', 'col3', 'col4', 'col5', 'col6']) {
        _colFontFamily[colKey] = 'Jameel Noori Nastaleeq';
      }
      for (final f in _fieldsMap.values) {
        f.fontFamily = 'Jameel Noori Nastaleeq';
        if (!f.isTable && !f.isPhoto && !f.isSignature && !f.isStamp && f.id != 'bismillah' && f.id != 'institution') {
          f.fontSize = 16.0;
        }
      }
    }

    if (_fieldsMap.containsKey('sub_header') && dict.containsKey('sub_header')) {
      _fieldsMap['sub_header']!.rawValue = dict['sub_header']!;
    }

    for (final colKey in ['col1', 'col2', 'col3', 'col4', 'col5', 'col6']) {
      final headerKey = 'table_header_$colKey';
      if (_fieldsMap.containsKey(headerKey) && dict.containsKey(colKey)) {
        _fieldsMap[headerKey]!.rawValue = dict[colKey]!;
      }
      if (_colTitleCtrls.containsKey(colKey) && dict.containsKey(colKey)) {
        _colTitleCtrls[colKey]?.text = dict[colKey]!;
      }
    }

    _lastBoundFieldId = null;
    _updateStudentFieldsData();
  }

  double get _tableWidthMm => _fieldsMap['marks_table']?.widthMm ?? 190.0;
  set _tableWidthMm(double val) {
    if (_fieldsMap.containsKey('marks_table')) {
      _fieldsMap['marks_table']!.widthMm = val;
    }
  }

  double get _tableHeightMm => _fieldsMap['marks_table']?.heightMm ?? 80.0;
  set _tableHeightMm(double val) {
    if (_fieldsMap.containsKey('marks_table')) {
      _fieldsMap['marks_table']!.heightMm = val;
    }
  }

  void _fitBoxToText(String fieldId) {
    final f = _fieldsMap[fieldId];
    if (f == null) return;
    final txt = f.displayText;
    if (txt.isEmpty) return;

    final textStyle = TextStyle(
      fontSize: f.fontSize,
      fontFamily: f.fontFamily,
      fontWeight: f.bold ? FontWeight.bold : FontWeight.normal,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: txt, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final double widthPx = textPainter.width + 16.0;
    final double heightPx = textPainter.height + 8.0;

    final double widthMm = (widthPx * 0.352778).clamp(15.0, _pageWidthMm);
    final double heightMm = (heightPx * 0.352778).clamp(6.0, _pageHeightMm);

    setState(() {
      f.widthMm = double.parse(widthMm.toStringAsFixed(1));
      f.heightMm = double.parse(heightMm.toStringAsFixed(1));
    });
  }

  void _matchTable2SizeWithTable1() {
    setState(() {
      final t1 = _fieldsMap['marks_table'];
      final t2 = _fieldsMap['marks_table_2'];
      if (t1 != null && t2 != null) {
        t2.widthMm = t1.widthMm;
        t2.heightMm = t1.heightMm;
      }
      _colCustomFlexTable2 = Map<String, double>.from(_colCustomFlex);
    });
  }

  void _onTableScaleChanged(double newScalePercent) {
    final ratio = newScalePercent / _tableScaleFactor;
    if (ratio <= 0 || ratio.isNaN) return;
    setState(() {
      _tableScaleFactor = newScalePercent;
      _tableHeaderFontSize = (_tableHeaderFontSize * ratio).clamp(6.0, 32.0);
      _tableCol1FontSize = (_tableCol1FontSize * ratio).clamp(6.0, 32.0);
      _bookNameFontSize = (_bookNameFontSize * ratio).clamp(6.0, 32.0);
      _col3FontSize = (_col3FontSize * ratio).clamp(6.0, 32.0);
      _col4FontSize = (_col4FontSize * ratio).clamp(6.0, 32.0);
      _tableObtainedFontSize = (_tableObtainedFontSize * ratio).clamp(6.0, 32.0);
      _tableGradeFontSize = (_tableGradeFontSize * ratio).clamp(6.0, 32.0);
      _tableRowFontSize = (_tableRowFontSize * ratio).clamp(6.0, 32.0);
      _rowSpacing = (_rowSpacing * ratio).clamp(1.0, 25.0);
      _colPadding = (_colPadding * ratio).clamp(1.0, 20.0);
    });
  }
  File? _uploadedStudentPhoto;
  File? _uploadedTeacherSignature;
  File? _uploadedPrincipalSignature;
  File? _uploadedPrincipalStamp;

  bool _convertGrNoDigits = false;

  final Map<String, double> _colCustomFlex = {
    'col1': 1.0,
    'col2': 3.0,
    'col3': 1.5,
    'col4': 1.5,
    'col5': 1.8,
    'col6': 1.8,
  };

  Map<String, double> _colCustomFlexTable2 = {
    'col1': 1.0,
    'col2': 3.0,
    'col3': 1.5,
    'col4': 1.5,
    'col5': 1.8,
    'col6': 1.8,
  };

  Map<int, double> _rowCustomSpacing = {};

  String? _selectedTableColKey = 'col2';
  Map<String, String> _colAlignment = {
    'col1': 'center',
    'col2': 'center', // Book Name default to Center as requested!
    'col3': 'center',
    'col4': 'center',
    'col5': 'center',
    'col6': 'center',
  };

  TextAlign _getColTextAlign(String colKey) {
    final alignStr = _colAlignment[colKey] ?? 'center';
    if (alignStr == 'left') return TextAlign.left;
    if (alignStr == 'right') return TextAlign.right;
    return TextAlign.center;
  }

  double _tableHeaderFontSize = 12.0;
  bool _tableHeaderBold = true;
  double _tableCol1FontSize = 11.0;    // S.R. (#)
  double _bookNameFontSize = 11.0;      // Book Name
  bool _bookNameBold = true;
  double _col3FontSize = 11.0;          // Column 3 (Max Marks)
  bool _col3Bold = false;
  double _col4FontSize = 11.0;          // Column 4 (Min Pass)
  bool _col4Bold = false;
  double _tableObtainedFontSize = 11.5; // Column 5 (Obtained)
  bool _tableObtainedBold = true;
  double _tableGradeFontSize = 11.5;    // Column 6 (Grade)
  bool _tableGradeBold = true;
  double _tableRowFontSize = 11.0;

  double _rowSpacing = 2.0;            // Vertical Row Padding (compact)
  double _colPadding = 2.5;            // Horizontal Cell Padding (compact)
  double _tableGridWidth = 0.0;        // Grid border thickness
  bool _enableSecondTable = false;     // Multi-table mode
  bool _showTableTotalRow = true;      // Show Total Mizan (کل میزان) row
  bool _enableSnapToGrid = true;       // Snap objects to grid lines and objects
  double _gridSpacingMm = 10.0;        // Grid density / spacing in mm (e.g. 5mm, 10mm, 20mm)
  int _mobileActiveTab = 0;           // 0: Designer Canvas, 1: Settings Panel
  int _selectedTabIndex = 0;          // Tablet/Desktop active section index
  bool _isBottomPanelExpanded = false; // Tablet Staff-ID-Card style bottom drawer expansion
  double _bottomPanelRatio = 0.50;    // Draggable bottom sheet height ratio (0.07 to 0.85)

  Color _tableHeaderBg = const Color(0xFF0D6B4E);
  bool _isTransparentTableHeader = false;

  bool _isTransparentRowBg = false;
  Color _alternatingRowBgColor = const Color(0xFFF8FAFC);

  // ─── Table Text Colors ───
  Color _tableHeaderTextColor = Colors.white;
  Color _bookNameTextColor = const Color(0xFF0F172A);
  Color _tableRowTextColor = const Color(0xFF0F172A);
  Color _col3TextColor = const Color(0xFF0F172A);
  Color _col4TextColor = const Color(0xFF0F172A);
  Color _tableMarksTextColor = const Color(0xFF0F172A);
  Color _tableGradeTextColor = const Color(0xFF0F766E);
  Color _tableGridColor = const Color(0xFFCBD5E1);

  final TextEditingController _fieldTextCtrl = TextEditingController();
  final TextEditingController _titlePrefixCtrl = TextEditingController();
  final TextEditingController _fieldHexCtrl = TextEditingController();
  String? _lastBoundFieldId;

  // ─── Date & Hijri Date Suite ───
  DateTime _customCardDate = DateTime.now();
  bool _showHijriDate = true;
  int _hijriOffsetDays = 0;
  String _manualHijriOverrideText = '';
  final TextEditingController _hijriTextCtrl = TextEditingController();

  // ─── Table Color & Section Customization State ───
  Color _table1OddRowBgColor = Colors.white;
  Color _totalRowBgColor = const Color(0xFFE2E8F0);
  Color _totalRowTextColor = const Color(0xFF0F172A);

  Color _table2HeaderBg = const Color(0xFF0D6B4E);
  Color _table2HeaderTextColor = Colors.white;
  Color _table2OddRowBgColor = Colors.white;
  Color _table2OddRowTextColor = const Color(0xFF0F172A);
  Color _table2EvenRowBgColor = const Color(0xFFF8FAFC);
  Color _table2EvenRowTextColor = const Color(0xFF0F172A);
  Color _table2TotalRowBgColor = const Color(0xFFE2E8F0);
  Color _table2TotalRowTextColor = const Color(0xFF0F172A);

  Color _table2GridColor = const Color(0xFFCBD5E1);
  double _table2GridWidth = 1.0;

  Color _table1HeaderBorderColor = const Color(0xFF0F766E);
  double _table1HeaderBorderWidth = 1.0;
  Color _table1TotalBorderColor = const Color(0xFFCBD5E1);
  double _table1TotalBorderWidth = 1.5;

  Color _table2HeaderBorderColor = const Color(0xFF0F766E);
  double _table2HeaderBorderWidth = 1.0;
  Color _table2TotalBorderColor = const Color(0xFFCBD5E1);
  double _table2TotalBorderWidth = 1.5;

  String _table1HeaderBorderSide = 'bottom';
  String _table1RowsBorderSide = 'bottom';
  String _table1TotalBorderSide = 'top';
  String _table1OuterBorderSide = 'all';

  Color _table1OuterBorderColor = const Color(0xFFCBD5E1);
  double _table1OuterBorderWidth = 1.0;
  double _table1CornerRadius = 6.0;
  Color _table1BgColor = Colors.transparent;

  String _table2HeaderBorderSide = 'bottom';
  String _table2RowsBorderSide = 'bottom';
  String _table2TotalBorderSide = 'top';
  String _table2OuterBorderSide = 'all';

  Color _table2OuterBorderColor = const Color(0xFFCBD5E1);
  double _table2OuterBorderWidth = 1.0;
  double _table2CornerRadius = 6.0;
  Color _table2BgColor = Colors.transparent;

  Border? _buildSectionBorder({
    required String borderSide,
    required Color color,
    required double width,
  }) {
    if (width <= 0.0 || borderSide == 'none') return null;

    final side = BorderSide(color: color, width: width);

    switch (borderSide) {
      case 'all':
        return Border.all(color: color, width: width);
      case 'top':
        return Border(top: side);
      case 'bottom':
        return Border(bottom: side);
      case 'left':
        return Border(left: side);
      case 'right':
        return Border(right: side);
      case 'horizontal':
        return Border(top: side, bottom: side);
      case 'vertical':
        return Border(left: side, right: side);
      default:
        return Border(bottom: side);
    }
  }

  int _selectedTableForColor = 1; // 1 = Table 1, 2 = Table 2
  String _selectedTableSection = 'header'; // 'header', 'rows', 'total', 'page'

  String _buildFormattedDateText() {
    final d = _customCardDate;
    final day = d.day.toString();
    final year = d.year.toString();

    final urduMonths = ['جنوری', 'فروری', 'مارچ', 'اپریل', 'مئی', 'جون', 'جولائی', 'اگست', 'ستمبر', 'اکتوبر', 'نومبر', 'دسمبر'];
    final enMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final hiMonths = ['जनवरी', 'फरवरी', 'मार्च', 'अप्रैल', 'मई', 'जून', 'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर'];
    final guMonths = ['જાન્યુઆરી', 'ફેબ્રુઆરી', 'માર્ચ', 'એપ્રિલ', 'મે', 'જૂન', 'જુલાઈ', 'ઑગસ્ટ', 'સપ્ટેમ્બર', 'ઑક્ટોબર', 'નવેમ્બર', 'ડિસેમ્બર'];
    final arMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    final bnMonths = ['জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'];

    String gregStr;
    if (_cardLanguage == 'ur') {
      gregStr = '$day ${urduMonths[d.month - 1]} $yearء';
    } else if (_cardLanguage == 'ar') {
      gregStr = '$day ${arMonths[d.month - 1]} $year م';
    } else if (_cardLanguage == 'hi') {
      gregStr = '$day ${hiMonths[d.month - 1]} $year';
    } else if (_cardLanguage == 'gu') {
      gregStr = '$day ${guMonths[d.month - 1]} $year';
    } else if (_cardLanguage == 'bn') {
      gregStr = '$day ${bnMonths[d.month - 1]} $year';
    } else {
      gregStr = '$day ${enMonths[d.month - 1]} $year';
    }

    return UrduNumberHelper.convertDigits(gregStr, _cardLanguage);
  }

  String _buildFormattedHijriDateText() {
    if (_manualHijriOverrideText.trim().isNotEmpty) {
      return UrduNumberHelper.convertDigits(_manualHijriOverrideText.trim(), _cardLanguage);
    }

    final d = _customCardDate;
    final adjusted = d.add(Duration(days: _hijriOffsetDays));
    final h = HijriCalendar.fromDate(adjusted);

    final urduHijriMonths = ['محرم الحرام', 'صفر المظفر', 'ربیع الاول', 'ربیع الثاني', 'جمادی الاولیٰ', 'جمادی الثانية', 'رجب المرجب', 'شعبان المعظم', 'رمضان المبارک', 'شوال المکرم', 'ذوالقعدة', 'ذوالحجة'];
    final enHijriMonths = ['Muharram', 'Safar', 'Rabi al-Awwal', 'Rabi al-Thani', 'Jumada al-Awwal', 'Jumada al-Thani', 'Rajab', 'Sha\'ban', 'Ramadan', 'Shawwal', 'Dhu al-Qi\'dah', 'Dhu al-Hijjah'];
    final arHijriMonths = ['محرم', 'صفر', 'ربيع الأول', 'ربيع الثاني', 'جمادى الأولى', 'جمادى الثانية', 'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'];
    final hiHijriMonths = ['मुहर्रम', 'सफर', 'रबी उल-अव्वल', 'रबी उस्सानी', 'जमादी उल-अव्वल', 'जमादी उस्सानी', 'रजब', 'शाबान', 'रमजान', 'शव्वल', 'ज़ुल-क़ादा', 'ज़ुल-हिज्जा'];
    final guHijriMonths = ['મોહર્રમ', 'સફર', 'રબી ઉલ-અવ્વલ', 'રબી ઉસ્સાની', 'જમાદી ઉલ-અવ્વલ', 'જમાદી ઉસ્સાની', 'રજબ', 'શાબાન', 'રમઝાન', 'શવ્વાલ', 'ઝુલ-કાદા', 'ઝુલ-હિજ્જા'];
    final bnHijriMonths = ['মুহাররাম', 'সফর', 'রবিউল আউয়াল', 'রবিউস সানি', 'জুমাদাল আউয়াল', 'জুমাদাউস সানি', 'রজব', 'শা\'বান', 'রমজান', 'শাওয়াল', 'জিলকদ', 'জিলহজ্জ'];

    final idx = (h.hMonth >= 1 && h.hMonth <= 12) ? h.hMonth - 1 : 0;
    String hijriStr;

    if (_cardLanguage == 'ur') {
      hijriStr = '${h.hDay} ${urduHijriMonths[idx]} ${h.hYear}ھـ';
    } else if (_cardLanguage == 'ar') {
      hijriStr = '${h.hDay} ${arHijriMonths[idx]} ${h.hYear} هـ';
    } else if (_cardLanguage == 'hi') {
      hijriStr = '${h.hDay} ${hiHijriMonths[idx]} ${h.hYear} हिजरी';
    } else if (_cardLanguage == 'gu') {
      hijriStr = '${h.hDay} ${guHijriMonths[idx]} ${h.hYear} હીજરી';
    } else if (_cardLanguage == 'bn') {
      hijriStr = '${h.hDay} ${bnHijriMonths[idx]} ${h.hYear} হিজরী';
    } else {
      hijriStr = '${h.hDay} ${enHijriMonths[idx]} ${h.hYear} AH';
    }

    return UrduNumberHelper.convertDigits(hijriStr, _cardLanguage);
  }

  void _updateCardDateFieldValue() {
    final formattedGreg = _buildFormattedDateText();
    final formattedHijri = _buildFormattedHijriDateText();

    if (_fieldsMap.containsKey('card_date')) {
      _fieldsMap['card_date']!.rawValue = formattedGreg;
      _fitBoxToText('card_date');
    }
    if (_fieldsMap.containsKey('card_hijri_date')) {
      _fieldsMap['card_hijri_date']!.rawValue = formattedHijri;
      _fieldsMap['card_hijri_date']!.visible = _showHijriDate;
      _fitBoxToText('card_hijri_date');
    }

    if (_selectedFieldId == 'card_date') {
      _fieldTextCtrl.text = formattedGreg;
    } else if (_selectedFieldId == 'card_hijri_date') {
      _fieldTextCtrl.text = formattedHijri;
    }
  }

  // ─── Dynamic / Conditional Color Rules ───
  bool _enableConditionalColors = true;
  List<GradingRule> _configuredGradingRules = [];

  Future<void> _loadConfiguredGradingRules() async {
    try {
      final rules = await GradingHelper.getRules();
      if (!mounted) return;
      setState(() {
        _configuredGradingRules = rules;
        _updateGradingScaleFieldValue();
        _updateStudentFieldsData();
      });
    } catch (_) {}
  }

  void _updateGradingScaleFieldValue() {
    final scaleText = _buildGradingScaleText();
    if (_fieldsMap.containsKey('grading_scale_title')) {
      _fieldsMap['grading_scale_title']!.rawValue = scaleText;
      if (_selectedFieldId == 'grading_scale_title') {
        _fieldTextCtrl.text = scaleText;
      }
    }
  }

  String _buildGradingScaleText() {
    final buffer = StringBuffer("Grading Scale / درجہ بندی:\n");
    final rules = _configuredGradingRules.isNotEmpty ? _configuredGradingRules : GradingHelper.defaultRules;
    for (final r in rules) {
      final minStr = r.minPercent % 1 == 0 ? r.minPercent.toInt().toString() : r.minPercent.toStringAsFixed(1);
      final maxStr = r.maxPercent % 1 == 0 ? r.maxPercent.toInt().toString() : r.maxPercent.toStringAsFixed(1);
      final gradeLabel = r.grade.padRight(4);
      if (r.minPercent == 0 && r.maxPercent < 33) {
        buffer.writeln("$gradeLabel : Fail (< 33%)");
      } else {
        buffer.writeln("$gradeLabel : \u2066$minStr%\u2069 – \u2066$maxStr%\u2069");
      }
    }
    return buffer.toString().trim();
  }

  double _distinctionThreshold = 90.0;
  double _highMarkThreshold = 75.0;
  double _averageMarkThreshold = 50.0;
  double _passMarkThreshold = 33.0;

  final TextEditingController _distinctionThresholdCtrl = TextEditingController(text: '90');
  final TextEditingController _highMarkThresholdCtrl = TextEditingController(text: '75');
  final TextEditingController _averageMarkThresholdCtrl = TextEditingController(text: '50');
  final TextEditingController _passMarkThresholdCtrl = TextEditingController(text: '33');

  String _distinctionLabel = 'Distinction';
  String _highMarkLabel = 'High Marks';
  String _averageMarkLabel = 'Average';
  String _passMarkLabel = 'Pass';
  String _failMarkLabel = 'Fail';

  final TextEditingController _distinctionLabelCtrl = TextEditingController(text: 'Distinction');
  final TextEditingController _highMarkLabelCtrl = TextEditingController(text: 'High Marks');
  final TextEditingController _averageMarkLabelCtrl = TextEditingController(text: 'Average');
  final TextEditingController _passMarkLabelCtrl = TextEditingController(text: 'Pass');
  final TextEditingController _failMarkLabelCtrl = TextEditingController(text: 'Fail');

  Color _distinctionMarkColor = const Color(0xFF10B981); // >= 90% (Emerald)
  Color _highMarkColor = const Color(0xFF0284C7);        // >= 75% (Sky Blue)
  Color _averageMarkColor = const Color(0xFF0F172A);     // >= 50% (Dark Slate)
  Color _lowMarkColor = const Color(0xFFD97706);         // >= 33% (Amber)
  Color _failMarkColor = const Color(0xFFEF4444);        // < 33% / ABSENT (Red)

  // ─── Group / Ungroup Table Columns State ───
  bool _isTableGrouped = true;
  String? _selectedColKey;

  final Map<String, double> _colX = {
    'col1': 0.035, // # S.R.
    'col2': 0.135, // Subject / Book Name
    'col3': 0.505, // Max Marks
    'col4': 0.655, // Min Pass
    'col5': 0.785, // Obtained Marks
    'col6': 0.915, // Grade
  };

  final Map<String, double> _colY = {
    'col1': 0.245,
    'col2': 0.245,
    'col3': 0.245,
    'col4': 0.245,
    'col5': 0.245,
    'col6': 0.245,
  };

  final Map<String, double> _colWidthMm = {
    'col1': 20.0,
    'col2': 75.0,
    'col3': 30.0,
    'col4': 30.0,
    'col5': 35.0,
    'col6': 30.0,
  };

  // ─── Per-Column Font Families ───
  final Map<String, String> _colFontFamily = {
    'col1': 'Segoe UI',
    'col2': 'Jameel Noori Nastaleeq',
    'col3': 'Segoe UI',
    'col4': 'Segoe UI',
    'col5': 'Segoe UI',
    'col6': 'Jameel Noori Nastaleeq',
  };

  String _getColumnFontFamily(String colKey) {
    return _colFontFamily[colKey] ?? _tableFontFamily;
  }

  Color _safeColor(Color c) {
    if (c == Colors.transparent || c.alpha == 0) {
      return const Color(0xFF0F172A);
    }
    return c;
  }

  Color _getMarkColor(double obtained, double max, bool isAbsent) {
    if (!_enableConditionalColors) return _safeColor(_tableMarksTextColor);
    if (isAbsent) return _safeColor(_failMarkColor);
    if (max <= 0) return _safeColor(_tableMarksTextColor);
    final pct = (obtained / max) * 100.0;
    if (pct >= _distinctionThreshold) return _safeColor(_distinctionMarkColor);
    if (pct >= _highMarkThreshold) return _safeColor(_highMarkColor);
    if (pct >= _averageMarkThreshold) return _safeColor(_averageMarkColor);
    if (pct >= _passMarkThreshold) return _safeColor(_lowMarkColor);
    return _safeColor(_failMarkColor);
  }

  Color _getGradeColor(String gradeName, Color markColor) {
    if (!_enableConditionalColors) return _safeColor(_tableGradeTextColor);
    return markColor;
  }

  String _getGradingScaleGrade(double totalObtained, double totalMax, bool hasAbsent) {
    if (hasAbsent) {
      return _cardLanguage == 'ur' ? 'راسب' : (_cardLanguage == 'ar' ? 'راسب' : 'Fail');
    }
    if (totalMax <= 0) return '-';
    final pct = (totalObtained / totalMax) * 100.0;

    final rules = _configuredGradingRules.isNotEmpty ? _configuredGradingRules : GradingHelper.defaultRules;
    if (rules.isNotEmpty) {
      for (final rule in rules) {
        final maxP = (rule.maxPercent >= 99.5) ? 100.0 : rule.maxPercent;
        if (pct >= rule.minPercent - 0.05 && pct <= maxP + 0.05) {
          return rule.grade;
        }
      }
      if (pct > rules.first.maxPercent) {
        return rules.first.grade;
      }
      if (pct < rules.last.minPercent) {
        return rules.last.grade;
      }
    }

    return '-';
  }

  String _getDynamicGrade(double obtained, double max, bool isAbsent, String defaultGrade) {
    if (isAbsent) {
      final text = _failMarkLabelCtrl.text.trim();
      return text.isNotEmpty ? text : _failMarkLabel;
    }
    if (max <= 0) return defaultGrade;
    final pct = (obtained / max) * 100.0;

    // 1. Evaluate Dynamic Grade Text Labels from Table Tab
    if (_enableConditionalColors) {
      if (pct >= _distinctionThreshold) {
        final text = _distinctionLabelCtrl.text.trim();
        return text.isNotEmpty ? text : _distinctionLabel;
      }
      if (pct >= _highMarkThreshold) {
        final text = _highMarkLabelCtrl.text.trim();
        return text.isNotEmpty ? text : _highMarkLabel;
      }
      if (pct >= _averageMarkThreshold) {
        final text = _averageMarkLabelCtrl.text.trim();
        return text.isNotEmpty ? text : _averageMarkLabel;
      }
      if (pct >= _passMarkThreshold) {
        final text = _passMarkLabelCtrl.text.trim();
        return text.isNotEmpty ? text : _passMarkLabel;
      }
      final text = _failMarkLabelCtrl.text.trim();
      return text.isNotEmpty ? text : _failMarkLabel;
    }

    // 2. Fallback to Grading Scale Rules
    final rules = _configuredGradingRules.isNotEmpty ? _configuredGradingRules : GradingHelper.defaultRules;
    if (rules.isNotEmpty) {
      for (final rule in rules) {
        final maxP = (rule.maxPercent >= 99.5) ? 100.0 : rule.maxPercent;
        if (pct >= rule.minPercent - 0.05 && pct <= maxP + 0.05) {
          return rule.grade;
        }
      }
      if (pct > rules.first.maxPercent) {
        return rules.first.grade;
      }
      if (pct < rules.last.minPercent) {
        return rules.last.grade;
      }
    }

    return defaultGrade;
  }

  double _getCellFontSize(String colKey) {
    switch (colKey) {
      case 'col1': return _tableCol1FontSize;
      case 'col2': return _bookNameFontSize;
      case 'col3': return _col3FontSize;
      case 'col4': return _col4FontSize;
      case 'col5': return _tableObtainedFontSize;
      case 'col6': return _tableGradeFontSize;
      default: return _tableRowFontSize;
    }
  }

  bool _isCellBold(String colKey) {
    switch (colKey) {
      case 'col2': return _bookNameBold;
      case 'col3': return _col3Bold;
      case 'col4': return _col4Bold;
      case 'col5': return _tableObtainedBold;
      case 'col6': return _tableGradeBold;
      default: return false;
    }
  }

  void _applyTableSizePreset(String preset) {
    setState(() {
      _tableScaleFactor = 100.0;
      switch (preset) {
        case 'compact':
          _tableHeaderFontSize = 9.5;
          _tableCol1FontSize = 9.0;
          _bookNameFontSize = 9.5;
          _col3FontSize = 9.0;
          _col4FontSize = 9.0;
          _tableObtainedFontSize = 9.5;
          _tableGradeFontSize = 9.5;
          _tableRowFontSize = 9.0;
          _rowSpacing = 3.0;
          _colPadding = 4.0;
          break;
        case 'standard':
          _tableHeaderFontSize = 12.0;
          _tableCol1FontSize = 11.0;
          _bookNameFontSize = 11.0;
          _col3FontSize = 11.0;
          _col4FontSize = 11.0;
          _tableObtainedFontSize = 11.5;
          _tableGradeFontSize = 11.5;
          _tableRowFontSize = 11.0;
          _rowSpacing = 2.0;
          _colPadding = 2.5;
          break;
        case 'large':
          _tableHeaderFontSize = 15.0;
          _tableCol1FontSize = 13.0;
          _bookNameFontSize = 13.5;
          _col3FontSize = 13.0;
          _col4FontSize = 13.0;
          _tableObtainedFontSize = 14.0;
          _tableGradeFontSize = 14.0;
          _tableRowFontSize = 13.0;
          _rowSpacing = 7.0;
          _colPadding = 8.0;
          break;
        case 'ultrahd':
          _tableHeaderFontSize = 18.0;
          _tableCol1FontSize = 15.0;
          _bookNameFontSize = 16.0;
          _col3FontSize = 15.0;
          _col4FontSize = 15.0;
          _tableObtainedFontSize = 16.0;
          _tableGradeFontSize = 16.5;
          _tableRowFontSize = 15.0;
          _rowSpacing = 9.0;
          _colPadding = 10.0;
          break;
      }
    });
  }

  List<_SubjectRowConfig> _tableSubjects = [];
  List<Map<String, dynamic>> _readymadeTemplatesList = [];

  String? _selectedFieldId = 'institution';
  bool _isFrontSide = true;
  int _customTextCounter = 1;
  int? _hoveredDividerIndex;
  int? _activeDraggingDividerIndex;

  final Map<String, _FieldConfig> _fieldsMap = {};

  final Map<String, bool> _columnVisible = {
    'col1': true,
    'col2': true,
    'col3': true,
    'col4': true,
    'col5': true,
    'col6': true,
  };

  final Map<String, TextEditingController> _colTitleCtrls = {};

  final List<String> _defaultFontFamilies = const [
    'Jameel Noori Nastaleeq',
    'Jameel Noori Kasheeda',
    'Arabic Typesetting',
    'Urdu Typesetting',
    'Aldhabi',
    'Andalus',
    'Simplified Arabic',
    'Traditional Arabic',
    'Sakkal Majalla',
    'Dubai',
    'Segoe UI',
    'Segoe Print',
    'Segoe Script',
    'Arial',
    'Calibri',
    'Cambria',
    'Century Gothic',
    'Times New Roman',
    'Georgia',
    'Garamond',
    'Book Antiqua',
    'Palatino Linotype',
    'Bahnschrift',
    'Candara',
    'Corbel',
    'Constantia',
    'Consolas',
    'Courier New',
    'Verdana',
    'Tahoma',
    'Trebuchet MS',
    'Impact',
    'Comic Sans MS',
    'Freestyle Script',
    'French Script MT',
    'Mistral',
    'Monotype Corsiva',
    'Lucida Handwriting',
    'Pristina',
    'Papyrus',
  ];

  List<String> _allFontFamilies = [];
  bool _fontsLoaded = false;

  final List<Color> _colorPalette = const [
    Colors.transparent,
    Colors.black,
    Colors.white,
    Color(0xFF0F766E),
    Color(0xFF0D6B4E),
    Color(0xFF00E5FF),
    Color(0xFFEAB308),
    Color(0xFF1E3A8A),
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFA855F7),
    Color(0xFF0284C7),
    Color(0xFF94A3B8),
    Color(0xFF78350F),
    Color(0xFF1E293B),
    Color(0xFF10B981),
    Color(0xFF6366F1),
    Color(0xFF881337),
    Color(0xFFFEF08A),
    Color(0xFF334155),
    Color(0xFF64748B),
    Color(0xFF15803D),
    Color(0xFFD97706),
    Color(0xFF0369A1),
  ];

  List<Student> get _filteredStudents {
    if (_selectedClassFilter == null || _selectedClassFilter == 'ALL') {
      return _studentsList;
    }
    return _studentsList
        .where((s) => s.className == _selectedClassFilter)
        .toList();
  }

  List<String> get _availableClasses {
    final classes = _studentsList
        .map((s) => s.className ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['ALL', ...classes];
  }

  List<_ColDef> get _visibleColumns {
    final cols = <_ColDef>[];
    final hdr1 = _fieldsMap['table_header_col1'];
    final hdr2 = _fieldsMap['table_header_col2'];
    final hdr3 = _fieldsMap['table_header_col3'];
    final hdr4 = _fieldsMap['table_header_col4'];
    final hdr5 = _fieldsMap['table_header_col5'];
    final hdr6 = _fieldsMap['table_header_col6'];
    if (_columnVisible['col1'] == true)
      cols.add(_ColDef('col1', 1, hdr1?.rawValue ?? '#'));
    if (_columnVisible['col2'] == true)
      cols.add(_ColDef('col2', 5, hdr2?.rawValue ?? 'Subject / Book Name'));
    if (_columnVisible['col3'] == true)
      cols.add(_ColDef('col3', 2, hdr3?.rawValue ?? 'Max Marks'));
    if (_columnVisible['col4'] == true)
      cols.add(_ColDef('col4', 2, hdr4?.rawValue ?? 'Min Pass'));
    if (_columnVisible['col5'] == true)
      cols.add(_ColDef('col5', 3, hdr5?.rawValue ?? 'Obtained Marks'));
    if (_columnVisible['col6'] == true)
      cols.add(_ColDef('col6', 2, hdr6?.rawValue ?? 'Grade'));
    return cols;
  }

  @override
  void initState() {
    super.initState();
    final defaultStudent = widget.student ?? Student(
      id: '1',
      registrationNumber: 'A26-0001',
      fullName: 'Sample Student',
    );
    _studentsList = List.from(widget.allStudents ?? []);
    if (widget.student != null && !_studentsList.any((s) => s.id == widget.student!.id)) {
      _studentsList.add(widget.student!);
    }
    if (widget.examResults != null && widget.examResults!.isNotEmpty) {
      for (final r in widget.examResults!) {
        final exists = _studentsList.any((s) => _matchStudentResult(r, s));
        if (!exists) {
          _studentsList.add(Student(
            id: '${r['student_id'] ?? r['id'] ?? '1'}',
            registrationNumber: '${r['registration_number'] ?? r['gr_no'] ?? '101'}',
            fullName: '${r['student_name'] ?? r['full_name'] ?? 'Student'}',
            grNo: '${r['gr_no'] ?? r['registration_number'] ?? '101'}',
            className: '${r['class_name'] ?? 'Class'}',
            fatherName: r['father_name']?.toString() ?? '',
            surname: r['surname']?.toString() ?? '',
            address: r['address']?.toString() ?? '',
            mobileNo: r['mobile_no']?.toString() ?? r['mobile']?.toString() ?? '',
          ));
        }
      }
    }
    if (_studentsList.isEmpty) {
      _studentsList = [defaultStudent];
    }

    _studentIndex = _studentsList.indexWhere((s) => _matchStudentResult({'student_id': s.id, 'id': s.id, 'registration_number': s.registrationNumber, 'full_name': s.fullName}, defaultStudent));
    if (_studentIndex < 0) _studentIndex = 0;
    _currentStudent = _studentsList[_studentIndex];



    _allFontFamilies = List.from(_defaultFontFamilies);
    _initializeDefaultTableSubjects();
    _initializeFieldsFromScratch();
    if (widget.examResults == null || widget.examResults!.isEmpty) {
      _loadRealStudentsFromApi();
    }
    _applyCardLanguage(_cardLanguage);
    _initColTitleControllers();
    _loadReadymadeTemplatesList();
    _loadSystemFonts();
    _loadConfiguredGradingRules();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _fieldTextCtrl.dispose();
    _titlePrefixCtrl.dispose();
    _fieldHexCtrl.dispose();
    _hijriTextCtrl.dispose();
    _distinctionThresholdCtrl.dispose();
    _highMarkThresholdCtrl.dispose();
    _averageMarkThresholdCtrl.dispose();
    _passMarkThresholdCtrl.dispose();
    _distinctionLabelCtrl.dispose();
    _highMarkLabelCtrl.dispose();
    _averageMarkLabelCtrl.dispose();
    _passMarkLabelCtrl.dispose();
    _failMarkLabelCtrl.dispose();
    for (final c in _colTitleCtrls.values) {
      c.dispose();
    }
    for (final s in _tableSubjects) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSystemFonts() async {
    try {
      // 1. Load bundled asset Urdu font under all family alias names
      try {
        final jameelData = await rootBundle.load('assets/fonts/JameelNooriNastaleeq.ttf');
        final aliases = [
          'Jameel Noori Nastaleeq',
          'JameelNooriNastaleeq',
          'Jameel Noori Kasheeda',
          'JameelNooriKasheeda',
          'Urdu Nastaleeq',
        ];
        for (final alias in aliases) {
          try {
            final loader = FontLoader(alias);
            loader.addFont(Future.value(jameelData));
            await loader.load();
          } catch (_) {}
        }
      } catch (_) {}

      // 2. Scan both System Fonts (C:\Windows\Fonts) AND User AppData Fonts (%LOCALAPPDATA%\Microsoft\Windows\Fonts)
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final fontDirs = <Directory>[
        Directory('C:\\Windows\\Fonts'),
        if (localAppData.isNotEmpty) Directory('$localAppData\\Microsoft\\Windows\\Fonts'),
      ];

      final discoveredUserFonts = <String>[];
      final loadedFamilies = <String>{};

      for (final fontDir in fontDirs) {
        if (!fontDir.existsSync()) continue;
        try {
          final fontFiles = fontDir.listSync().whereType<File>().toList();
          for (final f in fontFiles) {
            final pathLower = f.path.toLowerCase();
            if (pathLower.endsWith('.ttf') || pathLower.endsWith('.otf')) {
              final fileName = f.uri.pathSegments.last;
              String nameNoExt = fileName.substring(0, fileName.lastIndexOf('.'));
              
              // Clean website tags (e.g. "Al Mateen Bold - [UrduFonts.com]" -> "Al Mateen Bold")
              String cleanName = nameNoExt
                  .replaceAll(RegExp(r'\s*-\s*\[.*?\]', caseSensitive: false), '')
                  .replaceAll(RegExp(r'\s*-\s*UrduFonts.*', caseSensitive: false), '')
                  .trim();

              if (cleanName.isEmpty) cleanName = nameNoExt;

              try {
                final bytes = await f.readAsBytes();
                final byteData = Future.value(ByteData.sublistView(bytes));

                final namesToRegister = {
                  cleanName,
                  nameNoExt,
                  cleanName.replaceAll('-', ' '),
                  cleanName.replaceAll(' ', '-'),
                  cleanName.replaceAll(RegExp(r'[\s\-_]'), ''),
                };

                for (final regName in namesToRegister) {
                  final trimmed = regName.trim();
                  if (trimmed.isEmpty) continue;

                  if (!loadedFamilies.contains(trimmed)) {
                    try {
                      final loader = FontLoader(trimmed);
                      loader.addFont(byteData);
                      await loader.load();
                      loadedFamilies.add(trimmed);
                    } catch (_) {}
                  }

                  if (!discoveredUserFonts.contains(trimmed) && !trimmed.contains('- [')) {
                    discoveredUserFonts.add(trimmed);
                  }
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }

      // 3. Get complete list of ALL installed system font families on Windows
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Add-Type -AssemblyName System.Drawing; (New-Object System.Drawing.Text.InstalledFontCollection).Families | Select-Object -ExpandProperty Name',
      ]);

      if (result.exitCode == 0) {
        final systemFonts = (result.stdout as String)
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        for (final sf in systemFonts) {
          if (!discoveredUserFonts.contains(sf)) {
            discoveredUserFonts.add(sf);
          }
        }
      }

      if (mounted) {
        setState(() {
          final merged = List<String>.from(_defaultFontFamilies);
          for (final f in discoveredUserFonts) {
            if (!merged.contains(f)) {
              merged.add(f);
            }
          }
          _allFontFamilies = merged;
          _fontsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _fontsLoaded = true);
      }
    }
  }

  void _initColTitleControllers() {
    for (final colKey in [
      'table_header_col1',
      'table_header_col2',
      'table_header_col3',
      'table_header_col4',
      'table_header_col5',
      'table_header_col6',
    ]) {
      final f = _fieldsMap[colKey];
      _colTitleCtrls[colKey] = TextEditingController(text: f?.rawValue ?? '');
    }
  }

  void _bindFieldEditorControllers(String fieldId) {
    if (_lastBoundFieldId == fieldId) return;
    _lastBoundFieldId = fieldId;
    final f = _fieldsMap[fieldId];
    if (f != null) {
      _fieldTextCtrl.text = f.rawValue;
      _titlePrefixCtrl.text = f.titlePrefix;
      _updateHexCtrl(f.color);
    }
  }

  void _updateHexCtrl(Color c) {
    _fieldHexCtrl.text =
        '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  String _calculateGrade(double obtained, double maxMarks, bool isAbsent) {
    if (isAbsent) return 'راسب';
    if (maxMarks <= 0) return '-';
    final p = (obtained / maxMarks) * 100;
    if (p >= 80) return 'ممتاز';
    if (p >= 70) return 'اجود';
    if (p >= 60) return 'جيد';
    if (p >= 50) return 'مقبول';
    if (p >= 33) return 'مقبول';
    return 'راسب';
  }

  bool _matchStudentResult(Map<String, dynamic> r, Student s) {
    final rStudentId = r['student_id']?.toString().trim();
    final rId = r['id']?.toString().trim();
    final rRegNo = (r['registration_number'] ?? r['gr_no'])?.toString().trim();
    final rName = (r['student_name'] ?? r['full_name'])?.toString().trim().toLowerCase();

    final sId = s.id.trim();
    final sRegNo = s.registrationNumber.trim();
    final sGrNo = (s.grNo ?? '').trim();
    final sName = s.fullName.trim().toLowerCase();

    // 1. Direct ID match
    if (rStudentId != null && rStudentId.isNotEmpty && rStudentId == sId) return true;
    if (rId != null && rId.isNotEmpty && rId == sId) return true;

    // 2. Normalized RegNo / GR No match (e.g. A26-0008 vs A260008)
    String norm(String str) => str.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

    final nSRegNo = norm(sRegNo);
    final nSGrNo = norm(sGrNo);
    final nRRegNo = rRegNo != null ? norm(rRegNo) : '';
    final nRStudentId = rStudentId != null ? norm(rStudentId) : '';

    if (nSRegNo.isNotEmpty) {
      if (nRRegNo.isNotEmpty && nRRegNo == nSRegNo) return true;
      if (nRStudentId.isNotEmpty && nRStudentId == nSRegNo) return true;
    }
    if (nSGrNo.isNotEmpty) {
      if (nRRegNo.isNotEmpty && nRRegNo == nSGrNo) return true;
      if (nRStudentId.isNotEmpty && nRStudentId == nSGrNo) return true;
    }

    // 3. Name match
    if (sName.isNotEmpty && rName != null && rName.isNotEmpty) {
      if (rName == sName) return true;
      if (rName.contains(sName) || sName.contains(rName)) return true;
    }

    return false;
  }

  String _resolveBookName(dynamic m, int index) {
    String? bName;
    if (m is ExamMark) {
      bName = m.bookName;
      if (bName == null || bName.trim().isEmpty || bName.trim() == 'null') {
        if (m.bookId.trim().isNotEmpty && m.bookId.trim() != 'null' && int.tryParse(m.bookId) == null) {
          bName = m.bookId;
        }
      }
    } else if (m is Map) {
      bName = m['book_name'] ?? m['bookName'] ?? m['subject_name'] ?? m['subjectName'] ?? m['subject'] ?? m['name'] ?? m['title'] ?? m['course_name'];
      if (bName == null || '$bName'.trim().isEmpty || '$bName'.trim() == 'null') {
        if (m['book'] != null) {
          if (m['book'] is Map && m['book']['name'] != null && '${m['book']['name']}'.trim().isNotEmpty) {
            bName = '${m['book']['name']}';
          } else if (m['book'] is String && m['book'].toString().trim().isNotEmpty) {
            bName = m['book'].toString();
          }
        }
      }
      if (bName == null || '$bName'.trim().isEmpty || '$bName'.trim() == 'null') {
        final bId = m['book_id'] ?? m['bookId'];
        if (bId != null && '$bId'.trim().isNotEmpty && '$bId'.trim() != 'null' && int.tryParse('$bId') == null) {
          bName = '$bId';
        }
      }
    }
    if (bName != null && bName.toString().trim().isNotEmpty && bName.toString().trim() != 'null') {
      return bName.toString().trim();
    }
    return 'Subject ${index + 1}';
  }

  List<_SubjectRowConfig> _getSubjectsForStudent(Student s) {
    if (widget.examResults != null && widget.examResults!.isNotEmpty) {
      final res = widget.examResults!.firstWhere(
        (r) => _matchStudentResult(r, s),
        orElse: () => <String, dynamic>{},
      );

      final rawList = res.isNotEmpty ? res['subjects'] : null;
      if (rawList is List && rawList.isNotEmpty) {
        final configs = <_SubjectRowConfig>[];
        for (int i = 0; i < rawList.length; i++) {
          final m = rawList[i];
          final bookName = _resolveBookName(m, i);
          if (m is ExamMark) {
            final obt = (m.marksObtained ?? 0.0).toDouble();
            final maxM = m.maxMarks.toDouble();
            configs.add(_SubjectRowConfig(
              id: m.bookId.isNotEmpty ? m.bookId : '${i + 1}',
              bookName: bookName,
              maxMarks: maxM,
              marksObtained: obt,
              isAbsent: m.isAbsent,
              gradeName: _calculateGrade(obt, maxM, m.isAbsent),
            ));
          } else if (m is Map) {
            final bookId = '${m['book_id'] ?? m['bookId'] ?? (i + 1)}';
            final maxM = (m['max_marks'] ?? m['maxMarks'] ?? 100) is num
                ? (m['max_marks'] ?? m['maxMarks'] ?? 100).toDouble()
                : double.tryParse('${m['max_marks'] ?? m['maxMarks']}') ?? 100.0;
            final obt = (m['marks_obtained'] ?? m['marksObtained'] ?? 0) is num
                ? (m['marks_obtained'] ?? m['marksObtained'] ?? 0).toDouble()
                : double.tryParse('${m['marks_obtained'] ?? m['marksObtained']}') ?? 0.0;
            final isAbsent = m['is_absent'] == true || m['isAbsent'] == true || m['is_absent'] == 1;
            configs.add(_SubjectRowConfig(
              id: bookId,
              bookName: bookName,
              maxMarks: maxM,
              marksObtained: obt,
              isAbsent: isAbsent,
              gradeName: _calculateGrade(obt, maxM, isAbsent),
            ));
          }
        }
        if (configs.isNotEmpty) return configs;
      }
    }


    return [
      _SubjectRowConfig(id: '1', bookName: 'Bukhari', maxMarks: 100, marksObtained: 74, gradeName: 'ممتاز'),
      _SubjectRowConfig(id: '2', bookName: 'Mishqat', maxMarks: 100, marksObtained: 96, gradeName: 'اجود'),
      _SubjectRowConfig(id: '3', bookName: 'Mizan', maxMarks: 100, marksObtained: 75, gradeName: 'ممتاز'),
      _SubjectRowConfig(id: '4', bookName: 'Quran Tarjamah', maxMarks: 100, marksObtained: 92, gradeName: 'اجود'),
      _SubjectRowConfig(id: '5', bookName: 'nahva meer', maxMarks: 100, marksObtained: 95, gradeName: 'ممتاز'),
    ];
  }


  Map<String, int> _calculateClassRanks() {
    final ranks = <String, int>{};

    final classGroups = <String, List<Student>>{};
    for (final s in _studentsList) {
      final cName = s.className ?? 'DefaultClass';
      classGroups.putIfAbsent(cName, () => []).add(s);
    }

    for (final group in classGroups.values) {
      final studentScores = <Student, double>{};
      final studentObtained = <Student, double>{};
      for (final s in group) {
        final subs = _getSubjectsForStudent(s);
        double obt = 0;
        double max = 0;
        for (final m in subs) {
          if (!m.isAbsent) obt += m.marksObtained;
          max += m.maxMarks;
        }
        final p = max > 0 ? (obt / max) * 100 : 0.0;
        studentScores[s] = p;
        studentObtained[s] = obt;
      }

      final sortedStudents = group.toList()
        ..sort((a, b) {
          final cmpObt = (studentObtained[b] ?? 0.0).compareTo(studentObtained[a] ?? 0.0);
          if (cmpObt != 0) return cmpObt;
          return (studentScores[b] ?? 0.0).compareTo(studentScores[a] ?? 0.0);
        });

      for (int i = 0; i < sortedStudents.length; i++) {
        if (i == 0) {
          ranks[sortedStudents[0].id] = 1;
        } else {
          final prevStudent = sortedStudents[i - 1];
          final currStudent = sortedStudents[i];
          final prevObt = studentObtained[prevStudent] ?? 0.0;
          final currObt = studentObtained[currStudent] ?? 0.0;
          final prevPct = studentScores[prevStudent] ?? 0.0;
          final currPct = studentScores[currStudent] ?? 0.0;

          if ((prevObt - currObt).abs() < 0.01 && (prevPct - currPct).abs() < 0.01) {
            ranks[currStudent.id] = ranks[prevStudent.id]!;
          } else {
            ranks[currStudent.id] = ranks[prevStudent.id]! + 1;
          }
        }
      }
    }

    return ranks;
  }

  // ─── Full Name / Full Address Helpers (same as ID Card Designer) ─────
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

  String _getStudentClassDisplay(Student s, bool showDivision) {
    final baseClass = (s.className != null && s.className!.trim().isNotEmpty)
        ? s.className!.trim()
        : 'arabi awwal';

    if (!showDivision) {
      return baseClass;
    }

    final rawDiv = (s.division != null && s.division!.trim().isNotEmpty)
        ? s.division!.trim()
        : 'A';

    return '$baseClass ($rawDiv)';
  }

  Map<String, String> _buildStudentFieldValues(Student s, List<_SubjectRowConfig> subjects) {
    double totalObtained = 0;
    double totalMax = 0;
    bool hasAbsent = false;
    int absentCount = 0;

    for (final sub in subjects) {
      if (!sub.isAbsent) {
        totalObtained += sub.marksObtained;
      } else {
        hasAbsent = true;
        absentCount++;
      }
      totalMax += sub.maxMarks;
    }

    final percentage = totalMax > 0 ? (totalObtained / totalMax) * 100 : 0.0;
    final isPassed = !hasAbsent && percentage >= 33.0;

    String calculatedGrade = _getGradingScaleGrade(totalObtained, totalMax, hasAbsent);

    final ranksMap = _calculateClassRanks();
    final rankNo = ranksMap[s.id] ?? 1;

    final statusPassed = _cardLanguage == 'en'
        ? 'PASSED'
        : _cardLanguage == 'hi'
            ? 'उत्तीर्ण (PASSED)'
            : _cardLanguage == 'gu'
                ? 'પાસ (PASSED)'
                : _cardLanguage == 'ar'
                    ? 'ناجح (PASSED)'
                    : _cardLanguage == 'bn'
                        ? 'উত্তীর্ণ (PASSED)'
                        : 'PASSED (ناجح)';

    final statusFailed = _cardLanguage == 'en'
        ? 'FAILED'
        : _cardLanguage == 'hi'
            ? 'अनुत्तीर्ण (FAILED)'
            : _cardLanguage == 'gu'
                ? 'નાપાસ (FAILED)'
                : _cardLanguage == 'ar'
                    ? 'راسب (FAILED)'
                    : _cardLanguage == 'bn'
                        ? 'অনুত্তীর্ণ (FAILED)'
                        : 'FAILED (راسب)';

    final totalInClass = _studentsList.isNotEmpty
        ? _studentsList.where((student) => student.className == s.className).length
        : 1;

    return {
      'name': _getStudentNameDisplay(s, _fieldsMap['name']?.isCombinedName ?? false),
      'father': s.fatherName ?? '-',
      'class': _getStudentClassDisplay(s, _fieldsMap['class']?.showDivisionInClass ?? true),
      'total_students': UrduNumberHelper.convertDigits('$totalInClass', _cardLanguage),
      'gr_no': s.grNo ?? s.registrationNumber,
      'dob': s.dateOfBirth ?? '-',
      'address': _getStudentFullAddressDisplay(s, _fieldsMap['address']?.isCombinedAddress ?? false),
      'mobile_no': s.mobileNo ?? '-',
      'total_marks': UrduNumberHelper.convertDigits('${totalObtained.toStringAsFixed(0)} / ${totalMax.toStringAsFixed(0)}', _cardLanguage),
      'percentage': UrduNumberHelper.convertDigits('\u2066${percentage.toStringAsFixed(1)}%\u2069', _cardLanguage),
      'overall_grade': calculatedGrade,
      'position_rank': UrduNumberHelper.convertDigits('$rankNo', _cardLanguage),
      'result_status': isPassed ? statusPassed : statusFailed,
      'total_absent': UrduNumberHelper.convertDigits('$absentCount', _cardLanguage),
      'card_date': _buildFormattedDateText(),
    };
  }

  void _updateFieldsForCurrentStudent() {
    final s = _currentStudent;
    _tableSubjects = _getSubjectsForStudent(s);
    final values = _buildStudentFieldValues(s, _tableSubjects);

    for (final entry in values.entries) {
      if (_fieldsMap.containsKey(entry.key)) {
        _fieldsMap[entry.key]!.rawValue = entry.value;
      }
    }
  }

  void _initializeDefaultTableSubjects() {
    _updateFieldsForCurrentStudent();
  }

  void _initializeFieldsFromScratch() {
    final s = _currentStudent;
    _fieldsMap.clear();
    _fieldsMap.addAll({
      'bismillah': _FieldConfig(
        id: 'bismillah',
        label: 'Bismillah Calligraphy',
        titlePrefix: '',
        rawValue: 'بِسْمِ اللهِ الرَّحْمٰنِ الرَّحِيْمِ',
        showTitlePrefix: false,
        x: 0.16, y: 0.035,
        fontSize: 14, fontFamily: 'Jameel Noori Nastaleeq',
        color: Colors.white, bold: true, widthMm: 150, heightMm: 14,
      ),
      'institution': _FieldConfig(
        id: 'institution',
        label: 'Institution Header Title',
        titlePrefix: '', rawValue: 'JAMIA MADARSA AL-HIDAYAH',
        showTitlePrefix: false,
        x: 0.12, y: 0.058,
        fontSize: 19, fontFamily: 'Century Gothic',
        color: Colors.white, bold: true, widthMm: 160, heightMm: 15,
      ),
      'sub_header': _FieldConfig(
        id: 'sub_header', label: 'Sub Header Title',
        titlePrefix: '', rawValue: 'OFFICIAL MARKSHEET / RESULT CARD',
        showTitlePrefix: false,
        x: 0.15, y: 0.090,
        fontSize: 11.5, fontFamily: 'Segoe UI',
        color: const Color(0xFFFEF08A), bold: true, widthMm: 150, heightMm: 10,
      ),
      'session_info': _FieldConfig(
        id: 'session_info', label: 'Exam Session & Class',
        titlePrefix: '', rawValue: 'Annual — arabi 1',
        showTitlePrefix: false, visible: false,
        x: 0.28, y: 0.112,
        fontSize: 10, fontFamily: 'Segoe UI',
        color: Colors.white70, widthMm: 100, heightMm: 10,
      ),
      'name': _FieldConfig(
        id: 'name', label: 'Student Name',
        titlePrefix: 'Student Name: ', rawValue: s.fullName,
        showTitlePrefix: true,
        x: 0.05, y: 0.162,
        fontSize: 13.5, fontFamily: 'Segoe UI',
        color: const Color(0xFF0F172A), bold: true, widthMm: 110, heightMm: 12,
      ),
      'father': _FieldConfig(
        id: 'father', label: 'Father Name',
        titlePrefix: 'Father Name: ', rawValue: s.fatherName ?? '-',
        showTitlePrefix: true,
        x: 0.05, y: 0.198,
        fontSize: 12.5, fontFamily: 'Segoe UI',
        color: const Color(0xFF334155), visible: false, widthMm: 110, heightMm: 10,
      ),
      'class': _FieldConfig(
        id: 'class', label: 'Class / Darja',
        titlePrefix: 'Class: ', rawValue: s.className ?? 'arabi awwal',
        showTitlePrefix: true,
        x: 0.05, y: 0.198,
        fontSize: 13, fontFamily: 'Segoe UI',
        color: const Color(0xFF334155), widthMm: 110, heightMm: 10,
      ),
      'total_students': _FieldConfig(
        id: 'total_students', label: 'Total Class Students',
        titlePrefix: 'Total Students: ', rawValue: '1',
        showTitlePrefix: true, visible: false,
        x: 0.05, y: 0.22,
        fontSize: 12.5, fontFamily: 'Segoe UI',
        color: const Color(0xFF334155), widthMm: 110, heightMm: 10,
      ),
      'total_absent': _FieldConfig(
        id: 'total_absent', label: 'Total Absents Count',
        titlePrefix: 'Total Absent: ', rawValue: '0',
        showTitlePrefix: true, visible: false,
        x: 0.05, y: 0.24,
        fontSize: 12.5, fontFamily: 'Segoe UI',
        color: const Color(0xFF334155), widthMm: 110, heightMm: 10,
      ),
      'gr_no': _FieldConfig(
        id: 'gr_no', label: 'GR / Reg Number',
        titlePrefix: 'GR No: ', rawValue: s.grNo ?? s.registrationNumber,
        showTitlePrefix: true,
        x: 0.65, y: 0.162,
        fontSize: 13, fontFamily: 'Segoe UI',
        color: const Color(0xFF0F172A), bold: true, widthMm: 80, heightMm: 10,
      ),
      'dob': _FieldConfig(
        id: 'dob', label: 'Date of Birth',
        titlePrefix: 'D.O.B: ', rawValue: s.dateOfBirth ?? '-',
        showTitlePrefix: true,
        x: 0.65, y: 0.198,
        fontSize: 12, fontFamily: 'Segoe UI',
        color: const Color(0xFF64748B), visible: false, widthMm: 80, heightMm: 10,
      ),
      'card_date': _FieldConfig(
        id: 'card_date', label: 'Date of Issue / تاریخ اجرائ',
        titlePrefix: 'Date: ', rawValue: _buildFormattedDateText(),
        showTitlePrefix: true,
        x: 0.65, y: 0.198,
        fontSize: 12, fontFamily: 'Segoe UI',
        color: const Color(0xFF0F172A), bold: true, widthMm: 85, heightMm: 10,
      ),
      'card_hijri_date': _FieldConfig(
        id: 'card_hijri_date', label: 'Hijri Date / ہجری تاریخ (مطابق)',
        titlePrefix: 'مطابق: ', rawValue: _buildFormattedHijriDateText(),
        showTitlePrefix: true, visible: _showHijriDate,
        x: 0.65, y: 0.22,
        fontSize: 12, fontFamily: 'Jameel Noori Nastaleeq',
        color: const Color(0xFF0F172A), bold: true, widthMm: 85, heightMm: 10,
      ),
      'address': _FieldConfig(
        id: 'address', label: 'Student Address',
        titlePrefix: 'Address: ', rawValue: s.address ?? '-',
        showTitlePrefix: true,
        x: 0.05, y: 0.22,
        fontSize: 11.5, fontFamily: 'Segoe UI',
        color: const Color(0xFF64748B), visible: false, widthMm: 120, heightMm: 10,
      ),
      'mobile_no': _FieldConfig(
        id: 'mobile_no', label: 'Mobile Number',
        titlePrefix: 'Mobile No: ', rawValue: s.mobileNo ?? '-',
        showTitlePrefix: true,
        x: 0.65, y: 0.22,
        fontSize: 11.5, fontFamily: 'Segoe UI',
        color: const Color(0xFF64748B), visible: false, widthMm: 80, heightMm: 10,
      ),
      'table_header_col1': _FieldConfig(
        id: 'table_header_col1', label: '#',
        titlePrefix: '', rawValue: 'S.R.', showTitlePrefix: false,
        x: 0, y: 0, fontSize: 12, color: Colors.white, bold: true, widthMm: 20, heightMm: 10,
      ),
      'table_header_col2': _FieldConfig(
        id: 'table_header_col2', label: 'Book Name',
        titlePrefix: '', rawValue: 'Book Name', showTitlePrefix: false,
        x: 0, y: 0, fontSize: 12, color: Colors.white, bold: true, widthMm: 80, heightMm: 10,
      ),
      'table_header_col3': _FieldConfig(
        id: 'table_header_col3', label: 'Max Marks',
        titlePrefix: '', rawValue: 'Max Marks', showTitlePrefix: false,
        x: 0, y: 0, fontSize: 12, color: Colors.white, bold: true, widthMm: 30, heightMm: 10,
      ),
      'table_header_col4': _FieldConfig(
        id: 'table_header_col4', label: 'Min Pass',
        titlePrefix: '', rawValue: 'Min Pass', showTitlePrefix: false,
        x: 0, y: 0, fontSize: 12, color: Colors.white, bold: true, widthMm: 30, heightMm: 10,
      ),
      'table_header_col5': _FieldConfig(
        id: 'table_header_col5', label: 'Obtained',
        titlePrefix: '', rawValue: 'Obtained Marks', showTitlePrefix: false,
        x: 0, y: 0, fontSize: 12, color: Colors.white, bold: true, widthMm: 40, heightMm: 10,
      ),
      'table_header_col6': _FieldConfig(
        id: 'table_header_col6', label: 'Grade',
        titlePrefix: '', rawValue: 'Grade', showTitlePrefix: false,
        x: 0, y: 0, fontSize: 12, color: Colors.white, bold: true, widthMm: 30, heightMm: 10,
      ),
      'marks_table': _FieldConfig(
        id: 'marks_table', label: 'Subjects Marks Table 1',
        titlePrefix: '', rawValue: 'Table 1', showTitlePrefix: false,
        x: 0.035, y: 0.245, isTable: true, widthMm: 195, heightMm: 120,
      ),
      'marks_table_2': _FieldConfig(
        id: 'marks_table_2', label: 'Subjects Marks Table 2',
        titlePrefix: '', rawValue: 'Table 2', showTitlePrefix: false,
        visible: false,
        x: 0.035, y: 0.520, isTable: true, widthMm: 195, heightMm: 120,
      ),
      'total_marks': _FieldConfig(
        id: 'total_marks', label: 'Total Marks Summary',
        titlePrefix: 'Total Marks: ', rawValue: _buildTotalMarksText(),
        showTitlePrefix: true,
        x: 0.055, y: 0.705,
        fontSize: 12.5, fontFamily: 'Segoe UI',
        color: const Color(0xFF0F172A), bold: true, widthMm: 80, heightMm: 10,
      ),
      'percentage': _FieldConfig(
        id: 'percentage', label: 'Percentage',
        titlePrefix: 'Percentage: ', rawValue: _buildPercentageText(),
        showTitlePrefix: true,
        x: 0.055, y: 0.738,
        fontSize: 13, fontFamily: 'Segoe UI',
        color: const Color(0xFF0F766E), bold: true, widthMm: 80, heightMm: 10,
      ),
      'overall_grade': _FieldConfig(
        id: 'overall_grade', label: 'Overall Grade',
        titlePrefix: 'Overall Grade: ', rawValue: 'اجود',
        showTitlePrefix: true,
        x: 0.055, y: 0.772,
        fontSize: 12.5, fontFamily: 'Jameel Noori Nastaleeq',
        color: const Color(0xFF0F172A), bold: true, widthMm: 80, heightMm: 10,
      ),
      'position_rank': _FieldConfig(
        id: 'position_rank', label: 'Position / Rank',
        titlePrefix: 'Rank: ', rawValue: '1',
        showTitlePrefix: true,
        x: 0.055, y: 0.805,
        fontSize: 12.5, fontFamily: 'Segoe UI',
        color: const Color(0xFFF97316), bold: true, widthMm: 80, heightMm: 10,
      ),
      'result_status': _FieldConfig(
        id: 'result_status', label: 'Result Status Badge',
        titlePrefix: '', rawValue: 'PASSED (ناجح)', showTitlePrefix: false,
        x: 0.30, y: 0.842,
        fontSize: 12.5, fontFamily: 'Arabic Typesetting',
        color: const Color(0xFF15803D), bold: true, widthMm: 60, heightMm: 10,
      ),
      'grading_scale_title': _FieldConfig(
        id: 'grading_scale_title', label: 'Grading Scale Title',
        titlePrefix: '', rawValue: 'Grading Scale', showTitlePrefix: false,
        x: 0.62, y: 0.705,
        fontSize: 12.5, fontFamily: 'Segoe UI',
        color: const Color(0xFF0F172A), bold: true, widthMm: 80, heightMm: 45,
      ),
      'teacher_sign': _FieldConfig(
        id: 'teacher_sign', label: 'Teacher Signature',
        titlePrefix: '', rawValue: 'Class Teacher', showTitlePrefix: false,
        x: 0.06, y: 0.905,
        fontSize: 11.5, fontFamily: 'French Script MT',
        color: const Color(0xFF334155), isSignature: true, photoWidth: 55, photoHeight: 30,
      ),
      'stamp': _FieldConfig(
        id: 'stamp', label: 'Official Stamp',
        titlePrefix: '', rawValue: 'Official Stamp / Seal', showTitlePrefix: false,
        x: 0.42, y: 0.905,
        fontSize: 11.5, fontFamily: 'Segoe UI',
        color: const Color(0xFF0F766E), isStamp: true, photoWidth: 45, photoHeight: 45,
      ),
      'principal_sign': _FieldConfig(
        id: 'principal_sign', label: 'Principal Signature',
        titlePrefix: '', rawValue: 'Principal / Controller', showTitlePrefix: false,
        x: 0.74, y: 0.905,
        fontSize: 11.5, fontFamily: 'French Script MT',
        color: const Color(0xFF334155), isSignature: true, photoWidth: 55, photoHeight: 30,
      ),
      'footer_note': _FieldConfig(
        id: 'footer_note', label: 'Footer Note',
        titlePrefix: 'Note: ',
        rawValue: 'This is an official computer-generated Marksheet.',
        showTitlePrefix: true,
        x: 0.08, y: 0.948,
        fontSize: 9.5, fontFamily: 'Segoe UI',
        color: const Color(0xFF64748B), widthMm: 180, heightMm: 10,
      ),
    });
    _autoFitAllTextFields();
  }

  void _autoFitAllTextFields() {
    for (final key in _fieldsMap.keys) {
      final f = _fieldsMap[key];
      if (f != null && !f.isTable && !f.isPhoto && !f.isSignature && !f.isStamp) {
        final txt = f.displayText;
        if (txt.isEmpty) continue;
        final textStyle = TextStyle(
          fontSize: f.fontSize,
          fontFamily: f.fontFamily,
          fontWeight: f.bold ? FontWeight.bold : FontWeight.normal,
        );
        final textPainter = TextPainter(
          text: TextSpan(text: txt, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final double widthPx = textPainter.width + 16.0;
        final double heightPx = textPainter.height + 8.0;
        final double widthMm = (widthPx * 0.352778).clamp(15.0, _pageWidthMm);
        final double heightMm = (heightPx * 0.352778).clamp(6.0, _pageHeightMm);
        f.widthMm = double.parse(widthMm.toStringAsFixed(1));
        f.heightMm = double.parse(heightMm.toStringAsFixed(1));
      }
    }
  }

  void _updateStudentFieldsData() {
    _updateFieldsForCurrentStudent();
    _updateCardDateFieldValue();
    _refreshTotals();
    _autoFitAllTextFields();
    _lastBoundFieldId = null;
    if (_selectedFieldId != null) {
      _bindFieldEditorControllers(_selectedFieldId!);
    }
  }

  void _switchStudent(int idx) {
    final pool = _filteredStudents;
    if (idx >= 0 && idx < pool.length) {
      setState(() {
        _studentIndex = idx;
        _currentStudent = pool[idx];
        _updateStudentFieldsData();
      });
    }
  }

  String _buildTotalMarksText() {
    double obt = 0, max = 0;
    for (final m in _tableSubjects) {
      if (!m.isAbsent) obt += m.marksObtained;
      max += m.maxMarks;
    }
    final raw = '${obt.toStringAsFixed(0)} / ${max.toStringAsFixed(0)}';
    return UrduNumberHelper.convertDigits(raw, _cardLanguage);
  }

  String _buildPercentageText() {
    double obt = 0, max = 0;
    for (final m in _tableSubjects) {
      if (!m.isAbsent) obt += m.marksObtained;
      max += m.maxMarks;
    }
    final raw = max > 0 ? '\u2066${((obt / max) * 100).toStringAsFixed(1)}%\u2069' : '\u20660%\u2069';
    return UrduNumberHelper.convertDigits(raw, _cardLanguage);
  }

  void _refreshTotals() {
    if (_fieldsMap.containsKey('total_marks'))
      _fieldsMap['total_marks']!.rawValue = _buildTotalMarksText();
    if (_fieldsMap.containsKey('percentage'))
      _fieldsMap['percentage']!.rawValue = _buildPercentageText();
  }

  void _addTableSubject() {
    setState(() {
      _tableSubjects.add(
        _SubjectRowConfig(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          bookName: 'New Subject ${_tableSubjects.length + 1}',
          maxMarks: 100,
          marksObtained: 85,
          gradeName: 'اجود',
        ),
      );
      _refreshTotals();
    });
  }

  void _deleteTableSubject(int index) {
    if (index >= 0 && index < _tableSubjects.length) {
      setState(() {
        _tableSubjects[index].dispose();
        _tableSubjects.removeAt(index);
        _refreshTotals();
      });
    }
  }

  void _addCustomTextField() {
    final key = 'custom_text_${_customTextCounter++}';
    setState(() {
      _fieldsMap[key] = _FieldConfig(
        id: key, label: 'Custom Text ${_customTextCounter - 1}',
        titlePrefix: '', rawValue: 'Custom Text ${_customTextCounter - 1}',
        showTitlePrefix: false,
        x: 0.10, y: 0.50,
        fontSize: 12, fontFamily: 'Segoe UI',
        color: const Color(0xFF0F172A), isCustomText: true,
        widthMm: 80, heightMm: 14,
      );
      _selectedFieldId = key;
      _lastBoundFieldId = null;
    });
  }

  void _applyPaperPreset(String presetName) {
    setState(() {
      _selectedPaperPreset = presetName;
      switch (presetName) {
        case 'A4': _pageWidthMm = 210.0; _pageHeightMm = 297.0; break;
        case 'B5': _pageWidthMm = 176.0; _pageHeightMm = 250.0; break;
        case 'A5': _pageWidthMm = 148.0; _pageHeightMm = 210.0; break;
        case 'A3': _pageWidthMm = 297.0; _pageHeightMm = 420.0; break;
        case 'Letter': _pageWidthMm = 215.9; _pageHeightMm = 279.4; break;
        case 'Legal': _pageWidthMm = 215.9; _pageHeightMm = 355.6; break;
      }
      if (_isLandscape) {
        final tmp = _pageWidthMm;
        _pageWidthMm = _pageHeightMm;
        _pageHeightMm = tmp;
      }
    });
  }

  Future<void> _pickExternalTemplateImage({required bool isFront}) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res != null && res.files.single.path != null) {
      setState(() {
        if (isFront) {
          _uploadedTemplateImageFront = File(res.files.single.path!);
        } else {
          _uploadedTemplateImageBack = File(res.files.single.path!);
        }
        _useUploadedTemplate = true;
      });
    }
  }

  Future<void> _saveCurrentTemplateToReadymade() async {
    final nameCtrl = TextEditingController(
        text: 'My Template ${_readymadeTemplatesList.length + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save to Readymade Templates'),
        content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Template Name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E)),
            onPressed: () => Navigator.pop(ctx, nameCtrl.text),
            child: const Text('Save',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    nameCtrl.dispose();

    if (name == null || name.trim().isEmpty) return;

    final fieldsData = <String, Map<String, dynamic>>{};
    for (final entry in _fieldsMap.entries) {
      final f = entry.value;
      fieldsData[entry.key] = {
        'id': f.id,
        'label': f.label,
        'rawValue': f.rawValue,
        'titlePrefix': f.titlePrefix,
        'showTitlePrefix': f.showTitlePrefix,
        'fontFamily': f.fontFamily,
        'x': f.x,
        'y': f.y,
        'fontSize': f.fontSize,
        'color': f.color.toARGB32(),
        'bold': f.bold,
        'visible': f.visible,
        'side': f.side,
        'isPhoto': f.isPhoto,
        'isSignature': f.isSignature,
        'isStamp': f.isStamp,
        'isTable': f.isTable,
        'isCustomText': f.isCustomText,
        'isCombinedName': f.isCombinedName,
        'isCombinedAddress': f.isCombinedAddress,
        'widthMm': f.widthMm,
        'heightMm': f.heightMm,
      };
    }

    _readymadeTemplatesList.add({
      'name': name.trim(),
      'date': DateTime.now().toString().split(' ').first,
      'paper': _selectedPaperPreset,
      'cardLanguage': _cardLanguage,
      'headerBannerBg': _headerBannerBg.toARGB32(),
      'tableHeaderBg': _tableHeaderBg.toARGB32(),
      'pageBorderColor': _pageBorderColor.toARGB32(),
      'columnVisible': Map<String, bool>.from(_columnVisible),
      'fields': fieldsData,
      'pageWidthMm': _pageWidthMm,
      'pageHeightMm': _pageHeightMm,
      'pageBorderWidth': _pageBorderWidth,
      'borderRadius': _borderRadius,
      'pageBgColor': _pageBgColor.toARGB32(),
      'isTransparentPageBg': _isTransparentPageBg,
      'useUploadedTemplate': _useUploadedTemplate,
      'uploadedTemplateImageFront': _uploadedTemplateImageFront?.path,
      'uploadedTemplateImageBack': _uploadedTemplateImageBack?.path,
      'tableHeaderTextColor': _tableHeaderTextColor.toARGB32(),
      'bookNameTextColor': _bookNameTextColor.toARGB32(),
      'tableRowTextColor': _tableRowTextColor.toARGB32(),
      'tableMarksTextColor': _tableMarksTextColor.toARGB32(),
      'tableGradeTextColor': _tableGradeTextColor.toARGB32(),
      'alternatingRowBgColor': _alternatingRowBgColor.toARGB32(),
      'isTransparentRowBg': _isTransparentRowBg,
      'tableFontFamily': _tableFontFamily,
      'tableUrduFontFamily': _tableUrduFontFamily,
      'tableScaleFactor': _tableScaleFactor,
      'isTableGrouped': _isTableGrouped,
      'rowSpacing': _rowSpacing,
      'colPadding': _colPadding,
      'tableGridColor': _tableGridColor.toARGB32(),
      'tableGridWidth': _tableGridWidth,
      'tableHeaderFontSize': _tableHeaderFontSize,
      'tableHeaderBold': _tableHeaderBold,
      'colWidthMm': _colWidthMm,
      'colX': _colX,
      'colY': _colY,
      'colCustomFlex': _colCustomFlex,
      'tableCol1FontSize': _tableCol1FontSize,
      'bookNameFontSize': _bookNameFontSize,
      'bookNameBold': _bookNameBold,
      'col3FontSize': _col3FontSize,
      'col3Bold': _col3Bold,
      'col3TextColor': _col3TextColor.toARGB32(),
      'col4FontSize': _col4FontSize,
      'col4Bold': _col4Bold,
      'col4TextColor': _col4TextColor.toARGB32(),
      'tableObtainedFontSize': _tableObtainedFontSize,
      'tableObtainedBold': _tableObtainedBold,
      'tableGradeFontSize': _tableGradeFontSize,
      'tableGradeBold': _tableGradeBold,
      'colFontFamily': _colFontFamily,
      'enableConditionalColors': _enableConditionalColors,
      'distinctionThreshold': _distinctionThreshold,
      'highMarkThreshold': _highMarkThreshold,
      'averageMarkThreshold': _averageMarkThreshold,
      'passMarkThreshold': _passMarkThreshold,
      'distinctionLabel': _distinctionLabel,
      'highMarkLabel': _highMarkLabel,
      'averageMarkLabel': _averageMarkLabel,
      'passMarkLabel': _passMarkLabel,
      'failMarkLabel': _failMarkLabel,
      'distinctionMarkColor': _distinctionMarkColor.toARGB32(),
      'highMarkColor': _highMarkColor.toARGB32(),
      'averageMarkColor': _averageMarkColor.toARGB32(),
      'lowMarkColor': _lowMarkColor.toARGB32(),
      'failMarkColor': _failMarkColor.toARGB32(),
      'convertGrNoDigits': _convertGrNoDigits,
      'pdfPrintSide': _pdfPrintSide,
      'rowCustomSpacing': _rowCustomSpacing.map((key, value) => MapEntry(key.toString(), value)),
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'all_readymade_result_templates_v7',
        jsonEncode(_readymadeTemplatesList));

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Template "$name" saved!'),
        backgroundColor: const Color(0xFF0D6B4E),
      ));
    }
  }

  Future<void> _loadReadymadeTemplatesList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('all_readymade_result_templates_v7');
      if (str != null) {
        _readymadeTemplatesList =
            (jsonDecode(str) as List<dynamic>).cast<Map<String, dynamic>>();
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _deleteTemplate(int index, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _readymadeTemplatesList.removeAt(index);
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'all_readymade_result_templates_v7',
          jsonEncode(_readymadeTemplatesList));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Template "$name" deleted.'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _loadTemplatePayload(Map<String, dynamic> data) {
    setState(() {
      if (data.containsKey('cardLanguage'))
        _applyCardLanguage(data['cardLanguage'] as String);
      if (data.containsKey('paper'))
        _applyPaperPreset(data['paper'] as String);
      if (data.containsKey('headerBannerBg'))
        _headerBannerBg = Color(data['headerBannerBg'] as int);
      if (data.containsKey('tableHeaderBg'))
        _tableHeaderBg = Color(data['tableHeaderBg'] as int);
      if (data.containsKey('pageBorderColor'))
        _pageBorderColor = Color(data['pageBorderColor'] as int);
      if (data.containsKey('columnVisible')) {
        final cv = data['columnVisible'] as Map<String, dynamic>;
        for (final e in cv.entries) {
          _columnVisible[e.key] = e.value as bool;
        }
      }
      if (data.containsKey('pageWidthMm')) _pageWidthMm = (data['pageWidthMm'] as num).toDouble();
      if (data.containsKey('pageHeightMm')) _pageHeightMm = (data['pageHeightMm'] as num).toDouble();
      if (data.containsKey('pageBorderWidth')) _pageBorderWidth = (data['pageBorderWidth'] as num).toDouble();
      if (data.containsKey('borderRadius')) _borderRadius = (data['borderRadius'] as num).toDouble();
      if (data.containsKey('pageBgColor')) _pageBgColor = Color(data['pageBgColor'] as int);
      if (data.containsKey('isTransparentPageBg')) _isTransparentPageBg = data['isTransparentPageBg'] as bool;
      if (data.containsKey('useUploadedTemplate')) _useUploadedTemplate = data['useUploadedTemplate'] as bool;
      if (data.containsKey('uploadedTemplateImageFront')) {
        final path = data['uploadedTemplateImageFront'] as String?;
        _uploadedTemplateImageFront = path != null ? File(path) : null;
      }
      if (data.containsKey('uploadedTemplateImageBack')) {
        final path = data['uploadedTemplateImageBack'] as String?;
        _uploadedTemplateImageBack = path != null ? File(path) : null;
      }
      if (data.containsKey('tableHeaderTextColor')) _tableHeaderTextColor = Color(data['tableHeaderTextColor'] as int);
      if (data.containsKey('bookNameTextColor')) _bookNameTextColor = Color(data['bookNameTextColor'] as int);
      if (data.containsKey('tableRowTextColor')) _tableRowTextColor = Color(data['tableRowTextColor'] as int);
      if (data.containsKey('tableMarksTextColor')) _tableMarksTextColor = Color(data['tableMarksTextColor'] as int);
      if (data.containsKey('tableGradeTextColor')) _tableGradeTextColor = Color(data['tableGradeTextColor'] as int);
      if (data.containsKey('alternatingRowBgColor')) _alternatingRowBgColor = Color(data['alternatingRowBgColor'] as int);
      if (data.containsKey('isTransparentRowBg')) _isTransparentRowBg = data['isTransparentRowBg'] as bool;
      if (data.containsKey('tableFontFamily')) _tableFontFamily = data['tableFontFamily'] as String;
      if (data.containsKey('tableUrduFontFamily')) _tableUrduFontFamily = data['tableUrduFontFamily'] as String;
      if (data.containsKey('tableScaleFactor')) _tableScaleFactor = (data['tableScaleFactor'] as num).toDouble();
      if (data.containsKey('isTableGrouped')) _isTableGrouped = data['isTableGrouped'] as bool;
      if (data.containsKey('rowSpacing')) _rowSpacing = (data['rowSpacing'] as num).toDouble();
      if (data.containsKey('colPadding')) _colPadding = (data['colPadding'] as num).toDouble();
      if (data.containsKey('tableGridColor')) _tableGridColor = Color(data['tableGridColor'] as int);
      if (data.containsKey('tableGridWidth')) _tableGridWidth = (data['tableGridWidth'] as num).toDouble();
      if (data.containsKey('tableHeaderFontSize')) _tableHeaderFontSize = (data['tableHeaderFontSize'] as num).toDouble();
      if (data.containsKey('tableHeaderBold')) _tableHeaderBold = data['tableHeaderBold'] as bool;
      if (data.containsKey('colWidthMm')) {
        final Map<String, dynamic> map = data['colWidthMm'] as Map<String, dynamic>;
        _colWidthMm.clear();
        _colWidthMm.addAll(map.map((key, value) => MapEntry(key, (value as num).toDouble())));
      }
      if (data.containsKey('colX')) {
        final Map<String, dynamic> map = data['colX'] as Map<String, dynamic>;
        _colX.clear();
        _colX.addAll(map.map((key, value) => MapEntry(key, (value as num).toDouble())));
      }
      if (data.containsKey('colY')) {
        final Map<String, dynamic> map = data['colY'] as Map<String, dynamic>;
        _colY.clear();
        _colY.addAll(map.map((key, value) => MapEntry(key, (value as num).toDouble())));
      }
      if (data.containsKey('colCustomFlex')) {
        final Map<String, dynamic> map = data['colCustomFlex'] as Map<String, dynamic>;
        _colCustomFlex.clear();
        _colCustomFlex.addAll(map.map((key, value) => MapEntry(key, (value as num).toDouble())));
      }
      if (data.containsKey('tableCol1FontSize')) _tableCol1FontSize = (data['tableCol1FontSize'] as num).toDouble();
      if (data.containsKey('bookNameFontSize')) _bookNameFontSize = (data['bookNameFontSize'] as num).toDouble();
      if (data.containsKey('bookNameBold')) _bookNameBold = data['bookNameBold'] as bool;
      if (data.containsKey('col3FontSize')) _col3FontSize = (data['col3FontSize'] as num).toDouble();
      if (data.containsKey('col3Bold')) _col3Bold = data['col3Bold'] as bool;
      if (data.containsKey('col3TextColor')) _col3TextColor = Color(data['col3TextColor'] as int);
      if (data.containsKey('col4FontSize')) _col4FontSize = (data['col4FontSize'] as num).toDouble();
      if (data.containsKey('col4Bold')) _col4Bold = data['col4Bold'] as bool;
      if (data.containsKey('col4TextColor')) _col4TextColor = Color(data['col4TextColor'] as int);
      if (data.containsKey('tableObtainedFontSize')) _tableObtainedFontSize = (data['tableObtainedFontSize'] as num).toDouble();
      if (data.containsKey('tableObtainedBold')) _tableObtainedBold = data['tableObtainedBold'] as bool;
      if (data.containsKey('tableGradeFontSize')) _tableGradeFontSize = (data['tableGradeFontSize'] as num).toDouble();
      if (data.containsKey('tableGradeBold')) _tableGradeBold = data['tableGradeBold'] as bool;
      if (data.containsKey('colFontFamily')) {
        final Map<String, dynamic> map = data['colFontFamily'] as Map<String, dynamic>;
        _colFontFamily.clear();
        _colFontFamily.addAll(map.map((key, value) => MapEntry(key, value as String)));
      }
      if (data.containsKey('enableConditionalColors')) _enableConditionalColors = data['enableConditionalColors'] as bool;
      if (data.containsKey('distinctionThreshold')) _distinctionThreshold = (data['distinctionThreshold'] as num).toDouble();
      if (data.containsKey('highMarkThreshold')) _highMarkThreshold = (data['highMarkThreshold'] as num).toDouble();
      if (data.containsKey('averageMarkThreshold')) _averageMarkThreshold = (data['averageMarkThreshold'] as num).toDouble();
      if (data.containsKey('passMarkThreshold')) _passMarkThreshold = (data['passMarkThreshold'] as num).toDouble();
      if (data.containsKey('distinctionLabel')) {
        _distinctionLabel = data['distinctionLabel'] as String;
        _distinctionLabelCtrl.text = _distinctionLabel;
      }
      if (data.containsKey('highMarkLabel')) {
        _highMarkLabel = data['highMarkLabel'] as String;
        _highMarkLabelCtrl.text = _highMarkLabel;
      }
      if (data.containsKey('averageMarkLabel')) {
        _averageMarkLabel = data['averageMarkLabel'] as String;
        _averageMarkLabelCtrl.text = _averageMarkLabel;
      }
      if (data.containsKey('passMarkLabel')) {
        _passMarkLabel = data['passMarkLabel'] as String;
        _passMarkLabelCtrl.text = _passMarkLabel;
      }
      if (data.containsKey('failMarkLabel')) {
        _failMarkLabel = data['failMarkLabel'] as String;
        _failMarkLabelCtrl.text = _failMarkLabel;
      }
      if (data.containsKey('distinctionMarkColor')) _distinctionMarkColor = Color(data['distinctionMarkColor'] as int);
      if (data.containsKey('highMarkColor')) _highMarkColor = Color(data['highMarkColor'] as int);
      if (data.containsKey('averageMarkColor')) _averageMarkColor = Color(data['averageMarkColor'] as int);
      if (data.containsKey('lowMarkColor')) _lowMarkColor = Color(data['lowMarkColor'] as int);
      if (data.containsKey('failMarkColor')) _failMarkColor = Color(data['failMarkColor'] as int);
      if (data.containsKey('convertGrNoDigits')) _convertGrNoDigits = data['convertGrNoDigits'] as bool;
      if (data.containsKey('pdfPrintSide')) _pdfPrintSide = data['pdfPrintSide'] as String;
      if (data.containsKey('rowCustomSpacing')) {
        final Map<String, dynamic> map = data['rowCustomSpacing'] as Map<String, dynamic>;
        _rowCustomSpacing = map.map((key, value) => MapEntry(int.parse(key), (value as num).toDouble()));
      } else {
        _rowCustomSpacing = {};
      }
      if (data.containsKey('fields')) {
        final fMap = data['fields'] as Map<String, dynamic>;
        
        // Restore customTextCounter based on saved custom_text_* keys
        int maxCounter = 1;
        for (final entry in fMap.entries) {
          if (entry.key.startsWith('custom_text_')) {
            final part = entry.key.substring('custom_text_'.length);
            final val = int.tryParse(part);
            if (val != null && val >= maxCounter) {
              maxCounter = val + 1;
            }
          }
        }
        _customTextCounter = maxCounter;

        for (final entry in fMap.entries) {
          final m = entry.value as Map<String, dynamic>;
          if (!_fieldsMap.containsKey(entry.key)) {
            // Instantiate custom or new template fields dynamically
            _fieldsMap[entry.key] = _FieldConfig(
              id: entry.key,
              label: m['label'] as String? ?? entry.key,
              titlePrefix: m['titlePrefix'] as String? ?? '',
              rawValue: m['rawValue'] as String? ?? '',
              showTitlePrefix: m['showTitlePrefix'] as bool? ?? false,
              x: (m['x'] as num).toDouble(),
              y: (m['y'] as num).toDouble(),
              fontSize: (m['fontSize'] as num? ?? 11.0).toDouble(),
              fontFamily: m['fontFamily'] as String? ?? 'Segoe UI',
              color: Color(m['color'] as int? ?? const Color(0xFF0F172A).value),
              bold: m['bold'] as bool? ?? false,
              visible: m['visible'] as bool? ?? true,
              side: m['side'] as String? ?? 'front',
              isPhoto: m['isPhoto'] as bool? ?? false,
              isSignature: m['isSignature'] as bool? ?? false,
              isStamp: m['isStamp'] as bool? ?? false,
              isTable: m['isTable'] as bool? ?? false,
              isCustomText: m['isCustomText'] as bool? ?? false,
              isCombinedName: m['isCombinedName'] as bool? ?? false,
              isCombinedAddress: m['isCombinedAddress'] as bool? ?? false,
              widthMm: (m['widthMm'] as num? ?? 80.0).toDouble(),
              heightMm: (m['heightMm'] as num? ?? 14.0).toDouble(),
            );
          } else {
            // Update existing field attributes safely
            final f = _fieldsMap[entry.key]!;
            if (m.containsKey('rawValue')) f.rawValue = m['rawValue'] as String;
            if (m.containsKey('titlePrefix')) f.titlePrefix = m['titlePrefix'] as String;
            if (m.containsKey('showTitlePrefix')) f.showTitlePrefix = m['showTitlePrefix'] as bool;
            if (m.containsKey('fontFamily')) f.fontFamily = m['fontFamily'] as String;
            if (m.containsKey('x')) f.x = (m['x'] as num).toDouble();
            if (m.containsKey('y')) f.y = (m['y'] as num).toDouble();
            if (m.containsKey('fontSize')) f.fontSize = (m['fontSize'] as num).toDouble();
            if (m.containsKey('color')) f.color = Color(m['color'] as int);
            if (m.containsKey('bold')) f.bold = m['bold'] as bool;
            if (m.containsKey('visible')) f.visible = m['visible'] as bool;
            if (m.containsKey('widthMm')) f.widthMm = (m['widthMm'] as num).toDouble();
            if (m.containsKey('heightMm')) f.heightMm = (m['heightMm'] as num).toDouble();
            if (m.containsKey('side')) f.side = m['side'] as String;
          }
        }
      }
      for (final k in _colTitleCtrls.keys) {
        _colTitleCtrls[k]!.text = _fieldsMap[k]?.rawValue ?? '';
      }
      _lastBoundFieldId = null;
      _updateStudentFieldsData();
    });
  }

  bool _containsArabicUrdu(String text) {
    return RegExp(
            r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]')
        .hasMatch(text);
  }

  static const List<String> _urduFontFallback = [
    'Jameel Noori Nastaleeq',
    'Jameel Noori Kasheeda',
    'Urdu Typesetting',
    'Arabic Typesetting',
    'Amiri',
    'Segoe UI',
  ];

  /// High-DPI Vector/Image Rasterizer for Standalone Fields in PDF
  Future<Uint8List> _renderFieldToImage({
    required String text,
    required String fontFamily,
    required double fontSize,
    required Color color,
    required bool bold,
    required double boxWidthPt,
    required double boxHeightPt,
    required TextAlign textAlign,
    double pixelRatio = 3.0,
  }) async {
    final canvasW = (boxWidthPt * pixelRatio).ceilToDouble().clamp(1.0, 4000.0);
    final canvasH = (boxHeightPt * pixelRatio).ceilToDouble().clamp(1.0, 4000.0);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final textStyle = TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: _urduFontFallback,
      fontSize: fontSize * pixelRatio,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final isRtl = _cardLanguage == 'ur' || _cardLanguage == 'ar';
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: textAlign,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
    );

    textPainter.layout(maxWidth: canvasW);

    double dx = 0.0;
    if (textAlign == TextAlign.center) {
      dx = (canvasW - textPainter.width) / 2.0;
    } else if (textAlign == TextAlign.right) {
      dx = canvasW - textPainter.width;
    }
    double dy = (canvasH - textPainter.height) / 2.0;
    if (dy < 0) dy = 0.0;

    textPainter.paint(canvas, Offset(dx, dy));

    final picture = recorder.endRecording();
    final img = await picture.toImage(canvasW.toInt(), canvasH.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// High-DPI Rasterizer for Grading Scale Component in PDF Export
  Future<Uint8List> _renderGradingScaleToImage({
    required _FieldConfig f,
    required double boxWidthPt,
    required double boxHeightPt,
    double pixelRatio = 3.0,
  }) async {
    final canvasW = (boxWidthPt * pixelRatio).ceilToDouble().clamp(1.0, 4000.0);
    final canvasH = (boxHeightPt * pixelRatio).ceilToDouble().clamp(1.0, 4000.0);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final isRtl = _cardLanguage == 'ur' || _cardLanguage == 'ar';
    final textColor = f.color == Colors.transparent ? Colors.black87 : f.color;

    // Draw Outer Border
    final borderPaint = Paint()
      ..color = textColor.withAlpha(100)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * pixelRatio;

    final RRect outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2 * pixelRatio, 2 * pixelRatio, canvasW - 4 * pixelRatio, canvasH - 4 * pixelRatio),
      Radius.circular(6 * pixelRatio),
    );
    canvas.drawRRect(outerRect, borderPaint);

    // Header Title Box Background
    final headerBgPaint = Paint()
      ..color = textColor.withAlpha(25)
      ..style = PaintingStyle.fill;
    final headerH = (f.fontSize + 6) * pixelRatio;
    final headerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(4 * pixelRatio, 4 * pixelRatio, canvasW - 8 * pixelRatio, headerH),
      Radius.circular(4 * pixelRatio),
    );
    canvas.drawRRect(headerRect, headerBgPaint);

    // Header Text
    final titleStr = f.titlePrefix.trim().isNotEmpty ? f.titlePrefix.trim() : 'Grading Scale';
    final titleStyle = TextStyle(
      fontFamily: f.fontFamily,
      fontFamilyFallback: _urduFontFallback,
      fontSize: (f.fontSize * 0.90) * pixelRatio,
      fontWeight: FontWeight.bold,
      color: textColor,
    );
    final titlePainter = TextPainter(
      text: TextSpan(text: titleStr, style: titleStyle),
      textAlign: TextAlign.center,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout(maxWidth: canvasW - 12 * pixelRatio);

    titlePainter.paint(
      canvas,
      Offset((canvasW - titlePainter.width) / 2.0, 4 * pixelRatio + (headerH - titlePainter.height) / 2.0),
    );

    // Table Content Rules
    final rules = _configuredGradingRules.isNotEmpty ? _configuredGradingRules : GradingHelper.defaultRules;
    double currentY = headerH + 8 * pixelRatio;
    final availableH = canvasH - currentY - 6 * pixelRatio;
    final rowHeight = (availableH / rules.length).clamp(10.0 * pixelRatio, 40.0 * pixelRatio);

    final ruleStyle = TextStyle(
      fontFamily: _tableUrduFontFamily,
      fontFamilyFallback: _urduFontFallback,
      fontSize: (f.fontSize * 0.75) * pixelRatio,
      fontWeight: FontWeight.w600,
      color: textColor,
    );

    for (int i = 0; i < rules.length; i++) {
      final r = rules[i];
      final minStr = r.minPercent % 1 == 0 ? r.minPercent.toInt().toString() : r.minPercent.toStringAsFixed(1);
      final maxStr = r.maxPercent % 1 == 0 ? r.maxPercent.toInt().toString() : r.maxPercent.toStringAsFixed(1);
      final failLabel = _cardLanguage == 'ur' ? 'راسب' : (_cardLanguage == 'hi' ? 'अनुत्तीर्ण' : (_cardLanguage == 'gu' ? 'અનુત્તીર્ણ' : (_cardLanguage == 'ar' ? 'راسب' : (_cardLanguage == 'bn' ? 'ফেল' : 'Fail'))));
      final rangeTextRaw = (r.minPercent == 0 && r.maxPercent < 33)
          ? '$failLabel (< 33%)'
          : '$minStr% – $maxStr%';
      final rangeText = UrduNumberHelper.convertDigits(rangeTextRaw, _cardLanguage);

      // Left Column (Grade Name): e.g. A+ / ممتاز
      final gradePainter = TextPainter(
        text: TextSpan(text: r.grade, style: ruleStyle),
        textAlign: isRtl ? TextAlign.right : TextAlign.left,
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      )..layout(maxWidth: canvasW * 0.35);

      // Right Column (Range): e.g. 90% – 100%
      final rangePainter = TextPainter(
        text: TextSpan(text: rangeText, style: ruleStyle),
        textAlign: isRtl ? TextAlign.left : TextAlign.right,
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      )..layout(maxWidth: canvasW * 0.60);

      final yOffset = currentY + i * rowHeight + (rowHeight - gradePainter.height) / 2.0;

      if (isRtl) {
        gradePainter.paint(canvas, Offset(canvasW - 10 * pixelRatio - gradePainter.width, yOffset));
        rangePainter.paint(canvas, Offset(10 * pixelRatio, yOffset));
      } else {
        gradePainter.paint(canvas, Offset(10 * pixelRatio, yOffset));
        rangePainter.paint(canvas, Offset(canvasW - 10 * pixelRatio - rangePainter.width, yOffset));
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(canvasW.toInt(), canvasH.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// High-DPI Vector/Image Rasterizer for Table Cells in PDF
  Future<Uint8List> _renderTableCellToImage({
    required String text,
    required String fontFamily,
    required double fontSize,
    required Color color,
    required bool bold,
    double pixelRatio = 3.0,
  }) async {
    final textStyle = TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: _urduFontFallback,
      fontSize: fontSize * pixelRatio,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final isRtl = _cardLanguage == 'ur' || _cardLanguage == 'ar';
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
    );

    textPainter.layout();

    final canvasW = textPainter.width.ceilToDouble().clamp(1.0, 3000.0);
    final canvasH = textPainter.height.ceilToDouble().clamp(1.0, 3000.0);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    textPainter.paint(canvas, Offset.zero);

    final picture = recorder.endRecording();
    final img = await picture.toImage(canvasW.toInt(), canvasH.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

TextStyle _getCanvasTextStyle(_FieldConfig f, double fontScale) {
    return TextStyle(
      fontFamily: f.fontFamily,
      fontFamilyFallback: _urduFontFallback,
      fontSize: f.fontSize * fontScale,
      fontWeight: f.bold ? FontWeight.bold : FontWeight.normal,
      color: f.color == Colors.transparent ? Colors.black87 : f.color,
    );
  }

  Future<pw.Font> _getUrduPdfFont({bool isBold = false}) async {
    try {
      return isBold
          ? await PdfGoogleFonts.amiriBold()
          : await PdfGoogleFonts.amiriRegular();
    } catch (_) {
      return isBold
          ? await PdfGoogleFonts.poppinsBold()
          : await PdfGoogleFonts.poppinsRegular();
    }
  }

  Future<pw.Font> _resolvePdfFont(String fontName, bool isBold) async {
    final cn = fontName.toLowerCase().replaceAll(' ', '');

    if (cn.contains('nastaleeq') || cn.contains('jameel') || cn.contains('urdu') || cn.contains('arabic')) {
      return await _getUrduPdfFont(isBold: isBold);
    }

    final winFontsDir = 'C:\\Windows\\Fonts';
    final candidates = <String>[];

    if (cn.contains('segoe')) {
      candidates.add(isBold ? '$winFontsDir\\segoeuib.ttf' : '$winFontsDir\\segoeui.ttf');
    } else if (cn.contains('arial')) {
      candidates.add(isBold ? '$winFontsDir\\arialbd.ttf' : '$winFontsDir\\arial.ttf');
    } else if (cn.contains('calibri')) {
      candidates.add(isBold ? '$winFontsDir\\calibrib.ttf' : '$winFontsDir\\calibri.ttf');
    } else if (cn.contains('times')) {
      candidates.add(isBold ? '$winFontsDir\\timesbd.ttf' : '$winFontsDir\\times.ttf');
    } else if (cn.contains('georgia')) {
      candidates.add(isBold ? '$winFontsDir\\georgiab.ttf' : '$winFontsDir\\georgia.ttf');
    } else if (cn.contains('verdana')) {
      candidates.add(isBold ? '$winFontsDir\\verdanab.ttf' : '$winFontsDir\\verdana.ttf');
    } else if (cn.contains('tahoma')) {
      candidates.add(isBold ? '$winFontsDir\\tahomabd.ttf' : '$winFontsDir\\tahoma.ttf');
    } else if (cn.contains('century')) {
      candidates.addAll([
        isBold ? '$winFontsDir\\GOTHICB.TTF' : '$winFontsDir\\GOTHIC.TTF',
        '$winFontsDir\\CENTURY.TTF'
      ]);
    }

    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          return pw.Font.ttf(file.readAsBytesSync().buffer.asByteData());
        } catch (_) {}
      }
    }

    return isBold
        ? await PdfGoogleFonts.poppinsBold()
        : await PdfGoogleFonts.poppinsRegular();
  }

  PdfColor? _pdfBgColor(Color color) {
    if (color == Colors.transparent || color.opacity == 0.0 || color.value == 0) {
      return null;
    }
    return PdfColor.fromInt(color.toARGB32());
  }

  // ─── Windows Office / CorelDraw Style 2D Color Picker Dialog ───
  Future<Color?> _showAdvancedColorPicker(Color current) async {
    return showDialog<Color>(
      context: context,
      builder: (ctx) => _WindowsStyleColorPickerDialog(initialColor: current),
    );
  }

  // ─── PDF Export ────────────────────────────────────────────
  Future<void> _exportPdf({required String targetScope}) async {
    List<Student> exportPool;
    if (targetScope == 'single') {
      exportPool = [_currentStudent];
    } else if (targetScope == 'class') {
      exportPool = _filteredStudents.isNotEmpty ? _filteredStudents : _studentsList;
    } else {
      // Print All (All Students across all classes)
      if (widget.examResults != null && widget.examResults!.isNotEmpty) {
        exportPool = widget.examResults!.map((r) {
          return _studentsList.firstWhere(
            (s) => _matchStudentResult(r, s),
            orElse: () => Student(
              id: '${r['student_id'] ?? r['id'] ?? '1'}',
              registrationNumber: '${r['registration_number'] ?? r['gr_no'] ?? '101'}',
              fullName: '${r['student_name'] ?? r['full_name'] ?? 'Student'}',
              fatherName: r['father_name']?.toString() ?? '',
              surname: r['surname']?.toString() ?? '',
              className: '${r['class_name'] ?? ''}',
              address: r['address']?.toString() ?? '',
              mobileNo: r['mobile_no']?.toString() ?? r['mobile']?.toString() ?? '',
            ),
          );
        }).toList();
      } else {
        exportPool = _studentsList.isNotEmpty ? _studentsList : [_currentStudent];
      }
    }

    if (exportPool.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('⚠️ No students available to export PDF.'),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }

    // Show Progress Dialog for feedback
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 38,
                    height: 38,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.5,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PDF Export in Progress...',
                          style: AppTheme.getFontStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F766E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Generating Marksheets for ${exportPool.length} student(s)\nPlease wait...',
                          style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final pdf = pw.Document();
      final pdfW = _pageWidthMm * PdfPageFormat.mm;
      final pdfH = _pageHeightMm * PdfPageFormat.mm;
      final visCols = _visibleColumns;

      // Image render cache across student loop for superfast PDF generation
      final Map<String, Uint8List> renderCache = {};

      Future<Uint8List> getCachedFieldImage({
        required String text,
        required String fontFamily,
        required double fontSize,
        required Color color,
        required bool bold,
        required double boxWidthPt,
        required double boxHeightPt,
        required TextAlign textAlign,
      }) async {
        final cacheKey = 'F_${text}_${fontFamily}_${fontSize}_${color.toARGB32()}_${bold}_${boxWidthPt.toStringAsFixed(1)}_${boxHeightPt.toStringAsFixed(1)}_${textAlign.name}';
        if (renderCache.containsKey(cacheKey)) {
          return renderCache[cacheKey]!;
        }
        final bytes = await _renderFieldToImage(
          text: text,
          fontFamily: fontFamily,
          fontSize: fontSize,
          color: color,
          bold: bold,
          boxWidthPt: boxWidthPt,
          boxHeightPt: boxHeightPt,
          textAlign: textAlign,
        );
        renderCache[cacheKey] = bytes;
        return bytes;
      }

      Future<Uint8List> getCachedTableCellImage({
        required String text,
        required String fontFamily,
        required double fontSize,
        required Color color,
        required bool bold,
      }) async {
        final cacheKey = 'C_${text}_${fontFamily}_${fontSize}_${color.toARGB32()}_$bold';
        if (renderCache.containsKey(cacheKey)) {
          return renderCache[cacheKey]!;
        }
        final bytes = await _renderTableCellToImage(
          text: text,
          fontFamily: fontFamily,
          fontSize: fontSize,
          color: color,
          bold: bold,
        );
        renderCache[cacheKey] = bytes;
        return bytes;
      }

      // Load background templates if enabled
      Uint8List? bgFrontBytes;
      Uint8List? bgBackBytes;
      if (_useUploadedTemplate) {
        if (_uploadedTemplateImageFront != null && _uploadedTemplateImageFront!.existsSync()) {
          bgFrontBytes = _uploadedTemplateImageFront!.readAsBytesSync();
        }
        if (_uploadedTemplateImageBack != null && _uploadedTemplateImageBack!.existsSync()) {
          bgBackBytes = _uploadedTemplateImageBack!.readAsBytesSync();
        }
      }

      // Determine sides to print
      final List<String> sidesToPrint = [];
      if (_pdfPrintSide == 'both') {
        sidesToPrint.addAll(['front', 'back']);
      } else if (_pdfPrintSide == 'front') {
        sidesToPrint.add('front');
      } else {
        sidesToPrint.add('back');
      }

      // Pre-render Table Header cells
      final tableHeaderImages = <String, Uint8List>{};
      for (final col in visCols) {
        final colHeaderField = _fieldsMap['table_header_${col.key}'];
        final hdrFont = (colHeaderField != null && colHeaderField.fontFamily.isNotEmpty)
            ? colHeaderField.fontFamily
            : (_colFontFamily[col.key] ?? _tableFontFamily);
        final hdrFontSize = (colHeaderField != null) ? colHeaderField.fontSize : _tableHeaderFontSize;
        final hdrColor = (colHeaderField != null) ? colHeaderField.color : _tableHeaderTextColor;
        final hdrBold = (colHeaderField != null) ? colHeaderField.bold : _tableHeaderBold;

        final imgBytes = await getCachedTableCellImage(
          text: col.title,
          fontFamily: hdrFont,
          fontSize: hdrFontSize,
          color: _safeColor(hdrColor),
          bold: hdrBold,
        );
        tableHeaderImages[col.key] = imgBytes;
      }

      for (int i = 0; i < exportPool.length; i++) {
        final s = exportPool[i];
        final studentSubjects = _getSubjectsForStudent(s);
        final studentValues = _buildStudentFieldValues(s, studentSubjects);

        // 1. Render non-table text fields for Student s
        final renderedImages = <String, Uint8List>{};
        for (final f in _fieldsMap.values) {
          if (!f.visible || f.isTable) continue;

          if ((f.isPhoto || f.id == 'student_photo') && _uploadedStudentPhoto != null && _uploadedStudentPhoto!.existsSync()) {
            renderedImages[f.id] = _uploadedStudentPhoto!.readAsBytesSync();
            continue;
          }
          if (f.id == 'teacher_sign' && _uploadedTeacherSignature != null && _uploadedTeacherSignature!.existsSync()) {
            renderedImages[f.id] = _uploadedTeacherSignature!.readAsBytesSync();
            continue;
          }
          if (f.id == 'principal_sign' && _uploadedPrincipalSignature != null && _uploadedPrincipalSignature!.existsSync()) {
            renderedImages[f.id] = _uploadedPrincipalSignature!.readAsBytesSync();
            continue;
          }
          if ((f.isStamp || f.id == 'stamp') && _uploadedPrincipalStamp != null && _uploadedPrincipalStamp!.existsSync()) {
            renderedImages[f.id] = _uploadedPrincipalStamp!.readAsBytesSync();
            continue;
          }

          String valStr = studentValues[f.id] ?? f.rawValue;
          String txt = valStr;
          if (f.showTitlePrefix && f.titlePrefix.isNotEmpty) {
            txt = '${f.titlePrefix}$valStr';
          }
          if (f.id == 'gr_no') {
            if (_convertGrNoDigits) {
              txt = UrduNumberHelper.convertDigits(txt, _cardLanguage);
            }
          } else {
            txt = UrduNumberHelper.convertDigits(txt, _cardLanguage);
          }
          if (txt.trim().isEmpty) continue;

          final boxW_pt = f.widthMm * PdfPageFormat.mm;
          final boxH_pt = f.heightMm * PdfPageFormat.mm;
          final isHeaderField = f.id == 'bismillah' || f.id == 'institution' || f.id == 'sub_header' || f.id == 'session_info';
          final isRtl = _cardLanguage == 'ur' || _cardLanguage == 'ar';
          final txtAlign = isHeaderField
              ? TextAlign.center
              : (isRtl ? TextAlign.right : TextAlign.left);

          Uint8List imgBytes;
          if (f.id == 'grading_scale_title') {
            imgBytes = await _renderGradingScaleToImage(
              f: f,
              boxWidthPt: boxW_pt,
              boxHeightPt: boxH_pt,
            );
          } else {
            imgBytes = await getCachedFieldImage(
              text: txt,
              fontFamily: f.fontFamily,
              fontSize: f.fontSize,
              color: _safeColor(f.color),
              bold: f.bold,
              boxWidthPt: boxW_pt,
              boxHeightPt: boxH_pt,
              textAlign: txtAlign,
            );
          }
          renderedImages[f.id] = imgBytes;
        }

        // 2. Render Table Cells for Student s
        final tableCellImages = <String, Uint8List>{};
        for (int idx = 0; idx < studentSubjects.length; idx++) {
          final m = studentSubjects[idx];
          final rawObtStr = m.isAbsent ? 'ABSENT' : m.marksObtained.toStringAsFixed(0);
          final obtStr = UrduNumberHelper.convertDigits(rawObtStr, _cardLanguage);

          for (final col in visCols) {
            String cellTxt;
            double fSize = _getCellFontSize(col.key);
            bool isBold = _isCellBold(col.key);
            Color cVal = _tableRowTextColor;
            String cellFont = _colFontFamily[col.key] ?? _tableFontFamily;

            switch (col.key) {
              case 'col1':
                cellTxt = '${idx + 1}';
                break;
              case 'col2':
                cellTxt = m.bookName;
                cVal = _bookNameTextColor;
                if (!_colFontFamily.containsKey('col2') && _containsArabicUrdu(m.bookName)) cellFont = _tableUrduFontFamily;
                break;
              case 'col3':
                cellTxt = m.maxMarks.toInt().toString();
                break;
              case 'col4':
                cellTxt = m.minPass;
                break;
              case 'col5':
                cellTxt = obtStr;
                cVal = _getMarkColor(m.marksObtained, m.maxMarks, m.isAbsent);
                break;
              case 'col6':
                cellTxt = _getDynamicGrade(m.marksObtained, m.maxMarks, m.isAbsent, m.gradeName);
                final markColor = _getMarkColor(m.marksObtained, m.maxMarks, m.isAbsent);
                cVal = _getGradeColor(cellTxt, markColor);
                if (!_colFontFamily.containsKey('col6') && _containsArabicUrdu(cellTxt)) cellFont = _tableUrduFontFamily;
                break;
              default:
                cellTxt = '';
            }

            cellTxt = UrduNumberHelper.convertDigits(cellTxt, _cardLanguage);

            double cellFontSize = fSize;
            if (col.key == 'col6' || _containsArabicUrdu(cellTxt)) {
              cellFontSize = fSize * 1.7;
            }

            final key = '${col.key}_$idx';
            final imgBytes = await getCachedTableCellImage(
              text: cellTxt,
              fontFamily: cellFont,
              fontSize: cellFontSize,
              color: _safeColor(cVal),
              bold: isBold,
            );
            tableCellImages[key] = imgBytes;
          }
        }

      // Add pages for printed sides
      for (final currentSide in sidesToPrint) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(pdfW, pdfH, marginAll: 0),
            build: (pw.Context ctx) {
              final currentBgBytes = currentSide == 'front' ? bgFrontBytes : bgBackBytes;
              final List<pw.Widget> children = [
                pw.Container(
                  width: pdfW, height: pdfH,
                  decoration: pw.BoxDecoration(
                    color: _pdfBgColor(_pageBgColor),
                    border: pw.Border.all(
                        color: PdfColor.fromInt(_pageBorderColor.toARGB32()),
                        width: _pageBorderWidth),
                  ),
                  child: currentBgBytes != null
                      ? pw.Image(pw.MemoryImage(currentBgBytes), fit: pw.BoxFit.fill)
                      : null,
                ),
              ];

              final headerBg = _pdfBgColor(_headerBannerBg);
              if (headerBg != null && !_useUploadedTemplate && currentSide == 'front') {
                children.add(pw.Positioned(
                  left: pdfW * 0.035, top: pdfH * 0.025,
                  child: pw.Container(
                    width: pdfW * 0.93, height: pdfH * 0.110,
                    decoration: pw.BoxDecoration(
                      color: headerBg,
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                  ),
                ));
              }

              for (final f in _fieldsMap.values) {
                if (!f.visible) continue;
                if (f.side != currentSide) continue;
                if (f.id.startsWith('table_header_col')) continue;

                final posX = f.x * pdfW;
                final posY = f.y * pdfH;
                final boxW = f.widthMm * PdfPageFormat.mm;
                final boxH = f.heightMm * PdfPageFormat.mm;

                pw.Widget node;

                if (f.isTable && visCols.isNotEmpty) {
                  if (!_isTableGrouped) continue;
                  final isPdfRtl = _cardLanguage == 'ur' || _cardLanguage == 'ar';
                  final effectiveCols = isPdfRtl ? visCols.reversed.toList() : visCols;
                  final colWidths = <int, pw.FlexColumnWidth>{};
                  for (int ci = 0; ci < effectiveCols.length; ci++) {
                    colWidths[ci] =
                        pw.FlexColumnWidth(_colCustomFlex[effectiveCols[ci].key] ?? effectiveCols[ci].flex.toDouble());
                  }

                  node = pw.Container(
                    width: boxW,
                    child: pw.Table(
                      border: _tableGridWidth == 0.0
                          ? const pw.TableBorder()
                          : pw.TableBorder.all(
                              color: PdfColor.fromInt(_tableGridColor.toARGB32()),
                              width: _tableGridWidth),
                      columnWidths: colWidths,
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(
                            color: _pdfBgColor(_tableHeaderBg),
                          ),
                          children: effectiveCols.map((col) {
                            if (tableHeaderImages.containsKey(col.key)) {
                              final hdrFontSize = _fieldsMap['table_header_${col.key}']?.fontSize ?? _tableHeaderFontSize;
                              return pw.Padding(
                                padding: pw.EdgeInsets.symmetric(
                                    vertical: _rowCustomSpacing[-1] ?? _rowSpacing, horizontal: _colPadding),
                                child: pw.Align(
                                  alignment: (col.key == 'col1' || col.key == 'col3' || col.key == 'col4' || col.key == 'col5' || col.key == 'col6')
                                      ? pw.Alignment.center
                                      : ((_cardLanguage == 'ur' || _cardLanguage == 'ar')
                                          ? pw.Alignment.centerRight
                                          : pw.Alignment.centerLeft),
                                  child: pw.Image(
                                    pw.MemoryImage(tableHeaderImages[col.key]!),
                                    height: hdrFontSize + 2,
                                    fit: pw.BoxFit.contain,
                                  ),
                                ),
                              );
                            }
                            return pw.SizedBox();
                          }).toList(),
                        ),
                        ...List.generate(studentSubjects.length, (idx) {
                          return pw.TableRow(
                            decoration: pw.BoxDecoration(
                              color: (idx % 2 == 1) ? _pdfBgColor(_alternatingRowBgColor) : null,
                            ),
                            children: effectiveCols.map((col) {
                              final key = '${col.key}_$idx';
                              final fSize = _getCellFontSize(col.key);
                              if (tableCellImages.containsKey(key)) {
                                final isUrduCell = col.key == 'col6';
                                final imgH = isUrduCell ? (fSize * 1.5) : (fSize + 2);
                                final customRowPadding = _rowCustomSpacing[idx] ?? _rowSpacing;
                                return pw.Padding(
                                  padding: pw.EdgeInsets.symmetric(
                                      vertical: isUrduCell ? (customRowPadding * 0.8) : customRowPadding, horizontal: _colPadding),
                                  child: pw.Align(
                                    alignment: (col.key == 'col1' || col.key == 'col3' || col.key == 'col4' || col.key == 'col5' || col.key == 'col6')
                                        ? pw.Alignment.center
                                        : ((_cardLanguage == 'ur' || _cardLanguage == 'ar')
                                            ? pw.Alignment.centerRight
                                            : pw.Alignment.centerLeft),
                                    child: pw.Image(
                                      pw.MemoryImage(tableCellImages[key]!),
                                      height: imgH,
                                      fit: pw.BoxFit.contain,
                                    ),
                                  ),
                                );
                              }
                              return pw.SizedBox();
                            }).toList(),
                          );
                        }),
                      ],
                    ),
                  );
                } else if (!f.isTable) {
                  if (renderedImages.containsKey(f.id)) {
                    node = pw.Container(
                      width: boxW, height: boxH,
                      child: pw.Image(
                        pw.MemoryImage(renderedImages[f.id]!),
                        width: boxW, height: boxH,
                        fit: pw.BoxFit.fill,
                      ),
                    );
                  } else {
                    continue;
                  }
                } else {
                  continue;
                }

                children
                    .add(pw.Positioned(left: posX, top: posY, child: node));
              }

              if (!_isTableGrouped) {
                final tableSide = _fieldsMap['marks_table']?.side ?? 'front';
                if (currentSide == tableSide) {
                  for (final col in visCols) {
                    final cX = _colX[col.key] ?? 0.05;
                    final cY = _colY[col.key] ?? 0.25;
                    final cWidthMm = _colWidthMm[col.key] ?? 35.0;
                    final posX = cX * pdfW;
                    final posY = cY * pdfH;
                    final boxW = cWidthMm * PdfPageFormat.mm;

                    final colWidget = pw.Container(
                      width: boxW,
                      child: pw.Table(
                        border: _tableGridWidth == 0.0
                            ? const pw.TableBorder()
                            : pw.TableBorder.all(
                                color: PdfColor.fromInt(_tableGridColor.toARGB32()),
                                width: _tableGridWidth),
                        children: [
                          pw.TableRow(
                            decoration: pw.BoxDecoration(
                              color: _pdfBgColor(_tableHeaderBg),
                            ),
                            children: [
                              if (tableHeaderImages.containsKey(col.key))
                                pw.Padding(
                                  padding: pw.EdgeInsets.symmetric(
                                      vertical: _rowSpacing, horizontal: _colPadding),
                                  child: pw.Align(
                                    alignment: (col.key == 'col1' || col.key == 'col3' || col.key == 'col4' || col.key == 'col5' || col.key == 'col6')
                                        ? pw.Alignment.center
                                        : ((_cardLanguage == 'ur' || _cardLanguage == 'ar')
                                            ? pw.Alignment.centerRight
                                            : pw.Alignment.centerLeft),
                                    child: pw.Image(
                                      pw.MemoryImage(tableHeaderImages[col.key]!),
                                      height: (_fieldsMap['table_header_${col.key}']?.fontSize ?? _tableHeaderFontSize) + 2,
                                      fit: pw.BoxFit.contain,
                                    ),
                                  ),
                                )
                              else
                                pw.SizedBox(),
                            ],
                          ),
                          ...List.generate(studentSubjects.length, (idx) {
                            final key = '${col.key}_$idx';
                            final fSize = _getCellFontSize(col.key);
                            if (tableCellImages.containsKey(key)) {
                              final isUrduCell = col.key == 'col6';
                              final imgH = isUrduCell ? (fSize * 1.5) : (fSize + 2);
                              return pw.TableRow(
                                decoration: pw.BoxDecoration(
                                  color: (idx % 2 == 1) ? _pdfBgColor(_alternatingRowBgColor) : null,
                                ),
                                children: [
                                  pw.Padding(
                                    padding: pw.EdgeInsets.symmetric(
                                        vertical: isUrduCell ? 2 : _rowSpacing, horizontal: _colPadding),
                                   child: pw.Align(
                                    alignment: (col.key == 'col1' || col.key == 'col3' || col.key == 'col4' || col.key == 'col5' || col.key == 'col6')
                                        ? pw.Alignment.center
                                        : ((_cardLanguage == 'ur' || _cardLanguage == 'ar')
                                            ? pw.Alignment.centerRight
                                            : pw.Alignment.centerLeft),
                                      child: pw.Image(
                                        pw.MemoryImage(tableCellImages[key]!),
                                        height: imgH,
                                        fit: pw.BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            return pw.TableRow(children: [pw.SizedBox()]);
                          }),
                        ],
                      ),
                    );

                    children.add(pw.Positioned(left: posX, top: posY, child: colWidget));
                  }
                }
              }

              return pw.Stack(children: children);
            },
          ),
        );
      }
    }

    // Dismiss Progress Dialog
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    final fileName = exportPool.length > 1
        ? 'Marksheets_${targetScope}_${exportPool.length}_Students.pdf'
        : 'Marksheet_${_currentStudent.fullName.replaceAll(' ', '_')}.pdf';

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Result Cards PDF',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (savePath != null) {
      final pdfBytes = await pdf.save();
      await File(savePath).writeAsBytes(pdfBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ PDF successfully saved (${exportPool.length} Marksheets) to: $savePath',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF0D6B4E),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  } catch (e) {
    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('⚠️ Failed to generate PDF: $e',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: _buildTopHeader(isDark),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenW = constraints.maxWidth;
          final screenH = constraints.maxHeight;
          final isTabletOrMobile = screenW < 1000;

          if (isTabletOrMobile) {
            final activeRatio = _isBottomPanelExpanded ? _bottomPanelRatio.clamp(0.18, 0.88) : 0.06;
            final currentSheetHeight = (screenH * activeRatio).clamp(38.0, screenH * 0.90);

            return Stack(
              children: [
                // 100% Full Width Canvas Workspace
                Positioned.fill(
                  child: Stack(
                    children: [
                      _buildCanvasWorkspace(isDark),
                      Positioned(
                        right: 16,
                        bottom: _isBottomPanelExpanded ? currentSheetHeight + 12 : 54,
                        child: _buildZoomControls(isDark),
                      ),
                    ],
                  ),
                ),

                // Draggable & Collapsible Bottom Control Box / Drawer
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: currentSheetHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Draggable Bottom Sheet Bar Header (Ultra-Compact 38px)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (details) {
                            if (screenH <= 0) return;
                            final deltaRatio = details.delta.dy / screenH;
                            setState(() {
                              final newRatio = (_bottomPanelRatio - deltaRatio).clamp(0.06, 0.88);
                              _bottomPanelRatio = newRatio;
                              _isBottomPanelExpanded = newRatio > 0.10;
                            });
                          },
                          onTap: () {
                            setState(() {
                              if (_isBottomPanelExpanded) {
                                _isBottomPanelExpanded = false;
                              } else {
                                if (_bottomPanelRatio < 0.25) {
                                  _bottomPanelRatio = 0.50; // Open to half
                                }
                                _isBottomPanelExpanded = true;
                              }
                            });
                          },
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF0FDFA),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark ? Colors.white10 : const Color(0xFF0F766E).withAlpha(40),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Section Navigation Dropdown (at red mark in image 2!)
                                Container(
                                  height: 26,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white10 : Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF0F766E).withAlpha(120)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      value: _selectedTabIndex,
                                      icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF0F766E), size: 16),
                                      style: AppTheme.getFontStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF0F766E),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 0, child: Text('🎨 Readymade')),
                                        DropdownMenuItem(value: 1, child: Text('📐 Page Setup')),
                                        DropdownMenuItem(value: 2, child: Text('☑️ Fields')),
                                        DropdownMenuItem(value: 3, child: Text('✏️ Edit')),
                                        DropdownMenuItem(value: 4, child: Text('📊 Table')),
                                        DropdownMenuItem(value: 5, child: Text('🖨️ Print')),
                                        DropdownMenuItem(value: 6, child: Text('⚙️ Studio')),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setState(() {
                                            _selectedTabIndex = v;
                                            if (!_isBottomPanelExpanded) _isBottomPanelExpanded = true;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${(_bottomPanelRatio * 100).round()}%)',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Compact Front / Back Page Side Switcher
                                Container(
                                  height: 24,
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF0F766E).withAlpha(80)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          if (!_isFrontSide) setState(() => _isFrontSide = true);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _isFrontSide ? const Color(0xFF0F766E) : Colors.transparent,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Front',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: _isFrontSide ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          if (_isFrontSide) setState(() => _isFrontSide = false);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: !_isFrontSide ? const Color(0xFF0D6B4E) : Colors.transparent,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Back',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: !_isFrontSide ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F766E),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        _isBottomPanelExpanded ? 'Collapse' : 'Open Controls',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Icon(
                                        _isBottomPanelExpanded
                                            ? Icons.keyboard_arrow_down_rounded
                                            : Icons.keyboard_arrow_up_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Expanded Control Panel Content
                        if (_isBottomPanelExpanded)
                          Expanded(
                            child: _buildRightControlPanel(isDark),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // Desktop View (Width >= 1000px)
          final panelWidth = (screenW * 0.35).clamp(280.0, 380.0);
          return Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    _buildCanvasWorkspace(isDark),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: _buildZoomControls(isDark),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: panelWidth,
                child: Container(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  child: _buildRightControlPanel(isDark),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildTopHeader(bool isDark) {
    final pool = _filteredStudents;
    final screenW = MediaQuery.of(context).size.width;
    final isTabletOrMobile = screenW < 1000;

    if (isTabletOrMobile) {
      return AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 1.0,
        toolbarHeight: 40.0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Result Card Studio',
          style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
        ),
        actions: const [],
      );
    }

    return AppBar(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 1.5,
      titleSpacing: 8,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withAlpha(30),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.auto_awesome_mosaic_rounded,
                color: Color(0xFF0F766E), size: 22),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Result Card Studio',
                style: AppTheme.getFontStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            Text('Marksheet Designer',
                style: AppTheme.getFontStyle(fontSize: 10, color: Colors.grey)),
          ]),
        ]),
      ),
      actions: [
        SizedBox(
          width: (screenW - 220.0).clamp(100.0, 1200.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF0F766E).withAlpha(100)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _cardLanguage,
                          icon: const Icon(Icons.language_rounded, size: 15, color: Color(0xFF0F766E)),
                          style: AppTheme.getFontStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          items: UrduNumberHelper.supportedCardLanguages
                              .map((lang) => DropdownMenuItem<String>(
                                    value: lang['code'],
                                    child: Text('🌐 ${lang['name']}'),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _applyCardLanguage(v);
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_availableClasses.length > 1) ...[
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedClassFilter ?? 'ALL',
                            style: AppTheme.getFontStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87),
                            items: _availableClasses
                                .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                        c == 'ALL' ? 'All Classes' : 'Class $c')))
                                .toList(),
                            onChanged: (v) {
                              setState(() {
                                _selectedClassFilter = v;
                                _studentIndex = 0;
                                if (_filteredStudents.isNotEmpty) {
                                  _currentStudent = _filteredStudents.first;
                                  _updateStudentFieldsData();
                                }
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (pool.length > 1) ...[
                      IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: _studentIndex > 0
                              ? () => _switchStudent(_studentIndex - 1)
                              : null),
                      Text('${_studentIndex + 1}/${_filteredStudents.length}',
                          style: AppTheme.getFontStyle(
                              fontSize: 11.5, fontWeight: FontWeight.bold)),
                      IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: _studentIndex < pool.length - 1
                              ? () => _switchStudent(_studentIndex + 1)
                              : null),
                      const SizedBox(width: 6),
                    ],
                    IconButton(
                      icon: Icon(Icons.grid_on_rounded,
                          size: 18,
                          color: _showGridOverlay
                              ? const Color(0xFF0F766E)
                              : Colors.grey),
                      tooltip: 'Toggle Grid',
                      onPressed: () =>
                          setState(() => _showGridOverlay = !_showGridOverlay),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : const Color(0xFFF0FDFA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF0F766E).withAlpha(100)),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () {
                              if (!_isFrontSide) {
                                setState(() => _isFrontSide = true);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isFrontSide ? const Color(0xFF0D6B4E) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Front',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: _isFrontSide ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF0F766E)),
                                ),
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              if (_isFrontSide) {
                                setState(() => _isFrontSide = false);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: !_isFrontSide ? const Color(0xFF0D6B4E) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Back',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: !_isFrontSide ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF0F766E)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D6B4E),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                      onPressed: _saveCurrentTemplateToReadymade,
                      icon: const Icon(Icons.save_rounded,
                          size: 16, color: Colors.white),
                      label: const Text('Save',
                          style: TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                      onPressed: () => _exportPdf(targetScope: 'single'),
                      icon: const Icon(Icons.print_rounded,
                          size: 16, color: Colors.white),
                      label: const Text('Export PDF',
                          style: TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFrontBackSideSwitcher(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF0FDFA),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : const Color(0xFF0F766E).withAlpha(60),
            width: 1,
          ),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.flip_camera_android_rounded, size: 16, color: Color(0xFF0F766E)),
                const SizedBox(width: 6),
                Text(
                  'Page Side:',
                  style: AppTheme.getFontStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : const Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Container(
              height: 30,
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF0F766E).withAlpha(100)),
              ),
              padding: const EdgeInsets.all(2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (!_isFrontSide) {
                        setState(() {
                          _isFrontSide = true;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isFrontSide ? const Color(0xFF0D6B4E) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Front',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _isFrontSide ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (_isFrontSide) {
                        setState(() {
                          _isFrontSide = false;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: !_isFrontSide ? const Color(0xFF0D6B4E) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Back',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: !_isFrontSide ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalActionsTab(bool isDark) {
    final pool = _filteredStudents;
    final cardBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade300;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text(
          '⚙️ Studio Settings & Actions',
          style: AppTheme.getFontStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F766E),
          ),
        ),
        const SizedBox(height: 12),

        // 1. Language Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🌐 Card Language', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF0F766E).withAlpha(100)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _cardLanguage,
                    icon: const Icon(Icons.language_rounded, color: Color(0xFF0F766E)),
                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
                    items: UrduNumberHelper.supportedCardLanguages
                        .map((lang) => DropdownMenuItem<String>(
                              value: lang['code'],
                              child: Text('🌐 ${lang['name']}'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _applyCardLanguage(v));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2. Class Filter & Student Navigation Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🎓 Class Filter & Student Navigation', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_availableClasses.length > 1) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF0F766E).withAlpha(100)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: (_selectedClassFilter != null && _availableClasses.contains(_selectedClassFilter))
                          ? _selectedClassFilter
                          : (_availableClasses.contains('ALL') ? 'ALL' : _availableClasses.first),
                      icon: const Icon(Icons.filter_list_rounded, color: Color(0xFF0F766E)),
                      style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
                      items: _availableClasses
                          .map((c) => DropdownMenuItem<String>(
                                value: c,
                                child: Text(c == 'ALL' ? 'All Classes' : 'Class $c'),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedClassFilter = v;
                          _studentIndex = 0;
                          if (_filteredStudents.isNotEmpty) {
                            _currentStudent = _filteredStudents.first;
                            _updateStudentFieldsData();
                          }
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (pool.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: _studentIndex > 0
                          ? () {
                              setState(() {
                                _studentIndex--;
                                _currentStudent = pool[_studentIndex];
                                _updateStudentFieldsData();
                              });
                            }
                          : null,
                      icon: const Icon(Icons.arrow_back_ios_rounded, size: 13, color: Colors.white),
                      label: const Text('Prev', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    Text(
                      '${_studentIndex + 1} of ${pool.length}',
                      style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E)),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: _studentIndex < pool.length - 1
                          ? () {
                              setState(() {
                                _studentIndex++;
                                _currentStudent = pool[_studentIndex];
                                _updateStudentFieldsData();
                              });
                            }
                          : null,
                      icon: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.white),
                      label: const Text('Next', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 3. Template Actions (Save & Export PDF)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('💾 Save & Export Options', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D6B4E),
                        minimumSize: const Size(0, 38),
                      ),
                      onPressed: _saveCurrentTemplateToReadymade,
                      icon: const Icon(Icons.save_rounded, color: Colors.white, size: 16),
                      label: const Text('Save Template', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        minimumSize: const Size(0, 38),
                      ),
                      onPressed: () => _exportPdf(targetScope: 'single'),
                      icon: const Icon(Icons.print_rounded, color: Colors.white, size: 16),
                      label: const Text('Export PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedTabContent(int index, bool isDark) {
    switch (index) {
      case 0:
        return _buildReadymadeTab(isDark);
      case 1:
        return _buildMyTemplateTab(isDark);
      case 2:
        return _buildFieldsTab(isDark);
      case 3:
        return _buildEditTab(isDark);
      case 4:
        return _buildTableTab(isDark);
      case 5:
        return _buildExportPrintTab(isDark);
      case 6:
      default:
        return _buildGlobalActionsTab(isDark);
    }
  }

  Widget _buildRightControlPanel(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelW = constraints.maxWidth;
        final screenW = MediaQuery.of(context).size.width;
        final isTablet = screenW < 1000;
        final scale = (panelW / 360.0).clamp(0.75, 1.05);

        // On Tablet mode, horizontal TabBar is COMPLETELY REMOVED as requested!
        // The section dropdown in top header controls active tab view!
        if (isTablet) {
          return Container(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            child: KeyedSubtree(
              key: ValueKey(_selectedTabIndex),
              child: _buildSelectedTabContent(_selectedTabIndex, isDark),
            ),
          );
        }

        // Desktop View (screenW >= 1000px): Standard 7-Tab TabBar + TabBarView
        final tabHeight = (46.0 * scale).clamp(42.0, 50.0);
        final tabFontSize = (11.5 * scale).clamp(10.0, 12.0);
        final tabIconSize = (15.5 * scale).clamp(14.0, 16.0);
        final tabPadding = (8.0 * scale).clamp(4.0, 8.0);

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: DefaultTabController(
            length: 7,
            child: Column(
              children: [
                Container(
                  height: tabHeight,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white10 : Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                  ),
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    labelPadding: EdgeInsets.symmetric(horizontal: tabPadding),
                    indicatorColor: const Color(0xFF0F766E),
                    indicatorWeight: 2.5 * scale,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: const Color(0xFF0F766E),
                    unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    labelStyle: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: tabFontSize),
                    unselectedLabelStyle: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: tabFontSize),
                    tabs: [
                      Tab(
                        iconMargin: const EdgeInsets.only(bottom: 1),
                        icon: Icon(Icons.style_rounded, size: tabIconSize),
                        text: 'Readymade',
                      ),
                      Tab(
                        iconMargin: const EdgeInsets.only(bottom: 1),
                        icon: Icon(Icons.aspect_ratio_rounded, size: tabIconSize),
                        text: 'Page Setup',
                      ),
                      Tab(
                        iconMargin: const EdgeInsets.only(bottom: 1),
                        icon: Icon(Icons.check_box_rounded, size: tabIconSize),
                        text: 'Fields',
                      ),
                      Tab(
                        iconMargin: const EdgeInsets.only(bottom: 1),
                        icon: Icon(Icons.edit_note_rounded, size: tabIconSize),
                        text: 'Edit',
                      ),
                      Tab(
                        iconMargin: const EdgeInsets.only(bottom: 1),
                        icon: Icon(Icons.table_chart_rounded, size: tabIconSize),
                        text: 'Table',
                      ),
                      Tab(
                        iconMargin: const EdgeInsets.only(bottom: 1),
                        icon: Icon(Icons.print_rounded, size: tabIconSize),
                        text: 'Print',
                      ),
                      Tab(
                        iconMargin: const EdgeInsets.only(bottom: 1),
                        icon: Icon(Icons.tune_rounded, size: tabIconSize),
                        text: 'Studio',
                      ),
                    ],
                  ),
                ),
                _buildFrontBackSideSwitcher(isDark),
                Expanded(
                  child: TabBarView(children: [
                    _buildReadymadeTab(isDark),
                    _buildMyTemplateTab(isDark),
                    _buildFieldsTab(isDark),
                    _buildEditTab(isDark),
                    _buildTableTab(isDark),
                    _buildExportPrintTab(isDark),
                    _buildGlobalActionsTab(isDark),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Tab 1: Readymade ──────────────────────────────────────
  Widget _buildReadymadeTab(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text('📐 Built-in & Saved Templates',
          style: AppTheme.getFontStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: textColor)),
      const SizedBox(height: 10),
      _readymadeCard('Golden Amber Royal',
          'Classic Gold Header with Emerald Table', const Color(0xFFD97706), isDark),
      _readymadeCard('Executive Sapphire Navy',
          'Navy Blue Header with Sky Highlights', const Color(0xFF0369A1), isDark),
      _readymadeCard('Crimson Ruby Gold',
          'Crimson Header with Warm Cream Accents', const Color(0xFF881337), isDark),
      if (_readymadeTemplatesList.isNotEmpty) ...[
        const Divider(height: 24),
        Text('⭐ User Saved Templates',
            style: AppTheme.getFontStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F766E))),
        const SizedBox(height: 8),
        ..._readymadeTemplatesList.asMap().entries.map((entry) {
          final idx = entry.key;
          final t = entry.value;
          final name = t['name'] ?? 'Saved Template';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(name,
                  style: AppTheme.getFontStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: Text('Paper: ${t['paper'] ?? 'A4'}',
                  style: AppTheme.getFontStyle(
                      fontSize: 10.5, color: Colors.grey)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E)),
                    onPressed: () => _loadTemplatePayload(t),
                    child: const Text('Apply',
                        style:
                            TextStyle(color: Colors.white, fontSize: 10.5)),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                    onPressed: () => _deleteTemplate(idx, name),
                    tooltip: 'Delete Template',
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    ]);
  }

  Widget _readymadeCard(
      String name, String desc, Color primary, bool isDark) {
    return Card(
      elevation: 0,
      color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: primary.withAlpha(120))),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: primary, radius: 12),
            const SizedBox(width: 8),
            Text(name,
                style: AppTheme.getFontStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
          const SizedBox(height: 4),
          Text(desc,
              style: AppTheme.getFontStyle(fontSize: 10.5, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
              onPressed: () {
                _applyPaperPreset('A4');
                setState(() => _headerBannerBg = primary);
              },
              child: const Text('Apply A4',
                  style: TextStyle(fontSize: 10.5, color: Colors.white)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
              onPressed: () {
                _applyPaperPreset('B5');
                setState(() => _headerBannerBg = primary);
              },
              child: const Text('Apply B5',
                  style: TextStyle(fontSize: 10.5, color: Colors.white)),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Tab 2: My Template ────────────────────────────────────
  Widget _buildMyTemplateTab(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📄 Active Card Side',
            style: AppTheme.getFontStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F766E))),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Center(
                  child: Text('Front Side',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
                selected: _isFrontSide,
                selectedColor: const Color(0xFF0F766E),
                onSelected: (s) {
                  if (s) setState(() => _isFrontSide = true);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Center(
                  child: Text('Back Side',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
                selected: !_isFrontSide,
                selectedColor: const Color(0xFF0F766E),
                onSelected: (s) {
                  if (s) setState(() => _isFrontSide = false);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('🌐 Result Card Language',
            style: AppTheme.getFontStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F766E))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : const Color(0xFFF0FDFA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF0F766E).withAlpha(100)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _cardLanguage,
              style: AppTheme.getFontStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87),
              items: UrduNumberHelper.supportedCardLanguages
                  .map((lang) => DropdownMenuItem<String>(
                        value: lang['code'],
                        child: Text('🌐 ${lang['name']} (${lang['nativeName']})'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _applyCardLanguage(v);
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text('Convert G.R. No. Digits:',
                  style: AppTheme.getFontStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: textColor)),
            ),
            Switch(
              value: _convertGrNoDigits,
              activeColor: const Color(0xFF0F766E),
              onChanged: (v) {
                setState(() {
                  _convertGrNoDigits = v;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('📐 Page Presets',
            style: AppTheme.getFontStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F766E))),
        const SizedBox(height: 8),
        Wrap(
            spacing: 6,
            runSpacing: 6,
            children: ['A4', 'B5', 'A5', 'Letter', 'Legal']
                .map((p) => ChoiceChip(
                      label: Text(p,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                      selected: _selectedPaperPreset == p,
                      selectedColor: const Color(0xFF0F766E),
                      onSelected: (_) => _applyPaperPreset(p),
                    ))
                .toList()),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text('Orientation:',
                style: AppTheme.getFontStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: textColor)),
            ChoiceChip(
              label: const Text('Portrait',
                  style:
                      TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
              selected: !_isLandscape,
              selectedColor: const Color(0xFF0F766E),
              onSelected: (s) {
                if (s && _isLandscape) {
                  setState(() {
                    _isLandscape = false;
                    final tmp = _pageWidthMm;
                    _pageWidthMm = _pageHeightMm;
                    _pageHeightMm = tmp;
                  });
                }
              },
            ),
            ChoiceChip(
              label: const Text('Landscape',
                  style:
                      TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
              selected: _isLandscape,
              selectedColor: const Color(0xFF0F766E),
              onSelected: (s) {
                if (s && !_isLandscape) {
                  setState(() {
                    _isLandscape = true;
                    final tmp = _pageWidthMm;
                    _pageWidthMm = _pageHeightMm;
                    _pageHeightMm = tmp;
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sliderRow('Width (mm)', _pageWidthMm, 50, 450,
            (v) => setState(() => _pageWidthMm = v), isDark),
        _sliderRow('Height (mm)', _pageHeightMm, 50, 500,
            (v) => setState(() => _pageHeightMm = v), isDark),
        const Divider(height: 24),
        Text('📇 Card Page Outer Border & Background',
            style: AppTheme.getFontStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F766E))),
        const SizedBox(height: 8),
        _colorRowPicker('Card Page Background Color', _pageBgColor, (c) => setState(() => _pageBgColor = c), isDark),
        const SizedBox(height: 6),
        _colorRowPicker('Card Outer Border Color', _pageBorderColor, (c) => setState(() => _pageBorderColor = c), isDark),
        const SizedBox(height: 6),
        _sliderRow('Page Border Width (mm)', _pageBorderWidth, 0.0, 10.0, (v) => setState(() => _pageBorderWidth = v), isDark),
        const SizedBox(height: 6),
        _sliderRow('Page Corner Radius', _borderRadius, 0.0, 30.0, (v) => setState(() => _borderRadius = v), isDark),
        const Divider(height: 24),
        Text('📷 Upload Background Templates',
            style: AppTheme.getFontStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F766E))),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(vertical: 10)),
                onPressed: () => _pickExternalTemplateImage(isFront: true),
                icon: const Icon(Icons.upload_file_rounded, color: Colors.white, size: 18),
                label: Text(
                    _uploadedTemplateImageFront == null
                        ? 'Front Background'
                        : 'Change Front Bg',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(vertical: 10)),
                onPressed: () => _pickExternalTemplateImage(isFront: false),
                icon: const Icon(Icons.upload_file_rounded, color: Colors.white, size: 18),
                label: Text(
                    _uploadedTemplateImageBack == null
                        ? 'Back Background'
                        : 'Change Back Bg',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ),
          ],
        ),
        if (_uploadedTemplateImageFront != null || _uploadedTemplateImageBack != null || _useUploadedTemplate) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () {
                setState(() {
                  _uploadedTemplateImageFront = null;
                  _uploadedTemplateImageBack = null;
                  _useUploadedTemplate = false;
                });
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
              label: const Text('🗑️ Clear Uploaded Background',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Tab 3: Fields ─────────────────────────────────────────
  Widget _buildDateAndHijriSettingsCard(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final formattedStr = _buildFormattedDateText();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0F766E).withAlpha(100), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xFF0F766E)),
              const SizedBox(width: 6),
              Text('📅 Card Issue Date & Hijri Settings',
                  style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
            ],
          ),
          const SizedBox(height: 10),

          // Date Picker Row
          Row(
            children: [
              Expanded(
                child: Text('Gregorian Date:', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _customCardDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2050),
                  );
                  if (picked != null) {
                    setState(() {
                      _customCardDate = picked;
                      _updateCardDateFieldValue();
                    });
                  }
                },
                icon: const Icon(Icons.edit_calendar_rounded, size: 14, color: Colors.white),
                label: Text(
                  '${_customCardDate.day}/${_customCardDate.month}/${_customCardDate.year}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Show Hijri Switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Enable Hijri Date:', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor)),
              Switch(
                value: _showHijriDate,
                activeColor: const Color(0xFF0F766E),
                onChanged: (v) {
                  setState(() {
                    _showHijriDate = v;
                    _updateCardDateFieldValue();
                  });
                },
              ),
            ],
          ),

          if (_showHijriDate) ...[
            const SizedBox(height: 6),
            Text('Quick Hijri Moon Offset:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [-2, -1, 0, 1, 2].map((offset) {
                final isSel = _hijriOffsetDays == offset && _manualHijriOverrideText.isEmpty;
                final label = offset == 0 ? '0 (Auto)' : (offset > 0 ? '+$offset Day' : '$offset Day');
                return ChoiceChip(
                  label: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isSel ? Colors.white : textColor)),
                  selected: isSel,
                  selectedColor: const Color(0xFF0F766E),
                  onSelected: (_) => setState(() {
                    _hijriOffsetDays = offset;
                    _manualHijriOverrideText = '';
                    _updateCardDateFieldValue();
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text('Manual Hijri Text Override:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 4),
            TextField(
              controller: _hijriTextCtrl,
              style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'مثلاً: ۵ صفر ۱۴۴۸ھـ (خالی رکھنے پر خود بخود حساب ہوگا)',
                hintStyle: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                filled: true,
                fillColor: isDark ? Colors.white10 : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
              ),
              onChanged: (val) {
                setState(() {
                  _manualHijriOverrideText = val;
                  _updateCardDateFieldValue();
                });
              },
            ),
          ],

          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF0F766E).withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.preview_rounded, size: 15, color: Color(0xFF0F766E)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Card Date Result: $formattedStr', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldsTab(bool isDark) {
    final fields = _fieldsMap.values.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildDateAndHijriSettingsCard(isDark),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text('📋 Enable / Disable & Side Options',
                style: AppTheme.getFontStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F766E))),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
              onPressed: _addCustomTextField,
              icon: const Icon(Icons.add_rounded,
                  size: 16, color: Colors.white),
              label: const Text('+ Custom Text',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...fields.map((f) => _fieldCheckboxTile(f, isDark)),
      ]),
    );
  }

  // ── Tab 4: Edit ───────────────────────────────────────────
  Widget _buildEditTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectedFieldEditor(isDark),
        ],
      ),
    );
  }

  Widget _fieldCheckboxTile(_FieldConfig f, bool isDark) {
    final selected = _selectedFieldId == f.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF0F766E).withAlpha(25)
            : (isDark ? Colors.white10 : Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xFF0F766E) : Colors.grey.shade300,
          width: selected ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: f.visible,
            activeColor: const Color(0xFF0F766E),
            onChanged: (v) => setState(() => f.visible = v ?? true),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedFieldId = f.id;
                  _lastBoundFieldId = null;
                });
              },
              child: Text(
                f.label,
                style: AppTheme.getFontStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: f.side == 'front'
                  ? const Color(0xFF0F766E).withAlpha(30)
                  : Colors.amber.withAlpha(30),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: f.side == 'front'
                    ? const Color(0xFF0F766E)
                    : Colors.amber.shade700,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: f.side,
                isDense: true,
                style: AppTheme.getFontStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87),
                items: const [
                  DropdownMenuItem(value: 'front', child: Text('Front')),
                  DropdownMenuItem(value: 'back', child: Text('Back')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      f.side = val;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedFieldEditor(bool isDark) {
    _selectedFieldId ??= 'institution';
    final currentTargetId = _selectedFieldId!;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    final universalItems = <Map<String, String>>[
      // Header Elements
      {'id': 'institution', 'label': '🏫 Institution Header Title'},
      {'id': 'bismillah', 'label': '﷽ Bismillah Calligraphy'},
      {'id': 'sub_header', 'label': '📜 Sub Header Title'},
      {'id': 'session_info', 'label': '📅 Exam Session & Class'},

      // Student Details
      {'id': 'name', 'label': '👤 Student Name'},
      {'id': 'father', 'label': '👴 Father Name'},
      {'id': 'class', 'label': '📚 Class / Darja'},
      {'id': 'card_date', 'label': '📅 Date of Issue'},
      {'id': 'card_hijri_date', 'label': '🌙 Hijri Date'},
      {'id': 'total_students', 'label': '👥 Total Class Students'},
      {'id': 'total_absent', 'label': '❌ Total Absents Count'},
      {'id': 'gr_no', 'label': '🔢 GR / Reg Number'},
      {'id': 'dob', 'label': '🎂 Date of Birth'},
      {'id': 'address', 'label': '🏠 Address'},
      {'id': 'mobile_no', 'label': '📱 Mobile Number'},

      // Table Header Titles
      {'id': 'table_header_col1', 'label': '📊 Table Col 1 Header (# / S.R.)'},
      {'id': 'table_header_col2', 'label': '📊 Table Col 2 Header (Subject / Book Name)'},
      {'id': 'table_header_col3', 'label': '📊 Table Col 3 Header (Max Marks)'},
      {'id': 'table_header_col4', 'label': '📊 Table Col 4 Header (Min Pass)'},
      {'id': 'table_header_col5', 'label': '📊 Table Col 5 Header (Obtained Marks)'},
      {'id': 'table_header_col6', 'label': '📊 Table Col 6 Header (Grade)'},

      // Table Data Columns & Categories
      {'id': 'table_col1_text', 'label': '🔢 Table Col 1 Text (# S.R. Numbers)'},
      {'id': 'table_col2_text', 'label': '📖 Table Col 2 Text (Subject / Book Names)'},
      {'id': 'table_col3_text', 'label': '🎯 Table Col 3 Text (Max Marks Values)'},
      {'id': 'table_col4_text', 'label': '✅ Table Col 4 Text (Min Pass Values)'},
      {'id': 'table_col5_text', 'label': '💯 Table Col 5 Text (Obtained Marks Values)'},
      {'id': 'table_col6_text', 'label': '🌟 Table Col 6 Text (Grade Values)'},
      {'id': 'marks_table', 'label': '📋 Overall Subjects Table Layout'},

      // Results & Summary
      {'id': 'total_marks', 'label': '📈 Total Marks Summary Text'},
      {'id': 'percentage', 'label': '📊 Percentage Summary Text'},
      {'id': 'overall_grade', 'label': '🏆 Overall Grade Text'},
      {'id': 'position_rank', 'label': '🥇 Position / Rank Text'},
      {'id': 'result_status', 'label': '✅ Result Status Badge'},
      {'id': 'grading_scale_title', 'label': '📏 Grading Scale Title'},

      // Signatures & Stamp
      {'id': 'teacher_sign', 'label': '✍️ Teacher Signature'},
      {'id': 'principal_sign', 'label': '✍️ Principal Signature'},
      {'id': 'stamp', 'label': '🏵️ Official Stamp / Seal'},
      {'id': 'footer_note', 'label': '📝 Footer Disclaimer Note'},
    ];

    for (final entry in _fieldsMap.entries) {
      if (entry.value.isCustomText && !universalItems.any((item) => item['id'] == entry.key)) {
        universalItems.add({'id': entry.key, 'label': '📝 ${entry.value.label}'});
      }
    }

    final activeItem = universalItems.firstWhere(
      (item) => item['id'] == currentTargetId,
      orElse: () => {'id': currentTargetId, 'label': _fieldsMap[currentTargetId]?.label ?? currentTargetId},
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDFA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF0F766E).withAlpha(120), width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0284C7).withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mouse_rounded, size: 18, color: Color(0xFF0284C7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🎯 Selected Object: ${activeItem['label']}',
                          style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '💡 Mouse Selection: Click any text/table object on canvas to edit it!',
                          style: AppTheme.getFontStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),

            _buildUniversalEditorControls(currentTargetId, isDark, textColor),
          ],
        ),
      ),
    );
  }

  Widget _buildUniversalEditorControls(String targetId, bool isDark, Color textColor) {
    if (_fieldsMap.containsKey(targetId)) {
      final f = _fieldsMap[targetId]!;
      _bindFieldEditorControllers(targetId);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('Enable Field:',
                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
              ),
              Switch(
                value: f.visible,
                activeColor: const Color(0xFF0F766E),
                onChanged: (v) {
                  setState(() {
                    f.visible = v;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('Card Side:',
                  style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChoiceChip(
                    label: const Text('Front', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    selected: f.side == 'front',
                    selectedColor: const Color(0xFF0F766E),
                    onSelected: (s) {
                      if (s) setState(() => f.side = 'front');
                    },
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('Back', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    selected: f.side == 'back',
                    selectedColor: const Color(0xFF0F766E),
                    onSelected: (s) {
                      if (s) setState(() => f.side = 'back');
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (targetId == 'gr_no') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Convert G.R. No. Digits:',
                      style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor)),
                ),
                Switch(
                  value: _convertGrNoDigits,
                  activeColor: const Color(0xFF0F766E),
                  onChanged: (v) {
                    setState(() {
                      _convertGrNoDigits = v;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (targetId == 'name') ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text('Name Format:', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: textColor)),
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
                            f.isCombinedName = false;
                            _updateStudentFieldsData();
                            _applyCardLanguage(_cardLanguage);
                          });
                        },
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
                        onTap: () {
                          setState(() {
                            f.isCombinedName = true;
                            _updateStudentFieldsData();
                            _applyCardLanguage(_cardLanguage);
                          });
                        },
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
            const SizedBox(height: 8),
          ],
          if (targetId == 'address') ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text('Address Format:', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: textColor)),
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
                            f.isCombinedAddress = false;
                            _updateStudentFieldsData();
                            _applyCardLanguage(_cardLanguage);
                          });
                        },
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
                        onTap: () {
                          setState(() {
                            f.isCombinedAddress = true;
                            _updateStudentFieldsData();
                            _applyCardLanguage(_cardLanguage);
                          });
                        },
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
            const SizedBox(height: 8),
          ],
          if (targetId == 'class') ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text('Class Format:', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: textColor)),
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
                            f.showDivisionInClass = false;
                            _updateStudentFieldsData();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: !f.showDivisionInClass ? const Color(0xFF0D6B4E) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Class Only',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: !f.showDivisionInClass ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            f.showDivisionInClass = true;
                            _updateStudentFieldsData();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: f.showDivisionInClass ? const Color(0xFF0D6B4E) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Class + Division',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: f.showDivisionInClass ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (!f.isTable && !f.isPhoto && !f.isSignature && !f.isStamp) ...[
            Row(
              children: [
                Text('Display Text',
                    style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                if (targetId == 'grading_scale_title') ...[
                  const Spacer(),
                  InkWell(
                    onTap: _loadConfiguredGradingRules,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        children: const [
                          Icon(Icons.sync_rounded, size: 14, color: Color(0xFF0F766E)),
                          SizedBox(width: 4),
                          Text('Sync Grade Scale 🔄', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _fieldTextCtrl,
              maxLines: targetId == 'grading_scale_title' ? 6 : 1,
              style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: isDark ? Colors.white10 : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              ),
              onChanged: (v) {
                f.rawValue = v;
                setState(() {
                  if (!f.isTable && !f.isPhoto && !f.isSignature && !f.isStamp) {
                    _fitBoxToText(targetId);
                  }
                });
              },
            ),
            const SizedBox(height: 12),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Show Title / Prefix:',
                  style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
              Switch(
                value: f.showTitlePrefix,
                activeColor: const Color(0xFF0F766E),
                onChanged: (v) {
                  setState(() {
                    f.showTitlePrefix = v;
                    if (!f.isTable && !f.isPhoto && !f.isSignature && !f.isStamp) {
                      _fitBoxToText(targetId);
                    }
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (f.showTitlePrefix) ...[
            Text('Title / Prefix Text',
                style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            TextField(
              controller: _titlePrefixCtrl,
              style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                filled: true,
                fillColor: isDark ? Colors.white10 : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              ),
              onChanged: (v) {
                f.titlePrefix = v;
                setState(() {
                  if (!f.isTable && !f.isPhoto && !f.isSignature && !f.isStamp) {
                    _fitBoxToText(targetId);
                  }
                });
              },
            ),
            const SizedBox(height: 12),
          ],

          _SearchableFontDropdown(
            label: 'Font Family${_fontsLoaded ? ' (${_allFontFamilies.length} fonts)' : ' (loading...)'}',
            currentFont: f.fontFamily,
            fontFamilies: _allFontFamilies,
            isDark: isDark,
            onSelected: (font) {
              setState(() {
                f.fontFamily = font;
                if (targetId.startsWith('table_header_col')) {
                  final colKey = targetId.replaceAll('table_header_', '');
                  _colFontFamily[colKey] = font;
                }
                if (!f.isTable && !f.isPhoto && !f.isSignature && !f.isStamp) {
                  _fitBoxToText(targetId);
                }
              });
            },
          ),
          const SizedBox(height: 12),

          _numericValueRow('Font Size', f.fontSize, 6, 72, (v) {
            setState(() {
              f.fontSize = v;
              if (targetId.startsWith('table_header_col')) {
                _tableHeaderFontSize = v;
              }
              if (!f.isTable && !f.isPhoto && !f.isSignature && !f.isStamp) {
                _fitBoxToText(targetId);
              }
            });
          }, isDark),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Bold:', style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
              Switch(
                value: f.bold,
                activeColor: const Color(0xFF0F766E),
                onChanged: (v) {
                  setState(() {
                    f.bold = v;
                    if (targetId.startsWith('table_header_col')) {
                      _tableHeaderBold = v;
                    }
                    if (!f.isTable && !f.isPhoto && !f.isSignature && !f.isStamp) {
                      _fitBoxToText(targetId);
                    }
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(children: [
            Text('Text Color', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor)),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
              icon: const Icon(Icons.color_lens_rounded, size: 16, color: Color(0xFF0F766E)),
              label: const Text('2D Color Picker 🎨', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
              onPressed: () async {
                final c = await _showAdvancedColorPicker(f.color);
                if (c != null) {
                  setState(() {
                    f.color = c;
                    _updateHexCtrl(c);
                    if (targetId.startsWith('table_header_col')) {
                      _tableHeaderTextColor = c;
                    }
                  });
                }
              },
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _colorPalette.map((c) {
              final isTrans = c == Colors.transparent;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    f.color = c;
                    _updateHexCtrl(c);
                    if (targetId.startsWith('table_header_col')) {
                      _tableHeaderTextColor = c;
                    }
                  });
                },
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: f.color == c ? const Color(0xFF0F766E) : Colors.grey.shade400, width: f.color == c ? 2.5 : 1),
                  ),
                  child: isTrans ? const Icon(Icons.block, size: 10, color: Colors.red) : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _fieldHexCtrl,
            style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(width: 14, height: 14, color: f.color),
              ),
              filled: true,
              fillColor: isDark ? Colors.white10 : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
            onChanged: (val) {
              final clean = val.replaceAll('#', '');
              if (clean.length == 6) {
                try {
                  final parsed = int.parse('FF$clean', radix: 16);
                  setState(() {
                    f.color = Color(parsed);
                    if (targetId.startsWith('table_header_col')) {
                      _tableHeaderTextColor = Color(parsed);
                    }
                  });
                } catch (_) {}
              }
            },
          ),
          const SizedBox(height: 12),
          const Divider(height: 18),

          // ── Text Box Resizing Section ──
          Text('📐 Text Box Resizing & Dimensions',
              style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
          const SizedBox(height: 8),

          _sliderRow('Box Width (mm)', f.widthMm, 10.0, _pageWidthMm, (v) => setState(() => f.widthMm = double.parse(v.toStringAsFixed(1))), isDark),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Quick Width: ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              InkWell(
                onTap: () => setState(() => f.widthMm = (f.widthMm - 5.0).clamp(10.0, _pageWidthMm)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                  child: const Text('-5mm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() => f.widthMm = (f.widthMm + 5.0).clamp(10.0, _pageWidthMm)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                  child: const Text('+5mm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() => f.widthMm = (f.widthMm + 15.0).clamp(10.0, _pageWidthMm)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                  child: const Text('+15mm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          _sliderRow('Box Height (mm)', f.heightMm, 5.0, 150.0, (v) => setState(() => f.heightMm = double.parse(v.toStringAsFixed(1))), isDark),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Quick Height: ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              InkWell(
                onTap: () => setState(() => f.heightMm = (f.heightMm - 2.0).clamp(5.0, 150.0)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                  child: const Text('-2mm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() => f.heightMm = (f.heightMm + 2.0).clamp(5.0, 150.0)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                  child: const Text('+2mm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() => f.heightMm = (f.heightMm + 5.0).clamp(5.0, 150.0)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                  child: const Text('+5mm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Size Presets
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ActionChip(
                backgroundColor: const Color(0xFF0F766E).withAlpha(30),
                label: const Text('📐 Small (60mm)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                onPressed: () => setState(() => f.widthMm = 60.0),
              ),
              ActionChip(
                backgroundColor: const Color(0xFF0F766E).withAlpha(30),
                label: const Text('📐 Medium (110mm)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                onPressed: () => setState(() => f.widthMm = 110.0),
              ),
              ActionChip(
                backgroundColor: const Color(0xFF0F766E).withAlpha(30),
                label: const Text('📐 Large (150mm)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                onPressed: () => setState(() => f.widthMm = 150.0),
              ),
              ActionChip(
                backgroundColor: const Color(0xFF0F766E).withAlpha(30),
                label: const Text('📐 Full Width (190mm)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                onPressed: () => setState(() => f.widthMm = 190.0),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (!f.isTable && !f.isPhoto && !f.isSignature && !f.isStamp) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => _fitBoxToText(targetId),
                icon: const Icon(Icons.fit_screen_rounded, size: 15, color: Colors.white),
                label: const Text('✨ Fit Box to Text',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
          ],

          _numericValueRow('X Position (mm)', f.x * _pageWidthMm, 0, _pageWidthMm, (v) => setState(() => f.x = (v / _pageWidthMm).clamp(0.0, 0.98)), isDark),
          _numericValueRow('Y Position (mm)', f.y * _pageHeightMm, 0, _pageHeightMm, (v) => setState(() => f.y = (v / _pageHeightMm).clamp(0.0, 0.98)), isDark),
          const Divider(height: 20),

          // ── Alignment & Placement Controls ──
          Text('🧭 Alignment & Placement',
              style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () => setState(() => f.x = 0.035),
                  icon: const Icon(Icons.align_horizontal_left_rounded, size: 14),
                  label: const Text('Left', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () => setState(() {
                    final boxWFrac = f.widthMm / _pageWidthMm;
                    f.x = ((1.0 - boxWFrac) / 2.0).clamp(0.0, 0.95);
                  }),
                  icon: const Icon(Icons.align_horizontal_center_rounded, size: 14),
                  label: const Text('Center H', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () => setState(() {
                    final boxWFrac = f.widthMm / _pageWidthMm;
                    f.x = (1.0 - boxWFrac - 0.035).clamp(0.0, 0.95);
                  }),
                  icon: const Icon(Icons.align_horizontal_right_rounded, size: 14),
                  label: const Text('Right', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () => setState(() => f.y = 0.035),
                  icon: const Icon(Icons.align_vertical_top_rounded, size: 14),
                  label: const Text('Top', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () => setState(() {
                    final boxHFrac = f.heightMm / _pageHeightMm;
                    f.y = ((1.0 - boxHFrac) / 2.0).clamp(0.0, 0.95);
                  }),
                  icon: const Icon(Icons.align_vertical_center_rounded, size: 14),
                  label: const Text('Center V', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                  onPressed: () => setState(() {
                    final boxHFrac = f.heightMm / _pageHeightMm;
                    f.y = (1.0 - boxHFrac - 0.035).clamp(0.0, 0.95);
                  }),
                  icon: const Icon(Icons.align_vertical_bottom_rounded, size: 14),
                  label: const Text('Bottom', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),

          if (targetId == 'card_date' || targetId == 'card_hijri_date') ...[
            const Divider(height: 20),
            _buildDateAndHijriSettingsCard(isDark),
          ],

          if (f.isPhoto || f.isSignature || f.isStamp || targetId == 'student_photo' || targetId == 'teacher_sign' || targetId == 'principal_sign' || targetId == 'stamp') ...[
            const Divider(height: 20),
            Text(
              targetId == 'student_photo' || f.id == 'student_photo'
                  ? '📷 Student Photo Upload'
                  : (targetId == 'teacher_sign' || f.id == 'teacher_sign'
                      ? '✍️ Teacher Signature Upload'
                      : (targetId == 'principal_sign' || f.id == 'principal_sign'
                          ? '✍️ Principal Signature Upload'
                          : '🏵️ Official Stamp Upload')),
              style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E)),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
              onPressed: () async {
                final res = await FilePicker.platform.pickFiles(type: FileType.image);
                if (res != null && res.files.single.path != null) {
                  setState(() {
                    final file = File(res.files.single.path!);
                    if (targetId == 'student_photo' || f.id == 'student_photo') {
                      _uploadedStudentPhoto = file;
                    } else if (targetId == 'teacher_sign' || f.id == 'teacher_sign') {
                      _uploadedTeacherSignature = file;
                    } else if (targetId == 'principal_sign' || f.id == 'principal_sign') {
                      _uploadedPrincipalSignature = file;
                    } else if (targetId == 'stamp' || f.id == 'stamp') {
                      _uploadedPrincipalStamp = file;
                    }
                  });
                }
              },
              icon: const Icon(Icons.upload_file_rounded, color: Colors.white, size: 16),
              label: Text(
                targetId == 'student_photo' || f.id == 'student_photo'
                    ? 'Upload Student Photo'
                    : (targetId == 'teacher_sign' || f.id == 'teacher_sign'
                        ? 'Upload Teacher Signature'
                        : (targetId == 'principal_sign' || f.id == 'principal_sign'
                            ? 'Upload Principal Signature'
                            : 'Upload Official Stamp')),
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
          ],

          if (targetId == 'institution' || targetId == 'bismillah' || targetId == 'sub_header' || targetId == 'session_info') ...[
            const Divider(height: 20),
            Text('🎨 Header Banner Background Color',
                style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
            const SizedBox(height: 8),
            _colorRowPicker('Header Banner BG Color', _headerBannerBg, (c) {
              setState(() {
                _headerBannerBg = c;
              });
            }, isDark),
          ],


        ],
      );
    }

    if (targetId.startsWith('table_col') || targetId.startsWith('col_')) {
      final colKey = targetId.replaceAll('table_', '').replaceAll('_text', '').replaceAll('col_', 'col');
      final currentFont = _colFontFamily[colKey] ?? ((colKey == 'col2' || colKey == 'col6') ? _tableUrduFontFamily : _tableFontFamily);

      double colFontSize;
      bool colBold = false;
      Color colTextColor;

      switch (colKey) {
        case 'col1': colFontSize = _tableCol1FontSize; colTextColor = _tableRowTextColor; break;
        case 'col2': colFontSize = _bookNameFontSize; colBold = _bookNameBold; colTextColor = _bookNameTextColor; break;
        case 'col3': colFontSize = _col3FontSize; colBold = _col3Bold; colTextColor = _col3TextColor; break;
        case 'col4': colFontSize = _col4FontSize; colBold = _col4Bold; colTextColor = _col4TextColor; break;
        case 'col5': colFontSize = _tableObtainedFontSize; colBold = _tableObtainedBold; colTextColor = _tableMarksTextColor; break;
        case 'col6': colFontSize = _tableGradeFontSize; colBold = _tableGradeBold; colTextColor = _tableGradeTextColor; break;
        default: colFontSize = _tableRowFontSize; colTextColor = _tableRowTextColor; break;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchableFontDropdown(
            label: 'Column Font Family',
            currentFont: currentFont,
            fontFamilies: _allFontFamilies,
            isDark: isDark,
            onSelected: (font) => setState(() => _colFontFamily[colKey] = font),
          ),
          const SizedBox(height: 12),

          _sliderRow('Font Size', colFontSize, 6, 36, (v) {
            setState(() {
              switch (colKey) {
                case 'col1': _tableCol1FontSize = v; break;
                case 'col2': _bookNameFontSize = v; break;
                case 'col3': _col3FontSize = v; break;
                case 'col4': _col4FontSize = v; break;
                case 'col5': _tableObtainedFontSize = v; break;
                case 'col6': _tableGradeFontSize = v; break;
              }
            });
          }, isDark),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Bold:', style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
              Switch(
                value: colBold,
                activeColor: const Color(0xFF0F766E),
                onChanged: (v) {
                  setState(() {
                    switch (colKey) {
                      case 'col2': _bookNameBold = v; break;
                      case 'col3': _col3Bold = v; break;
                      case 'col4': _col4Bold = v; break;
                      case 'col5': _tableObtainedBold = v; break;
                      case 'col6': _tableGradeBold = v; break;
                    }
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(children: [
            Text('Text Color', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor)),
            const Spacer(),
            GestureDetector(
              onTap: () async {
                final c = await _showAdvancedColorPicker(colTextColor);
                if (c != null) {
                  setState(() {
                    switch (colKey) {
                      case 'col1': _tableRowTextColor = c; break;
                      case 'col2': _bookNameTextColor = c; break;
                      case 'col3': _col3TextColor = c; break;
                      case 'col4': _col4TextColor = c; break;
                      case 'col5': _tableMarksTextColor = c; break;
                      case 'col6': _tableGradeTextColor = c; break;
                    }
                  });
                }
              },
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(color: colTextColor, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade400, width: 1.5)),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          _sliderRow('Column Width (mm)', _colWidthMm[colKey] ?? 35.0, 10, 150, (v) {
            setState(() {
              _colWidthMm[colKey] = v;
              _colCustomFlex[colKey] = v;
            });
          }, isDark),
          const SizedBox(height: 8),

          const Divider(height: 20),
          Text('↔️ Table Row & Column Distance', style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF0F766E).withAlpha(100)),
            ),
            child: Column(
              children: [
                _sliderRow('Row Height / Spacing (mm)', _rowSpacing, 0.0, 25.0, (v) => setState(() => _rowSpacing = v), isDark),
                const SizedBox(height: 6),
                _sliderRow('Column Spacing (mm)', _colPadding, 0.0, 25.0, (v) => setState(() => _colPadding = v), isDark),
                const SizedBox(height: 6),
                _sliderRow('Grid Line Thickness (mm)', _tableGridWidth, 0.0, 5.0, (v) => setState(() => _tableGridWidth = v), isDark),
              ],
            ),
          ),
          const SizedBox(height: 10),



          if (colKey == 'col2') ...[
            const Divider(height: 16),
            Text('📖 Edit Subject / Book Names:', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
            const SizedBox(height: 6),
            ..._tableSubjects.map((sub) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TextField(
                controller: sub.bookNameCtrl,
                style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  sub.bookName = val;
                  setState(() {});
                },
              ),
            )),
          ],
        ],
      );
    }

    // Case 3: Target is Overall Table (marks_table) in Fields Tab
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Quick Size Presets ── (Red Box 1)
        Text('📐 Quick Size Presets', style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: [
            {'label': 'Compact', 'key': 'compact'},
            {'label': 'Standard', 'key': 'standard'},
            {'label': 'Large / Bold', 'key': 'large'},
            {'label': 'Ultra HD', 'key': 'ultrahd'},
          ].map((p) => ChoiceChip(
            label: Text(p['label']!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            selected: false,
            onSelected: (_) => _applyTableSizePreset(p['key']!),
          )).toList(),
        ),
        const Divider(height: 20),

        // ── Grid Lines & Smart Object Snapping Controls ──
        Text('🛈 Grid Lines & Smart Snapping',
            style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : const Color(0xFFF0FDFA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF0F766E).withAlpha(80)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('🧲 Snap to Grid & Objects:', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor)),
                  Switch(
                    value: _enableSnapToGrid,
                    activeColor: const Color(0xFF0F766E),
                    onChanged: (v) => setState(() => _enableSnapToGrid = v),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('🌐 Show Grid Lines:', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor)),
                  Switch(
                    value: _showGridOverlay,
                    activeColor: const Color(0xFF0F766E),
                    onChanged: (v) => setState(() => _showGridOverlay = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Grid Line Count / Density:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => setState(() {
                        _showGridOverlay = true;
                        _gridSpacingMm = (_gridSpacingMm - 2.5).clamp(2.0, 50.0);
                      }),
                      icon: const Icon(Icons.add_rounded, size: 14, color: Colors.white),
                      label: const Text('➕ Increase Lines', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                      onPressed: () => setState(() {
                        _showGridOverlay = true;
                        _gridSpacingMm = (_gridSpacingMm + 2.5).clamp(2.0, 50.0);
                      }),
                      icon: const Icon(Icons.remove_rounded, size: 14),
                      label: const Text('➖ Decrease Lines', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 4,
                children: [2.0, 5.0, 10.0, 15.0, 20.0].map((step) {
                  final isSelected = (_gridSpacingMm - step).abs() < 0.5;
                  return ChoiceChip(
                    label: Text('${step.toInt()} mm', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : textColor)),
                    selected: isSelected,
                    selectedColor: const Color(0xFF0F766E),
                    onSelected: (_) => setState(() {
                      _showGridOverlay = true;
                      _gridSpacingMm = step;
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              _sliderRow('Grid Line Density / Spacing (mm)', _gridSpacingMm, 2.0, 50.0, (v) => setState(() => _gridSpacingMm = v), isDark),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Table Scaling & Dimensions ──
        Text('📏 Table Scaling, Width & Height',
            style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
        const SizedBox(height: 8),
        _sliderRow('Table Scale %', _tableScaleFactor, 50, 150, (v) => _onTableScaleChanged(v), isDark),
        const SizedBox(height: 6),
        _sliderRow('Table Width (mm)', _tableWidthMm, 50, 300, (v) => setState(() {
          _tableWidthMm = v;
          if (_fieldsMap.containsKey('marks_table')) _fieldsMap['marks_table']!.widthMm = v;
        }), isDark),
        const SizedBox(height: 6),
        _sliderRow('Table Height (mm)', _tableHeightMm, 10, 250, (v) => setState(() {
          _tableHeightMm = v;
          if (_fieldsMap.containsKey('marks_table')) _fieldsMap['marks_table']!.heightMm = v;
        }), isDark),
        const SizedBox(height: 6),

        if (_fieldsMap.containsKey('marks_table')) ...[
          _sliderRow('X Position (mm)', _fieldsMap['marks_table']!.x * _pageWidthMm, 0, _pageWidthMm, (v) => setState(() => _fieldsMap['marks_table']!.x = (v / _pageWidthMm).clamp(0.0, 0.98)), isDark),
          const SizedBox(height: 6),
          _sliderRow('Y Position (mm)', _fieldsMap['marks_table']!.y * _pageHeightMm, 0, _pageHeightMm, (v) => setState(() => _fieldsMap['marks_table']!.y = (v / _pageHeightMm).clamp(0.0, 0.98)), isDark),
        ],
        const Divider(height: 20),

        // ── Table Colors & Style ──
        Text('🎨 Table Colors & Style',
            style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
        const SizedBox(height: 8),
        _colorRowPicker('Header Background Color', _tableHeaderBg, (c) => setState(() => _tableHeaderBg = c), isDark),
        const SizedBox(height: 6),
        _colorRowPicker('Header Text Color', _tableHeaderTextColor, (c) => setState(() => _tableHeaderTextColor = c), isDark),
        const SizedBox(height: 6),
        _colorRowPicker('Subject / Book Name Color', _bookNameTextColor, (c) => setState(() => _bookNameTextColor = c), isDark),
        const SizedBox(height: 6),
        _colorRowPicker('General Cells Color (#, Max, Min)', _tableRowTextColor, (c) => setState(() => _tableRowTextColor = c), isDark),
        const SizedBox(height: 6),
        _colorRowPicker('Default Marks Text Color', _tableMarksTextColor, (c) => setState(() => _tableMarksTextColor = c), isDark),
        const SizedBox(height: 6),
        _colorRowPicker('Default Grade Text Color', _tableGradeTextColor, (c) => setState(() => _tableGradeTextColor = c), isDark),
        const SizedBox(height: 6),
        _colorRowPicker('Alternating Row Stripe Color', _alternatingRowBgColor, (c) => setState(() => _alternatingRowBgColor = c), isDark),
        const Divider(height: 20),

        // ── Table Typography & Fonts ──
        Text('🔤 Table Typography & Fonts',
            style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
        const SizedBox(height: 8),
        _SearchableFontDropdown(
          label: 'Table General Font',
          currentFont: _tableFontFamily,
          fontFamilies: _allFontFamilies,
          isDark: isDark,
          onSelected: (font) => setState(() => _tableFontFamily = font),
        ),
        const SizedBox(height: 10),
        _SearchableFontDropdown(
          label: 'Table Urdu & Grade Font',
          currentFont: _tableUrduFontFamily,
          fontFamilies: _allFontFamilies,
          isDark: isDark,
          onSelected: (font) => setState(() => _tableUrduFontFamily = font),
        ),
      ],
    );
  }

  Widget _buildTableColorsSection(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0F766E).withAlpha(100), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded, size: 18, color: Color(0xFF0F766E)),
              const SizedBox(width: 6),
              Text('🎨 Table Colors & Border Settings',
                  style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
            ],
          ),
          const SizedBox(height: 10),

          // Table Selection (Table 1 vs Table 2 if Table 2 enabled)
          if (_enableSecondTable && _selectedTableSection != 'page') ...[
            Text('Select Table to Format:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedTableForColor == 1 ? const Color(0xFF0F766E) : (isDark ? Colors.white10 : Colors.grey.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    onPressed: () => setState(() => _selectedTableForColor = 1),
                    icon: Icon(Icons.table_chart_rounded, size: 14, color: _selectedTableForColor == 1 ? Colors.white : textColor),
                    label: Text('Table 1', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _selectedTableForColor == 1 ? Colors.white : textColor)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedTableForColor == 2 ? const Color(0xFF0F766E) : (isDark ? Colors.white10 : Colors.grey.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    onPressed: () => setState(() => _selectedTableForColor = 2),
                    icon: Icon(Icons.table_chart_rounded, size: 14, color: _selectedTableForColor == 2 ? Colors.white : textColor),
                    label: Text('Table 2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _selectedTableForColor == 2 ? Colors.white : textColor)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Section Selector Tabs (Header, Rows, Total Row, Page Outer)
          Text('Select Table Section to Edit:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.table_rows_outlined, size: 14, color: Colors.white),
                label: Text('📌 Header', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _selectedTableSection == 'header' ? Colors.white : textColor)),
                selected: _selectedTableSection == 'header',
                selectedColor: const Color(0xFF0F766E),
                onSelected: (_) => setState(() => _selectedTableSection = 'header'),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.reorder_rounded, size: 14, color: Colors.white),
                label: Text('📄 Data Rows', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _selectedTableSection == 'rows' ? Colors.white : textColor)),
                selected: _selectedTableSection == 'rows',
                selectedColor: const Color(0xFF0F766E),
                onSelected: (_) => setState(() => _selectedTableSection = 'rows'),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.summarize_rounded, size: 14, color: Colors.white),
                label: Text('📊 Total Row', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _selectedTableSection == 'total' ? Colors.white : textColor)),
                selected: _selectedTableSection == 'total',
                selectedColor: const Color(0xFF0F766E),
                onSelected: (_) => setState(() => _selectedTableSection = 'total'),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.border_outer_rounded, size: 14, color: Colors.white),
                label: Text('🔳 Table Outer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _selectedTableSection == 'outer' ? Colors.white : textColor)),
                selected: _selectedTableSection == 'outer',
                selectedColor: const Color(0xFF0F766E),
                onSelected: (_) => setState(() => _selectedTableSection = 'outer'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Contextual Color & Border Pickers based on _selectedTableSection & _selectedTableForColor
          if (_selectedTableSection == 'header') ...[
            Text('📌 Header Colors & Border', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
            const SizedBox(height: 6),
            if (_selectedTableForColor == 1) ...[
              _colorRowPicker('Header Background Color', _tableHeaderBg, (c) => setState(() => _tableHeaderBg = c), isDark),
              const SizedBox(height: 6),
              _colorRowPicker('Header Text Color', _tableHeaderTextColor, (c) => setState(() => _tableHeaderTextColor = c), isDark),
              const SizedBox(height: 6),
              _buildBorderSidePicker(
                label: 'Header Border Options',
                currentSide: _table1HeaderBorderSide,
                onChanged: (side) => setState(() => _table1HeaderBorderSide = side),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _colorRowPicker('Header Border Color', _table1HeaderBorderColor, (c) => setState(() => _table1HeaderBorderColor = c), isDark),
              const SizedBox(height: 6),
              _sliderRow('Header Border Thickness (mm)', _table1HeaderBorderWidth, 0.0, 5.0, (v) => setState(() => _table1HeaderBorderWidth = v), isDark),
            ] else ...[
              _colorRowPicker('Table 2 Header Background Color', _table2HeaderBg, (c) => setState(() => _table2HeaderBg = c), isDark),
              const SizedBox(height: 6),
              _colorRowPicker('Table 2 Header Text Color', _table2HeaderTextColor, (c) => setState(() => _table2HeaderTextColor = c), isDark),
              const SizedBox(height: 6),
              _buildBorderSidePicker(
                label: 'Table 2 Header Border Options',
                currentSide: _table2HeaderBorderSide,
                onChanged: (side) => setState(() => _table2HeaderBorderSide = side),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _colorRowPicker('Table 2 Header Border Color', _table2HeaderBorderColor, (c) => setState(() => _table2HeaderBorderColor = c), isDark),
              const SizedBox(height: 6),
              _sliderRow('Table 2 Header Border Thickness (mm)', _table2HeaderBorderWidth, 0.0, 5.0, (v) => setState(() => _table2HeaderBorderWidth = v), isDark),
            ],
          ] else if (_selectedTableSection == 'rows') ...[
            Text('📄 Data Rows Colors & Grid Border', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
            const SizedBox(height: 6),
            if (_selectedTableForColor == 1) ...[
              _colorRowPicker('Odd Row Background', _table1OddRowBgColor, (c) => setState(() => _table1OddRowBgColor = c), isDark),
              const SizedBox(height: 6),
              _colorRowPicker('Odd Row Text Color', _tableRowTextColor, (c) => setState(() => _tableRowTextColor = c), isDark),
              const SizedBox(height: 6),
              _colorRowPicker('Even Banded Row Background', _alternatingRowBgColor, (c) => setState(() => _alternatingRowBgColor = c), isDark),
              const SizedBox(height: 6),
              _colorRowPicker('Even Row Text Color', _bookNameTextColor, (c) => setState(() => _bookNameTextColor = c), isDark),
              const SizedBox(height: 6),
              _buildBorderSidePicker(
                label: 'Data Rows Border Options',
                currentSide: _table1RowsBorderSide,
                onChanged: (side) => setState(() => _table1RowsBorderSide = side),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _colorRowPicker('Grid Lines Border Color', _tableGridColor, (c) => setState(() => _tableGridColor = c), isDark),
              const SizedBox(height: 6),
              _sliderRow('Grid Lines Thickness (mm)', _tableGridWidth, 0.0, 5.0, (v) => setState(() => _tableGridWidth = v), isDark),
            ] else ...[
              _colorRowPicker('Table 2 Odd Row Background', _table2OddRowBgColor, (c) => setState(() => _table2OddRowBgColor = c), isDark),
              const SizedBox(height: 6),
              _colorRowPicker('Table 2 Odd Row Text Color', _table2OddRowTextColor, (c) => setState(() => _table2OddRowTextColor = c), isDark),
              const SizedBox(height: 6),
              _colorRowPicker('Table 2 Even Banded Row Background', _table2EvenRowBgColor, (c) => setState(() => _table2EvenRowBgColor = c), isDark),
              const SizedBox(height: 6),
              _colorRowPicker('Table 2 Even Row Text Color', _table2EvenRowTextColor, (c) => setState(() => _table2EvenRowTextColor = c), isDark),
              const SizedBox(height: 6),
              _buildBorderSidePicker(
                label: 'Table 2 Data Rows Border Options',
                currentSide: _table2RowsBorderSide,
                onChanged: (side) => setState(() => _table2RowsBorderSide = side),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _colorRowPicker('Table 2 Grid Lines Border Color', _table2GridColor, (c) => setState(() => _table2GridColor = c), isDark),
              const SizedBox(height: 6),
              _sliderRow('Table 2 Grid Lines Thickness (mm)', _table2GridWidth, 0.0, 5.0, (v) => setState(() => _table2GridWidth = v), isDark),
            ],
          ] else if (_selectedTableSection == 'total') ...[
            Text('📊 Total Summary Colors & Border', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
            const SizedBox(height: 6),
            if (_selectedTableForColor == 1) ...[
              _colorRowPicker('Total Row Background', _totalRowBgColor, (c) => setState(() => _totalRowBgColor = c), isDark),
              const SizedBox(height: 6),
              _colorRowPicker('Total Row Text Color', _totalRowTextColor, (c) => setState(() => _totalRowTextColor = c), isDark),
              const SizedBox(height: 6),
              _buildBorderSidePicker(
                label: 'Total Row Border Options',
                currentSide: _table1TotalBorderSide,
                onChanged: (side) => setState(() => _table1TotalBorderSide = side),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _colorRowPicker('Total Border Color', _table1TotalBorderColor, (c) => setState(() => _table1TotalBorderColor = c), isDark),
              const SizedBox(height: 6),
              _sliderRow('Total Border Thickness (mm)', _table1TotalBorderWidth, 0.0, 5.0, (v) => setState(() => _table1TotalBorderWidth = v), isDark),
            ] else ...[
              _colorRowPicker('Table 2 Total Row Background', _table2TotalRowBgColor, (c) => setState(() => _table2TotalRowBgColor = c), isDark),
              const SizedBox(height: 6),
              _colorRowPicker('Table 2 Total Row Text Color', _table2TotalRowTextColor, (c) => setState(() => _table2TotalRowTextColor = c), isDark),
              const SizedBox(height: 6),
              _buildBorderSidePicker(
                label: 'Table 2 Total Row Border Options',
                currentSide: _table2TotalBorderSide,
                onChanged: (side) => setState(() => _table2TotalBorderSide = side),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _colorRowPicker('Table 2 Total Top Border Color', _table2TotalBorderColor, (c) => setState(() => _table2TotalBorderColor = c), isDark),
              const SizedBox(height: 6),
              _sliderRow('Table 2 Total Border Thickness (mm)', _table2TotalBorderWidth, 0.0, 5.0, (v) => setState(() => _table2TotalBorderWidth = v), isDark),
            ],
          ] else if (_selectedTableSection == 'outer') ...[
            Text('🔳 Table Outer Box & Border', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
            const SizedBox(height: 6),
            if (_selectedTableForColor == 1) ...[
              _colorRowPicker('Table 1 Background Color', _table1BgColor, (c) => setState(() => _table1BgColor = c), isDark),
              const SizedBox(height: 6),
              _buildBorderSidePicker(
                label: 'Table 1 Outer Border Options',
                currentSide: _table1OuterBorderSide,
                onChanged: (side) => setState(() => _table1OuterBorderSide = side),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _colorRowPicker('Table 1 Outer Border Color', _table1OuterBorderColor, (c) => setState(() => _table1OuterBorderColor = c), isDark),
              const SizedBox(height: 6),
              _sliderRow('Table 1 Outer Border Thickness (mm)', _table1OuterBorderWidth, 0.0, 5.0, (v) => setState(() => _table1OuterBorderWidth = v), isDark),
              const SizedBox(height: 6),
              _sliderRow('Table 1 Corner Radius', _table1CornerRadius, 0.0, 30.0, (v) => setState(() => _table1CornerRadius = v), isDark),
            ] else ...[
              _colorRowPicker('Table 2 Background Color', _table2BgColor, (c) => setState(() => _table2BgColor = c), isDark),
              const SizedBox(height: 6),
              _buildBorderSidePicker(
                label: 'Table 2 Outer Border Options',
                currentSide: _table2OuterBorderSide,
                onChanged: (side) => setState(() => _table2OuterBorderSide = side),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _colorRowPicker('Table 2 Outer Border Color', _table2OuterBorderColor, (c) => setState(() => _table2OuterBorderColor = c), isDark),
              const SizedBox(height: 6),
              _sliderRow('Table 2 Outer Border Thickness (mm)', _table2OuterBorderWidth, 0.0, 5.0, (v) => setState(() => _table2OuterBorderWidth = v), isDark),
              const SizedBox(height: 6),
              _sliderRow('Table 2 Corner Radius', _table2CornerRadius, 0.0, 30.0, (v) => setState(() => _table2CornerRadius = v), isDark),
            ],
          ],
        ],
      ),
    );
  }

  // ── Tab 4: Table Tab (Layout Mode, Visible Columns, Dynamic Grade Text Labels & Subjects) ─────────
  Widget _buildTableTab(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTableColorsSection(isDark),
          const SizedBox(height: 12),

          // ── Group / Ungroup Table Columns Switch ──
          Text('🔗 Table Layout Mode',
              style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF0F766E).withAlpha(60)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isTableGrouped ? const Color(0xFF0F766E) : Colors.transparent,
                      elevation: _isTableGrouped ? 2 : 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => setState(() {
                      _isTableGrouped = true;
                      _selectedColKey = null;
                    }),
                    icon: Icon(Icons.link_rounded, size: 16, color: _isTableGrouped ? Colors.white : Colors.grey),
                    label: Text('🔗 Grouped Table', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _isTableGrouped ? Colors.white : textColor)),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_isTableGrouped ? const Color(0xFF0284C7) : Colors.transparent,
                      elevation: !_isTableGrouped ? 2 : 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => setState(() {
                      _isTableGrouped = false;
                    }),
                    icon: Icon(Icons.link_off_rounded, size: 16, color: !_isTableGrouped ? Colors.white : Colors.grey),
                    label: Text('🔓 Ungroup Columns', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: !_isTableGrouped ? Colors.white : textColor)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Multi-Table & Mizan Summary Controls ──
          Text('📊 Multi-Table & Summary Settings',
              style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF0F766E).withAlpha(80)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.table_rows_rounded, size: 16, color: Color(0xFF0F766E)),
                        const SizedBox(width: 6),
                        Text('Enable 2 Tables:',
                            style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor)),
                      ],
                    ),
                    Switch(
                      value: _enableSecondTable,
                      activeColor: const Color(0xFF0F766E),
                      onChanged: (v) => setState(() {
                        _enableSecondTable = v;
                        if (_fieldsMap.containsKey('marks_table_2')) {
                          _fieldsMap['marks_table_2']!.visible = v;
                        }
                      }),
                    ),
                  ],
                ),
                if (_enableSecondTable) ...[
                  const Divider(height: 12),
                  Text('Dual Tables Layout Presets:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                          onPressed: () => setState(() {
                            final t1 = _fieldsMap['marks_table'];
                            final t2 = _fieldsMap['marks_table_2'];
                            if (t1 != null) { t1.x = 0.035; t1.y = 0.245; }
                            if (t2 != null) { t2.x = 0.035; t2.y = 0.520; }
                          }),
                          icon: const Icon(Icons.swap_vert_rounded, size: 14),
                          label: const Text('⬇️ Vertical Stack', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                          onPressed: () => setState(() {
                            final t1 = _fieldsMap['marks_table'];
                            final t2 = _fieldsMap['marks_table_2'];
                            if (t1 != null) { t1.x = 0.035; t1.y = 0.245; }
                            if (t2 != null) { t2.x = 0.510; t2.y = 0.245; }
                          }),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                          label: const Text('➡️ Side-by-Side', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: _matchTable2SizeWithTable1,
                      icon: const Icon(Icons.aspect_ratio_rounded, size: 14, color: Colors.white),
                      label: const Text('📐 Match Table 2 Size with Table 1',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
                const Divider(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calculate_rounded, size: 16, color: Color(0xFF0F766E)),
                        const SizedBox(width: 6),
                        Text('Show Total Summary Row:',
                            style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor)),
                      ],
                    ),
                    Switch(
                      value: _showTableTotalRow,
                      activeColor: const Color(0xFF0F766E),
                      onChanged: (v) => setState(() => _showTableTotalRow = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_enableSecondTable && _fieldsMap.containsKey('marks_table_2')) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0F766E).withAlpha(40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📍 Table 2 Independent Position', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
                  const SizedBox(height: 6),
                  _sliderRow('Table 2 X Position (mm)', _fieldsMap['marks_table_2']!.x * _pageWidthMm, 0, _pageWidthMm, (v) => setState(() => _fieldsMap['marks_table_2']!.x = (v / _pageWidthMm).clamp(0.0, 0.95)), isDark),
                  const SizedBox(height: 4),
                  _sliderRow('Table 2 Y Position (mm)', _fieldsMap['marks_table_2']!.y * _pageHeightMm, 0, _pageHeightMm, (v) => setState(() => _fieldsMap['marks_table_2']!.y = (v / _pageHeightMm).clamp(0.0, 0.95)), isDark),
                  const SizedBox(height: 4),
                  _sliderRow('Table 2 Width (mm)', _fieldsMap['marks_table_2']!.widthMm, 30, 210, (v) => setState(() => _fieldsMap['marks_table_2']!.widthMm = v), isDark),
                ],
              ),
            ),
          ],
          const Divider(height: 20),

          // ── MS Word Style Column & Row Numeric Inputs ──
          Text('📐 Column Selection & Resize Inspector',
              style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF0F766E).withAlpha(60)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _numericValueRow('Row Height / Spacing (mm)', _rowSpacing, 0.5, 30.0, (v) => setState(() => _rowSpacing = v), isDark),
                _numericValueRow('Cell Padding (mm)', _colPadding, 0.5, 20.0, (v) => setState(() => _colPadding = v), isDark),
                const SizedBox(height: 6),
                const Divider(height: 12),
                Text('Select Column to Edit:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4, runSpacing: 4,
                  children: [
                    {'key': 'col1', 'title': '# S.R.'},
                    {'key': 'col2', 'title': 'Book Name'},
                    {'key': 'col3', 'title': 'Max Marks'},
                    {'key': 'col4', 'title': 'Min Pass'},
                    {'key': 'col5', 'title': 'Obtained'},
                    {'key': 'col6', 'title': 'Grade'},
                  ].map((c) {
                    final isSel = _selectedTableColKey == c['key'];
                    return ChoiceChip(
                      label: Text(c['title']!, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isSel ? Colors.white : textColor)),
                      selected: isSel,
                      selectedColor: const Color(0xFF0F766E),
                      onSelected: (_) => setState(() => _selectedTableColKey = c['key']),
                    );
                  }).toList(),
                ),
                if (_selectedTableColKey != null) ...[
                  const Divider(height: 14),
                  Builder(builder: (ctx) {
                    final colKey = _selectedTableColKey!;
                    final colDef = _visibleColumns.firstWhere((c) => c.key == colKey, orElse: () => _visibleColumns.first);
                    final colVal1 = _colCustomFlex[colKey] ?? colDef.flex.toDouble();
                    final align = _colAlignment[colKey] ?? 'center';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Editing: ${colDef.title}', style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
                        const SizedBox(height: 6),
                        _numericValueRow('Table 1 Column Width (mm)', colVal1, 0.5, 100.0, (v) => setState(() => _colCustomFlex[colKey] = v), isDark),
                        if (_enableSecondTable) ...[
                          const SizedBox(height: 4),
                          _numericValueRow('Table 2 Column Width (mm)', _colCustomFlexTable2[colKey] ?? colDef.flex.toDouble(), 0.5, 100.0, (v) => setState(() => _colCustomFlexTable2[colKey] = v), isDark),
                        ],
                        const SizedBox(height: 8),
                        Text('Text Alignment:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: align == 'left' ? const Color(0xFF0F766E) : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                ),
                                onPressed: () => setState(() => _colAlignment[colKey] = 'left'),
                                icon: Icon(Icons.format_align_left_rounded, size: 14, color: align == 'left' ? Colors.white : textColor),
                                label: Text('Left', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: align == 'left' ? Colors.white : textColor)),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: align == 'center' ? const Color(0xFF0F766E) : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                ),
                                onPressed: () => setState(() => _colAlignment[colKey] = 'center'),
                                icon: Icon(Icons.format_align_center_rounded, size: 14, color: align == 'center' ? Colors.white : textColor),
                                label: Text('Center', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: align == 'center' ? Colors.white : textColor)),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: align == 'right' ? const Color(0xFF0F766E) : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                ),
                                onPressed: () => setState(() => _colAlignment[colKey] = 'right'),
                                icon: Icon(Icons.format_align_right_rounded, size: 14, color: align == 'right' ? Colors.white : textColor),
                                label: Text('Right', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: align == 'right' ? Colors.white : textColor)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }),
                ],
              ],
            ),
          ),
          const Divider(height: 20),

          // ── Visible Columns Toggles ──
          Text('👁️ Visible Columns', style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              {'key': 'col1', 'label': '# S.R.'},
              {'key': 'col2', 'label': 'Book Name'},
              {'key': 'col3', 'label': 'Max Marks'},
              {'key': 'col4', 'label': 'Min Pass'},
              {'key': 'col5', 'label': 'Obtained'},
              {'key': 'col6', 'label': 'Grade'},
            ].map((col) {
              final isVis = _columnVisible[col['key']] ?? true;
              return FilterChip(
                label: Text(col['label']!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isVis ? Colors.white : textColor)),
                selected: isVis,
                selectedColor: const Color(0xFF0F766E),
                onSelected: (v) => setState(() => _columnVisible[col['key']!] = v),
              );
            }).toList(),
          ),
          const Divider(height: 20),

          // ── Dynamic Grade Text Labels & Threshold Settings (TABLE TAB) ──
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFF0F766E), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text('🌟 Dynamic Grade Text Labels',
                    style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
              ),
              Switch(
                value: _enableConditionalColors,
                activeColor: const Color(0xFF0F766E),
                onChanged: (v) => setState(() => _enableConditionalColors = v),
              ),
            ],
          ),
          if (_enableConditionalColors) ...[
            const SizedBox(height: 8),
            Text('Customize Dynamic Grade Text Labels & Threshold Percentages:', style: AppTheme.getFontStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _conditionalColorRowPicker(
              icon: '🌟', labelCtrl: _distinctionLabelCtrl, onLabelChanged: (v) => setState(() { _distinctionLabel = v; _updateStudentFieldsData(); }),
              controller: _distinctionThresholdCtrl, isLessThan: false, onThresholdChanged: (v) => setState(() { _distinctionThreshold = v; _updateStudentFieldsData(); }),
              colorVal: _distinctionMarkColor, onColorSelected: (c) => setState(() { _distinctionMarkColor = c; _updateStudentFieldsData(); }), isDark: isDark,
            ),
            _conditionalColorRowPicker(
              icon: '🔷', labelCtrl: _highMarkLabelCtrl, onLabelChanged: (v) => setState(() { _highMarkLabel = v; _updateStudentFieldsData(); }),
              controller: _highMarkThresholdCtrl, isLessThan: false, onThresholdChanged: (v) => setState(() { _highMarkThreshold = v; _updateStudentFieldsData(); }),
              colorVal: _highMarkColor, onColorSelected: (c) => setState(() { _highMarkColor = c; _updateStudentFieldsData(); }), isDark: isDark,
            ),
            _conditionalColorRowPicker(
              icon: '🔸', labelCtrl: _averageMarkLabelCtrl, onLabelChanged: (v) => setState(() { _averageMarkLabel = v; _updateStudentFieldsData(); }),
              controller: _averageMarkThresholdCtrl, isLessThan: false, onThresholdChanged: (v) => setState(() { _averageMarkThreshold = v; _updateStudentFieldsData(); }),
              colorVal: _averageMarkColor, onColorSelected: (c) => setState(() { _averageMarkColor = c; _updateStudentFieldsData(); }), isDark: isDark,
            ),
            _conditionalColorRowPicker(
              icon: '⚠️', labelCtrl: _passMarkLabelCtrl, onLabelChanged: (v) => setState(() { _passMarkLabel = v; _updateStudentFieldsData(); }),
              controller: _passMarkThresholdCtrl, isLessThan: false, onThresholdChanged: (v) => setState(() { _passMarkThreshold = v; _updateStudentFieldsData(); }),
              colorVal: _lowMarkColor, onColorSelected: (c) => setState(() { _lowMarkColor = c; _updateStudentFieldsData(); }), isDark: isDark,
            ),
            _conditionalColorRowPicker(
              icon: '❌', labelCtrl: _failMarkLabelCtrl, onLabelChanged: (v) => setState(() { _failMarkLabel = v; _updateStudentFieldsData(); }),
              controller: _passMarkThresholdCtrl, isLessThan: true, onThresholdChanged: (v) => setState(() { _passMarkThreshold = v; _updateStudentFieldsData(); }),
              colorVal: _failMarkColor, onColorSelected: (c) => setState(() { _failMarkColor = c; _updateStudentFieldsData(); }), isDark: isDark,
            ),
          ],
          const Divider(height: 20),

          // ── Editable Subject Rows ──
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text('📖 Subjects & Marks Rows', style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E))),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                onPressed: _addTableSubject,
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('+ Add Book', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(_tableSubjects.length, (idx) {
            final m = _tableSubjects[idx];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 10, backgroundColor: const Color(0xFF0F766E),
                        child: Text('${idx + 1}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: m.bookNameCtrl,
                          style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
                          decoration: const InputDecoration(labelText: 'Subject / Book Name', isDense: true, border: OutlineInputBorder()),
                          onChanged: (val) { m.bookName = val; setState(() {}); },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => _deleteTableSubject(idx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: m.maxMarksCtrl, keyboardType: TextInputType.number,
                          style: AppTheme.getFontStyle(fontSize: 11.5, color: textColor),
                          decoration: const InputDecoration(labelText: 'Max Marks', isDense: true, border: OutlineInputBorder()),
                          onChanged: (val) { m.maxMarks = double.tryParse(val) ?? 100.0; _refreshTotals(); setState(() {}); },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: m.obtainedCtrl, keyboardType: TextInputType.number,
                          style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor),
                          decoration: const InputDecoration(labelText: 'Obtained', isDense: true, border: OutlineInputBorder()),
                          onChanged: (val) { m.marksObtained = double.tryParse(val) ?? 0.0; _refreshTotals(); setState(() {}); },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: m.minPassCtrl, keyboardType: TextInputType.number,
                          style: AppTheme.getFontStyle(fontSize: 11.5, color: textColor),
                          decoration: const InputDecoration(labelText: 'Min Pass', isDense: true, border: OutlineInputBorder()),
                          onChanged: (val) { m.minPass = val; setState(() {}); },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: m.gradeCtrl,
                          style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E)),
                          decoration: const InputDecoration(labelText: 'Grade', isDense: true, border: OutlineInputBorder()),
                          onChanged: (val) { m.gradeName = val; setState(() {}); },
                        ),
                      ),
                    ],
                  ),
                  if (_enableSecondTable) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('Table Group:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
                        const Spacer(),
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
                                onTap: () => setState(() => m.tableGroup = 1),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: m.tableGroup == 1 ? const Color(0xFF0D6B4E) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Table 1',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: m.tableGroup == 1 ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => m.tableGroup = 2),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: m.tableGroup == 2 ? const Color(0xFF0D6B4E) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Table 2',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: m.tableGroup == 2 ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBorderSidePicker({
    required String label,
    required String currentSide,
    required ValueChanged<String> onChanged,
    required bool isDark,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;

    final borderOptions = <Map<String, String>>[
      {'value': 'none', 'label': '🚫 No Border'},
      {'value': 'all', 'label': '⏹️ All Borders'},
      {'value': 'top', 'label': '⬆️ Top Border'},
      {'value': 'bottom', 'label': '⬇️ Bottom Border'},
      {'value': 'left', 'label': '⬅️ Left Border'},
      {'value': 'right', 'label': '➡️ Right Border'},
      {'value': 'horizontal', 'label': '⏸️ Horizontal Grid'},
      {'value': 'vertical', 'label': '🔲 Vertical Grid'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: borderOptions.any((o) => o['value'] == currentSide) ? currentSide : 'none',
                isExpanded: true,
                isDense: true,
                style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: textColor),
                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                items: borderOptions.map((opt) {
                  return DropdownMenuItem<String>(
                    value: opt['value'],
                    child: Text(opt['label']!, style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) onChanged(val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorRowPicker(String label, Color colorVal, ValueChanged<Color> onSelected, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final isTransparent = colorVal == Colors.transparent || colorVal.alpha == 0;

    final quickColors = [
      Colors.transparent,
      Colors.black,
      const Color(0xFF0F766E),
      const Color(0xFF1E3A8A),
      const Color(0xFFD97706),
      const Color(0xFFDC2626),
      const Color(0xFF059669),
      Colors.white,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor))),
              InkWell(
                onTap: () async {
                  final c = await _showAdvancedColorPicker(colorVal);
                  if (c != null) onSelected(c);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: const [
                      Icon(Icons.color_lens_rounded, size: 13, color: Color(0xFF0F766E)),
                      SizedBox(width: 3),
                      Text('Picker 🎨', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: quickColors.map((c) {
              final isTrans = c == Colors.transparent;
              final isSelected = isTrans ? isTransparent : (colorVal.value == c.value && !isTransparent);
              return GestureDetector(
                onTap: () => onSelected(c),
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? const Color(0xFF0F766E) : Colors.grey.shade400, width: isSelected ? 2.5 : 1.0),
                    boxShadow: isSelected ? const [BoxShadow(color: Colors.black26, blurRadius: 3)] : null,
                  ),
                  child: isTrans ? const Icon(Icons.block, size: 10, color: Colors.red) : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _conditionalColorRowPicker({
    required String icon,
    required TextEditingController labelCtrl,
    required ValueChanged<String> onLabelChanged,
    required TextEditingController controller,
    required bool isLessThan,
    required ValueChanged<double> onThresholdChanged,
    required Color colorVal,
    required ValueChanged<Color> onColorSelected,
    required bool isDark,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: labelCtrl,
                style: AppTheme.getFontStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: textColor),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                  ),
                ),
                onChanged: onLabelChanged,
              ),
            ),
          ),
          Text(
            isLessThan ? '< ' : '≥ ',
            style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF0F766E)),
          ),
          SizedBox(
            width: 38,
            height: 26,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.center,
              style: AppTheme.getFontStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: textColor),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                ),
              ),
              onChanged: (val) {
                final parsed = UrduNumberHelper.tryParseDouble(val);
                if (parsed != null && parsed >= 0 && parsed <= 100) {
                  onThresholdChanged(parsed);
                }
              },
            ),
          ),
          Text(' %', style: AppTheme.getFontStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () async {
              final c = await _showAdvancedColorPicker(colorVal);
              if (c != null) onColorSelected(c);
            },
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: colorVal,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade400, width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSearchableFontPicker({
    required String currentFont,
    required ValueChanged<String> onSelected,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchCtrl = TextEditingController();
    List<String> filtered = List.from(_allFontFamilies);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Row(
                children: [
                  const Icon(Icons.font_download_rounded, color: Color(0xFF0F766E), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Choose Font',
                    style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                  ),
                ],
              ),
              content: SizedBox(
                width: 380,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      style: AppTheme.getFontStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: '🔍 Search font (e.g. Jameel, Segoe, Arial)...',
                        hintStyle: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          final query = val.toLowerCase().trim();
                          if (query.isEmpty) {
                            filtered = List.from(_allFontFamilies);
                          } else {
                            filtered = _allFontFamilies.where((f) => f.toLowerCase().contains(query)).toList();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text('No font found matching "${searchCtrl.text}"',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (lCtx, idx) {
                                final fontName = filtered[idx];
                                final isSelected = fontName == currentFont;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF0F766E).withAlpha(40)
                                        : (isDark ? Colors.white.withAlpha(5) : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF0F766E) : Colors.grey.shade300,
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    title: Text(
                                      fontName,
                                      style: TextStyle(
                                        fontFamily: fontName,
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? const Color(0xFF0F766E) : (isDark ? Colors.white : Colors.black87),
                                      ),
                                    ),
                                    trailing: isSelected
                                        ? const Icon(Icons.check_circle_rounded, color: Color(0xFF0F766E), size: 18)
                                        : null,
                                    onTap: () {
                                      onSelected(fontName);
                                      Navigator.of(dialogCtx).pop();
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Tab 5: Print ──────────────────────────────────────────
  Widget _buildExportPrintTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🖨️ PDF Export Options',
            style: AppTheme.getFontStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F766E))),
        const SizedBox(height: 12),
        Text('📄 Print Sides',
            style: AppTheme.getFontStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F766E))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF0F766E).withAlpha(60)),
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pdfPrintSide == 'both' ? const Color(0xFF0F766E) : Colors.transparent,
                    elevation: _pdfPrintSide == 'both' ? 2 : 0,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => setState(() => _pdfPrintSide = 'both'),
                  child: Text('Both Sides', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _pdfPrintSide == 'both' ? Colors.white : (isDark ? Colors.white : Colors.black87))),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pdfPrintSide == 'front' ? const Color(0xFF0F766E) : Colors.transparent,
                    elevation: _pdfPrintSide == 'front' ? 2 : 0,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => setState(() => _pdfPrintSide = 'front'),
                  child: Text('Front Only', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _pdfPrintSide == 'front' ? Colors.white : (isDark ? Colors.white : Colors.black87))),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pdfPrintSide == 'back' ? const Color(0xFF0F766E) : Colors.transparent,
                    elevation: _pdfPrintSide == 'back' ? 2 : 0,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => setState(() => _pdfPrintSide = 'back'),
                  child: Text('Back Only', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _pdfPrintSide == 'back' ? Colors.white : (isDark ? Colors.white : Colors.black87))),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              minimumSize: const Size(double.infinity, 44)),
          onPressed: () => _exportPdf(targetScope: 'single'),
          icon:
              const Icon(Icons.person_rounded, color: Colors.white),
          label: Text(
              'Print Single (${_currentStudent.fullName})',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              minimumSize: const Size(double.infinity, 44)),
          onPressed: () => _exportPdf(targetScope: 'class'),
          icon:
              const Icon(Icons.groups_rounded, color: Colors.white),
          label: Text(
              'Print Class (${_filteredStudents.length})',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D6B4E),
              minimumSize: const Size(double.infinity, 44)),
          onPressed: () => _exportPdf(targetScope: 'all'),
          icon:
              const Icon(Icons.domain_rounded, color: Colors.white),
          label: Text(
              'Print All (${_studentsList.length})',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _sliderRow(String label, double val, double min, double max,
      ValueChanged<double> onChanged, bool isDark) {
    return _SliderRow(
      label: label,
      val: val,
      min: min,
      max: max,
      onChanged: onChanged,
      isDark: isDark,
    );
  }

  Widget _numericValueRow(String label, double val, double min, double max,
      ValueChanged<double> onChanged, bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.getFontStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF0F766E).withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    final nv = (val - 0.5).clamp(min, max);
                    onChanged(nv);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.remove_rounded, size: 14, color: Color(0xFF0F766E)),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: TextFormField(
                    initialValue: val.toStringAsFixed(1),
                    key: ValueKey('${label}_$val'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: AppTheme.getFontStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F766E),
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                    ),
                    onFieldSubmitted: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null) {
                        onChanged(parsed.clamp(min, max));
                      }
                    },
                  ),
                ),
                InkWell(
                  onTap: () {
                    final nv = (val + 0.5).clamp(min, max);
                    onChanged(nv);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.add_rounded, size: 14, color: Color(0xFF0F766E)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControls(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 10, offset: Offset(0, 3))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Zoom In (+) [Up to 10x]',
            child: IconButton(
              icon: const Icon(Icons.add_rounded, size: 18),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                final currentScale = _transformationController.value.getMaxScaleOnAxis();
                if (currentScale >= 10.0) return;
                final targetScale = (currentScale * 1.25).clamp(0.1, 10.0);
                final factor = targetScale / currentScale;
                setState(() {
                  final matrix = _transformationController.value.clone();
                  matrix.scale(factor, factor);
                  _transformationController.value = matrix;
                  _zoomScale = targetScale;
                });
              },
            ),
          ),
          InkWell(
            onTap: () {
              setState(() {
                _transformationController.value = Matrix4.identity();
                _zoomScale = 1.0;
              });
            },
            child: Tooltip(
              message: 'Reset Zoom (100% / Fit)',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  '${(_zoomScale * 100).round()}%',
                  style: AppTheme.getFontStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F766E),
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Zoom Out (-) [Down to 0.1x]',
            child: IconButton(
              icon: const Icon(Icons.remove_rounded, size: 18),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                final currentScale = _transformationController.value.getMaxScaleOnAxis();
                if (currentScale <= 0.1) return;
                final targetScale = (currentScale / 1.25).clamp(0.1, 10.0);
                final factor = targetScale / currentScale;
                setState(() {
                  final matrix = _transformationController.value.clone();
                  matrix.scale(factor, factor);
                  _transformationController.value = matrix;
                  _zoomScale = targetScale;
                });
              },
            ),
          ),
          const Divider(height: 1, indent: 4, endIndent: 4),
          Tooltip(
            message: 'Reset View / Fit to Screen',
            child: IconButton(
              icon: const Icon(Icons.center_focus_strong_rounded, size: 16, color: Color(0xFF0F766E)),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() {
                  _transformationController.value = Matrix4.identity();
                  _zoomScale = 1.0;
                });
              },
            ),
          ),
          const Divider(height: 1, indent: 4, endIndent: 4),
          Tooltip(
            message: _enableSnapToGrid ? 'Snap to Grid & Objects: ON' : 'Snap to Grid & Objects: OFF',
            child: IconButton(
              icon: Icon(
                _enableSnapToGrid ? Icons.grid_goldenratio_rounded : Icons.grid_off_rounded,
                size: 16,
                color: _enableSnapToGrid ? const Color(0xFF0F766E) : Colors.grey,
              ),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() {
                  _enableSnapToGrid = !_enableSnapToGrid;
                });
              },
            ),
          ),
          Tooltip(
            message: 'Increase Grid Lines',
            child: IconButton(
              icon: const Icon(Icons.add_chart_rounded, size: 16, color: Color(0xFF0284C7)),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() {
                  _showGridOverlay = true;
                  _gridSpacingMm = (_gridSpacingMm - 2.5).clamp(2.0, 50.0);
                });
              },
            ),
          ),
          Tooltip(
            message: 'Decrease Grid Lines',
            child: IconButton(
              icon: const Icon(Icons.table_chart_outlined, size: 16, color: Colors.blueGrey),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () {
                setState(() {
                  _showGridOverlay = true;
                  _gridSpacingMm = (_gridSpacingMm + 2.5).clamp(2.0, 50.0);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Canvas ───────────────────────────────────────────────
  Widget _buildCanvasWorkspace(bool isDark) {
    return LayoutBuilder(builder: (context, constraints) {
      const pad = 32.0;
      final maxW = constraints.maxWidth - pad * 2;
      final maxH = constraints.maxHeight - pad * 2;

      double cw = maxW;
      double ch = cw * (_pageHeightMm / _pageWidthMm);
      if (ch > maxH) {
        ch = maxH;
        cw = ch * (_pageWidthMm / _pageHeightMm);
      }

      final fontScale = cw / (_pageWidthMm * 2.834645);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _selectedFieldId = null;
            _lastBoundFieldId = null;
          });
        },
        child: InteractiveViewer(
          transformationController: _transformationController,
          boundaryMargin: const EdgeInsets.all(2500),
          minScale: 0.1,
          maxScale: 10.0,
          clipBehavior: Clip.none,
          onInteractionUpdate: (_) {
            final currentScale = _transformationController.value.getMaxScaleOnAxis();
            if ((currentScale - _zoomScale).abs() > 0.01) {
              setState(() {
                _zoomScale = currentScale;
              });
            }
          },
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _selectedFieldId = null;
                  _lastBoundFieldId = null;
                });
              },
              child: Container(
                width: cw,
                height: ch,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: _isTransparentPageBg
                      ? Colors.transparent
                      : _pageBgColor,
                  borderRadius: BorderRadius.circular(_borderRadius),
                  border: Border.all(
                      color: _pageBorderColor, width: _pageBorderWidth),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 16,
                        offset: Offset(0, 6))
                  ],
                ),
                child: _buildCanvasStack(cw, ch, fontScale),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildSingleTableWidget({
    required String tableId,
    required List<_SubjectRowConfig> subjectsList,
    required List<_ColDef> visCols,
    required double fontScale,
    required bool isSelected,
    required Map<String, double> colFlexMap,
  }) {
    if (subjectsList.isEmpty) return const SizedBox.shrink();

    double totalMax = 0;
    double totalObt = 0;
    double totalMinPass = 0;
    bool hasMinPassNum = false;

    for (final s in subjectsList) {
      totalMax += s.maxMarks;
      if (!s.isAbsent) totalObt += s.marksObtained;
      final mp = double.tryParse(s.minPass);
      if (mp != null) {
        totalMinPass += mp;
        hasMinPassNum = true;
      }
    }

    final overallGrade = _getGradingScaleGrade(totalObt, totalMax, false);

    final mizanTitle = _cardLanguage == 'ur'
        ? 'کل میزان'
        : (_cardLanguage == 'ar'
            ? 'المجموع الكلي'
            : (_cardLanguage == 'hi'
                ? 'कुल योग'
                : (_cardLanguage == 'gu'
                    ? 'કુલ સરવાળો'
                    : (_cardLanguage == 'bn' ? 'সর্বমোট' : 'Total Marks'))));

    final String rawMax = totalMax.toStringAsFixed(0);
    final String rawObt = totalObt.toStringAsFixed(0);
    final String rawMin = hasMinPassNum ? totalMinPass.toStringAsFixed(0) : '-';

    final isTable2 = tableId == 'marks_table_2';
    final gridClr = isTable2 ? _table2GridColor : _tableGridColor;
    final gridW = isTable2 ? _table2GridWidth : _tableGridWidth;

    final headerBorder = _buildSectionBorder(
      borderSide: isTable2 ? _table2HeaderBorderSide : _table1HeaderBorderSide,
      color: isTable2 ? _table2HeaderBorderColor : _table1HeaderBorderColor,
      width: isTable2 ? _table2HeaderBorderWidth : _table1HeaderBorderWidth,
    );

    final rowsBorder = _buildSectionBorder(
      borderSide: isTable2 ? _table2RowsBorderSide : _table1RowsBorderSide,
      color: gridClr,
      width: gridW,
    );

    final totalBorder = _buildSectionBorder(
      borderSide: isTable2 ? _table2TotalBorderSide : _table1TotalBorderSide,
      color: isTable2 ? _table2TotalBorderColor : _table1TotalBorderColor,
      width: isTable2 ? _table2TotalBorderWidth : _table1TotalBorderWidth,
    );

    final outerBorder = isSelected
        ? Border.all(color: Colors.cyan, width: 2)
        : _buildSectionBorder(
            borderSide: isTable2 ? _table2OuterBorderSide : _table1OuterBorderSide,
            color: isTable2 ? _table2OuterBorderColor : _table1OuterBorderColor,
            width: isTable2 ? _table2OuterBorderWidth : _table1OuterBorderWidth,
          );

    final outerBg = isTable2 ? _table2BgColor : _table1BgColor;
    final outerRadius = isTable2 ? _table2CornerRadius : _table1CornerRadius;

    return Container(
      decoration: BoxDecoration(
        color: outerBg,
        border: outerBorder,
        borderRadius: BorderRadius.circular(outerRadius),
        boxShadow: isSelected
            ? [BoxShadow(color: Colors.cyan.withAlpha(80), blurRadius: 8, spreadRadius: 1)]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _isTransparentTableHeader ? Colors.transparent : (isTable2 ? _table2HeaderBg : _tableHeaderBg),
              border: headerBorder,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  vertical: _rowCustomSpacing[-1] ?? _rowSpacing),
              child: Row(
                textDirection: (_cardLanguage == 'ur' || _cardLanguage == 'ar')
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                children: visCols.map((col) {
                  final flexVal = ((colFlexMap[col.key] ?? col.flex.toDouble()) * 100).round();
                  final hdrFont = _colFontFamily[col.key] ?? _tableFontFamily;
                  final hdrFontSize = _tableHeaderFontSize;
                  final hdrColor = isTable2 ? _table2HeaderTextColor : _tableHeaderTextColor;
                  final hdrBold = _tableHeaderBold;

                  return Expanded(
                    flex: flexVal,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedFieldId = 'table_header_${col.key}';
                          _selectedTableColKey = col.key;
                          _selectedTableSection = 'header';
                          if (isTable2) _selectedTableForColor = 2; else _selectedTableForColor = 1;
                          _lastBoundFieldId = null;
                        });
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: _colPadding),
                        child: Text(
                          col.title,
                          textAlign: _getColTextAlign(col.key),
                          style: TextStyle(
                            fontFamily: hdrFont,
                            fontSize: hdrFontSize * fontScale,
                            color: hdrColor,
                            fontWeight: hdrBold ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          ...List.generate(subjectsList.length, (idx) {
            final m = subjectsList[idx];
            final obtStr = m.isAbsent ? 'ABSENT' : m.marksObtained.toStringAsFixed(0);

            String cellText(String colKey) {
              switch (colKey) {
                case 'col1': return '${idx + 1}';
                case 'col2': return m.bookName;
                case 'col3': return m.maxMarks.toInt().toString();
                case 'col4': return m.minPass;
                case 'col5': return obtStr;
                case 'col6': return _getDynamicGrade(m.marksObtained, m.maxMarks, m.isAbsent, m.gradeName);
                default: return '';
              }
            }

            Color cellColor(String colKey) {
              final markColor = _getMarkColor(m.marksObtained, m.maxMarks, m.isAbsent);
              final isEvenRow = idx % 2 == 1;

              final defaultOddRowText = isTable2 ? _table2OddRowTextColor : _tableRowTextColor;
              final defaultEvenRowText = isTable2 ? _table2EvenRowTextColor : _bookNameTextColor;
              final rowTextColor = isEvenRow ? defaultEvenRowText : defaultOddRowText;

              switch (colKey) {
                case 'col1':
                case 'col2':
                case 'col3':
                case 'col4': return rowTextColor;
                case 'col5': return markColor;
                case 'col6': return _getGradeColor(m.gradeName, markColor);
                default: return rowTextColor;
              }
            }

            final oddBg = isTable2 ? _table2OddRowBgColor : _table1OddRowBgColor;
            final evenBg = isTable2 ? _table2EvenRowBgColor : _alternatingRowBgColor;

            final rowBgColor = (!_isTransparentRowBg)
                ? (idx % 2 == 1 ? evenBg : oddBg)
                : Colors.transparent;

            return Container(
              decoration: BoxDecoration(
                color: rowBgColor,
                border: rowsBorder,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                        vertical: _rowCustomSpacing[idx] ?? _rowSpacing),
                    child: Row(
                      textDirection: (_cardLanguage == 'ur' || _cardLanguage == 'ar')
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      children: visCols.map((col) {
                        final rawTxt = cellText(col.key);
                        final txt = UrduNumberHelper.convertDigits(rawTxt, _cardLanguage);
                        final clr = cellColor(col.key);
                        final customColFont = _colFontFamily[col.key];
                        final cellFontFamily = customColFont ?? ((col.key == 'col6' || _containsArabicUrdu(txt)) ? _tableUrduFontFamily : _tableFontFamily);
                        final isUrduCell = col.key == 'col6' || _containsArabicUrdu(txt);
                        final scaleFactor = isUrduCell ? 1.7 : 1.0;
                        final flexVal = ((colFlexMap[col.key] ?? col.flex.toDouble()) * 100).round();

                        return Expanded(
                          flex: flexVal,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedFieldId = 'table_${col.key}_text';
                                _selectedTableColKey = col.key;
                                _selectedTableSection = 'rows';
                                if (isTable2) _selectedTableForColor = 2; else _selectedTableForColor = 1;
                                _lastBoundFieldId = null;
                              });
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: _colPadding),
                              child: Text(
                                txt,
                                textAlign: _getColTextAlign(col.key),
                                style: TextStyle(
                                  fontFamily: cellFontFamily,
                                  fontFamilyFallback: _urduFontFallback,
                                  fontSize: _getCellFontSize(col.key) * scaleFactor * fontScale,
                                  color: clr,
                                  fontWeight: _isCellBold(col.key) ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (isSelected)
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) {
                          setState(() {
                            final cur = _rowCustomSpacing[idx] ?? _rowSpacing;
                            _rowCustomSpacing[idx] = (cur + details.delta.dy / 2.0).clamp(0.5, 30.0);
                          });
                        },
                        child: Container(
                          height: 5,
                          color: Colors.cyan.withAlpha(20),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
          if (_showTableTotalRow) ...[
            InkWell(
              onTap: () {
                setState(() {
                  _selectedTableSection = 'total';
                  if (isTable2) _selectedTableForColor = 2; else _selectedTableForColor = 1;
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isTable2 ? _table2TotalRowBgColor : _totalRowBgColor,
                  border: totalBorder,
                ),
                padding: EdgeInsets.symmetric(vertical: _rowSpacing + 1),
                child: Row(
                  textDirection: (_cardLanguage == 'ur' || _cardLanguage == 'ar')
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  children: visCols.map((col) {
                    String cellTxt = '';
                    if (col.key == 'col1' || col.key == 'col2') {
                      cellTxt = col.key == 'col2' ? mizanTitle : '';
                    } else if (col.key == 'col3') {
                      cellTxt = rawMax;
                    } else if (col.key == 'col4') {
                      cellTxt = rawMin;
                    } else if (col.key == 'col5') {
                      cellTxt = rawObt;
                    } else if (col.key == 'col6') {
                      cellTxt = overallGrade;
                    }

                    final txt = UrduNumberHelper.convertDigits(cellTxt, _cardLanguage);
                    final flexVal = ((colFlexMap[col.key] ?? col.flex.toDouble()) * 100).round();
                    final totTxtColor = tableId == 'marks_table_2' ? _table2TotalRowTextColor : _totalRowTextColor;

                    return Expanded(
                      flex: flexVal,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: _colPadding),
                        child: Text(
                          txt,
                          textAlign: _getColTextAlign(col.key),
                          style: TextStyle(
                            fontFamily: _tableUrduFontFamily,
                            fontFamilyFallback: _urduFontFallback,
                            fontSize: _getCellFontSize(col.key) * 1.05 * fontScale,
                            color: totTxtColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCanvasStack(double cw, double ch, double fontScale) {
    final sideStr = _isFrontSide ? 'front' : 'back';
    final visCols = _visibleColumns;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (_useUploadedTemplate) ...[
          if (_isFrontSide && _uploadedTemplateImageFront != null && _uploadedTemplateImageFront!.existsSync())
            Positioned.fill(
              child: Image.file(_uploadedTemplateImageFront!, fit: BoxFit.fill),
            )
          else if (!_isFrontSide && _uploadedTemplateImageBack != null && _uploadedTemplateImageBack!.existsSync())
            Positioned.fill(
              child: Image.file(_uploadedTemplateImageBack!, fit: BoxFit.fill),
            ),
        ],
        if (!_useUploadedTemplate && _isFrontSide)
          Positioned(
            left: cw * 0.035,
            top: ch * 0.025,
            width: cw * 0.93,
            height: ch * 0.110,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _selectedFieldId = 'institution';
                  _lastBoundFieldId = null;
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: (_headerBannerBg == Colors.transparent || _headerBannerBg.opacity == 0.0 || _headerBannerBg.value == 0)
                      ? Colors.transparent
                      : _headerBannerBg,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        if (_showGridOverlay)
          Positioned.fill(
              child: CustomPaint(
                  painter: _GridPainter(
                      color: Colors.cyan.withAlpha(90),
                      gridSpacingMm: _gridSpacingMm,
                      pageWidthMm: _pageWidthMm,
                      pageHeightMm: _pageHeightMm,
                  ))),

        ..._fieldsMap.values
            .where((f) =>
                f.visible &&
                f.side == sideStr &&
                !f.id.startsWith('table_header_col'))
            .map((f) {
          final isSelected = _selectedFieldId == f.id;
          final left = f.x * cw;
          final top = f.y * ch;
          final boxW = f.widthMm * (cw / _pageWidthMm);
          final boxH = f.heightMm * (ch / _pageHeightMm);

          Widget content;

          if (f.isTable && visCols.isNotEmpty) {
            if (!_isTableGrouped) {
              content = const SizedBox.shrink();
            } else {
              final List<Widget> tableOverlayWidgets = [];
              final activeFlexMap = f.id == 'marks_table_2' ? _colCustomFlexTable2 : _colCustomFlex;
              final totalFlex = visCols.fold<double>(0.0, (sum, c) => sum + (activeFlexMap[c.key] ?? c.flex.toDouble()));
              double currentAccumulatedFlex = 0.0;
              final isTableRtl = _cardLanguage == 'ur' || _cardLanguage == 'ar';

              for (int i = 0; i < visCols.length - 1; i++) {
                final col = visCols[i];
                final nextCol = visCols[i + 1];
                final flexVal = activeFlexMap[col.key] ?? col.flex.toDouble();
                currentAccumulatedFlex += flexVal;

                final ratio = totalFlex > 0 ? (currentAccumulatedFlex / totalFlex) : 0.0;
                final handleLeft = isTableRtl ? ((1.0 - ratio) * boxW - 5.0) : (ratio * boxW - 5.0);

                final isHovered = _hoveredDividerIndex == i;
                final isDragging = _activeDraggingDividerIndex == i;

                tableOverlayWidgets.add(
                  Positioned(
                    left: handleLeft,
                    top: 0,
                    bottom: 0,
                    width: 10.0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      onEnter: (_) => setState(() => _hoveredDividerIndex = i),
                      onExit: (_) => setState(() => _hoveredDividerIndex = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) {
                          setState(() {
                            _selectedFieldId = f.id;
                            _selectedColKey = null;
                            _lastBoundFieldId = null;
                            _activeDraggingDividerIndex = i;
                          });
                        },
                        onHorizontalDragEnd: (_) {
                          setState(() {
                            _activeDraggingDividerIndex = null;
                          });
                        },
                        onHorizontalDragCancel: () {
                          setState(() {
                            _activeDraggingDividerIndex = null;
                          });
                        },
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            final targetMap = f.id == 'marks_table_2' ? _colCustomFlexTable2 : _colCustomFlex;
                            final tFlex = visCols.fold<double>(0.0, (sum, c) => sum + (targetMap[c.key] ?? c.flex.toDouble()));
                            if (tFlex <= 0.0) return;

                            // Convert all columns to explicit millimeter widths to keep non-dragged columns intact
                            for (final c in visCols) {
                              final fVal = targetMap[c.key] ?? c.flex.toDouble();
                              final calculatedMm = f.widthMm * (fVal / tFlex);
                              targetMap[c.key] = calculatedMm;
                            }

                            final rawDeltaMm = details.delta.dx / (cw / _pageWidthMm);
                            final deltaMm = isTableRtl ? -rawDeltaMm : rawDeltaMm;

                            final colKeyA = col.key;
                            final colKeyB = nextCol.key;

                            final widthA = targetMap[colKeyA]!;
                            final widthB = targetMap[colKeyB]!;
                            final combinedWidth = widthA + widthB;

                            final newWidthA = (widthA + deltaMm).clamp(8.0, combinedWidth - 8.0);
                            final newWidthB = combinedWidth - newWidthA;

                            targetMap[colKeyA] = newWidthA;
                            targetMap[colKeyB] = newWidthB;
                          });
                        },
                        child: Container(
                          color: Colors.transparent,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              width: (isDragging || isHovered) ? 2.5 : 1.5,
                              color: isDragging
                                  ? Colors.cyan
                                  : isHovered
                                      ? Colors.cyan.withAlpha(200)
                                      : Colors.cyan.withAlpha(80),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              if (isSelected) {
                // 1. Top edge handle
                tableOverlayWidgets.add(
                  Positioned(
                    top: -6, left: 0, right: 0, height: 12,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) {
                          final deltaY = details.delta.dy / ch;
                          final deltaSpacing = -details.delta.dy / 5.0;
                          setState(() {
                            f.y = (f.y + deltaY).clamp(0.0, 0.95);
                            _rowSpacing = (_rowSpacing + deltaSpacing).clamp(0.5, 25.0);
                          });
                        },
                        child: Container(
                          color: Colors.transparent, alignment: Alignment.center,
                          child: Container(
                            width: 20, height: 5,
                            decoration: BoxDecoration(
                              color: Colors.cyan, borderRadius: BorderRadius.circular(2.5),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                // 2. Bottom edge handle
                tableOverlayWidgets.add(
                  Positioned(
                    bottom: -6, left: 0, right: 0, height: 12,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) {
                          final deltaSpacing = details.delta.dy / 5.0;
                          setState(() {
                            _rowSpacing = (_rowSpacing + deltaSpacing).clamp(0.5, 25.0);
                          });
                        },
                        child: Container(
                          color: Colors.transparent, alignment: Alignment.center,
                          child: Container(
                            width: 20, height: 5,
                            decoration: BoxDecoration(
                              color: Colors.cyan, borderRadius: BorderRadius.circular(2.5),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                // 3. Left edge handle
                tableOverlayWidgets.add(
                  Positioned(
                    left: -6, top: 0, bottom: 0, width: 12,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (details) {
                          final deltaX = details.delta.dx / cw;
                          final deltaMm = details.delta.dx / (cw / _pageWidthMm);
                          setState(() {
                            final newX = (f.x + deltaX).clamp(0.0, 0.95);
                            final newW = (f.widthMm - deltaMm).clamp(30.0, _pageWidthMm);
                            f.x = newX;
                            f.widthMm = newW;
                          });
                        },
                        child: Container(
                          color: Colors.transparent, alignment: Alignment.center,
                          child: Container(
                            width: 5, height: 20,
                            decoration: BoxDecoration(
                              color: Colors.cyan, borderRadius: BorderRadius.circular(2.5),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                // 4. Right edge handle
                tableOverlayWidgets.add(
                  Positioned(
                    right: -6, top: 0, bottom: 0, width: 12,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (details) {
                          final deltaMm = details.delta.dx / (cw / _pageWidthMm);
                          setState(() {
                            f.widthMm = (f.widthMm + deltaMm).clamp(30.0, _pageWidthMm * (1.0 - f.x));
                          });
                        },
                        child: Container(
                          color: Colors.transparent, alignment: Alignment.center,
                          child: Container(
                            width: 5, height: 20,
                            decoration: BoxDecoration(
                              color: Colors.cyan, borderRadius: BorderRadius.circular(2.5),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                // 5. Top-Left corner handle
                tableOverlayWidgets.add(
                  Positioned(
                    top: -8, left: -8, width: 16, height: 16,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpLeftDownRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) {
                          final deltaX = details.delta.dx / cw;
                          final deltaY = details.delta.dy / ch;
                          final deltaMm = details.delta.dx / (cw / _pageWidthMm);
                          final deltaSpacing = -details.delta.dy / 5.0;
                          setState(() {
                            f.x = (f.x + deltaX).clamp(0.0, 0.95);
                            f.y = (f.y + deltaY).clamp(0.0, 0.95);
                            f.widthMm = (f.widthMm - deltaMm).clamp(30.0, _pageWidthMm);
                            _rowSpacing = (_rowSpacing + deltaSpacing).clamp(0.5, 25.0);
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.cyan, shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                // 6. Top-Right corner handle
                tableOverlayWidgets.add(
                  Positioned(
                    top: -8, right: -8, width: 16, height: 16,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpRightDownLeft,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) {
                          final deltaY = details.delta.dy / ch;
                          final deltaMm = details.delta.dx / (cw / _pageWidthMm);
                          final deltaSpacing = -details.delta.dy / 5.0;
                          setState(() {
                            f.y = (f.y + deltaY).clamp(0.0, 0.95);
                            f.widthMm = (f.widthMm + deltaMm).clamp(30.0, _pageWidthMm * (1.0 - f.x));
                            _rowSpacing = (_rowSpacing + deltaSpacing).clamp(0.5, 25.0);
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.cyan, shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                // 7. Bottom-Left corner handle
                tableOverlayWidgets.add(
                  Positioned(
                    bottom: -8, left: -8, width: 16, height: 16,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpRightDownLeft,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) {
                          final deltaX = details.delta.dx / cw;
                          final deltaMm = details.delta.dx / (cw / _pageWidthMm);
                          final deltaSpacing = details.delta.dy / 5.0;
                          setState(() {
                            f.x = (f.x + deltaX).clamp(0.0, 0.95);
                            f.widthMm = (f.widthMm - deltaMm).clamp(30.0, _pageWidthMm);
                            _rowSpacing = (_rowSpacing + deltaSpacing).clamp(0.5, 25.0);
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.cyan, shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                // 8. Bottom-Right corner handle
                tableOverlayWidgets.add(
                  Positioned(
                    bottom: -8, right: -8, width: 16, height: 16,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpLeftDownRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) {
                          final deltaMm = details.delta.dx / (cw / _pageWidthMm);
                          final deltaSpacing = details.delta.dy / 5.0;
                          setState(() {
                            f.widthMm = (f.widthMm + deltaMm).clamp(30.0, _pageWidthMm * (1.0 - f.x));
                            _rowSpacing = (_rowSpacing + deltaSpacing).clamp(0.5, 25.0);
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.cyan, shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              Widget tableBodyWidget;
              if (f.id == 'marks_table_2') {
                final t2Subs = _tableSubjects.where((s) => s.tableGroup == 2).toList();
                tableBodyWidget = _buildSingleTableWidget(
                  tableId: f.id,
                  subjectsList: t2Subs,
                  visCols: visCols,
                  fontScale: fontScale,
                  isSelected: isSelected,
                  colFlexMap: _colCustomFlexTable2,
                );
              } else {
                final t1Subs = _enableSecondTable
                    ? _tableSubjects.where((s) => s.tableGroup == 1).toList()
                    : _tableSubjects;
                tableBodyWidget = _buildSingleTableWidget(
                  tableId: f.id,
                  subjectsList: t1Subs.isEmpty && !_enableSecondTable ? _tableSubjects : t1Subs,
                  visCols: visCols,
                  fontScale: fontScale,
                  isSelected: isSelected,
                  colFlexMap: _colCustomFlex,
                );
              }

              content = Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: boxW,
                    child: tableBodyWidget,
                  ),
                  ...tableOverlayWidgets
                ],
              );
            }
          } else if (f.isPhoto || f.id == 'student_photo') {
            content = Container(
              width: boxW,
              height: boxH,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: isSelected
                    ? Border.all(color: Colors.cyan, width: 1.5)
                    : Border.all(color: Colors.grey.shade400, width: 1),
              ),
              child: (_uploadedStudentPhoto != null && _uploadedStudentPhoto!.existsSync())
                  ? Image.file(_uploadedStudentPhoto!, fit: BoxFit.cover)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_rounded, size: 24, color: Colors.grey),
                          Text('Student Photo', style: AppTheme.getFontStyle(fontSize: 8, color: Colors.grey)),
                        ],
                      ),
                    ),
            );
          } else if (f.id == 'teacher_sign') {
            content = Container(
              width: boxW,
              height: boxH,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: isSelected ? Border.all(color: Colors.cyan, width: 1.5) : null,
              ),
              child: (_uploadedTeacherSignature != null && _uploadedTeacherSignature!.existsSync())
                  ? Image.file(_uploadedTeacherSignature!, fit: BoxFit.contain)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(UrduNumberHelper.convertDigits(f.displayText, _cardLanguage), style: _getCanvasTextStyle(f, fontScale)),
                          Text('(Teacher Sign)', style: AppTheme.getFontStyle(fontSize: 8, color: Colors.grey)),
                        ],
                      ),
                    ),
            );
          } else if (f.id == 'principal_sign') {
            content = Container(
              width: boxW,
              height: boxH,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: isSelected ? Border.all(color: Colors.cyan, width: 1.5) : null,
              ),
              child: (_uploadedPrincipalSignature != null && _uploadedPrincipalSignature!.existsSync())
                  ? Image.file(_uploadedPrincipalSignature!, fit: BoxFit.contain)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(UrduNumberHelper.convertDigits(f.displayText, _cardLanguage), style: _getCanvasTextStyle(f, fontScale)),
                          Text('(Principal Sign)', style: AppTheme.getFontStyle(fontSize: 8, color: Colors.grey)),
                        ],
                      ),
                    ),
            );
          } else if (f.id == 'stamp' || f.isStamp) {
            content = Container(
              width: boxW,
              height: boxH,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: isSelected ? Border.all(color: Colors.cyan, width: 1.5) : null,
              ),
              child: (_uploadedPrincipalStamp != null && _uploadedPrincipalStamp!.existsSync())
                  ? Image.file(_uploadedPrincipalStamp!, fit: BoxFit.contain)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(UrduNumberHelper.convertDigits(f.displayText, _cardLanguage), style: _getCanvasTextStyle(f, fontScale)),
                          Text('(Official Stamp)', style: AppTheme.getFontStyle(fontSize: 8, color: Colors.grey)),
                        ],
                      ),
                    ),
            );
          } else if (f.id == 'grading_scale_title') {
            content = Container(
              width: boxW,
              constraints: BoxConstraints(minHeight: boxH),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.cyan.withAlpha(20) : Colors.transparent,
                border: Border.all(
                  color: isSelected ? Colors.cyan : f.color.withAlpha(100),
                  width: isSelected ? 1.5 : 1.0,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: f.color.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      f.titlePrefix.trim().isNotEmpty ? f.titlePrefix.trim() : 'Grading Scale',
                      textAlign: TextAlign.center,
                      style: AppTheme.getFontStyle(
                        fontSize: (f.fontSize * fontScale * 0.90).clamp(8.0, 40.0),
                        fontWeight: FontWeight.bold,
                        color: f.color,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Table(
                    textDirection: (_cardLanguage == 'ur' || _cardLanguage == 'ar')
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(2.6),
                    },
                    children: (_configuredGradingRules.isNotEmpty ? _configuredGradingRules : GradingHelper.defaultRules).map((r) {
                      final minStr = r.minPercent % 1 == 0 ? r.minPercent.toInt().toString() : r.minPercent.toStringAsFixed(1);
                      final maxStr = r.maxPercent % 1 == 0 ? r.maxPercent.toInt().toString() : r.maxPercent.toStringAsFixed(1);
                      final failLabel = _cardLanguage == 'ur' ? 'راسب' : (_cardLanguage == 'hi' ? 'अनुत्तीर्ण' : (_cardLanguage == 'gu' ? 'અનુત્તીર્ણ' : (_cardLanguage == 'ar' ? 'راسب' : (_cardLanguage == 'bn' ? 'ফেল' : 'Fail'))));
                      final rangeTextRaw = (r.minPercent == 0 && r.maxPercent < 33)
                          ? '$failLabel (< 33%)'
                          : '$minStr% – $maxStr%';
                      final rangeText = UrduNumberHelper.convertDigits(rangeTextRaw, _cardLanguage);
                      return TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1.0),
                            child: Text(
                              r.grade,
                              style: AppTheme.getFontStyle(
                                fontSize: (f.fontSize * fontScale * 0.82).clamp(7.5, 40.0),
                                fontWeight: FontWeight.bold,
                                color: f.color,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1.0),
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                rangeText,
                                style: TextStyle(
                                  fontFamily: f.fontFamily,
                                  fontSize: (f.fontSize * fontScale * 0.82).clamp(7.5, 40.0),
                                  fontWeight: FontWeight.w600,
                                  color: f.color.withAlpha(220),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          } else {
            final isHeaderField = f.id == 'bismillah' || f.id == 'institution' || f.id == 'sub_header' || f.id == 'session_info';
            final isRtl = _cardLanguage == 'ur' || _cardLanguage == 'ar';
            final align = isHeaderField
                ? Alignment.center
                : (isRtl ? Alignment.centerRight : Alignment.centerLeft);
            final txtAlign = isHeaderField
                ? TextAlign.center
                : (isRtl ? TextAlign.right : TextAlign.left);
            final displayTxt = f.id == 'gr_no'
                ? (_convertGrNoDigits ? UrduNumberHelper.convertDigits(f.displayText, _cardLanguage) : f.displayText)
                : UrduNumberHelper.convertDigits(f.displayText, _cardLanguage);

            content = Container(
              width: boxW,
              constraints: BoxConstraints(minHeight: boxH),
              padding: const EdgeInsets.all(2),
              alignment: align,
              decoration: BoxDecoration(
                color: isSelected ? Colors.cyan.withAlpha(20) : Colors.transparent,
                border: isSelected ? Border.all(color: Colors.cyan, width: 1.5) : null,
              ),
              child: Directionality(
                textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: align,
                  child: Text(
                    displayTxt,
                    textAlign: txtAlign,
                    style: _getCanvasTextStyle(f, fontScale),
                  ),
                ),
              ),
            );
          }

          if (f.isTable && !_isTableGrouped) return const SizedBox.shrink();

          return Positioned(
            left: left,
            top: top,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedFieldId = f.id;
                      _selectedColKey = null;
                      _lastBoundFieldId = null;
                    });
                  },
                  onPanUpdate: (d) {
                    final deltaXmm = d.delta.dx * (_pageWidthMm / cw);
                    final deltaYmm = d.delta.dy * (_pageHeightMm / ch);
                    double newXmm = (f.x * _pageWidthMm) + deltaXmm;
                    double newYmm = (f.y * _pageHeightMm) + deltaYmm;

                    if (_enableSnapToGrid) {
                      final step = _gridSpacingMm > 0 ? _gridSpacingMm : 10.0;
                      final nearGridX = (newXmm / step).round() * step;
                      final nearGridY = (newYmm / step).round() * step;

                      if ((newXmm - nearGridX).abs() < 2.5) newXmm = nearGridX;
                      if ((newYmm - nearGridY).abs() < 2.5) newYmm = nearGridY;
                    }

                    setState(() {
                      f.x = (newXmm / _pageWidthMm).clamp(0.0, 0.95);
                      f.y = (newYmm / _pageHeightMm).clamp(0.0, 0.95);
                      _selectedFieldId = f.id;
                      _selectedColKey = null;
                      _lastBoundFieldId = null;
                    });
                  },
                  child: content,
                ),
                if (isSelected && !f.isTable)
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (d) {
                          final deltaWmm = d.delta.dx * (_pageWidthMm / cw);
                          final deltaHmm = d.delta.dy * (_pageHeightMm / ch);
                          setState(() {
                            f.widthMm = (f.widthMm + deltaWmm).clamp(10.0, _pageWidthMm);
                            f.heightMm = (f.heightMm + deltaHmm).clamp(5.0, 150.0);
                          });
                        },
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                          ),
                          child: const Icon(Icons.open_in_full_rounded, size: 9, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),

        if (!_isTableGrouped)
          ...visCols.map((col) {
            final cX = _colX[col.key] ?? 0.05;
            final cY = _colY[col.key] ?? 0.25;
            final cWidthMm = _colWidthMm[col.key] ?? 35.0;
            final left = cX * cw;
            final top = cY * ch;
            final boxW = cWidthMm * (cw / _pageWidthMm);
            final isSelectedCol = _selectedColKey == col.key;

            return Positioned(
              left: left,
              top: top,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedColKey = col.key;
                    _selectedFieldId = 'col_${col.key}';
                    _lastBoundFieldId = null;
                  });
                },
                onPanUpdate: (d) {
                  setState(() {
                    _colX[col.key] = ((_colX[col.key] ?? 0.05) + d.delta.dx / cw).clamp(0.0, 0.95);
                    _colY[col.key] = ((_colY[col.key] ?? 0.25) + d.delta.dy / ch).clamp(0.0, 0.95);
                    _selectedColKey = col.key;
                    _selectedFieldId = 'col_${col.key}';
                    _lastBoundFieldId = null;
                  });
                },
                child: Container(
                  width: boxW,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: isSelectedCol
                        ? Border.all(color: Colors.cyan, width: 2.5)
                        : (_tableGridWidth == 0.0
                            ? null
                            : Border.all(color: _tableGridColor, width: _tableGridWidth)),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: isSelectedCol
                        ? [BoxShadow(color: Colors.cyan.withAlpha(90), blurRadius: 8, spreadRadius: 1)]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        color: _isTransparentTableHeader ? Colors.transparent : _tableHeaderBg,
                        padding: EdgeInsets.symmetric(vertical: _rowSpacing, horizontal: _colPadding),
                        child: Text(
                          col.title,
                          textAlign: col.key == 'col1' || col.key == 'col3' || col.key == 'col4' || col.key == 'col5' || col.key == 'col6'
                              ? TextAlign.center
                              : TextAlign.left,
                          style: TextStyle(
                            fontFamily: _tableFontFamily,
                            fontSize: _tableHeaderFontSize * fontScale,
                            color: _tableHeaderTextColor,
                            fontWeight: _tableHeaderBold ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      ...List.generate(_tableSubjects.length, (idx) {
                        final m = _tableSubjects[idx];
                        final obtStr = m.isAbsent ? 'ABSENT' : m.marksObtained.toStringAsFixed(0);

                        String cellText(String colKey) {
                          switch (colKey) {
                            case 'col1': return '${idx + 1}';
                            case 'col2': return m.bookName;
                            case 'col3': return m.maxMarks.toInt().toString();
                            case 'col4': return m.minPass;
                            case 'col5': return obtStr;
                            case 'col6': return _getDynamicGrade(m.marksObtained, m.maxMarks, m.isAbsent, m.gradeName);
                            default: return '';
                          }
                        }

                        Color cellColor(String colKey) {
                          final markColor = _getMarkColor(m.marksObtained, m.maxMarks, m.isAbsent);
                          switch (colKey) {
                            case 'col1': return _tableRowTextColor;
                            case 'col2': return _bookNameTextColor;
                            case 'col3': return _tableRowTextColor;
                            case 'col4': return _tableRowTextColor;
                            case 'col5': return markColor;
                            case 'col6': return _getGradeColor(m.gradeName, markColor);
                            default: return _tableRowTextColor;
                          }
                        }

                        final rowBgColor = (!_isTransparentRowBg && idx % 2 == 1)
                            ? _alternatingRowBgColor
                            : Colors.transparent;

                        final txt = cellText(col.key);
                        final clr = cellColor(col.key);
                        final isCentered = col.key == 'col1' || col.key == 'col3' || col.key == 'col4' || col.key == 'col5' || col.key == 'col6';
                        final customColFont = _colFontFamily[col.key];
                        final cellFontFamily = customColFont ?? ((col.key == 'col6' || _containsArabicUrdu(txt)) ? _tableUrduFontFamily : _tableFontFamily);
                        final isUrduCell = col.key == 'col6' || _containsArabicUrdu(txt);
                        final scaleFactor = isUrduCell ? 1.7 : 1.0;

                        return Container(
                          width: double.infinity,
                          color: rowBgColor,
                          padding: EdgeInsets.symmetric(vertical: _rowSpacing, horizontal: _colPadding),
                          child: Text(
                            txt,
                            textAlign: isCentered ? TextAlign.center : TextAlign.left,
                            style: TextStyle(
                              fontFamily: cellFontFamily,
                              fontFamilyFallback: _urduFontFallback,
                              fontSize: _getCellFontSize(col.key) * scaleFactor * fontScale,
                              color: clr,
                              fontWeight: _isCellBold(col.key) ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  final double gridSpacingMm;
  final double pageWidthMm;
  final double pageHeightMm;

  _GridPainter({
    required this.color,
    this.gridSpacingMm = 10.0,
    this.pageWidthMm = 210.0,
    this.pageHeightMm = 297.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.6;

    final stepMm = gridSpacingMm > 0 ? gridSpacingMm : 10.0;
    final stepX = (stepMm / pageWidthMm) * size.width;
    final stepY = (stepMm / pageHeightMm) * size.height;

    for (double x = stepX; x < size.width; x += stepX) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = stepY; y < size.height; y += stepY) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.gridSpacingMm != gridSpacingMm ||
      oldDelegate.pageWidthMm != pageWidthMm ||
      oldDelegate.pageHeightMm != pageHeightMm;
}

// ═════════════════════════════════════════════════════════════════════════════
// 🎨 Windows Office / CorelDraw Style Interactive 2D Color Picker Dialog
// ═════════════════════════════════════════════════════════════════════════════

class _WindowsStyleColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _WindowsStyleColorPickerDialog({required this.initialColor});

  @override
  State<_WindowsStyleColorPickerDialog> createState() =>
      __WindowsStyleColorPickerDialogState();
}

class __WindowsStyleColorPickerDialogState
    extends State<_WindowsStyleColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _val;
  late String _colorModel;

  late TextEditingController _rCtrl;
  late TextEditingController _gCtrl;
  late TextEditingController _bCtrl;
  late TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _colorModel = 'RGB';
    final hsv = HSVColor.fromColor(widget.initialColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _val = hsv.value;

    final c = widget.initialColor;
    _rCtrl = TextEditingController(text: '${c.red}');
    _gCtrl = TextEditingController(text: '${c.green}');
    _bCtrl = TextEditingController(text: '${c.blue}');
    _hexCtrl = TextEditingController(
        text: '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}');
  }

  @override
  void dispose() {
    _rCtrl.dispose();
    _gCtrl.dispose();
    _bCtrl.dispose();
    _hexCtrl.dispose();
    super.dispose();
  }

  Color get _currentColor =>
      HSVColor.fromAHSV(1.0, _hue, _saturation, _val).toColor();

  void _syncControllersFromHSV() {
    final c = _currentColor;
    _rCtrl.text = '${c.red}';
    _gCtrl.text = '${c.green}';
    _bCtrl.text = '${c.blue}';
    _hexCtrl.text =
        '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  void _updateFromRGB(int r, int g, int b) {
    final c = Color.fromARGB(255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    final hsv = HSVColor.fromColor(c);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _val = hsv.value;
      _syncControllersFromHSV();
    });
  }

  void _stepChannel(String channel, int delta) {
    final c = _currentColor;
    int r = c.red, g = c.green, b = c.blue;
    if (channel == 'R') r = (r + delta).clamp(0, 255);
    if (channel == 'G') g = (g + delta).clamp(0, 255);
    if (channel == 'B') b = (b + delta).clamp(0, 255);
    _updateFromRGB(r, g, b);
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _currentColor;
    final media = MediaQuery.of(context);
    final maxDialogW = (media.size.width * 0.85).clamp(280.0, 360.0);
    final maxDialogH = (media.size.height * 0.85).clamp(320.0, 560.0);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Row(
        children: [
          const Icon(Icons.color_lens_rounded, color: Color(0xFF0F766E), size: 18),
          const SizedBox(width: 8),
          Text('Color Picker', style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
      contentPadding: const EdgeInsets.all(16),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxDialogW,
          maxHeight: maxDialogH,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 180,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onPanUpdate: (d) => _handlePanSpectrum(d.localPosition, Size(230, 180)),
                        onTapDown: (d) => _handlePanSpectrum(d.localPosition, Size(230, 180)),
                        child: CustomPaint(
                          size: const Size(double.infinity, 180),
                          painter: _ColorSpectrumPainter(
                            hue: _hue,
                            saturation: _saturation,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    GestureDetector(
                      onPanUpdate: (d) => _handlePanValue(d.localPosition.dy, 180),
                      onTapDown: (d) => _handlePanValue(d.localPosition.dy, 180),
                      child: SizedBox(
                        width: 28,
                        height: 180,
                        child: CustomPaint(
                          painter: _ValueBarPainter(
                            hue: _hue,
                            saturation: _saturation,
                            value: _val,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  const Text('Color model: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _colorModel,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                        items: const [
                          DropdownMenuItem(value: 'RGB', child: Text('RGB')),
                          DropdownMenuItem(value: 'HSL', child: Text('HSL')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _colorModel = v);
                        },
                      ),
                    ),
                  ),
                  const Spacer(),

                  Container(
                    width: 50,
                    height: 30,
                    decoration: BoxDecoration(
                      color: currentColor,
                      border: Border.all(color: Colors.grey.shade600),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              _buildSpinnerRow('Red:', _rCtrl, 'R', currentColor.red),
              const SizedBox(height: 6),
              _buildSpinnerRow('Green:', _gCtrl, 'G', currentColor.green),
              const SizedBox(height: 6),
              _buildSpinnerRow('Blue:', _bCtrl, 'B', currentColor.blue),
              const SizedBox(height: 8),

              Row(
                children: [
                  const SizedBox(width: 50, child: Text('Hex:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  SizedBox(
                    width: 110,
                    height: 32,
                    child: TextField(
                      controller: _hexCtrl,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        final clean = val.replaceAll('#', '');
                        if (clean.length == 6) {
                          try {
                            final parsed = int.parse('FF$clean', radix: 16);
                            final c = Color(parsed);
                            _updateFromRGB(c.red, c.green, c.blue);
                          } catch (_) {}
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800),
                icon: const Icon(Icons.block, size: 14, color: Colors.white),
                label: const Text('No BG', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.pop(context, Colors.transparent),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                onPressed: () => Navigator.pop(context, currentColor),
                child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpinnerRow(String label, TextEditingController ctrl, String channel, int currentVal) {
    return Row(
      children: [
        SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        Container(
          width: 90,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) {
                    final parsed = int.tryParse(v) ?? 0;
                    final c = _currentColor;
                    int r = c.red, g = c.green, b = c.blue;
                    if (channel == 'R') r = parsed;
                    if (channel == 'G') g = parsed;
                    if (channel == 'B') b = parsed;
                    _updateFromRGB(r, g, b);
                  },
                ),
              ),
              Container(
                width: 22,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.grey.shade400)),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _stepChannel(channel, 1),
                        child: const Icon(Icons.arrow_drop_up, size: 14),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => _stepChannel(channel, -1),
                        child: const Icon(Icons.arrow_drop_down, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handlePanSpectrum(Offset pos, Size size) {
    final dx = pos.dx.clamp(0.0, size.width);
    final dy = pos.dy.clamp(0.0, size.height);
    setState(() {
      _hue = (dx / size.width) * 360.0;
      _saturation = 1.0 - (dy / size.height);
      _syncControllersFromHSV();
    });
  }

  void _handlePanValue(double dy, double height) {
    final clampY = dy.clamp(0.0, height);
    setState(() {
      _val = 1.0 - (clampY / height);
      _syncControllersFromHSV();
    });
  }
}

class _ColorSpectrumPainter extends CustomPainter {
  final double hue;
  final double saturation;

  _ColorSpectrumPainter({required this.hue, required this.saturation});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final hueGradient = LinearGradient(
      colors: const [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF00FF00),
        Color(0xFF00FFFF),
        Color(0xFF0000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ],
    );

    final paintHue = Paint()..shader = hueGradient.createShader(rect);
    canvas.drawRect(rect, paintHue);

    final satGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white,
        Colors.white.withAlpha(0),
        Colors.black.withAlpha(150),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final paintSat = Paint()..shader = satGradient.createShader(rect);
    canvas.drawRect(rect, paintSat);

    final posX = (hue / 360.0) * size.width;
    final posY = (1.0 - saturation) * size.height;

    final cursorPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(Offset(posX, posY), 6, cursorPaint);
    canvas.drawCircle(Offset(posX, posY), 5, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant _ColorSpectrumPainter old) =>
      old.hue != hue || old.saturation != saturation;
}

class _ValueBarPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;

  _ValueBarPainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width - 8, size.height);

    final pureColor = HSVColor.fromAHSV(1.0, hue, saturation, 1.0).toColor();

    final valGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white,
        pureColor,
        Colors.black,
      ],
    );

    final paintVal = Paint()..shader = valGradient.createShader(rect);
    canvas.drawRect(rect, paintVal);

    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.grey.shade600
        ..style = PaintingStyle.stroke,
    );

    final arrowY = (1.0 - value) * size.height;
    final arrowPath = Path()
      ..moveTo(size.width, arrowY - 5)
      ..lineTo(size.width - 7, arrowY)
      ..lineTo(size.width, arrowY + 5)
      ..close();

    canvas.drawPath(arrowPath, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant _ValueBarPainter old) =>
      old.hue != hue || old.saturation != saturation || old.value != value;
}

class _SearchableFontDropdown extends StatefulWidget {
  final String label;
  final String currentFont;
  final List<String> fontFamilies;
  final ValueChanged<String> onSelected;
  final bool isDark;

  const _SearchableFontDropdown({
    Key? key,
    required this.label,
    required this.currentFont,
    required this.fontFamilies,
    required this.onSelected,
    required this.isDark,
  }) : super(key: key);

  @override
  State<_SearchableFontDropdown> createState() => _SearchableFontDropdownState();
}

class _SearchableFontDropdownState extends State<_SearchableFontDropdown> {
  late TextEditingController _controller;
  bool _isExpanded = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentFont);
  }

  @override
  void didUpdateWidget(covariant _SearchableFontDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentFont != widget.currentFont && !_isExpanded) {
      _controller.text = widget.currentFont;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final filtered = widget.fontFamilies.where((f) {
      if (_searchQuery.isEmpty) return true;
      final qNorm = _searchQuery.toLowerCase().replaceAll(RegExp(r'[\s\-_\[\]]'), '');
      final fNorm = f.toLowerCase().replaceAll(RegExp(r'[\s\-_\[\]]'), '');
      return f.toLowerCase().contains(_searchQuery.toLowerCase()) || fNorm.contains(qNorm);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 4),
        ],
        Container(
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.white10 : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isExpanded ? const Color(0xFF0F766E) : Colors.grey.shade300,
              width: _isExpanded ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                style: TextStyle(
                  fontFamily: widget.fontFamilies.contains(_controller.text) ? _controller.text : null,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  hintText: '🔍 Search font (e.g. Jameel, Segoe)...',
                  hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 18,
                      color: const Color(0xFF0F766E),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                        if (_isExpanded) {
                          _searchQuery = '';
                        }
                      });
                    },
                  ),
                ),
                onTap: () {
                  setState(() {
                    _isExpanded = true;
                    _searchQuery = '';
                  });
                },
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _isExpanded = true;
                  });
                },
              ),
              if (_isExpanded) ...[
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No font found matching "${_searchQuery}"',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (ctx, idx) {
                            final fontName = filtered[idx];
                            final isSel = fontName == widget.currentFont;
                            return InkWell(
                              onTap: () {
                                widget.onSelected(fontName);
                                _controller.text = fontName;
                                setState(() {
                                  _isExpanded = false;
                                  _searchQuery = '';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                color: isSel ? const Color(0xFF0F766E).withAlpha(40) : null,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        fontName,
                                        style: TextStyle(
                                          fontFamily: fontName,
                                          fontSize: 12.5,
                                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                          color: isSel ? const Color(0xFF0F766E) : textColor,
                                        ),
                                      ),
                                    ),
                                    if (isSel)
                                      const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF0F766E)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatefulWidget {
  final String label;
  final double val;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool isDark;

  const _SliderRow({
    required this.label,
    required this.val,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.isDark,
  });

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.val.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant _SliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.val != widget.val) {
      final parsed = double.tryParse(_controller.text);
      if (parsed == null || (parsed - widget.val).abs() > 0.05) {
        _controller.text = widget.val.toStringAsFixed(1);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(widget.label,
                  style: AppTheme.getFontStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: textColor)),
            ),
            Container(
              width: 50,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: widget.isDark ? Colors.white10 : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF0284C7), width: 1)),
              child: TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: AppTheme.getFontStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0284C7)),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                ),
                onSubmitted: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null) {
                    final clamped = parsed.clamp(widget.min, widget.max);
                    widget.onChanged(clamped);
                    _controller.text = clamped.toStringAsFixed(1);
                  } else {
                    _controller.text = widget.val.toStringAsFixed(1);
                  }
                },
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null) {
                    widget.onChanged(parsed.clamp(widget.min, widget.max));
                  }
                },
              ),
            ),
          ],
        ),
        Row(children: [
          IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  size: 18, color: Color(0xFF0F766E)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                final nv = (widget.val - 0.5).clamp(widget.min, widget.max);
                widget.onChanged(nv);
                _controller.text = nv.toStringAsFixed(1);
              }),
          Expanded(
              child: Slider(
            value: widget.val.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            activeColor: const Color(0xFF0F766E),
            onChanged: (nv) {
              widget.onChanged(nv);
              _controller.text = nv.toStringAsFixed(1);
            },
          )),
          IconButton(
              icon: const Icon(Icons.add_circle_outline,
                  size: 18, color: Color(0xFF0F766E)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                final nv = (widget.val + 0.5).clamp(widget.min, widget.max);
                widget.onChanged(nv);
                _controller.text = nv.toStringAsFixed(1);
              }),
        ]),
      ],
    );
  }
}
