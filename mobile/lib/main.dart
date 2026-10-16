import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/hotel_store.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (SupabaseConfig.isConfigured) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        // ignore: deprecated_member_use
        anonKey: SupabaseConfig.publishableKey,
      );
      debugPrint('[Supabase] Initialized successfully with ${SupabaseConfig.url}');
    }
  } catch (e) {
    debugPrint('[Supabase] Init error (running with offline cache): $e');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => HotelStore(),
      child: const EaseInnApp(),
    ),
  );
}

class EaseInnApp extends StatelessWidget {
  const EaseInnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EaseInn PMS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
