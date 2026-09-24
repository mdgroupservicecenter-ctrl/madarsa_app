import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/biometric_hardware_service.dart';
import '../../../../core/services/attendance_timing_helper.dart';
import '../../../../core/services/cctv_attendance_engine.dart';
import '../../../../core/services/cctv_schedule_resolver.dart';
import '../../../../core/services/cctv_stream_service.dart';
import '../../../../core/services/cctv_native_face_engine.dart';
import '../../../../core/services/cctv_discovery_service.dart';
import '../../../../core/storage/database_helper.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/attendance_models.dart';
import '../../data/repositories/attendance_repository.dart';

enum AttendanceMasterMode {
  auto,     // Automatically ON during Shift/Period, OFF during Breaks/Outside hours
  manualOn, // Manually FORCED ON (Admin takes attendance right now)
  manualOff // Manually FORCED OFF (Admin pauses attendance completely)
}

class CctvAttendanceKioskScreen extends StatefulWidget {
  final List<StudentAttendance> initialStudents;
  final AttendanceRepository repository;
  final String? shiftId;
  final String? shiftName;
  final String? shiftStartTime;

  const CctvAttendanceKioskScreen({
    super.key,
    required this.initialStudents,
    required this.repository,
    this.shiftId,
    this.shiftName,
    this.shiftStartTime,
  });

  @override
  State<CctvAttendanceKioskScreen> createState() => _CctvAttendanceKioskScreenState();
}

class _CctvAttendanceKioskScreenState extends State<CctvAttendanceKioskScreen> {
  late final CctvStreamService _streamService;
  late final CctvAttendanceEngine _engine;

  StreamSubscription<CctvFramePayload>? _frameSubscription;
  StreamSubscription<List<CctvTrackedFace>>? _facesSubscription;
  StreamSubscription<CctvAttendanceEvent>? _eventSubscription;
  StreamSubscription<({int liveCount, int totalCount})>? _peopleCountSubscription;
  Timer? _clockTimer;

  DateTime _currentTime = DateTime.now();
  final ValueNotifier<List<CctvTrackedFace>> _trackedFacesNotifier = ValueNotifier<List<CctvTrackedFace>>([]);
  final List<CctvAttendanceEvent> _eventsFeed = [];

  // 0% Lag ValueNotifiers for targeted UI updates
  final ValueNotifier<DateTime> _clockNotifier = ValueNotifier<DateTime>(DateTime.now());
  late final ValueNotifier<({int total, int present, int late})> _statsNotifier;
  final ValueNotifier<({int liveCount, int totalCount})> _peopleCountNotifier =
      ValueNotifier<({int liveCount, int totalCount})>((liveCount: 0, totalCount: 0));
  final ValueNotifier<int> _feedUpdateNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _attendanceActiveNotifier = ValueNotifier<bool>(false);

  bool _isPaused = false;
  DateTime _lastAiInferenceTime = DateTime.fromMillisecondsSinceEpoch(0);
  int _presentCount = 0;
  int _lateCount = 0;
  int _totalStudents = 0;

  // Multi-Class Support
  List<StudentAttendance> _allStudentsPool = [];
  String _selectedClassFilter = 'ALL';
  List<String> _classList = ['ALL'];

  // Period & Shift Attendance Mode
  bool _isPeriodMode = false;
  int _selectedPeriodNumber = 1;

  // Smart Schedule Timetable & Master Mode Switch
  final CctvScheduleResolver _scheduleResolver = CctvScheduleResolver();
  bool _isAutoSchedule = true;
  AttendanceMasterMode _masterMode = AttendanceMasterMode.auto;
  CctvScheduleState? _currentScheduleState;

  // Multi-Camera Simultaneous Attendance Mode (Security NVR)
  bool _isMultiCamMode = false;
  bool _isPeopleCountingEnabled = true;
  bool _isAntiSpoofingEnabled = true;
  int _spoofSensitivityLevel = 2; // 0=Off, 1=Low, 2=Medium, 3=High

  // Multi-Camera Round-Robin Fair AI Scheduler & Live Headcount Aggregator
  final Map<String, CctvFramePayload> _latestFramesByCamera = {};
  final Map<String, DateTime> _lastAiInferenceByCamera = {};
  final Map<String, int> _multiCamLiveCountByCamera = {};

