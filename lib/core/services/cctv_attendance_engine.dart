import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../features/attendance/data/models/attendance_models.dart';
import '../../features/attendance/data/repositories/attendance_repository.dart';
import 'attendance_timing_helper.dart';
import 'biometric_hardware_service.dart';
import 'cctv_native_face_engine.dart';

class CctvTrackedFace {
  final Rect boundingBox;
  final double frameWidth;
  final double frameHeight;
  final String? studentId;
  final String? studentName;
  final String? grNo;
  final String? className;
  final String? photoPath;
  final double confidence;
  final double blurScore;
  final bool isLiveFace;
  final bool isSpoof;
  final bool isMatched;
  final bool isOnCooldown;
  final bool isUnknownVisitor;
  final String statusTag;
  final double livenessScore;

  const CctvTrackedFace({
    required this.boundingBox,
    this.frameWidth = 0.0,
    this.frameHeight = 0.0,
    this.studentId,
    this.studentName,
    this.grNo,
    this.className,
    this.photoPath,
    this.confidence = 0.0,
    this.blurScore = 100.0,
    this.isLiveFace = true,
    this.isSpoof = false,
    this.isMatched = false,
    this.isOnCooldown = false,
    this.isUnknownVisitor = false,
    this.statusTag = 'Detecting...',
    this.livenessScore = 0.0,
  });
}

class CctvAttendanceEvent {
  final String studentId;
  final String studentName;
  final String grNo;
  final String className;
  final String? photoPath;
  final DateTime timestamp;
  final String status; // 'Present', 'Late', 'Out'
  final double matchConfidence;
  final String remarks;
  final String cameraName;

  const CctvAttendanceEvent({
    required this.studentId,
    required this.studentName,
    required this.grNo,
    required this.className,
    this.photoPath,
    required this.timestamp,
    required this.status,
    required this.matchConfidence,
    required this.remarks,
    this.cameraName = 'Camera 1',
  });
}

/// In-memory record of a unique individual seen in the current CCTV kiosk session
class _SessionCountedPerson {
  final int personId;
  final String? studentId;
  final List<String> templates;
  final List<Float32List> vectors;
  final DateTime firstSeen;
  DateTime lastSeen;

  _SessionCountedPerson({
    required this.personId,
    this.studentId,
    required String initialTemplate,
    Float32List? initialVector,
    required this.firstSeen,
    required this.lastSeen,
  })  : templates = (initialTemplate.isNotEmpty) ? [initialTemplate] : [],
        vectors = (initialVector != null) ? [initialVector] : [];

  /// Backward-compatibility getter for single template
  String get template => templates.isNotEmpty ? templates.first : '';
  Float32List? get vector => vectors.isNotEmpty ? vectors.first : null;

  void addObservation(String newTemplate, Float32List? newVector, DateTime seen) {
    lastSeen = seen;
    if (newTemplate.isNotEmpty && !templates.contains(newTemplate) && templates.length < 16) {
      templates.add(newTemplate);
    }
    if (newVector != null && vectors.length < 16) {
      bool hasCloseVector = false;
      for (final existing in vectors) {
        if (CctvNativeFaceEngine.cosineSimilarity(newVector, existing) >= 90.0) {
          hasCloseVector = true;
          break;
        }
      }
      if (!hasCloseVector || vectors.length < 3) {
        vectors.add(newVector);
      }
    }
  }
}

/// Spatio-temporal track for persistent identity locking across video frames
class _ActiveFaceTrack {
  final int trackId;
  Rect boundingBox;
  DateTime lastSeen;
  StudentAttendance? lockedStudent;
  double lockedConfidence = 0.0;
  bool isUnknownVisitor = false;
  int consecutiveFrames = 1;
  int? sessionPersonId;
  int hits = 0;
  String state = 'tentative'; // 'tentative', 'confirmed', 'counted'

  _ActiveFaceTrack({
    required this.trackId,
    required this.boundingBox,
    required this.lastSeen,
  });

  /// Returns true once track has accumulated enough hits to be reliably confirmed
  bool get isConfirmed => hits >= 3;

  /// Compute Intersection over Union (IoU) with another bounding box
  double computeIoU(Rect other) {
    final double intersectLeft = boundingBox.left > other.left ? boundingBox.left : other.left;
    final double intersectTop = boundingBox.top > other.top ? boundingBox.top : other.top;
    final double intersectRight = boundingBox.right < other.right ? boundingBox.right : other.right;
    final double intersectBottom = boundingBox.bottom < other.bottom ? boundingBox.bottom : other.bottom;

    if (intersectRight <= intersectLeft || intersectBottom <= intersectTop) {
      return 0.0;
    }

    final double intersection = (intersectRight - intersectLeft) * (intersectBottom - intersectTop);
    final double areaA = boundingBox.width * boundingBox.height;
    final double areaB = other.width * other.height;
    final double union = areaA + areaB - intersection;

    if (union <= 0.0) return 0.0;
    return intersection / union;
  }

  /// Distance between centers normalized by average box dimension
  double normalizedCenterDistance(Rect other) {
    final double cAx = boundingBox.left + boundingBox.width / 2.0;
    final double cAy = boundingBox.top + boundingBox.height / 2.0;
    final double cBx = other.left + other.width / 2.0;
    final double cBy = other.top + other.height / 2.0;
    final double dx = cAx - cBx;
    final double dy = cAy - cBy;
    final double dist = math.sqrt(dx * dx + dy * dy);
    final double avgDim = (boundingBox.width + boundingBox.height + other.width + other.height) / 4.0;
    if (avgDim <= 0) return 999.0;
    return dist / avgDim;
  }

  /// Check if `other` matches this track (IoU >= 0.20 or center distance <= 0.45 avg dim)
  bool matches(Rect other) {
    final iou = computeIoU(other);
    if (iou >= 0.20) return true;
    final dist = normalizedCenterDistance(other);
    return dist <= 0.45;
  }
}

