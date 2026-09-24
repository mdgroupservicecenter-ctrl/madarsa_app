class AttendanceReport {
  final String date;
  final int present;
  final int absent;
  final int late;
  final List<String> absentNames;

  AttendanceReport({
    required this.date,
    required this.present,
    required this.absent,
    required this.late,
    required this.absentNames,
  });

  factory AttendanceReport.fromJson(Map<String, dynamic> json) {
    return AttendanceReport(
      date: json['date'] ?? '',
      present: json['present'] ?? 0,
      absent: json['absent'] ?? 0,
      late: json['late'] ?? 0,
      absentNames: List<String>.from(json['absent_names'] ?? []),
    );
  }
}

class FeeSummary {
  final double totalCollected;
  final double totalPending;
  final double totalExpected;

  FeeSummary({
    required this.totalCollected,
    required this.totalPending,
    required this.totalExpected,
  });

  factory FeeSummary.fromJson(Map<String, dynamic> json) {
    return FeeSummary(
      totalCollected: (json['totalCollected'] ?? 0).toDouble(),
      totalPending: (json['totalPending'] ?? 0).toDouble(),
      totalExpected: (json['totalExpected'] ?? 0).toDouble(),
    );
  }
}

class FeeBreakdown {
  final String type;
  final String status;
  final double total;

  FeeBreakdown({
    required this.type,
    required this.status,
    required this.total,
  });

  factory FeeBreakdown.fromJson(Map<String, dynamic> json) {
    return FeeBreakdown(
      type: json['fee_type'] ?? '',
      status: json['status'] ?? '',
      total: (json['total'] ?? 0).toDouble(),
    );
  }
}

class StudentStats {
  final int total;
  final List<ClassStat> byClass;
  final List<GenderStat> byGender;

  StudentStats({
    required this.total,
    required this.byClass,
    required this.byGender,
  });

  factory StudentStats.fromJson(Map<String, dynamic> json) {
    return StudentStats(
      total: json['total'] ?? 0,
      byClass: (json['byClass'] as List? ?? [])
          .map((item) => ClassStat.fromJson(item))
          .toList(),
      byGender: (json['byGender'] as List? ?? [])
          .map((item) => GenderStat.fromJson(item))
          .toList(),
    );
  }
}

class ClassStat {
  final String className;
  final int count;
  final int male;
  final int female;

  ClassStat({
    required this.className,
    required this.count,
    required this.male,
    required this.female,
  });

  factory ClassStat.fromJson(Map<String, dynamic> json) {
    return ClassStat(
      className: json['class_name'] ?? '',
      count: json['count'] ?? 0,
      male: json['male'] ?? 0,
      female: json['female'] ?? 0,
    );
  }
}

class GenderStat {
  final String gender;
  final int count;

  GenderStat({
    required this.gender,
    required this.count,
  });

  factory GenderStat.fromJson(Map<String, dynamic> json) {
    return GenderStat(
      gender: json['gender'] ?? '',
      count: json['count'] ?? 0,
    );
  }
}
