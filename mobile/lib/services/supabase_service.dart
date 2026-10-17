import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // Keep mobile authentication on the same Supabase project as the web app
  // and the Render WhatsApp token verifier.
  static const String url = 'https://pvydmztbjyrqefaqdqhb.supabase.co';
  static const String publishableKey =
      'sb_publishable__U1X_V5sTRpj3Yr2N1x_mw_ejQD0IUV';

  static bool get isConfigured =>
      url.isNotEmpty &&
      publishableKey.isNotEmpty &&
      !url.contains('placeholder');

  static SupabaseClient? get client {
    try {
      if (isConfigured) {
        return Supabase.instance.client;
      }
    } catch (_) {}
    return null;
  }
}
