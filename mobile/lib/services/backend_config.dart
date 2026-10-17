import 'dart:io';

import 'package:flutter/foundation.dart';

/// Shared API host selection for OCR and WhatsApp.
/// Debug builds target the local server; release builds target Render.
class BackendConfig {
  static const String productionUrl = 'https://easeinn.onrender.com';
  static const String _debugOverride = String.fromEnvironment(
    'EASEINN_BACKEND_URL',
  );
  static bool get isRelease => kReleaseMode;

  static String get baseUrl {
    if (kReleaseMode) return productionUrl;

    final override = _debugOverride.trim().replaceFirst(RegExp(r'/+$'), '');
    if (override.isNotEmpty) return override;
    if (kIsWeb) return 'http://localhost:3001';
    if (Platform.isAndroid) return 'http://10.0.2.2:3001';
    return 'http://localhost:3001';
  }
}
