import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/biometric_hardware_service.dart';
import '../../../../core/services/cctv_stream_service.dart';

/// Interactive camera and CCTV photo capture dialog for biometric enrollment.
/// Allows capturing portraits from live CCTV / IP camera streams (Hikvision, CP Plus, Tapo, Mobile IP)
/// or local USB webcams with real-time face detection validation.
class CctvPhotoCaptureDialog extends StatefulWidget {
  final String studentName;
  final String studentId;

  const CctvPhotoCaptureDialog({
    super.key,
    required this.studentName,
    required this.studentId,
  });

  static Future<String?> show(
    BuildContext context, {
    required String studentName,
    required String studentId,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CctvPhotoCaptureDialog(
        studentName: studentName,
        studentId: studentId,
      ),
    );
  }

  @override
  State<CctvPhotoCaptureDialog> createState() => _CctvPhotoCaptureDialogState();
}

class _CctvPhotoCaptureDialogState extends State<CctvPhotoCaptureDialog> {
  final CctvStreamService _streamService = CctvStreamService();
  final BiometricHardwareService _biometricService = BiometricHardwareService();

  late TextEditingController _ipUrlController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;

  CctvSourceType _sourceType = CctvSourceType.ipCamera;
  int _selectedCameraIndex = 0;

  Uint8List? _currentFrameBytes;
  StreamSubscription<Uint8List>? _frameSubscription;
  Timer? _aiAnalysisTimer;

  bool _isConnecting = false;
  bool _isCapturing = false;
  String? _errorMessage;
  String? _statusMessage;

  DetectedFace? _latestDetectedFace;
  double _detectedConfidence = 0.0;
  bool _hasFaceInFrame = false;
  int _frameWidth = 640;
  int _frameHeight = 480;

  @override
  void initState() {
    super.initState();
    final cfg = _streamService.config;
    _ipUrlController = TextEditingController(text: cfg.ipUrl.isNotEmpty ? cfg.ipUrl : 'http://192.168.1.100:8080/shot.jpg');
    _usernameController = TextEditingController(text: cfg.username);
    _passwordController = TextEditingController(text: cfg.password);
    _sourceType = cfg.sourceType == CctvSourceType.webcam ? CctvSourceType.webcam : CctvSourceType.ipCamera;
    _selectedCameraIndex = cfg.cameraIndex;

    _loadPreferencesAndStart();
  }

  @override
  void dispose() {
    _aiAnalysisTimer?.cancel();
    _frameSubscription?.cancel();
    _streamService.stopStream();
    _ipUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferencesAndStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSourceStr = prefs.getString('cctv_source_type');
      if (savedSourceStr == 'webcam') {
        _sourceType = CctvSourceType.webcam;
      } else if (savedSourceStr == 'ipCamera') {
        _sourceType = CctvSourceType.ipCamera;
      }
      final savedIp = prefs.getString('cctv_ip_url');
      if (savedIp != null && savedIp.isNotEmpty) {
        _ipUrlController.text = savedIp;
      }
      final savedUser = prefs.getString('cctv_username');
      if (savedUser != null) _usernameController.text = savedUser;
      final savedPass = prefs.getString('cctv_password');
      if (savedPass != null) _passwordController.text = savedPass;

      if (_sourceType == CctvSourceType.webcam) {
        await _streamService.discoverCameras();
      }
    } catch (_) {}

