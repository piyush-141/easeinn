import 'dart:typed_data';
import 'camera_bridge_interface.dart';

CameraBridge getCameraBridge() => StubCameraBridge();

class StubCameraBridge implements CameraBridge {
  @override
  bool get isSupported => false;

  @override
  Future<String?> initCamera() async => null;

  @override
  Future<Uint8List?> capturePhoto() async => null;

  @override
  void stopCamera() {}
}
