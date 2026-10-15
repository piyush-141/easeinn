import 'camera_bridge_interface.dart';
import 'camera_bridge_stub.dart'
    if (dart.library.html) 'camera_bridge_web.dart';

CameraBridge createCameraBridge() => getCameraBridge();
