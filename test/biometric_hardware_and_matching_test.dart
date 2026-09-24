import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/services/biometric_hardware_service.dart';

void main() {
  final service = BiometricHardwareService();

  group('Biometric Face Template & Matching Algorithm Tests', () {
    test('Identical face template yields 100% match score', () async {
      final imgBytes = Uint8List.fromList(List.generate(500, (i) => (i * 17) % 256));
      final template = await service.generateFaceTemplate(imgBytes, requireFace: false);

      final result = service.matchFace(
        liveTemplate: template,
        enrolledTemplate: template,
        threshold: 75.0,
      );

      expect(result.isMatch, isTrue);
      expect(result.similarityScore, 100.0);
    });

    test('Two different face images produce mismatch and are rejected below 75% threshold', () async {
      // Create two distinct simulated image patterns (e.g. Student A vs Student B)
      final studentABytes = Uint8List.fromList(List.generate(1000, (i) => (i % 2 == 0 ? 240 : 20)));
      final studentBBytes = Uint8List.fromList(List.generate(1000, (i) => ((i * 37) % 100)));

      final templateA = await service.generateFaceTemplate(studentABytes, requireFace: false);
      final templateB = await service.generateFaceTemplate(studentBBytes, requireFace: false);

      final result = service.matchFace(
        liveTemplate: templateA,
        enrolledTemplate: templateB,
        threshold: 75.0,
      );

      expect(result.isMatch, isFalse);
      expect(result.similarityScore, lessThan(75.0));
      expect(result.details, contains('Face Mismatch'));
    });

    test('detectFaceFromPixels detects human face and rejects non-face images (cars, chairs, blank canvas)', () {
      // 1. Non-face: Blue canvas (sky or car)
      final blueCarRgba = Uint8List(100 * 100 * 4);
      for (var i = 0; i < blueCarRgba.length; i += 4) {
        blueCarRgba[i] = 30; // R
        blueCarRgba[i + 1] = 90; // G
        blueCarRgba[i + 2] = 230; // B
        blueCarRgba[i + 3] = 255;
      }
      final carResult = service.detectFaceFromPixels(blueCarRgba, 100, 100);
      expect(carResult.hasFace, isFalse);
      expect(carResult.reason, anyOf(contains('skin-tone'), contains('blank'), contains('chehra detect nahi hua')));

      // 2. Non-face: Blank white sheet
      final whiteSheetRgba = Uint8List(100 * 100 * 4);
      whiteSheetRgba.fillRange(0, whiteSheetRgba.length, 255);
      final blankResult = service.detectFaceFromPixels(whiteSheetRgba, 100, 100);
      expect(blankResult.hasFace, isFalse);

      // 3. Valid Human Face: Natural skin chrominance cluster with facial geometry & contrast
      final faceRgba = Uint8List(100 * 100 * 4);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          final idx = (y * 100 + x) * 4;
          // Background: dark grey
          faceRgba[idx] = 40;
          faceRgba[idx + 1] = 40;
          faceRgba[idx + 2] = 40;
          faceRgba[idx + 3] = 255;

          // Face oval region (x: 25-75, y: 15-85)
          final dx = (x - 50) / 25.0;
          final dy = (y - 50) / 35.0;
          if (dx * dx + dy * dy <= 1.0) {
            // Natural skin tone
            var r = 210;
            var g = 155;
            var b = 120;

            // Eye region dip in luminance (y between 32 and 40)
            if (y >= 32 && y <= 40 && (x >= 32 && x <= 45 || x >= 55 && x <= 68)) {
              r = 80;
              g = 60;
              b = 50;
            }

            // Mouth region (y between 68 and 74)
            if (y >= 68 && y <= 74 && x >= 38 && x <= 62) {
              r = 175;
              g = 90;
              b = 85;
            }

            faceRgba[idx] = r;
            faceRgba[idx + 1] = g;
            faceRgba[idx + 2] = b;
            faceRgba[idx + 3] = 255;
          }
        }
      }

      final faceResult = service.detectFaceFromPixels(faceRgba, 100, 100);
      expect(faceResult.hasFace, isTrue);
      expect(faceResult.confidence, greaterThanOrEqualTo(45.0));
      expect(faceResult.skinCoverage, greaterThan(20.0));
    });

    test('generateFaceTemplate rejects non-face image by throwing NoFaceDetectedException', () async {
      // Non-face byte array marked with REJECT/NO_FACE or blank bytes
      final nonFaceBytes = Uint8List.fromList(utf8.encode('REJECT_NON_FACE_CAR_OR_CHAIR_SIMULATION'));

      expect(
        () async => await service.generateFaceTemplate(nonFaceBytes, requireFace: true),
        throwsA(isA<NoFaceDetectedException>()),
      );
    });
  });

  group('Biometric Fingerprint Minutiae Matching Algorithm Tests', () {
    test('Exact same fingerprint template yields 100% match score', () {
      const template = 'FP_V1:abc123hash:95:W3sieCI6MTAwLCJ5IjoxNTAsInQiOjQ1LCJ0eXBlIjoxLCJxIjo4NX1d';
      final result = service.matchFingerprint(
        liveTemplate: template,
        enrolledTemplate: template,
        threshold: 75.0,
      );

      expect(result.isMatch, isTrue);
      expect(result.matchScore, 100.0);
    });

    test('Different fingerprint minutiae patterns are rejected below threshold', () {
      // Simulated distinct minutiae sets
      final fingerA = 'FP_V1:hashA:85:${base64Encode(utf8.encode(jsonEncode([
        {'x': 100, 'y': 100, 't': 30, 'type': 1, 'q': 90},
        {'x': 150, 'y': 200, 't': 45, 'type': 2, 'q': 85},
        {'x': 200, 'y': 300, 't': 60, 'type': 1, 'q': 88},
      ])))}';

      final fingerB = 'FP_V1:hashB:80:${base64Encode(utf8.encode(jsonEncode([
        {'x': 400, 'y': 450, 't': 180, 'type': 2, 'q': 80},
        {'x': 500, 'y': 550, 't': 220, 'type': 1, 'q': 75},
        {'x': 600, 'y': 650, 't': 270, 'type': 2, 'q': 85},
      ])))}';

      final result = service.matchFingerprint(
        liveTemplate: fingerA,
        enrolledTemplate: fingerB,
        threshold: 75.0,
      );

      expect(result.isMatch, isFalse);
      expect(result.matchScore, lessThan(75.0));
      expect(result.details, contains('Fingerprint Mismatch'));
    });
  });

  group('Biometric Hardware Detection Tests', () {
    test('Detects disconnected scanner when no USB hardware is connected', () async {
      final status = await service.checkFingerprintScanner(forceRefresh: true);
      // Since no physical scanner is plugged into the user machine, isConnected should be false
      expect(status.isConnected, isFalse);
      expect(status.status, anyOf('DISCONNECTED', 'NOT_READY'));
    });
  });
}
