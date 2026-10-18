import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/hotel_store.dart';

/// Shows an interactive 6-digit Email OTP confirmation bottom sheet
Future<void> showEmailOtpSheet(
  BuildContext context, {
  required String email,
  required VoidCallback onSuccess,
}) async {
  final otpController = TextEditingController();
  bool isVerifying = false;
  bool isResending = false;
  String? localError;
  String? localSuccess;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E293B), // Slate card
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.mark_email_read_rounded,
                        color: Color(0xFF10B981),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Confirm Your Email',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            email,
                            style: GoogleFonts.inter(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.pop(sheetCtx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Enter the 6-digit confirmation code sent to your email to verify your account.',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '123456',
                    hintStyle: GoogleFonts.outfit(
                      color: Colors.white24,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                    ),
                  ),
                ),
                if (localError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    localError!,
                    style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (localSuccess != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    localSuccess!,
                    style: GoogleFonts.inter(color: const Color(0xFF10B981), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: isVerifying
                      ? null
                      : () async {
                          final code = otpController.text.trim();
                          if (code.length < 6) {
                            setModalState(() {
                              localError = 'Please enter all 6 digits of the code.';
                              localSuccess = null;
                            });
                            return;
                          }
                          setModalState(() {
                            isVerifying = true;
                            localError = null;
                          });

                          final auth = AuthService();
                          final store = context.read<HotelStore>();
                          final res = await auth.verifyEmailOtp(
                            email: email,
                            token: code,
                            store: store,
                          );

                          if (!dialogCtx.mounted) return;

                          if (res.success) {
                            Navigator.pop(sheetCtx);
                            onSuccess();
                          } else {
                            setModalState(() {
                              isVerifying = false;
                              localError = res.errorMessage ?? 'Verification failed';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isVerifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Verify & Continue',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: isResending
                      ? null
                      : () async {
                          setModalState(() {
                            isResending = true;
                            localError = null;
                          });
                          final auth = AuthService();
                          final sent = await auth.resendVerificationEmail(email);
                          setModalState(() {
                            isResending = false;
                            if (sent) {
                              localSuccess = 'A new code has been sent to your email!';
                            } else {
                              localError = 'Could not resend code. Please try again.';
                            }
                          });
                        },
                  child: Text(
                    isResending ? 'Resending code...' : 'Resend Code',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
