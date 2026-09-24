import '../../../../core/network/api_client.dart';
import '../../../../core/constants/app_constants.dart';

class DesignerStudentItem {
  final String id;
  final String fullName;
  final String? fatherName;
  final String? grandFatherName;
  final String? surname;
  final String? grNo;
  final String? rollNumber;
  final String? className;
  final String? dateOfBirth;
  final String? mobileNo;
  final String? village;
  final String? taluka;
  final String? district;
  final String? state;
  final String? pinCode;
  final String? address;
  final String? aadhaarNo;
  final String? gender;
  final String? photoUrl;

  DesignerStudentItem({
    required this.id,
    required this.fullName,
    this.fatherName,
    this.grandFatherName,
    this.surname,
    this.grNo,
    this.rollNumber,
    this.className,
    this.dateOfBirth,
    this.mobileNo,
    this.village,
    this.taluka,
    this.district,
    this.state,
    this.pinCode,
    this.address,
    this.aadhaarNo,
    this.gender,
    this.photoUrl,
  });

  String get combinedName {
    final parts = [fullName, fatherName, grandFatherName, surname]
        .where((p) => p != null && p.trim().isNotEmpty && p != '-')
        .toList();
    return parts.isEmpty ? fullName : parts.join(' ');
  }

  String get combinedAddress {
    final parts = [address, village, taluka, district, state, pinCode]
        .where((p) => p != null && p.trim().isNotEmpty && p != '-')
        .toList();
    return parts.isEmpty ? (address ?? 'N/A') : parts.join(', ');
  }

  Map<String, String> toTokensMap() {
    return {
      '{{student.name}}': fullName,
      '{{student.father_name}}': fatherName ?? '-',
      '{{student.grand_father}}': grandFatherName ?? '-',
      '{{student.surname}}': surname ?? '-',
      '{{student.combined_name}}': combinedName,
      '{{student.gr_no}}': grNo ?? 'GR-001',
      '{{student.roll_no}}': rollNumber ?? '01',
      '{{student.class_name}}': className ?? 'دارالعلوم',
      '{{student.dob}}': dateOfBirth ?? '01/01/2010',
      '{{student.phone}}': mobileNo ?? '+91 98765 43210',
      '{{student.address}}': address ?? '-',
      '{{student.village}}': village ?? '-',
      '{{student.taluka}}': taluka ?? '-',
      '{{student.district}}': district ?? '-',
      '{{student.state}}': state ?? '-',
      '{{student.pin_code}}': pinCode ?? '-',
      '{{student.combined_address}}': combinedAddress,
      '{{student.aadhaar}}': aadhaarNo ?? '**** **** ****',
      '{{student.gender}}': gender ?? 'مرد',
    };
  }
}

class DesignerStaffItem {
  final String id;
  final String fullName;
  final String? designation;
  final String? department;
  final String? mobileNo;
  final String? employeeId;
  final String? photoUrl;

  DesignerStaffItem({
    required this.id,
    required this.fullName,
    this.designation,
    this.department,
    this.mobileNo,
    this.employeeId,
    this.photoUrl,
  });

  Map<String, String> toTokensMap() {
    return {
      '{{staff.name}}': fullName,
      '{{staff.designation}}': designation ?? 'استاذ / مدرس',
      '{{staff.department}}': department ?? 'شعبہ تدریس',
      '{{staff.phone}}': mobileNo ?? '+91 98765 00000',
      '{{staff.employee_id}}': employeeId ?? 'EMP-01',
    };
  }
}

class DesignerDataService {
  static final ApiClient _apiClient = ApiClient();

  /// Fetch students list from local backend or fallback
  static Future<List<DesignerStudentItem>> fetchStudents({String? classFilter}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (classFilter != null && classFilter.isNotEmpty && classFilter != 'All Classes') {
        queryParams['class_name'] = classFilter;
      }
      final res = await _apiClient.get(ApiConstants.students, queryParams: queryParams);
      if (res.statusCode == 200 && res.data != null) {
        final List<dynamic> list = res.data['students'] is List
            ? res.data['students']
            : (res.data is List ? res.data : []);
        if (list.isNotEmpty) {
          return list.map((json) {
            final m = Map<String, dynamic>.from(json as Map);
            return DesignerStudentItem(
              id: m['id']?.toString() ?? '',
              fullName: m['full_name']?.toString() ?? m['name']?.toString() ?? 'طالب علم',
              fatherName: m['father_name']?.toString(),
              grandFatherName: m['grand_father_name']?.toString(),
              surname: m['surname']?.toString(),
              grNo: m['gr_no']?.toString() ?? m['registration_number']?.toString(),
              rollNumber: m['roll_number']?.toString(),
              className: m['class_name']?.toString(),
              dateOfBirth: m['date_of_birth']?.toString(),
              mobileNo: m['mobile_no']?.toString() ?? m['mobile']?.toString(),
              village: m['village']?.toString(),
              taluka: m['taluka']?.toString(),
              district: m['district']?.toString(),
              state: m['state']?.toString(),
              pinCode: m['pin_code']?.toString(),
              address: m['address']?.toString(),
              aadhaarNo: m['aadhaar_no']?.toString(),
              gender: m['gender']?.toString(),
              photoUrl: m['photo_url']?.toString(),
            );
          }).toList();
        }
      }
    } catch (_) {}

