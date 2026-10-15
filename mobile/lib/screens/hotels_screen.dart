import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/hotel_store.dart';
import '../models/property.dart';
import '../theme/app_theme.dart';

class HotelsScreen extends StatelessWidget {
  const HotelsScreen({super.key});

  void _showAddHotelDialog(BuildContext context) {
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
              _buildDialogField('Hotel Name *', nameCtrl, 'e.g. EaseInn Lakeview Heritage'),
              const SizedBox(height: 10),
              _buildDialogField('Property Category / Tier', tierCtrl, 'e.g. Boutique Hotel, Resort, Suites'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildDialogField('City', cityCtrl, '')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDialogField('State', stateCtrl, '')),
                ],
              ),
              const SizedBox(height: 10),
              _buildDialogField('Street Address', addressCtrl, 'e.g. 14 MG Road'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildDialogField('Pincode', pincodeCtrl, '')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDialogField('Room Inventory', roomsCtrl, '12', keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildDialogField('Default Check-In', checkInTimeCtrl, '12:00 PM')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDialogField('Default Check-Out', checkOutTimeCtrl, '11:00 AM')),
                ],
              ),
              const SizedBox(height: 10),
              _buildDialogField('GSTIN / Tax ID', gstCtrl, 'e.g. 29ABCDE1234F1Z5'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildDialogField('Front Desk Phone', phoneCtrl, '')),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDialogField('Official Email', emailCtrl, '')),
                ],
              ),
              const SizedBox(height: 10),
              _buildDialogField('Branch Bank / UPI ID (VPA) *', upiCtrl, 'e.g. piyushpal427@okaxis'),
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
              if (nameCtrl.text.trim().isEmpty) return;
              context.read<HotelStore>().addNewProperty(
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

  // Edit Hotel Details Dialog (Comprehensive Hotel-specific info)
  void _showEditHotelDialog(BuildContext context, Property prop) {
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
                'Edit Hotel Branch Info',
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
              _buildDialogField('Hotel Classification / Tier', tierCtrl, 'e.g. Boutique Hotel'),
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
                'Bank Account & UPI QR Details',
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
                const SnackBar(content: Text('Branch details saved!')),
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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Hotels & Branch Selection',
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
        ),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Hotel Properties Portfolio',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
              ),
              const SizedBox(height: 2),
              Text(
                'Tap on any branch to switch active front desk operations and access property specifics',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
              ),
              const SizedBox(height: 16),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: store.properties.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final prop = store.properties[index];
                  final isActive = prop.id == store.currentProperty.id;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isActive ? AppTheme.brandPrimary : AppTheme.slateBorder,
                        width: isActive ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isActive ? AppTheme.brandPrimary.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
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
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          prop.name,
                                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                                        ),
                                        Text(
                                          '${prop.hotelTier} • ${prop.city}, ${prop.state}',
                                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.statusVacantBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: AppTheme.statusVacant, size: 12),
                                    SizedBox(width: 4),
                                    Text('Active Branch', style: TextStyle(color: AppTheme.statusVacant, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Hotel Specific Meta Grid
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.slateBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildMetaItem(Icons.place_outlined, 'Address', '${prop.address}, ${prop.pincode}'),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(child: _buildMetaItem(Icons.schedule_rounded, 'Standard Timings', 'In ${prop.defaultCheckInTime} • Out ${prop.defaultCheckOutTime}')),
                                  Expanded(child: _buildMetaItem(Icons.meeting_room_outlined, 'Capacity', '${prop.totalRooms} Rooms registered')),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(child: _buildMetaItem(Icons.receipt_outlined, 'GSTIN', prop.gstNumber)),
                                  Expanded(child: _buildMetaItem(Icons.phone_outlined, 'Phone', prop.phone)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              _buildMetaItem(Icons.qr_code_2_rounded, 'UPI / Bank ID', '${prop.upiId} (${prop.upiPayeeName})'),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _showEditHotelDialog(context, prop),
                              icon: const Icon(Icons.edit_outlined, size: 13),
                              label: const Text('Edit Branch Details', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.slateDark,
                                side: const BorderSide(color: AppTheme.slateBorder),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: isActive
                                  ? Container(
                                      height: 38,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppTheme.brandLight.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Currently Managing',
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.brandDark),
                                      ),
                                    )
                                  : ElevatedButton(
                                      onPressed: () {
                                        store.switchProperty(prop.id);
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Switched active branch to ${prop.name}')),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.brandPrimary,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: const Text('Switch Branch', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _showAddHotelDialog(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.brandPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.add_business_rounded, color: AppTheme.brandPrimary),
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

  Widget _buildMetaItem(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: AppTheme.slateMuted),
        const SizedBox(width: 5),
        Expanded(
          child: RichText(
            text: TextSpan(
              text: '$label: ',
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.slateMuted),
              children: [
                TextSpan(
                  text: value,
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.slateDark),
                ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
