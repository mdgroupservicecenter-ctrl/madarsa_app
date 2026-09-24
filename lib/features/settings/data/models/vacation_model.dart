class Vacation {
  final String id;
  final String? academicYearId;
  final String title;
  final String? titleUrdu;
  final String startDate; // YYYY-MM-DD
  final String endDate; // YYYY-MM-DD
  final String? startDateHijri;
  final String? endDateHijri;
  final String vacationType; // 'Ramzan', 'Eid', 'Summer', 'Winter', 'General'
  final int totalDays;
  final String? remarks;
  final String? createdAt;
  final String? updatedAt;

  Vacation({
    required this.id,
    this.academicYearId,
    required this.title,
    this.titleUrdu,
    required this.startDate,
    required this.endDate,
    this.startDateHijri,
    this.endDateHijri,
    this.vacationType = 'General',
    this.totalDays = 0,
    this.remarks,
    this.createdAt,
    this.updatedAt,
  });

  factory Vacation.fromJson(Map<String, dynamic> json) {
    return Vacation(
      id: json['id']?.toString() ?? '',
      academicYearId: json['academic_year_id']?.toString(),
      title: json['title']?.toString() ?? '',
      titleUrdu: json['title_urdu']?.toString(),
      startDate: json['start_date']?.toString() ?? '',
      endDate: json['end_date']?.toString() ?? '',
      startDateHijri: json['start_date_hijri']?.toString(),
      endDateHijri: json['end_date_hijri']?.toString(),
      vacationType: json['vacation_type']?.toString() ?? 'General',
      totalDays: (json['total_days'] as num?)?.toInt() ?? 0,
      remarks: json['remarks']?.toString(),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'academic_year_id': academicYearId,
      'title': title,
      'title_urdu': titleUrdu,
      'start_date': startDate,
      'end_date': endDate,
      'start_date_hijri': startDateHijri,
      'end_date_hijri': endDateHijri,
      'vacation_type': vacationType,
      'total_days': totalDays,
      'remarks': remarks,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Vacation copyWith({
    String? id,
    String? academicYearId,
    String? title,
    String? titleUrdu,
    String? startDate,
    String? endDate,
    String? startDateHijri,
    String? endDateHijri,
    String? vacationType,
    int? totalDays,
    String? remarks,
    String? createdAt,
    String? updatedAt,
  }) {
    return Vacation(
      id: id ?? this.id,
      academicYearId: academicYearId ?? this.academicYearId,
      title: title ?? this.title,
      titleUrdu: titleUrdu ?? this.titleUrdu,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      startDateHijri: startDateHijri ?? this.startDateHijri,
      endDateHijri: endDateHijri ?? this.endDateHijri,
      vacationType: vacationType ?? this.vacationType,
      totalDays: totalDays ?? this.totalDays,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
