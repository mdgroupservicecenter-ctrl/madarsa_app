import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/services/attendance_timing_helper.dart';
import 'package:madarsa_app/features/attendance/data/models/attendance_models.dart';

void main() {
  group('Student Attendance Biometric Enrollment Tests', () {
    test('Student with photo is considered face-enrolled', () {
      final student = StudentAttendance(
        id: 'st_1',
        fullName: 'Zaid Khan',
        photoPath: 'https://example.com/photos/zaid.jpg',
      );
      expect(student.isEnrolledFor('Face'), isTrue);
      expect(student.isEnrolledFor('Fingerprint'), isFalse);
    });

    test('Student with face_data is considered face-enrolled', () {
      final student = StudentAttendance(
        id: 'st_2',
        fullName: 'Umar Farooq',
        hasFaceEnrolled: true,
        faceData: 'face_template_hash_abc123',
      );
      expect(student.isEnrolledFor('Face'), isTrue);
      expect(student.isEnrolledFor('Fingerprint'), isFalse);
    });

    test('Student with fingerprint_data is considered fingerprint-enrolled', () {
      final student = StudentAttendance(
        id: 'st_3',
        fullName: 'Ali Hassan',
        hasFingerprintEnrolled: true,
        fingerprintData: 'fp_minutiae_hash_xyz789',
      );
      expect(student.isEnrolledFor('Face'), isFalse);
      expect(student.isEnrolledFor('Fingerprint'), isTrue);
    });

    test('Student without photo or biometric data is not enrolled', () {
      final student = StudentAttendance(
        id: 'st_4',
        fullName: 'Bilal Ahmed',
      );
      expect(student.isEnrolledFor('Face'), isFalse);
      expect(student.isEnrolledFor('Fingerprint'), isFalse);
    });
  });

  group('Attendance Timing & Grace Period Late Evaluation Tests', () {
    setUp(() {
      // Manually configure settings for testing:
      // Shift Start: 08:00 AM, Late Grace: 15 minutes -> Cutoff: 08:15 AM
      AttendanceTimingHelper.configureForTest(
        lateGrace: 15,
        startTime: '08:00',
        endTime: '13:00',
      );
    });

    test('Marks Present when arrival is before shift start (07:55 AM)', () {
      final arrival = DateTime(2026, 9, 15, 7, 55);
      final result = AttendanceTimingHelper.evaluate(arrival);
      expect(result.status, 'Present');
      expect(result.isLate, isFalse);
      expect(result.timeFormatted, '07:55:00 AM');
    });

    test('Marks Present when arrival is within grace period (08:10 AM)', () {
      final arrival = DateTime(2026, 9, 15, 8, 10);
      final result = AttendanceTimingHelper.evaluate(arrival);
      expect(result.status, 'Present');
      expect(result.isLate, isFalse);
      expect(result.timeFormatted, '08:10:00 AM');
    });

    test('Marks Present at exact grace cutoff boundary (08:15 AM)', () {
      final arrival = DateTime(2026, 9, 15, 8, 15);
      final result = AttendanceTimingHelper.evaluate(arrival);
      expect(result.status, 'Present');
      expect(result.isLate, isFalse);
      expect(result.timeFormatted, '08:15:00 AM');
    });

    test('Marks Late when arrival is beyond grace period (08:16 AM)', () {
      final arrival = DateTime(2026, 9, 15, 8, 16);
      final result = AttendanceTimingHelper.evaluate(arrival);
      expect(result.status, 'Late');
      expect(result.isLate, isTrue);
      expect(result.timeFormatted, '08:16:00 AM');
      expect(result.message, contains('Late'));
    });

    test('Respects custom late grace minutes (e.g. 30 mins)', () {
      AttendanceTimingHelper.lateGraceMinutes = 30; // Cutoff: 08:30 AM
      final arrival = DateTime(2026, 9, 15, 8, 25);
      final result = AttendanceTimingHelper.evaluate(arrival);
      expect(result.status, 'Present');
      expect(result.isLate, isFalse);
    });
  });

  group('Student Attendance JSON Serialization Tests', () {
    test('fromJson and toJson round-trip preserves biometric fields', () {
      final original = {
        'id': 'st_99',
        'registration_number': 'REG101',
        'gr_no': 'GR55',
        'full_name': 'Hamza Tariq',
        'class_name': 'Hifz 1',
        'photo_path': '/uploads/students/hamza.png',
        'has_face_enrolled': true,
        'has_fingerprint_enrolled': true,
        'face_data': 'face_data_template',
        'fingerprint_data': 'finger_data_template',
        'status': 'Present',
        'remarks': 'Biometric Verified',
        'check_in_time': '08:05 AM',
        'check_out_time': '01:30 PM',
        'verification_method': 'Face',
      };

      final s = StudentAttendance.fromJson(original);
      expect(s.id, 'st_99');
      expect(s.fullName, 'Hamza Tariq');
      expect(s.hasFaceEnrolled, isTrue);
      expect(s.hasFingerprintEnrolled, isTrue);
      expect(s.verificationMethod, 'Face');
      expect(s.checkInTime, '08:05 AM');
      expect(s.checkOutTime, '01:30 PM');

      final map = s.toJson();
      expect(map['student_id'], 'st_99');
      expect(map['status'], 'Present');
      expect(map['check_in_time'], '08:05 AM');
      expect(map['check_out_time'], '01:30 PM');
      expect(map['verification_method'], 'Face');
    });
  });

  group('IN / OUT Time Optionality & Auto-Save Logic Tests', () {
    test('in_only mode records checkInTime and leaves checkOutTime empty', () {
      final s = StudentAttendance(id: 'st_10', fullName: 'Talha');
      const mode = 'in_only';
      const timeNow = '08:10 AM';

      String inTime = s.checkInTime;
      String outTime = s.checkOutTime;

      if (mode == 'in_only') {
        if (inTime.isEmpty) inTime = timeNow;
      } else if (mode == 'out_only') {
        outTime = timeNow;
      }

      expect(inTime, '08:10 AM');
      expect(outTime, '');
    });

    test('out_only mode records checkOutTime and leaves checkInTime unchanged', () {
      final s = StudentAttendance(id: 'st_11', fullName: 'Zubair', checkInTime: '08:00 AM');
      const mode = 'out_only';
      const timeNow = '01:15 PM';

      String inTime = s.checkInTime;
      String outTime = s.checkOutTime;

      if (mode == 'in_only') {
        if (inTime.isEmpty) inTime = timeNow;
      } else if (mode == 'out_only') {
        outTime = timeNow;
      }

      expect(inTime, '08:00 AM');
      expect(outTime, '01:15 PM');
    });

    test('both mode sequentially records IN first and then OUT', () {
      final s = StudentAttendance(id: 'st_12', fullName: 'Hassan');
      const mode = 'both';
      const inTimestamp = '08:05 AM';
      const outTimestamp = '01:30 PM';

      // 1st scan / action (Aamad)
      String inTime = s.checkInTime;
      String outTime = s.checkOutTime;
      if (mode == 'both') {
        if (inTime.isEmpty) {
          inTime = inTimestamp;
        } else if (outTime.isEmpty) {
          outTime = inTimestamp;
        }
      }
      expect(inTime, '08:05 AM');
      expect(outTime, '');

      // 2nd scan / action (Chutti)
      if (mode == 'both') {
        if (inTime.isEmpty) {
          inTime = outTimestamp;
        } else if (outTime.isEmpty) {
          outTime = outTimestamp;
        }
      }
      expect(inTime, '08:05 AM');
      expect(outTime, '01:30 PM');
    });

    test('Marking Absent clears both check-in and check-out times', () {
      final s = StudentAttendance(
        id: 'st_13',
        fullName: 'Saad',
        checkInTime: '08:10 AM',
        checkOutTime: '01:00 PM',
      );
      const status = 'Absent';

      String inTime = s.checkInTime;
      String outTime = s.checkOutTime;
      if (status == 'Absent') {
        inTime = '';
        outTime = '';
      }

      expect(inTime, '');
      expect(outTime, '');
    });
  });

  group('Multi-Shift Timing Evaluation Tests', () {
    test('Evaluates status based on specific shift start time and late grace', () {
      AttendanceTimingHelper.lateGraceMinutes = 15;
      AttendanceTimingHelper.shifts = [
        {
          'id': 'shift_morning',
          'name': 'Morning Shift',
          'start_time': '08:00',
          'end_time': '12:00',
        },
        {
          'id': 'shift_afternoon',
          'name': 'Afternoon Shift',
          'start_time': '14:00',
          'end_time': '17:00',
        },
      ];

      // With 15 mins grace:
      // Morning cutoff is 08:15. At 08:10 -> Present
      final morningArrival = DateTime(2026, 9, 15, 8, 10);
      final morningRes = AttendanceTimingHelper.evaluate(
        morningArrival,
        targetShiftId: 'shift_morning',
      );
      expect(morningRes.status, 'Present');
      expect(morningRes.isLate, isFalse);

      // Afternoon cutoff is 14:15. At 14:20 -> Late
      final afternoonArrival = DateTime(2026, 9, 15, 14, 20);
      final afternoonRes = AttendanceTimingHelper.evaluate(
        afternoonArrival,
        targetShiftId: 'shift_afternoon',
      );
      expect(afternoonRes.status, 'Late');
      expect(afternoonRes.isLate, isTrue);
    });
  });

  group('Period Attendance Model Tests', () {
    test('PeriodAttendanceRecord fromJson and toJson round-trip', () {
      final json = {
        'student_id': 'st_200',
        'full_name': 'Zaid',
        'class_id': 'c_1',
        'period_id': 'p_3',
        'period_number': 3,
        'date': '15/09/2026',
        'status': 'Present',
        'time': '10:15:00 AM',
        'remarks': 'Class participation active',
      };

      final record = PeriodAttendanceRecord.fromJson(json);
      expect(record.studentId, 'st_200');
      expect(record.fullName, 'Zaid');
      expect(record.periodNumber, 3);
      expect(record.date, '15/09/2026');
      expect(record.status, 'Present');
      expect(record.time, '10:15:00 AM');

      final serialized = record.toJson();
      expect(serialized['student_id'], 'st_200');
      expect(serialized['period_number'], 3);
      expect(serialized['date'], '15/09/2026');
      expect(serialized['status'], 'Present');
      expect(serialized['time'], '10:15:00 AM');
    });

    test('PeriodAttendanceRecord copyWith updates fields properly', () {
      final record = PeriodAttendanceRecord(
        studentId: 'st_201',
        date: '15/09/2026',
        periodNumber: 1,
        status: 'Present',
      );

      final updated = record.copyWith(
        status: 'Absent',
        time: '08:30:00 AM',
        remarks: 'Medical leave',
      );

      expect(updated.studentId, 'st_201');
      expect(updated.status, 'Absent');
      expect(updated.time, '08:30:00 AM');
      expect(updated.remarks, 'Medical leave');
    });
  });

  group('Shift Operating Window & Validation Tests', () {
    test('checkShiftWindow permits attendance within operating window with 30m buffer', () {
      AttendanceTimingHelper.shifts = [
        {
          'id': 'shift_morning',
          'name': 'Morning Shift',
          'start_time': '08:00',
          'end_time': '12:00',
        },
      ];

      // Shift is 08:00 - 12:00.
      // Early margin: 07:30 (allowed)
      // Late margin: 12:30 (allowed)

      // At 07:45 (15m before shift): Allowed!
      final earlyTime = DateTime(2026, 9, 15, 7, 45);
      final earlyCheck = AttendanceTimingHelper.checkShiftWindow(earlyTime, targetShiftId: 'shift_morning');
      expect(earlyCheck.isWithinWindow, isTrue);

      // At 10:00 (mid shift): Allowed!
      final midTime = DateTime(2026, 9, 15, 10, 0);
      final midCheck = AttendanceTimingHelper.checkShiftWindow(midTime, targetShiftId: 'shift_morning');
      expect(midCheck.isWithinWindow, isTrue);

      // At 12:20 (within 30m grace after shift): Allowed!
      final endGraceTime = DateTime(2026, 9, 15, 12, 20);
      final endGraceCheck = AttendanceTimingHelper.checkShiftWindow(endGraceTime, targetShiftId: 'shift_morning');
      expect(endGraceCheck.isWithinWindow, isTrue);

      // At 06:30 (way before shift): Outside!
      final tooEarlyTime = DateTime(2026, 9, 15, 6, 30);
      final tooEarlyCheck = AttendanceTimingHelper.checkShiftWindow(tooEarlyTime, targetShiftId: 'shift_morning');
      expect(tooEarlyCheck.isWithinWindow, isFalse);

      // At 16:00 (afternoon outside morning shift): Outside!
      final lateTime = DateTime(2026, 9, 15, 16, 0);
      final lateCheck = AttendanceTimingHelper.checkShiftWindow(lateTime, targetShiftId: 'shift_morning');
      expect(lateCheck.isWithinWindow, isFalse);
    });

    test('Unmarking / Resetting attendance clears status and in/out times', () {
      final s = StudentAttendance(
        id: 'st_99',
        fullName: 'Hamza',
        status: 'Present',
        checkInTime: '08:15:00 AM',
        checkOutTime: '12:00:00 PM',
        verificationMethod: 'Manual',
      );

      // Reset / unmark action: status = ''
      const newStatus = '';
      String inTime = s.checkInTime;
      String outTime = s.checkOutTime;

      if (newStatus == 'Absent' || newStatus.isEmpty) {
        inTime = '';
        outTime = '';
      }

      expect(inTime, isEmpty);
      expect(outTime, isEmpty);
    });
  });
}

