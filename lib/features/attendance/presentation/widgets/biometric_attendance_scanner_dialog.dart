import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/attendance_timing_helper.dart';
import '../../../../core/services/biometric_hardware_service.dart';
import '../../data/models/attendance_models.dart';
import '../../data/repositories/attendance_repository.dart';
import 'biometric_enrollment_dialog.dart';

class BiometricAttendanceScannerDialog extends StatefulWidget {
  final List<StudentAttendance> students;
  final StudentAttendance? targetStudent;
  final AttendanceRepository repository;
  final String initialBiometricType; // 'Face' or 'Fingerprint'
  final String date;
  final String? shiftId;
  final String? shiftName;
  final VoidCallback? onAttendanceUpdated;

  const BiometricAttendanceScannerDialog({
    super.key,
    required this.students,
    this.targetStudent,
    required this.repository,
    this.initialBiometricType = 'Face',
    required this.date,
    this.shiftId,
    this.shiftName,
    this.onAttendanceUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required List<StudentAttendance> students,
    StudentAttendance? targetStudent,
    required AttendanceRepository repository,
    String initialBiometricType = 'Face',
    required String date,
    String? shiftId,
    String? shiftName,
    VoidCallback? onAttendanceUpdated,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BiometricAttendanceScannerDialog(
        students: students,
        targetStudent: targetStudent,
        repository: repository,
        initialBiometricType: initialBiometricType,
        date: date,
        shiftId: shiftId,
        shiftName: shiftName,
        onAttendanceUpdated: onAttendanceUpdated,
      ),
    );
  }

  @override
  State<BiometricAttendanceScannerDialog> createState() => _BiometricAttendanceScannerDialogState();
}

