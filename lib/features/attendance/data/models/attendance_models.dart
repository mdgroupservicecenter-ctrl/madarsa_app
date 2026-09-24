class StudentAttendance {
  final String id;
  final String registrationNumber;
  final String? grNo;
  final String fullName;
  final String className;
  String? photoPath;
  bool hasFaceEnrolled;
  bool hasFingerprintEnrolled;
  String? faceData;
  String? fingerprintData;
  String? status;
  String remarks;
  String checkInTime;
  String checkOutTime;
  String verificationMethod;
  String shiftId;
  String shiftName;

  StudentAttendance({
    required this.id,
    this.registrationNumber = '',
    this.grNo,
    required this.fullName,
    this.className = '',
    this.photoPath,
    this.hasFaceEnrolled = false,
    this.hasFingerprintEnrolled = false,
    this.faceData,
    this.fingerprintData,
    this.status,
    this.remarks = '',
    this.checkInTime = '',
    this.checkOutTime = '',
    this.verificationMethod = 'Manual',
    this.shiftId = '',
    this.shiftName = '',
  });

  bool isEnrolledFor(String biometricType) {
    if (biometricType.toLowerCase().contains('face')) {
      return hasFaceEnrolled || (photoPath != null && photoPath!.trim().isNotEmpty);
    }
    if (biometricType.toLowerCase().contains('finger')) {
      return hasFingerprintEnrolled || (fingerprintData != null && fingerprintData!.trim().isNotEmpty);
    }
    return false;
  }

  factory StudentAttendance.fromJson(Map<String, dynamic> json) {
    final photo = json['photo_path']?.toString();
    final fData = json['face_data']?.toString();
    final fpData = json['fingerprint_data']?.toString();
    final faceEnrolled = json['has_face_enrolled'] == true || (fData != null && fData.isNotEmpty) || (photo != null && photo.isNotEmpty);
    final fpEnrolled = json['has_fingerprint_enrolled'] == true || (fpData != null && fpData.isNotEmpty);

    return StudentAttendance(
      id: json['id'] ?? '',
      registrationNumber: json['registration_number'] ?? '',
      grNo: json['gr_no'],
      fullName: json['full_name'] ?? '',
      className: json['class_name'] ?? '',
      photoPath: photo,
      hasFaceEnrolled: faceEnrolled,
      hasFingerprintEnrolled: fpEnrolled,
      faceData: fData,
      fingerprintData: fpData,
      status: json['status'],
      remarks: json['remarks'] ?? '',
      checkInTime: json['check_in_time'] ?? '',
      checkOutTime: json['check_out_time'] ?? '',
      verificationMethod: json['verification_method'] ?? 'Manual',
      shiftId: json['shift_id'] ?? '',
      shiftName: json['shift_name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student_id': id,
      'status': status,
      'remarks': remarks,
      'check_in_time': checkInTime,
      'check_out_time': checkOutTime,
      'verification_method': verificationMethod,
      'shift_id': shiftId,
      'shift_name': shiftName,
    };
  }
}

class StaffAttendance {
  final String id;
  final String staffNo;
  final String fullName;
  final String staffType;
  final String? mobileNo;
  String? status;
  String checkInTime;
  String checkOutTime;
  String remarks;
  String verificationMethod;

  StaffAttendance({
    required this.id,
    required this.staffNo,
    required this.fullName,
    required this.staffType,
    this.mobileNo,
    this.status,
    required this.checkInTime,
    required this.checkOutTime,
    required this.remarks,
    required this.verificationMethod,
  });

  factory StaffAttendance.fromJson(Map<String, dynamic> json) {
    return StaffAttendance(
      id: json['id'] ?? '',
      staffNo: json['staff_no'] ?? '',
      fullName: json['full_name'] ?? '',
      staffType: json['staff_type'] ?? '',
      mobileNo: json['mobile_no'],
      status: json['status'],
      checkInTime: json['check_in_time'] ?? '',
      checkOutTime: json['check_out_time'] ?? '',
      remarks: json['remarks'] ?? '',
      verificationMethod: json['verification_method'] ?? 'Manual',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'staff_id': id,
      'status': status,
      'check_in_time': checkInTime,
      'check_out_time': checkOutTime,
      'remarks': remarks,
      'verification_method': verificationMethod,
    };
  }
}

class PeriodAttendanceRecord {
  final String studentId;
  final String registrationNumber;
  final String? grNo;
  final String fullName;
  final String className;
  final String? classId;
  final String? periodId;
  final int? periodNumber;
  final String? date;
  final String? photoPath;
  String status; // 'Present' or 'Absent'
  String time; // '08:30:15 AM'
  String remarks;

  PeriodAttendanceRecord({
    required this.studentId,
    this.registrationNumber = '',
    this.grNo,
    this.fullName = '',
    this.className = '',
    this.classId,
    this.periodId,
    this.periodNumber,
    this.date,
    this.photoPath,
    this.status = 'Present',
    this.time = '',
    this.remarks = '',
  });

  PeriodAttendanceRecord copyWith({
    String? studentId,
    String? registrationNumber,
    String? grNo,
    String? fullName,
    String? className,
    String? classId,
    String? periodId,
    int? periodNumber,
    String? date,
    String? photoPath,
    String? status,
    String? time,
    String? remarks,
  }) {
    return PeriodAttendanceRecord(
      studentId: studentId ?? this.studentId,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      grNo: grNo ?? this.grNo,
      fullName: fullName ?? this.fullName,
      className: className ?? this.className,
      classId: classId ?? this.classId,
      periodId: periodId ?? this.periodId,
      periodNumber: periodNumber ?? this.periodNumber,
      date: date ?? this.date,
      photoPath: photoPath ?? this.photoPath,
      status: status ?? this.status,
      time: time ?? this.time,
      remarks: remarks ?? this.remarks,
    );
  }

  factory PeriodAttendanceRecord.fromJson(Map<String, dynamic> json) {
    return PeriodAttendanceRecord(
      studentId: json['student_id'] ?? json['id'] ?? '',
      registrationNumber: json['registration_number'] ?? '',
      grNo: json['gr_no'],
      fullName: json['full_name'] ?? '',
      className: json['class_name'] ?? '',
      classId: json['class_id']?.toString(),
      periodId: json['period_id']?.toString(),
      periodNumber: int.tryParse(json['period_number']?.toString() ?? ''),
      date: json['date']?.toString(),
      photoPath: json['photo_path'],
      status: json['status'] ?? 'Present',
      time: json['time'] ?? '',
      remarks: json['remarks'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'status': status,
      'time': time,
      'remarks': remarks,
      if (classId != null) 'class_id': classId,
      if (periodId != null) 'period_id': periodId,
      if (periodNumber != null) 'period_number': periodNumber,
      if (date != null) 'date': date,
    };
  }
}
