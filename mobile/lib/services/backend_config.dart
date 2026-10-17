import 'package:flutter/foundation.dart';

/// Shared API host selection for OCR and WhatsApp.
/// Both debug and release builds target Render unless explicitly overridden.
class BackendConfig {
  static const String productionUrl = 'https://easeinn.onrender.com';
  static const String _debugOverride = String.fromEnvironment(
    'EASEINN_BACKEND_URL',
  );
  static bool get isRelease => kReleaseMode;

  static String get baseUrl {
    final override = _debugOverride.trim().replaceFirst(RegExp(r'/+$'), '');
    if (override.isNotEmpty) return override;
    return productionUrl;
  }
}
