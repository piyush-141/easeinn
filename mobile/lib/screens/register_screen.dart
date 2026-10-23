import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/hotel_store.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';
import '../widgets/email_otp_dialog.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _currentStep = 1; // 1 = Hotel Property (Primary), 2 = Manager Account (Secondary)
  bool _isLoading = false;
  String? _errorMessage;

  // Manager controllers (Secondary)
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _obscurePassword = true;

  // Hotel controllers (Primary)
  final _hotelNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController(text: 'Karnataka');
  final _addressController = TextEditingController();
  final _totalRoomsController = TextEditingController(text: '16');
  final _upiIdController = TextEditingController(text: 'piyushpal427@okaxis');
  final _upiPayeeNameController = TextEditingController();

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _hotelNameController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _addressController.dispose();
    _totalRoomsController.dispose();
    _upiIdController.dispose();
    _upiPayeeNameController.dispose();
    super.dispose();
  }

  /// Step 1: Validate Hotel Property Details (Primary)
  void _validateStep1AndProceed() {
    setState(() => _errorMessage = null);

    final hotelName = _hotelNameController.text.trim();
    final city = _cityController.text.trim();

    if (hotelName.isEmpty) {
      setState(() => _errorMessage = 'Please enter your hotel or property name');
      return;
    }
    if (city.isEmpty) {
      setState(() => _errorMessage = 'Please enter the city');
      return;
    }

    setState(() => _currentStep = 2);
  }

  /// Step 2: Validate Manager Account (Secondary) and Submit Full Registration
  Future<void> _submitRegistration() async {
    setState(() => _errorMessage = null);

    final name = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your full name');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid work email address');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Please enter your contact mobile number');
      return;
    }

    final hotelName = _hotelNameController.text.trim();
    final city = _cityController.text.trim();
    final state = _stateController.text.trim();
    final address = _addressController.text.trim();
    final rooms = int.tryParse(_totalRoomsController.text.trim()) ?? 12;
    final upiId = _upiIdController.text.trim();
    final upiPayee = _upiPayeeNameController.text.trim().isNotEmpty
        ? _upiPayeeNameController.text.trim()
        : hotelName;

    setState(() => _isLoading = true);

    final authService = AuthService();
    final store = context.read<HotelStore>();

    final result = await authService.signUpHotel(
      hotelName: hotelName,
      city: city,
      state: state,
      address: address,
      totalRooms: rooms,
      upiId: upiId,
      upiPayeeName: upiPayee,
      fullName: name,
      email: email,
      password: password,
      phone: phone,
      store: store,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      if (result.requiresEmailConfirmation && result.email != null) {
        showEmailOtpSheet(
          context,
          email: result.email!,
          onSuccess: () async {
            await authService.setCompletedOnboarding();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Welcome to EaseInn! Hotel workspace is ready.'),
                backgroundColor: Color(0xFF10B981),
              ),
            );
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeShell()),
              (route) => false,
            );
          },
        );
        return;
      }

      // Mark onboarding completed
      await authService.setCompletedOnboarding();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Welcome to EaseInn! Hotel workspace is ready.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );

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
          _errorMessage = result.errorMessage ?? 'Registration failed. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            if (_currentStep == 2) {
              setState(() => _currentStep = 1);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Image.asset('assets/images/easeinn_logo.png'),
            ),
            const SizedBox(width: 8),
            Text(
              'Register Hotel Property',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Step Indicator ───────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildStepTab(
                      stepNumber: 1,
                      title: 'Hotel Property',
                      isActive: _currentStep == 1,
                      isCompleted: _currentStep > 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStepTab(
                      stepNumber: 2,
                      title: 'Manager Account',
                      isActive: _currentStep == 2,
                      isCompleted: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Error Banner if any ──────────────────────────────
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
                          style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── STEP 1: Hotel Details (Primary) ──────────────────
              if (_currentStep == 1) ...[
                Text(
                  'Hotel & Property Information',
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Register your primary hotel property first. Managers will be assigned to this hotel.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
                ),
                const SizedBox(height: 20),

                _buildTextField(
                  label: 'Hotel / Property Name',
                  controller: _hotelNameController,
                  hint: 'e.g. EaseInn Boutique & Suites',
                  icon: Icons.business_rounded,
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildTextField(
                        label: 'City',
                        controller: _cityController,
                        hint: 'e.g. Bengaluru',
                        icon: Icons.location_city_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: _buildTextField(
                        label: 'State',
                        controller: _stateController,
                        hint: 'Karnataka',
                        icon: Icons.map_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                _buildTextField(
                  label: 'Property Address',
                  controller: _addressController,
                  hint: 'e.g. 88 MG Road, Indiranagar',
                  icon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        label: 'Total Rooms',
                        controller: _totalRoomsController,
                        hint: '16',
                        icon: Icons.bed_rounded,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _buildTextField(
                        label: 'Hotel UPI ID (For Direct Payments)',
                        controller: _upiIdController,
                        hint: 'hotel@upi',
                        icon: Icons.qr_code_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _validateStep1AndProceed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Continue to Manager Account', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ],

              // ── STEP 2: Manager Account (Secondary) ──────────────
              if (_currentStep == 2) ...[
                Text(
                  'General Manager Credentials',
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set up your administrative account for front-desk operations.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
                ),
                const SizedBox(height: 20),

                _buildTextField(
                  label: 'Full Name',
                  controller: _fullNameController,
                  hint: 'e.g. Piyush Pal',
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 14),

                _buildTextField(
                  label: 'Work Email Address',
                  controller: _emailController,
                  hint: 'manager@yourhotel.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),

                _buildTextField(
                  label: 'Mobile Contact',
                  controller: _phoneController,
                  hint: '+91 98765 43210',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),

                _buildTextField(
                  label: 'Password',
                  controller: _passwordController,
                  hint: 'Minimum 6 characters',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: 28),

                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981), // Emerald
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                              const Icon(Icons.check_circle_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Launch Hotel Workspace',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Already have a hotel account? ',
                      style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Text(
                        'Sign In',
                        style: GoogleFonts.inter(
                          color: AppTheme.brandPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepTab({
    required int stepNumber,
    required String title,
    required bool isActive,
    required bool isCompleted,
  }) {
    final color = isActive
        ? AppTheme.brandPrimary
        : isCompleted
            ? const Color(0xFF10B981)
            : Colors.white24;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: isActive ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: color,
            child: isCompleted
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Text(
                    '$stepNumber',
                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? Colors.white : Colors.white60,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            prefixIcon: Icon(icon, color: Colors.white54, size: 19),
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      ],
    );
  }
}