class _BiometricAttendanceScannerDialogState extends State<BiometricAttendanceScannerDialog>
    with SingleTickerProviderStateMixin {
  final BiometricHardwareService _biometricService = BiometricHardwareService();

  late String _biometricType; // 'Face' or 'Fingerprint'
  String _deviceMode = 'external'; // 'external' (USB Scanner) or 'mobile' (Camera / Sensor)
  String _scanTimeMode = 'auto'; // 'auto' (1st IN / 2nd OUT), 'in_only', 'out_only'
  StudentAttendance? _selectedStudent;
  String? _selectedShiftId;
  String? _selectedShiftName;

  bool _isScanning = false;
  String? _lastScanMessage;
  bool _lastScanSuccess = false;
  AttendanceTimingResult? _lastTimingResult;

  FingerprintDeviceStatus? _scannerStatus;
  CameraDeviceStatus? _cameraStatus;
  bool _isCheckingHardware = false;

  String? _verifiedLivePhotoPath;
  FaceDetectionResult? _lastVerifiedDetection;
  int? _matchedFaceIndex;

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _biometricType = widget.initialBiometricType;
    if (_biometricType == 'Face') {
      _deviceMode = 'mobile';
    } else {
      _deviceMode = 'external';
    }

    _selectedShiftId = widget.shiftId;
    _selectedShiftName = widget.shiftName;
    if (_selectedShiftId == null && AttendanceTimingHelper.shifts.isNotEmpty) {
      _selectedShiftId = AttendanceTimingHelper.shifts.first['id']?.toString();
      _selectedShiftName = AttendanceTimingHelper.shifts.first['name']?.toString() ??
          AttendanceTimingHelper.shifts.first['shift_name']?.toString();
    }

    if (widget.targetStudent != null && widget.students.any((s) => s.id == widget.targetStudent!.id)) {
      _selectedStudent = widget.students.firstWhere((s) => s.id == widget.targetStudent!.id);
    } else if (widget.students.isNotEmpty) {
      _selectedStudent = widget.students.first;
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Auto load timings from backend
    AttendanceTimingHelper.loadTimings();

    // Check connected hardware
    _refreshHardwareStatus();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _refreshHardwareStatus({bool force = false}) async {
    if (!mounted) return;
    setState(() => _isCheckingHardware = true);

    try {
      final scanner = await _biometricService.checkFingerprintScanner(forceRefresh: force);
      final camera = await _biometricService.checkCameraDevice();

      if (mounted) {
        setState(() {
          _scannerStatus = scanner;
          _cameraStatus = camera;
          _isCheckingHardware = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingHardware = false);
    }
  }

  Future<void> _performScan({String? customLiveFacePath}) async {
    final student = _selectedStudent;
    if (student == null) return;

    // 1. Enrollment Check: Does the student have enrolled biometric data in the system?
    final isEnrolled = student.isEnrolledFor(_biometricType);
    if (!isEnrolled) {
      setState(() {
        _lastScanSuccess = false;
        _lastScanMessage = '⚠️ Biometric data is NOT enrolled for "${student.fullName}".\nScanner attendance requires the student to have enrolled biometric data first.';
        _lastTimingResult = null;
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _lastScanMessage = null;
    });

    // 2. Hardware Check & Live Biometric Verification
    if (_biometricType == 'Fingerprint') {
      await _verifyFingerprintScan(student);
    } else {
      await _verifyFaceScan(student, customLiveFacePath);
    }
  }

  Future<void> _verifyFingerprintScan(StudentAttendance student) async {
    // A. Verify USB Scanner is physically connected
    final scanner = await _biometricService.checkFingerprintScanner(forceRefresh: true);
    setState(() => _scannerStatus = scanner);

    if (!scanner.isConnected && scanner.activePort == null) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _lastScanSuccess = false;
        _lastScanMessage = '❌ Biometric Scanner Not Connected!\nNo USB fingerprint scanner (Mantra MFS100 / Morpho / SecuGen) detected, or RD Service is offline.\n\nPlease connect a physical scanner to mark attendance.';
        _lastTimingResult = null;
      });
      return;
    }

    // B. Trigger real physical scanner capture
    final captureResult = await _biometricService.captureFingerprintFromDevice();
    if (!captureResult.success || captureResult.template == null) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _lastScanSuccess = false;
        _lastScanMessage = '❌ Fingerprint Capture Failed: ${captureResult.errorMessage ?? 'Finger not placed properly.'}';
        _lastTimingResult = null;
      });
      return;
    }

    // C. Genuine Minutiae Matching against enrolled template
    final enrolledTemplate = student.fingerprintData ?? '';
    FingerprintMatchResult? matchResult;
    if (enrolledTemplate.isNotEmpty) {
      matchResult = _biometricService.matchFingerprint(
        liveTemplate: captureResult.template!,
        enrolledTemplate: enrolledTemplate,
        threshold: 75.0,
      );
    }

    if (matchResult != null && matchResult.isMatch) {
      // D. Genuine Match Verified! Auto-save attendance
      await _markAttendanceSuccess(student, 'Fingerprint (${matchResult.matchScore}% Match)');
      return;
    }

    // Auto-search across other enrolled students
    StudentAttendance? matchedOtherStudent;
    FingerprintMatchResult? bestFpMatch;
    for (final other in widget.students) {
      if (other.id == student.id) continue;
      final otherFp = other.fingerprintData ?? '';
      if (otherFp.isNotEmpty) {
        final res = _biometricService.matchFingerprint(
          liveTemplate: captureResult.template!,
          enrolledTemplate: otherFp,
          threshold: 75.0,
        );
        if (res.isMatch) {
          matchedOtherStudent = other;
          bestFpMatch = res;
          break;
        }
      }
    }

    if (matchedOtherStudent != null && bestFpMatch != null) {
      if (!mounted) return;
      setState(() {
        _selectedStudent = matchedOtherStudent;
      });
      await _markAttendanceSuccess(matchedOtherStudent, 'Auto-Matched Fingerprint (${bestFpMatch.matchScore}% Match)');
      return;
    }

    if (!mounted) return;
    final currentScore = matchResult?.matchScore ?? 0;
    setState(() {
      _isScanning = false;
      _lastScanSuccess = false;
      _lastScanMessage = '❌ Fingerprint Mismatch! (Score: $currentScore%, Minimum 75% required).\nThis fingerprint does not match "${student.fullName}" or any registered student. Attendance NOT marked.';
      _lastTimingResult = null;
    });
    return;
  }

  Future<void> _verifyFaceScan(StudentAttendance student, String? livePhotoPath) async {
    String? photoToVerify = livePhotoPath;

    // If no live photo provided, prompt user to select live capture or photo
    if (photoToVerify == null || photoToVerify.isEmpty) {
      final camera = await _biometricService.checkCameraDevice();
      setState(() => _cameraStatus = camera);

      if (!camera.isConnected) {
        // Prompt file selection for live verification photo
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
          dialogTitle: 'Select Live Verification Photo for ${student.fullName}',
        );

        if (result == null || result.files.single.path == null) {
          if (!mounted) return;
          setState(() {
            _isScanning = false;
            _lastScanSuccess = false;
            _lastScanMessage = 'Face verification cancelled. Please select or capture live photo to verify.';
          });
          return;
        }
        photoToVerify = result.files.single.path!;
      } else {
        // Camera available: pick photo or capture frame
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        );
        if (result == null || result.files.single.path == null) {
          if (!mounted) return;
          setState(() {
            _isScanning = false;
            _lastScanSuccess = false;
            _lastScanMessage = 'Live face capture cancelled.';
          });
          return;
        }
        photoToVerify = result.files.single.path!;
      }
    }

    // Extract live face feature template from selected image bytes
    try {
      final bytes = await File(photoToVerify).readAsBytes();

      // Step 1: Enforce Human Face Detection (reject cars, chairs, objects, scenery, flat cards)
      final liveFaceDetection = await _biometricService.detectFace(bytes);
      if (!liveFaceDetection.hasFace) {
        if (!mounted) return;
        setState(() {
          _isScanning = false;
          _lastScanSuccess = false;
          _verifiedLivePhotoPath = photoToVerify;
          _lastVerifiedDetection = liveFaceDetection;
          _lastScanMessage = '❌ No Human Face Detected!\n'
              '${liveFaceDetection.reason}\n\n'
              'Attendance requires a clear frontal face of a student. Vehicles, furniture, scenery, or non-human objects are not accepted.';
          _lastTimingResult = null;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _verifiedLivePhotoPath = photoToVerify;
        _lastVerifiedDetection = liveFaceDetection;
        _matchedFaceIndex = null;
      });

      final liveTemplates = await _biometricService.generateFaceTemplates(bytes);

      // Get enrolled face template for the currently selected student
      String enrolledTemplate = student.faceData ?? '';
      if ((enrolledTemplate.isEmpty || _biometricService.isFallbackTemplate(enrolledTemplate)) &&
          student.photoPath != null &&
          File(student.photoPath!).existsSync()) {
        try {
          final enrolledBytes = await File(student.photoPath!).readAsBytes();
          final enrolledDetection = await _biometricService.detectFace(enrolledBytes);
          if (enrolledDetection.hasFace) {
            enrolledTemplate = await _biometricService.generateFaceTemplate(enrolledBytes, requireFace: false);
            student.faceData = enrolledTemplate;
            student.hasFaceEnrolled = true;
            try {
              await widget.repository.enrollStudentBiometric(
                studentId: student.id,
                biometricType: 'Face',
                templateData: enrolledTemplate,
                photoPath: student.photoPath,
              );
            } catch (_) {}
          }
        } catch (_) {}
      }

      FaceMatchResult? matchResult;
      int? matchedIndex;
      if (enrolledTemplate.isNotEmpty) {
        for (int i = 0; i < liveTemplates.length; i++) {
          final res = _biometricService.matchFace(
            liveTemplate: liveTemplates[i],
            enrolledTemplate: enrolledTemplate,
            threshold: 65.0,
          );
          if (res.isMatch && (matchResult == null || res.similarityScore > matchResult.similarityScore)) {
            matchResult = res;
            matchedIndex = i;
          }
        }
      }

      if (matchResult != null && matchResult.isMatch) {
        if (!mounted) return;
        setState(() {
          _matchedFaceIndex = matchedIndex;
        });
        // Match Verified for the selected student! Auto-save attendance
        await _markAttendanceSuccess(
          student,
          'Face Scan (${matchResult.similarityScore}% Similarity, Detected: ${liveFaceDetection.detectedFaces.length} Faces)',
        );
        return;
      }

      // If selected student does not match, auto-search across all other enrolled students
      StudentAttendance? matchedOtherStudent;
      FaceMatchResult? bestMatch;
      int? otherMatchedIndex;
      double highestScore = 0.0;

      for (final other in widget.students) {
        if (other.id == student.id) continue;
        String otherTemplate = other.faceData ?? '';
        if ((otherTemplate.isEmpty || _biometricService.isFallbackTemplate(otherTemplate)) &&
            other.photoPath != null &&
            File(other.photoPath!).existsSync()) {
          try {
            final otherBytes = await File(other.photoPath!).readAsBytes();
            final det = await _biometricService.detectFace(otherBytes);
            if (det.hasFace) {
              otherTemplate = await _biometricService.generateFaceTemplate(otherBytes, requireFace: false);
              other.faceData = otherTemplate;
              other.hasFaceEnrolled = true;
              try {
                await widget.repository.enrollStudentBiometric(
                  studentId: other.id,
                  biometricType: 'Face',
                  templateData: otherTemplate,
                  photoPath: other.photoPath,
                );
              } catch (_) {}
            }
          } catch (_) {}
        }
        if (otherTemplate.isNotEmpty) {
          for (int i = 0; i < liveTemplates.length; i++) {
            final res = _biometricService.matchFace(
              liveTemplate: liveTemplates[i],
              enrolledTemplate: otherTemplate,
              threshold: 65.0,
            );
            if (res.isMatch && res.similarityScore > highestScore) {
              highestScore = res.similarityScore;
              matchedOtherStudent = other;
              bestMatch = res;
              otherMatchedIndex = i;
            }
          }
        }
      }

      if (matchedOtherStudent != null && bestMatch != null) {
        // Auto-switch selected student to the matched student
        if (!mounted) return;
        setState(() {
          _selectedStudent = matchedOtherStudent;
          _matchedFaceIndex = otherMatchedIndex;
        });
        await _markAttendanceSuccess(
          matchedOtherStudent,
          'Auto-Matched Face (${bestMatch.similarityScore}% Similarity, Detected: ${liveFaceDetection.detectedFaces.length} Faces)',
        );
        return;
      }

      // No match found anywhere
      if (!mounted) return;
      final currentScore = matchResult?.similarityScore ?? 0.0;
      setState(() {
        _isScanning = false;
        _lastScanSuccess = false;
        _lastScanMessage = '❌ Face Mismatch! (Max Similarity: $currentScore%, Minimum 65% required).\n'
            '${liveFaceDetection.detectedFaces.length} face(s) detected in the image, but none matched "${student.fullName}" or any registered student.';
        _lastTimingResult = null;
      });
      return;

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _lastScanSuccess = false;
        if (e is NoFaceDetectedException) {
          _lastScanMessage = '❌ No Face Detected!\n${e.message}\n${e.details}';
        } else {
          _lastScanMessage = 'Error processing face image: $e';
        }
      });
    }
  }

  Future<void> _markAttendanceSuccess(StudentAttendance student, String matchDetails) async {
    // Evaluate Madarsa Timings & Grace Period for automatic Late calculation
    final now = DateTime.now();
    final timingResult = AttendanceTimingHelper.evaluate(now, targetShiftId: _selectedShiftId ?? widget.shiftId);

    final isCheckingOut = _scanTimeMode == 'out_only' ||
        (_scanTimeMode == 'auto' && student.checkInTime.isNotEmpty && student.checkOutTime.isEmpty);

    final finalCheckIn = _scanTimeMode == 'out_only'
        ? student.checkInTime
        : (isCheckingOut ? (student.checkInTime.isNotEmpty ? student.checkInTime : timingResult.timeFormatted) : timingResult.timeFormatted);
    final finalCheckOut = _scanTimeMode == 'in_only'
        ? student.checkOutTime
        : (isCheckingOut ? timingResult.timeFormatted : student.checkOutTime);
    final String finalStatus = isCheckingOut
        ? ((student.status != null && student.status!.isNotEmpty) ? student.status! : 'Present')
        : timingResult.status;

    final targetShiftId = _selectedShiftId ?? widget.shiftId;
    final targetShiftName = _selectedShiftName ?? widget.shiftName ?? timingResult.shiftName;

    try {
      await widget.repository.saveSingleStudentAttendance(
        studentId: student.id,
        date: widget.date,
        status: finalStatus,
        checkInTime: finalCheckIn,
        checkOutTime: finalCheckOut,
        remarks: 'Biometric Verified ($matchDetails)',
        verificationMethod: _biometricType,
        shiftId: targetShiftId,
        shiftName: targetShiftName,
      );

      student.status = finalStatus;
      student.checkInTime = finalCheckIn;
      student.checkOutTime = finalCheckOut;
      student.verificationMethod = _biometricType;
      student.shiftId = targetShiftId ?? '';
      student.shiftName = targetShiftName ?? '';

      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _lastScanSuccess = true;
        _lastTimingResult = timingResult;
        _lastScanMessage = isCheckingOut
            ? '✅ Biometric OUT Recorded: ${student.fullName} at ${timingResult.timeFormatted}\n$matchDetails'
            : '✅ Biometric IN Recorded: ${student.fullName} marked ${timingResult.status.toUpperCase()} at ${timingResult.timeFormatted}\n$matchDetails';
      });
      widget.onAttendanceUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _lastScanSuccess = false;
        _lastScanMessage = 'Auto-save failed: $e';
      });
    }
  }

  void _openEnrollmentDialog(StudentAttendance student) async {
    final res = await BiometricEnrollmentDialog.show(
      context,
      student: student,
      repository: widget.repository,
      initialType: _biometricType,
    );
    if (res == true && mounted) {
      setState(() {
        _lastScanMessage = 'Biometric enrolled! Ready to verify attendance.';
        _lastScanSuccess = true;
      });
      _refreshHardwareStatus(force: true);
      widget.onAttendanceUpdated?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFace = _biometricType == 'Face';
    final primaryColor = isFace ? Colors.teal : Colors.blue;
    final student = _selectedStudent;
    final isEnrolled = student != null && student.isEnrolledFor(_biometricType);
    final size = MediaQuery.of(context).size;
    final maxDialogWidth = (size.width * 0.95).clamp(340.0, 640.0);
    final maxDialogHeight = (size.height * 0.90).clamp(420.0, 750.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      elevation: 24,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxDialogWidth,
          maxHeight: maxDialogHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isFace
                      ? [const Color(0xFF0D6B4E), const Color(0xFF00796B)]
                      : [const Color(0xFF1565C0), const Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isFace ? Icons.face_retouching_natural_rounded : Icons.fingerprint_rounded,
                      color: const Color(0xFFFACC15),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BIOMETRIC ATTENDANCE SCANNER',
                          style: AppTheme.getFontStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          'Hardware Detection, Template Matching & Madarsa Shift Auto-Save',
                          style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(210)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Controls Toolbar (Biometric Type + Device Mode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: isDark ? const Color(0xFF1E1E2C) : Colors.grey.shade50,
              child: Row(
                children: [
                  // Biometric Type Chips
                  ChoiceChip(
                    avatar: const Icon(Icons.face_retouching_natural_rounded, size: 16),
                    label: const Text('Face Scan'),
                    selected: _biometricType == 'Face',
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          _biometricType = 'Face';
                          _deviceMode = 'mobile';
                          _verifiedLivePhotoPath = null;
                          _lastVerifiedDetection = null;
                          _matchedFaceIndex = null;
                          _lastScanMessage = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.fingerprint_rounded, size: 16),
                    label: const Text('Fingerprint'),
                    selected: _biometricType == 'Fingerprint',
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          _biometricType = 'Fingerprint';
                          _deviceMode = 'external';
                          _verifiedLivePhotoPath = null;
                          _lastVerifiedDetection = null;
                          _matchedFaceIndex = null;
                          _lastScanMessage = null;
                        });
                      }
                    },
                  ),
                  const Spacer(),
                  // Device Mode Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _deviceToggleItem('mobile', '📱 Cam/Sensor', isDark),
                        _deviceToggleItem('external', '🔌 USB Scanner', isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Main Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Student Selector Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _selectedStudent?.id,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Select Student to Verify',
                        prefixIcon: const Icon(Icons.person_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: widget.students.map((s) {
                        final enrolled = s.isEnrolledFor(_biometricType);
                        return DropdownMenuItem<String>(
                          value: s.id,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${s.fullName} (GR: ${s.grNo ?? s.registrationNumber})',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: enrolled ? Colors.green.withAlpha(20) : Colors.red.withAlpha(20),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  enrolled ? 'Enrolled' : 'Not Enrolled',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: enrolled ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedStudent = widget.students.firstWhere(
                              (s) => s.id == val,
                              orElse: () => _selectedStudent!,
                            );
                            _verifiedLivePhotoPath = null;
                            _lastVerifiedDetection = null;
                            _lastScanMessage = null;
                            _lastTimingResult = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    _buildShiftSelector(isDark),

                    // Time Mode Selector & Current Status Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E2C) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Time Mode:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _buildScanTimeChip('auto', '⚡ Auto (1st IN / 2nd OUT)', isDark),
                                      const SizedBox(width: 6),
                                      _buildScanTimeChip('in_only', '🟢 IN Only', isDark),
                                      const SizedBox(width: 6),
                                      _buildScanTimeChip('out_only', '🔴 OUT Only', isDark),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_selectedStudent != null &&
                              (_selectedStudent!.checkInTime.isNotEmpty || _selectedStudent!.checkOutTime.isNotEmpty)) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  'Current: ',
                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                ),
                                if (_selectedStudent!.checkInTime.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withAlpha(20),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'IN: ${_selectedStudent!.checkInTime}',
                                      style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                if (_selectedStudent!.checkOutTime.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withAlpha(20),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'OUT: ${_selectedStudent!.checkOutTime}',
                                      style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Scanner Viewport Frame (Full-Frame CCTV / HD Viewfinder)
                    Container(
                      height: 220,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF14141E) : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isScanning
                              ? primaryColor
                              : (_lastScanSuccess ? Colors.green : (isEnrolled ? primaryColor.withAlpha(120) : Colors.red.withAlpha(120))),
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Background Grid Lines
                            CustomPaint(
                              size: const Size(double.infinity, 220),
                              painter: _ScannerGridPainter(color: primaryColor.withAlpha(25)),
                            ),

                            // If face mode and photo selected, render full image with dynamic face box
                            if (isFace && _verifiedLivePhotoPath != null && File(_verifiedLivePhotoPath!).existsSync())
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final vw = constraints.maxWidth;
                                    final vh = constraints.maxHeight;
                                    final imgW = _lastVerifiedDetection?.imageWidth.toDouble();
                                    final imgH = _lastVerifiedDetection?.imageHeight.toDouble();

                                    double renderW = vw;
                                    double renderH = vh;
                                    double offsetX = 0;
                                    double offsetY = 0;

                                    if (imgW != null && imgH != null && imgW > 0 && imgH > 0) {
                                      final imgAspect = imgW / imgH;
                                      final viewAspect = vw / vh;
                                      if (imgAspect > viewAspect) {
                                        renderW = vw;
                                        renderH = vw / imgAspect;
                                        offsetY = (vh - renderH) / 2;
                                      } else {
                                        renderH = vh;
                                        renderW = vh * imgAspect;
                                        offsetX = (vw - renderW) / 2;
                                      }
                                    }

                                    final facesToRender = _lastVerifiedDetection?.detectedFaces ?? [];
                                    final hasAnyFace = _lastVerifiedDetection != null &&
                                        _lastVerifiedDetection!.hasFace &&
                                        imgW != null &&
                                        imgH != null &&
                                        imgW > 0 &&
                                        imgH > 0;

                                    final scaleX = (imgW != null && imgW > 0) ? (renderW / imgW) : 1.0;
                                    final scaleY = (imgH != null && imgH > 0) ? (renderH / imgH) : 1.0;

                                    return Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Image.file(
                                            File(_verifiedLivePhotoPath!),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        Positioned.fill(
                                          child: Container(
                                            color: Colors.black.withAlpha(25),
                                          ),
                                        ),
                                        if (hasAnyFace)
                                          for (int i = 0; i < (facesToRender.isNotEmpty ? facesToRender.length : 1); i++)
                                            Builder(
                                              builder: (context) {
                                                final f = facesToRender.isNotEmpty ? facesToRender[i] : null;
                                                final fLeft = f?.left ?? _lastVerifiedDetection!.faceLeft;
                                                final fTop = f?.top ?? _lastVerifiedDetection!.faceTop;
                                                final fW = f?.width ?? _lastVerifiedDetection!.boxWidth;
                                                final fH = f?.height ?? _lastVerifiedDetection!.boxHeight;

                                                final boxLeft = offsetX + (fLeft * scaleX);
                                                final boxTop = offsetY + (fTop * scaleY);
                                                final boxWidth = fW * scaleX;
                                                final boxHeight = fH * scaleY;

                                                final isThisMatched = _lastScanSuccess &&
                                                    (_matchedFaceIndex == null || _matchedFaceIndex == i);

                                                final borderColor = isThisMatched ? Colors.greenAccent : const Color(0xFF00E5FF);
                                                final labelText = isThisMatched
                                                    ? 'MATCHED'
                                                    : (facesToRender.length > 1 ? 'STUDENT #${i + 1}' : 'FACE DETECTED');

                                                return Positioned(
                                                  left: boxLeft,
                                                  top: boxTop,
                                                  width: boxWidth,
                                                  height: boxHeight,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color: borderColor,
                                                        width: 2,
                                                      ),
                                                      borderRadius: BorderRadius.circular(6),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: borderColor.withAlpha(90),
                                                          blurRadius: 8,
                                                          spreadRadius: 1,
                                                        ),
                                                      ],
                                                    ),
                                                    child: Align(
                                                      alignment: Alignment.topLeft,
                                                      child: Container(
                                                        margin: const EdgeInsets.all(2),
                                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: Colors.black87,
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Icon(
                                                                Icons.center_focus_strong,
                                                                size: 9,
                                                                color: borderColor,
                                                              ),
                                                              const SizedBox(width: 2),
                                                              Text(
                                                                labelText,
                                                                style: TextStyle(
                                                                  fontSize: 8,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: borderColor,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                      ],
                                    );
                                  },
                                ),
                              )
                            else if (isFace) ...[
                              // Full-frame CCTV Viewfinder overlay (Idle / Scanning)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _ViewfinderCornerPainter(
                                    color: _isScanning ? primaryColor : Colors.white24,
                                  ),
                                ),
                              ),
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 76,
                                      height: 76,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: primaryColor.withAlpha(_isScanning ? 35 : 15),
                                        border: Border.all(
                                          color: _isScanning ? primaryColor : Colors.white24,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.center_focus_strong_rounded,
                                        size: 40,
                                        color: _isScanning ? primaryColor : Colors.white38,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _isScanning ? 'SCANNING FULL FRAME...' : 'FULL-FRAME AI SCANNER ACTIVE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 0.8,
                                        fontWeight: FontWeight.w600,
                                        color: _isScanning ? primaryColor : Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else
                              // Fingerprint Mode Reticle
                              Container(
                                width: 105,
                                height: 105,
                                decoration: BoxDecoration(
                                  color: primaryColor.withAlpha(_isScanning ? 30 : 10),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _isScanning ? primaryColor : Colors.white24,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.fingerprint_rounded,
                                    size: 60,
                                    color: _isScanning ? primaryColor : Colors.white30,
                                  ),
                                ),
                              ),

                            // Animated Scan Line (Sweeps across full frame)
                            if (_isScanning)
                              AnimatedBuilder(
                                animation: _animController,
                                builder: (context, child) {
                                  return Positioned(
                                    top: 10 + (_animController.value * 190),
                                    left: 10,
                                    right: 10,
                                    child: Container(
                                      height: 2.5,
                                      decoration: BoxDecoration(
                                        color: primaryColor,
                                        boxShadow: [
                                          BoxShadow(color: primaryColor.withAlpha(200), blurRadius: 10, spreadRadius: 2),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),

                            // Top-left CCTV / Full-Frame scan indicator badge
                            if (isFace)
                              Positioned(
                                top: 10,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.fullscreen_rounded, size: 12, color: primaryColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        'FULL-FRAME AI (CCTV & HD)',
                                        style: TextStyle(fontSize: 9, color: primaryColor, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Top-right device mode badge
                            Positioned(
                              top: 10,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _deviceMode == 'mobile' ? 'MODE: CAMERA / MOBILE' : 'MODE: USB SCANNER (RD SERVICE)',
                                  style: const TextStyle(fontSize: 9.5, color: Colors.white70, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),

                            // Bottom Status Indicator
                            Positioned(
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _isScanning
                                      ? 'Scanning Entire Frame for Face Biometrics...'
                                      : (isEnrolled ? 'Ready to Verify (Full-Frame CCTV / HD)' : 'Data Not Enrolled'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _isScanning ? primaryColor : (isEnrolled ? Colors.white : Colors.redAccent),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Unenrolled Warning with "Enroll Now" button
                    if (!isEnrolled && student != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(20),
                          border: Border.all(color: Colors.red.withAlpha(80)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${student.fullName} has no $_biometricType enrolled',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.red),
                                  ),
                                  const Text(
                                    'Please enroll biometric data for the student before marking attendance via scanner.',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Enroll Now', style: TextStyle(fontSize: 11.5)),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                              onPressed: () => _openEnrollmentDialog(student),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Feedback / Result Card
                    if (_lastScanMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _lastScanSuccess ? Colors.green.withAlpha(20) : Colors.red.withAlpha(20),
                          border: Border.all(color: _lastScanSuccess ? Colors.green.withAlpha(100) : Colors.red.withAlpha(100)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _lastScanSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                  color: _lastScanSuccess ? Colors.green : Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _lastScanMessage!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _lastScanSuccess ? Colors.green.shade800 : Colors.red.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!isEnrolled && student != null) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                                  label: Text('Enroll $_biometricType for ${student.fullName} Now'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  onPressed: () => _openEnrollmentDialog(student),
                                ),
                              ),
                            ],
                            if (_lastTimingResult != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _lastTimingResult!.status == 'Present' ? Colors.green : Colors.orange,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _lastTimingResult!.status.toUpperCase(),
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Shift: ${_lastTimingResult!.shiftName} • Check-in: ${_lastTimingResult!.timeFormatted}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                                  ),
                                  if (_lastTimingResult!.lateMinutes > 0)
                                    Text(
                                      ' (${_lastTimingResult!.lateMinutes} min late)',
                                      style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Trigger Scan Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        icon: _isScanning
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(isFace ? Icons.camera_alt_rounded : Icons.fingerprint_rounded, size: 20),
                        label: Text(
                          _isScanning ? 'Verifying Biometrics...' : (isFace ? 'Verify Face & Mark Attendance' : 'Read Fingerprint & Mark Attendance'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isScanning || !isEnrolled ? null : () => _performScan(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Persistent Hardware Health Status
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _scannerStatus?.isConnected == true ? Icons.usb_rounded : Icons.usb_off_rounded,
                            size: 16,
                            color: _scannerStatus?.isConnected == true ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _biometricType == 'Fingerprint'
                                  ? (_scannerStatus?.isConnected == true
                                      ? 'Scanner: ${_scannerStatus?.deviceModel} (Port ${_scannerStatus?.activePort ?? 11100})'
                                      : 'Scanner: Disconnected (Plug in USB Scanner)')
                                  : (_cameraStatus?.isConnected == true
                                      ? 'Webcam: ${_cameraStatus?.cameraName}'
                                      : 'Webcam: Disconnected (Use Photo Verification)'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: (_biometricType == 'Fingerprint' ? _scannerStatus?.isConnected : _cameraStatus?.isConnected) == true
                                    ? Colors.green.shade700
                                    : Colors.grey.shade600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Refresh Hardware',
                            icon: _isCheckingHardware
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh_rounded, size: 16),
                            onPressed: _isCheckingHardware ? null : () => _refreshHardwareStatus(force: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceToggleItem(String mode, String label, bool isDark) {
    final isSelected = _deviceMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _deviceMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }

  Widget _buildShiftSelector(bool isDark) {
    if (AttendanceTimingHelper.shifts.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 16, color: Colors.blue.shade400),
          const SizedBox(width: 8),
          Text(
            'Shift:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.grey.shade800,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: AttendanceTimingHelper.shifts.map((shift) {
                  final sId = shift['id']?.toString() ?? '';
                  final sName = shift['name']?.toString() ?? shift['shift_name']?.toString() ?? 'Shift';
                  final isSelected = _selectedShiftId == sId;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$sName (${shift['start_time'] ?? '08:00'})'),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      ),
                      selected: isSelected,
                      selectedColor: Colors.blue.shade700,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _selectedShiftId = sId;
                            _selectedShiftName = sName;
                          });
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanTimeChip(String mode, String label, bool isDark) {
    final isSelected = _scanTimeMode == mode;
    return InkWell(
      onTap: () => setState(() => _scanTimeMode = mode),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (mode == 'in_only'
                  ? Colors.green.withAlpha(30)
                  : mode == 'out_only'
                      ? Colors.red.withAlpha(30)
                      : Colors.blue.withAlpha(30))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? (mode == 'in_only'
                    ? Colors.green
                    : mode == 'out_only'
                        ? Colors.red
                        : Colors.blue)
                : (isDark ? Colors.white24 : Colors.grey.shade400),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? (mode == 'in_only'
                    ? Colors.green
                    : mode == 'out_only'
                        ? Colors.red
                        : Colors.blue)
                : (isDark ? Colors.white70 : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }
}

class _ScannerGridPainter extends CustomPainter {
  final Color color;
  _ScannerGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ViewfinderCornerPainter extends CustomPainter {
  final Color color;

  _ViewfinderCornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 20.0;
    const pad = 8.0;

    // Top-Left
    canvas.drawLine(const Offset(pad, pad + len), const Offset(pad, pad), paint);
    canvas.drawLine(const Offset(pad, pad), const Offset(pad + len, pad), paint);

    // Top-Right
    canvas.drawLine(Offset(size.width - pad - len, pad), Offset(size.width - pad, pad), paint);
    canvas.drawLine(Offset(size.width - pad, pad), Offset(size.width - pad, pad + len), paint);

    // Bottom-Left
    canvas.drawLine(Offset(pad, size.height - pad - len), Offset(pad, size.height - pad), paint);
    canvas.drawLine(Offset(pad, size.height - pad), Offset(pad + len, size.height - pad), paint);

    // Bottom-Right
    canvas.drawLine(Offset(size.width - pad - len, size.height - pad), Offset(size.width - pad, size.height - pad), paint);
    canvas.drawLine(Offset(size.width - pad, size.height - pad), Offset(size.width - pad, size.height - pad - len), paint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderCornerPainter oldDelegate) => oldDelegate.color != color;
}
