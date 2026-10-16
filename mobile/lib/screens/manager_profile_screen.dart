import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/hotel_store.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable_scale.dart';
import 'login_screen.dart';

class ManagerProfileScreen extends StatefulWidget {
  const ManagerProfileScreen({super.key});

  @override
  State<ManagerProfileScreen> createState() => _ManagerProfileScreenState();
}

class _ManagerProfileScreenState extends State<ManagerProfileScreen> {
  // Edit Profile Dialog
  void _showEditProfileDialog(BuildContext context, HotelStore store) {
    final nameCtrl = TextEditingController(text: store.staffName);
    final roleCtrl = TextEditingController(text: store.staffRole);
    final emailCtrl = TextEditingController(text: store.staffEmail);
    final phoneCtrl = TextEditingController(text: store.staffPhone);
    final empIdCtrl = TextEditingController(text: store.staffEmployeeId);
    final emergencyCtrl = TextEditingController(text: store.staffEmergencyContact);
    final shiftCtrl = TextEditingController(text: store.staffCurrentShift);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.brandLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_rounded, color: AppTheme.brandPrimary, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'Edit Manager Profile',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildField('Full Name *', nameCtrl, 'e.g. Devika Rao'),
              const SizedBox(height: 12),
              _buildField('Designation / Role *', roleCtrl, 'e.g. General Manager'),
              const SizedBox(height: 12),
              _buildField('Staff / Employee ID', empIdCtrl, 'e.g. EAS-MGR-009'),
              const SizedBox(height: 12),
              _buildField('Work Email *', emailCtrl, 'devika.rao@easeinn.com', keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _buildField('Phone Number *', phoneCtrl, '+91 98450 11223', keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _buildField('Emergency Contact Number', emergencyCtrl, '+91 98450 99887', keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _buildField('Current Assigned Shift', shiftCtrl, 'Morning (07:00 AM - 03:30 PM)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.slateMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              store.updateStaffProfile(
                name: nameCtrl.text.trim(),
                role: roleCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                phone: phoneCtrl.text.trim(),
                employeeId: empIdCtrl.text.trim(),
                emergencyContact: emergencyCtrl.text.trim(),
                currentShift: shiftCtrl.text.trim(),
              );
              AuthService().updateCachedProfile(
                name: nameCtrl.text.trim(),
                role: roleCtrl.text.trim(),
                email: emailCtrl.text.trim(),
              );
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Manager profile updated successfully'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  // Change Password Dialog
  void _showChangePasswordDialog(BuildContext context, HotelStore store) {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: Color(0xFFD97706), size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'Change Password',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ensure your account is protected with a strong, distinct password.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
                  ),
                  const SizedBox(height: 14),
                  _buildPasswordField(
                    'Current Password',
                    currentPassCtrl,
                    obscureCurrent,
                    () => setDialogState(() => obscureCurrent = !obscureCurrent),
                  ),
                  const SizedBox(height: 12),
                  _buildPasswordField(
                    'New Password',
                    newPassCtrl,
                    obscureNew,
                    () => setDialogState(() => obscureNew = !obscureNew),
                  ),
                  const SizedBox(height: 12),
                  _buildPasswordField(
                    'Confirm New Password',
                    confirmPassCtrl,
                    obscureConfirm,
                    () => setDialogState(() => obscureConfirm = !obscureConfirm),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel', style: TextStyle(color: AppTheme.slateMuted)),
              ),
              ElevatedButton(
                onPressed: () {
                  if (newPassCtrl.text.isEmpty || newPassCtrl.text != confirmPassCtrl.text) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Passwords do not match or cannot be empty!'),
                        backgroundColor: Color(0xFFDC2626),
                      ),
                    );
                    return;
                  }
                  store.changePassword(
                    currentPassword: currentPassCtrl.text,
                    newPassword: newPassCtrl.text,
                  );
                  Navigator.of(dialogCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password updated successfully!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brandPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Update Password'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint, {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.slateDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.slateBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.slateBorder)),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField(String label, TextEditingController ctrl, bool obscure, VoidCallback toggle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.slateDark),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: AppTheme.slateMuted),
              onPressed: toggle,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.slateBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.slateBorder)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Manager Profile',
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
        ),
        actions: [
          // Cloud Sync Button
          IconButton(
            tooltip: 'Sync Data with Cloud',
            icon: store.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brandPrimary),
                  )
                : const Icon(Icons.sync_rounded, color: AppTheme.brandPrimary),
            onPressed: store.isSyncing
                ? null
                : () async {
                    await store.syncData();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.cloud_done_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('PMS database & local caches synced with cloud!'),
                            ],
                          ),
                          backgroundColor: Color(0xFF16A34A),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppTheme.slateBorder, height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. MANAGER HERO CARD
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.slateBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: AppTheme.brandPrimary,
                              child: Text(
                                store.staffName.isNotEmpty ? store.staffName.substring(0, 1) : 'D',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 30,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.verified_rounded, size: 13, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      store.staffName,
                                      style: GoogleFonts.outfit(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.brandLight,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      store.staffRole,
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.brandDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                store.staffEmail,
                                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${store.staffPhone} • ID: ${store.staffEmployeeId}',
                                style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.slateMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFFF1F5F9), height: 1),
                    const SizedBox(height: 12),
                    // Actions: Edit Profile & Change Password
                    Row(
                      children: [
                        Expanded(
                          child: PressableScale(
                            pressedScale: 0.95,
                            child: OutlinedButton.icon(
                              onPressed: () => _showEditProfileDialog(context, store),
                              icon: const Icon(Icons.edit_outlined, size: 15),
                              label: const Text('Edit Profile'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.slateDark,
                                side: const BorderSide(color: AppTheme.slateBorder),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PressableScale(
                            pressedScale: 0.95,
                            child: OutlinedButton.icon(
                              onPressed: () => _showChangePasswordDialog(context, store),
                              icon: const Icon(Icons.lock_outline_rounded, size: 15),
                              label: const Text('Change Password'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.slateDark,
                                side: const BorderSide(color: AppTheme.slateBorder),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 2. MANAGER WORK & SHIFT DETAILS
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.brandLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.badge_outlined, color: AppTheme.brandPrimary, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Employment & Operational Info',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildInfoRow(Icons.schedule_rounded, 'Assigned Shift', store.staffCurrentShift),
                    _buildInfoRow(Icons.pin_outlined, 'Employee Badge ID', store.staffEmployeeId),
                    _buildInfoRow(Icons.contact_phone_outlined, 'Emergency Contact', store.staffEmergencyContact),
                    _buildInfoRow(Icons.admin_panel_settings_outlined, 'Security Clearance', 'Full Access (${store.staffRole} Level)'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 3. CLOUD SYNC & OFFLINE CACHE STATUS CARD
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.cloud_done_rounded, color: Color(0xFF10B981), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cloud Data Sync',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          Text(
                            store.lastSyncTime != null
                                ? 'Last synced: ${DateFormat('hh:mm a, d MMM').format(store.lastSyncTime!)}'
                                : 'Not synced yet',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                          ),
                        ],
                      ),
                    ),
                    PressableScale(
                      pressedScale: 0.94,
                      child: ElevatedButton(
                        onPressed: store.isSyncing
                            ? null
                            : () async {
                                await store.syncData();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('PMS database synced with cloud!'),
                                      backgroundColor: Color(0xFF16A34A),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brandPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: store.isSyncing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Sync Now', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 4. MANAGER NOTIFICATION & APP PREFERENCES
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.notifications_active_outlined, color: Color(0xFFD97706), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Manager Notifications & Security',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeThumbColor: AppTheme.brandPrimary,
                      title: Text(
                        'Check-In & Check-Out Alerts',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.slateDark),
                      ),
                      subtitle: Text(
                        'Receive real-time notifications when guests check in or out',
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                      ),
                      value: store.notificationCheckInAlerts,
                      onChanged: (val) => store.toggleNotifications(checkIn: val),
                    ),
                    const Divider(color: Color(0xFFF1F5F9)),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeThumbColor: AppTheme.brandPrimary,
                      title: Text(
                        'UPI & Direct Payment Alerts',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.slateDark),
                      ),
                      subtitle: Text(
                        'Instant push notification on successful advance / settlement payments',
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                      ),
                      value: store.notificationPaymentAlerts,
                      onChanged: (val) => store.toggleNotifications(payment: val),
                    ),
                    const Divider(color: Color(0xFFF1F5F9)),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeThumbColor: AppTheme.brandPrimary,
                      title: Text(
                        'Biometric / Fingerprint App Unlock',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.slateDark),
                      ),
                      subtitle: Text(
                        'Require FaceID or fingerprint unlock to access PMS management',
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                      ),
                      value: store.biometricAuthEnabled,
                      onChanged: (val) => store.toggleBiometrics(val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Log Out Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: PressableScale(
                  pressedScale: 0.96,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmSignOut(context, store),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      backgroundColor: const Color(0xFFFEF2F2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 20),
                    label: Text(
                      'Sign Out from Shift / Account',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, HotelStore store) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Sign Out',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to sign out from ${store.currentProperty.name}? You will need to log in again to access front-desk management.',
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.slateMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.slateDark),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await AuthService().signOut(store);
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.slateMuted),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slateDark),
            ),
          ),
        ],
      ),
    );
  }
}
