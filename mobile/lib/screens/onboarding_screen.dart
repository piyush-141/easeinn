import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'icon': Icons.document_scanner_rounded,
      'accent': const Color(0xFF6366F1), // Indigo
      'tag': 'AI VISION OCR',
      'title': '10-Second Indian ID Check-In',
      'description':
          'Instant OCR extraction for Aadhaar, PAN, and Voter ID cards with automatic number masking and guest folio creation.',
      'metric': '98.5% Accuracy • Real-time Scan',
    },
    {
      'icon': Icons.hotel_rounded,
      'accent': const Color(0xFF0EA5E9), // Sky Blue
      'tag': 'LIVE FRONT DESK',
      'title': 'Room & Occupancy Management',
      'description':
          'Track vacant, occupied, and cleaning statuses in real time. Effortless check-ins, extensions, and check-outs across all floors.',
      'metric': 'Zero Double Bookings • Instant Status',
    },
    {
      'icon': Icons.qr_code_2_rounded,
      'accent': const Color(0xFF10B981), // Emerald
      'tag': 'INSTANT UPI PAYMENTS',
      'title': 'Dynamic QR & GST Invoicing',
      'description':
          'Accept guest payments directly to your hotel bank account with dynamic UPI QR codes and generate GST invoices on demand.',
      'metric': 'Direct Settlement • GST Ready',
    },
  ];

  Future<void> _proceedToLogin() async {
    await AuthService().setCompletedOnboarding();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _proceedToRegister() async {
    await AuthService().setCompletedOnboarding();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Header with Logo ─────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Image.asset(
                      'assets/images/easeinn_logo.png',
                      errorBuilder: (_, __, ___) => const Icon(Icons.hotel_rounded, size: 20, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'EaseInn',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _proceedToLogin,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),

            // ── Carousel ─────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  final Color accent = page['accent'] as Color;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Minimalist Icon Card
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(color: accent.withValues(alpha: 0.3), width: 1.5),
                          ),
                          child: Icon(
                            page['icon'] as IconData,
                            size: 52,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Pill Tag
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            page['tag'] as String,
                            style: GoogleFonts.inter(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Title
                        Text(
                          page['title'] as String,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Subtitle
                        Text(
                          page['description'] as String,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Metric Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 14, color: accent),
                              const SizedBox(width: 6),
                              Text(
                                page['metric'] as String,
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── Dot Indicators ────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == i ? AppTheme.brandPrimary : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Action Buttons ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                children: [
                  // Register Hotel Account
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _proceedToRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brandPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Register Hotel Account',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Existing Hotel Login
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _proceedToLogin,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Sign In to Existing Property',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
