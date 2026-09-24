import 'dart:convert';

class StudentDocument {
  final String id;
  final String documentName;
  final String filePath;
  final String uploadedAt;

  StudentDocument({
    required this.id,
    required this.documentName,
    required this.filePath,
    required this.uploadedAt,
  });

  factory StudentDocument.fromJson(Map<String, dynamic> json) {
    return StudentDocument(
      id: json['id'],
      documentName: json['document_name'],
      filePath: json['file_path'],
      uploadedAt: json['uploaded_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'document_name': documentName,
      'file_path': filePath,
      'uploaded_at': uploadedAt,
    };
  }
}

String? _sanitizeRollNumber(String? val) {
  if (val == null) return null;
  final s = val.trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^\d{4}[-\/\.]\d{1,2}[-\/\.]\d{1,2}').hasMatch(s)) return null;
  if (RegExp(r'^\d{1,2}[-\/\.]\d{1,2}[-\/\.]\d{2,4}').hasMatch(s)) return null;
  return s;
}

class StudentSubDepartment {
  final String? subDepartmentId;
  final String? subDepartmentName;
  final String? className;
  final String? division;
  final String? rollNumber;

  StudentSubDepartment({
    this.subDepartmentId,
    this.subDepartmentName,
    this.className,
    this.division,
    this.rollNumber,
  });

  factory StudentSubDepartment.fromJson(Map<String, dynamic> json) {
    return StudentSubDepartment(
      subDepartmentId: json['sub_department_id']?.toString() ?? json['id']?.toString(),
      subDepartmentName: json['sub_department_name']?.toString() ?? json['name']?.toString(),
      className: json['class_name']?.toString(),
      division: json['division']?.toString(),
      rollNumber: _sanitizeRollNumber(json['roll_number']?.toString() ?? json['rollNumber']?.toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sub_department_id': subDepartmentId,
      'sub_department_name': subDepartmentName,
      'class_name': className,
      'division': division,
      if (rollNumber != null) 'roll_number': rollNumber,
    };
  }

  StudentSubDepartment copyWith({
    String? subDepartmentId,
    String? subDepartmentName,
    String? className,
    String? division,
    String? rollNumber,
  }) {
    return StudentSubDepartment(
      subDepartmentId: subDepartmentId ?? this.subDepartmentId,
      subDepartmentName: subDepartmentName ?? this.subDepartmentName,
      className: className ?? this.className,
      division: division ?? this.division,
      rollNumber: rollNumber ?? this.rollNumber,
    );
  }
}

class Student {
  final String id;
  final String? grNo;
  final String registrationNumber;
  final String fullName;
  final String? fatherName;
  final String? surname;
  final String? grandFatherName;
  final String? dateOfBirth;
  final String? village;
  final String? taluka;
  final String? district;
  final String? state;
  final String? pinCode;
  final String? address;
  final String? mobileNo;
  final String? aadhaarNo;
  final String? className;
  final String? studentStatus;
  final String? admissionType;
  final String? admissionDate;
  final String? admissionDateH;
  final String? conditionType;
  final double? monthlyFees;
  final String? gender;
  final String? enrollmentDate;
  final String? category;
  final String? division;
  final String? rollNumber;
  final String? photoPath;
  final bool isActive;
  final int totalAttendance;
  final num pendingFees;
  final double paidFees;
  final String? admissionTimeAge;
  final String? nowAge;
  final List<StudentDocument>? documents;
  final String? contributorId;
  final double? contributorAmount;
  final String? contributorName;
  final String? departmentId;
  final String? departmentName;
  final List<StudentSubDepartment>? subDepartments;
  final double? admissionFee;
  final double? bookFee;
  final String? feeStructure;
  final String? staffId;
  final String? staffName;

