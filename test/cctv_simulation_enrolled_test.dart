import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/network/api_client.dart';
import 'package:madarsa_app/core/services/biometric_hardware_service.dart';
import 'package:madarsa_app/core/services/cctv_attendance_engine.dart';
import 'package:madarsa_app/core/services/cctv_stream_service.dart';
import 'package:madarsa_app/features/attendance/data/models/attendance_models.dart';
import 'package:madarsa_app/features/attendance/data/repositories/attendance_repository.dart';

class _MockAttendanceRepo extends AttendanceRepository {
  final List<StudentAttendance> saved = [];
  _MockAttendanceRepo() : super(ApiClient());

  @override
  Future<void> saveStudentAttendance({
    required String className,
    required String date,
    required List<StudentAttendance> attendanceList,
    String? shiftId,
    String? shiftName,
  }) async {
    saved.addAll(attendanceList);
  }

  @override
  Future<List<PeriodAttendanceRecord>> getPeriodAttendance({
    String? classId,
    String? className,
    required String date,
    required int periodNumber,
  }) async {
    return <PeriodAttendanceRecord>[];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CCTV Simulation Stream: Uses enrolled student photos, in-memory caching, scene dwell, and manual navigation', () async {
    final streamService = CctvStreamService();
    final bioService = BiometricHardwareService();
    final mockRepo = _MockAttendanceRepo();
    final engine = CctvAttendanceEngine(repository: mockRepo);
    engine.enableAudioVoice = false;

    final abuPath = 'C:/Users/MD Services/Downloads/istockphoto-1138008113-612x612.jpg';
    final ahmadPath = r'C:\Users\MD Services\Downloads\75f27b7bd18caf219d95bf7f316cdd06.jpg';

    if (!File(abuPath).existsSync() || !File(ahmadPath).existsSync()) {
      return; // Skip if files absent on machine
    }

    final abuBytes = await File(abuPath).readAsBytes();
    final ahmadBytes = await File(ahmadPath).readAsBytes();

    final abuTemplate = await bioService.generateFaceTemplate(abuBytes, requireFace: false);
    final ahmadTemplate = await bioService.generateFaceTemplate(ahmadBytes, requireFace: false);

    final abuStudent = StudentAttendance(
      id: 'student_abu_talha',
      registrationNumber: 'REG001',
      fullName: 'ابوطلحہ',
      className: 'فارسی دوم',
      photoPath: abuPath,
      faceData: abuTemplate,
      hasFaceEnrolled: true,
    );

    final ahmadStudent = StudentAttendance(
      id: 'student_ahmad',
      registrationNumber: 'REG002',
      fullName: 'احمد',
      className: 'فارسی دوم',
      photoPath: ahmadPath,
      faceData: ahmadTemplate,
      hasFaceEnrolled: true,
    );

    await engine.initializeStudents([abuStudent, ahmadStudent]);

    // Start simulation with enrolled student photos
    final started = await streamService.startStream(CctvCameraConfig(
      sourceType: CctvSourceType.simulation,
      targetFps: 15,
      simulationImages: [abuPath, ahmadPath],
    ));
    expect(started, isTrue);

    // Initial scene should be Abu Talha
    expect(streamService.currentSimulationSceneName, contains('istockphoto-1138008113'));

    // Process Abu Talha frame
    final tracked1 = await engine.processFrame(abuBytes);
    expect(tracked1, isNotEmpty);
    final match1 = tracked1.firstWhere((f) => f.isMatched);
    expect(match1.studentId, equals('student_abu_talha'));
    expect(match1.studentName, equals('ابوطلحہ'));
    expect(match1.isUnknownVisitor, isFalse);
    expect(match1.confidence, greaterThanOrEqualTo(55.0));

    // Next Scene Navigation -> Ahmad
    streamService.nextSimulationScene();
    expect(streamService.currentSimulationSceneName, contains('75f27b7bd18caf219d95bf7f316cdd06'));

    // Process Ahmad frame
    final tracked2 = await engine.processFrame(ahmadBytes);
    expect(tracked2, isNotEmpty);
    final match2 = tracked2.firstWhere((f) => f.isMatched);
    expect(match2.studentId, equals('student_ahmad'));
    expect(match2.studentName, equals('احمد'));
    expect(match2.isUnknownVisitor, isFalse);
    expect(match2.confidence, greaterThanOrEqualTo(55.0));

    // Previous Scene Navigation -> back to Abu Talha
    streamService.previousSimulationScene();
    expect(streamService.currentSimulationSceneName, contains('istockphoto-1138008113'));

    // Verify both students' attendance records were auto-saved
    expect(mockRepo.saved.length, equals(2));
    expect(mockRepo.saved[0].id, equals('student_abu_talha'));
    expect(mockRepo.saved[1].id, equals('student_ahmad'));

    await streamService.stopStream();
    streamService.dispose();
  });
}
