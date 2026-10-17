import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/hotel_store.dart';
import '../theme/app_theme.dart';
import 'onboarding_screen.dart';
import 'login_screen.dart';
import 'home_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );

    _fadeController.forward();
    _bootApp();
  }

  Future<void> _bootApp() async {
    final startTime = DateTime.now();
    final authService = AuthService();
    final store = context.read<HotelStore>();

    final bool onboardingDone = await authService.hasCompletedOnboarding();
    final bool hasValidSession = await authService.checkInitialSession(store);

    // Keep splash visible for minimum ~700ms for smooth initial load
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed < const Duration(milliseconds: 700)) {
      await Future.delayed(const Duration(milliseconds: 700) - elapsed);
    }

    if (!mounted) return;

    if (!onboardingDone) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => const OnboardingScreen(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    } else if (!hasValidSession) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => const HomeShell(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate
      body: Stack(
        children: [
          // Subtle background gradient glow
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.brandPrimary.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.brandAccent.withValues(alpha: 0.12),
              ),
            ),
          ),

          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand Logo with clean container
                    Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/images/easeinn_logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.hotel_rounded,
                            size: 44,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // App Title
                    Text(
                      'EaseInn',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Tagline
                    Text(
                      'HOSPITALITY OS & SMART PMS',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom version & status indicator
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.brandPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'v1.0.0 • Verified Front Desk',
                    style: GoogleFonts.inter(
                      color: Colors.white30,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
