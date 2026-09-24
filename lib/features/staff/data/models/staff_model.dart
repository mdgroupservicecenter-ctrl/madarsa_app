class StaffMember {
  final String id;
  final String staffNo;
  final String fullName;
  final String? fatherName;
  final String? surname;
  final String? dateOfBirth;
  final String? gender;
  final String staffType;
  final String? qualification;
  final int experienceYears;
  final String? joiningDate;
  final String? joiningDateH;
  final double salary;
  final String? mobileNo;
  final String? aadhaarNo;
  final String? village;
  final String? taluka;
  final String? district;
  final String? state;
  final String? pinCode;
  final String? emergencyContact;
  final String? address;
  final bool isActive;
  final String? note;
  final String? roleId;
  final String? roleName;
  final String? userId;
  final String? photoPath;
  final String? createdAt;
  final String? updatedAt;
  final List<dynamic>? assignedBooks;

  const StaffMember({
    required this.id,
    required this.staffNo,
    required this.fullName,
    this.fatherName,
    this.surname,
    this.dateOfBirth,
    this.gender,
    required this.staffType,
    this.qualification,
    this.experienceYears = 0,
    this.joiningDate,
    this.joiningDateH,
    this.salary = 0,
    this.mobileNo,
    this.aadhaarNo,
    this.village,
    this.taluka,
    this.district,
    this.state,
    this.pinCode,
    this.emergencyContact,
    this.address,
    this.isActive = true,
    this.note,
    this.roleId,
    this.roleName,
    this.userId,
    this.photoPath,
    this.createdAt,
    this.updatedAt,
    this.assignedBooks,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id'] ?? '',
      staffNo: json['staff_no'] ?? '',
      fullName: json['full_name'] ?? '',
      fatherName: json['father_name'],
      surname: json['surname'],
      dateOfBirth: json['date_of_birth'],
      gender: json['gender'],
      staffType: json['staff_type'] ?? 'Teacher',
      qualification: json['qualification'],
      experienceYears: (json['experience_years'] as num?)?.toInt() ?? 0,
      joiningDate: json['joining_date'],
      joiningDateH: json['joining_date_h'],
      salary: (json['salary'] as num?)?.toDouble() ?? 0,
      mobileNo: json['mobile_no'],
      aadhaarNo: json['aadhaar_no'],
      village: json['village'],
      taluka: json['taluka'],
      district: json['district'],
      state: json['state'],
      pinCode: json['pin_code'],
      emergencyContact: json['emergency_contact'],
      address: json['address'],
      isActive: json['is_active'] == 1 || json['is_active'] == true,
      note: json['note'],
      roleId: json['role_id'],
      roleName: json['role_name'],
      userId: json['user_id'],
      photoPath: json['photo_path'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      assignedBooks: json['assigned_books'] as List<dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'staff_no': staffNo,
        'full_name': fullName,
        'father_name': fatherName,
        'surname': surname,
        'date_of_birth': dateOfBirth,
        'gender': gender,
        'staff_type': staffType,
        'qualification': qualification,
        'experience_years': experienceYears,
        'joining_date': joiningDate,
        'joining_date_h': joiningDateH,
        'salary': salary,
        'mobile_no': mobileNo,
        'aadhaar_no': aadhaarNo,
        'village': village,
        'taluka': taluka,
        'district': district,
        'state': state,
        'pin_code': pinCode,
        'emergency_contact': emergencyContact,
        'address': address,
        'is_active': isActive ? 1 : 0,
        'note': note,
        'role_id': roleId,
        'role_name': roleName,
        'user_id': userId,
        'photo_path': photoPath,
        'assigned_books': assignedBooks,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  StaffMember copyWith({
    String? id,
    String? staffNo,
    String? fullName,
    String? fatherName,
    String? surname,
    String? dateOfBirth,
    String? gender,
    String? staffType,
    String? qualification,
    int? experienceYears,
    String? joiningDate,
    String? joiningDateH,
    double? salary,
    String? mobileNo,
    String? aadhaarNo,
    String? village,
    String? taluka,
    String? district,
    String? state,
    String? pinCode,
    String? emergencyContact,
    String? address,
    bool? isActive,
    String? note,
    String? roleId,
    String? roleName,
    String? userId,
    String? photoPath,
    List<dynamic>? assignedBooks,
  }) {
    return StaffMember(
      id: id ?? this.id,
      staffNo: staffNo ?? this.staffNo,
      fullName: fullName ?? this.fullName,
      fatherName: fatherName ?? this.fatherName,
      surname: surname ?? this.surname,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      staffType: staffType ?? this.staffType,
      qualification: qualification ?? this.qualification,
      experienceYears: experienceYears ?? this.experienceYears,
      joiningDate: joiningDate ?? this.joiningDate,
      joiningDateH: joiningDateH ?? this.joiningDateH,
      salary: salary ?? this.salary,
      mobileNo: mobileNo ?? this.mobileNo,
      aadhaarNo: aadhaarNo ?? this.aadhaarNo,
      village: village ?? this.village,
      taluka: taluka ?? this.taluka,
      district: district ?? this.district,
      state: state ?? this.state,
      pinCode: pinCode ?? this.pinCode,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      address: address ?? this.address,
      isActive: isActive ?? this.isActive,
      note: note ?? this.note,
      roleId: roleId ?? this.roleId,
      roleName: roleName ?? this.roleName,
      userId: userId ?? this.userId,
      photoPath: photoPath ?? this.photoPath,
      createdAt: createdAt,
      updatedAt: updatedAt,
      assignedBooks: assignedBooks ?? this.assignedBooks,
    );
  }

  // Helper
  String get displayName => fullName;
  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : 'S';
  }
}