    if (mounted) {
      _startLiveStream();
    }
  }

  Future<void> _startLiveStream() async {
    _aiAnalysisTimer?.cancel();
    await _frameSubscription?.cancel();
    await _streamService.stopStream();

    if (!mounted) return;
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _statusMessage = 'Connecting to ${_sourceType == CctvSourceType.ipCamera ? "CCTV camera" : "Webcam"}...';
      _latestDetectedFace = null;
      _hasFaceInFrame = false;
    });

    final newConfig = CctvCameraConfig(
      sourceType: _sourceType,
      ipUrl: _ipUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      cameraIndex: _selectedCameraIndex,
      targetFps: 30,
    );

    // Save configuration
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cctv_source_type', _sourceType.name);
      if (_sourceType == CctvSourceType.ipCamera) {
        await prefs.setString('cctv_ip_url', newConfig.ipUrl);
        await prefs.setString('cctv_username', newConfig.username);
        await prefs.setString('cctv_password', newConfig.password);
      }
    } catch (_) {}

    _frameSubscription = _streamService.onFrameCaptured.listen((bytes) {
      if (!mounted) return;
      if (_currentFrameBytes == null) {
        setState(() {
          _isConnecting = false;
          _statusMessage = null;
        });
      }
      _currentFrameBytes = bytes;
      setState(() {});
    });

    final started = await _streamService.startStream(newConfig);
    if (!mounted) return;

    if (!started) {
      setState(() {
        _isConnecting = false;
        _errorMessage = _streamService.lastError ?? 'Failed to connect to camera. Check power and network.';
        _statusMessage = null;
      });
    } else {
      setState(() {
        _isConnecting = false;
        _statusMessage = null;
      });
      // Start periodic AI face detection check on live stream frames
      _startPeriodicFaceCheck();
    }
  }

  void _startPeriodicFaceCheck() {
    _aiAnalysisTimer?.cancel();
    _aiAnalysisTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      final frame = _currentFrameBytes;
      if (frame == null || frame.isEmpty || !mounted || _isCapturing) return;

      try {
        final detection = await _biometricService.detectFace(
          frame,
          sensitivity: FaceDetectionSensitivity.balanced,
        );
        if (!mounted) return;

        setState(() {
          _hasFaceInFrame = detection.hasFace && detection.detectedFaces.isNotEmpty;
          if (_hasFaceInFrame) {
            _latestDetectedFace = detection.detectedFaces.first;
            _detectedConfidence = detection.confidence;
            _frameWidth = detection.imageWidth > 0 ? detection.imageWidth : 640;
            _frameHeight = detection.imageHeight > 0 ? detection.imageHeight : 480;
          } else {
            _latestDetectedFace = null;
            _detectedConfidence = 0.0;
          }
        });
      } catch (_) {}
    });
  }

  Future<void> _captureCurrentFrame() async {
    final frame = _currentFrameBytes;
    if (frame == null || frame.isEmpty) return;

    setState(() => _isCapturing = true);

    try {
      // 1. Validate Face Detection on captured frame
      final detection = await _biometricService.detectFace(
        frame,
        sensitivity: FaceDetectionSensitivity.balanced,
      );

      if (!detection.hasFace || detection.detectedFaces.isEmpty) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                SizedBox(width: 8),
                Text('Face Not Clearly Detected', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              'Camera frame me insani chehra saaf detect nahi hua!\n\n'
              'Kya aap isi frame ko student ke photo ke tor par capture karna chahte hain ya dubara behtar position me snapshot lena chahte hain?',
              style: TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Retake (Dubara Le)'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Use This Photo Anyway'),
              ),
            ],
          ),
        );

        if (proceed != true) {
          setState(() => _isCapturing = false);
          return;
        }
      }

      // 2. Save captured photo permanently to MadarsaCctvPhotos directory
      final String userProfile = Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
      final targetDir = Directory('$userProfile\\Pictures\\MadarsaCctvPhotos');
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }

      final safeName = widget.studentName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final fileName = 'cctv_${safeName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${targetDir.path}\\$fileName');
      await file.writeAsBytes(frame);

      // Stop stream before exiting
      await _streamService.stopStream();

      if (mounted) {
        Navigator.pop(context, file.path);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCapturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save captured photo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 740),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CCTV & CAMERA PHOTO CAPTURE',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Capture frontal face photo for: ${widget.studentName}',
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Source Selector
                    SegmentedButton<CctvSourceType>(
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: const Color(0xFF0F766E),
                        selectedForegroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: CctvSourceType.ipCamera,
                          icon: Icon(Icons.security_rounded, size: 16),
                          label: Text('IP / CCTV Camera', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        ButtonSegment(
                          value: CctvSourceType.webcam,
                          icon: Icon(Icons.camera_alt_rounded, size: 16),
                          label: Text('USB Webcam', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      selected: {_sourceType},
                      onSelectionChanged: (val) {
                        setState(() {
                          _sourceType = val.first;
                          _currentFrameBytes = null;
                        });
                        _startLiveStream();
                      },
                    ),
                    const SizedBox(height: 10),

                    // Controls based on source
                    if (_sourceType == CctvSourceType.ipCamera) ...[
                      // Quick Camera Presets
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.phone_android_rounded, size: 13, color: Color(0xFF0F766E)),
                            label: const Text('Mobile IP Webcam', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              _ipUrlController.text = 'http://192.168.1.50:8080/shot.jpg';
                              _startLiveStream();
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.videocam_rounded, size: 13, color: Color(0xFF0F766E)),
                            label: const Text('Hikvision / Ezviz', style: TextStyle(fontSize: 10.5)),
                            onPressed: () {
                              _ipUrlController.text = 'http://192.168.1.64/ISAPI/Streaming/channels/101/picture';
                              _startLiveStream();
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.camera_outdoor_rounded, size: 13, color: Color(0xFF0F766E)),
                            label: const Text('CP Plus / Dahua', style: TextStyle(fontSize: 10.5)),
                            onPressed: () {
                              _ipUrlController.text = 'http://192.168.1.250/cgi-bin/snapshot.cgi';
                              _startLiveStream();
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.wifi_rounded, size: 13, color: Color(0xFF0F766E)),
                            label: const Text('TP-Link Tapo', style: TextStyle(fontSize: 10.5)),
                            onPressed: () {
                              _ipUrlController.text = 'http://192.168.1.100:8080/shot.jpg';
                              _startLiveStream();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // IP Camera URL & Connect Button Row
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ipUrlController,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                labelText: 'CCTV HTTP Stream / Snapshot URL',
                                hintText: 'http://192.168.1.100:8080/shot.jpg',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Connect', style: TextStyle(fontSize: 11)),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onPressed: _isConnecting ? null : _startLiveStream,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Optional Credentials
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _usernameController,
                              style: const TextStyle(fontSize: 11),
                              decoration: InputDecoration(
                                labelText: 'Username (Optional)',
                                hintText: 'admin',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _passwordController,
                              obscureText: true,
                              style: const TextStyle(fontSize: 11),
                              decoration: InputDecoration(
                                labelText: 'Password (Optional)',
                                hintText: '••••••',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // USB Webcam Selector
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedCameraIndex < _streamService.availableCamerasList.length
                                  ? _selectedCameraIndex
                                  : 0,
                              decoration: InputDecoration(
                                labelText: 'Select Connected USB Camera',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                              items: List.generate(_streamService.availableCamerasList.length, (idx) {
                                final cam = _streamService.availableCamerasList[idx];
                                return DropdownMenuItem<int>(
                                  value: idx,
                                  child: Text(
                                    cam.name.isNotEmpty ? cam.name : 'Webcam #$idx',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              }),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedCameraIndex = val);
                                  _startLiveStream();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Refresh', style: TextStyle(fontSize: 11)),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onPressed: _isConnecting ? null : _startLiveStream,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),

                    // LIVE VIEWFINDER CONTAINER
                    Container(
                      height: 280,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _hasFaceInFrame ? Colors.tealAccent : const Color(0xFF334155),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _hasFaceInFrame ? Colors.teal.withAlpha(60) : Colors.black26,
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Frame Display
                          if (_currentFrameBytes != null)
                            Image.memory(
                              _currentFrameBytes!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            )
                          else
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isConnecting) ...[
                                    const CircularProgressIndicator(color: Color(0xFF14B8A6)),
                                    const SizedBox(height: 12),
                                    Text(
                                      _statusMessage ?? 'Connecting to live camera...',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ] else if (_errorMessage != null) ...[
                                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 36),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24),
                                      child: Text(
                                        _errorMessage!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.refresh_rounded, size: 14, color: Colors.tealAccent),
                                      label: const Text('Try Again', style: TextStyle(color: Colors.tealAccent, fontSize: 11)),
                                      onPressed: _startLiveStream,
                                    ),
                                  ] else
                                    const Text('No Video Feed', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ),

                          // Bounding Box Overlay for Detected Face
                          if (_hasFaceInFrame && _latestDetectedFace != null && _currentFrameBytes != null)
                            LayoutBuilder(
                              builder: (ctx, constraints) {
                                final w = constraints.maxWidth;
                                final h = constraints.maxHeight;
                                final imgW = _frameWidth.toDouble();
                                final imgH = _frameHeight.toDouble();
                                final scale = math.min(w / imgW, h / imgH);
                                final renderW = imgW * scale;
                                final renderH = imgH * scale;
                                final offX = (w - renderW) / 2.0;
                                final offY = (h - renderH) / 2.0;

                                final f = _latestDetectedFace!;
                                final left = offX + f.left * scale;
                                final top = offY + f.top * scale;
                                final boxW = f.width * scale;
                                final boxH = f.height * scale;

                                return Stack(
                                  children: [
                                    Positioned(
                                      left: left,
                                      top: top,
                                      width: boxW,
                                      height: boxH,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: const Color(0xFF10B981), width: 2.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Align(
                                          alignment: Alignment.topLeft,
                                          child: Container(
                                            margin: const EdgeInsets.all(2),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'FACE DETECTED (${_detectedConfidence.toInt()}%)',
                                              style: const TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                          // Top Stream Status Badge
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(160),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _currentFrameBytes != null ? const Color(0xFF10B981) : Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _sourceType == CctvSourceType.ipCamera ? 'LIVE CCTV' : 'LIVE WEBCAM',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Top Face Status Badge
                          if (_currentFrameBytes != null)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _hasFaceInFrame ? const Color(0xFF0F766E) : Colors.black.withAlpha(160),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: _hasFaceInFrame ? const Color(0xFF2DD4BF) : Colors.white24),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _hasFaceInFrame ? Icons.check_circle_rounded : Icons.face_rounded,
                                      size: 12,
                                      color: _hasFaceInFrame ? const Color(0xFF2DD4BF) : Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _hasFaceInFrame
                                          ? 'Face Ready (${_detectedConfidence.toInt()}%)'
                                          : 'Center Face in View',
                                      style: TextStyle(
                                        color: _hasFaceInFrame ? Colors.white : Colors.white70,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Actions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: _isCapturing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.camera_alt_rounded, size: 18),
                    label: Text(_isCapturing ? 'Capturing...' : 'Capture & Enroll Photo'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: (_currentFrameBytes == null || _isCapturing) ? null : _captureCurrentFrame,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
