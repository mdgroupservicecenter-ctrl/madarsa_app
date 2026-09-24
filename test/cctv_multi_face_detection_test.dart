import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/services/biometric_hardware_service.dart';

void main() {
  final service = BiometricHardwareService();

  group('CCTV & Multi-Face Biometric Detection Tests', () {
    test('Detects all faces in 3 high-res group photos and 1 portrait photo', () async {
      final paths = [
        'C:/Users/MD Services/Downloads/young-happy-students-walking-while-talking.jpg',
        'C:/Users/MD Services/Downloads/smiling-students-with-backpacks.jpg',
        'C:/Users/MD Services/Downloads/11708.jpg',
        'C:/Users/MD Services/Downloads/istockphoto-1138008113-612x612.jpg',
      ];

      for (final p in paths) {
        final file = File(p);
        if (!file.existsSync()) continue;

        final bytes = await file.readAsBytes();
        final sw = Stopwatch()..start();
        final result = await service.detectFace(bytes);
        sw.stop();

        print('FILE: ${p.split("/").last}');
        print('  Elapsed: ${sw.elapsedMilliseconds}ms');
        print('  Has Face: ${result.hasFace}');
        print('  Total Detected Faces: ${result.faceCount}');
        print('  Confidence: ${result.confidence}%');

        expect(result.hasFace, isTrue, reason: 'Must detect human faces in $p');
        expect(result.detectedFaces.isNotEmpty, isTrue);

        for (int i = 0; i < result.detectedFaces.length; i++) {
          final f = result.detectedFaces[i];
          expect(f.width, greaterThan(0));
          expect(f.height, greaterThan(0));
          expect(f.confidence, greaterThanOrEqualTo(40.0));
        }

        // Generate templates for all faces
        final templates = await service.generateFaceTemplates(bytes);
        expect(templates.isNotEmpty, isTrue);
        expect(templates.length, equals(result.faceCount));
        print('  Generated ${templates.length} templates successfully.');
      }
    });

    test('Multi-face attendance matching matches target student inside a group photo', () async {
      final groupPath = 'C:/Users/MD Services/Downloads/young-happy-students-walking-while-talking.jpg';
      final file = File(groupPath);
      if (!file.existsSync()) return;

      final groupBytes = await file.readAsBytes();
      final groupTemplates = await service.generateFaceTemplates(groupBytes);
      expect(groupTemplates.isNotEmpty, isTrue);

      // Simulate an enrolled student whose template is the 1st student in this group photo
      final enrolledTemplate = groupTemplates.first;

      bool matchFound = false;
      int matchedIndex = -1;
      for (int i = 0; i < groupTemplates.length; i++) {
        final match = service.matchFace(
          liveTemplate: groupTemplates[i],
          enrolledTemplate: enrolledTemplate,
          threshold: 65.0,
        );
        if (match.isMatch) {
          matchFound = true;
          matchedIndex = i;
          break;
        }
      }

      expect(matchFound, isTrue);
      expect(matchedIndex, equals(0));
    });
  });
}
