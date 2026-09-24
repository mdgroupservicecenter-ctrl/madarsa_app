import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/services/biometric_hardware_service.dart';
import 'package:madarsa_app/core/services/cctv_native_face_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('C++ Native CCTV Face Engine (Dart FFI) Tests', () {
    late CctvNativeFaceEngine engine;

    setUp(() {
      engine = CctvNativeFaceEngine();
    });

    test('Loads C++ native DLL and returns version 251', () {
      expect(engine.isAvailable, isTrue, reason: 'cctv_face_engine.dll should be loaded on Windows');
      expect(engine.engineVersion, equals(251));
      print('C++ Native Engine is available! Version: ${engine.engineVersion}');
    });

    test('Fast C++ SIMD template matching test', () {
      final vecA = Float32List(176);
      final vecB = Float32List(176);

      for (int i = 0; i < 176; i++) {
        vecA[i] = (i % 10) / 10.0;
        vecB[i] = (i % 10) / 10.0;
      }

      // Self-match should yield 100% confidence
      final selfScore = engine.matchTemplates(vecA, vecB);
      expect(selfScore, greaterThan(90.0));
      print('C++ SIMD Self-Match Score: $selfScore%');

      // Batch matching against 100 simulated enrolled templates
      final db = List.generate(100, (idx) {
        final v = Float32List(176);
        for (int i = 0; i < 176; i++) {
          v[i] = ((idx + i) % 15) / 15.0;
        }
        return v;
      });
      // Insert exact match at index 42
      db[42] = vecA;

      final sw = Stopwatch()..start();
      final match = engine.batchMatch(probe: vecA, enrolledList: db, threshold: 70.0);
      sw.stop();

      print('C++ Batch match over 100 students took: ${sw.elapsedMicroseconds} microseconds (${sw.elapsedMilliseconds} ms)');
      expect(match.bestIndex, equals(42));
      expect(match.confidence, greaterThan(90.0));
    });

    test('C++ Multi-Face Detection on real student photo', () async {
      final testFile = File('assets/test_faces/11708.jpg');
      if (!testFile.existsSync()) return;

      final bytes = await testFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(byteData, isNotNull);

      final rgba = byteData!.buffer.asUint8List();
      final width = image.width;
      final height = image.height;

      final sw = Stopwatch()..start();
      final faces = engine.detectFaces(
        rgba: rgba,
        width: width,
        height: height,
        sensitivity: FaceDetectionSensitivity.balanced,
      );
      sw.stop();

      print('C++ Native detectFaces found ${faces.length} faces in ${sw.elapsedMilliseconds} ms (${sw.elapsedMicroseconds} us)!');
      expect(faces.isNotEmpty, isTrue);

      final primary = faces.first;
      print('First Face: [${primary.left}, ${primary.top}, ${primary.right}, ${primary.bottom}] confidence: ${primary.confidence}%');

      // Extract 176-D template in C++
      final rect = ui.Rect.fromLTRB(
        primary.left.toDouble(),
        primary.top.toDouble(),
        primary.right.toDouble(),
        primary.bottom.toDouble(),
      );

      final tmpl = engine.extractTemplate(
        rgba: rgba,
        width: width,
        height: height,
        faceRect: rect,
      );
      expect(tmpl, isNotNull);
      expect(tmpl!.length, equals(176));
      print('C++ Extracted 176-D template successfully!');
    });

    test('C++ Direct JPEG Face Detection & Template Extraction (Fast Path)', () async {
      final testFile = File('assets/test_faces/11708.jpg');
      if (!testFile.existsSync()) return;

      final jpegBytes = await testFile.readAsBytes();

      final sw = Stopwatch()..start();
      final res = engine.detectFacesJpeg(
        jpegBytes: jpegBytes,
        sensitivity: FaceDetectionSensitivity.balanced,
      );
      sw.stop();

      print('C++ detectFacesJpeg found ${res.faces.length} faces in ${sw.elapsedMicroseconds} us (${sw.elapsedMilliseconds} ms)! [Image size: ${res.width}x${res.height}]');
      expect(res.faces, isNotEmpty);
      expect(res.width, greaterThan(0));
      expect(res.height, greaterThan(0));

      final firstFace = res.faces.first;
      print('FirstFace livenessScore: ${firstFace.livenessScore}%, isLiveFace: ${firstFace.isLiveFace}');
      final faceRect = ui.Rect.fromLTRB(
        firstFace.left.toDouble(),
        firstFace.top.toDouble(),
        firstFace.right.toDouble(),
        firstFace.bottom.toDouble(),
      );

      final sw2 = Stopwatch()..start();
      final tpl = engine.extractTemplateJpeg(jpegBytes: jpegBytes, faceRect: faceRect);
      sw2.stop();

      print('C++ extractTemplateJpeg extracted 176-D vector in ${sw2.elapsedMicroseconds} us (${sw2.elapsedMilliseconds} ms)!');
      expect(tpl, isNotNull);
      expect(tpl!.length, equals(176));

      // Cosine similarity test
      final sim = CctvNativeFaceEngine.cosineSimilarity(tpl, tpl);
      expect(sim, greaterThan(99.0));
      print('Dart cosineSimilarity self-score: $sim%');
    });

    test('C++ Anti-Spoofing on True Real Face vs Fake Spoof Face', () async {
      final realFile = File('image_T1.jpg');
      final fakeFile = File('image_F1.jpg');
      if (!realFile.existsSync()) return;

      final realBytes = await realFile.readAsBytes();
      final resReal = engine.detectFacesJpeg(jpegBytes: realBytes);
      print('Real Image (image_T1.jpg) faces: ${resReal.faces.length}');
      if (resReal.faces.isNotEmpty) {
        final f = resReal.faces.first;
        print('REAL HUMAN: livenessScore=${f.livenessScore}%, isLiveFace=${f.isLiveFace}, blurScore=${f.blurScore}');
      }

      if (fakeFile.existsSync()) {
        final fakeBytes = await fakeFile.readAsBytes();
        final resFake = engine.detectFacesJpeg(jpegBytes: fakeBytes);
        print('Fake Image (image_F1.jpg) faces: ${resFake.faces.length}');
        if (resFake.faces.isNotEmpty) {
          final f = resFake.faces.first;
          print('FAKE SPOOF: livenessScore=${f.livenessScore}%, isLiveFace=${f.isLiveFace}, blurScore=${f.blurScore}');
        }
      }
    });
  });
}
