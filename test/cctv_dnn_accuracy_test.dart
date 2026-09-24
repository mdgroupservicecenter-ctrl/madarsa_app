import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/services/biometric_hardware_service.dart';
import 'package:madarsa_app/core/services/cctv_native_face_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OpenCV DNN ResNet-10 SSD Accuracy Test on Portrait and Workbench', () async {
    final engine = CctvNativeFaceEngine();
    expect(engine.isAvailable, isTrue);
    expect(engine.engineVersion, greaterThanOrEqualTo(220));

    // 1. Test Human Portrait (Must be detected with high confidence)
    final portraitFile = File('C:/Users/MD Services/Downloads/11708.jpg');
    if (portraitFile.existsSync()) {
      final bytes = await portraitFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = byteData!.buffer.asUint8List();

      final faces = engine.detectFaces(
        rgba: rgba,
        width: frame.image.width,
        height: frame.image.height,
        sensitivity: FaceDetectionSensitivity.balanced,
      );

      print('Human Portrait Detection: found ${faces.length} face(s)');
      expect(faces.isNotEmpty, isTrue);
      for (final f in faces) {
        print('  Human Face box: [${f.left}, ${f.top}, ${f.right}, ${f.bottom}] confidence: ${f.confidence.toStringAsFixed(1)}%');
      }
    }

    // 2. Test User Workbench Photo with no human (Must have 0 faces, no false detections)
    final deskFile = File(r'C:\Users\MD Services\.gemini\antigravity\brain\078d07f5-e3ac-4471-b10e-3df02180c0f0\.user_uploaded\media_1789536980201.png');
    if (deskFile.existsSync()) {
      final bytes = await deskFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = byteData!.buffer.asUint8List();

      final deskFaces = engine.detectFaces(
        rgba: rgba,
        width: frame.image.width,
        height: frame.image.height,
        sensitivity: FaceDetectionSensitivity.balanced,
      );

      print('Desk Object Photo Detection: found ${deskFaces.length} face(s)');
      expect(deskFaces.isEmpty, isTrue, reason: 'Deep Neural Network must NOT detect non-human objects');
      print('SUCCESS: Zero false detections on desk / non-human objects!');
    }
  });
}
