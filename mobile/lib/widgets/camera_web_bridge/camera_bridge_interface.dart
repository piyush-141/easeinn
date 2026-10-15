import 'dart:typed_data';

abstract class CameraBridge {
  bool get isSupported;
  Future<String?> initCamera();
  Future<Uint8List?> capturePhoto();
  void stopCamera();
}
