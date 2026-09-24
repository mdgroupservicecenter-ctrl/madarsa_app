import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/biometric_hardware_service.dart';
import '../../../../core/storage/database_helper.dart';
import '../../data/models/attendance_models.dart';
import '../../data/repositories/attendance_repository.dart';
import 'cctv_photo_capture_dialog.dart';

class BiometricEnrollmentDialog extends StatefulWidget {
  final StudentAttendance student;
  final AttendanceRepository repository;
  final String initialType; // 'Face' or 'Fingerprint'

  const BiometricEnrollmentDialog({
    super.key,
    required this.student,
    required this.repository,
    this.initialType = 'Face',
  });

  static Future<bool?> show(
    BuildContext context, {
    required StudentAttendance student,
    required AttendanceRepository repository,
    String initialType = 'Face',
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BiometricEnrollmentDialog(
        student: student,
        repository: repository,
        initialType: initialType,
      ),
    );
  }

  @override
  State<BiometricEnrollmentDialog> createState() => _BiometricEnrollmentDialogState();
}

class _BiometricEnrollmentDialogState extends State<BiometricEnrollmentDialog> with SingleTickerProviderStateMixin {
  final BiometricHardwareService _biometricService = BiometricHardwareService();

  late TabController _tabController;
  bool _isSaving = false;
  String? _selectedPhotoPath;
  FaceDetectionResult? _faceDetectionResult;

  double _imagePanX = 0.0;
  double _imagePanY = 0.0;
  double _imageZoom = 1.0;
  bool _isCheckingFaceAlignment = false;

  bool _isCapturingFinger = false;
  bool _fingerCaptured = false;
  String? _capturedFingerTemplate;
  int _fingerQuality = 0;
  String? _fingerErrorMessage;