class _MatchCandidate {
  final StudentAttendance student;
  final double score;
  const _MatchCandidate(this.student, this.score);
}

class CctvAttendanceEngine {
  final BiometricHardwareService _biometricService = BiometricHardwareService();
  final CctvNativeFaceEngine _nativeEngine = CctvNativeFaceEngine();
  final AttendanceRepository repository;

  /// Returns true if high-speed C++ Native Engine (cctv_face_engine.dll) is active
  bool get isNativeEngineActive => _nativeEngine.isAvailable;

  List<StudentAttendance> _enrolledStudents = [];
  final Map<String, String> _templateCache = {}; // studentId -> template
  final List<StudentAttendance> _enrolledStudentIndex = [];
  final List<Float32List> _enrolledVectorCache = [];
  final Map<String, DateTime> _cooldownCache = {}; // studentId -> lastMarkedTime

  // Spatio-temporal track registry for persistent face tracking across frames
  final List<_ActiveFaceTrack> _activeTracks = [];
  int _nextTrackId = 1;

  // Strict session tracking to prevent duplicate attendance in the same shift or period
  final Map<String, String> _markedInRecords = {}; // "${studentId}_${date}_${shiftId}" -> check_in_time
  final Map<String, String> _markedOutRecords = {}; // "${studentId}_${date}_${shiftId}" -> check_out_time
  final Map<String, DateTime> _checkInTimestamps = {}; // studentId -> DateTime of check-in
  final Map<String, String> _markedPeriodRecords = {}; // "${studentId}_${date}_period_${periodNumber}" -> time
  final Map<String, bool> _studentInsideState = {}; // studentId -> true if inside, false if stepped out
  final Map<String, DateTime> _lastMovementActionTime = {}; // studentId -> last IN/OUT/RE-ENTRY time

  bool isStudentInside(String studentId) => _studentInsideState[studentId] ?? false;

  Duration cooldownDuration = const Duration(minutes: 5);
  double matchThreshold = 70.0;
  bool enableAudioVoice = true;

  bool _enableAntiSpoofing = true;
  bool get enableAntiSpoofing => _enableAntiSpoofing;
  set enableAntiSpoofing(bool val) {
    _enableAntiSpoofing = val;
    CctvNativeFaceEngine.instance.setSpoofLevel(val ? _spoofSensitivityLevel : 0);
  }

  int _spoofSensitivityLevel = 2; // 0=Off, 1=Low, 2=Medium, 3=High
  int get spoofSensitivityLevel => _spoofSensitivityLevel;
  set spoofSensitivityLevel(int level) {
    _spoofSensitivityLevel = level.clamp(0, 3);
    if (_enableAntiSpoofing) {
      CctvNativeFaceEngine.instance.setSpoofLevel(_spoofSensitivityLevel);
    }
  }

  String currentMode = 'auto'; // 'auto', 'in', 'out'
  String currentCameraName = 'Camera 1';

  String? currentShiftId;
  String? currentShiftName;
  String? currentShiftStartTime; // e.g. "08:00"
  int lateGraceMinutes = 15;

  // Period Attendance Configuration
  bool isPeriodMode = false;
  int currentPeriodNumber = 1;
  String? currentPeriodId;
  String? currentPeriodName;

  /// Flag to pause auto-marking when outside active shift/period timetable
  bool isAttendanceSuspended = false;
  String? scheduleSuspensionReason;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  final StreamController<List<CctvTrackedFace>> _trackedFacesController =
      StreamController<List<CctvTrackedFace>>.broadcast();
  Stream<List<CctvTrackedFace>> get onFacesTracked => _trackedFacesController.stream;

  final StreamController<CctvAttendanceEvent> _attendanceEventController =
      StreamController<CctvAttendanceEvent>.broadcast();
  Stream<CctvAttendanceEvent> get onAttendanceMarked => _attendanceEventController.stream;

  // Human & Crowd Counter (افراد کی گنتی / People Counter) with Biometric Session Deduplication
  bool enablePeopleCounting = true;
  final List<_SessionCountedPerson> _sessionCountedPeople = [];
  int _nextSessionPersonId = 1;

  int get totalSessionPeopleCount => enablePeopleCounting ? _sessionCountedPeople.length : 0;
  int liveInFramePeopleCount = 0;

  final StreamController<({int liveCount, int totalCount})> _peopleCountController =
      StreamController<({int liveCount, int totalCount})>.broadcast();
  Stream<({int liveCount, int totalCount})> get onPeopleCountChanged => _peopleCountController.stream;

  /// Reset people counter to 0 (clears session biometric cache when screen closes or reset is pressed)
  void resetPeopleCount() {
    _sessionCountedPeople.clear();
    _nextSessionPersonId = 1;
    liveInFramePeopleCount = 0;
    if (!_peopleCountController.isClosed) {
      _peopleCountController.add((liveCount: 0, totalCount: 0));
    }
  }

  final List<CctvAttendanceEvent> recentActivityFeed = [];

  CctvAttendanceEngine({required this.repository});

  /// Clear active spatio-temporal face tracks (e.g. on mode switch, camera change, or reset)
  void clearActiveTracks() {
    _activeTracks.clear();
    _nextTrackId = 1;
  }

  /// Switch between Daily Shift Attendance and Period-Wise Attendance
  void switchAttendanceMode({required bool periodMode, int? periodNumber, String? periodId, String? periodName}) {
    isPeriodMode = periodMode;
    if (periodNumber != null) currentPeriodNumber = periodNumber;
    if (periodId != null) currentPeriodId = periodId;
    if (periodName != null) currentPeriodName = periodName;
    clearActiveTracks();
  }

  /// Set check-in / check-out direction mode ('auto', 'in', 'out')
  void setAttendanceMode(String mode) {
    currentMode = mode;
    _cooldownCache.clear();
    clearActiveTracks();
  }

