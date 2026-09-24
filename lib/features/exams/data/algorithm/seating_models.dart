class SeatPosition {
  final int row;
  final int col;
  final int seatNumber;

  const SeatPosition({
    required this.row,
    required this.col,
    required this.seatNumber,
  });

  @override
  String toString() => 'Seat($seatNumber: R$row-C$col)';

  @override
  bool operator ==(Object other) =>
      other is SeatPosition && row == other.row && col == other.col;

  @override
  int get hashCode => row.hashCode ^ col.hashCode;
}

class StudentSeatInput {
  final String studentId;
  final String studentName;
  final String registrationNumber;
  final String? rollNumber;
  final String classId;
  final String className;
  final String bookId;
  final String bookName;
  final double? meritScore;

  const StudentSeatInput({
    required this.studentId,
    required this.studentName,
    required this.registrationNumber,
    this.rollNumber,
    required this.classId,
    required this.className,
    required this.bookId,
    required this.bookName,
    this.meritScore,
  });

  @override
  String toString() => 'Student($studentName, book=$bookName)';
}

class SeatAssignment {
  final StudentSeatInput student;
  final SeatPosition seat;
  final String method;

  const SeatAssignment({
    required this.student,
    required this.seat,
    required this.method,
  });
}

class SeatHistoryEntry {
  final String studentId;
  final String bookId;
  final int hallId;
  final int seatRow;
  final int seatColumn;

  const SeatHistoryEntry({
    required this.studentId,
    required this.bookId,
    required this.hallId,
    required this.seatRow,
    required this.seatColumn,
  });
}

class SeatingResult {
  final List<SeatAssignment> assignments;
  final List<StudentSeatInput> overflow;
  final List<String> warnings;
  final String primaryMethod;
  final int totalStudents;
  final int placedCount;
  final int tier1Count;
  final int tier2Count;
  final int tier3Count;

  const SeatingResult({
    required this.assignments,
    this.overflow = const [],
    this.warnings = const [],
    required this.primaryMethod,
    required this.totalStudents,
    required this.placedCount,
    this.tier1Count = 0,
    this.tier2Count = 0,
    this.tier3Count = 0,
  });

  bool get hasOverflow => overflow.isNotEmpty;
  bool get isFullyAntiAdjacent => tier2Count == 0 && tier3Count == 0;
  double get placementRate =>
      totalStudents > 0 ? placedCount / totalStudents : 0;
}