  Student({
    required this.id,
    this.grNo,
    required this.registrationNumber,
    required this.fullName,
    this.fatherName,
    this.surname,
    this.grandFatherName,
    this.dateOfBirth,
    this.village,
    this.taluka,
    this.district,
    this.state,
    this.pinCode,
    this.address,
    this.mobileNo,
    this.aadhaarNo,
    this.className,
    this.studentStatus,
    this.admissionType,
    this.admissionDate,
    this.admissionDateH,
    this.conditionType,
    this.monthlyFees,
    this.gender,
    this.enrollmentDate,
    this.category,
    this.division,
    this.rollNumber,
    this.photoPath,
    this.isActive = true,
    this.totalAttendance = 0,
    this.pendingFees = 0,
    this.paidFees = 0.0,
    this.admissionTimeAge,
    this.nowAge,
    this.documents,
    this.contributorId,
    this.contributorAmount,
    this.contributorName,
    this.departmentId,
    this.departmentName,
    this.subDepartments,
    this.admissionFee,
    this.bookFee,
    this.feeStructure,
    this.staffId,
    this.staffName,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    List<StudentSubDepartment>? parsedSubDepts;
    if (json['sub_departments'] != null) {
      if (json['sub_departments'] is String) {
        final str = (json['sub_departments'] as String).trim();
        if (str.isNotEmpty && str != 'null') {
          try {
            final decoded = jsonDecode(str);
            if (decoded is List) {
              parsedSubDepts = decoded
                  .map((i) => StudentSubDepartment.fromJson(Map<String, dynamic>.from(i)))
                  .toList();
            }
          } catch (e) {
            // parsing error fallback
          }
        }
      } else if (json['sub_departments'] is List) {
        parsedSubDepts = (json['sub_departments'] as List)
            .map((i) => StudentSubDepartment.fromJson(Map<String, dynamic>.from(i)))
            .toList();
      }
    }

    return Student(
      id: json['id'],
      grNo: json['gr_no'],
      registrationNumber: json['registration_number'] ?? json['gr_no'] ?? '',
      fullName: json['full_name'] ?? '',
      fatherName: json['father_name'],
      surname: json['surname'],
      grandFatherName: json['grand_father_name'],
      dateOfBirth: json['date_of_birth'],
      village: json['village'],
      taluka: json['taluka'],
      district: json['district'],
      state: json['state'],
      pinCode: json['pin_code'],
      address: json['address'],
      mobileNo: json['mobile_no'],
      aadhaarNo: json['aadhaar_no'],
      className: json['class_name'],
      studentStatus: json['student_status'],
      admissionType: json['admission_type'],
      admissionDate: json['admission_date'],
      admissionDateH: json['admission_date_h'],
      conditionType: json['condition_type'],
      monthlyFees: json['monthly_fees'] != null
          ? (json['monthly_fees'] as num).toDouble()
          : null,
      gender: json['gender'],
      enrollmentDate: json['enrollment_date'],
      category: json['category'],
      division: json['division'],
      rollNumber: _sanitizeRollNumber(json['roll_number']?.toString()),
      photoPath: json['photo_path'],
      isActive: json['is_active'] == 1 || json['is_active'] == true,
      totalAttendance: json['total_attendance'] ?? 0,
      pendingFees: json['pending_fees'] ?? 0,
      paidFees: (json['paid_fees'] as num?)?.toDouble() ?? (json['total_paid'] as num?)?.toDouble() ?? 0.0,
      admissionTimeAge: json['admission_time_age'],
      nowAge: json['now_age'],
      documents: json['documents'] != null
          ? (json['documents'] as List)
                .map((i) => StudentDocument.fromJson(i))
                .toList()
          : null,
      contributorId: json['contributor_id'],
      contributorAmount: json['contributor_amount'] != null
          ? (json['contributor_amount'] as num).toDouble()
          : null,
      contributorName: json['contributor_name'],
      departmentId: json['department_id'],
      departmentName: json['department_name'],
      subDepartments: parsedSubDepts,
      admissionFee: json['admission_fee'] != null
          ? (json['admission_fee'] as num).toDouble()
          : null,
      bookFee: json['book_fee'] != null
          ? (json['book_fee'] as num).toDouble()
          : null,
      feeStructure: json['fee_structure']?.toString(),
      staffId: json['staff_id']?.toString() ?? json['staffId']?.toString(),
      staffName: json['staff_name']?.toString() ?? json['staffName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gr_no': grNo,
      'registration_number': registrationNumber,
      'full_name': fullName,
      'father_name': fatherName,
      'surname': surname,
      'grand_father_name': grandFatherName,
      'date_of_birth': dateOfBirth,
      'village': village,
      'taluka': taluka,
      'district': district,
      'state': state,
      'pin_code': pinCode,
      'address': address,
      'mobile_no': mobileNo,
      'aadhaar_no': aadhaarNo,
      'class_name': className,
      'student_status': studentStatus,
      'admission_type': admissionType,
      'admission_date': admissionDate,
      'admission_date_h': admissionDateH,
      'condition_type': conditionType,
      'monthly_fees': monthlyFees,
      'gender': gender,
      'enrollment_date': enrollmentDate,
      'category': category,
      'division': division,
      'roll_number': rollNumber,
      'photo_path': photoPath,
      'is_active': isActive ? 1 : 0,
      'contributor_id': contributorId,
      'contributor_amount': contributorAmount,
      'contributor_name': contributorName,
      'admission_time_age': admissionTimeAge,
      'now_age': nowAge,
      'department_id': departmentId,
      'department_name': departmentName,
      'sub_departments': subDepartments != null
          ? jsonEncode(subDepartments!.map((s) => s.toJson()).toList())
          : null,
      'documents': documents?.map((d) => d.toJson()).toList(),
      'admission_fee': admissionFee,
      'book_fee': bookFee,
      'fee_structure': feeStructure,
      if (staffId != null) 'staff_id': staffId,
      if (staffName != null) 'staff_name': staffName,
    };
  }

  Student copyWith({
    String? id,
    String? grNo,
    String? registrationNumber,
    String? fullName,
    String? fatherName,
    String? surname,
    String? grandFatherName,
    String? dateOfBirth,
    String? village,
    String? taluka,
    String? district,
    String? state,
    String? pinCode,
    String? address,
    String? mobileNo,
    String? aadhaarNo,
    String? className,
    String? studentStatus,
    String? admissionType,
    String? admissionDate,
    String? admissionDateH,
    String? conditionType,
    double? monthlyFees,
    String? gender,
    String? enrollmentDate,
    String? category,
    String? division,
    String? rollNumber,
    String? photoPath,
    bool? isActive,
    int? totalAttendance,
    num? pendingFees,
    double? paidFees,
    String? admissionTimeAge,
    String? nowAge,
    List<StudentDocument>? documents,
    String? contributorId,
    double? contributorAmount,
    String? contributorName,
    String? departmentId,
    String? departmentName,
    List<StudentSubDepartment>? subDepartments,
    double? admissionFee,
    double? bookFee,
    String? feeStructure,
    String? staffId,
    String? staffName,
  }) {
    return Student(
      id: id ?? this.id,
      grNo: grNo ?? this.grNo,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      fullName: fullName ?? this.fullName,
      fatherName: fatherName ?? this.fatherName,
      surname: surname ?? this.surname,
      grandFatherName: grandFatherName ?? this.grandFatherName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      village: village ?? this.village,
      taluka: taluka ?? this.taluka,
      district: district ?? this.district,
      state: state ?? this.state,
      pinCode: pinCode ?? this.pinCode,
      address: address ?? this.address,
      mobileNo: mobileNo ?? this.mobileNo,
      aadhaarNo: aadhaarNo ?? this.aadhaarNo,
      className: className ?? this.className,
      studentStatus: studentStatus ?? this.studentStatus,
      admissionType: admissionType ?? this.admissionType,
      admissionDate: admissionDate ?? this.admissionDate,
      admissionDateH: admissionDateH ?? this.admissionDateH,
      conditionType: conditionType ?? this.conditionType,
      monthlyFees: monthlyFees ?? this.monthlyFees,
      gender: gender ?? this.gender,
      enrollmentDate: enrollmentDate ?? this.enrollmentDate,
      category: category ?? this.category,
      division: division ?? this.division,
      rollNumber: rollNumber ?? this.rollNumber,
      photoPath: photoPath ?? this.photoPath,
      isActive: isActive ?? this.isActive,
      totalAttendance: totalAttendance ?? this.totalAttendance,
      pendingFees: pendingFees ?? this.pendingFees,
      paidFees: paidFees ?? this.paidFees,
      admissionTimeAge: admissionTimeAge ?? this.admissionTimeAge,
      nowAge: nowAge ?? this.nowAge,
      documents: documents ?? this.documents,
      contributorId: contributorId ?? this.contributorId,
      contributorAmount: contributorAmount ?? this.contributorAmount,
      contributorName: contributorName ?? this.contributorName,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      subDepartments: subDepartments ?? this.subDepartments,
      admissionFee: admissionFee ?? this.admissionFee,
      bookFee: bookFee ?? this.bookFee,
      feeStructure: feeStructure ?? this.feeStructure,
      staffId: staffId ?? this.staffId,
      staffName: staffName ?? this.staffName,
    );
  }
}