  /// Convenience setter for Period Mode
  void setPeriodMode(bool enabled, {int periodNumber = 1}) {
    switchAttendanceMode(periodMode: enabled, periodNumber: periodNumber);
  }

  /// Update the active camera label for remarks
  void setCameraName(String name) {
    currentCameraName = name;
    clearActiveTracks();
  }

  /// Initialize engine with student database and pre-warm biometric templates
  Future<void> initializeStudents(List<StudentAttendance> students) async {
    _enrolledStudents = List.from(students);
    _templateCache.clear();
    _enrolledStudentIndex.clear();
    _enrolledVectorCache.clear();
    _markedInRecords.clear();
    _markedOutRecords.clear();
    _checkInTimestamps.clear();
    _studentInsideState.clear();
    _lastMovementActionTime.clear();
    clearActiveTracks();

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final List<Future<void>> warmFutures = [];
    for (final s in _enrolledStudents) {
      bool needRefresh = false;
      if (s.faceData != null && s.faceData!.trim().isNotEmpty) {
        _cacheStudentTemplate(s, s.faceData!.trim());
        final vec = _biometricService.extractFloatVector(s.faceData!);
        if (vec != null && vec.length >= 176 && vec[170] == 0.0 && vec[171] == 0.0 && vec[174] == 0.0) {
          needRefresh = true;
        }
      } else {
        needRefresh = true;
      }

      if (needRefresh && s.photoPath != null && s.photoPath!.isNotEmpty) {
        // Pre-warm template from photo in background
        warmFutures.add(_preWarmTemplate(s));
      }

      // Pre-populate shift attendance cache if already marked today
      final sShift = s.shiftId.isNotEmpty ? s.shiftId : (currentShiftId ?? 'main');
      final sKey = '${s.id}_${todayStr}_$sShift';
      if (s.status != null && s.status!.isNotEmpty && s.status != 'Absent') {
        _markedInRecords[sKey] = s.checkInTime.isNotEmpty ? s.checkInTime : 'Recorded';
      }
      if (s.checkOutTime.isNotEmpty) {
        _markedOutRecords[sKey] = s.checkOutTime;
      }
      if (s.checkInTime.isNotEmpty && s.checkOutTime.isEmpty) {
        _studentInsideState[s.id] = true;
      } else if (s.checkInTime.isNotEmpty && s.checkOutTime.isNotEmpty) {
        _studentInsideState[s.id] = false;
      }
    }

    if (warmFutures.isNotEmpty) {
      await Future.wait(warmFutures);
    }

    // Pre-populate period attendance cache for today from repository
    try {
      final periodRecords = await repository.getPeriodAttendance(
        date: todayStr,
        periodNumber: currentPeriodNumber,
      );
      for (final pr in periodRecords) {
        if (pr.status != 'Absent') {
          final pKey = '${pr.studentId}_${todayStr}_period_${pr.periodNumber ?? currentPeriodNumber}';
          _markedPeriodRecords[pKey] = pr.time.isNotEmpty ? pr.time : 'Recorded';
        }
      }
    } catch (_) {}
  }

  /// Manually seed session state from already loaded students pool
  void initializeSessionFromStudents(List<StudentAttendance> students, String dateStr, String? shiftId) {
    final sId = (shiftId != null && shiftId.isNotEmpty) ? shiftId : (currentShiftId ?? 'main');
    _markedInRecords.clear();
    _markedOutRecords.clear();
    _checkInTimestamps.clear();
    _studentInsideState.clear();
    _lastMovementActionTime.clear();
    for (final s in students) {
      final sKey = '${s.id}_${dateStr}_$sId';
      if ((s.status != null && s.status!.isNotEmpty && s.status != 'Absent') || s.checkInTime.isNotEmpty) {
        _markedInRecords[sKey] = s.checkInTime.isNotEmpty ? s.checkInTime : 'Recorded';
      }
      if (s.checkOutTime.isNotEmpty) {
        _markedOutRecords[sKey] = s.checkOutTime;
      }
      if (s.checkInTime.isNotEmpty && s.checkOutTime.isEmpty) {
        _studentInsideState[s.id] = true;
      } else if (s.checkInTime.isNotEmpty && s.checkOutTime.isNotEmpty) {
        _studentInsideState[s.id] = false;
      }
    }
    debugPrint('[CctvAttendanceEngine] Initialized session: ${_markedInRecords.length} IN, ${_markedOutRecords.length} OUT');
  }

  void _cacheStudentTemplate(StudentAttendance s, String template) {
    _templateCache[s.id] = template;
    final vec = _biometricService.extractFloatVector(template);
    if (vec != null) {
      _enrolledStudentIndex.add(s);
      _enrolledVectorCache.add(vec);
    }
  }