  @override
  void initState() {
    super.initState();
    _streamService = CctvStreamService();
    _engine = CctvAttendanceEngine(repository: widget.repository);

    _engine.currentShiftId = widget.shiftId;
    _engine.currentShiftName = widget.shiftName;
    _engine.currentShiftStartTime = widget.shiftStartTime;
    _engine.setCameraName(_streamService.activeCameraName);

    _allStudentsPool = List.from(widget.initialStudents);
    _totalStudents = widget.initialStudents.length;
    _presentCount = widget.initialStudents.where((s) => s.status == 'Present').length;
    _lateCount = widget.initialStudents.where((s) => s.status == 'Late').length;
    _statsNotifier = ValueNotifier((total: _totalStudents, present: _presentCount, late: _lateCount));

    // Seed session state with already-scanned students
    _engine.initializeSessionFromStudents(
      widget.initialStudents,
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      widget.shiftId,
    );

    // Synchronously resolve initial schedule so isAttendanceSuspended is accurate BEFORE any frames arrive
    _currentTime = DateTime.now();
    _clockNotifier.value = _currentTime;
    _updateAutoSchedule(_currentTime);

    _peopleCountSubscription = _engine.onPeopleCountChanged.listen((counts) {
      if (!_isMultiCamMode) {
        _peopleCountNotifier.value = counts;
      }
    });

    _streamService.loadSavedProfiles().then((_) {
      if (mounted) setState(() {});
    });

    _scheduleResolver.syncFromMadarsaTimings().then((_) {
      if (mounted) {
        _updateAutoSchedule(DateTime.now());
        setState(() {});
      }
    });

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final now = DateTime.now();
        _currentTime = now;
        _clockNotifier.value = now;
        _updateAutoSchedule(now);
      }
    });

    _initEngineAndStream();
  }

  void _updateAutoSchedule(DateTime now) {
    final state = _scheduleResolver.resolveCurrentState(now);
    _currentScheduleState = state;

    final bool shouldBeActive;
    if (_masterMode == AttendanceMasterMode.manualOn) {
      shouldBeActive = true;
    } else if (_masterMode == AttendanceMasterMode.manualOff) {
      shouldBeActive = false;
    } else {
      // In Auto mode: if schedule says active, or if specified targetShiftId is in operating window
      if (state.isAttendanceActive) {
        shouldBeActive = true;
      } else if (widget.shiftId != null && widget.shiftId!.isNotEmpty) {
        final windowCheck = AttendanceTimingHelper.checkShiftWindow(now, targetShiftId: widget.shiftId);
        shouldBeActive = windowCheck.isWithinWindow;
      } else {
        shouldBeActive = false;
      }
    }

    _engine.isAttendanceSuspended = !shouldBeActive;
    _engine.scheduleSuspensionReason = shouldBeActive
        ? null
        : (_masterMode == AttendanceMasterMode.manualOff
            ? 'Attendance OFF (Manual)'
            : state.statusSubtitle);
    if (_attendanceActiveNotifier.value != shouldBeActive) {
      _attendanceActiveNotifier.value = shouldBeActive;
    }

    if (shouldBeActive && state.activeSlot != null) {
      if (state.isShift) {
        final rawId = state.activeSlot!.id;
        final cleanId = rawId.startsWith('shift_') ? rawId.substring(6) : rawId;
        _engine.currentShiftId = cleanId;
        _engine.currentShiftName = state.activeSlot!.name;
        _engine.currentShiftStartTime = state.activeSlot!.startTime;
        if (_isPeriodMode) {
          _isPeriodMode = false;
          _engine.switchAttendanceMode(periodMode: false);
        }
      } else if (state.isPeriod) {
        if (!_isPeriodMode || _selectedPeriodNumber != state.periodNumber) {
          _isPeriodMode = true;
          _selectedPeriodNumber = state.periodNumber;
          _engine.switchAttendanceMode(
            periodMode: true,
            periodNumber: state.periodNumber,
            periodName: state.activeSlot?.name,
          );
        }
      }
    } else if (!state.isPeriod && _isPeriodMode && _isAutoSchedule) {
      _isPeriodMode = false;
      _engine.switchAttendanceMode(periodMode: false);
    }
  }

  void _setMasterMode(AttendanceMasterMode mode) {
    setState(() {
      _masterMode = mode;
      _updateAutoSchedule(_currentTime);
    });
  }

  Future<void> _initEngineAndStream() async {
    // 1. Attempt to load all students across all classes for All-Classes gate attendance
    try {
      final db = await DatabaseHelper().database;
      final rows = await db.query(
        'students',
        where: 'is_active = 1 OR is_active IS NULL',
        orderBy: 'full_name ASC',
      );
      if (rows.isNotEmpty) {
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        List<Map<String, dynamic>> attRows = [];
        try {
          attRows = await db.query('attendance', where: 'date = ?', whereArgs: [todayStr]);
        } catch (_) {}
        final attMap = {for (final a in attRows) a['student_id']?.toString() ?? '': a};

        final List<StudentAttendance> fullList = [];
        for (final r in rows) {
          try {
            final fData = r['face_data']?.toString().trim();
            final photo = r['photo_path']?.toString().trim();
            final hasFace = (fData != null && fData.isNotEmpty) ||
                (photo != null && photo.isNotEmpty && File(photo).existsSync());
            final sid = r['id']?.toString() ?? '';
            final todayAtt = attMap[sid];
            fullList.add(StudentAttendance(
              id: sid,
              registrationNumber: r['registration_number']?.toString() ?? r['gr_no']?.toString() ?? '',
              grNo: r['gr_no']?.toString() ?? '',
              fullName: r['full_name']?.toString() ?? '',
              className: r['class_name']?.toString() ?? '',
              photoPath: photo,
              hasFaceEnrolled: hasFace,
              faceData: fData,
              status: todayAtt?['status']?.toString(),
              checkInTime: todayAtt?['check_in_time']?.toString() ?? '',
              checkOutTime: todayAtt?['check_out_time']?.toString() ?? '',
              verificationMethod: todayAtt?['verification_method']?.toString() ?? 'Manual',
              shiftId: todayAtt?['shift_id']?.toString() ?? widget.shiftId ?? '',
              shiftName: todayAtt?['shift_name']?.toString() ?? widget.shiftName ?? '',
            ));
          } catch (_) {}
        }
        if (fullList.isNotEmpty) {
          final initialMap = {for (final s in widget.initialStudents) s.id: s};
          for (final s in fullList) {
            final existing = initialMap[s.id];
            if (existing != null) {
              s.status = existing.status;
              s.checkInTime = existing.checkInTime;
              s.checkOutTime = existing.checkOutTime;
              if ((s.faceData == null || s.faceData!.isEmpty) && existing.faceData != null && existing.faceData!.isNotEmpty) {
                s.faceData = existing.faceData;
                s.hasFaceEnrolled = true;
              }
              if ((s.photoPath == null || s.photoPath!.isEmpty) && existing.photoPath != null && existing.photoPath!.isNotEmpty) {
                s.photoPath = existing.photoPath;
                s.hasFaceEnrolled = true;
              }
            }
          }
          _allStudentsPool = fullList;
        }
      }
    } catch (e) {
      debugPrint('[CCTV Kiosk] Error loading full students pool: $e');
    }

    // Fallback to API if local sqlite was empty or only had partial initial students
    if (_allStudentsPool.length <= widget.initialStudents.length && widget.initialStudents.isNotEmpty) {
      try {
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final apiStudents = await widget.repository.getStudentAttendance(
          className: 'ALL',
          date: todayStr,
          shiftId: widget.shiftId,
        );
        if (apiStudents.length > _allStudentsPool.length) {
          _allStudentsPool = apiStudents;
        }
      } catch (_) {}
    }

    final classes = _allStudentsPool
        .map((s) => s.className.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    _classList = ['ALL', ...classes];

    final initialList = _selectedClassFilter == 'ALL'
        ? _allStudentsPool
        : _allStudentsPool.where((s) => s.className == _selectedClassFilter).toList();

    _totalStudents = initialList.length;
    _presentCount = initialList.where((s) => s.status == 'Present').length;
    _lateCount = initialList.where((s) => s.status == 'Late').length;
    _statsNotifier.value = (total: _totalStudents, present: _presentCount, late: _lateCount);
    if (mounted) setState(() {});

    _engine.initializeSessionFromStudents(
      _allStudentsPool,
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      widget.shiftId,
    );

    await _engine.initializeStudents(initialList);

    // Load saved preferences
    final prefs = await SharedPreferences.getInstance();
    final savedSourceStr = prefs.getString('cctv_source_type') ?? 'webcam';
    final savedIpUrl = prefs.getString('cctv_ip_url') ?? 'http://192.168.1.100:8080/shot.jpg';
    final savedUser = prefs.getString('cctv_username') ?? '';
    final savedPass = prefs.getString('cctv_password') ?? '';
    final savedThreshold = (prefs.getDouble('cctv_threshold') ?? 55.0).clamp(50.0, 65.0);
    final savedCooldown = prefs.getInt('cctv_cooldown_min') ?? 5;
    final savedSensitivity = prefs.getString('cctv_sensitivity') ?? 'sensitive';
    final savedDetectAll = prefs.getBool('cctv_detect_all_humans') ?? true;
    final savedCounting = prefs.getBool('cctv_enable_people_counting') ?? true;
    final savedAntiSpoofing = prefs.getBool('cctv_enable_anti_spoofing') ?? true;
    final savedSpoofLevel = prefs.getInt('cctv_spoof_sensitivity_level') ?? 2;
    final savedFps = prefs.getInt('cctv_target_fps') ?? 60;

    _engine.matchThreshold = savedThreshold;
    _engine.cooldownDuration = Duration(minutes: savedCooldown);
    _engine.detectAllHumans = savedDetectAll;
    _isPeopleCountingEnabled = savedCounting;
    _engine.enablePeopleCounting = savedCounting;
    _isAntiSpoofingEnabled = savedAntiSpoofing;
    _spoofSensitivityLevel = savedSpoofLevel.clamp(0, 3);
    _engine.spoofSensitivityLevel = _spoofSensitivityLevel;
    _engine.enableAntiSpoofing = savedAntiSpoofing;

    if (savedSensitivity == 'strict') {
      _engine.detectionSensitivity = FaceDetectionSensitivity.strict;
    } else if (savedSensitivity == 'balanced') {
      _engine.detectionSensitivity = FaceDetectionSensitivity.balanced;
    } else {
      _engine.detectionSensitivity = FaceDetectionSensitivity.sensitive;
    }

    CctvSourceType savedSource = CctvSourceType.webcam;
    if (savedSourceStr == 'ipCamera') savedSource = CctvSourceType.ipCamera;
    if (savedSourceStr == 'simulation') savedSource = CctvSourceType.simulation;

    _facesSubscription = _engine.onFacesTracked.listen((faces) {
      if (mounted && !_isMultiCamMode) {
        _trackedFacesNotifier.value = faces;
      }
    });

    _eventSubscription = _engine.onAttendanceMarked.listen((event) {
      if (mounted) {
        _eventsFeed.insert(0, event);
        if (_eventsFeed.length > 50) _eventsFeed.removeLast();
        if (!event.status.contains('Info Only')) {
          final poolStudent = _allStudentsPool.where((s) => s.id == event.studentId).firstOrNull;
          if (poolStudent != null) {
            if (event.status.contains('Present')) {
              poolStudent.status = 'Present';
            } else if (event.status.contains('Late')) {
              poolStudent.status = 'Late';
            }
          }
          final currentFiltered = _selectedClassFilter == 'ALL'
              ? _allStudentsPool
              : _allStudentsPool.where((s) => s.className == _selectedClassFilter).toList();
          _totalStudents = currentFiltered.length;
          _presentCount = currentFiltered.where((s) => s.status == 'Present').length;
          _lateCount = currentFiltered.where((s) => s.status == 'Late').length;
          _statsNotifier.value = (total: _totalStudents, present: _presentCount, late: _lateCount);
        }
        _feedUpdateNotifier.value++;
      }
    });

    _frameSubscription = _streamService.onTaggedFrameCaptured.listen((payload) {
      if (!_isPaused && mounted) {
        final now = DateTime.now();
        if (!_isMultiCamMode) {
          // AI Face Recognition Throttle: >= 330ms (~3 inferences/sec)
          // Video frames render at full 60 FPS smoothly via singleDisplayImageNotifier directly on the GPU
          if (!_engine.isProcessing && now.difference(_lastAiInferenceTime).inMilliseconds >= 330) {
            _lastAiInferenceTime = now;
            _engine.processFrame(
              payload.bytes,
              cameraName: payload.cameraName,
              cameraId: payload.cameraId,
              cameraRole: payload.cameraRole,
            );
          }
        } else {
          // Multi-Camera Mode:
          // 1. Buffer latest frame for this camera source (overwriting previous to keep memory O(1))
          _latestFramesByCamera[payload.cameraId] = payload;

          // 2. Fair Round-Robin AI Scheduler:
          // Ensure strictly ONE frame is processed by AI at a time, spaced by >= 250ms.
          // Cycles through all active camera sources evenly so no camera is ever starved.
          if (!_engine.isProcessing && now.difference(_lastAiInferenceTime).inMilliseconds >= 250) {
            final activeSourceIds = _streamService.activeChannels
                .map((c) => c.profile.id)
                .toSet();

            // Select the least recently processed active camera with a buffered frame
            String? candidateCamId;
            DateTime oldestInference = now;

            for (final camId in activeSourceIds) {
              if (!_latestFramesByCamera.containsKey(camId)) continue;
              final lastInferred = _lastAiInferenceByCamera[camId] ?? DateTime.fromMillisecondsSinceEpoch(0);
              if (candidateCamId == null || lastInferred.isBefore(oldestInference)) {
                oldestInference = lastInferred;
                candidateCamId = camId;
              }
            }

            if (candidateCamId != null && _latestFramesByCamera.containsKey(candidateCamId)) {
              final frameToProcess = _latestFramesByCamera[candidateCamId]!;
              _lastAiInferenceTime = now;
              _lastAiInferenceByCamera[candidateCamId] = now;

              final sharedChannels = _streamService.getChannelsSharingSource(candidateCamId);
              final targetChannels = sharedChannels.isNotEmpty
                  ? sharedChannels
                  : _streamService.activeChannels.where((c) => c.profile.id == candidateCamId).toList();

              _engine.processFrame(
                frameToProcess.bytes,
                cameraName: frameToProcess.cameraName,
                cameraId: frameToProcess.cameraId,
                cameraRole: frameToProcess.cameraRole,
              ).then((faces) {
                if (mounted) {
                  for (final ch in targetChannels) {
                    ch.trackedFacesNotifier.value = faces;
                  }
                  if (_isMultiCamMode && _isPeopleCountingEnabled) {
                    _multiCamLiveCountByCamera[candidateCamId!] = faces.length;
                    int aggregateLive = 0;
                    for (final srcId in activeSourceIds) {
                      aggregateLive += (_multiCamLiveCountByCamera[srcId] ?? 0);
                    }
                    _peopleCountNotifier.value = (
                      liveCount: aggregateLive,
                      totalCount: _engine.totalSessionPeopleCount,
                    );
                  }
                }
              });
            }
          }
        }
      }
    });

    await _streamService.discoverCameras();
    final hasWebcam = _streamService.availableCamerasList.isNotEmpty || CctvNativeFaceEngine.instance.isAvailable;

    final initialSource = (savedSource == CctvSourceType.webcam && !hasWebcam)
        ? CctvSourceType.simulation
        : savedSource;

    final enrolledSimulationImages = _allStudentsPool
        .where((s) => s.hasFaceEnrolled && s.photoPath != null && s.photoPath!.isNotEmpty)
        .map((s) => s.photoPath!)
        .where((p) => File(p).existsSync())
        .toSet()
        .toList();

    await _streamService.startStream(CctvCameraConfig(
      sourceType: initialSource,
      ipUrl: savedIpUrl,
      username: savedUser,
      password: savedPass,
      targetFps: savedFps,
      simulationImages: enrolledSimulationImages,
    ));

    if (mounted) setState(() {});
  }

  Future<void> _changeClassFilter(String newFilter) async {
    _selectedClassFilter = newFilter;
    final filtered = newFilter == 'ALL'
        ? _allStudentsPool
        : _allStudentsPool.where((s) => s.className == newFilter).toList();
    _totalStudents = filtered.length;
    _presentCount = filtered.where((s) => s.status == 'Present').length;
    _lateCount = filtered.where((s) => s.status == 'Late').length;
    _statsNotifier.value = (total: _totalStudents, present: _presentCount, late: _lateCount);
    await _engine.initializeStudents(filtered);
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera(CctvCameraProfile profile) async {
    final enrolledSimulationImages = _allStudentsPool
        .where((s) => s.hasFaceEnrolled && s.photoPath != null && s.photoPath!.isNotEmpty)
        .map((s) => s.photoPath!)
        .where((p) => File(p).existsSync())
        .toSet()
        .toList();
    await _streamService.switchCameraProfile(profile, simulationImages: enrolledSimulationImages);
    _engine.setCameraName(profile.name);
    if (mounted) setState(() {});
  }

  Future<void> _switchToWebcam() async {
    final webcamProfile = _streamService.cameraProfiles.firstWhere(
      (p) => p.sourceType == CctvSourceType.webcam,
      orElse: () => const CctvCameraProfile(
        id: 'webcam_default',
        name: 'Webcam',
        sourceType: CctvSourceType.webcam,
      ),
    );
    await _switchCamera(webcamProfile);
  }

  Future<void> _switchToSimulation() async {
    final simProfile = _streamService.cameraProfiles.firstWhere(
      (p) => p.sourceType == CctvSourceType.simulation,
      orElse: () => const CctvCameraProfile(
        id: 'sim_default',
        name: 'Demo Simulation',
        sourceType: CctvSourceType.simulation,
      ),
    );
    await _switchCamera(simProfile);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _frameSubscription?.cancel();
    _facesSubscription?.cancel();
    _eventSubscription?.cancel();
    _peopleCountSubscription?.cancel();
    _clockNotifier.dispose();
    _statsNotifier.dispose();
    _peopleCountNotifier.dispose();
    _feedUpdateNotifier.dispose();
    _attendanceActiveNotifier.dispose();
    _trackedFacesNotifier.dispose();
    _streamService.stopMultiCameraStreams();
    _streamService.stopStream();
    _latestFramesByCamera.clear();
    _lastAiInferenceByCamera.clear();
    _multiCamLiveCountByCamera.clear();
    _engine.dispose();
    super.dispose();
  }

  ImageProvider? _getStudentPhotoProvider(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final clean = path.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return NetworkImage(clean);
    }
    try {
      final file = File(clean);
      if (file.existsSync()) {
        return FileImage(file);
      }
    } catch (_) {}
    if (clean.startsWith('/') || clean.startsWith('\\')) {
      final fullUrl = '${ApiConstants.baseUrl.replaceAll("/api", "")}$clean';
      return NetworkImage(fullUrl);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hijri = HijriCalendar.fromDate(_currentTime);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // App-consistent clean Light background
      body: SafeArea(
        child: Column(
          children: [
            // Top App-Theme Light Header Bar
            _buildTopLightHeaderBar(hijri),

            // Main Content Area: Left Viewport (66%) + Right Activity Feed (34%)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left / Center: CCTV Live Stream inside a clean rounded card
                    Expanded(
                      flex: 66,
                      child: _buildCctvViewportCard(),
                    ),

                    const SizedBox(width: 16),

                    // Right: Live Activity Stream Feed Card with Class Filter on Top
                    Expanded(
                      flex: 34,
                      child: Column(
                        children: [
                          _buildClassFilterCard(),
                          const SizedBox(height: 10),
                          Expanded(
                            child: _buildLiveActivityFeedCard(),
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

  static const double _kTopItemHeight = 36.0;

  Widget _buildTopLightHeaderBar(HijriCalendar hijri) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1250;
        final isVeryCompact = constraints.maxWidth < 1100;
        final isUltraCompact = constraints.maxWidth < 950;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // ─── LEFT & CENTER CONTROLS (Scrolls smoothly horizontally if window is small) ───
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Logo & Engine Badge
                      SizedBox(
                        height: _kTopItemHeight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: _kTopItemHeight,
                              height: _kTopItemHeight,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.2)),
                              ),
                              child: const Icon(Icons.videocam_rounded, color: Color(0xFF0F766E), size: 20),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isCompact ? 'CCTV AI' : 'CCTV AI Attendance',
                                      style: AppTheme.getFontStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: _engine.isNativeEngineActive ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: _engine.isNativeEngineActive ? const Color(0xFFA7F3D0) : const Color(0xFFBFDBFE),
                                        ),
                                      ),
                                      child: Text(
                                        _engine.isNativeEngineActive ? '⚡ C++' : 'DART',
                                        style: TextStyle(
                                          color: _engine.isNativeEngineActive ? const Color(0xFF065F46) : const Color(0xFF1E40AF),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 1),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: _isPaused ? Colors.orange : const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    ValueListenableBuilder<double>(
                                      valueListenable: _streamService.actualFpsNotifier,
                                      builder: (context, fps, _) {
                                        final displayFps = fps > 0 ? fps : _streamService.config.targetFps.toDouble();
                                        return Text(
                                          _isPaused
                                              ? 'PAUSED'
                                              : 'LIVE • ${_streamService.config.sourceType.name.toUpperCase()} • ${displayFps.toStringAsFixed(1)} FPS',
                                          style: TextStyle(
                                            color: _isPaused ? Colors.orange.shade700 : const Color(0xFF64748B),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // 3. MASTER ATTENDANCE TOGGLE BUTTON (User Request: On/Off/Auto Button)
                      _buildMasterAttendanceButton(),
                      const SizedBox(width: 8),

                      // 4. Schedule Timetable / Period Dropdown (Fixed 36px height)
                      Container(
                        height: _kTopItemHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _isAutoSchedule
                              ? const Color(0xFFF0FDF4)
                              : (_isPeriodMode ? const Color(0xFFEFF6FF) : const Color(0xFFFEF3C7)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isAutoSchedule
                                ? const Color(0xFF86EFAC)
                                : (_isPeriodMode ? const Color(0xFFBFDBFE) : const Color(0xFFFDE68A)),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _isAutoSchedule ? 100 : (_isPeriodMode ? _selectedPeriodNumber : 0),
                            isDense: true,
                            menuMaxHeight: 350,
                            icon: Icon(
                              _isAutoSchedule
                                  ? Icons.auto_mode_rounded
                                  : (_isPeriodMode ? Icons.access_time_filled_rounded : Icons.today_rounded),
                              size: 14,
                              color: _isAutoSchedule
                                  ? const Color(0xFF16A34A)
                                  : (_isPeriodMode ? const Color(0xFF2563EB) : const Color(0xFFD97706)),
                            ),
                            style: TextStyle(
                              color: _isAutoSchedule
                                  ? const Color(0xFF14532D)
                                  : (_isPeriodMode ? const Color(0xFF1E40AF) : const Color(0xFF92400E)),
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                            selectedItemBuilder: (context) => [
                              const Align(alignment: Alignment.centerLeft, child: Text('🤖 Auto Timetable')),
                              const Align(alignment: Alignment.centerLeft, child: Text('📅 Daily Shift')),
                              ...List.generate(8, (i) => Align(
                                alignment: Alignment.centerLeft,
                                child: Text('⏰ Period ${i + 1}'),
                              )),
                            ],
                            items: [
                              const DropdownMenuItem(value: 100, child: Text('🤖 Auto Timetable')),
                              const DropdownMenuItem(value: 0, child: Text('📅 Force Daily Shift')),
                              ...List.generate(8, (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text('⏰ Force Period ${i + 1}'),
                              )),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  if (val == 100) {
                                    _isAutoSchedule = true;
                                    _updateAutoSchedule(_currentTime);
                                  } else if (val == 0) {
                                    _isAutoSchedule = false;
                                    _isPeriodMode = false;
                                    _engine.isAttendanceSuspended = (_masterMode == AttendanceMasterMode.manualOff);
                                    _engine.switchAttendanceMode(periodMode: false);
                                    _updateAutoSchedule(_currentTime);
                                  } else {
                                    _isAutoSchedule = false;
                                    _isPeriodMode = true;
                                    _selectedPeriodNumber = val;
                                    _engine.isAttendanceSuspended = (_masterMode == AttendanceMasterMode.manualOff);
                                    _engine.switchAttendanceMode(periodMode: true, periodNumber: val);
                                    _updateAutoSchedule(_currentTime);
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 5. PEOPLE / CROWD HEADCOUNT PILL (User Request: Program me Human Count)
                      _buildPeopleCounterPill(),
                      const SizedBox(width: 8),

                      // 5.5. ANTI-SPOOFING SHIELD PILL
                      _buildAntiSpoofPill(),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // ─── RIGHT ACTION GROUP (ALWAYS 100% VISIBLE & PINNED TO TOP-RIGHT CORNER) ───
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 6. Stats Pill (Decoupled with ValueListenableBuilder for 0% lag)
                  ValueListenableBuilder<({int total, int present, int late})>(
                    valueListenable: _statsNotifier,
                    builder: (context, stats, _) {
                      if (isUltraCompact) return const SizedBox.shrink();
                      return Container(
                        height: _kTopItemHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isVeryCompact) ...[
                              _buildStatItem('TOTAL', '${stats.total}', const Color(0xFF0284C7)),
                              Container(height: 14, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 5)),
                            ],
                            _buildStatItem('PRESENT', '${stats.present}', const Color(0xFF15803D)),
                            Container(height: 14, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 5)),
                            _buildStatItem('LATE', '${stats.late}', const Color(0xFFB45309)),
                          ],
                        ),
                      );
                    },
                  ),
                  if (!isUltraCompact) const SizedBox(width: 6),

                  // 7. Digital Clock (Decoupled with ValueListenableBuilder for 0% lag)
                  ValueListenableBuilder<DateTime>(
                    valueListenable: _clockNotifier,
                    builder: (context, time, _) {
                      return Container(
                        height: _kTopItemHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time_rounded, color: Color(0xFF0F766E), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('hh:mm:ss a').format(time),
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),

                  // 8. Multi-Cam Grid View Button (ALWAYS VISIBLE, Height 36px)
                  SizedBox(
                    height: _kTopItemHeight,
                    child: OutlinedButton.icon(
                      icon: Icon(
                        _isMultiCamMode ? Icons.grid_view_rounded : Icons.videocam_rounded,
                        size: 14,
                        color: _isMultiCamMode ? Colors.white : const Color(0xFF0F766E),
                      ),
                      label: Text(
                        _isMultiCamMode ? 'Grid' : 'Single',
                        style: TextStyle(
                          color: _isMultiCamMode ? Colors.white : const Color(0xFF0F766E),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _isMultiCamMode ? const Color(0xFF0F766E) : Colors.white,
                        side: BorderSide(color: _isMultiCamMode ? const Color(0xFF0F766E) : Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _toggleMultiCamMode,
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 9. Setup & Settings Button (ALWAYS PINNED RIGHT & VISIBLE, Height 36px)
                  SizedBox(
                    height: _kTopItemHeight,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.settings_rounded, size: 14),
                      label: Text(isCompact ? 'Setup' : 'CCTV Setup', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _showLightSettingsDialog,
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 10. Exit Button (ALWAYS VISIBLE, 36x36px)
                  Container(
                    width: _kTopItemHeight,
                    height: _kTopItemHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.close_rounded, color: Colors.grey.shade700, size: 18),
                      tooltip: 'Close Kiosk',
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Master Attendance Mode Button with live visual feedback and popup selector
  Widget _buildMasterAttendanceButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: _attendanceActiveNotifier,
      builder: (context, isActive, _) {
        final Color bgColor;
        final Color borderColor;
        final Color textColor;
        final IconData iconData;
        final String labelText;

        switch (_masterMode) {
          case AttendanceMasterMode.auto:
            if (isActive) {
              bgColor = const Color(0xFFF0FDF4);
              borderColor = const Color(0xFF86EFAC);
              textColor = const Color(0xFF15803D);
              iconData = Icons.auto_mode_rounded;
              labelText = '🤖 Attendance: Auto (Active)';
            } else {
              bgColor = const Color(0xFFFFFBEB);
              borderColor = const Color(0xFFFDE68A);
              textColor = const Color(0xFFB45309);
              iconData = Icons.pause_circle_outline_rounded;
              labelText = '⏸️ Attendance: Auto (Idle)';
            }
            break;
          case AttendanceMasterMode.manualOn:
            bgColor = const Color(0xFFECFDF5);
            borderColor = const Color(0xFF6EE7B7);
            textColor = const Color(0xFF065F46);
            iconData = Icons.check_circle_rounded;
            labelText = '🟢 Attendance: Force ON';
            break;
          case AttendanceMasterMode.manualOff:
            bgColor = const Color(0xFFFFF1F2);
            borderColor = const Color(0xFFFECDD3);
            textColor = const Color(0xFFBE123C);
            iconData = Icons.cancel_rounded;
            labelText = '🔴 Attendance: Force OFF';
            break;
        }

        return Container(
          height: _kTopItemHeight,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: PopupMenuButton<AttendanceMasterMode>(
            tooltip: 'Change Attendance Mode',
            offset: const Offset(0, 42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: _setMasterMode,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: AttendanceMasterMode.auto,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.auto_mode_rounded, color: Color(0xFF16A34A)),
                  title: const Text('🤖 Auto Timetable', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Follows school shift and period timings automatically', style: TextStyle(fontSize: 11)),
                  trailing: _masterMode == AttendanceMasterMode.auto ? const Icon(Icons.check_rounded, color: Color(0xFF16A34A)) : null,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: AttendanceMasterMode.manualOn,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669)),
                  title: const Text('🟢 Force ON', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669))),
                  subtitle: const Text('Record attendance right now regardless of schedule', style: TextStyle(fontSize: 11)),
                  trailing: _masterMode == AttendanceMasterMode.manualOn ? const Icon(Icons.check_rounded, color: Color(0xFF059669)) : null,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: AttendanceMasterMode.manualOff,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.cancel_rounded, color: Color(0xFFE11D48)),
                  title: const Text('🔴 Force OFF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFE11D48))),
                  subtitle: const Text('Stop recording attendance; camera and face detection remain active', style: TextStyle(fontSize: 11)),
                  trailing: _masterMode == AttendanceMasterMode.manualOff ? const Icon(Icons.check_rounded, color: Color(0xFFE11D48)) : null,
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconData, size: 14, color: textColor),
                  const SizedBox(width: 5),
                  Text(
                    labelText,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down_rounded, size: 16, color: textColor),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _togglePeopleCounting(bool enable) async {
    setState(() {
      _isPeopleCountingEnabled = enable;
      _engine.enablePeopleCounting = enable;
      if (!enable) {
        _peopleCountNotifier.value = (liveCount: 0, totalCount: 0);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cctv_enable_people_counting', enable);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enable ? 'Head Counting enabled.' : 'Head Counting disabled.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _setSpoofSensitivityLevel(int level) async {
    setState(() {
      _spoofSensitivityLevel = level.clamp(0, 3);
      if (level == 0) {
        _isAntiSpoofingEnabled = false;
        _engine.enableAntiSpoofing = false;
      } else {
        _isAntiSpoofingEnabled = true;
        _engine.enableAntiSpoofing = true;
        _engine.spoofSensitivityLevel = _spoofSensitivityLevel;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cctv_enable_anti_spoofing', _isAntiSpoofingEnabled);
    await prefs.setInt('cctv_spoof_sensitivity_level', _spoofSensitivityLevel);
    if (mounted) {
      final names = ['Off (Disabled)', 'Low (40% Permissive)', 'Medium (55% Balanced)', 'High (70% Strict)'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Anti-Spoofing Sensitivity: ${names[_spoofSensitivityLevel]}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _toggleAntiSpoofing(bool enable) async {
    setState(() {
      _isAntiSpoofingEnabled = enable;
      _engine.enableAntiSpoofing = enable;
      if (enable && _spoofSensitivityLevel == 0) {
        _spoofSensitivityLevel = 2; // Default back to Medium when re-enabled
        _engine.spoofSensitivityLevel = 2;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cctv_enable_anti_spoofing', enable);
    await prefs.setInt('cctv_spoof_sensitivity_level', _spoofSensitivityLevel);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enable
              ? 'Anti-Spoofing Shield enabled (${_spoofSensitivityLevel == 1 ? 'Low' : _spoofSensitivityLevel == 3 ? 'High' : 'Medium'}).'
              : 'Anti-Spoofing Shield disabled.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Anti-Spoofing Shield Pill with Sensitivity Level Selector (High / Medium / Low / Off)
  Widget _buildAntiSpoofPill() {
    final String levelLabel;
    final Color textColor;
    final Color bgColor;
    final Color borderColor;

    if (!_isAntiSpoofingEnabled || _spoofSensitivityLevel == 0) {
      levelLabel = '🛡️ Spoof: OFF';
      textColor = const Color(0xFFE11D48);
      bgColor = const Color(0xFFFFF1F2);
      borderColor = const Color(0xFFFECDD3);
    } else {
      textColor = const Color(0xFF15803D);
      bgColor = const Color(0xFFF0FDF4);
      borderColor = const Color(0xFF86EFAC);
      switch (_spoofSensitivityLevel) {
        case 1:
          levelLabel = '🛡️ Spoof: Low (40%)';
          break;
        case 2:
          levelLabel = '🛡️ Spoof: Med (55%)';
          break;
        case 3:
          levelLabel = '🛡️ Spoof: High (70%)';
          break;
        default:
          levelLabel = '🛡️ Spoof: Med (55%)';
      }
    }

    return Container(
      height: _kTopItemHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<int>(
            tooltip: 'Anti-Spoofing Sensitivity Level',
            offset: const Offset(0, 42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: _setSpoofSensitivityLevel,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 3,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.shield_rounded, color: Color(0xFFE11D48)),
                  title: const Text('🟠 High Sensitivity (70% - Strict)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Maximum security: MiniFASNet + Moiré + Chrominance checks',
                      style: TextStyle(fontSize: 11)),
                  trailing: (_isAntiSpoofingEnabled && _spoofSensitivityLevel == 3)
                      ? const Icon(Icons.check_rounded, color: Color(0xFFE11D48))
                      : null,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 2,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.verified_user_rounded, color: Color(0xFF0284C7)),
                  title: const Text('🔵 Medium Sensitivity (55% - Balanced)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Recommended: Balanced AI check, safe for CCTV & room light',
                      style: TextStyle(fontSize: 11)),
                  trailing: (_isAntiSpoofingEnabled && _spoofSensitivityLevel == 2)
                      ? const Icon(Icons.check_rounded, color: Color(0xFF0284C7))
                      : null,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 1,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.shield_outlined, color: Color(0xFF16A34A)),
                  title: const Text('🟢 Low Sensitivity (40% - Permissive)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Blocks obvious screen/paper replays, zero false rejections',
                      style: TextStyle(fontSize: 11)),
                  trailing: (_isAntiSpoofingEnabled && _spoofSensitivityLevel == 1)
                      ? const Icon(Icons.check_rounded, color: Color(0xFF16A34A))
                      : null,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 0,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.gpp_bad_rounded, color: Colors.grey),
                  title: const Text('⚪ Off (Disabled)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                  subtitle: const Text('Disable anti-spoofing; all detected faces allowed',
                      style: TextStyle(fontSize: 11)),
                  trailing: (!_isAntiSpoofingEnabled || _spoofSensitivityLevel == 0)
                      ? const Icon(Icons.check_rounded, color: Colors.grey)
                      : null,
                ),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isAntiSpoofingEnabled ? Icons.security_rounded : Icons.gpp_bad_rounded,
                  size: 14,
                  color: textColor,
                ),
                const SizedBox(width: 4),
                Text(
                  levelLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down_rounded, size: 16, color: textColor),
              ],
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _toggleAntiSpoofing(!_isAntiSpoofingEnabled),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _isAntiSpoofingEnabled ? const Color(0xFFE11D48) : const Color(0xFF0F766E),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _isAntiSpoofingEnabled ? 'Disable' : 'Enable',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// People / Crowd Counter Pill with live stats, on/off toggle & reset button
  Widget _buildPeopleCounterPill() {
    if (!_isPeopleCountingEnabled) {
      return Container(
        height: _kTopItemHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_off_rounded, size: 16, color: Color(0xFFB45309)),
            const SizedBox(width: 5),
            const Text(
              '👥 Count: OFF',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFFB45309),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _togglePeopleCounting(true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white),
                    SizedBox(width: 2),
                    Text('Enable', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ValueListenableBuilder<({int liveCount, int totalCount})>(
      valueListenable: _peopleCountNotifier,
      builder: (context, counts, _) {
        return Container(
          height: _kTopItemHeight,
          padding: const EdgeInsets.only(left: 8, right: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_rounded, size: 16, color: Color(0xFF0F766E)),
              const SizedBox(width: 5),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A)),
                  children: [
                    const TextSpan(text: 'In View: '),
                    TextSpan(
                      text: '${counts.liveCount}',
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w900, color: Color(0xFF0F766E), fontSize: 12),
                    ),
                    const TextSpan(text: ' | Total: '),
                    TextSpan(
                      text: '${counts.totalCount}',
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w900, color: Color(0xFF2563EB), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 15, color: Color(0xFF64748B)),
                tooltip: 'Reset Headcount',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  _engine.resetPeopleCount();
                  _multiCamLiveCountByCamera.clear();
                  _peopleCountNotifier.value = (liveCount: 0, totalCount: 0);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Headcount reset to 0.'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.power_settings_new_rounded, size: 15, color: Color(0xFFE11D48)),
                tooltip: 'Disable Headcount',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () => _togglePeopleCounting(false),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(color: textColor.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.w700),
        ),
        Text(
          value,
          style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }


  Widget _buildCctvViewportCard() {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: _isMultiCamMode
            ? _buildMultiCamSecurityGrid()
            : Stack(
                fit: StackFit.expand,
                children: [
            // 1. Live Camera Stream Frame inside viewport
            Container(
              color: const Color(0xFF0A0E17),
              child: (_streamService.config.sourceType == CctvSourceType.webcam &&
                      !_streamService.isNativeOpenCvStreaming &&
                      _streamService.cameraController != null &&
                      _streamService.cameraController!.value.isInitialized)
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: _streamService.cameraController!.value.aspectRatio,
                        child: CameraPreview(_streamService.cameraController!),
                      ),
                    )
                  : ValueListenableBuilder<ui.Image?>(
                      valueListenable: _streamService.singleDisplayImageNotifier,
                      builder: (context, image, _) {
                        if (image != null) {
                          return RawImage(
                            image: image,
                            fit: BoxFit.contain,
                          );
                        }
                        return AnimatedBuilder(
                        animation: _streamService,
                        builder: (context, _) {
                          final isConnecting = _streamService.isConnecting;
                          final err = _streamService.lastError;
                          final hasError = err != null && err.isNotEmpty && !_streamService.isStreaming;

                          if (isConnecting) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(color: Color(0xFF10B981)),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Connecting to Camera Stream...',
                                    style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _streamService.config.sourceType == CctvSourceType.ipCamera
                                        ? 'Probing ${_streamService.config.ipUrl}...'
                                        : 'Initializing hardware camera...',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                            );
                          }

                          if (hasError) {
                            return Center(
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 480),
                                margin: const EdgeInsets.all(24),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E2D).withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.videocam_off_rounded, color: Colors.amber, size: 32),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Camera Feed Offline',
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      err,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                                    ),
                                    const SizedBox(height: 18),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        FilledButton.icon(
                                          icon: const Icon(Icons.refresh_rounded, size: 16),
                                          label: const Text('Retry Connection', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF10B981),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          ),
                                          onPressed: () {
                                            _streamService.startStream(_streamService.config);
                                          },
                                        ),
                                        FilledButton.tonalIcon(
                                          icon: const Icon(Icons.videocam_rounded, size: 14),
                                          label: const Text('Start Webcam', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF0F766E),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          ),
                                          onPressed: _switchToWebcam,
                                        ),
                                        FilledButton.tonalIcon(
                                          icon: const Icon(Icons.play_circle_fill_rounded, size: 14),
                                          label: const Text('Demo Simulation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF2E384D),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          ),
                                          onPressed: _switchToSimulation,
                                        ),
                                        OutlinedButton.icon(
                                          icon: const Icon(Icons.settings_rounded, size: 14, color: Colors.white70),
                                          label: const Text('CCTV Setup', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Colors.white24),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          ),
                                          onPressed: _showLightSettingsDialog,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: Color(0xFF10B981)),
                                const SizedBox(height: 16),
                                const Text(
                                  'Connecting to Camera Stream...',
                                  style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Waiting for camera stream connection...',
                                  style: TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    FilledButton.tonalIcon(
                                      icon: const Icon(Icons.videocam_rounded, size: 14),
                                      label: const Text('Start Webcam', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF0F766E),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: _switchToWebcam,
                                    ),
                                    FilledButton.tonalIcon(
                                      icon: const Icon(Icons.play_circle_fill_rounded, size: 14),
                                      label: const Text('Demo Simulation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF1E293B),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: _switchToSimulation,
                                    ),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.settings_rounded, size: 14, color: Colors.white70),
                                      label: const Text('CCTV Setup', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Colors.white24),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      ),
                                      onPressed: _showLightSettingsDialog,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
            ),

            // 2. High-Tech Viewfinder HUD Overlay (Neon Green & White Badges)
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<List<CctvTrackedFace>>(
                  valueListenable: _trackedFacesNotifier,
                  builder: (context, faces, _) {
                    return CustomPaint(
                      painter: _CctvHudPainter(
                        trackedFaces: faces,
                        isStreaming: _streamService.isStreaming,
                      ),
                    );
                  },
                ),
              ),
            ),

            // 3. Multi-Camera Switcher Badge (Top-Left)
            Positioned(
              left: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _streamService.activeCameraName,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<CctvCameraProfile>(
                      tooltip: 'Switch Camera',
                      icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      itemBuilder: (context) => _streamService.cameraProfiles.map((cam) => PopupMenuItem(
                        value: cam,
                        child: Row(
                          children: [
                            Icon(
                              cam.sourceType == CctvSourceType.webcam ? Icons.camera_alt_rounded : Icons.videocam_rounded,
                              size: 16,
                              color: cam.id == _streamService.activeProfileId ? const Color(0xFF0F766E) : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              cam.name,
                              style: TextStyle(
                                fontWeight: cam.id == _streamService.activeProfileId ? FontWeight.bold : FontWeight.normal,
                                color: cam.id == _streamService.activeProfileId ? const Color(0xFF0F766E) : const Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                      onSelected: (cam) => _switchCamera(cam),
                    ),
                  ],
                ),
              ),
            ),

            // 3.5. Informative Schedule Banner (When Outside Active Attendance Schedule or Manually Paused)
            ValueListenableBuilder<bool>(
              valueListenable: _attendanceActiveNotifier,
              builder: (context, isActive, _) {
                if (isActive) return const SizedBox.shrink();
                final String title;
                final String subtitle;
                if (_masterMode == AttendanceMasterMode.manualOff) {
                  title = 'Attendance OFF (Manual)';
                  subtitle = 'Attendance recording is turned off; camera & face recognition are running';
                } else {
                  title = 'Attendance Paused (Outside Schedule)';
                  subtitle = _currentScheduleState?.statusSubtitle ?? 'Outside scheduled attendance hours';
                }

                return Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade400.withValues(alpha: 0.7), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.amber.shade200,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Demo Simulation Controls (Only when in Demo Simulation mode)
            if (_streamService.config.sourceType == CctvSourceType.simulation)
              Positioned(
                left: 20,
                bottom: 80,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.science_rounded, size: 13, color: Color(0xFF0F766E)),
                            SizedBox(width: 4),
                            Text(
                              'DEMO MODE',
                              style: TextStyle(color: Color(0xFF0F766E), fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, size: 18, color: Color(0xFF0F766E)),
                        tooltip: 'Previous Enrolled Student',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () {
                          _streamService.previousSimulationScene();
                          setState(() {});
                        },
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _streamService.currentSimulationSceneName,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, size: 18, color: Color(0xFF0F766E)),
                        tooltip: 'Next Enrolled Student',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () {
                          _streamService.nextSimulationScene();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),

            // 4. Clean Light Bottom Floating Control Pill (Responsive & 100% Overflow-Free)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Pause / Resume Button (32px)
                        SizedBox(
                          height: 32,
                          width: 32,
                          child: IconButton(
                            icon: Icon(
                              _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                              color: _isPaused ? const Color(0xFF10B981) : Colors.amber.shade800,
                              size: 19,
                            ),
                            tooltip: _isPaused ? 'Resume Video Stream' : 'Pause Video Stream',
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              setState(() => _isPaused = !_isPaused);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Mode Selector Dropdown (32px)
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _engine.currentMode,
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Color(0xFF64748B)),
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11.5, fontWeight: FontWeight.bold),
                              items: const [
                                DropdownMenuItem(value: 'auto', child: Text('Auto (IN/OUT)')),
                                DropdownMenuItem(value: 'in', child: Text('Force IN')),
                                DropdownMenuItem(value: 'out', child: Text('Force OUT')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _engine.currentMode = val);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Voice Toggle Button (32px)
                        SizedBox(
                          height: 32,
                          width: 32,
                          child: IconButton(
                            icon: Icon(
                              _engine.enableAudioVoice ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                              color: _engine.enableAudioVoice ? const Color(0xFF0F766E) : Colors.grey,
                              size: 18,
                            ),
                            tooltip: 'Toggle Voice Announcement',
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              setState(() => _engine.enableAudioVoice = !_engine.enableAudioVoice);
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(height: 18, width: 1, color: Colors.grey.shade300),
                        const SizedBox(width: 6),

                        // Sensitivity Selector Dropdown (32px)
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<FaceDetectionSensitivity>(
                              value: _engine.detectionSensitivity,
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Color(0xFF64748B)),
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11.5, fontWeight: FontWeight.bold),
                              items: const [
                                DropdownMenuItem(
                                  value: FaceDetectionSensitivity.sensitive,
                                  child: Text('🎯 Sensitive'),
                                ),
                                DropdownMenuItem(
                                  value: FaceDetectionSensitivity.balanced,
                                  child: Text('🎯 Balanced'),
                                ),
                                DropdownMenuItem(
                                  value: FaceDetectionSensitivity.strict,
                                  child: Text('🎯 Strict'),
                                ),
                              ],
                              onChanged: (val) async {
                                if (val != null) {
                                  setState(() => _engine.detectionSensitivity = val);
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setString('cctv_sensitivity', val.name);
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(height: 18, width: 1, color: Colors.grey.shade300),
                        const SizedBox(width: 6),

                        // Anti-Spoofing Sensitivity Level Dropdown (32px)
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _isAntiSpoofingEnabled ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _isAntiSpoofingEnabled ? const Color(0xFF86EFAC) : const Color(0xFFFECDD3),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _isAntiSpoofingEnabled ? _spoofSensitivityLevel : 0,
                              dropdownColor: Colors.white,
                              icon: Icon(Icons.arrow_drop_down_rounded,
                                  size: 16,
                                  color: _isAntiSpoofingEnabled ? const Color(0xFF15803D) : const Color(0xFFE11D48)),
                              style: TextStyle(
                                color: _isAntiSpoofingEnabled ? const Color(0xFF15803D) : const Color(0xFFE11D48),
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                              items: const [
                                DropdownMenuItem(value: 3, child: Text('🛡️ Spoof: High (70%)')),
                                DropdownMenuItem(value: 2, child: Text('🛡️ Spoof: Med (55%)')),
                                DropdownMenuItem(value: 1, child: Text('🛡️ Spoof: Low (40%)')),
                                DropdownMenuItem(value: 0, child: Text('🛡️ Spoof: Off')),
                              ],
                              onChanged: (val) {
                                if (val != null) _setSpoofSensitivityLevel(val);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(height: 18, width: 1, color: Colors.grey.shade300),
                        const SizedBox(width: 4),

                        // Target Filter Toggle (32px)
                        SizedBox(
                          height: 32,
                          width: 32,
                          child: IconButton(
                            icon: Icon(
                              _engine.detectAllHumans ? Icons.groups_rounded : Icons.person_search_rounded,
                              color: _engine.detectAllHumans ? const Color(0xFF0284C7) : Colors.grey.shade600,
                              size: 18,
                            ),
                            tooltip: _engine.detectAllHumans
                                ? 'Target: All Humans & Visitors (Click for Students Only)'
                                : 'Target: Registered Students Only (Click for All Humans)',
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              setState(() => _engine.detectAllHumans = !_engine.detectAllHumans);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('cctv_detect_all_humans', _engine.detectAllHumans);
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(height: 18, width: 1, color: Colors.grey.shade300),
                        const SizedBox(width: 6),

                        // Dynamic FPS Selector Dropdown (32px)
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: [5, 8, 10, 12, 15, 25, 30, 60].contains(_streamService.config.targetFps)
                                  ? _streamService.config.targetFps
                                  : 15,
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Color(0xFF64748B)),
                              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11.5, fontWeight: FontWeight.bold),
                              items: const [
                                DropdownMenuItem(value: 5, child: Text('⚡ 5 FPS')),
                                DropdownMenuItem(value: 8, child: Text('⚡ 8 FPS')),
                                DropdownMenuItem(value: 12, child: Text('⚡ 12 FPS')),
                                DropdownMenuItem(value: 15, child: Text('⚡ 15 FPS')),
                                DropdownMenuItem(value: 25, child: Text('⚡ 25 FPS')),
                                DropdownMenuItem(value: 30, child: Text('⚡ 30 FPS')),
                                DropdownMenuItem(value: 60, child: Text('⚡ 60 FPS')),
                              ],
                              onChanged: (newFps) async {
                                if (newFps != null) {
                                  _streamService.updateFps(newFps);
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setInt('cctv_target_fps', newFps);
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleMultiCamMode() async {
    setState(() {
      _isMultiCamMode = !_isMultiCamMode;
    });

    _latestFramesByCamera.clear();
    _lastAiInferenceByCamera.clear();
    _multiCamLiveCountByCamera.clear();
    _engine.clearActiveTracks();

    if (_isMultiCamMode) {
      await _streamService.stopStream();
      await _streamService.startMultiCameraStreams(_streamService.cameraProfiles);
    } else {
      await _streamService.stopMultiCameraStreams();
      final activeProf = _streamService.cameraProfiles.firstWhere(
        (p) => p.id == _streamService.activeProfileId,
        orElse: () => _streamService.cameraProfiles.first,
      );
      await _streamService.startStream(activeProf.toConfig(targetFps: _streamService.config.targetFps));
    }
    if (mounted) setState(() {});
  }

  Widget _buildMultiCamSecurityGrid() {
    final channels = _streamService.activeChannels;
    if (channels.isEmpty) {
      return Container(
        color: const Color(0xFF0A0E17),
        child: const Center(
          child: Text(
            'Multi-Cam Security Grid Starting...\nAll configured cameras will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    // Dynamic, responsive grid layout: adapts cleanly for 1 up to 10+ cameras
    final int crossAxisCount = switch (channels.length) {
      1 => 1,
      2 => 2,
      3 || 4 => 2,
      5 || 6 => 3,
      7 || 8 || 9 => 3,
      _ => 4,
    };

    return Container(
      color: const Color(0xFF0B1120),
      child: Column(
        children: [
          // Security Grid Multiplexer Top Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: Row(
              children: [
                const Icon(Icons.grid_view_rounded, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text(
                  'Multi-Cam Security Grid (${channels.length} Tiles Active)',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    '⚡ Stream Multiplexer Active: Run any camera across multiple grid tiles simultaneously!',
                    style: TextStyle(color: Color(0xFF5EEAD4), fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E).withValues(alpha: 0.25),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF5EEAD4)),
                  label: const Text('⚡ Apply Cam to All Tiles', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF5EEAD4))),
                  onPressed: () async {
                    final activeProf = _streamService.activeProfile ?? _streamService.cameraProfiles.first;
                    await _streamService.applySourceToAllProfiles(activeProf.id);
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF0F766E),
                          content: Text('✅ "${activeProf.name}" applied to all grid tiles!'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.add_to_photos_rounded, size: 14),
                  label: const Text('+ Clone / Add Grid Tile', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final activeProf = _streamService.activeProfile ?? _streamService.cameraProfiles.first;
                    await _streamService.duplicateCameraProfile(activeProf.id);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),

          // The Grid of Camera Tiles
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 16 / 9,
                ),
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return _buildSingleChannelTile(channel, index + 1);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleChannelTile(CctvCameraChannel channel, int channelNumber) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.5), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Ultra-Low CPU Pre-Decoded GPU Texture Renderer (Zero CPU JPEG decoding in Widget!)
          ValueListenableBuilder<ui.Image?>(
            valueListenable: channel.displayImageNotifier,
            builder: (context, image, _) {
              if (image != null) {
                return RawImage(
                  image: image,
                  fit: BoxFit.contain,
                );
              }
              return ValueListenableBuilder<bool>(
                valueListenable: channel.isOnlineNotifier,
                builder: (context, isOnline, _) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOnline ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                          color: isOnline ? const Color(0xFF10B981) : Colors.white30,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isOnline ? 'Connecting Stream...' : 'Feed Offline / Standby',
                          style: TextStyle(
                            color: isOnline ? const Color(0xFF10B981) : Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          channel.profile.sourceType == CctvSourceType.webcam
                              ? 'Webcam #${channel.profile.cameraIndex}'
                              : channel.profile.ipUrl,
                          style: const TextStyle(color: Colors.white24, fontSize: 9.5, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),

          // 2. HUD Overlay for this specific camera
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<List<CctvTrackedFace>>(
                valueListenable: channel.trackedFacesNotifier,
                builder: (context, faces, _) {
                  return CustomPaint(
                    painter: _CctvHudPainter(
                      trackedFaces: faces,
                      isStreaming: channel.isStreaming,
                    ),
                  );
                },
              ),
            ),
          ),

          // 3. Channel Label (Top-Left) with Camera Switcher / Multiplexer Dropdown
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  popupMenuTheme: PopupMenuThemeData(
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                child: PopupMenuButton<String>(
                  tooltip: 'Click to select which camera to show in Grid $channelNumber',
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  offset: const Offset(0, 32),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: channel.isOnlineNotifier,
                        builder: (context, isOnline, _) {
                          return Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'CAM $channelNumber: ${channel.profile.name}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 16),
                    ],
                  ),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem<String>(
                      enabled: false,
                      height: 28,
                      child: Text(
                        'ASSIGN CAMERA FEED TO THIS TILE:',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                      ),
                    ),
                    const PopupMenuDivider(height: 6),
                    ..._streamService.cameraProfiles.map((prof) {
                      final isSelected = prof.ipUrl == channel.profile.ipUrl && prof.sourceType == channel.profile.sourceType;
                      return PopupMenuItem<String>(
                        value: 'assign_${prof.id}',
                        height: 36,
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check_circle_rounded : Icons.videocam_outlined,
                              size: 16,
                              color: isSelected ? const Color(0xFF10B981) : Colors.white70,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                prof.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.white : Colors.white70,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              prof.sourceType == CctvSourceType.webcam ? 'Webcam' : prof.ipUrl,
                              style: const TextStyle(fontSize: 9, color: Colors.white38, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      );
                    }),
                    const PopupMenuDivider(height: 6),
                    const PopupMenuItem<String>(
                      value: 'duplicate_tile',
                      height: 36,
                      child: Row(
                        children: [
                          Icon(Icons.add_to_photos_rounded, size: 16, color: Color(0xFF38BDF8)),
                          SizedBox(width: 8),
                          Text(
                            '+ Clone / Duplicate into New Grid Tile',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (action) async {
                    if (action == 'duplicate_tile') {
                      await _streamService.duplicateCameraProfile(channel.profile.id);
                      if (mounted) setState(() {});
                    } else if (action.startsWith('assign_')) {
                      final profId = action.substring('assign_'.length);
                      final selected = _streamService.cameraProfiles.where((p) => p.id == profId).firstOrNull;
                      if (selected != null) {
                        await _streamService.assignCameraToChannel(channel.profile.id, selected);
                        if (mounted) setState(() {});
                      }
                    }
                  },
                ),
              ),
            ),
          ),

          // 4. Live FPS Badge (Top-Right)
          Positioned(
            right: 8,
            top: 8,
            child: ValueListenableBuilder<bool>(
              valueListenable: channel.isOnlineNotifier,
              builder: (context, isOnline, _) {
                final displayFps = isOnline ? _streamService.config.targetFps : 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isOnline ? '⚡ $displayFps FPS' : '⚪ Standby',
                    style: TextStyle(
                      color: isOnline ? const Color(0xFF38BDF8) : Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Class Filter Card placed at the top of the right sidebar (User Request)
  Widget _buildClassFilterCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: const Icon(Icons.school_rounded, size: 16, color: Color(0xFF0F766E)),
          ),
          const SizedBox(width: 10),
          const Text(
            'Class:',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedClassFilter,
                  isExpanded: true,
                  menuMaxHeight: 350,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF0F766E)),
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
                  selectedItemBuilder: (context) => _classList.map((c) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        c == 'ALL' ? '🏢 All Classes (All Students)' : 'Class: $c',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  items: _classList.map((c) => DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [
                        const Icon(Icons.school_rounded, size: 14, color: Color(0xFF0F766E)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c == 'ALL' ? '🏢 All Classes (All Students)' : 'Class: $c',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) _changeClassFilter(val);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveActivityFeedCard() {
    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: _feedUpdateNotifier,
        builder: (context, count, child) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Feed Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Live Activity Feed',
                        style: AppTheme.getFontStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '(Live Log)',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          '${_eventsFeed.length} Scanned',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

                // Feed List
                Expanded(
                  child: _eventsFeed.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.face_retouching_natural_rounded,
                                    size: 54, color: Colors.grey.shade300),
                                const SizedBox(height: 14),
                                const Text(
                                  'No Attendees Recorded Yet',
                                  style: TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Recognized faces and attendance records will appear here as attendees are scanned.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _eventsFeed.length,
                          padding: const EdgeInsets.all(12),
                          itemBuilder: (context, index) {
                            final event = _eventsFeed[index];
                            final photoProvider = _getStudentPhotoProvider(event.photoPath);
                            final isInfo = event.status.toLowerCase().contains('info');
                            final isLate = event.status == 'Late';
                            final isOut = event.status == 'Out';

                            final statusTextColor = isInfo
                                ? const Color(0xFFD97706)
                                : isOut
                                    ? const Color(0xFF0369A1)
                                    : isLate
                                        ? const Color(0xFFB45309)
                                        : const Color(0xFF15803D);

                            final statusBgColor = isInfo
                                ? const Color(0xFFFFFBEB)
                                : isOut
                                    ? const Color(0xFFF0F9FF)
                                    : isLate
                                        ? const Color(0xFFFFFBEB)
                                        : const Color(0xFFF0FDF4);

                            final statusBorderColor = isInfo
                                ? const Color(0xFFFCD34D)
                                : isOut
                                    ? const Color(0xFFBAE6FD)
                                    : isLate
                                        ? const Color(0xFFFDE68A)
                                        : const Color(0xFFBBF7D0);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Student Avatar
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    backgroundImage: photoProvider,
                                    child: photoProvider == null
                                        ? Text(
                                            event.studentName.isNotEmpty ? event.studentName[0].toUpperCase() : '?',
                                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F766E), fontSize: 16),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),

                                  // Student Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          event.studentName,
                                          style: const TextStyle(
                                            color: Color(0xFF0F172A),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 2,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              'GR: ${event.grNo.isNotEmpty ? event.grNo : "N/A"}',
                                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                            Container(width: 3, height: 3, decoration: const BoxDecoration(color: Color(0xFFCBD5E1), shape: BoxShape.circle)),
                                            Text(
                                              DateFormat('hh:mm:ss a').format(event.timestamp),
                                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w500),
                                            ),
                                            Container(width: 3, height: 3, decoration: const BoxDecoration(color: Color(0xFFCBD5E1), shape: BoxShape.circle)),
                                            Text(
                                              '(${event.matchConfidence.toStringAsFixed(0)}% Match)',
                                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Status Pill Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusBgColor,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: statusBorderColor),
                                    ),
                                    child: Text(
                                      isInfo ? 'INFO (OFF)' : event.status.toUpperCase(),
                                      style: TextStyle(
                                        color: statusTextColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LIGHT CCTV CAMERA SETUP WIZARD & CONFIGURATION DIALOG
  // ═══════════════════════════════════════════════════════════════════════
  void _showLightSettingsDialog() {
    final config = _streamService.config;
    String initialIp = config.ipUrl;
    if (initialIp.contains('/ISAPI/') || initialIp.contains('/cgi-bin/')) {
      final parsed = CctvStreamService.parseHostAndPort(initialIp);
      if (parsed.host.isNotEmpty) initialIp = parsed.host;
    }
    final ipUrlCtrl = TextEditingController(text: initialIp);
    final userCtrl = TextEditingController(text: config.username.isNotEmpty ? config.username : 'admin');
    final passCtrl = TextEditingController(text: config.password);

    String? testResultMsg;
    bool? testSuccess;
    bool isTesting = false;
    int activeTab = 0; // 0: Single Camera & AI, 1: Multi-Camera Manager

    List<DiscoveredCamera> discoveredCameras = [];
    bool isScanningNetwork = false;
    String? scanStatusMsg;
    Uint8List? liveSampleFrameBytes;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final currentCfg = _streamService.config;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.settings_rounded, color: Color(0xFF0F766E), size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CCTV Camera Setup & AI Configuration',
                        style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Camera connections, multi-camera grid & AI settings',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: math.min(680.0, MediaQuery.of(ctx).size.width - 32),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Two-Tab Segmented Switcher Header
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setDlgState(() => activeTab = 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: activeTab == 0 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: activeTab == 0
                                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.tune_rounded, size: 16, color: activeTab == 0 ? const Color(0xFF0F766E) : Colors.grey),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Camera & AI Settings',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: activeTab == 0 ? FontWeight.bold : FontWeight.normal,
                                        color: activeTab == 0 ? const Color(0xFF0F766E) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => setDlgState(() => activeTab = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: activeTab == 1 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: activeTab == 1
                                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.grid_view_rounded, size: 16, color: activeTab == 1 ? const Color(0xFF0F766E) : Colors.grey),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Multi-Cam Channels (${_streamService.cameraProfiles.length})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: activeTab == 1 ? FontWeight.bold : FontWeight.normal,
                                        color: activeTab == 1 ? const Color(0xFF0F766E) : const Color(0xFF64748B),
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
                    const SizedBox(height: 16),

                    if (activeTab == 0) ...[
                      // Camera Source Segmented Buttons
                      const Text('Camera Source:',
                          style: TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SegmentedButton<CctvSourceType>(
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: const Color(0xFF0F766E),
                          selectedForegroundColor: Colors.white,
                        ),
                        segments: const [
                          ButtonSegment(value: CctvSourceType.webcam, label: Text('USB Webcam')),
                          ButtonSegment(value: CctvSourceType.ipCamera, label: Text('IP / CCTV Camera')),
                          ButtonSegment(value: CctvSourceType.simulation, label: Text('Demo Simulation')),
                        ],
                        selected: {currentCfg.sourceType},
                        onSelectionChanged: (set) async {
                          final newSource = set.first;
                          final enrolledSimulationImages = _allStudentsPool
                              .where((s) => s.hasFaceEnrolled && s.photoPath != null && s.photoPath!.isNotEmpty)
                              .map((s) => s.photoPath!)
                              .where((p) => File(p).existsSync())
                              .toSet()
                              .toList();
                          final newCfg = currentCfg.copyWith(
                            sourceType: newSource,
                            simulationImages: enrolledSimulationImages,
                          );
                          await _streamService.startStream(newCfg);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('cctv_source_type', newSource.name);
                          setDlgState(() {
                            testResultMsg = null;
                            testSuccess = null;
                          });
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),

                      // 🌐 UNIVERSAL IP CAMERA & WI-FI AUTO-DISCOVERY (Hik-Partner Pro style)
                      if (currentCfg.sourceType == CctvSourceType.ipCamera) ...[
                        // 1. Auto-Discovery Bar (Search Wi-Fi / LAN Cameras like Hik-Partner Pro)
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.wifi_tethering_rounded, color: Color(0xFF16A34A), size: 18),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Wi-Fi / Local Network Camera Discovery',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF15803D)),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: isScanningNetwork
                                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Icon(Icons.radar_rounded, size: 14),
                                    label: Text(isScanningNetwork ? 'Scanning...' : 'Scan Cameras', style: const TextStyle(fontSize: 11)),
                                    onPressed: isScanningNetwork
                                        ? null
                                        : () async {
                                            setDlgState(() {
                                              isScanningNetwork = true;
                                              scanStatusMsg = 'Searching Wi-Fi & LAN (Hikvision SADP, ONVIF, Subnet sweep)...';
                                            });
                                            final found = await CctvDiscoveryService.discoverNetworkCameras();
                                            setDlgState(() {
                                              isScanningNetwork = false;
                                              discoveredCameras = found;
                                              if (found.isEmpty) {
                                                scanStatusMsg = 'No IP cameras responded to auto-discovery. You can enter the camera IP address manually below.';
                                              } else {
                                                scanStatusMsg = 'Found ${found.length} camera(s) online! Click a camera to select:';
                                              }
                                            });
                                          },
                                  ),
                                ],
                              ),
                              if (scanStatusMsg != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  scanStatusMsg!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: discoveredCameras.isEmpty ? const Color(0xFFB45309) : const Color(0xFF15803D),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              if (discoveredCameras.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  constraints: const BoxConstraints(maxHeight: 140),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: discoveredCameras.length,
                                    separatorBuilder: (_, index) => const Divider(height: 1),
                                    itemBuilder: (ctx, idx) {
                                      final cam = discoveredCameras[idx];
                                      return ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                        leading: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Icon(Icons.videocam_rounded, color: Color(0xFF16A34A), size: 18),
                                        ),
                                        title: Text(
                                          cam.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                        subtitle: Text(
                                          'IP: ${cam.ip} • Port: ${cam.port} • Protocol: ${cam.discoveryMethod}',
                                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                        ),
                                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF16A34A)),
                                        onTap: () {
                                          ipUrlCtrl.text = cam.ip;
                                          if (userCtrl.text.isEmpty) userCtrl.text = 'admin';
                                          setDlgState(() {});
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Brand Quick-Select Chips (Zero technical URLs injected!)
                        const Text('Camera Brand Helper / Preset:',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ActionChip(
                              avatar: const Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFF0F766E)),
                              label: const Text('✨ Auto-Detect IP / Port', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                final input = ipUrlCtrl.text.trim();
                                if (input.isNotEmpty) {
                                  setDlgState(() {
                                    testResultMsg = 'Probing $input for active camera ports...';
                                    testSuccess = null;
                                  });
                                  final res = await CctvDiscoveryService.probeSingleIp(input);
                                  if (res != null) {
                                    ipUrlCtrl.text = res.suggestedStreamUrl ?? (res.port != 80 && res.port != 554 ? '${res.ip}:${res.port}' : res.ip);
                                    setDlgState(() {
                                      testResultMsg = 'Auto-detected ${res.brand} on port ${res.port}! ✅';
                                      testSuccess = true;
                                    });
                                  } else {
                                    setDlgState(() {
                                      testResultMsg = 'Device at $input did not respond on common camera ports.';
                                      testSuccess = false;
                                    });
                                  }
                                } else {
                                  setDlgState(() {
                                    isScanningNetwork = true;
                                    scanStatusMsg = 'Searching Wi-Fi & LAN for online cameras...';
                                  });
                                  final found = await CctvDiscoveryService.discoverNetworkCameras();
                                  setDlgState(() {
                                    isScanningNetwork = false;
                                    discoveredCameras = found;
                                    if (found.isNotEmpty) {
                                      ipUrlCtrl.text = found.first.ip + (found.first.port != 80 && found.first.port != 554 ? ':${found.first.port}' : '');
                                      scanStatusMsg = 'Auto-detected ${found.first.brand} (${found.first.ip})! ✅';
                                    } else {
                                      scanStatusMsg = 'No online cameras responded. Please enter camera IP manually below.';
                                    }
                                  });
                                }
                              },
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.phone_android_rounded, size: 14, color: Color(0xFF7C3AED)),
                              label: const Text('📱 Mobile IP Webcam', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                final cur = ipUrlCtrl.text.trim();
                                if (cur.isNotEmpty) {
                                  final host = cur.replaceAll(RegExp(r'^https?://'), '').split('/')[0].split(':')[0];
                                  ipUrlCtrl.text = '$host:8080';
                                } else {
                                  ipUrlCtrl.text = '192.168.1.50:8080';
                                }
                                setDlgState(() {});
                              },
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.videocam_rounded, size: 14, color: Color(0xFFDC2626)),
                              label: const Text('📹 Hikvision', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                final cur = ipUrlCtrl.text.trim();
                                if (cur.isNotEmpty) {
                                  final host = cur.replaceAll(RegExp(r'^https?://'), '').split('/')[0].split(':')[0];
                                  ipUrlCtrl.text = host;
                                } else {
                                  ipUrlCtrl.text = '192.168.1.64';
                                }
                                setDlgState(() {});
                              },
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFF2563EB)),
                              label: const Text('🎥 CP Plus / Dahua', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                final cur = ipUrlCtrl.text.trim();
                                if (cur.isNotEmpty) {
                                  final host = cur.replaceAll(RegExp(r'^https?://'), '').split('/')[0].split(':')[0];
                                  ipUrlCtrl.text = host;
                                } else {
                                  ipUrlCtrl.text = '192.168.1.250';
                                }
                                setDlgState(() {});
                              },
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.wifi_rounded, size: 14, color: Color(0xFF0D9488)),
                              label: const Text('📡 TP-Link Tapo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                final cur = ipUrlCtrl.text.trim();
                                if (cur.isNotEmpty) {
                                  final host = cur.replaceAll(RegExp(r'^https?://'), '').split('/')[0].split(':')[0];
                                  ipUrlCtrl.text = host;
                                } else {
                                  ipUrlCtrl.text = '192.168.1.100';
                                }
                                setDlgState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Clean Camera IP Input
                        const Text('Camera IP Address (Wi-Fi or LAN):',
                            style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: ipUrlCtrl,
                          decoration: InputDecoration(
                            hintText: 'e.g. 192.168.1.64 or 192.168.1.50:8080',
                            helperText: 'Enter camera IP address — Direct Wi-Fi/LAN connection without complex NVR setup!',
                            helperStyle: const TextStyle(fontSize: 10, color: Color(0xFF0F766E), fontWeight: FontWeight.w600),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Credentials (Username & Password)
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Username (Optional):', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: userCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'admin',
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Password (Optional):', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: passCtrl,
                                    obscureText: true,
                                    decoration: InputDecoration(
                                      hintText: '••••••',
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Live Camera Test Button
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              icon: isTesting
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.wifi_find_rounded, size: 16),
                              label: Text(isTesting ? 'Auto-Negotiating Camera Stream...' : 'Test Camera Connection'),
                              onPressed: isTesting
                                  ? null
                                  : () async {
                                      setDlgState(() {
                                        isTesting = true;
                                        testResultMsg = null;
                                        testSuccess = null;
                                        liveSampleFrameBytes = null;
                                      });
                                      final testCfg = currentCfg.copyWith(
                                        ipUrl: ipUrlCtrl.text.trim(),
                                        username: userCtrl.text.trim(),
                                        password: passCtrl.text.trim(),
                                      );
                                      final res = await _streamService.testCameraConnection(testCfg);
                                      setDlgState(() {
                                        isTesting = false;
                                        testSuccess = res['success'] == true;
                                        testResultMsg = res['message']?.toString();
                                        if (res['bytes'] is Uint8List) {
                                          liveSampleFrameBytes = res['bytes'] as Uint8List;
                                        }
                                      });
                                    },
                            ),
                          ],
                        ),
                        if (testResultMsg != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: testSuccess == true ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: testSuccess == true ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
                            ),
                            child: Row(
                              children: [
                                if (testSuccess == true && liveSampleFrameBytes != null) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.memory(
                                      liveSampleFrameBytes!,
                                      width: 64,
                                      height: 48,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    testResultMsg!,
                                    style: TextStyle(
                                      color: testSuccess == true ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                      ],

                      if (currentCfg.sourceType == CctvSourceType.webcam) ...[
                        const Text('Select Connected USB Camera:',
                            style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<int>(
                          initialValue: currentCfg.cameraIndex < _streamService.availableCamerasList.length
                              ? currentCfg.cameraIndex
                              : 0,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: List.generate(_streamService.availableCamerasList.length, (idx) {
                            final cam = _streamService.availableCamerasList[idx];
                            return DropdownMenuItem<int>(
                              value: idx,
                              child: Text(cam.name.isNotEmpty ? cam.name : 'Webcam #$idx'),
                            );
                          }),
                          onChanged: (val) {
                            if (val != null) {
                              _streamService.startStream(currentCfg.copyWith(cameraIndex: val));
                              setDlgState(() {});
                              setState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                      ],

                      const Divider(),
                      const SizedBox(height: 8),

                      // AI Match Threshold Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Recognition Threshold:',
                              style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
                          Text('${_engine.matchThreshold.toStringAsFixed(0)}%',
                              style: const TextStyle(color: Color(0xFF0F766E), fontWeight: FontWeight.w900, fontSize: 13)),
                        ],
                      ),
                      Slider(
                        value: _engine.matchThreshold,
                        min: 50.0,
                        max: 90.0,
                        divisions: 40,
                        activeColor: const Color(0xFF0F766E),
                        onChanged: (val) {
                          setDlgState(() => _engine.matchThreshold = val);
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 6),

                      // Anti-Duplication Cooldown Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Anti-Duplication Cooldown:',
                              style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
                          Text('${_engine.cooldownDuration.inMinutes} Minutes',
                              style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.w900, fontSize: 13)),
                        ],
                      ),
                      Slider(
                        value: _engine.cooldownDuration.inMinutes.toDouble(),
                        min: 1.0,
                        max: 15.0,
                        divisions: 14,
                        activeColor: const Color(0xFF0284C7),
                        onChanged: (val) {
                          setDlgState(() => _engine.cooldownDuration = Duration(minutes: val.toInt()));
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),

                      // AI Human & Face Detection Sensitivity
                      const Text(
                        'Detection Sensitivity:',
                        style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSensitivityOptionTile(
                              title: 'Sensitive (Indoor)',
                              subtitle: 'Room lighting and webcams. Fast face detection.',
                              value: FaceDetectionSensitivity.sensitive,
                              current: _engine.detectionSensitivity,
                              onSelect: () {
                                setDlgState(() => _engine.detectionSensitivity = FaceDetectionSensitivity.sensitive);
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSensitivityOptionTile(
                              title: 'Balanced (Standard)',
                              subtitle: 'Optimized for daylight and uniform lighting.',
                              value: FaceDetectionSensitivity.balanced,
                              current: _engine.detectionSensitivity,
                              onSelect: () {
                                setDlgState(() => _engine.detectionSensitivity = FaceDetectionSensitivity.balanced);
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSensitivityOptionTile(
                              title: 'Strict (High Precision)',
                              subtitle: 'High precision. Only clear direct faces match.',
                              value: FaceDetectionSensitivity.strict,
                              current: _engine.detectionSensitivity,
                              onSelect: () {
                                setDlgState(() => _engine.detectionSensitivity = FaceDetectionSensitivity.strict);
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Target Filter Toggle Switch
                      SwitchListTile(
                        title: const Text(
                          'Detect All Humans & Visitors',
                          style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'When disabled, only registered students are boxed on screen',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        value: _engine.detectAllHumans,
                        activeTrackColor: const Color(0xFF0F766E),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          setDlgState(() => _engine.detectAllHumans = val);
                          setState(() {});
                        },
                      ),

                      // Head Counting Toggle Switch
                      SwitchListTile(
                        title: const Text(
                          'Head & People Counting',
                          style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Live counting of people in view and total unique attendees',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        value: _isPeopleCountingEnabled,
                        activeTrackColor: const Color(0xFF0F766E),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          setDlgState(() {
                            _isPeopleCountingEnabled = val;
                            _engine.enablePeopleCounting = val;
                            if (!val) {
                              _peopleCountNotifier.value = (liveCount: 0, totalCount: 0);
                            }
                          });
                          setState(() {});
                        },
                      ),

                      // Anti-Spoofing Toggle Switch
                      SwitchListTile(
                        title: const Text(
                          'Anti-Spoofing Defense Shield',
                          style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Rejects fake faces presented via mobile screens, photos, or videos',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        value: _isAntiSpoofingEnabled,
                        activeTrackColor: const Color(0xFF0F766E),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          setDlgState(() {
                            _isAntiSpoofingEnabled = val;
                            _engine.enableAntiSpoofing = val;
                            if (val && _spoofSensitivityLevel == 0) {
                              _spoofSensitivityLevel = 2;
                              _engine.spoofSensitivityLevel = 2;
                            }
                          });
                          setState(() {});
                        },
                      ),

                      if (_isAntiSpoofingEnabled) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Anti-Spoofing Sensitivity Level:',
                          style: TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        SegmentedButton<int>(
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: const Color(0xFF0F766E),
                            selectedForegroundColor: Colors.white,
                          ),
                          segments: const [
                            ButtonSegment(
                              value: 1,
                              label: Text('Low (40%)'),
                              tooltip: 'Permissive: Obvious replays blocked; safe for IP cameras & low-light',
                            ),
                            ButtonSegment(
                              value: 2,
                              label: Text('Medium (55%)'),
                              tooltip: 'Balanced (Recommended): Dual AI MiniFASNet verification',
                            ),
                            ButtonSegment(
                              value: 3,
                              label: Text('High (70%)'),
                              tooltip: 'Strict: Maximum defense with Moiré + Chrominance checks',
                            ),
                          ],
                          selected: {_spoofSensitivityLevel.clamp(1, 3)},
                          onSelectionChanged: (set) {
                            final lvl = set.first;
                            _setSpoofSensitivityLevel(lvl);
                            setDlgState(() {});
                            setState(() {});
                          },
                        ),
                      ],
                    ] else ...[
                      // ═══════════════════════════════════════════════════════
                      // TAB 2: MULTI-CAMERA CHANNELS MANAGEMENT
                      // ═══════════════════════════════════════════════════════
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Configured Camera Profiles',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                    ),
                                    Text(
                                      'Each camera streams live and performs face recognition in the multi-camera grid',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F766E),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('+ Add Camera', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  _showAddEditCameraModal(ctx, setDlgState);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.bolt_rounded, size: 15, color: Color(0xFF0F766E)),
                                label: const Text('⚡ Apply to All Grids', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  final activeProf = _streamService.activeProfile ?? _streamService.cameraProfiles.first;
                                  await _streamService.applySourceToAllProfiles(activeProf.id);
                                  setDlgState(() {});
                                  setState(() {});
                                  messenger.showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF0F766E),
                                      content: Text('✅ "${activeProf.name}" applied to all ${_streamService.cameraProfiles.length} grid tiles!'),
                                    ),
                                  );
                                },
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.check_circle_outline_rounded, size: 15, color: Color(0xFF16A34A)),
                                label: const Text('🟢 Activate All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  await _streamService.enableAllProfiles();
                                  setDlgState(() {});
                                  setState(() {});
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      backgroundColor: Color(0xFF16A34A),
                                      content: Text('✅ All cameras activated for grid view!'),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      if (_streamService.cameraProfiles.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          alignment: Alignment.center,
                          child: const Text('No cameras configured yet. Click "+ Add Camera" to add one.',
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        )
                      else
                        ...List.generate(_streamService.cameraProfiles.length, (idx) {
                          final cam = _streamService.cameraProfiles[idx];
                          final isCurrent = cam.id == _streamService.activeProfileId;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: isCurrent ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCurrent ? const Color(0xFF86EFAC) : Colors.grey.shade300,
                                width: isCurrent ? 1.5 : 1.0,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  await _switchCamera(cam);
                                  setDlgState(() {});
                                  setState(() {});
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: (isCurrent ? const Color(0xFF16A34A) : const Color(0xFF0F766E)).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          cam.sourceType == CctvSourceType.webcam ? Icons.camera_alt_rounded : Icons.videocam_rounded,
                                          color: isCurrent ? const Color(0xFF16A34A) : const Color(0xFF0F766E),
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                  cam.name,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                                ),
                                                if (isCurrent)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFD97706),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.star_rounded, size: 10, color: Colors.white),
                                                        SizedBox(width: 2),
                                                        Text('SINGLE CAM MAIN', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
                                                      ],
                                                    ),
                                                  ),
                                                if (cam.isEnabled)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF16A34A),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.check_circle_rounded, size: 10, color: Colors.white),
                                                        SizedBox(width: 3),
                                                        Text('ACTIVE IN GRID', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                                      ],
                                                    ),
                                                  )
                                                else
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFF1F5F9),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: Colors.grey.shade300),
                                                    ),
                                                    child: const Text('STANDBY (Disabled)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                                  ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: cam.role == 'madarsa_gate'
                                                        ? const Color(0xFF2563EB).withValues(alpha: 0.15)
                                                        : (cam.role == 'classroom'
                                                            ? const Color(0xFFD97706).withValues(alpha: 0.15)
                                                            : const Color(0xFF64748B).withValues(alpha: 0.15)),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    cam.role == 'madarsa_gate'
                                                        ? '🚪 Gate In/Out'
                                                        : (cam.role == 'classroom' ? '🏫 Classroom' : '🌐 All-in-One'),
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                      color: cam.role == 'madarsa_gate'
                                                          ? const Color(0xFF1D4ED8)
                                                          : (cam.role == 'classroom' ? const Color(0xFFB45309) : const Color(0xFF475569)),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              cam.sourceType == CctvSourceType.webcam
                                                  ? 'USB Webcam Index #${cam.cameraIndex}'
                                                  : cam.ipUrl,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Grid Active toggle switch
                                      Tooltip(
                                        message: cam.isEnabled ? 'Active in Grid (Click to disable)' : 'Standby / Disabled (Click to enable in grid)',
                                        child: Switch(
                                          value: cam.isEnabled,
                                          activeThumbColor: const Color(0xFF16A34A),
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          onChanged: (val) async {
                                            await _streamService.toggleProfileEnabled(cam.id, val);
                                            setDlgState(() {});
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                      // Quick Test Connection
                                      IconButton(
                                        icon: const Icon(Icons.wifi_find_rounded, size: 18, color: Color(0xFF0284C7)),
                                        tooltip: 'Quick Test Connection',
                                        onPressed: () async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text('Testing connection to ${cam.name} (${cam.ipUrl})...'),
                                              duration: const Duration(seconds: 1),
                                            ),
                                          );
                                          final res = await _streamService.testCameraConnection(cam.toConfig());
                                          messenger.hideCurrentSnackBar();
                                          messenger.showSnackBar(
                                            SnackBar(
                                              backgroundColor: res['success'] == true ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                              content: Text(res['success'] == true
                                                  ? '✅ ${cam.name} is ONLINE & Connected!'
                                                  : '⚠️ ${cam.name} is Offline: ${res['message']}'),
                                              duration: const Duration(seconds: 3),
                                            ),
                                          );
                                        },
                                      ),
                                      // Edit Camera
                                      IconButton(
                                        icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF0F766E)),
                                        tooltip: 'Edit Camera',
                                        onPressed: () {
                                          _showAddEditCameraModal(ctx, setDlgState, existing: cam);
                                        },
                                      ),
                                      // More Actions Menu
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFF64748B)),
                                        tooltip: 'More Actions',
                                        offset: const Offset(0, 36),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        onSelected: (val) async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          if (val == 'main') {
                                            await _switchCamera(cam);
                                            setDlgState(() {});
                                            setState(() {});
                                          } else if (val == 'apply_all') {
                                            await _streamService.applySourceToAllProfiles(cam.id);
                                            setDlgState(() {});
                                            setState(() {});
                                            messenger.showSnackBar(
                                              SnackBar(
                                                backgroundColor: const Color(0xFF0F766E),
                                                content: Text('✅ "${cam.name}" applied to all grid tiles!'),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                          } else if (val == 'clone') {
                                            await _streamService.duplicateCameraProfile(cam.id);
                                            setDlgState(() {});
                                            setState(() {});
                                            messenger.showSnackBar(
                                              SnackBar(
                                                backgroundColor: const Color(0xFF0F766E),
                                                content: Text('✅ "${cam.name}" cloned into a new Grid Tile! Both stream simultaneously.'),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                          } else if (val == 'delete') {
                                            await _streamService.deleteCameraProfile(cam.id);
                                            setDlgState(() {});
                                            setState(() {});
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (!isCurrent)
                                            const PopupMenuItem<String>(
                                              value: 'main',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.play_arrow_rounded, color: Color(0xFF0F766E), size: 18),
                                                  SizedBox(width: 10),
                                                  Text('Set as Single-Cam Main View', style: TextStyle(fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                          const PopupMenuItem<String>(
                                            value: 'apply_all',
                                            child: Row(
                                              children: [
                                                Icon(Icons.copy_all_rounded, color: Color(0xFF0F766E), size: 18),
                                                SizedBox(width: 10),
                                                Text('Apply Source to All Grids', style: TextStyle(fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem<String>(
                                            value: 'clone',
                                            child: Row(
                                              children: [
                                                Icon(Icons.add_to_photos_rounded, color: Color(0xFF7C3AED), size: 18),
                                                SizedBox(width: 10),
                                                Text('Clone / Duplicate to New Tile', style: TextStyle(fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                          if (_streamService.cameraProfiles.length > 1) ...[
                                            const PopupMenuDivider(height: 6),
                                            const PopupMenuItem<String>(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 18),
                                                  SizedBox(width: 10),
                                                  Text('Delete Camera', style: TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_rounded, color: Color(0xFF2563EB), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'To view all cameras simultaneously, click the "Grid" button on the Kiosk top bar.',
                                style: TextStyle(color: Color(0xFF1E40AF), fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  final newCfg = currentCfg.copyWith(
                    ipUrl: ipUrlCtrl.text.trim(),
                    username: userCtrl.text.trim(),
                    password: passCtrl.text.trim(),
                  );
                  await _streamService.startStream(newCfg);
                  if (_isMultiCamMode) {
                    await _streamService.startMultiCameraStreams(_streamService.cameraProfiles);
                  }

                  // Save configuration to SharedPreferences
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('cctv_source_type', newCfg.sourceType.name);
                  await prefs.setString('cctv_ip_url', newCfg.ipUrl);
                  await prefs.setString('cctv_username', newCfg.username);
                  await prefs.setString('cctv_password', newCfg.password);
                  await prefs.setDouble('cctv_threshold', _engine.matchThreshold);
                  await prefs.setInt('cctv_cooldown_min', _engine.cooldownDuration.inMinutes);
                  await prefs.setString('cctv_sensitivity', _engine.detectionSensitivity.name);
                  await prefs.setBool('cctv_detect_all_humans', _engine.detectAllHumans);
                  await prefs.setBool('cctv_enable_people_counting', _isPeopleCountingEnabled);
                  await prefs.setBool('cctv_enable_anti_spoofing', _isAntiSpoofingEnabled);
                  await prefs.setInt('cctv_spoof_sensitivity_level', _spoofSensitivityLevel);

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (mounted) {
                    setState(() {});
                  }
                },
                child: const Text('Save & Connect'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddEditCameraModal(BuildContext parentCtx, StateSetter parentSetState, {CctvCameraProfile? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? 'Camera ${_streamService.cameraProfiles.length + 1}');
    final ipUrlCtrl = TextEditingController(text: existing?.ipUrl ?? '192.168.1.64');
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '');
    CctvSourceType selectedSource = existing?.sourceType ?? CctvSourceType.ipCamera;
    String selectedRole = existing?.role ?? 'all';
    int selectedCamIndex = existing?.cameraIndex ?? 0;
    String? testMsg;
    bool? testOk;
    bool isTestingCam = false;
    Uint8List? sampleFrameBytes;

    showDialog(
      context: parentCtx,
      builder: (modalCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              existing != null ? 'Edit Camera' : 'Add New Camera',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Camera Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        hintText: 'e.g. Gate 1, Classroom 1, Hifz Hall',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Camera Attendance Role:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('🌐 All-in-One (Follows Auto Schedule)'),
                        ),
                        DropdownMenuItem(
                          value: 'madarsa_gate',
                          child: Text('🚪 Madarsa Gate (Daily Shift In / Out Only)'),
                        ),
                        DropdownMenuItem(
                          value: 'classroom',
                          child: Text('🏫 Classroom (Period-Wise Attendance Only)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedRole = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('Camera Type:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    SegmentedButton<CctvSourceType>(
                      segments: const [
                        ButtonSegment(value: CctvSourceType.ipCamera, label: Text('IP / CCTV Camera')),
                        ButtonSegment(value: CctvSourceType.webcam, label: Text('USB Webcam')),
                      ],
                      selected: {selectedSource},
                      onSelectionChanged: (set) => setModalState(() => selectedSource = set.first),
                    ),
                    const SizedBox(height: 12),
                    if (selectedSource == CctvSourceType.ipCamera) ...[
                      // Quick Brand / Universal IP Helpers
                      const Text('Quick Brand Helpers (Click to pre-fill IP):', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF0F766E)),
                            label: const Text('✨ Auto-Detect IP / Port', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final input = ipUrlCtrl.text.trim();
                              if (input.isNotEmpty) {
                                setModalState(() {
                                  testMsg = 'Probing $input for active camera ports...';
                                  testOk = null;
                                });
                                final res = await CctvDiscoveryService.probeSingleIp(input);
                                if (res != null) {
                                  ipUrlCtrl.text = res.suggestedStreamUrl ?? (res.port != 80 && res.port != 554 ? '${res.ip}:${res.port}' : res.ip);
                                  setModalState(() {
                                    testMsg = 'Auto-detected ${res.brand} on port ${res.port}! ✅';
                                    testOk = true;
                                  });
                                } else {
                                  setModalState(() {
                                    testMsg = 'Device at $input did not respond on common camera ports.';
                                    testOk = false;
                                  });
                                }
                              } else {
                                setModalState(() {
                                  testMsg = 'Searching local Wi-Fi & network for online cameras...';
                                  testOk = null;
                                });
                                final found = await CctvDiscoveryService.discoverNetworkCameras();
                                setModalState(() {
                                  if (found.isNotEmpty) {
                                    ipUrlCtrl.text = found.first.suggestedStreamUrl ?? (found.first.port != 80 && found.first.port != 554 ? '${found.first.ip}:${found.first.port}' : found.first.ip);
                                    testMsg = 'Auto-discovered ${found.first.brand} (${found.first.ip})! ✅';
                                    testOk = true;
                                  } else {
                                    testMsg = 'No online cameras detected on Wi-Fi. Please enter camera IP manually below.';
                                    testOk = false;
                                  }
                                });
                              }
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.phone_android_rounded, size: 14, color: Color(0xFF7C3AED)),
                            label: const Text('📱 Mobile IP Webcam', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              final cur = ipUrlCtrl.text.trim();
                              if (cur.isNotEmpty) {
                                final host = cur.replaceAll(RegExp(r'^https?://'), '').split('/')[0].split(':')[0];
                                ipUrlCtrl.text = '$host:8080';
                              } else {
                                ipUrlCtrl.text = '192.168.1.50:8080';
                              }
                              setModalState(() {});
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.videocam_rounded, size: 14, color: Color(0xFFDC2626)),
                            label: const Text('📹 Hikvision', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              final cur = ipUrlCtrl.text.trim();
                              if (cur.isNotEmpty) {
                                final host = cur.replaceAll(RegExp(r'^https?://'), '').split('/')[0].split(':')[0];
                                ipUrlCtrl.text = host;
                              } else {
                                ipUrlCtrl.text = '192.168.1.64';
                              }
                              setModalState(() {});
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFF2563EB)),
                            label: const Text('🎥 CP Plus / Dahua', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              final cur = ipUrlCtrl.text.trim();
                              if (cur.isNotEmpty) {
                                final host = cur.replaceAll(RegExp(r'^https?://'), '').split('/')[0].split(':')[0];
                                ipUrlCtrl.text = host;
                              } else {
                                ipUrlCtrl.text = '192.168.1.250';
                              }
                              setModalState(() {});
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.wifi_rounded, size: 14, color: Color(0xFF0D9488)),
                            label: const Text('📡 TP-Link Tapo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              final cur = ipUrlCtrl.text.trim();
                              if (cur.isNotEmpty) {
                                final host = cur.replaceAll(RegExp(r'^https?://'), '').split('/')[0].split(':')[0];
                                ipUrlCtrl.text = host;
                              } else {
                                ipUrlCtrl.text = '192.168.1.100';
                              }
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text('Camera IP Address (Wi-Fi or LAN):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: ipUrlCtrl,
                        decoration: InputDecoration(
                          hintText: 'e.g. 192.168.1.64 or 192.168.1.50:8080',
                          helperText: 'Enter camera IP address — Direct Wi-Fi/LAN connection without complex NVR setup!',
                          helperStyle: const TextStyle(fontSize: 10, color: Color(0xFF0F766E), fontWeight: FontWeight.w600),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: userCtrl,
                              decoration: InputDecoration(
                                labelText: 'Username (Optional)',
                                hintText: 'admin',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: passCtrl,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Password (Optional)',
                                hintText: '••••••',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        icon: isTestingCam
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_find_rounded, size: 16),
                        label: Text(isTestingCam ? 'Auto-Negotiating Stream...' : 'Test Connection'),
                        onPressed: isTestingCam
                            ? null
                            : () async {
                                setModalState(() {
                                  isTestingCam = true;
                                  sampleFrameBytes = null;
                                  testMsg = null;
                                });
                                final res = await _streamService.testCameraConnection(CctvCameraConfig(
                                  sourceType: CctvSourceType.ipCamera,
                                  ipUrl: ipUrlCtrl.text.trim(),
                                  username: userCtrl.text.trim(),
                                  password: passCtrl.text.trim(),
                                ));
                                setModalState(() {
                                  isTestingCam = false;
                                  testOk = res['success'] == true;
                                  testMsg = res['message']?.toString();
                                  if (res['bytes'] is Uint8List) {
                                    sampleFrameBytes = res['bytes'] as Uint8List;
                                  }
                                  if (testOk == true && res['workingUrl'] != null) {
                                    var url = res['workingUrl'].toString();
                                    if (url.toLowerCase().contains(':8080/video')) {
                                      url = url.replaceAll(RegExp(r':8080/video\b', caseSensitive: false), ':8080/shot.jpg');
                                    } else if (url.toLowerCase().endsWith('/video')) {
                                      url = '${url.substring(0, url.length - 6)}/shot.jpg';
                                    }
                                    ipUrlCtrl.text = url;
                                  }
                                });
                              },
                      ),
                      if (testMsg != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: testOk == true ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: testOk == true ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              if (testOk == true && sampleFrameBytes != null) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(
                                    sampleFrameBytes!,
                                    width: 56,
                                    height: 42,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  testMsg!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: testOk == true ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else ...[
                      const Text('Select USB Webcam:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<int>(
                        initialValue: selectedCamIndex < _streamService.availableCamerasList.length ? selectedCamIndex : 0,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: List.generate(_streamService.availableCamerasList.length, (i) {
                          final cam = _streamService.availableCamerasList[i];
                          return DropdownMenuItem(value: i, child: Text(cam.name.isNotEmpty ? cam.name : 'Webcam #$i'));
                        }),
                        onChanged: (val) {
                          if (val != null) selectedCamIndex = val;
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(modalCtx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                onPressed: () async {
                  final name = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : 'Camera';
                  final prof = CctvCameraProfile(
                    id: existing?.id ?? 'cam_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    role: selectedRole,
                    sourceType: selectedSource,
                    cameraIndex: selectedCamIndex,
                    ipUrl: ipUrlCtrl.text.trim(),
                    username: userCtrl.text.trim(),
                    password: passCtrl.text.trim(),
                  );
                  if (existing != null) {
                    await _streamService.editCameraProfile(prof);
                  } else {
                    await _streamService.addCameraProfile(prof);
                  }
                  if (modalCtx.mounted) {
                    Navigator.pop(modalCtx);
                  }
                  parentSetState(() {});
                  if (mounted) setState(() {});
                },
                child: const Text('Save Camera'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSensitivityOptionTile({
    required String title,
    required String subtitle,
    required FaceDetectionSensitivity value,
    required FaceDetectionSensitivity current,
    required VoidCallback onSelect,
  }) {
    final isSelected = value == current;
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F766E).withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F766E) : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: isSelected ? const Color(0xFF0F766E) : Colors.grey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFF0F766E) : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _CctvHudPainter extends CustomPainter {
  final List<CctvTrackedFace> trackedFaces;
  final bool isStreaming;

  _CctvHudPainter({
    required this.trackedFaces,
    required this.isStreaming,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Draw Tracked Faces Bounding Boxes and Clean Badges
    for (final face in trackedFaces) {
      final fW = face.frameWidth > 0 ? face.frameWidth : 1280.0;
      final fH = face.frameHeight > 0 ? face.frameHeight : 720.0;

      // Calculate exact BoxFit.contain scaling and centering offsets
      final scale = math.min(size.width / fW, size.height / fH);
      final renderW = fW * scale;
      final renderH = fH * scale;
      final offsetX = (size.width - renderW) / 2.0;
      final offsetY = (size.height - renderH) / 2.0;

      final screenRect = Rect.fromLTRB(
        (offsetX + face.boundingBox.left * scale).clamp(0.0, size.width),
        (offsetY + face.boundingBox.top * scale).clamp(0.0, size.height),
        (offsetX + face.boundingBox.right * scale).clamp(0.0, size.width),
        (offsetY + face.boundingBox.bottom * scale).clamp(0.0, size.height),
      );

      // Only draw if the box has valid size on screen
      if (screenRect.width < 10 || screenRect.height < 10) continue;

      final Color boxColor;
      final String tagText;
      final Color badgeBg;
      final Color textColor;

      if (face.isSpoof) {
        // High visibility Crimson Red alert for Spoof / Phone Screen / Fake Attack (0% Attendance Marked)
        boxColor = const Color(0xFFDC2626);
        final liveStr = face.livenessScore > 0 ? ' • Liveness: ${face.livenessScore.toStringAsFixed(1)}%' : '';
        tagText = '⚠️ Spoof Attack Blocked$liveStr\nAttendance Blocked • Fake / Screen Attack Rejected';
        badgeBg = const Color(0xFFFEF2F2);
        textColor = const Color(0xFF991B1B);
      } else if (face.isMatched) {
        boxColor = face.isOnCooldown ? const Color(0xFF0284C7) : const Color(0xFF10B981);
        final grInfo = (face.grNo != null && face.grNo!.isNotEmpty) ? ' [GR: ${face.grNo}]' : '';
        final classInfo = (face.className != null && face.className!.isNotEmpty) ? ' • ${face.className}' : '';
        final liveStr = face.livenessScore > 0 ? ' • Live: ${face.livenessScore.toStringAsFixed(1)}%' : '';
        tagText = '${face.studentName ?? "Student"}$grInfo$classInfo • ${face.confidence.toStringAsFixed(0)}% Match$liveStr\n${face.statusTag}';
        badgeBg = Colors.white;
        textColor = const Color(0xFF0F172A);
      } else {
        // Slate Gray for Unregistered Genuine Human / Visitor
        boxColor = const Color(0xFF64748B);
        final liveStr = face.livenessScore > 0 ? ' • Live: ${face.livenessScore.toStringAsFixed(1)}%' : '';
        tagText = '👤 Unknown Visitor • Unregistered$liveStr\nNo record found in system';
        badgeBg = const Color(0xFFF8FAFC);
        textColor = const Color(0xFF334155);
      }

      final boxPaint = Paint()
        ..color = boxColor
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke;

      // Draw rounded face bounding box
      canvas.drawRRect(
        RRect.fromRectAndRadius(screenRect, const Radius.circular(8)),
        boxPaint,
      );

      final textSpan = TextSpan(
        text: tagText,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeRect = Rect.fromLTWH(
        screenRect.left.clamp(4.0, size.width - textPainter.width - 16),
        (screenRect.top - textPainter.height - 12).clamp(4.0, size.height - textPainter.height - 12),
        textPainter.width + 12,
        textPainter.height + 6,
      );

      // Badge Background with colored border
      final badgeBgPaint = Paint()..color = badgeBg;
      final badgeBorderPaint = Paint()
        ..color = boxColor
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;

      canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(6)), badgeBgPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(6)), badgeBorderPaint);

      textPainter.paint(canvas, Offset(badgeRect.left + 6, badgeRect.top + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _CctvHudPainter oldDelegate) => true;
}
