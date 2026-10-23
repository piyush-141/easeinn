import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../services/hotel_store.dart';
import '../services/auth_service.dart';
import '../models/property.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable_scale.dart';

// ── BUSINESS SELF PROFILE SCREEN (APPLE-LIKE, MINIMAL) ──
class HotelsScreen extends StatelessWidget {
  const HotelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final prop = store.currentProperty;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Business Profile',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.slateDark,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => _showEditHotelDialog(context, prop),
            child: Text(
              'Edit',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.brandPrimary,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. HERO BUSINESS CARD ──
              _buildHeroCard(context, prop, store),

              const SizedBox(height: 22),

              // ── 2. LOCATION & CONTACT GROUP ──
              _buildSectionHeader('CONTACT & LOCATION'),
              const SizedBox(height: 8),
              _buildGroupedCard([
                _buildSettingTile(
                  icon: Icons.location_on_rounded,
                  iconColor: const Color(0xFF2563EB),
                  iconBg: const Color(0xFFEFF6FF),
                  label: 'STREET ADDRESS',
                  value: '${prop.address}, ${prop.city}, ${prop.state} ${prop.pincode}',
                  onTap: () => _copyToClipboard(context, '${prop.address}, ${prop.city}, ${prop.state} ${prop.pincode}', 'Address copied'),
                ),
                _buildTileDivider(),
                _buildSettingTile(
                  icon: Icons.phone_rounded,
                  iconColor: const Color(0xFF16A34A),
                  iconBg: const Color(0xFFDCFCE7),
                  label: 'FRONT DESK PHONE',
                  value: prop.phone.isNotEmpty ? prop.phone : 'Not configured',
                  onTap: prop.phone.isNotEmpty
                      ? () => _copyToClipboard(context, prop.phone, 'Phone number copied')
                      : null,
                ),
                _buildTileDivider(),
                _buildSettingTile(
                  icon: Icons.alternate_email_rounded,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  label: 'OFFICIAL EMAIL',
                  value: prop.email.isNotEmpty ? prop.email : 'Not configured',
                  onTap: prop.email.isNotEmpty
                      ? () => _copyToClipboard(context, prop.email, 'Email copied')
                      : null,
                ),
              ]),

              const SizedBox(height: 22),

              // ── 3. OPERATIONS & TIMINGS GROUP ──
              _buildSectionHeader('OPERATIONS & TIMINGS'),
              const SizedBox(height: 8),
              _buildGroupedCard([
                _buildSettingTile(
                  icon: Icons.login_rounded,
                  iconColor: const Color(0xFFD97706),
                  iconBg: const Color(0xFFFEF3C7),
                  label: 'STANDARD CHECK-IN',
                  value: prop.defaultCheckInTime,
                  onTap: () => _showEditHotelDialog(context, prop),
                ),
                _buildTileDivider(),
                _buildSettingTile(
                  icon: Icons.logout_rounded,
                  iconColor: const Color(0xFFEA580C),
                  iconBg: const Color(0xFFFFEDD5),
                  label: 'STANDARD CHECK-OUT',
                  value: prop.defaultCheckOutTime,
                  onTap: () => _showEditHotelDialog(context, prop),
                ),
                _buildTileDivider(),
                _buildSettingTile(
                  icon: Icons.meeting_room_rounded,
                  iconColor: const Color(0xFF4F46E5),
                  iconBg: const Color(0xFFEEF2FF),
                  label: 'TOTAL CAPACITY',
                  value: '${prop.totalRooms} Registered Rooms',
                ),
              ]),

              const SizedBox(height: 22),

              // ── 4. TAX & PAYMENTS GROUP ──
              _buildSectionHeader('TAX & PAYMENTS'),
              const SizedBox(height: 8),
              _buildGroupedCard([
                _buildSettingTile(
                  icon: Icons.receipt_long_rounded,
                  iconColor: const Color(0xFF475569),
                  iconBg: const Color(0xFFF1F5F9),
                  label: 'GSTIN / TAX IDENTIFIER',
                  value: prop.gstNumber.isNotEmpty ? prop.gstNumber : 'Unregistered',
                  onTap: prop.gstNumber.isNotEmpty
                      ? () => _copyToClipboard(context, prop.gstNumber, 'GSTIN copied')
                      : null,
                ),
                _buildTileDivider(),
                _buildSettingTile(
                  icon: Icons.account_balance_rounded,
                  iconColor: const Color(0xFF7C3AED),
                  iconBg: const Color(0xFFF5F3FF),
                  label: 'DESK UPI ID (VPA)',
                  value: prop.upiId,
                  onTap: () => _copyToClipboard(context, prop.upiId, 'UPI ID copied'),
                ),
                _buildTileDivider(),
                _buildSettingTile(
                  icon: Icons.badge_rounded,
                  iconColor: const Color(0xFF0D9488),
                  iconBg: const Color(0xFFCCFBF1),
                  label: 'PAYEE ACCOUNT NAME',
                  value: prop.upiPayeeName,
                ),
                _buildTileDivider(),
                _buildSettingTile(
                  icon: Icons.qr_code_scanner_rounded,
                  iconColor: AppTheme.brandPrimary,
                  iconBg: AppTheme.brandLight,
                  label: 'PAYMENT QR CODE',
                  value: 'View desk scan & pay QR',
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF94A3B8)),
                  onTap: () => _showUpiQrDialog(context, prop),
                ),
              ]),

              const SizedBox(height: 24),

              // ── 5. AT LAST: BUTTON TO CHANGE BRANCH ──
              _buildSectionHeader('HOTEL BRANCHES'),
              const SizedBox(height: 8),
              PressableScale(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HotelBranchesScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.slateBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.swap_horiz_rounded,
                          color: Color(0xFF2563EB),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Change Hotel Branch',
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.slateDark,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Switch active property • ${store.properties.length} registered',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
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

  // ── 1. HERO BUSINESS CARD ──
  Widget _buildHeroCard(BuildContext context, Property prop, HotelStore store) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slateBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.brandLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: AppTheme.brandPrimary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prop.name,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${prop.hotelTier} • ${prop.city}, ${prop.state}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFFBBF7D0), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Active Branch',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                ),
                child: Text(
                  '${prop.totalRooms} Rooms',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditHotelDialog(context, prop),
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: Text(
                      'Edit Details',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.slateDark,
                      side: const BorderSide(color: AppTheme.slateBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () => _shareHotelDetails(prop),
                    icon: const Icon(Icons.share_outlined, size: 14),
                    label: Text(
                      'Share Profile',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.slateDark,
                      side: const BorderSide(color: AppTheme.slateBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── SECTION HEADER ──
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF8E8E93), // Apple secondary label
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  // ── GROUPED CARD CONTAINER (APPLE INSET STYLE) ──
  Widget _buildGroupedCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  // ── TILE DIVIDER ──
  Widget _buildTileDivider() {
    return const Divider(
      height: 1,
      thickness: 0.6,
      indent: 56,
      color: Color(0xFFF1F5F9),
    );
  }

  // ── SETTING LIST TILE (APPLE SETTINGS STYLE) ──
  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateDark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: Color(0xFFC7C7CC),
              ),
          ],
        ),
      ),
    );
  }

  // ── COPY TO CLIPBOARD HELPER ──
  void _copyToClipboard(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── SHARE HOTEL DETAILS ──
  void _shareHotelDetails(Property prop) {
    final text = '''
*${prop.name}*
${prop.hotelTier}

📍 *Address:* ${prop.address}, ${prop.city}, ${prop.state} - ${prop.pincode}
📞 *Front Desk:* ${prop.phone}
✉️ *Email:* ${prop.email}
⏰ *Timings:* Check-in: ${prop.defaultCheckInTime} | Check-out: ${prop.defaultCheckOutTime}
${prop.gstNumber.isNotEmpty ? '🧾 *GSTIN:* ${prop.gstNumber}\n' : ''}
💳 *UPI Payment:* ${prop.upiId} (${prop.upiPayeeName})
'''.trim();

    // ignore: deprecated_member_use
    Share.share(text, subject: '${prop.name} - Business Profile');
  }

  // ── UPI PAYMENT QR MODAL SHEET ──
  void _showUpiQrDialog(BuildContext context, Property prop) {
    final upiUri = 'upi://pay?pa=${prop.upiId}&pn=${Uri.encodeComponent(prop.upiPayeeName)}&cu=INR';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Desk Payment QR Code',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.slateDark,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.slateMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: QrImageView(
                data: upiUri,
                version: QrVersions.auto,
                size: 190.0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              prop.upiId,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.brandPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Payee: ${prop.upiPayeeName}',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: AppTheme.slateMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── EDIT HOTEL BRANCH DIALOG ──
  static void _showEditHotelDialog(BuildContext context, Property prop) {
    final nameCtrl = TextEditingController(text: prop.name);
    final tierCtrl = TextEditingController(text: prop.hotelTier);
    final addressCtrl = TextEditingController(text: prop.address);
    final cityCtrl = TextEditingController(text: prop.city);
    final stateCtrl = TextEditingController(text: prop.state);
    final pincodeCtrl = TextEditingController(text: prop.pincode);
    final phoneCtrl = TextEditingController(text: prop.phone);
    final emailCtrl = TextEditingController(text: prop.email);
    final gstCtrl = TextEditingController(text: prop.gstNumber);
    final checkInTimeCtrl = TextEditingController(text: prop.defaultCheckInTime);
    final checkOutTimeCtrl = TextEditingController(text: prop.defaultCheckOutTime);
    final upiCtrl = TextEditingController(text: prop.upiId);
    final payeeCtrl = TextEditingController(text: prop.upiPayeeName);

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
              child: const Icon(Icons.business_rounded, color: AppTheme.brandPrimary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Edit Business Details',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDialogField('Hotel Branch Name', nameCtrl, ''),
              const SizedBox(height: 10),
              _buildDialogField('Classification / Tier', tierCtrl, 'e.g. Boutique Hotel'),
              const SizedBox(height: 10),
              _buildDialogField('Street Address', addressCtrl, ''),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildDialogField('City', cityCtrl, '')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDialogField('State', stateCtrl, '')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildDialogField('Pincode', pincodeCtrl, '')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDialogField('Desk Phone', phoneCtrl, '')),
                ],
              ),
              const SizedBox(height: 10),
              _buildDialogField('Official Email', emailCtrl, ''),
              const SizedBox(height: 10),
              _buildDialogField('GSTIN / Business Tax ID', gstCtrl, '29ABCDE1234F1Z5'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildDialogField('Standard Check-In', checkInTimeCtrl, '12:00 PM')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDialogField('Standard Check-Out', checkOutTimeCtrl, '11:00 AM')),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppTheme.slateBorder),
              const SizedBox(height: 8),
              Text(
                'Bank & UPI QR Payment Details',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
              ),
              const SizedBox(height: 8),
              _buildDialogField('UPI VPA / Bank ID *', upiCtrl, 'e.g. piyushpal427@okaxis'),
              const SizedBox(height: 10),
              _buildDialogField('Payee Account Name *', payeeCtrl, 'e.g. Piyush Pal'),
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
              context.read<HotelStore>().updatePropertyDetails(
                propertyId: prop.id,
                name: nameCtrl.text,
                address: addressCtrl.text,
                city: cityCtrl.text,
                state: stateCtrl.text,
                pincode: pincodeCtrl.text,
                phone: phoneCtrl.text,
                email: emailCtrl.text,
                upiId: upiCtrl.text,
                upiPayeeName: payeeCtrl.text,
                gstNumber: gstCtrl.text,
                defaultCheckInTime: checkInTimeCtrl.text,
                defaultCheckOutTime: checkOutTimeCtrl.text,
                hotelTier: tierCtrl.text,
              );
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile details updated!')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save Details'),
          ),
        ],
      ),
    );
  }

  // ── DIALOG FIELD BUILDER ──
  static Widget _buildDialogField(String label, TextEditingController ctrl, String hint, {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slateDark)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 13, color: AppTheme.slateDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12, color: AppTheme.slateMuted),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.slateBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.slateBorder)),
          ),
        ),
      ],
    );
  }
}

