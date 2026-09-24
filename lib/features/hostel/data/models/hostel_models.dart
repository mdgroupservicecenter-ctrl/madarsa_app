class Hostel {
  final String id;
  final String name;
  final String? description;
  final int roomCount;
  final int capacity; // total beds
  final int occupiedCount; // occupied beds

  Hostel({
    required this.id,
    required this.name,
    this.description,
    required this.roomCount,
    required this.capacity,
    required this.occupiedCount,
  });

  factory Hostel.fromJson(Map<String, dynamic> json) {
    return Hostel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      roomCount: (json['room_count'] as num?)?.toInt() ?? 0,
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      occupiedCount: (json['occupied_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'room_count': roomCount,
      'capacity': capacity,
      'occupied_count': occupiedCount,
    };
  }
}

class HostelRoom {
  final String id;
  final String hostelId;
  final String roomNumber;
  final String? description;
  final String? hostelName;
  final int bedCount;
  final int occupiedCount;
  final int vacantCount;

  HostelRoom({
    required this.id,
    required this.hostelId,
    required this.roomNumber,
    this.description,
    this.hostelName,
    required this.bedCount,
    required this.occupiedCount,
    required this.vacantCount,
  });

  factory HostelRoom.fromJson(Map<String, dynamic> json) {
    return HostelRoom(
      id: json['id'] as String? ?? '',
      hostelId: json['hostel_id'] as String? ?? '',
      roomNumber: json['room_number'] as String? ?? '',
      description: json['description'] as String?,
      hostelName: json['hostel_name'] as String?,
      bedCount: (json['bed_count'] as num?)?.toInt() ?? 0,
      occupiedCount: (json['occupied_count'] as num?)?.toInt() ?? 0,
      vacantCount: (json['vacant_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hostel_id': hostelId,
      'room_number': roomNumber,
      'description': description,
      'hostel_name': hostelName,
      'bed_count': bedCount,
      'occupied_count': occupiedCount,
      'vacant_count': vacantCount,
    };
  }
}

class HostelBed {
  final String id;
  final String roomId;
  final String bedNumber;
  final String? description;
  final int isOccupied;
  final String? allocationId;
  final String? studentId;
  final String? studentName;
  final String? studentGrNo;

  HostelBed({
    required this.id,
    required this.roomId,
    required this.bedNumber,
    this.description,
    required this.isOccupied,
    this.allocationId,
    this.studentId,
    this.studentName,
    this.studentGrNo,
  });

  factory HostelBed.fromJson(Map<String, dynamic> json) {
    return HostelBed(
      id: json['id'] as String? ?? '',
      roomId: json['room_id'] as String? ?? '',
      bedNumber: json['bed_number'] as String? ?? '',
      description: json['description'] as String?,
      isOccupied: (json['is_occupied'] as num?)?.toInt() ?? 0,
      allocationId: json['allocation_id'] as String?,
      studentId: json['student_id'] as String?,
      studentName: json['student_name'] as String?,
      studentGrNo: json['student_gr_no'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'bed_number': bedNumber,
      'description': description,
      'is_occupied': isOccupied,
      'allocation_id': allocationId,
      'student_id': studentId,
      'student_name': studentName,
      'student_gr_no': studentGrNo,
    };
  }
}

class HostelAllocation {
  final String id;
  final String bedId;
  final String bedNumber;
  final String studentId;
  final String studentName;
  final String? fatherName;
  final String? surname;
  final String? grNo;
  final String? village;
  final String? registrationNumber;
  final String? className;
  final int? age;
  final String roomId;
  final String roomNumber;
  final String hostelId;
  final String hostelName;
  final String allocationDate;
  final String status;
  final String? vacateDate;

  HostelAllocation({
    required this.id,
    required this.bedId,
    required this.bedNumber,
    required this.studentId,
    required this.studentName,
    this.fatherName,
    this.surname,
    this.grNo,
    this.village,
    this.registrationNumber,
    this.className,
    this.age,
    required this.roomId,
    required this.roomNumber,
    required this.hostelId,
    required this.hostelName,
    required this.allocationDate,
    required this.status,
    this.vacateDate,
  });

  factory HostelAllocation.fromJson(Map<String, dynamic> json) {
    return HostelAllocation(
      id: json['id'] as String? ?? '',
      bedId: json['bed_id'] as String? ?? '',
      bedNumber: json['bed_number'] as String? ?? '',
      studentId: json['student_id'] as String? ?? '',
      studentName: json['student_name'] as String? ?? '',
      fatherName: json['father_name'] as String?,
      surname: json['surname'] as String?,
      grNo: json['gr_no'] as String?,
      village: json['village'] as String?,
      registrationNumber: json['registration_number'] as String?,
      className: json['class_name'] as String?,
      age: (json['age'] as num?)?.toInt(),
      roomId: json['room_id'] as String? ?? '',
      roomNumber: json['room_number'] as String? ?? '',
      hostelId: json['hostel_id'] as String? ?? '',
      hostelName: json['hostel_name'] as String? ?? '',
      allocationDate: json['allocation_date'] as String? ?? '',
      status: json['status'] as String? ?? 'Active',
      vacateDate: json['vacate_date'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bed_id': bedId,
      'bed_number': bedNumber,
      'student_id': studentId,
      'student_name': studentName,
      'father_name': fatherName,
      'surname': surname,
      'gr_no': grNo,
      'village': village,
      'registration_number': registrationNumber,
      'class_name': className,
      'age': age,
      'room_id': roomId,
      'room_number': roomNumber,
      'hostel_id': hostelId,
      'hostel_name': hostelName,
      'allocation_date': allocationDate,
      'status': status,
      'vacate_date': vacateDate,
    };
  }
}