    // Fallback Sample Students
    return [
      DesignerStudentItem(
        id: 'sample_1',
        fullName: 'محمد زید بن خالد انصاری',
        fatherName: 'مولانا خالد احمد انصاری',
        grandFatherName: 'احمد حسن',
        surname: 'انصاری',
        grNo: 'GR-1045',
        rollNumber: '25',
        className: 'درجہ رابعہ (عالمیت)',
        dateOfBirth: '12/05/2006',
        mobileNo: '+91 98765 43210',
        village: 'پھولپور',
        taluka: 'نظام آباد',
        district: 'اعظم گڑھ',
        state: 'اتر پردیش',
        pinCode: '276001',
        address: 'قاسم العلوم محلہ، مکان نمبر 45',
        aadhaarNo: '1234 5678 9012',
        gender: 'مرد',
      ),
      DesignerStudentItem(
        id: 'sample_2',
        fullName: 'عبد اللہ بن ساجد قریشی',
        fatherName: 'ساجد علی قریشی',
        grandFatherName: 'علی حسین',
        surname: 'قریشی',
        grNo: 'GR-1046',
        rollNumber: '26',
        className: 'درجہ خامسہ (حفظ)',
        dateOfBirth: '18/09/2008',
        mobileNo: '+91 98765 11223',
        village: 'شاہ گنج',
        taluka: 'جونپور',
        district: 'جونپور',
        state: 'اتر پردیش',
        pinCode: '223101',
        address: 'مین مارکیٹ، نزد جامع مسجد',
        aadhaarNo: '9876 5432 1098',
        gender: 'مرد',
      ),
    ];
  }

  /// Fetch classes list from backend
  static Future<List<String>> fetchClasses() async {
    try {
      final res = await _apiClient.get(ApiConstants.classes);
      if (res.statusCode == 200 && res.data != null) {
        final List<dynamic> list = res.data['classes'] is List
            ? res.data['classes']
            : (res.data is List ? res.data : []);
        final classes = list.map((e) => e['name']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        if (classes.isNotEmpty) return classes;
      }
    } catch (_) {}
    return ['درجہ اولیٰ', 'درجہ ثانیہ', 'درجہ ثالثہ', 'درجہ رابعہ', 'درجہ خامسہ', 'حفظ القرآن'];
  }

  /// Fetch staff list from local backend or fallback
  static Future<List<DesignerStaffItem>> fetchStaff() async {
    try {
      final res = await _apiClient.get(ApiConstants.staff);
      if (res.statusCode == 200 && res.data != null) {
        final List<dynamic> list = res.data['staff'] is List
            ? res.data['staff']
            : (res.data is List ? res.data : []);
        if (list.isNotEmpty) {
          return list.map((json) {
            final m = Map<String, dynamic>.from(json as Map);
            return DesignerStaffItem(
              id: m['id']?.toString() ?? '',
              fullName: m['name']?.toString() ?? m['full_name']?.toString() ?? 'ملازم',
              designation: m['designation']?.toString() ?? 'استاذ',
              department: m['department']?.toString() ?? 'تعلیمی',
              mobileNo: m['phone']?.toString() ?? m['mobile']?.toString(),
              employeeId: m['employee_id']?.toString() ?? 'EMP-01',
              photoUrl: m['photo_url']?.toString(),
            );
          }).toList();
        }
      }
    } catch (_) {}

    return [
      DesignerStaffItem(
        id: 'staff_1',
        fullName: 'مولانا مفتی محمد سلمان قاسمی',
        designation: 'شیخ الحدیث و صدر المدرسین',
        department: 'شعبہ درس نظامی',
        mobileNo: '+91 98765 88990',
        employeeId: 'EMP-001',
      ),
      DesignerStaffItem(
        id: 'staff_2',
        fullName: 'قاری عبد الرشید حفظہ اللہ',
        designation: 'استاذ تجوید و قراءت',
        department: 'شعبہ حفظ و قراءت',
        mobileNo: '+91 98765 77665',
        employeeId: 'EMP-002',
      ),
    ];
  }
}
