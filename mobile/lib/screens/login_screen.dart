import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/hotel_store.dart';
import '../theme/app_theme.dart';
import '../theme/app_brand.dart';
import 'register_screen.dart';
import 'home_shell.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/email_otp_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController(text: 'frontdesk@easeinn.com');
  final _passwordController = TextEditingController(text: 'easeinn2026');
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _performLogin([String? customEmail, String? customPassword]) async {
    final email = customEmail ?? _emailController.text.trim();
    final password = customPassword ?? _passwordController.text;

    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email address');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = AuthService();
    final store = context.read<HotelStore>();

    final result = await authService.signIn(
      email: email,
      password: password,
      store: store,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      await authService.setCompletedOnboarding();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    } else {
      if (result.requiresEmailConfirmation && result.email != null) {
        showEmailOtpSheet(
          context,
          email: result.email!,
          onSuccess: () async {
            await authService.setCompletedOnboarding();
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeShell()),
              (route) => false,
            );
          },
        );
      } else {
        setState(() {
          _errorMessage = result.errorMessage ?? 'Sign in failed. Check email or password.';
        });
      }
    }
  }

  void _quickDemoLogin() {
    _emailController.text = 'frontdesk@easeinn.com';
    _passwordController.text = 'easeinn2026';
    _performLogin('frontdesk@easeinn.com', 'easeinn2026');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Brand Logo & Header ──────────────────────────
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AppBrand.logo(
                          fit: BoxFit.contain,
                          fallbackColor: Colors.white,
                          fallbackIconSize: 36,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'EaseInn PMS',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Smart Front Desk & Indian ID OCR Verification',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Login Card ───────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B), // Slate card
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Sign In to Shift',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enter your staff email or property admin credentials.',
                          style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 20),

                        // Error Banner
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 18, color: Colors.redAccent),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Email Field
                        Text(
                          'Email Address',
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            prefixIcon: const Icon(Icons.email_outlined, color: Colors.white54, size: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.brandPrimary, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        Text(
                          'Password',
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            prefixIcon: const Icon(Icons.lock_outline, color: Colors.white54, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: Colors.white54,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.brandPrimary, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Sign In Button
                        SizedBox(
                          height: 48,
                          child: PressableScale(
                            pressedScale: 0.96,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : () => _performLogin(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.brandPrimary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Sign In to Shift',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.arrow_forward_rounded, size: 18),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Quick 1-Tap Demo Login Button
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _quickDemoLogin,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppTheme.brandAccent),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            backgroundColor: AppTheme.brandAccent.withValues(alpha: 0.1),
                          ),
                          icon: const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 19),
                          label: Text(
                            'Quick Demo Login (Devika Rao)',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Register New Hotel Link ──────────────────────
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(Icons.add_business_rounded, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'New Hotel? ',
                            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const RegisterScreen()),
                              );
                            },
                            child: Text(
                              'Register Your Property',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF10B981),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
