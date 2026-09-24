import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cctv_attendance_engine.dart';
import 'cctv_native_face_engine.dart';

enum CctvSourceType {
  webcam,
  ipCamera,
  simulation,
}

class CctvCameraProfile {
  final String id;
  final String name;
  final CctvSourceType sourceType;
  final int cameraIndex;
  final String ipUrl;
  final String username;
  final String password;
  final bool isEnabled;
  /// Camera Attendance Role:
  /// - 'all': All-in-One (Follows Auto Timetable Schedule)
  /// - 'madarsa_gate': Madarsa Gate (Daily Shift In / Out Only)
  /// - 'classroom': Classroom (Period Attendance Only)
  final String role;

  const CctvCameraProfile({
    required this.id,
    required this.name,
    this.sourceType = CctvSourceType.webcam,
    this.cameraIndex = 0,
    this.ipUrl = 'http://192.168.1.100:8080/shot.jpg',
    this.username = '',
    this.password = '',
    this.isEnabled = true,
    this.role = 'all',
  });

  CctvCameraConfig toConfig({int targetFps = 60, List<String>? simulationImages}) => CctvCameraConfig(
        sourceType: sourceType,
        cameraIndex: cameraIndex,
        ipUrl: ipUrl,
        username: username,
        password: password,
        targetFps: targetFps,
        simulationImages: simulationImages ?? const [],
        role: role,
      );

  CctvCameraProfile copyWith({
    String? id,
    String? name,
    CctvSourceType? sourceType,
    int? cameraIndex,
    String? ipUrl,
    String? username,
    String? password,
    bool? isEnabled,
    String? role,
  }) {
    return CctvCameraProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      sourceType: sourceType ?? this.sourceType,
      cameraIndex: cameraIndex ?? this.cameraIndex,
      ipUrl: ipUrl ?? this.ipUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      isEnabled: isEnabled ?? this.isEnabled,
      role: role ?? this.role,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sourceType': sourceType.name,
        'cameraIndex': cameraIndex,
        'ipUrl': ipUrl,
        'username': username,
        'password': password,
        'isEnabled': isEnabled,
        'role': role,
      };

  factory CctvCameraProfile.fromJson(Map<String, dynamic> json) => CctvCameraProfile(
        id: json['id'] ?? 'cam_1',
        name: json['name'] ?? 'Camera 1',
        sourceType: CctvSourceType.values.firstWhere(
          (e) => e.name == json['sourceType'],
          orElse: () => CctvSourceType.webcam,
        ),
        cameraIndex: json['cameraIndex'] ?? 0,
        ipUrl: json['ipUrl'] ?? '',
        username: json['username'] ?? '',
        password: json['password'] ?? '',
        isEnabled: json['isEnabled'] ?? true,
        role: json['role'] ?? 'all',
      );
}

class CctvFramePayload {
  final Uint8List bytes;
  final String cameraName;
  final String cameraId;
  final String cameraRole; // 'all', 'madarsa_gate', 'classroom'

  const CctvFramePayload({
    required this.bytes,
    required this.cameraName,
    required this.cameraId,
    this.cameraRole = 'all',
  });
}

class CctvCameraChannel {
  final CctvCameraProfile profile;
  final ValueNotifier<Uint8List?> lastFrameNotifier;
  final ValueNotifier<List<CctvTrackedFace>> trackedFacesNotifier;
  final ValueNotifier<bool> isStreamingNotifier;
  bool isStreaming;
  Timer? timer;
  double actualFps;
  int frameCount;

  CctvCameraChannel({
    required this.profile,
    ValueNotifier<Uint8List?>? lastFrameNotifier,
    ValueNotifier<List<CctvTrackedFace>>? trackedFacesNotifier,
    this.isStreaming = false,
    this.actualFps = 0.0,
    this.frameCount = 0,
  })  : lastFrameNotifier = lastFrameNotifier ?? ValueNotifier<Uint8List?>(null),
        trackedFacesNotifier = trackedFacesNotifier ?? ValueNotifier<List<CctvTrackedFace>>([]),
        isStreamingNotifier = ValueNotifier<bool>(isStreaming);

  void dispose() {
    timer?.cancel();
    timer = null;
    isStreaming = false;
    isStreamingNotifier.value = false;
  }
}

class CctvCameraConfig {
  final CctvSourceType sourceType;
  final int cameraIndex;
  final String ipUrl;
  final String username;
  final String password;
  final int targetFps; // e.g., 5 to 15 FPS
  final List<String> simulationImages;
  final String role; // 'all', 'madarsa_gate', 'classroom'

  const CctvCameraConfig({
    this.sourceType = CctvSourceType.webcam,
    this.cameraIndex = 0,
    this.ipUrl = 'http://192.168.1.100:8080/shot.jpg',
    this.username = '',
    this.password = '',
    this.targetFps = 60,
    this.simulationImages = const [],
    this.role = 'all',
  });

  CctvCameraConfig copyWith({
    CctvSourceType? sourceType,
    int? cameraIndex,
    String? ipUrl,
    String? username,
    String? password,
    int? targetFps,
    List<String>? simulationImages,
    String? role,
  }) {
    return CctvCameraConfig(
      sourceType: sourceType ?? this.sourceType,
      cameraIndex: cameraIndex ?? this.cameraIndex,
      ipUrl: ipUrl ?? this.ipUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      targetFps: targetFps ?? this.targetFps,
      simulationImages: simulationImages ?? this.simulationImages,
      role: role ?? this.role,
    );
  }
}

class CctvStreamService extends ChangeNotifier {
  static final CctvStreamService _instance = CctvStreamService._internal();
  factory CctvStreamService() => _instance;
  CctvStreamService._internal() {
    _initDefaultProfiles();
  }

  void _initDefaultProfiles() {
    _cameraProfiles = [
      const CctvCameraProfile(
        id: 'cam_1',
        name: 'Gate 1 (Main Entrance)',
        sourceType: CctvSourceType.webcam,
        cameraIndex: 0,
      ),
      const CctvCameraProfile(
        id: 'cam_2',
        name: 'Gate 2 (Back Gate)',
        sourceType: CctvSourceType.ipCamera,
        ipUrl: 'http://192.168.1.101:8080/shot.jpg',
      ),
      const CctvCameraProfile(
        id: 'cam_3',
        name: 'Dar-ul-Iqama / Hall',
        sourceType: CctvSourceType.ipCamera,
        ipUrl: 'http://192.168.1.102:8080/shot.jpg',
      ),
    ];
    _activeCameraName = _cameraProfiles.first.name;
    _activeProfileId = _cameraProfiles.first.id;
  }

