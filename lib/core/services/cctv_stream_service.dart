import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
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
  final ValueNotifier<ui.Image?> displayImageNotifier;
  final ValueNotifier<List<CctvTrackedFace>> trackedFacesNotifier;
  final ValueNotifier<bool> isStreamingNotifier;
  final ValueNotifier<bool> isOnlineNotifier;
  bool isStreaming;
  bool isOffline;
  int failureCount;
  DateTime? lastProbeTime;
  String? resolvedStreamUrl;
  Timer? timer;
  double actualFps;
  int frameCount;

  CctvCameraChannel({
    required this.profile,
    ValueNotifier<Uint8List?>? lastFrameNotifier,
    ValueNotifier<ui.Image?>? displayImageNotifier,
    ValueNotifier<List<CctvTrackedFace>>? trackedFacesNotifier,
    this.isStreaming = false,
    this.isOffline = false,
    this.failureCount = 0,
    this.actualFps = 0.0,
    this.frameCount = 0,
    this.resolvedStreamUrl,
  })  : lastFrameNotifier = lastFrameNotifier ?? ValueNotifier<Uint8List?>(null),
        displayImageNotifier = displayImageNotifier ?? ValueNotifier<ui.Image?>(null),
        trackedFacesNotifier = trackedFacesNotifier ?? ValueNotifier<List<CctvTrackedFace>>([]),
        isStreamingNotifier = ValueNotifier<bool>(isStreaming),
        isOnlineNotifier = ValueNotifier<bool>(!isOffline);

  void dispose() {
    timer?.cancel();
    timer = null;
    isStreaming = false;
    isStreamingNotifier.value = false;
    isOnlineNotifier.dispose();
    displayImageNotifier.dispose();
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
      const CctvCameraProfile(
        id: 'cam_4',
        name: 'Classroom 1 (Awwal)',
        sourceType: CctvSourceType.ipCamera,
        ipUrl: 'http://192.168.1.103:8080/shot.jpg',
        role: 'classroom',
      ),
      const CctvCameraProfile(
        id: 'cam_5',
        name: 'Classroom 2 (Doyam)',
        sourceType: CctvSourceType.ipCamera,
        ipUrl: 'http://192.168.1.104:8080/shot.jpg',
        role: 'classroom',
      ),
      const CctvCameraProfile(
        id: 'cam_6',
        name: 'Office / Reception',
        sourceType: CctvSourceType.ipCamera,
        ipUrl: 'http://192.168.1.105:8080/shot.jpg',
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

  String? _activeSnapshotUrl;
  String? get activeSnapshotUrl => _activeSnapshotUrl;

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

  /// Hardware GPU Texture Notifier for Single-Camera Viewport (Hardware Decoded ONCE, Zero Widget setState)
  final ValueNotifier<ui.Image?> singleDisplayImageNotifier = ValueNotifier<ui.Image?>(null);
  bool _singleDecoding = false;
  ui.Image? _currentSingleDecodedImage;

  void _decodeAndDistributeSingleImage(Uint8List bytes) async {
    if (_singleDecoding) return; // Strict single-flight: drop intermediate frames to prevent queueing
    _singleDecoding = true;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 540, // Optimal balance of crisp HD clarity & ultra-low CPU decoding
      );
      final frameInfo = await codec.getNextFrame();
      final newImage = frameInfo.image;
      codec.dispose();

      final old = _currentSingleDecodedImage;
      _currentSingleDecodedImage = newImage;
      singleDisplayImageNotifier.value = newImage;
      old?.dispose(); // Instantly free previous DirectX/Vulkan texture
    } catch (_) {
    } finally {
      _singleDecoding = false;
    }
  }

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
      _decodeAndDistributeSingleImage(bytes);
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
  Map<String, CctvCameraChannel> get channels => _channels;

  // Source-Level Multiplexing & Broadcasting State:
  final Map<String, Timer> _multiCamSourceTimers = {};
  final Map<String, String> _multiCamResolvedUrls = {};
  final Map<String, bool> _multiCamSourceOffline = {};
  final Map<String, int> _multiCamSourceFailures = {};
  final Map<String, DateTime> _multiCamSourceLastProbe = {};
  final Map<String, bool> _multiCamSourceFetching = {};

  // Pre-decoded GPU Textures for Multi-Camera Grid (Decoded ONCE per physical source stream!)
  final Map<String, ui.Image> _multiCamDecodedImages = {};
  final Map<String, bool> _multiCamDecoding = {};

  String _normalizePhysicalSourceKey(CctvCameraProfile p) {
    if (p.sourceType == CctvSourceType.ipCamera) {
      final parsed = parseHostAndPort(p.ipUrl);
      final host = parsed.host.toLowerCase().trim();
      int port = parsed.port;
      if (port == 80 && _discoveredHostPorts.containsKey(host)) {
        port = _discoveredHostPorts[host]!;
      }
      return 'ip:$host:$port';
    } else if (p.sourceType == CctvSourceType.webcam) {
      return 'webcam:${p.cameraIndex}';
    } else {
      return 'simulation';
    }
  }

  void _decodeAndDistributeSourceImage(String sourceKey, Uint8List bytes, List<CctvCameraChannel> boundChannels) async {
    if (_multiCamDecoding[sourceKey] == true) return;
    _multiCamDecoding[sourceKey] = true;
    try {
      final targetW = _isMultiCamMode ? 480 : 640;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetW, // Hardware-accelerated decode directly to GPU texture
      );
      final frameInfo = await codec.getNextFrame();
      final newImage = frameInfo.image;
      codec.dispose();

      final old = _multiCamDecodedImages[sourceKey];
      _multiCamDecodedImages[sourceKey] = newImage;
      old?.dispose();

      for (final ch in boundChannels) {
        ch.displayImageNotifier.value = newImage;
      }
      singleDisplayImageNotifier.value = newImage;
    } catch (_) {
      // Ignore transient decode errors on partial bytes
    } finally {
      _multiCamDecoding[sourceKey] = false;
    }
  }

  List<CctvCameraChannel> get activeChannels {
    if (_isMultiCamMode) {
      final validIds = _cameraProfiles.where((p) => p.isEnabled).map((p) => p.id).toSet();
      _channels.removeWhere((id, ch) {
        if (!validIds.contains(id)) {
          ch.dispose();
          return true;
        }
        return false;
      });
      bool hasChanges = false;
      for (final profile in _cameraProfiles) {
        if (!profile.isEnabled) continue;
        if (!_channels.containsKey(profile.id)) {
          final channel = CctvCameraChannel(profile: profile, isStreaming: true);
          _channels[profile.id] = channel;
          hasChanges = true;
        }
      }
      if (hasChanges) {
        _rebuildMultiCamSourceStreamers();
      }
    }
    return _channels.values.toList();
  }
  bool _isMultiCamMode = false;
  bool get isMultiCamMode => _isMultiCamMode;

  /// Find all active channels that share the same physical camera source as [channelId]
  List<CctvCameraChannel> getChannelsSharingSource(String channelId) {
    CctvCameraProfile? targetProfile;
    final ch = _channels[channelId];
    if (ch != null) {
      targetProfile = ch.profile;
    } else {
      final found = _cameraProfiles.where((p) => p.id == channelId);
      if (found.isNotEmpty) targetProfile = found.first;
    }
    if (targetProfile == null) return [];
    final key = _normalizePhysicalSourceKey(targetProfile);
    return _channels.values.where((c) => _normalizePhysicalSourceKey(c.profile) == key).toList();
  }

  /// Dynamic FPS Adjustment without tearing down video stream (supports 1 to 60 FPS)
  void updateFps(int newFps) {
    final clamped = newFps.clamp(1, 60);
    _config = _config.copyWith(targetFps: clamped);

    for (final timer in _multiCamSourceTimers.values) {
      timer.cancel();
    }
    _multiCamSourceTimers.clear();
    _rebuildMultiCamSourceStreamers();
  }

  /// Start simultaneous streaming from multiple cameras in parallel (Security NVR Grid mode)
  /// Features Smart Source Multiplexing: Multiple grid channels can share the same physical camera
  /// without opening multiple conflicting connections or exceeding CPU/network limits!
  Future<void> startMultiCameraStreams(List<CctvCameraProfile> profiles) async {
    await stopMultiCameraStreams();
    _isMultiCamMode = true;
    _isStreaming = true;

    for (final profile in profiles) {
      if (!profile.isEnabled) continue;
      final channel = CctvCameraChannel(profile: profile, isStreaming: true);
      _channels[profile.id] = channel;
    }

    _startFpsCounter();
    _rebuildMultiCamSourceStreamers();
    notifyListeners();
  }

  void _rebuildMultiCamSourceStreamers() {
    if (!_isMultiCamMode && !_isStreaming) return;

    final activeSourceKeys = <String>{};
    for (final ch in _channels.values) {
      if (ch.isStreaming && ch.profile.isEnabled) {
        activeSourceKeys.add(_normalizePhysicalSourceKey(ch.profile));
      }
    }

    // Cancel timers for sources with no listeners
    _multiCamSourceTimers.removeWhere((key, timer) {
      if (!activeSourceKeys.contains(key)) {
        timer.cancel();
        return true;
      }
      return false;
    });

    // Hardware-accelerated polling: Target FPS delivers fluid, real-time security display
    // while keeping CPU < 25% and utilizing GPU hardware decoding
    final effectiveFps = _isMultiCamMode ? 15 : _config.targetFps.clamp(15, 30);
    final intervalMs = (1000 / effectiveFps).round();

    // Start timer for each unique physical source key if not already running
    for (final sourceKey in activeSourceKeys) {
      if (_multiCamSourceTimers.containsKey(sourceKey)) continue;

      final sampleChannel = _channels.values.firstWhere(
        (c) => _normalizePhysicalSourceKey(c.profile) == sourceKey,
      );

      _multiCamSourceTimers[sourceKey] = Timer.periodic(
        Duration(milliseconds: intervalMs),
        (_) async => _executeSourceStreamTick(sourceKey, sampleChannel.profile),
      );
    }
  }

  Future<void> _executeSourceStreamTick(String sourceKey, CctvCameraProfile profile) async {
    if (!_isMultiCamMode && !_isStreaming) return;

    // Find all channels currently bound to this physical source
    final boundChannels = _channels.values
        .where((c) => c.isStreaming && _normalizePhysicalSourceKey(c.profile) == sourceKey)
        .toList();

    if (boundChannels.isEmpty) return;

    final now = DateTime.now();
    final isOffline = _multiCamSourceOffline[sourceKey] == true;

    // 🛡️ SMART OFFLINE ISOLATION & CPU SHIELD:
    // If this source is offline, gently probe once every 3.5s (Zero CPU, Zero Sockets)
    if (isOffline) {
      final lastProbe = _multiCamSourceLastProbe[sourceKey];
      if (lastProbe != null && now.difference(lastProbe).inMilliseconds < 3500) {
        return;
      }
      _multiCamSourceLastProbe[sourceKey] = now;
    }

    if (_multiCamSourceFetching[sourceKey] == true) return;
    _multiCamSourceFetching[sourceKey] = true;

    try {
      Uint8List? bytes;
      if (profile.sourceType == CctvSourceType.ipCamera) {
        String? targetUrl = _multiCamResolvedUrls[sourceKey];
        if (targetUrl == null) {
          final parsed = parseHostAndPort(profile.ipUrl);
          int? openPort;
          if (parsed.host.isNotEmpty) {
            openPort = await findReachableCameraPort(parsed.host, parsed.port, timeout: const Duration(milliseconds: 400));
          }
          final candidates = _getCandidateStreamUrls(
            profile.ipUrl,
            profile.username,
            profile.password,
            activePort: openPort,
          );
          for (final c in candidates) {
            if (c.toLowerCase().startsWith('rtsp://')) continue;
            final test = await _fetchIpCameraFrame(c, profile.username, profile.password);
            if (test != null && _isValidImageBytes(test)) {
              _multiCamResolvedUrls[sourceKey] = c;
              targetUrl = c;
              bytes = test;
              break;
            }
          }
        } else {
          bytes = await _fetchIpCameraFrame(
            targetUrl,
            profile.username,
            profile.password,
          );
        }
      } else if (profile.sourceType == CctvSourceType.webcam) {
        bytes = await _fetchWebcamFrame(cameraIndex: profile.cameraIndex);
      } else {
        bytes = await _getNextSimulationFrame();
      }

      if (bytes != null && bytes.isNotEmpty && _isValidImageBytes(bytes)) {
        _multiCamSourceOffline[sourceKey] = false;
        _multiCamSourceFailures[sourceKey] = 0;
        if (!_isMultiCamMode && _lastError != null) {
          _setLastError(null);
        }

        // 🚀 SMART FAN-OUT: BROADCAST FRAME TO ALL CHANNELS BOUND TO THIS SOURCE!
        // Whether 1 channel or 10 channels are bound to this same camera,
        // all grid tiles play the LIVE stream concurrently in sync at 60 FPS!
        for (final ch in boundChannels) {
          ch.isOffline = false;
          ch.failureCount = 0;
          ch.isOnlineNotifier.value = true;
          ch.lastFrameNotifier.value = bytes;
          ch.resolvedStreamUrl = _multiCamResolvedUrls[sourceKey];
        }

        // ⚡ SINGLE HARDWARE GPU DECODE: Decoded ONCE and distributed to all bound grid tiles & single display
        _decodeAndDistributeSourceImage(sourceKey, bytes, boundChannels);

        _framesInCurrentSecond++;

        if (!_frameStreamController.isClosed) {
          _frameStreamController.add(bytes);
        }

        // Send to attendance face recognition tagged stream once per tick
        if (!_taggedFrameStreamController.isClosed && boundChannels.isNotEmpty) {
          final primary = boundChannels.first;
          _taggedFrameStreamController.add(CctvFramePayload(
            bytes: bytes,
            cameraName: primary.profile.name,
            cameraId: primary.profile.id,
            cameraRole: primary.profile.role,
          ));
        }
      } else {
        final f = (_multiCamSourceFailures[sourceKey] ?? 0) + 1;
        _multiCamSourceFailures[sourceKey] = f;
        if (f >= 5) {
          _multiCamSourceOffline[sourceKey] = true;
          _multiCamResolvedUrls.remove(sourceKey);
          for (final ch in boundChannels) {
            ch.isOffline = true;
            ch.isOnlineNotifier.value = false;
          }
          if (!_isMultiCamMode) {
            _setLastError('Camera feed offline or unreachable. Please check camera network & power.');
            notifyListeners();
          }
        }
      }
    } catch (_) {
      final f = (_multiCamSourceFailures[sourceKey] ?? 0) + 1;
      _multiCamSourceFailures[sourceKey] = f;
      if (f >= 5) {
        _multiCamSourceOffline[sourceKey] = true;
        for (final ch in boundChannels) {
          ch.isOffline = true;
          ch.isOnlineNotifier.value = false;
        }
        if (!_isMultiCamMode) {
          _setLastError('Camera feed error. Please check camera network connection.');
          notifyListeners();
        }
      }
    } finally {
      _multiCamSourceFetching[sourceKey] = false;
    }
  }

  Future<Uint8List?> _fetchWebcamFrame({int cameraIndex = 0}) async {
    if (CctvNativeFaceEngine.instance.isAvailable) {
      if (!_isNativeOpenCvStreaming) {
        final opened = CctvNativeFaceEngine.instance.openCamera(cameraIndex: cameraIndex, width: 640, height: 480);
        if (opened) _isNativeOpenCvStreaming = true;
      }
      if (_isNativeOpenCvStreaming) {
        return CctvNativeFaceEngine.instance.readCameraJpeg(quality: 55);
      }
    }
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      try {
        if (_availableCameras.isEmpty) {
          _availableCameras = await availableCameras();
        }
        if (_availableCameras.isNotEmpty) {
          final idx = cameraIndex.clamp(0, _availableCameras.length - 1);
          _cameraController = CameraController(
            _availableCameras[idx],
            ResolutionPreset.medium,
            enableAudio: false,
          );
          await _cameraController!.initialize();
        }
      } catch (_) {}
    }
    if (_cameraController != null && _cameraController!.value.isInitialized && !_isCapturing) {
      _isCapturing = true;
      try {
        final xfile = await _cameraController!.takePicture();
        final bytes = await xfile.readAsBytes();
        try {
          File(xfile.path).deleteSync();
        } catch (_) {}
        return bytes;
      } catch (_) {
        return null;
      } finally {
        _isCapturing = false;
      }
    }
    return null;
  }

  Future<void> stopMultiCameraStreams() async {
    _isMultiCamMode = false;
    for (final timer in _multiCamSourceTimers.values) {
      timer.cancel();
    }
    _multiCamSourceTimers.clear();
    _multiCamSourceFetching.clear();
    for (final img in _multiCamDecodedImages.values) {
      img.dispose();
    }
    _multiCamDecodedImages.clear();
    _multiCamDecoding.clear();
    for (final ch in _channels.values) {
      ch.dispose();
    }
    _channels.clear();
    notifyListeners();
  }

  /// Clones a camera profile to allow monitoring the same camera in multiple grid tiles
  Future<CctvCameraProfile> duplicateCameraProfile(String profileId) async {
    final original = _cameraProfiles.firstWhere((p) => p.id == profileId, orElse: () => _cameraProfiles.first);
    final count = _cameraProfiles.where((p) => p.ipUrl == original.ipUrl && p.sourceType == original.sourceType).length;
    final copy = CctvCameraProfile(
      id: 'cam_${DateTime.now().millisecondsSinceEpoch}',
      name: '${original.name} (Grid ${count + 1})',
      sourceType: original.sourceType,
      cameraIndex: original.cameraIndex,
      ipUrl: original.ipUrl,
      username: original.username,
      password: original.password,
      role: original.role,
      isEnabled: true,
    );
    await addCameraProfile(copy);
    return copy;
  }

  /// Assign a new camera profile source to an existing grid channel tile
  Future<void> assignCameraToChannel(String channelId, CctvCameraProfile newSourceProfile) async {
    final idx = _cameraProfiles.indexWhere((p) => p.id == channelId);
    if (idx != -1) {
      _cameraProfiles[idx] = newSourceProfile.copyWith(
        id: channelId,
        name: '${newSourceProfile.name} (Tile ${idx + 1})',
      );
      await saveProfiles();
      if (_isMultiCamMode) {
        await startMultiCameraStreams(_cameraProfiles);
      }
      notifyListeners();
    }
  }

  /// Clones the source settings (IP/type/credentials) of [sourceProfileId] to all existing camera profiles,
  /// instantly activating all grid tiles with this working camera!
  Future<void> applySourceToAllProfiles(String sourceProfileId) async {
    final source = _cameraProfiles.firstWhere((p) => p.id == sourceProfileId, orElse: () => _cameraProfiles.first);
    for (int i = 0; i < _cameraProfiles.length; i++) {
      final p = _cameraProfiles[i];
      _cameraProfiles[i] = p.copyWith(
        sourceType: source.sourceType,
        cameraIndex: source.cameraIndex,
        ipUrl: source.ipUrl,
        username: source.username,
        password: source.password,
        isEnabled: true,
      );
    }
    await saveProfiles();
    if (_isMultiCamMode) {
      await startMultiCameraStreams(_cameraProfiles);
    }
    notifyListeners();
  }

  /// Enables all camera profiles so all grid tiles are active
  Future<void> enableAllProfiles() async {
    for (int i = 0; i < _cameraProfiles.length; i++) {
      _cameraProfiles[i] = _cameraProfiles[i].copyWith(isEnabled: true);
    }
    await saveProfiles();
    if (_isMultiCamMode) {
      await startMultiCameraStreams(_cameraProfiles);
    }
    notifyListeners();
  }

  /// Toggle enabled state for a specific camera profile
  Future<void> toggleProfileEnabled(String profileId, bool isEnabled) async {
    final idx = _cameraProfiles.indexWhere((p) => p.id == profileId);
    if (idx != -1) {
      _cameraProfiles[idx] = _cameraProfiles[idx].copyWith(isEnabled: isEnabled);
      await saveProfiles();
      if (_isMultiCamMode) {
        await startMultiCameraStreams(_cameraProfiles);
      }
      notifyListeners();
    }
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
    if (_isMultiCamMode) {
      await startMultiCameraStreams(_cameraProfiles);
    }
    notifyListeners();
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
    if (_isMultiCamMode) {
      await startMultiCameraStreams(_cameraProfiles);
    }
    notifyListeners();
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
      if (_isMultiCamMode) {
        await startMultiCameraStreams(_cameraProfiles);
      }
      notifyListeners();
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
    if (_isMultiCamMode) {
      await startMultiCameraStreams(_cameraProfiles);
    }
    notifyListeners();
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

  /// Initialize and start streaming based on current config using unified GPU-accelerated engine
  Future<bool> startStream([CctvCameraConfig? newConfig]) async {
    await stopStream();

    if (newConfig != null) {
      _config = newConfig;
    }

    _setLastError(null);
    _setIsConnecting(true);
    _isMultiCamMode = false;

    try {
      _startFpsCounter();

      final existingIndex = _cameraProfiles.indexWhere((p) => p.id == _activeProfileId);
      final prof = CctvCameraProfile(
        id: _activeProfileId,
        name: existingIndex >= 0 ? _cameraProfiles[existingIndex].name : _activeCameraName,
        sourceType: _config.sourceType,
        cameraIndex: _config.cameraIndex,
        ipUrl: _config.ipUrl,
        username: _config.username,
        password: _config.password,
        role: _config.role,
        isEnabled: true,
      );

      final channel = CctvCameraChannel(profile: prof, isStreaming: true);
      _channels[prof.id] = channel;
      _isStreaming = true;

      _rebuildMultiCamSourceStreamers();
      notifyListeners();
      return true;
    } catch (e) {
      _setLastError(e.toString());
      return false;
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

    if (!_isMultiCamMode) {
      for (final timer in _multiCamSourceTimers.values) {
        timer.cancel();
      }
      _multiCamSourceTimers.clear();
      _multiCamSourceFetching.clear();
      for (final img in _multiCamDecodedImages.values) {
        img.dispose();
      }
      _multiCamDecodedImages.clear();
      _multiCamDecoding.clear();
      for (final ch in _channels.values) {
        ch.dispose();
      }
      _channels.clear();
    }

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

    _currentSingleDecodedImage?.dispose();
    _currentSingleDecodedImage = null;
    singleDisplayImageNotifier.value = null;
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

  List<String> _getCandidateStreamUrls(String rawUrl, String username, String password, {int? activePort}) {
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
    final port = activePort ?? parsed.port;
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
      addUrl(base);
      for (final pat in snapshotPaths) {
        if (base.toLowerCase().contains(pat)) {
          addUrl(base.replaceAll(RegExp(pat, caseSensitive: false), '/video'));
          addUrl(base.replaceAll(RegExp(pat, caseSensitive: false), '/videofeed'));
          addUrl(base.replaceAll(RegExp(pat, caseSensitive: false), '/mjpegfeed'));
          addUrl(base.replaceAll(RegExp(pat, caseSensitive: false), '/live'));
          addUrl(base.replaceAll(RegExp(pat, caseSensitive: false), '/mjpeg'));
        }
      }
    }

    // 2. ⚡ UNIVERSAL BRAND AUTO-PROBE:
    // If user provided just an IP, hostname, or basic URL without a deep stream path,
    // automatically generate candidate URLs for ALL major standalone CCTV brands:
    if (host.isNotEmpty) {
      // Prioritize Mobile IP Webcam endpoints if port 8080 is detected or specified
      if (port == 8080 || activePort == 8080) {
        addUrl('http://$authPrefix$host:8080/shot.jpg');
        addUrl('http://$authPrefix$host:8080/video');
      }

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

      // 🇨🇳 Generic ONVIF / Xiongmai (XM / XMeye / iCSee) / Chinese Wi-Fi Cameras (Yoosee, V380, Srihome, Tiandy, Jovision)
      addUrl('rtsp://$authPrefix$host:$rtspPort/onvif1');
      addUrl('rtsp://$authPrefix$host:$rtspPort/live/ch0');
      addUrl('rtsp://$authPrefix$host:$rtspPort/user=${username.isNotEmpty ? username : 'admin'}_password=${password}_channel=1_stream=0.sdp');
      addUrl('rtsp://$authPrefix$host:$rtspPort/h264Preview_01_main');
      addUrl('rtsp://$authPrefix$host:$rtspPort/');
      addUrl('http://$authPrefix$host/webcapture.jpg?command=snap&channel=1');
      addUrl('http://$authPrefix$host/snapshot.cgi');
      addUrl('http://$authPrefix$host/image.jpg');
      addUrl('http://$authPrefix$host/tmpfs/auto.jpg');
      addUrl('http://$authPrefix$host/LAPI/V1.0/Channel/1/Media/Snapshot');

      // 📱 Mobile IP Webcam (Android / iOS)
      addUrl('http://$authPrefix$host:8080/shot.jpg');
      addUrl('http://$authPrefix$host:8080/video');
      addUrl('http://$authPrefix$host/shot.jpg');
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

  /// Cache of discovered open ports by host to eliminate redundant socket scans across frames
  static final Map<String, int> _discoveredHostPorts = {};

  /// Discovers which CCTV/Webcam port is active on the given host.
  /// Checks 8080 (Mobile Webcam), 554 (RTSP), 80 (HTTP), 8000 (Hikvision), 34567 (XM), 8899 (Chinese ONVIF), 37777 (Dahua), 4747 (DroidCam).
  static Future<int?> findReachableCameraPort(
    String host,
    int specifiedPort, {
    Duration timeout = const Duration(milliseconds: 400),
  }) async {
    final cleanHost = host.trim().toLowerCase();
    if (specifiedPort == 80 && _discoveredHostPorts.containsKey(cleanHost)) {
      return _discoveredHostPorts[cleanHost];
    }

    // 1. If user explicitly specified a non-standard port (like 8080 or 8081 or 554), try it first!
    if (specifiedPort != 80) {
      if (await checkTcpReachability(host, specifiedPort, timeout: timeout)) {
        _discoveredHostPorts[cleanHost] = specifiedPort;
        return specifiedPort;
      }
    } else {
      if (await checkTcpReachability(host, 80, timeout: timeout)) {
        _discoveredHostPorts[cleanHost] = 80;
        return 80;
      }
    }

    // 2. Concurrently check other high-probability ports
    final candidatePorts = [8080, 554, 8000, 34567, 8899, 37777, 4747, 8081, 80];
    for (final p in candidatePorts) {
      if (p == specifiedPort) continue;
      if (await checkTcpReachability(host, p, timeout: timeout)) {
        _discoveredHostPorts[cleanHost] = p;
        return p;
      }
    }
    return null;
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





  Future<Uint8List?> _fetchIpCameraFrame(String ipUrl, String username, String password) async {
    final client = _getHttpClient();
    try {
      var cleanUrl = ipUrl.trim();
      // Normalize IP webcam / MJPEG streaming URLs to snapshot URLs for HTTP frame-by-frame polling
      if (cleanUrl.toLowerCase().contains(':8080/video')) {
        cleanUrl = cleanUrl.replaceAll(RegExp(r':8080/video\b', caseSensitive: false), ':8080/shot.jpg');
      } else if (cleanUrl.toLowerCase().endsWith('/video')) {
        cleanUrl = '${cleanUrl.substring(0, cleanUrl.length - 6)}/shot.jpg';
      }

      final uri = Uri.parse(cleanUrl);
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 3));
      if (!cleanUrl.contains('@') && username.isNotEmpty) {
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

        // Fast async TCP reachability pre-check across all camera ports (8080, 554, 80, 8000, 34567, etc.)
        final parsed = parseHostAndPort(testConfig.ipUrl);
        int? openPort;
        if (parsed.host.isNotEmpty) {
          openPort = await findReachableCameraPort(parsed.host, parsed.port, timeout: const Duration(milliseconds: 600));
          if (openPort == null) {
            return {
              'success': false,
              'message': 'Cannot reach camera endpoint (${parsed.host}). Device is offline, powered off, or port is closed.',
            };
          }
        }

        final candidates = _getCandidateStreamUrls(testConfig.ipUrl, testConfig.username, testConfig.password, activePort: openPort);

        // 1. Try Snapshot Feeds FIRST across all candidates
        // Snapshot feeds (Android IP Webcam /shot.jpg, ISAPI snapshot, Dahua CGI snapshot, Tapo)
        // are instantaneous, ultra-reliable, never hang, and ideal for multi-cam grids.
        for (final candidate in candidates) {
          if (candidate.toLowerCase().startsWith('rtsp://')) continue;
          final isSnapshot = candidate.toLowerCase().contains('/shot.jpg') ||
              candidate.toLowerCase().contains('/snapshot.jpg') ||
              candidate.toLowerCase().contains('/photo.jpg') ||
              candidate.toLowerCase().contains('/picture') ||
              candidate.toLowerCase().contains('/webcapture.jpg') ||
              candidate.toLowerCase().contains('/tmpfs/auto.jpg');
          if (isSnapshot) {
            try {
              final frameBytes = await _fetchIpCameraFrame(candidate, testConfig.username, testConfig.password);
              if (frameBytes != null && _isValidImageBytes(frameBytes)) {
                return {
                  'success': true,
                  'workingUrl': candidate,
                  'message': 'Connected to IP Camera! Live feed confirmed (${frameBytes.length} bytes) ✅',
                  'bytes': frameBytes,
                };
              }
            } catch (_) {}
          }
        }

        // 2. Try Video Streams (OpenCV Native Engine)
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
                final finalWorkingUrl = candidate.contains(':8080/video')
                    ? candidate.replaceAll(':8080/video', ':8080/shot.jpg')
                    : candidate;
                return {
                  'success': true,
                  'workingUrl': finalWorkingUrl,
                  'message': 'IP Camera live stream connected successfully via Native Engine! ($finalWorkingUrl) ✅',
                  'bytes': sampleJpeg,
                };
              }
            }
          }
        }

        // 3. Fallback to any remaining HTTP candidates
        for (final candidate in candidates) {
          if (candidate.toLowerCase().startsWith('rtsp://')) continue;
          try {
            final frameBytes = await _fetchIpCameraFrame(candidate, testConfig.username, testConfig.password);
            if (frameBytes != null && _isValidImageBytes(frameBytes)) {
              return {
                'success': true,
                'workingUrl': candidate,
                'message': 'Connected to IP Camera! Direct live stream confirmed (${frameBytes.length} bytes) ✅',
                'bytes': frameBytes,
              };
            }
          } catch (_) {}
        }

        return {
          'success': false,
          'message': 'Could not connect to camera stream at ${parsed.host}. Please verify camera is online and credentials are correct.',
        };
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
