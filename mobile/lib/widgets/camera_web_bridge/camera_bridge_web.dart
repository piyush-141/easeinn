// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: undefined_prefixed_name
import 'dart:ui_web' as ui_web;
import 'dart:convert';
import 'dart:typed_data';
import 'camera_bridge_interface.dart';

CameraBridge getCameraBridge() => WebCameraBridge();

class WebCameraBridge implements CameraBridge {
  html.VideoElement? _videoElement;
  html.MediaStream? _mediaStream;

  @override
  bool get isSupported => true;

  @override
  Future<String?> initCamera() async {
    final viewId = 'camera-view-${DateTime.now().microsecondsSinceEpoch}';
    final video = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.borderRadius = '24px 24px 0 0';

    ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) => video);

    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      throw Exception('Camera device not supported by this browser.');
    }

    final stream = await mediaDevices.getUserMedia({
      'video': {
        'facingMode': {'ideal': 'environment'},
        'width': {'ideal': 1920},
        'height': {'ideal': 1080},
      },
      'audio': false,
    });

    video.srcObject = stream;
    _videoElement = video;
    _mediaStream = stream;
    return viewId;
  }

  @override
  Future<Uint8List?> capturePhoto() async {
    if (_videoElement == null) return null;
    final videoWidth = _videoElement!.videoWidth;
    final videoHeight = _videoElement!.videoHeight;
    final w = videoWidth > 0 ? videoWidth : 1280;
    final h = videoHeight > 0 ? videoHeight : 720;

    final canvas = html.CanvasElement(width: w, height: h);
    canvas.context2D.drawImage(_videoElement!, 0, 0);

    final dataUrl = canvas.toDataUrl('image/jpeg', 0.92);
    final base64String = dataUrl.split(',')[1];
    return base64Decode(base64String);
  }

  @override
  void stopCamera() {
    if (_mediaStream != null) {
      for (final track in _mediaStream!.getTracks()) {
        track.stop();
      }
      _mediaStream = null;
    }
  }
}