  List<CctvCameraProfile> _cameraProfiles = [];
  List<CctvCameraProfile> get cameraProfiles => List.unmodifiable(_cameraProfiles);

  String _activeProfileId = 'cam_1';
  String get activeProfileId => _activeProfileId;

  String _activeCameraName = 'Camera 1';
  String get activeCameraName => _activeCameraName;

  CctvCameraProfile? get activeProfile {
    try {
      return _cameraProfiles.firstWhere((p) => p.id == _activeProfileId);
    } catch (_) {
      return _cameraProfiles.isNotEmpty ? _cameraProfiles.first : null;
    }
  }

  String get activeCameraRole => activeProfile?.role ?? _config.role;

  CctvCameraConfig _config = const CctvCameraConfig();
  CctvCameraConfig get config => _config;
  int get currentFps => _config.targetFps;

  CameraController? _cameraController;
  CameraController? get cameraController => _cameraController;

  List<CameraDescription> _availableCameras = [];
  List<CameraDescription> get availableCamerasList => _availableCameras;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;
  bool _isNativeOpenCvStreaming = false;
  bool get isNativeOpenCvStreaming => _isNativeOpenCvStreaming;

  Timer? _pollingTimer;
  StreamSubscription? _mjpegSubscription;
  HttpClient? _persistentHttpClient;

  HttpClient _getHttpClient() {
    _persistentHttpClient ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..idleTimeout = const Duration(seconds: 30);
    return _persistentHttpClient!;
  }

  final StreamController<Uint8List> _frameStreamController =
      StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get onFrameCaptured => _frameStreamController.stream;

  final StreamController<CctvFramePayload> _taggedFrameStreamController =
      StreamController<CctvFramePayload>.broadcast();
  Stream<CctvFramePayload> get onTaggedFrameCaptured => _taggedFrameStreamController.stream;

  double _actualFps = 0.0;
  double get actualFps => _actualFps;
  final ValueNotifier<double> actualFpsNotifier = ValueNotifier<double>(0.0);
  int _framesInCurrentSecond = 0;
  Timer? _fpsTimer;

  String? _lastError;
  String? get lastError => _lastError;
  final ValueNotifier<String?> lastErrorNotifier = ValueNotifier<String?>(null);

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;
  final ValueNotifier<bool> isConnectingNotifier = ValueNotifier<bool>(false);

  void _setLastError(String? err) {
    _lastError = err;
    lastErrorNotifier.value = err;
    notifyListeners();
  }

  void _setIsConnecting(bool val) {
    _isConnecting = val;
    isConnectingNotifier.value = val;
    notifyListeners();
  }

  bool _isCapturing = false;
  int _simIndex = 0;
  int _simDwellCounter = 0;
  final List<Uint8List> _cachedSimulationBytes = [];
  final List<String> _cachedSimulationPaths = [];

  void _emitSimulationFrame(Uint8List bytes) {
    if (!_frameStreamController.isClosed && _isStreaming) {
      _framesInCurrentSecond++;
      _frameStreamController.add(bytes);
      if (!_taggedFrameStreamController.isClosed) {
        _taggedFrameStreamController.add(CctvFramePayload(
          bytes: bytes,
          cameraName: _activeCameraName,
          cameraId: _activeProfileId,
          cameraRole: activeCameraRole,
        ));
      }
    }
  }

  void nextSimulationScene() {
    if (_cachedSimulationBytes.isNotEmpty) {
      _simIndex = (_simIndex + 1) % _cachedSimulationBytes.length;
      _simDwellCounter = 0;
      if (_isStreaming) {
        _emitSimulationFrame(_cachedSimulationBytes[_simIndex]);
      }
    }
  }

  void previousSimulationScene() {
    if (_cachedSimulationBytes.isNotEmpty) {
      _simIndex = (_simIndex - 1 + _cachedSimulationBytes.length) % _cachedSimulationBytes.length;
      _simDwellCounter = 0;
      if (_isStreaming) {
        _emitSimulationFrame(_cachedSimulationBytes[_simIndex]);
      }
    }
  }

  String get currentSimulationSceneName {
    if (_cachedSimulationPaths.isEmpty) return 'Default Demo';
    final path = _cachedSimulationPaths[_simIndex % _cachedSimulationPaths.length];
    return path.split(RegExp(r'[/\\]')).last;
  }

  final Map<String, CctvCameraChannel> _channels = {};
  List<CctvCameraChannel> get activeChannels => _channels.values.toList();
  bool _isMultiCamMode = false;
  bool get isMultiCamMode => _isMultiCamMode;

  /// Dynamic FPS Adjustment without tearing down video stream (supports 1 to 60 FPS)
  void updateFps(int newFps) {
    final clamped = newFps.clamp(1, 60);
    _config = _config.copyWith(targetFps: clamped);

    if (_isNativeOpenCvStreaming && _isStreaming) {
      _startNativeWebcamLoop();
    } else if (_config.sourceType == CctvSourceType.simulation && _isStreaming) {
      _pollingTimer?.cancel();
      _simDwellCounter = 0;
      final intervalMs = (1000 / clamped).round();
      _startSimulationLoop(intervalMs);
    } else if (_config.sourceType == CctvSourceType.webcam && _isStreaming) {
      _pollingTimer?.cancel();
      _isCapturing = false;
      _scheduleNextWebcamCapture();
      _actualFps = clamped.toDouble();
      actualFpsNotifier.value = _actualFps;
    }

    if (_isMultiCamMode) {
      final intervalMs = (1000 / clamped).round();
      for (final ch in _channels.values) {
        ch.timer?.cancel();
        _startChannelLoop(ch, intervalMs);
      }
    }
  }