// ── HOTEL BRANCHES SELECTION & PORTFOLIO SCREEN ──
class HotelBranchesScreen extends StatelessWidget {
  const HotelBranchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Hotel Branches',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.slateDark,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Add Branch',
            icon: const Icon(Icons.add_business_rounded, color: AppTheme.brandPrimary),
            onPressed: () => _showAddHotelDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: store.properties.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final prop = store.properties[index];
                  final isActive = prop.id == store.currentProperty.id;

                  return PressableScale(
                    pressedScale: 0.98,
                    onTap: () {
                      if (!isActive) {
                        store.switchProperty(prop.id);
                        AuthService().updateCachedProperty(prop.id, prop.name);
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Switched to ${prop.name}')),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive ? AppTheme.brandPrimary : AppTheme.slateBorder,
                          width: isActive ? 1.8 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isActive
                                ? AppTheme.brandPrimary.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: isActive ? AppTheme.brandLight : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.hotel_rounded,
                                  color: isActive ? AppTheme.brandPrimary : AppTheme.slateMuted,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      prop.name,
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                    Text(
                                      '${prop.hotelTier} • ${prop.city}, ${prop.state}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        color: AppTheme.slateMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0FDF4),
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(color: const Color(0xFFBBF7D0), width: 0.8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF16A34A),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Active',
                                        style: GoogleFonts.inter(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF15803D),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Compact meta
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildBranchMetaRow(Icons.place_outlined, '${prop.address}, ${prop.pincode}'),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Expanded(child: _buildBranchMetaRow(Icons.phone_outlined, prop.phone)),
                                    Expanded(child: _buildBranchMetaRow(Icons.meeting_room_outlined, '${prop.totalRooms} Rooms')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => HotelsScreen._showEditHotelDialog(context, prop),
                                icon: const Icon(Icons.edit_outlined, size: 13),
                                label: const Text('Edit', style: TextStyle(fontSize: 11.5)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.slateDark,
                                  side: const BorderSide(color: AppTheme.slateBorder),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  minimumSize: const Size(0, 32),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: isActive
                                    ? Container(
                                        height: 32,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Currently Active',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF64748B),
                                          ),
                                        ),
                                      )
                                    : ElevatedButton(
                                        onPressed: () {
                                          store.switchProperty(prop.id);
                                          AuthService().updateCachedProperty(prop.id, prop.name);
                                          Navigator.of(context).pop();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Switched to ${prop.name}')),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.brandPrimary,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          minimumSize: const Size(0, 32),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        child: const Text('Switch Branch', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                      ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _showAddHotelDialog(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.brandPrimary, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add_business_rounded, color: AppTheme.brandPrimary, size: 18),
                label: Text(
                  'Add New Hotel Branch',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildBranchMetaRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppTheme.slateMuted),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateDark),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ── ADD NEW HOTEL BRANCH DIALOG ──
  static void _showAddHotelDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final tierCtrl = TextEditingController(text: 'Boutique Hotel');
    final cityCtrl = TextEditingController(text: 'Bengaluru');
    final stateCtrl = TextEditingController(text: 'Karnataka');
    final addressCtrl = TextEditingController();
    final pincodeCtrl = TextEditingController(text: '560038');
    final phoneCtrl = TextEditingController(text: '+91 ');
    final emailCtrl = TextEditingController();
    final roomsCtrl = TextEditingController(text: '12');
    final gstCtrl = TextEditingController(text: '29ABCDE1234F1Z5');
    final checkInTimeCtrl = TextEditingController(text: '12:00 PM');
    final checkOutTimeCtrl = TextEditingController(text: '11:00 AM');
    final upiCtrl = TextEditingController(text: 'piyushpal427@okaxis');
    final payeeCtrl = TextEditingController(text: 'Piyush Pal');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Register New Hotel Branch',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HotelsScreen._buildDialogField('Hotel Name *', nameCtrl, 'e.g. EaseInn Lakeview Heritage'),
              const SizedBox(height: 10),
              HotelsScreen._buildDialogField('Property Category / Tier', tierCtrl, 'e.g. Boutique Hotel, Resort, Suites'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: HotelsScreen._buildDialogField('City', cityCtrl, '')),
                  const SizedBox(width: 8),
                  Expanded(child: HotelsScreen._buildDialogField('State', stateCtrl, '')),
                ],
              ),
              const SizedBox(height: 10),
              HotelsScreen._buildDialogField('Street Address', addressCtrl, 'e.g. 14 MG Road'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: HotelsScreen._buildDialogField('Pincode', pincodeCtrl, '')),
                  const SizedBox(width: 8),
                  Expanded(child: HotelsScreen._buildDialogField('Room Inventory', roomsCtrl, '12', keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: HotelsScreen._buildDialogField('Default Check-In', checkInTimeCtrl, '12:00 PM')),
                  const SizedBox(width: 8),
                  Expanded(child: HotelsScreen._buildDialogField('Default Check-Out', checkOutTimeCtrl, '11:00 AM')),
                ],
              ),
              const SizedBox(height: 10),
              HotelsScreen._buildDialogField('GSTIN / Tax ID', gstCtrl, 'e.g. 29ABCDE1234F1Z5'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: HotelsScreen._buildDialogField('Front Desk Phone', phoneCtrl, '')),
                  const SizedBox(width: 8),
                  Expanded(child: HotelsScreen._buildDialogField('Official Email', emailCtrl, '')),
                ],
              ),
              const SizedBox(height: 10),
              HotelsScreen._buildDialogField('Branch Bank / UPI ID (VPA) *', upiCtrl, 'e.g. piyushpal427@okaxis'),
              const SizedBox(height: 10),
              HotelsScreen._buildDialogField('Payee Account Name *', payeeCtrl, 'e.g. Piyush Pal'),
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
              final newP = context.read<HotelStore>().addNewProperty(
                name: nameCtrl.text.trim(),
                city: cityCtrl.text.trim(),
                state: stateCtrl.text.trim(),
                address: addressCtrl.text.trim(),
                phone: phoneCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                totalRooms: int.tryParse(roomsCtrl.text) ?? 12,
                upiId: upiCtrl.text.trim().isEmpty ? 'piyushpal427@okaxis' : upiCtrl.text.trim(),
                upiPayeeName: payeeCtrl.text.trim().isEmpty ? nameCtrl.text.trim() : payeeCtrl.text.trim(),
              );
              AuthService().updateCachedProperty(newP.id, newP.name);
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Switched to ${nameCtrl.text.trim()}')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Register & Activate'),
          ),
        ],
      ),
    );
  }
}