  Future<void> _preWarmTemplate(StudentAttendance s) async {
    try {
      final file = File(s.photoPath!);
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        try {
          final template = await _biometricService.generateFaceTemplate(bytes, requireFace: false);
          _cacheStudentTemplate(s, template);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Detection sensitivity mode (sensitive, balanced, strict)
  FaceDetectionSensitivity detectionSensitivity = FaceDetectionSensitivity.balanced;

  /// Whether to track and display bounding boxes for all humans (students + visitors)
  /// If true: Enrolled students get Green boxes with name & attendance; visitors get Blue boxes.
  /// If false: Only enrolled students get boxes (clean background like Safepro AI).
  bool detectAllHumans = true;

  /// Process a raw video frame from webcam / CCTV stream
  Future<List<CctvTrackedFace>> processFrame(
    Uint8List frameBytes, {
    String? cameraName,
    String? cameraRole,
  }) async {
    if (_isProcessing) return [];
    _isProcessing = true;
    final activeCam = cameraName ?? currentCameraName;

    final bool effectiveIsPeriod;
    if (cameraRole == 'madarsa_gate') {
      effectiveIsPeriod = false;
    } else if (cameraRole == 'classroom') {
      effectiveIsPeriod = true;
    } else {
      effectiveIsPeriod = isPeriodMode;
    }

    try {
      final now = DateTime.now();
      // Expire stale tracks (not seen for > 5.0 seconds)
      _activeTracks.removeWhere((t) => now.difference(t.lastSeen).inMilliseconds >= 5000);

      // 1. Detect all faces simultaneously in the frame
      final detection = await _biometricService.detectFace(
        frameBytes,
        sensitivity: detectionSensitivity,
      );
      if (!detection.hasFace || detection.detectedFaces.isEmpty) {
        _trackedFacesController.add([]);
        if (enablePeopleCounting && !_peopleCountController.isClosed) {
          liveInFramePeopleCount = 0;
          _peopleCountController.add((
            liveCount: 0,
            totalCount: totalSessionPeopleCount,
          ));
        }
        return [];
      }

      // 2. Extract 176-D biometric feature templates for all detected faces (zero duplicate detection)
      final liveTemplates = await _biometricService.generateFaceTemplates(
        frameBytes,
        preDetectedFaces: detection.detectedFaces,
        nativeWidth: detection.imageWidth,
        nativeHeight: detection.imageHeight,
      );

      final List<CctvTrackedFace> trackedList = [];
      final imgW = detection.imageWidth.toDouble();
      final imgH = detection.imageHeight.toDouble();

      final Set<_ActiveFaceTrack> matchedTracksInFrame = {};
      final Set<int> claimedSessionPersonIdsInThisFrame = {};

      for (int i = 0; i < detection.detectedFaces.length; i++) {
        final face = detection.detectedFaces[i];
        final rect = Rect.fromLTRB(
          face.left.toDouble(),
          face.top.toDouble(),
          face.right.toDouble(),
          face.bottom.toDouble(),
        );

        // Find best matching active track for this face
        _ActiveFaceTrack? track;
        double bestTrackScore = -1.0;

        for (final existingTrack in _activeTracks) {
          if (matchedTracksInFrame.contains(existingTrack)) continue;
          if (existingTrack.matches(rect)) {
            final iou = existingTrack.computeIoU(rect);
            if (iou > bestTrackScore) {
              bestTrackScore = iou;
              track = existingTrack;
            }
          }
        }

        if (track != null) {
          track.boundingBox = rect;
          track.lastSeen = now;
          track.consecutiveFrames++;
          track.hits++;
          if (track.state == 'tentative' && track.isConfirmed) {
            track.state = 'confirmed';
          }
          matchedTracksInFrame.add(track);
        } else {
          track = _ActiveFaceTrack(
            trackId: _nextTrackId++,
            boundingBox: rect,
            lastSeen: now,
          );
          _activeTracks.add(track);
          matchedTracksInFrame.add(track);
        }

        final effectiveIsLive = enableAntiSpoofing ? face.isLiveFace : true;

        // 0. ABSOLUTE ANTI-SPOOFING SHIELD (Silent-Face-Anti-Spoofing MiniFASNetV2)
        // If a mobile phone screen, tablet, photo printout, or video replay is presented:
        // ZERO attendance marked, ZERO database writes, Crimson Red alert box on HUD.
        if (enableAntiSpoofing && !effectiveIsLive) {
          track.lockedStudent = null;
          track.lockedConfidence = 0.0;
          track.isUnknownVisitor = false;
          trackedList.add(CctvTrackedFace(
            boundingBox: rect,
            frameWidth: imgW,
            frameHeight: imgH,
            confidence: face.confidence,
            blurScore: face.blurScore,
            isLiveFace: false,
            isSpoof: true,
            isMatched: false,
            isOnCooldown: false,
            isUnknownVisitor: false,
            statusTag: '⚠️ Spoof Detected • Attendance Blocked',
            livenessScore: face.livenessScore,
          ));
          continue; // Block all database marking and candidate resolution!
        }

        final liveTemplate = i < liveTemplates.length ? liveTemplates[i] : null;
        final liveVec = (liveTemplate != null && liveTemplate.isNotEmpty)
            ? _biometricService.extractFloatVector(liveTemplate)
            : null;
        final activeTrack = track;

        StudentAttendance? bestStudent;
        double bestScore = 0.0;

        if (liveTemplate != null && liveTemplate.isNotEmpty) {
          // FAST-PATH: If this spatio-temporal track is already locked to an identified student,
          // verify directly with that student (<0.05ms) instead of looping over all 544 students!
          if (activeTrack.lockedStudent != null) {
            final candTpl = _templateCache[activeTrack.lockedStudent!.id] ?? activeTrack.lockedStudent!.faceData;
            if (candTpl != null && candTpl.trim().isNotEmpty) {
              final verified = _biometricService.matchFace(
                liveTemplate: liveTemplate,
                enrolledTemplate: candTpl.trim(),
                threshold: matchThreshold - 6.0, // Track-holding tolerance margin
              );
              if (verified.similarityScore >= (matchThreshold - 6.0)) {
                bestStudent = activeTrack.lockedStudent;
                bestScore = verified.similarityScore;
                activeTrack.lockedConfidence = bestScore;
              }
            }
          }

          if (bestStudent == null) {
            final List<_MatchCandidate> candidates = [];

            // Stage 1: Fast SIMD candidate pre-filtering via native C++ engine (<1ms for 544 students)
            if (_nativeEngine.isAvailable && liveVec != null && _enrolledVectorCache.isNotEmpty) {
              final match = _nativeEngine.batchMatch(
                probe: liveVec,
                enrolledList: _enrolledVectorCache,
                threshold: 40.0,
              );
              if (match.bestIndex >= 0 && match.bestIndex < _enrolledStudentIndex.length) {
                final cand = _enrolledStudentIndex[match.bestIndex];
                final candTpl = _templateCache[cand.id] ?? cand.faceData;
                if (candTpl != null && candTpl.trim().isNotEmpty) {
                  final verified = _biometricService.matchFace(
                    liveTemplate: liveTemplate,
                    enrolledTemplate: candTpl.trim(),
                    threshold: matchThreshold,
                  );
                  if (verified.similarityScore >= matchThreshold) {
                    candidates.add(_MatchCandidate(cand, verified.similarityScore));
                  }
                }
              }
            }

            // Stage 2: Pure fallback only if native engine was unavailable or had empty vector cache
            if (candidates.isEmpty && (!_nativeEngine.isAvailable || _enrolledVectorCache.isEmpty)) {
              for (final student in _enrolledStudents) {
                final studentTemplate = _templateCache[student.id] ?? student.faceData;
                if (studentTemplate == null || studentTemplate.trim().isEmpty) continue;

                final match = _biometricService.matchFace(
                  liveTemplate: liveTemplate,
                  enrolledTemplate: studentTemplate.trim(),
                  threshold: matchThreshold,
                );
                if (match.similarityScore >= matchThreshold) {
                  candidates.add(_MatchCandidate(student, match.similarityScore));
                }
              }
            }

            if (candidates.isNotEmpty) {
              candidates.sort((a, b) => b.score.compareTo(a.score));

              final topCandidate = candidates.first;
              final runnerUp = candidates.length > 1 ? candidates[1] : null;

              // Zero false-positive cross-matching protection:
              // 1. Strict biometric threshold (>= 70.0%)
              // 2. Ambiguity Margin / Top-2 Gap: If runner-up is within 6.0% of top score,
              //    there is identity ambiguity. Reject match unless top score is overwhelming (> 85.0%).
              final double ambiguityGap = runnerUp != null ? (topCandidate.score - runnerUp.score) : 999.0;
              final bool isAmbiguous = ambiguityGap < 6.0 && topCandidate.score < 85.0;

              if (!isAmbiguous && topCandidate.score >= matchThreshold) {
                _MatchCandidate chosenCand = topCandidate;

                // Spatio-temporal track stability (only if within 2.5% of top)
                for (final cand in candidates) {
                  if (chosenCand.score - cand.score <= 2.5 &&
                      track.lockedStudent != null &&
                      track.lockedStudent!.id == cand.student.id) {
                    chosenCand = cand;
                    break;
                  }
                }

                bestStudent = chosenCand.student;
                bestScore = chosenCand.score;

                // Lock this track to the resolved student
                track.lockedStudent = bestStudent;
                track.lockedConfidence = bestScore;
                track.isUnknownVisitor = false;
              } else {
                // Ambiguous or below threshold: zero false identity matching!
                track.lockedStudent = null;
                track.lockedConfidence = 0.0;
              }
            } else {
              // No enrolled student matched this face
              track.lockedStudent = null;
              track.lockedConfidence = 0.0;
            }
          }
        }

        if (bestStudent != null && bestScore >= matchThreshold) {
          final dateStr = DateFormat('yyyy-MM-dd').format(now);
          final timeStr = DateFormat('hh:mm:ss a').format(now);
          final displayShortTime = DateFormat('hh:mm a').format(now);

          final shiftKey = '${bestStudent.id}_${dateStr}_${currentShiftId ?? "main"}';
          final periodKey = '${bestStudent.id}_${dateStr}_period_$currentPeriodNumber';

          final lastMarked = _cooldownCache[bestStudent.id];
          final bool isCooldownActive = (lastMarked != null && now.difference(lastMarked) < cooldownDuration);

          String actionType = 'none'; // 'check_in', 'check_out', 'period', 'already_done'
          String status = 'Present';
          String tag = '';

          if (effectiveIsPeriod) {
            final bool isMarkedPeriod = _markedPeriodRecords.containsKey(periodKey);
            if (isMarkedPeriod) {
              actionType = 'already_done';
              tag = 'ALREADY MARKED [Period $currentPeriodNumber] (${_markedPeriodRecords[periodKey]})';
            } else {
              actionType = 'period';
              status = 'Present';
              tag = 'MATCH: ${bestScore.toStringAsFixed(0)}% | P$currentPeriodNumber Present';
            }
          } else {
            // Shift Attendance: Supports Dynamic In/Out & Temporary Exit Re-Entry Lifecycle
            final bool hasIn = _markedInRecords.containsKey(shiftKey) ||
                (bestStudent.checkInTime.isNotEmpty && bestStudent.status != null && bestStudent.status != 'Absent');
            final bool isInside = _studentInsideState[bestStudent.id] ?? (hasIn && bestStudent.checkOutTime.isEmpty);

            // 15-second debounce between movement transitions for the same student
            final lastAct = _lastMovementActionTime[bestStudent.id];
            final bool isMovementDebounced = (lastAct != null && now.difference(lastAct).inSeconds < 15);

            if (currentMode == 'in') {
              if (hasIn && isInside) {
                actionType = 'already_done';
                final inTime = _markedInRecords[shiftKey] ?? (bestStudent.checkInTime.isNotEmpty ? bestStudent.checkInTime : displayShortTime);
                tag = 'IN ALREADY RECORDED ($inTime)';
              } else if (hasIn && !isInside) {
                // Stepped out earlier and re-entering via Gate In camera
                actionType = 're_entry';
                status = 'Present';
                tag = 'RE-ENTERED: $displayShortTime (Welcome Back)';
              } else {
                actionType = 'check_in';
                final timingEval = AttendanceTimingHelper.evaluate(now, targetShiftId: currentShiftId);
                status = timingEval.status;
                tag = 'CHECK-IN: $status | ${bestScore.toStringAsFixed(0)}%';
              }
            } else if (currentMode == 'out') {
              if (!isInside && _markedOutRecords.containsKey(shiftKey)) {
                actionType = 'already_done';
                final outTime = _markedOutRecords[shiftKey] ?? (bestStudent.checkOutTime.isNotEmpty ? bestStudent.checkOutTime : displayShortTime);
                tag = 'OUT ALREADY RECORDED ($outTime)';
              } else {
                actionType = 'check_out';
                status = 'Present';
                tag = 'EXIT / OUT: $displayShortTime (Stepped Out)';
              }
            } else {
              // Smart Auto Movement Mode
              if (!hasIn) {
                // First arrival -> Check-IN
                actionType = 'check_in';
                final timingEval = AttendanceTimingHelper.evaluate(now, targetShiftId: currentShiftId);
                status = timingEval.status;
                tag = 'CHECK-IN: $status (${timingEval.message})';
              } else if (isMovementDebounced) {
                // Scanned again within 15 seconds: hold steady state to avoid flip-flop
                actionType = 'already_done';
                if (isInside) {
                  tag = 'INSIDE • Checked-In (${_markedInRecords[shiftKey] ?? displayShortTime})';
                } else {
                  tag = 'STEPPED OUT • (${_markedOutRecords[shiftKey] ?? displayShortTime})';
                }
              } else if (isInside) {
                // Student was inside and scans again -> Stepped Out (temporary exit recorded)
                actionType = 'check_out';
                status = 'Present';
                tag = 'EXIT / OUT: $displayShortTime (Stepped Out)';
              } else {
                // Student was outside and returns -> Re-Entry (clears temporary exit)
                actionType = 're_entry';
                status = 'Present';
                tag = 'RE-ENTERED: $displayShortTime (Welcome Back)';
              }
            }
          }

          if (isAttendanceSuspended) {
            tag = '🚫 Attendance OFF (Outside Timings)';
          } else if (isCooldownActive && actionType == 'none') {
            tag = 'RECENTLY SCANNED (${DateFormat('hh:mm a').format(lastMarked)})';
          }

          final isOnCooldown = (actionType == 'already_done') || (isCooldownActive && actionType == 'none');

          trackedList.add(CctvTrackedFace(
            boundingBox: rect,
            frameWidth: imgW,
            frameHeight: imgH,
            studentId: bestStudent.id,
            studentName: bestStudent.fullName,
            grNo: (bestStudent.grNo != null && bestStudent.grNo!.isNotEmpty) ? bestStudent.grNo : bestStudent.registrationNumber,
            className: bestStudent.className,
            photoPath: bestStudent.photoPath,
            confidence: bestScore,
            blurScore: face.blurScore,
            isLiveFace: effectiveIsLive,
            isMatched: true,
            isOnCooldown: isOnCooldown,
            isUnknownVisitor: false,
            statusTag: tag,
            livenessScore: face.livenessScore,
          ));

          // Track unique student in session people counter if enabled
          if (enablePeopleCounting) {
            final studentId = bestStudent.id;
            _SessionCountedPerson? existingPerson = _sessionCountedPeople
                .where((p) => p.studentId == studentId)
                .firstOrNull;

            // Also check if this student was previously registered under activeTrack's sessionPersonId
            if (existingPerson == null && activeTrack.sessionPersonId != null) {
              existingPerson = _sessionCountedPeople
                  .where((p) => p.personId == activeTrack.sessionPersonId)
                  .firstOrNull;
            }

            // Or if any previously counted visitor has a matching biometric vector
            if (existingPerson == null && liveVec != null) {
              for (final p in _sessionCountedPeople) {
                for (final v in p.vectors) {
                  if (CctvNativeFaceEngine.cosineSimilarity(liveVec, v) >= 50.0) {
                    existingPerson = p;
                    break;
                  }
                }
                if (existingPerson != null) break;
              }
            }

            if (existingPerson != null && !claimedSessionPersonIdsInThisFrame.contains(existingPerson.personId)) {
              existingPerson.addObservation(liveTemplate ?? '', liveVec, now);
              activeTrack.sessionPersonId = existingPerson.personId;
              claimedSessionPersonIdsInThisFrame.add(existingPerson.personId);
            } else {
              final newId = _nextSessionPersonId++;
              _sessionCountedPeople.add(_SessionCountedPerson(
                personId: newId,
                studentId: studentId,
                initialTemplate: liveTemplate ?? '',
                initialVector: liveVec,
                firstSeen: now,
                lastSeen: now,
              ));
              activeTrack.sessionPersonId = newId;
              claimedSessionPersonIdsInThisFrame.add(newId);
            }
          }

          // Auto-mark attendance ONLY if active (not suspended), not marked yet in this session, not on cooldown, and live face
          if (!isAttendanceSuspended && !isOnCooldown && effectiveIsLive &&
              (actionType == 'check_in' || actionType == 'check_out' || actionType == 're_entry' || actionType == 'period')) {
            _cooldownCache[bestStudent.id] = now;
            _lastMovementActionTime[bestStudent.id] = now;

            if (actionType == 'period') {
              _markedPeriodRecords[periodKey] = timeStr;
              _autoMarkAttendance(bestStudent, status, bestScore, now, isPeriod: true, cameraName: activeCam);
            } else if (actionType == 'check_in') {
              _markedInRecords[shiftKey] = timeStr;
              _checkInTimestamps[bestStudent.id] = now;
              _studentInsideState[bestStudent.id] = true;
              _autoMarkAttendance(bestStudent, status, bestScore, now, isCheckOut: false, cameraName: activeCam);
            } else if (actionType == 'check_out') {
              _markedOutRecords[shiftKey] = timeStr;
              _studentInsideState[bestStudent.id] = false;
              _autoMarkAttendance(bestStudent, 'Present', bestScore, now, isCheckOut: true, cameraName: activeCam);
            } else if (actionType == 're_entry') {
              _markedOutRecords.remove(shiftKey);
              _studentInsideState[bestStudent.id] = true;
              _autoMarkAttendance(bestStudent, 'Present', bestScore, now, isReEntry: true, cameraName: activeCam);
            }
          } else if (isAttendanceSuspended && !isOnCooldown && effectiveIsLive) {
            // Attendance is suspended/OFF: update cooldown to prevent UI frame chatter, but DO NOT save or announce voice
            _cooldownCache[bestStudent.id] = now;
          }
        } else if (enablePeopleCounting && detectAllHumans && effectiveIsLive && face.confidence >= 55.0 && trackedList.where((f) => !f.isMatched).length < 5) {
          // Unregistered Human / Visitor detected (strictly genuine live human face)
          activeTrack.isUnknownVisitor = true;

          // Biometric Deduplication: Check if this face was ALREADY counted in this kiosk session!
          _SessionCountedPerson? matchedPerson;

          // 1. Fast check if track already holds sessionPersonId (unless claimed by another face in this same frame)
          if (activeTrack.sessionPersonId != null &&
              !claimedSessionPersonIdsInThisFrame.contains(activeTrack.sessionPersonId)) {
            final sid = activeTrack.sessionPersonId;
            matchedPerson = _sessionCountedPeople
                .where((p) => p.personId == sid)
                .firstOrNull;
          }

          // 2. Multi-Signal Biometric Deduplication against all people counted in this kiosk session
          if (matchedPerson == null) {
            double highestScore = 0.0;
            _SessionCountedPerson? bestCandidate;

            // A. Ultra-Fast Vector Cosine Similarity matching (scale, translation, and lighting robust)
            if (liveVec != null) {
              for (final person in _sessionCountedPeople) {
                if (claimedSessionPersonIdsInThisFrame.contains(person.personId)) continue;
                for (final storedVec in person.vectors) {
                  final sim = CctvNativeFaceEngine.cosineSimilarity(liveVec, storedVec);
                  if (sim > highestScore) {
                    highestScore = sim;
                    // For the same individual across angles, cosine similarity is >= 50.0%
                    if (sim >= 50.0) {
                      bestCandidate = person;
                    }
                  }
                }
              }
            }

            // B. String template matching fallback if vector did not match
            if (bestCandidate == null && liveTemplate != null && liveTemplate.isNotEmpty) {
              for (final person in _sessionCountedPeople) {
                if (claimedSessionPersonIdsInThisFrame.contains(person.personId)) continue;
                for (final storedTpl in person.templates) {
                  if (storedTpl.isNotEmpty) {
                    final matchRes = _biometricService.matchFace(
                      liveTemplate: liveTemplate,
                      enrolledTemplate: storedTpl,
                      threshold: 62.0,
                    );
                    if (matchRes.similarityScore > highestScore) {
                      highestScore = matchRes.similarityScore;
                      if (matchRes.similarityScore >= 62.0) {
                        bestCandidate = person;
                      }
                    }
                  }
                }
              }
            }

            if (bestCandidate != null) {
              matchedPerson = bestCandidate;
            }
          }

          if (matchedPerson != null) {
            // Already counted in this kiosk session! Update observation, DO NOT increment headcount
            matchedPerson.addObservation(liveTemplate ?? '', liveVec, now);
            activeTrack.sessionPersonId = matchedPerson.personId;
            claimedSessionPersonIdsInThisFrame.add(matchedPerson.personId);
          } else {
            // Brand new unique human seen for the first time in this session
            final newId = _nextSessionPersonId++;
            _sessionCountedPeople.add(_SessionCountedPerson(
              personId: newId,
              initialTemplate: liveTemplate ?? '',
              initialVector: liveVec,
              firstSeen: now,
              lastSeen: now,
            ));
            activeTrack.sessionPersonId = newId;
            claimedSessionPersonIdsInThisFrame.add(newId);
          }

          final visitorTag = isAttendanceSuspended
              ? '👤 Unknown Visitor • Attendance OFF'
              : '👤 Unknown Visitor • Unregistered';
          trackedList.add(CctvTrackedFace(
            boundingBox: rect,
            frameWidth: imgW,
            frameHeight: imgH,
            confidence: face.confidence,
            blurScore: face.blurScore,
            isLiveFace: true,
            isMatched: false,
            isUnknownVisitor: true,
            statusTag: visitorTag,
            livenessScore: face.livenessScore,
          ));
        }
      }

      liveInFramePeopleCount = enablePeopleCounting ? trackedList.length : 0;
      if (!_peopleCountController.isClosed) {
        _peopleCountController.add((
          liveCount: liveInFramePeopleCount,
          totalCount: totalSessionPeopleCount,
        ));
      }

      _trackedFacesController.add(trackedList);
      return trackedList;
    } catch (e) {
      debugPrint('[CctvAttendanceEngine] processFrame error: $e');
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  /// Auto-saves attendance record to repository and database
  Future<void> _autoMarkAttendance(
    StudentAttendance student,
    String status,
    double matchConfidence,
    DateTime now, {
    bool isCheckOut = false,
    bool isReEntry = false,
    bool isPeriod = false,
    String? cameraName,
  }) async {
    if (isAttendanceSuspended) {
      debugPrint('[CctvAttendanceEngine] GUARD: Attendance is suspended! Auto-mark aborted.');
      return;
    }
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('hh:mm:ss a').format(now);
    final cam = cameraName ?? currentCameraName;

    final String eventRemarks;
    final String eventStatus;
    if (isPeriod) {
      eventRemarks = 'CCTV Face AI [$cam] Period $currentPeriodNumber (${matchConfidence.toStringAsFixed(1)}%)';
      eventStatus = 'Period $currentPeriodNumber • $status';
    } else if (isReEntry) {
      eventRemarks = 'CCTV Face AI [$cam] Re-Entered (Temporary exit cleared) (${matchConfidence.toStringAsFixed(1)}%)';
      eventStatus = 'Re-Entered';
    } else if (isCheckOut) {
      eventRemarks = 'CCTV Face AI [$cam] Stepped Out (${matchConfidence.toStringAsFixed(1)}%)';
      eventStatus = 'Check-Out';
    } else {
      eventRemarks = 'CCTV Face AI [$cam] Check-In (${matchConfidence.toStringAsFixed(1)}%)';
      eventStatus = status; // 'Present' or 'Late'
    }

    final event = CctvAttendanceEvent(
      studentId: student.id,
      studentName: student.fullName,
      grNo: student.grNo ?? '',
      className: student.className,
      photoPath: student.photoPath,
      timestamp: now,
      status: eventStatus,
      matchConfidence: matchConfidence,
      remarks: eventRemarks,
      cameraName: cam,
    );

    recentActivityFeed.insert(0, event);
    if (recentActivityFeed.length > 50) {
      recentActivityFeed.removeLast();
    }
    _attendanceEventController.add(event);

    // Audio & Speech announcement
    if (enableAudioVoice) {
      final audioType = isPeriod ? 'period' : (isReEntry ? 're_entry' : (isCheckOut ? 'out' : status));
      _playAudioAnnouncement(student.fullName, audioType);
    }

    try {
      if (isPeriod) {
        // 1. Save period attendance
        await repository.saveSinglePeriodAttendance(
          studentId: student.id,
          classId: student.className,
          periodId: currentPeriodId,
          periodNumber: currentPeriodNumber,
          date: dateStr,
          status: status,
          time: timeStr,
          remarks: eventRemarks,
        );

        // 2. Cross-Period to Gate Attendance Auto-Bridging:
        // If student missed gate scan on arrival, period attendance becomes Shift Check-IN!
        // If already checked in, latest period scan becomes Shift Check-OUT!
        final sShift = student.shiftId.isNotEmpty ? student.shiftId : (currentShiftId ?? 'main');
        final sKey = '${student.id}_${dateStr}_$sShift';
        final hasGateIn = _markedInRecords.containsKey(sKey) ||
            (student.checkInTime.isNotEmpty && student.status != null && student.status != 'Absent');

        if (!hasGateIn) {
          student.checkInTime = timeStr;
          student.status = 'Present';
          final bridgeRemarks = 'Auto-bridged from Period $currentPeriodNumber [$cam]';
          student.remarks = bridgeRemarks;
          student.verificationMethod = 'CCTV Face AI (Period)';
          _markedInRecords[sKey] = timeStr;
          _checkInTimestamps[student.id] = now;
          _studentInsideState[student.id] = true;
          _lastMovementActionTime[student.id] = now;

          await repository.saveSingleStudentAttendance(
            studentId: student.id,
            date: dateStr,
            status: 'Present',
            remarks: bridgeRemarks,
            checkInTime: timeStr,
            checkOutTime: student.checkOutTime,
            verificationMethod: 'CCTV Face AI (Period-Bridged)',
            shiftId: currentShiftId,
            shiftName: currentShiftName,
          );
        } else {
          // Update check_out_time to latest period scan time
          student.checkOutTime = timeStr;
          _markedOutRecords[sKey] = timeStr;
          await repository.saveSingleStudentAttendance(
            studentId: student.id,
            date: dateStr,
            status: student.status ?? 'Present',
            remarks: 'CCTV Face AI Updated from Period $currentPeriodNumber [$cam]',
            checkInTime: student.checkInTime,
            checkOutTime: timeStr,
            verificationMethod: 'CCTV Face AI (Period-Bridged)',
            shiftId: currentShiftId,
            shiftName: currentShiftName,
          );
        }
      } else {
        if (isReEntry) {
          // Re-entry: clear temporary exit time so student remains present without an exit time
          student.checkOutTime = '';
          student.remarks = eventRemarks;
          if (student.status == null || student.status!.isEmpty || student.status == 'Absent') {
            student.status = 'Present';
          }
        } else if (isCheckOut) {
          student.checkOutTime = timeStr;
          student.remarks = eventRemarks;
          if (student.status == null || student.status!.isEmpty || student.status == 'Absent') {
            student.status = 'Present';
          }
        } else {
          student.status = status;
          student.checkInTime = timeStr;
          student.remarks = eventRemarks;
        }
        student.verificationMethod = 'CCTV Face AI';
        if (currentShiftId != null) student.shiftId = currentShiftId!;
        if (currentShiftName != null) student.shiftName = currentShiftName!;

        // Save single student update (clearing checkOutTime if isReEntry)
        await repository.saveSingleStudentAttendance(
          studentId: student.id,
          date: dateStr,
          status: student.status ?? 'Present',
          remarks: eventRemarks,
          checkInTime: student.checkInTime,
          checkOutTime: student.checkOutTime,
          verificationMethod: 'CCTV Face AI',
          shiftId: currentShiftId,
          shiftName: currentShiftName,
        );

        // Batch sync for UI lists
        await repository.saveStudentAttendance(
          className: student.className,
          date: dateStr,
          attendanceList: [student],
          shiftId: currentShiftId,
          shiftName: currentShiftName,
        );
      }
    } catch (e) {
      debugPrint('[CctvAttendanceEngine] Auto-save error: $e');
    }
  }

  /// Plays system chime and native Windows Speech voice announcement
  void _playAudioAnnouncement(String studentName, String actionType) {
    try {
      if (Platform.isWindows) {
        final cleanName = studentName.replaceAll("'", '').replaceAll('"', '');
        final String speakText;
        if (actionType == 'out' || actionType == 'check_out') {
          speakText = 'Exit recorded. Goodbye, $cleanName.';
        } else if (actionType == 're_entry') {
          speakText = 'Welcome back, $cleanName.';
        } else if (actionType == 'period') {
          speakText = 'Attendance marked. Welcome, $cleanName.';
        } else {
          speakText = 'Attendance marked. Welcome, $cleanName.';
        }
        Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '[System.Media.SystemSounds]::Asterisk.Play(); \$s = New-Object -ComObject SAPI.SpVoice; \$s.Rate = 1; \$s.Speak("$speakText")',
        ]).catchError((_) => ProcessResult(0, 0, '', ''));
      }
    } catch (_) {}
  }

  void dispose() {
    resetPeopleCount();
    clearActiveTracks();
    _trackedFacesController.close();
    _attendanceEventController.close();
    _peopleCountController.close();
  }
}