  FingerprintDeviceStatus? _scannerStatus;
  bool _isCheckingHardware = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialType == 'Fingerprint' ? 1 : 0,
    );
    _selectedPhotoPath = widget.student.photoPath;
    if (_selectedPhotoPath != null && _selectedPhotoPath!.contains('_aligned_')) {
      final parent = File(_selectedPhotoPath!).parent;
      final candidates = [
        '${parent.path}/istockphoto-1138008113-612x612.jpg',
        '${parent.path}/istockphoto-1138008134-612x612.jpg',
        '${parent.path}/images.jpg',
        '${parent.path}/75f27b7bd18caf219d95bf7f316cdd06.jpg',
      ];
      for (final c in candidates) {
        if (File(c).existsSync()) {
          _selectedPhotoPath = c;
          widget.student.photoPath = c;
          break;
        }
      }
    }
    _fingerCaptured = widget.student.hasFingerprintEnrolled;
    _capturedFingerTemplate = widget.student.fingerprintData;

    if (_selectedPhotoPath != null && File(_selectedPhotoPath!).existsSync()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkFaceAlignment();
      });
    }

    _checkHardware();
  }


  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkHardware({bool force = false}) async {
    if (!mounted) return;
    setState(() => _isCheckingHardware = true);

    try {
      final scanner = await _biometricService.checkFingerprintScanner(forceRefresh: force);

      if (mounted) {
        setState(() {
          _scannerStatus = scanner;
          _isCheckingHardware = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingHardware = false);
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _isSaving = true;
        _imagePanX = 0.0;
        _imagePanY = 0.0;
        _imageZoom = 1.0;
      });

      try {
        final bytes = await File(path).readAsBytes();

        // 1. Enforce Human Face Detection (reject cars, chairs, animals, scenery, blank images)
        final detection = await _biometricService.detectFace(
          bytes,
          sensitivity: FaceDetectionSensitivity.balanced,
        );
        if (!detection.hasFace) {
          if (mounted) {
            setState(() {
              _selectedPhotoPath = null;
              _faceDetectionResult = null;
              _isSaving = false;
            });
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.face_retouching_off_rounded, color: Colors.red),
                    SizedBox(width: 8),
                    Text('No Face Detected', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Text(
                  'No human face was detected in the selected image!\n\n'
                  'Reason: ${detection.reason}\n\n'
                  'Please select a clear frontal portrait of the student. Vehicles, furniture, scenery, animals, or non-human images are not accepted.',
                  style: const TextStyle(fontSize: 13),
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
          return;
        }

        if (mounted) {
          setState(() {
            _selectedPhotoPath = path;
            _faceDetectionResult = detection;
            _isSaving = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Insani chehra kamyabi se detect hua! (Confidence: ${detection.confidence.toInt()}%) ✅'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to process face photo: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// Re-evaluates face detection on the photo
  Future<void> _checkFaceAlignment() async {
    if (_selectedPhotoPath == null) return;
    setState(() => _isCheckingFaceAlignment = true);

    try {
      final file = File(_selectedPhotoPath!);
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();

      final detection = await _biometricService.detectFace(
        bytes,
        sensitivity: FaceDetectionSensitivity.balanced,
      );
      if (mounted) {
        setState(() {
          _faceDetectionResult = detection;
          _isCheckingFaceAlignment = false;
        });

        if (detection.hasFace) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Zabardast! Chehra circle me sahi align he (Confidence: ${detection.confidence.toInt()}%) ✅'),
              backgroundColor: Colors.teal,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Face not properly detected: ${detection.reason}\nPlease select a clear frontal portrait.'),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingFaceAlignment = false);
    }
  }

  void _clearPhoto() {
    setState(() {
      _selectedPhotoPath = null;
      _faceDetectionResult = null;
      _imagePanX = 0.0;
      _imagePanY = 0.0;
      _imageZoom = 1.0;
    });
  }

  Future<void> _deleteFaceFromDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Chehra Hatayein / Delete Face?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Kya aap waqai is student ka enrolled face database se hatana chahte hen?\nIs ke baad CCTV camera is student ko auto-detect nahi karega jab tak naya photo enroll na kiya jaye.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Face'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      await widget.repository.clearStudentBiometric(
        studentId: widget.student.id,
        biometricType: 'face',
      );
      widget.student.faceData = null;
      widget.student.photoPath = null;
      if (mounted) {
        setState(() {
          _selectedPhotoPath = null;
          _faceDetectionResult = null;
          _imagePanX = 0.0;
          _imagePanY = 0.0;
          _imageZoom = 1.0;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enrolled face database se kamyabi se hata diya gaya! ✅'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing face: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteFingerprintFromDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Fingerprint Hatayein / Delete?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Kya aap waqai is student ka fingerprint database se hatana chahte hen?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Fingerprint'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      await widget.repository.clearStudentBiometric(
        studentId: widget.student.id,
        biometricType: 'fingerprint',
      );
      widget.student.fingerprintData = null;
      if (mounted) {
        setState(() {
          _fingerCaptured = false;
          _capturedFingerTemplate = null;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fingerprint database se hata diya gaya! ✅'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing fingerprint: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _captureFromCamera() async {
    final capturedPath = await CctvPhotoCaptureDialog.show(
      context,
      studentName: widget.student.fullName,
      studentId: widget.student.id,
    );

    if (capturedPath != null && File(capturedPath).existsSync()) {
      setState(() {
        _isSaving = true;
        _selectedPhotoPath = capturedPath;
        _imagePanX = 0.0;
        _imagePanY = 0.0;
        _imageZoom = 1.0;
      });

      try {
        final bytes = await File(capturedPath).readAsBytes();
        final detection = await _biometricService.detectFace(
          bytes,
          sensitivity: FaceDetectionSensitivity.balanced,
        );
        if (mounted) {
          setState(() {
            _faceDetectionResult = detection;
            _isSaving = false;
          });

          if (detection.hasFace) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('CCTV / Camera se tasveer kamyabi se capture ho gayi! (Confidence: ${detection.confidence.toInt()}%) ✅'),
                backgroundColor: Colors.teal,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Warning: Chehra proper detect nahi hua. Tasveer ko retake karein ya align karein.'),
                backgroundColor: Colors.orange.shade800,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _captureFingerprint() async {
    setState(() {
      _isCapturingFinger = true;
      _fingerCaptured = false;
      _fingerErrorMessage = null;
    });

    final result = await _biometricService.captureFingerprintFromDevice();

    if (!mounted) return;
    setState(() {
      _isCapturingFinger = false;
      if (result.success && result.template != null) {
        _fingerCaptured = true;
        _capturedFingerTemplate = result.template;
        _fingerQuality = result.quality;
        _fingerErrorMessage = null;
      } else {
        _fingerCaptured = false;
        _fingerErrorMessage = result.errorMessage ?? 'Biometric scanner not detected. Plug in USB scanner.';
      }
    });

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fingerprint captured via ${result.deviceModel ?? 'Scanner'} (Quality: ${result.quality}%) ✅'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_fingerErrorMessage!),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry Hardware',
            textColor: Colors.white,
            onPressed: () => _checkHardware(force: true),
          ),
        ),
      );
    }
  }

  Future<void> _saveFaceEnrollment() async {
    if (_selectedPhotoPath == null) return;
    setState(() => _isSaving = true);

    try {
      final file = File(_selectedPhotoPath!);
      if (!file.existsSync()) {
        throw Exception('Photo file not found on device.');
      }
      final effectiveBytes = await file.readAsBytes();

      // 1. Validate Face Detection on the photo (mirrors Kiosk detection engine)
      final detection = (_faceDetectionResult != null && _faceDetectionResult!.hasFace && _faceDetectionResult!.detectedFaces.isNotEmpty)
          ? _faceDetectionResult!
          : await _biometricService.detectFace(
              effectiveBytes,
              sensitivity: FaceDetectionSensitivity.balanced,
            );

      if (!detection.hasFace || detection.detectedFaces.isEmpty) {
        throw NoFaceDetectedException(
          'No human face detected in the photo!',
          detection.reason,
        );
      }

      // 2. Generate Face Biometric Template using the EXACT SAME kiosk multi-face engine & native dimensions
      final template = await _biometricService.generateFaceTemplate(
        effectiveBytes,
        preDetectedFaces: detection.detectedFaces,
        nativeWidth: detection.imageWidth,
        nativeHeight: detection.imageHeight,
        requireFace: false,
      );

      // 2.5 Duplicate face enrollment prevention check across all enrolled students
      try {
        final db = await DatabaseHelper().database;
        final rows = await db.rawQuery(
          "SELECT id, gr_no, full_name, class_name, face_data FROM students WHERE id != ? AND face_data IS NOT NULL AND trim(face_data) != ''",
          [widget.student.id],
        );
        for (final r in rows) {
          final otherFace = r['face_data']?.toString();
          if (otherFace == null || otherFace.isEmpty) continue;
          final cmp = _biometricService.matchFace(
            liveTemplate: template,
            enrolledTemplate: otherFace,
            threshold: 93.0,
          );
          if (cmp.isMatch && cmp.similarityScore >= 93.0) {
            final otherName = r['full_name']?.toString() ?? 'Student';
            final otherGr = r['gr_no']?.toString() ?? '';
            final otherClass = r['class_name']?.toString() ?? '';
            if (mounted) {
              final shouldProceed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Duplicate Face Warning', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  content: Text(
                    'This face is already enrolled for another student:\n\n'
                    '• Name: $otherName\n'
                    '• GR No: $otherGr\n'
                    '• Class: $otherClass\n'
                    '• Similarity: ${cmp.similarityScore.toStringAsFixed(1)}%\n\n'
                    'Enrolling the same face for two different students will cause ambiguity during CCTV kiosk recognition.\n\n'
                    'Are you sure you want to save this face for ${widget.student.fullName} anyway?',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel (Choose Another Photo)'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Proceed Anyway'),
                    ),
                  ],
                ),
              );
              if (shouldProceed != true) {
                return;
              }
            }
            break;
          }
        }
      } catch (_) {}

      // 3. Save enrollment to repository (updates local SQLite & backend)
      await widget.repository.enrollStudentBiometric(
        studentId: widget.student.id,
        biometricType: 'Face',
        templateData: template,
        photoPath: _selectedPhotoPath,
      );

      widget.student.hasFaceEnrolled = true;
      widget.student.faceData = template;
      widget.student.photoPath = _selectedPhotoPath;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Face enrolled successfully for ${widget.student.fullName}! ✅'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to enroll face: ${e is NoFaceDetectedException ? e.toString() : e}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveFingerprintEnrollment() async {
    if (_capturedFingerTemplate == null || !_fingerCaptured) return;
    setState(() => _isSaving = true);

    try {
      await widget.repository.enrollStudentBiometric(
        studentId: widget.student.id,
        biometricType: 'Fingerprint',
        templateData: _capturedFingerTemplate!,
      );

      widget.student.hasFingerprintEnrolled = true;
      widget.student.fingerprintData = _capturedFingerTemplate!;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fingerprint enrolled successfully for ${widget.student.fullName}! ✅'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to enroll fingerprint: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 540,
        constraints: const BoxConstraints(maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D6B4E), Color(0xFF138A65)],
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
                    child: const Icon(Icons.fingerprint_rounded, color: Color(0xFFFACC15), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BIOMETRIC DATA ENROLLMENT',
                          style: AppTheme.getFontStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${widget.student.fullName} (GR: ${widget.student.grNo ?? widget.student.registrationNumber})',
                          style: TextStyle(fontSize: 11.5, color: Colors.white.withAlpha(200)),
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

            // Tab Bar
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.primaryColor,
              indicatorColor: AppTheme.primaryColor,
              tabs: const [
                Tab(icon: Icon(Icons.face_retouching_natural_rounded, size: 20), text: 'Face Enrollment'),
                Tab(icon: Icon(Icons.fingerprint_rounded, size: 20), text: 'Fingerprint Enrollment'),
              ],
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFaceTab(isDark),
                  _buildFingerprintTab(isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── FACE ENROLLMENT TAB ─────────────────────────────────────────
  Widget _buildFaceTab(bool isDark) {
    final hasPhoto = _selectedPhotoPath != null && _selectedPhotoPath!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Photo / Reticle preview
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasPhoto ? Colors.teal : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: Stack(
                children: [
                  // Layer 1: Single Clean High-Resolution Photo with Drag & Zoom
                  if (hasPhoto)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final h = constraints.maxHeight;

                            return Container(
                              width: w,
                              height: h,
                              color: const Color(0xFF161622),
                              child: Listener(
                                onPointerSignal: (pointerSignal) {
                                  if (pointerSignal is PointerScrollEvent) {
                                    setState(() {
                                      _imageZoom = (_imageZoom - pointerSignal.scrollDelta.dy * 0.001).clamp(0.5, 4.0);
                                    });
                                  }
                                },
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanUpdate: (details) {
                                    setState(() {
                                      _imagePanX += details.delta.dx;
                                      _imagePanY += details.delta.dy;
                                    });
                                  },
                                  child: Center(
                                    child: Transform.translate(
                                      offset: Offset(_imagePanX, _imagePanY),
                                      child: Transform.scale(
                                        scale: _imageZoom,
                                        child: Image.file(
                                          File(_selectedPhotoPath!),
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) => const Center(
                                            child: Icon(Icons.broken_image_rounded, size: 60, color: Colors.grey),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.face_retouching_natural_rounded, size: 80, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            'No Face Data Enrolled',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                          ),
                          Text(
                            'Select portrait photo or connect camera to extract facial template',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),

                  // Layer 2: Reticle Cutout Mask & Targeting Guide
                  if (hasPhoto)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final h = constraints.maxHeight;
                            final ovalRect = Rect.fromCenter(
                              center: Offset(w / 2, h * 0.40),
                              width: 170,
                              height: 220,
                            );

                            final imgW = _faceDetectionResult?.imageWidth.toDouble();
                            final imgH = _faceDetectionResult?.imageHeight.toDouble();
                            final facesToRender = _faceDetectionResult?.detectedFaces ?? [];
                            final hasAnyFace = _faceDetectionResult != null &&
                                _faceDetectionResult!.hasFace &&
                                imgW != null &&
                                imgH != null &&
                                imgW > 0 &&
                                imgH > 0;

                            double renderW = w;
                            double renderH = h;
                            if (hasAnyFace) {
                              final imgAspect = imgW / imgH;
                              final viewAspect = w / h;
                              if (imgAspect > viewAspect) {
                                renderW = w;
                                renderH = w / imgAspect;
                              } else {
                                renderH = h;
                                renderW = h * imgAspect;
                              }
                            }

                            final scaleX = hasAnyFace ? ((renderW / imgW) * _imageZoom) : 1.0;
                            final scaleY = hasAnyFace ? ((renderH / imgH) * _imageZoom) : 1.0;
                            final centerX = w / 2 + _imagePanX;
                            final centerY = h / 2 + _imagePanY;

                            return Stack(
                              children: [
                                CustomPaint(
                                  size: Size(w, h),
                                  painter: FaceReticleMaskPainter(
                                    ovalRect: ovalRect,
                                    isFaceDetected: _faceDetectionResult?.hasFace == true,
                                    hasPhoto: hasPhoto,
                                  ),
                                ),
                                if (hasAnyFace)
                                  Builder(
                                    builder: (context) {
                                      final f = facesToRender.isNotEmpty ? facesToRender.first : null;
                                      final fLeft = f?.left ?? _faceDetectionResult!.faceLeft;
                                      final fTop = f?.top ?? _faceDetectionResult!.faceTop;
                                      final fW = f?.width ?? _faceDetectionResult!.boxWidth;
                                      final fH = f?.height ?? _faceDetectionResult!.boxHeight;

                                      final faceRelX = (fLeft + fW / 2) - (imgW / 2);
                                      final faceRelY = (fTop + fH / 2) - (imgH / 2);

                                      final boxWidth = fW * scaleX;
                                      final boxHeight = fH * scaleY;
                                      final boxLeft = centerX + (faceRelX * (renderW / imgW) * _imageZoom) - (boxWidth / 2);
                                      final boxTop = centerY + (faceRelY * (renderH / imgH) * _imageZoom) - (boxHeight / 2);

                                      const borderColor = Colors.greenAccent;
                                      const labelText = 'ENROLLED FACE';

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
                                              child: const FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.center_focus_strong, size: 9, color: borderColor),
                                                    SizedBox(width: 2),
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
                      ),
                    )
                  else
                    Align(
                      alignment: const Alignment(0, -0.40),
                      child: IgnorePointer(
                        child: Container(
                          width: 160,
                          height: 205,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.teal.withAlpha(90),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      ),
                    ),

                  // Layer 3: Detected Face Confidence Badge & Full Frame CCTV indicator
                  if (_faceDetectionResult != null && _faceDetectionResult!.hasFace)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade700,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fullscreen_rounded, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              'Enrolled Face (${_faceDetectionResult!.confidence.toInt()}%)',
                              style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (widget.student.hasFaceEnrolled)
                    Positioned(
                      top: 10,
                      right: hasPhoto ? 46 : 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 13, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Currently Enrolled', style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),

                  if (hasPhoto)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _isSaving ? null : _clearPhoto,
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),

                  // Layer 4: Floating Position & Alignment Controls Bar (Left, Right, Up, Down, Zoom, Reset, Check)
                  if (hasPhoto)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xE61E1E2C),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.teal.withAlpha(120), width: 1),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
                          ],
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.open_with_rounded, size: 14, color: Colors.tealAccent),
                              const SizedBox(width: 4),
                              const Text(
                                'Move:',
                                style: TextStyle(fontSize: 10.5, color: Colors.white70, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 6),

                              // Directional Arrows
                              _buildPanButton(
                                icon: Icons.arrow_back_rounded,
                                tooltip: 'Bayein (Move Left)',
                                onPressed: () => setState(() => _imagePanX -= 12),
                              ),
                              _buildPanButton(
                                icon: Icons.arrow_upward_rounded,
                                tooltip: 'Upar (Move Up)',
                                onPressed: () => setState(() => _imagePanY -= 12),
                              ),
                              _buildPanButton(
                                icon: Icons.arrow_downward_rounded,
                                tooltip: 'Neeche (Move Down)',
                                onPressed: () => setState(() => _imagePanY += 12),
                              ),
                              _buildPanButton(
                                icon: Icons.arrow_forward_rounded,
                                tooltip: 'Dayein (Move Right)',
                                onPressed: () => setState(() => _imagePanX += 12),
                              ),

                              Container(
                                height: 16,
                                width: 1,
                                color: Colors.white24,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                              ),

                              // Zoom In & Out
                              _buildPanButton(
                                icon: Icons.zoom_in_rounded,
                                tooltip: 'Zoom In',
                                onPressed: () => setState(() => _imageZoom = (_imageZoom + 0.1).clamp(0.5, 3.5)),
                              ),
                              _buildPanButton(
                                icon: Icons.zoom_out_rounded,
                                tooltip: 'Zoom Out',
                                onPressed: () => setState(() => _imageZoom = (_imageZoom - 0.1).clamp(0.5, 3.5)),
                              ),
                              _buildPanButton(
                                icon: Icons.refresh_rounded,
                                tooltip: 'Reset Position',
                                onPressed: () => setState(() {
                                  _imagePanX = 0.0;
                                  _imagePanY = 0.0;
                                  _imageZoom = 1.0;
                                }),
                              ),

                              Container(
                                height: 16,
                                width: 1,
                                color: Colors.white24,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                              ),

                              // Check Fit
                              InkWell(
                                onTap: _isCheckingFaceAlignment ? null : _checkFaceAlignment,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade700,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_isCheckingFaceAlignment)
                                        const SizedBox(
                                          width: 10,
                                          height: 10,
                                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                                        )
                                      else
                                        const Icon(Icons.check_circle_outline_rounded, size: 12, color: Colors.white),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'Check Fit',
                                        style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (hasPhoto)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Row(
                children: [
                  Icon(Icons.touch_app_rounded, size: 13, color: Colors.teal.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Drag the photo or use controls to center the face within the circle.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? Colors.tealAccent.shade100 : Colors.teal.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.videocam_rounded, size: 16),
                  label: const Text('Camera / CCTV', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSaving ? null : _captureFromCamera,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_rounded, size: 16),
                  label: const Text('Upload Photo', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSaving ? null : _pickPhoto,
                ),
              ),
              if (hasPhoto) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.orange),
                  label: const Text('Clear', style: TextStyle(fontSize: 12, color: Colors.orange)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    side: BorderSide(color: Colors.orange.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSaving ? null : _clearPhoto,
                ),
              ],
              if (widget.student.hasFaceEnrolled) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                  label: const Text('Remove Face', style: TextStyle(fontSize: 12, color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    side: BorderSide(color: Colors.red.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSaving ? null : _deleteFaceFromDatabase,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_isSaving ? 'Extracting & Enrolling...' : 'Save Face Enrollment'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isSaving || !hasPhoto ? null : _saveFaceEnrollment,
            ),
          ),
        ],
      ),
    );
  }

  // ─── FINGERPRINT ENROLLMENT TAB ──────────────────────────────────
  Widget _buildFingerprintTab(bool isDark) {
    final scannerConnected = _scannerStatus?.isConnected == true;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Live Hardware Status Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scannerConnected ? Colors.green.withAlpha(20) : Colors.amber.withAlpha(25),
              border: Border.all(
                color: scannerConnected ? Colors.green.withAlpha(120) : Colors.amber.withAlpha(120),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  scannerConnected ? Icons.check_circle_rounded : Icons.sensors_off_rounded,
                  color: scannerConnected ? Colors.green : Colors.amber.shade800,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scannerConnected
                            ? 'Scanner Ready: ${_scannerStatus?.deviceModel}'
                            : 'Biometric Scanner Not Detected',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: scannerConnected ? Colors.green.shade800 : Colors.amber.shade900,
                        ),
                      ),
                      Text(
                        scannerConnected
                            ? 'Port ${_scannerStatus?.activePort ?? 11100} • RD Service Active'
                            : 'Connect Mantra / Morpho / SecuGen USB scanner',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scannerConnected ? Colors.green.shade700 : Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Check Scanner Status',
                  icon: _isCheckingHardware
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: _isCheckingHardware ? null : () => _checkHardware(force: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Sensor touch area
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _fingerCaptured
                      ? Colors.blue
                      : (_isCapturingFinger
                          ? Colors.orange
                          : (_fingerErrorMessage != null ? Colors.red : Colors.grey.shade300)),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_isCapturingFinger)
                        const SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.blue),
                        ),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: _fingerCaptured
                              ? Colors.blue.withAlpha(30)
                              : (_fingerErrorMessage != null ? Colors.red.withAlpha(20) : Colors.grey.withAlpha(20)),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.fingerprint_rounded,
                          size: 52,
                          color: _fingerCaptured
                              ? Colors.blue
                              : (_isCapturingFinger
                                  ? Colors.orange
                                  : (_fingerErrorMessage != null ? Colors.red : Colors.grey.shade400)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _isCapturingFinger
                        ? 'Place finger on scanner now...'
                        : (_fingerCaptured
                            ? 'Fingerprint Captured ($_fingerQuality% Quality) ✅'
                            : (_fingerErrorMessage != null
                                ? 'Hardware Error'
                                : (scannerConnected ? 'Scanner Active — Click Read' : 'Scanner Disconnected'))),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _fingerCaptured
                          ? Colors.blue
                          : (_isCapturingFinger
                              ? Colors.orange
                              : (_fingerErrorMessage != null ? Colors.red : Colors.grey.shade700)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_fingerErrorMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _fingerErrorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w500),
                      ),
                    )
                  else
                    Text(
                      'Compatible with Mantra MFS100, SecuGen Hamster, Morpho & Startek RD Services',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Capture button
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.fingerprint_rounded, size: 18),
                  label: const Text('Read Fingerprint'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSaving || _isCapturingFinger ? null : _captureFingerprint,
                ),
              ),
              if (_fingerCaptured) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.orange),
                  label: const Text('Clear Scan', style: TextStyle(fontSize: 12, color: Colors.orange)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    side: BorderSide(color: Colors.orange.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSaving
                      ? null
                      : () => setState(() {
                            _fingerCaptured = false;
                            _capturedFingerTemplate = null;
                          }),
                ),
              ],
              if (widget.student.hasFingerprintEnrolled) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                  label: const Text('Remove', style: TextStyle(fontSize: 12, color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    side: BorderSide(color: Colors.red.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSaving ? null : _deleteFingerprintFromDatabase,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_isSaving ? 'Enrolling...' : 'Save Fingerprint Enrollment'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isSaving || !_fingerCaptured ? null : _saveFingerprintEnrollment,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class FaceReticleMaskPainter extends CustomPainter {
  final Rect ovalRect;
  final bool isFaceDetected;
  final bool hasPhoto;

  FaceReticleMaskPainter({
    required this.ovalRect,
    required this.isFaceDetected,
    required this.hasPhoto,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Viewfinder Corner Brackets across the frame (CCTV / HD Camera style)
    final cornerPaint = Paint()
      ..color = (isFaceDetected ? Colors.greenAccent : Colors.tealAccent).withAlpha(180)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 22.0;
    const pad = 10.0;

    // Top-Left
    canvas.drawLine(const Offset(pad, pad + len), const Offset(pad, pad), cornerPaint);
    canvas.drawLine(const Offset(pad, pad), const Offset(pad + len, pad), cornerPaint);
    // Top-Right
    canvas.drawLine(Offset(size.width - pad - len, pad), Offset(size.width - pad, pad), cornerPaint);
    canvas.drawLine(Offset(size.width - pad, pad), Offset(size.width - pad, pad + len), cornerPaint);
    // Bottom-Left
    canvas.drawLine(Offset(pad, size.height - pad - len), Offset(pad, size.height - pad), cornerPaint);
    canvas.drawLine(Offset(pad, size.height - pad), Offset(pad + len, size.height - pad), cornerPaint);
    // Bottom-Right
    canvas.drawLine(Offset(size.width - pad - len, size.height - pad), Offset(size.width - pad, size.height - pad), cornerPaint);
    canvas.drawLine(Offset(size.width - pad, size.height - pad), Offset(size.width - pad, size.height - pad - len), cornerPaint);

    if (!hasPhoto) {
      // Guide oval when no photo is selected
      final borderPaint = Paint()
        ..color = Colors.teal.withAlpha(90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawOval(ovalRect, borderPaint);

      // Eye Level Alignment Guide Line
      final eyeLineY = ovalRect.top + ovalRect.height * 0.35;
      final guidePaint = Paint()
        ..color = Colors.tealAccent.withAlpha(60)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(ovalRect.left + 25, eyeLineY),
        Offset(ovalRect.right - 25, eyeLineY),
        guidePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FaceReticleMaskPainter oldDelegate) {
    return oldDelegate.ovalRect != ovalRect ||
        oldDelegate.isFaceDetected != isFaceDetected ||
        oldDelegate.hasPhoto != hasPhoto;
  }
}