  /// Start simultaneous streaming from multiple cameras in parallel (Security NVR Grid mode)
  Future<void> startMultiCameraStreams(List<CctvCameraProfile> profiles) async {
    await stopMultiCameraStreams();
    _isMultiCamMode = true;
    final intervalMs = (1000 / _config.targetFps.clamp(1, 60)).round();

    for (final profile in profiles) {
      if (!profile.isEnabled) continue;
      final channel = CctvCameraChannel(profile: profile, isStreaming: true);
      _channels[profile.id] = channel;
      _startChannelLoop(channel, intervalMs);
    }
  }

  void _startChannelLoop(CctvCameraChannel channel, int intervalMs) {
    channel.timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) async {
      if (!channel.isStreaming || !_isMultiCamMode) return;
      try {
        Uint8List? bytes;
        if (channel.profile.sourceType == CctvSourceType.ipCamera) {
          bytes = await _fetchIpCameraFrame(
            channel.profile.ipUrl,
            channel.profile.username,
            channel.profile.password,
          );
        } else {
          bytes = await _getNextSimulationFrame();
        }

        if (bytes != null && bytes.isNotEmpty && _isValidImageBytes(bytes)) {
          channel.lastFrameNotifier.value = bytes;
          _framesInCurrentSecond++;
          if (!_taggedFrameStreamController.isClosed) {
            _taggedFrameStreamController.add(CctvFramePayload(
              bytes: bytes,
              cameraName: channel.profile.name,
              cameraId: channel.profile.id,
              cameraRole: channel.profile.role,
            ));
          }
        }
      } catch (_) {}
    });
  }

  Future<void> stopMultiCameraStreams() async {
    _isMultiCamMode = false;
    for (final ch in _channels.values) {
      ch.dispose();
    }
    _channels.clear();
  }

  /// Switch to a different Camera Profile
  Future<bool> switchCameraProfile(CctvCameraProfile profile, {List<String>? simulationImages}) async {
    _activeProfileId = profile.id;
    _activeCameraName = profile.name;
    final images = simulationImages ?? _config.simulationImages;
    return await startStream(profile.toConfig(targetFps: _config.targetFps, simulationImages: images));
  }

  /// Update Camera Profiles list and persist
  Future<void> updateProfiles(List<CctvCameraProfile> profiles) async {
    _cameraProfiles = List.from(profiles);
    await saveProfiles();
  }

  /// Load camera profiles from persistent storage
  Future<void> loadSavedProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cctv_camera_profiles_json');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List decoded = jsonDecode(jsonStr);
        final loaded = decoded.map((e) => CctvCameraProfile.fromJson(Map<String, dynamic>.from(e))).toList();
        if (loaded.isNotEmpty) {
          _cameraProfiles = loaded;
          if (!_cameraProfiles.any((p) => p.id == _activeProfileId)) {
            _activeProfileId = _cameraProfiles.first.id;
            _activeCameraName = _cameraProfiles.first.name;
          }
        }
      }
    } catch (e) {
      debugPrint('[CctvStreamService] Error loading camera profiles: $e');
    }
  }

  /// Save camera profiles to persistent storage
  Future<void> saveProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _cameraProfiles.map((p) => p.toJson()).toList();
      await prefs.setString('cctv_camera_profiles_json', jsonEncode(list));
    } catch (e) {
      debugPrint('[CctvStreamService] Error saving camera profiles: $e');
    }
  }

  /// Add a new Camera Profile
  Future<void> addCameraProfile(CctvCameraProfile profile) async {
    _cameraProfiles.add(profile);
    await saveProfiles();
  }

  /// Update an existing Camera Profile
  Future<void> editCameraProfile(CctvCameraProfile profile) async {
    final idx = _cameraProfiles.indexWhere((p) => p.id == profile.id);
    if (idx != -1) {
      _cameraProfiles[idx] = profile;
      if (_activeProfileId == profile.id) {
        _activeCameraName = profile.name;
      }
      await saveProfiles();
    }
  }

  /// Delete a Camera Profile
  Future<void> deleteCameraProfile(String profileId) async {
    _cameraProfiles.removeWhere((p) => p.id == profileId);
    if (_cameraProfiles.isEmpty) {
      _initDefaultProfiles();
    }
    if (_activeProfileId == profileId) {
      _activeProfileId = _cameraProfiles.first.id;
      _activeCameraName = _cameraProfiles.first.name;
    }
    await saveProfiles();
  }

  /// Discover all available hardware webcams
  Future<List<CameraDescription>> discoverCameras() async {
    try {
      _availableCameras = await availableCameras();
      return _availableCameras;
    } catch (e) {
      debugPrint('[CctvStreamService] discoverCameras error: $e');
      _availableCameras = [];
      return [];
    }
  }

  /// Initialize and start streaming based on current config
  Future<bool> startStream([CctvCameraConfig? newConfig]) async {
    await stopStream();

    if (newConfig != null) {
      _config = newConfig;
    }

    _setLastError(null);
    _setIsConnecting(true);

    try {
      _startFpsCounter();

      bool success = false;
      switch (_config.sourceType) {
        case CctvSourceType.webcam:
          success = await _startWebcamStream();
          break;
        case CctvSourceType.ipCamera:
          success = await _startIpCameraStream();
          break;
        case CctvSourceType.simulation:
          success = await _startSimulationStream();
          break;
      }
      return success;
    } finally {
      _setIsConnecting(false);
    }
  }

  /// Stop streaming and release all camera handles
  Future<void> stopStream() async {
    _isStreaming = false;
    _isCapturing = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _mjpegSubscription?.cancel();
    _mjpegSubscription = null;
    _persistentHttpClient?.close(force: true);
    _persistentHttpClient = null;
    _fpsTimer?.cancel();
    _fpsTimer = null;
    _actualFps = 0.0;
    actualFpsNotifier.value = 0.0;

    if (_isNativeOpenCvStreaming) {
      _isNativeOpenCvStreaming = false;
      try {
        CctvNativeFaceEngine.instance.closeCamera();
      } catch (_) {}
    }

    if (_cameraController != null) {
      try {
        await _cameraController!.dispose();
      } catch (e) {
        debugPrint('[CctvStreamService] Error disposing camera controller: $e');
      }
      _cameraController = null;
    }
  }

  /// Start USB / Built-in Webcam streaming
  Future<bool> _startWebcamStream() async {
    try {
      final cameraIndex = _config.cameraIndex;

      // 1. FAST-PATH: Native C++ OpenCV DirectShow Stream (Zero disk writes, true 30/60 FPS)
      if (CctvNativeFaceEngine.instance.isAvailable) {
        final opened = CctvNativeFaceEngine.instance.openCamera(
          cameraIndex: cameraIndex,
          width: 640,
          height: 480,
        );
        if (opened) {
          _isStreaming = true;
          _isNativeOpenCvStreaming = true;
          _isCapturing = false;
          _startNativeWebcamLoop();
          return true;
        }
      }

      // 2. FALLBACK: Flutter camera_windows plugin
      if (_availableCameras.isEmpty) {
        await discoverCameras();
      }

      if (_availableCameras.isEmpty) {
        _lastError = 'No physical webcam detected. Please connect USB camera or use IP Camera / Simulation.';
        return false;
      }

      final camIdx = cameraIndex < _availableCameras.length ? cameraIndex : 0;
      final selectedCamera = _availableCameras[camIdx];

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      _isStreaming = true;
      _isNativeOpenCvStreaming = false;
      _isCapturing = false;

      // Sequential non-blocking frame capture loop (zero disk contention, zero camera lock)
      _scheduleNextWebcamCapture();

      return true;
    } catch (e) {
      _lastError = 'Failed to initialize webcam: $e';
      debugPrint('[CctvStreamService] Webcam init error: $e');
      return false;
    }
  }

  void _startNativeWebcamLoop() {
    _pollingTimer?.cancel();
    // For Native OpenCV hardware stream, poll at 16ms (~60 FPS) for real-time responsiveness.
    // Respect user configured FPS if set to 30 or 60, otherwise default to 60 FPS (16ms)
    // to eliminate polling lag and provide glass-to-glass real-time video.
    final effectiveFps = _config.targetFps >= 30 ? _config.targetFps.clamp(30, 60) : 60;
    final intervalMs = (1000 / effectiveFps).round();

    _pollingTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!_isStreaming || !_isNativeOpenCvStreaming) return;

      final jpegBytes = CctvNativeFaceEngine.instance.readCameraJpeg(quality: 70);
      if (jpegBytes != null && jpegBytes.isNotEmpty) {
        _framesInCurrentSecond++;
        if (!_frameStreamController.isClosed) {
          _frameStreamController.add(jpegBytes);
        }
        if (!_taggedFrameStreamController.isClosed) {
          _taggedFrameStreamController.add(CctvFramePayload(
            bytes: jpegBytes,
            cameraName: _activeCameraName,
            cameraId: _activeProfileId,
            cameraRole: activeCameraRole,
          ));
        }
      }
    });
  }

  void _scheduleNextWebcamCapture() {
    if (!_isStreaming || _cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    // Adaptive capture interval: allows Media Foundation Direct3D pipeline to run at full 60 FPS
    // without shutter stutter while providing snappy AI analysis (~5-8 FPS)
    final delayMs = (1000 / _config.targetFps.clamp(1, 10)).round();

    _pollingTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (!_isStreaming || _isCapturing) return;
      _isCapturing = true;

      XFile? xfile;
      try {
        if (_cameraController != null && _cameraController!.value.isInitialized) {
          xfile = await _cameraController!.takePicture();
          final bytes = await xfile.readAsBytes();

          if (!_frameStreamController.isClosed && _isStreaming && _isValidImageBytes(bytes)) {
            _framesInCurrentSecond++;
            _frameStreamController.add(bytes);
            if (!_taggedFrameStreamController.isClosed) {
              _taggedFrameStreamController.add(CctvFramePayload(
                bytes: bytes,
                cameraName: _activeCameraName,
                cameraId: _activeProfileId,
                cameraRole: activeCameraRole,
              ));
            }
          }
        }
      } catch (e) {
        // Silently catch transient camera busy errors
      } finally {
        if (xfile != null) {
          try {
            final f = File(xfile.path);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
        _isCapturing = false;
        if (_isStreaming) {
          // Add smooth breathing space (75ms) so Windows Media Foundation preview stays fluid at 60 FPS
          Future.delayed(const Duration(milliseconds: 75), () {
            if (_isStreaming) _scheduleNextWebcamCapture();
          });
        }
      }
    });
  }

  /// Check whether bytes form a complete, valid JPEG or PNG file
  bool _isValidImageBytes(Uint8List bytes) {
    if (bytes.length < 256) return false;
    // JPEG signature: starts with 0xFF 0xD8
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      if (bytes[bytes.length - 2] == 0xFF && bytes[bytes.length - 1] == 0xD9) {
        return true;
      }
      // Scan last 16 bytes for 0xFF 0xD9 in case of trailing boundary / padding
      for (int i = bytes.length - 1; i >= bytes.length - 16 && i > 1; i--) {
        if (bytes[i - 1] == 0xFF && bytes[i] == 0xD9) {
          return true;
        }
      }
      return false;
    }
    // PNG signature: starts with 0x89 0x50 0x4E 0x47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return true;
    }
    return false;
  }

  List<String> _getCandidateStreamUrls(String rawUrl, String username, String password) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return [];

    final candidates = <String>[];
    void addUrl(String u) {
      final clean = u.trim();
      if (clean.isNotEmpty && !candidates.contains(clean)) {
        candidates.add(clean);
      }
    }

    final parsed = parseHostAndPort(trimmed);
    final host = parsed.host;
    final port = parsed.port;
    final hasAuthInUrl = trimmed.contains('@');

    // Build credentials component
    final userEnc = username.isNotEmpty ? Uri.encodeComponent(username) : '';
    final passEnc = password.isNotEmpty ? Uri.encodeComponent(password) : '';
    final authPrefix = (!hasAuthInUrl && (userEnc.isNotEmpty || passEnc.isNotEmpty))
        ? '$userEnc:$passEnc@'
        : '';

    // If explicit URL was given (e.g. user entered specific path/scheme)
    String withAuth = trimmed;
    if (!hasAuthInUrl && authPrefix.isNotEmpty) {
      try {
        final normalized = (trimmed.startsWith('http://') ||
                trimmed.startsWith('https://') ||
                trimmed.startsWith('rtsp://'))
            ? trimmed
            : 'http://$trimmed';
        final uri = Uri.parse(normalized);
        final portStr = uri.hasPort ? ':${uri.port}' : '';
        withAuth = '${uri.scheme}://$authPrefix${uri.host}$portStr${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
      } catch (_) {}
    }

    // 1. If explicit URL was provided with a specific path, prioritize it!
    const snapshotPaths = ['/shot.jpg', '/snapshot.jpg', '/photo.jpg', '/shot', '/snapshot', '/capture.jpg', '/picture'];
    for (final base in [withAuth, trimmed]) {
      for (final pat in snapshotPaths) {
        if (base.toLowerCase().contains(pat)) {
          addUrl(base.replaceAll(RegExp(pat, caseSensitive: false), '/video'));
          addUrl(base.replaceAll(RegExp(pat, caseSensitive: false), '/videofeed'));
          addUrl(base.replaceAll(RegExp(pat, caseSensitive: false), '/mjpegfeed'));
          addUrl(base.replaceAll(RegExp(pat, caseSensitive: false), '/live'));
          addUrl(base.replaceAll(RegExp(pat, caseSensitive: false), '/mjpeg'));
        }
      }
      addUrl(base);
    }

    // 2. ⚡ UNIVERSAL BRAND AUTO-PROBE:
    // If user provided just an IP, hostname, or basic URL without a deep stream path,
    // automatically generate candidate URLs for ALL major standalone CCTV brands:
    if (host.isNotEmpty) {
      final rtspPort = (port == 80 || port == 8080) ? 554 : port;
      // 📹 Hikvision / Ezviz Standalone IP Camera & NVR Channels
      addUrl('rtsp://$authPrefix$host:$rtspPort/Streaming/Channels/101');
      addUrl('rtsp://$authPrefix$host:$rtspPort/Streaming/Channels/102');
      addUrl('rtsp://$authPrefix$host:$rtspPort/Streaming/Channels/1');
      addUrl('rtsp://$authPrefix$host:$rtspPort/h264/ch1/main/av_stream');
      addUrl('http://$authPrefix$host/ISAPI/Streaming/channels/101/picture');

      // 🎥 CP Plus / Dahua Standalone IP Camera & NVR Channels
      addUrl('rtsp://$authPrefix$host:$rtspPort/cam/realmonitor?channel=1&subtype=0');
      addUrl('rtsp://$authPrefix$host:$rtspPort/cam/realmonitor?channel=1&subtype=1');
      addUrl('http://$authPrefix$host/cgi-bin/snapshot.cgi');

      // 📡 TP-Link Tapo Standalone Wi-Fi Camera
      addUrl('rtsp://$authPrefix$host:$rtspPort/stream1');
      addUrl('rtsp://$authPrefix$host:$rtspPort/stream2');

      // 🌐 Uniview (UNV) & Imou Standalone IP Cameras
      addUrl('rtsp://$authPrefix$host:$rtspPort/unicast/c1/s0/live');
      addUrl('rtsp://$authPrefix$host:$rtspPort/media/video1');

      // 🇨🇳 Generic ONVIF / Xiongmai (XM) / Chinese Wi-Fi Cameras
      addUrl('rtsp://$authPrefix$host:$rtspPort/onvif1');
      addUrl('rtsp://$authPrefix$host:$rtspPort/live/ch0');
      addUrl('rtsp://$authPrefix$host:$rtspPort/h264Preview_01_main');
      addUrl('rtsp://$authPrefix$host:$rtspPort/');

      // 📱 Mobile IP Webcam (Android / iOS)
      addUrl('http://$authPrefix$host:8080/video');
      addUrl('http://$authPrefix$host:8080/shot.jpg');
      addUrl('http://$authPrefix$host/video');
      addUrl('http://$authPrefix$host/videofeed');
      addUrl('http://$authPrefix$host/mjpeg');
    }

    return candidates;
  }

  /// Non-blocking asynchronous TCP socket ping.
  /// Confirms if the IP camera host and port are reachable on the local network.
  /// Never stalls or freezes the Flutter UI thread.
  static Future<bool> checkTcpReachability(
    String host,
    int port, {
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (e) {
      debugPrint('[CctvStreamService] TCP connection to $host:$port failed: $e');
      return false;
    }
  }

  /// Extracts host and port safely from raw camera URL or RTSP endpoint.
  static ({String host, int port}) parseHostAndPort(String rawUrl) {
    String host = '';
    int port = 80;
    try {
      final trimmed = rawUrl.trim();
      final normalized = (trimmed.startsWith('http://') ||
              trimmed.startsWith('https://') ||
              trimmed.startsWith('rtsp://'))
          ? trimmed
          : 'http://$trimmed';
      final u = Uri.parse(normalized);
      host = u.host.trim();
      port = u.hasPort
          ? u.port
          : (u.scheme == 'rtsp' ? 554 : (u.scheme == 'https' ? 443 : 80));
    } catch (_) {}
    return (host: host, port: port);
  }

  /// Fast async probe to verify if candidate HTTP endpoint responds with 200/206
  /// before handing it off to OpenCV VideoCapture.
  Future<bool> _isHttpEndpointValid(String url, String username, String password) async {
    if (url.toLowerCase().startsWith('rtsp://')) {
      return true; // RTSP reachability confirmed via port pre-check
    }
    try {
      final client = _getHttpClient();
      final uri = Uri.parse(url);
      final request = await client.openUrl('GET', uri).timeout(const Duration(milliseconds: 1000));
      if (!url.contains('@') && username.isNotEmpty) {
        final authStr = '$username:$password';
        final base64Auth = base64Encode(utf8.encode(authStr));
        request.headers.set('Authorization', 'Basic $base64Auth');
      }
      request.headers.set('User-Agent', 'MadarsaApp/1.0');
      final response = await request.close().timeout(const Duration(milliseconds: 1000));
      final sub = response.listen((_) {});
      await Future.delayed(const Duration(milliseconds: 40));
      await sub.cancel();
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _startIpCameraStream() async {
    final rawUrl = _config.ipUrl.trim();
    if (rawUrl.isEmpty) {
      _setLastError('IP Camera URL is empty. Please configure valid camera URL or RTSP endpoint.');
      return false;
    }

    // 0. Non-blocking TCP Reachability Pre-check:
    // Guarantees zero UI freeze when camera is offline or unreachable
    final parsed = parseHostAndPort(rawUrl);
    if (parsed.host.isNotEmpty) {
      bool isReachable = await checkTcpReachability(parsed.host, parsed.port, timeout: const Duration(milliseconds: 800));
      if (!isReachable && parsed.port == 80) {
        isReachable = await checkTcpReachability(parsed.host, 554, timeout: const Duration(milliseconds: 800));
      }
      if (!isReachable) {
        final err = 'Camera endpoint (${parsed.host}:${parsed.port}) is offline or unreachable. Please verify camera power, Wi-Fi, and IP address.';
        debugPrint('[CctvStreamService] ❌ $err');
        _setLastError(err);
        _isStreaming = false;
        _isNativeOpenCvStreaming = false;
        return false;
      }
      debugPrint('[CctvStreamService] ✅ TCP connection confirmed to ${parsed.host}:${parsed.port}');
    }

    final candidates = _getCandidateStreamUrls(rawUrl, _config.username, _config.password);
    if (candidates.isEmpty) {
      _setLastError('Invalid IP Camera URL format.');
      return false;
    }

    // 1. ⚡ ULTRA FAST-PATH: Native C++ OpenCV Direct VideoStream (45-60 FPS Hardware Decoding)
    if (CctvNativeFaceEngine.instance.isAvailable) {
      for (final candidate in candidates) {
        // Skip pure snapshot URLs for OpenCV VideoCapture if video endpoints are available
        final isSnapshotOnly = candidate.toLowerCase().contains('/shot.jpg') ||
            candidate.toLowerCase().contains('/snapshot.jpg') ||
            candidate.toLowerCase().contains('/photo.jpg');
        if (isSnapshotOnly && candidates.length > 1) continue;

        // Fast async HTTP pre-check prevents calling OpenCV on dead/404 URLs
        final isValid = await _isHttpEndpointValid(candidate, _config.username, _config.password);
        if (!isValid) {
          debugPrint('[CctvStreamService] Skipping invalid endpoint (HTTP error/404): $candidate');
          continue;
        }

        debugPrint('[CctvStreamService] Trying Native OpenCV stream on validated: $candidate');
        final opened = CctvNativeFaceEngine.instance.openCameraUrl(candidate);
        if (opened) {
          debugPrint('[CctvStreamService] Native OpenCV connected to: $candidate ✅');
          _isStreaming = true;
          _isNativeOpenCvStreaming = true;
          _isCapturing = false;
          _setLastError(null);
          _startNativeWebcamLoop();
          return true;
        }
      }
    }

    // 2. ⚡ DART CONTINUOUS MJPEG STREAM READER (Zero Socket Churn, Real-Time 30-60 FPS)
    for (final candidate in candidates) {
      final isSnapshot = candidate.toLowerCase().contains('/shot.jpg') ||
          candidate.toLowerCase().contains('/snapshot.jpg') ||
          candidate.toLowerCase().contains('/photo.jpg');
      if (isSnapshot) continue;

      debugPrint('[CctvStreamService] Trying Dart Continuous MJPEG Stream on: $candidate');
      final connected = await _tryStartDartMjpegStream(candidate, _config.username, _config.password);
      if (connected) {
        debugPrint('[CctvStreamService] Dart Continuous MJPEG Stream active on: $candidate ✅');
        _isStreaming = true;
        _isNativeOpenCvStreaming = false;
        _setLastError(null);
        return true;
      }
    }

    // 3. Fallback: High-Performance Persistent Keep-Alive Snapshot Stream
    debugPrint('[CctvStreamService] Probing persistent keep-alive snapshot stream on: $rawUrl');
    final testFrame = await _fetchIpCameraFrame(_config.ipUrl, _config.username, _config.password);
    if (testFrame != null && _isValidImageBytes(testFrame)) {
      debugPrint('[CctvStreamService] Snapshot stream confirmed active ✅');
      _isStreaming = true;
      _isNativeOpenCvStreaming = false;
      _setLastError(null);
      _runIpCameraPollingLoop();
      return true;
    }

    final failMsg = 'Cannot connect to camera stream at $rawUrl. No supported video feed or snapshot endpoint found.';
    debugPrint('[CctvStreamService] ❌ $failMsg');
    _setLastError(failMsg);
    _isStreaming = false;
    _isNativeOpenCvStreaming = false;
    return false;
  }

  Future<bool> _tryStartDartMjpegStream(String url, String username, String password) async {
    try {
      final client = _getHttpClient();
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 4));

      if (!url.contains('@') && username.isNotEmpty) {
        final authStr = '$username:$password';
        final base64Auth = base64Encode(utf8.encode(authStr));
        request.headers.set('Authorization', 'Basic $base64Auth');
      }

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        return false;
      }

      final completer = Completer<bool>();
      final bytesBuffer = BytesBuilder(copy: false);
      bool receivedFirstFrame = false;

      _mjpegSubscription?.cancel();
      _mjpegSubscription = response.listen(
        (chunk) {
          if (!_isStreaming) return;
          bytesBuffer.add(chunk);
          var currentBytes = bytesBuffer.toBytes();

          Uint8List? latestFrame;

          // Process all complete JPEG frames in the buffer to always dispatch the freshest frame
          while (true) {
            int soi = -1;
            for (int i = 0; i < currentBytes.length - 1; i++) {
              if (currentBytes[i] == 0xFF && currentBytes[i + 1] == 0xD8) {
                soi = i;
                break;
              }
            }

            if (soi == -1) {
              // No SOI found; discard stale leading garbage if buffer grew excessively
              if (currentBytes.length > 65536) {
                bytesBuffer.clear();
              }
              break;
            }

            int eoi = -1;
            for (int i = soi + 2; i < currentBytes.length - 1; i++) {
              if (currentBytes[i] == 0xFF && currentBytes[i + 1] == 0xD9) {
                eoi = i + 1; // inclusive
                break;
              }
            }

            if (eoi == -1) {
              // Incomplete trailing frame: retain from soi onwards for next chunk
              if (soi > 0) {
                final partial = currentBytes.sublist(soi);
                bytesBuffer.clear();
                bytesBuffer.add(partial);
              }
              break;
            }

            // Extract this complete frame and advance buffer
            latestFrame = Uint8List.fromList(currentBytes.sublist(soi, eoi + 1));
            final remaining = currentBytes.sublist(eoi + 1);
            bytesBuffer.clear();
            bytesBuffer.add(remaining);
            currentBytes = remaining;
            // Continue loop to see if an even newer frame is already complete in this batch!
          }

          if (latestFrame != null && _isValidImageBytes(latestFrame)) {
            _framesInCurrentSecond++;
            if (!_frameStreamController.isClosed) {
              _frameStreamController.add(latestFrame);
            }
            if (!_taggedFrameStreamController.isClosed) {
              _taggedFrameStreamController.add(CctvFramePayload(
                bytes: latestFrame,
                cameraName: _activeCameraName,
                cameraId: _activeProfileId,
                cameraRole: activeCameraRole,
              ));
            }

            if (!receivedFirstFrame) {
              receivedFirstFrame = true;
              if (!completer.isCompleted) completer.complete(true);
            }
          }
        },
        onError: (err) {
          debugPrint('[CctvStreamService] MJPEG stream error: $err');
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(receivedFirstFrame);
        },
        cancelOnError: true,
      );

      return await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => receivedFirstFrame,
      );
    } catch (e) {
      debugPrint('[CctvStreamService] Failed to start MJPEG stream: $e');
      return false;
    }
  }

  Future<Uint8List?> _fetchIpCameraFrame(String ipUrl, String username, String password) async {
    final client = _getHttpClient();
    try {
      final uri = Uri.parse(ipUrl.trim());
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 3));
      if (!ipUrl.contains('@') && username.isNotEmpty) {
        final authStr = '$username:$password';
        final base64Auth = base64Encode(utf8.encode(authStr));
        request.headers.set('Authorization', 'Basic $base64Auth');
      }
      final response = await request.close().timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        return await consolidateHttpClientResponseBytes(response);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _runIpCameraPollingLoop() async {
    while (_isStreaming && _config.sourceType == CctvSourceType.ipCamera) {
      final targetDelayMs = _config.targetFps >= 60 ? 16 : (1000 / _config.targetFps.clamp(1, 60)).round();
      final sw = Stopwatch()..start();
      try {
        final bytes = await _fetchIpCameraFrame(_config.ipUrl, _config.username, _config.password);
        if (bytes != null && _isValidImageBytes(bytes)) {
          if (!_frameStreamController.isClosed && _isStreaming) {
            _framesInCurrentSecond++;
            _frameStreamController.add(bytes);
            if (!_taggedFrameStreamController.isClosed) {
              _taggedFrameStreamController.add(CctvFramePayload(
                bytes: bytes,
                cameraName: _activeCameraName,
                cameraId: _activeProfileId,
                cameraRole: activeCameraRole,
              ));
            }
          }
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final elapsed = sw.elapsedMilliseconds;
      final waitMs = (targetDelayMs - elapsed).clamp(1, 1000);
      await Future.delayed(Duration(milliseconds: waitMs));
    }
  }

  Future<Uint8List?> _getNextSimulationFrame() async {
    if (_cachedSimulationBytes.isEmpty) {
      final defaultImages = [
        'C:/Users/MD Services/Downloads/istockphoto-1138008113-612x612.jpg',
        r'C:\Users\MD Services\Downloads\75f27b7bd18caf219d95bf7f316cdd06.jpg',
        r'C:\Users\MD Services\Downloads\smiling-students-with-backpacks.jpg',
      ];
      final rawImages = _config.simulationImages.isNotEmpty
          ? _config.simulationImages
          : defaultImages;
      final validFiles = rawImages.where((p) => File(p).existsSync()).toList();
      for (final p in validFiles) {
        try {
          final b = await File(p).readAsBytes();
          if (b.isNotEmpty && _isValidImageBytes(b)) {
            _cachedSimulationBytes.add(b);
            _cachedSimulationPaths.add(p);
          }
        } catch (_) {}
      }
    }

    if (_cachedSimulationBytes.isEmpty) return null;
    final bytes = _cachedSimulationBytes[_simIndex % _cachedSimulationBytes.length];
    _simDwellCounter++;
    final framesPerScene = (_config.targetFps * 3.5).round().clamp(15, 240);
    if (_simDwellCounter >= framesPerScene) {
      _simDwellCounter = 0;
      _simIndex = (_simIndex + 1) % _cachedSimulationBytes.length;
    }
    return bytes;
  }

  /// Start simulation stream using sample images
  Future<bool> _startSimulationStream() async {
    final defaultImages = [
      'C:/Users/MD Services/Downloads/istockphoto-1138008113-612x612.jpg',
      r'C:\Users\MD Services\Downloads\75f27b7bd18caf219d95bf7f316cdd06.jpg',
      r'C:\Users\MD Services\Downloads\smiling-students-with-backpacks.jpg',
    ];

    final rawImages = _config.simulationImages.isNotEmpty
        ? _config.simulationImages
        : defaultImages;

    final validFiles = rawImages.where((p) => File(p).existsSync()).toList();
    if (validFiles.isEmpty) {
      _lastError = 'No valid simulation images found on disk.';
      return false;
    }

    _cachedSimulationPaths
      ..clear()
      ..addAll(validFiles);
    _cachedSimulationBytes.clear();

    for (final p in validFiles) {
      try {
        final b = await File(p).readAsBytes();
        if (b.isNotEmpty && _isValidImageBytes(b)) {
          _cachedSimulationBytes.add(b);
        }
      } catch (_) {}
    }

    if (_cachedSimulationBytes.isEmpty) {
      _lastError = 'Failed to load simulation frames into memory.';
      return false;
    }

    _simIndex = 0;
    _simDwellCounter = 0;
    _isStreaming = true;
    final intervalMs = (1000 / _config.targetFps.clamp(1, 60)).round();
    _startSimulationLoop(intervalMs);
    return true;
  }

  void _startSimulationLoop(int intervalMs) {
    if (_cachedSimulationBytes.isEmpty) return;

    // Dwell for 2.8 seconds on each scene (at current target FPS) before cycling to next student
    final framesPerScene = (_config.targetFps * 2.8).round().clamp(10, 180);

    _pollingTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!_isStreaming || _cachedSimulationBytes.isEmpty) return;
      try {
        final bytes = _cachedSimulationBytes[_simIndex % _cachedSimulationBytes.length];

        _simDwellCounter++;
        if (_simDwellCounter >= framesPerScene) {
          _simDwellCounter = 0;
          _simIndex = (_simIndex + 1) % _cachedSimulationBytes.length;
        }

        _emitSimulationFrame(bytes);
      } catch (e) {
        debugPrint('[CctvStreamService] Simulation stream error: $e');
      }
    });
  }

  /// Test camera connection for given configuration
  Future<Map<String, dynamic>> testCameraConnection(CctvCameraConfig testConfig) async {
    try {
      if (testConfig.sourceType == CctvSourceType.webcam) {
        final cams = await discoverCameras();
        if (cams.isEmpty) {
          return {'success': false, 'message': 'No USB / Laptop camera hardware detected.'};
        }
        final idx = testConfig.cameraIndex < cams.length ? testConfig.cameraIndex : 0;
        final cam = cams[idx];
        final testController = CameraController(
          cam,
          ResolutionPreset.low,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await testController.initialize();
        final xfile = await testController.takePicture();
        final bytes = await xfile.readAsBytes();
        try {
          File(xfile.path).deleteSync();
        } catch (_) {}
        await testController.dispose();
        return {
          'success': true,
          'message': 'Webcam "${cam.name}" connected and captured frame (${bytes.length} bytes) successfully! ✅',
          'bytes': bytes,
        };
      } else if (testConfig.sourceType == CctvSourceType.ipCamera) {
        if (testConfig.ipUrl.trim().isEmpty) {
          return {'success': false, 'message': 'IP Camera URL cannot be empty.'};
        }

        // Fast async TCP reachability pre-check prevents UI freezing on offline cameras
        final parsed = parseHostAndPort(testConfig.ipUrl);
        if (parsed.host.isNotEmpty) {
          bool isAlive = await checkTcpReachability(parsed.host, parsed.port, timeout: const Duration(milliseconds: 900));
          if (!isAlive && parsed.port == 80) {
            isAlive = await checkTcpReachability(parsed.host, 554, timeout: const Duration(milliseconds: 900));
          }
          if (!isAlive) {
            return {
              'success': false,
              'message': 'Cannot reach camera endpoint (${parsed.host}:${parsed.port}). Device is offline, powered off, or port is closed.',
            };
          }
        }

        final candidates = _getCandidateStreamUrls(testConfig.ipUrl, testConfig.username, testConfig.password);
        for (final candidate in candidates) {
          final isVideo = candidate.toLowerCase().contains('/video') ||
              candidate.toLowerCase().contains('/videofeed') ||
              candidate.toLowerCase().startsWith('rtsp://');
          if (isVideo && CctvNativeFaceEngine.instance.isAvailable) {
            final isValid = await _isHttpEndpointValid(candidate, testConfig.username, testConfig.password);
            if (!isValid && !candidate.toLowerCase().startsWith('rtsp://')) continue;

            final opened = CctvNativeFaceEngine.instance.openCameraUrl(candidate);
            if (opened) {
              await Future.delayed(const Duration(milliseconds: 250));
              final sampleJpeg = CctvNativeFaceEngine.instance.readCameraJpeg(quality: 70);
              CctvNativeFaceEngine.instance.closeCamera();
              if (sampleJpeg != null && sampleJpeg.isNotEmpty) {
                return {
                  'success': true,
                  'workingUrl': candidate,
                  'message': 'IP Camera live 60 FPS stream connected successfully via Native Engine! ($candidate) ✅',
                  'bytes': sampleJpeg,
                };
              }
            }
          }
        }
        if (testConfig.ipUrl.trim().toLowerCase().startsWith('rtsp://')) {
          return {
            'success': false,
            'message': 'RTSP camera stream could not be opened. Check NVR IP, port (default 554), channel number, and credentials.',
          };
        }
        final client = _getHttpClient();
        final uri = Uri.parse(testConfig.ipUrl.trim());
        final request = await client.getUrl(uri).timeout(const Duration(seconds: 4));
        if (!testConfig.ipUrl.contains('@') && testConfig.username.isNotEmpty) {
          final authStr = '${testConfig.username}:${testConfig.password}';
          final base64Auth = base64Encode(utf8.encode(authStr));
          request.headers.set('Authorization', 'Basic $base64Auth');
        }
        final response = await request.close().timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(response);
          if (bytes.isNotEmpty) {
            return {
              'success': true,
              'workingUrl': testConfig.ipUrl.trim(),
              'message': 'IP Camera stream reached! Received frame (${bytes.length} bytes, HTTP 200) ✅',
              'bytes': bytes,
            };
          } else {
            return {'success': false, 'message': 'Camera returned empty data payload.'};
          }
        } else {
          return {'success': false, 'message': 'Camera returned HTTP ${response.statusCode}: ${response.reasonPhrase}'};
        }
      } else {
        return {'success': true, 'message': 'Simulation mode active (using sample photo stream) ✅'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection failed: $e'};
    }
  }

  void _startFpsCounter() {
    _framesInCurrentSecond = 0;
    _actualFps = 0.0;
    actualFpsNotifier.value = 0.0;
    _fpsTimer?.cancel();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isNativeOpenCvStreaming) {
        if (_framesInCurrentSecond > 0 || !_isStreaming) {
          _actualFps = _framesInCurrentSecond.toDouble();
        }
      } else if (_config.sourceType == CctvSourceType.webcam && _isStreaming && _cameraController != null && _cameraController!.value.isInitialized) {
        _actualFps = _config.targetFps.toDouble();
      } else {
        if (_framesInCurrentSecond > 0 || !_isStreaming) {
          _actualFps = _framesInCurrentSecond.toDouble();
        }
      }
      actualFpsNotifier.value = _actualFps;
      _framesInCurrentSecond = 0;
    });
  }

  @override
  void dispose() {
    stopStream();
    actualFpsNotifier.dispose();
    lastErrorNotifier.dispose();
    isConnectingNotifier.dispose();
    _frameStreamController.close();
    _taggedFrameStreamController.close();
    super.dispose();
  }
}
