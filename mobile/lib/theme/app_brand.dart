import 'package:flutter/material.dart';

/// Single source of truth for EaseInn's primary logo & branding.
///
/// To switch the logo across the ENTIRE app, simply change [primaryLogoSrc].
/// - If it starts with 'http://' or 'https://', it loads dynamically over network.
/// - If it is a local path (e.g. 'assets/images/mascot-logo.png'), it loads from bundle assets.
///
/// To also update the native launcher icon (Android, iOS, Web, Windows) whenever
/// you switch the asset path, run:
///   `dart run flutter_launcher_icons`
class AppBrand {
  AppBrand._();

  /// 🔹 PRIMARY APP LOGO FLAG:
  /// Provide any local asset path (e.g., 'assets/images/mascot-logo.png')
  /// OR any remote URL (e.g., 'https://your-domain.com/new-logo.png').
  /// Changing this single string instantly updates the logo across every screen in the app.
  static const String primaryLogoSrc = 'assets/images/mascot-logo.png';

  /// Whether [primaryLogoSrc] is a remote web URL
  static bool get isNetworkLogo =>
      primaryLogoSrc.startsWith('http://') || primaryLogoSrc.startsWith('https://');

  /// Universal Logo Widget that automatically handles network vs local asset,
  /// sizing, fit, and error fallback.
  static Widget logo({
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    Color? fallbackColor,
    double fallbackIconSize = 24,
  }) {
    if (isNetworkLogo) {
      return Image.network(
        primaryLogoSrc,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.hotel_rounded,
          size: fallbackIconSize,
          color: fallbackColor ?? const Color(0xFF0066CC),
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return SizedBox(
            width: width,
            height: height,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      );
    }

    return Image.asset(
      primaryLogoSrc,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.hotel_rounded,
        size: fallbackIconSize,
        color: fallbackColor ?? const Color(0xFF0066CC),
      ),
    );
  }
}
