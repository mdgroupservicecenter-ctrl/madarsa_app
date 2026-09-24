import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/services/cctv_native_face_engine.dart';

void main() {
  test('Diagnose CctvNativeFaceEngine camera', () {
    print('Testing CctvNativeFaceEngine...');
    print('isAvailable: ${CctvNativeFaceEngine.instance.isAvailable}');
    print('engineVersion: ${CctvNativeFaceEngine.instance.engineVersion}');

    if (CctvNativeFaceEngine.instance.isAvailable) {
      for (int i = 0; i < 3; i++) {
        final opened = CctvNativeFaceEngine.instance.openCamera(cameraIndex: i, width: 640, height: 480);
        print('Camera Index $i opened: $opened');
        if (opened) {
          final sw = Stopwatch()..start();
          int readCount = 0;
          for (int f = 0; f < 30; f++) {
            final jpeg = CctvNativeFaceEngine.instance.readCameraJpeg(quality: 70);
            if (jpeg != null && jpeg.isNotEmpty) {
              readCount++;
            }
            sleep(const Duration(milliseconds: 10));
          }
          sw.stop();
          print('Read $readCount frames in ${sw.elapsedMilliseconds} ms (${(readCount / (sw.elapsedMilliseconds / 1000)).toStringAsFixed(1)} FPS)');
          CctvNativeFaceEngine.instance.closeCamera();
        }
      }
    }
  });
}
