import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/room.dart';
import '../services/hotel_store.dart';
import '../theme/app_theme.dart';

class RoomDetailScreen extends StatefulWidget {
  final Room room;
  const RoomDetailScreen({super.key, required this.room});

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  late TextEditingController _rateController;
  late TextEditingController _roomNumberController;
  late String _selectedCategory;
  late int _selectedFloor;
  late RoomStatus _selectedStatus;
  bool _isEditing = false;
  bool _hasChanges = false;

  static const List<String> _categoryOptions = [
    'Standard Room',
    'Deluxe Room',
    'Executive Suite',
    'Super Deluxe',
    'Presidential Suite',
  ];

  static const List<int> _floorOptions = [1, 2, 3, 4, 5];

  @override
  void initState() {
    super.initState();
    _rateController = TextEditingController(text: widget.room.baseRate.toInt().toString());
    _roomNumberController = TextEditingController(text: widget.room.roomNumber);
    _selectedCategory = widget.room.categoryName;
    _selectedFloor = widget.room.floor;
    _selectedStatus = widget.room.status;
  }

  @override
  void dispose() {
    _rateController.dispose();
    _roomNumberController.dispose();
    super.dispose();
  }

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  void _saveChanges(HotelStore store) {
    final newRate = double.tryParse(_rateController.text) ?? widget.room.baseRate;
    store.updateRoomDetails(
      roomId: widget.room.id,
      roomNumber: _roomNumberController.text.trim(),
      categoryName: _selectedCategory,
      floor: _selectedFloor,
      baseRate: newRate,
      status: _selectedStatus,
    );
    setState(() {
      _isEditing = false;
      _hasChanges = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Room ${_roomNumberController.text} updated successfully'),
        backgroundColor: AppTheme.statusVacant,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    Navigator.of(context).pop(true); // signal refresh
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    // Get the latest room data from store
    final room = store.rooms.firstWhere((r) => r.id == widget.room.id, orElse: () => widget.room);
    final activeStay = store.activeStays.where((s) => s.roomId == room.id).firstOrNull;
    final bill = activeStay != null
        ? store.bills.where((b) => b.stayId == activeStay.id).firstOrNull
        : null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Room ${room.roomNumber}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_isEditing)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: Text('Edit', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            )
          else ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _hasChanges = false;
                  _rateController.text = room.baseRate.toInt().toString();
                  _roomNumberController.text = room.roomNumber;
                  _selectedCategory = room.categoryName;
                  _selectedFloor = room.floor;
                  _selectedStatus = room.status;
                });
              },
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.slateMuted)),
            ),
            TextButton(
              onPressed: _hasChanges ? () => _saveChanges(store) : null,
              child: Text(
                'Save',
                style: GoogleFonts.inter(
                  color: _hasChanges ? AppTheme.brandPrimary : AppTheme.slateBorder,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Room Status Hero Card
            _buildStatusHeroCard(room),
            const SizedBox(height: 16),

            // Room Info Edit Card
            _buildRoomInfoCard(room),
            const SizedBox(height: 16),

            // Pricing Card
            _buildPricingCard(room),
            const SizedBox(height: 16),

            // Current Occupancy Card (if occupied)
            if (activeStay != null) ...[
              _buildOccupancyCard(activeStay, bill, store),
              const SizedBox(height: 16),
            ],

            // Status Quick Change (when not editing)
            if (!_isEditing && room.status != RoomStatus.occupied)
              _buildQuickStatusCard(room, store),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeroCard(Room room) {
    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    switch (room.status) {
      case RoomStatus.occupied:
        statusColor = AppTheme.statusOccupied;
        statusIcon = Icons.person_rounded;
        statusLabel = 'Occupied';
        break;
      case RoomStatus.needsCleaning:
        statusColor = AppTheme.statusCleaning;
        statusIcon = Icons.cleaning_services_rounded;
        statusLabel = 'Needs Cleaning';
        break;
      case RoomStatus.maintenance:
        statusColor = Colors.red.shade400;
        statusIcon = Icons.build_rounded;
        statusLabel = 'Maintenance';
        break;
      case RoomStatus.reserved:
        statusColor = AppTheme.statusReserved;
        statusIcon = Icons.event_rounded;
        statusLabel = 'Reserved';
        break;
      default:
        statusColor = AppTheme.statusVacant;
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'Vacant';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusColor.withValues(alpha: 0.9), statusColor.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                room.roomNumber,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.categoryName,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Floor ${room.floor} • ₹${room.baseRate.toInt()}/night',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 13, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomInfoCard(Room room) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.brandPrimary),
              const SizedBox(width: 8),
              Text(
                'Room Details',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
              ),
              if (_isEditing) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.brandLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Editing', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Room Number
          _buildFieldLabel('Room Number'),
          const SizedBox(height: 6),
          if (_isEditing)
            TextField(
              controller: _roomNumberController,
              onChanged: (_) => _markChanged(),
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
              decoration: _inputDecoration('e.g. 101', Icons.tag_rounded),
            )
          else
            _buildStaticField(room.roomNumber, Icons.tag_rounded),

          const SizedBox(height: 12),

          // Category
          _buildFieldLabel('Room Category / Type'),
          const SizedBox(height: 6),
          if (_isEditing)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.slateBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  borderRadius: BorderRadius.circular(10),
                  items: _categoryOptions.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(cat, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.slateDark)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedCategory = val);
                      _markChanged();
                    }
                  },
                ),
              ),
            )
          else
            _buildStaticField(room.categoryName, Icons.category_rounded),

          const SizedBox(height: 12),

          // Floor
          _buildFieldLabel('Floor'),
          const SizedBox(height: 6),
          if (_isEditing)
            Wrap(
              spacing: 8,
              children: _floorOptions.map((floor) {
                final isSelected = _selectedFloor == floor;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedFloor = floor);
                    _markChanged();
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.brandPrimary : AppTheme.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? AppTheme.brandPrimary : AppTheme.slateBorder,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$floor',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isSelected ? Colors.white : AppTheme.slateDark,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            )
          else
            _buildStaticField('Floor ${room.floor}', Icons.layers_rounded),
        ],
      ),
    );
  }

  Widget _buildPricingCard(Room room) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_rounded, size: 16, color: AppTheme.brandPrimary),
              const SizedBox(width: 8),
              Text(
                'Pricing',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildFieldLabel('Nightly Rate (₹)'),
          const SizedBox(height: 6),
          if (_isEditing)
            TextField(
              controller: _rateController,
              keyboardType: TextInputType.number,
              onChanged: (_) => _markChanged(),
              style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.slateMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.slateBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.slateBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.brandPrimary, width: 2)),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${room.baseRate.toInt()}',
                  style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('/night', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.slateMuted)),
                ),
              ],
            ),

          if (!_isEditing) ...[
            const SizedBox(height: 12),
            // Estimated revenue cards
            Row(
              children: [
                Expanded(
                  child: _buildRevenueMiniCard(
                    '7 Nights',
                    '₹${(room.baseRate * 7).toInt()}',
                    AppTheme.brandLight,
                    AppTheme.brandPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildRevenueMiniCard(
                    '30 Nights',
                    '₹${(room.baseRate * 30).toInt()}',
                    AppTheme.statusVacantBg,
                    AppTheme.statusVacant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRevenueMiniCard(String label, String value, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: textColor, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
        ],
      ),
    );
  }

  Widget _buildOccupancyCard(dynamic stay, dynamic bill, HotelStore store) {
    final nights = stay.actualNights;
    final totalAmount = nights * stay.nightlyRate;
    final advancePaid = bill?.amountPaid ?? 0.0;
    final balance = (totalAmount - advancePaid).clamp(0.0, totalAmount);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.statusOccupiedBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.statusOccupied.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 16, color: AppTheme.statusOccupied),
              const SizedBox(width: 8),
              Text(
                'Current Occupancy',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.statusOccupied),
              ),
            ],
          ),
          const Divider(height: 16, color: Color(0xFFD0D5F0)),
          _buildInfoRow('Guest', stay.guest?.fullName ?? 'Guest'),
          _buildInfoRow('Check-In', DateFormat('d MMM yyyy, hh:mm a').format(stay.checkInAt)),
          _buildInfoRow('Check-Out', DateFormat('d MMM yyyy, hh:mm a').format(stay.expectedCheckOut)),
          _buildInfoRow('Duration', '$nights night${nights > 1 ? "s" : ""}'),
          _buildInfoRow('Guests', stay.guestSummary),
          const Divider(height: 16, color: Color(0xFFD0D5F0)),
          _buildInfoRow('Total', '₹${totalAmount.toInt()}'),
          _buildInfoRow('Advance Paid', '₹${advancePaid.toInt()}'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Balance Due', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.statusOccupied)),
              Text(
                '₹${balance.toInt()}',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: balance > 0 ? Colors.red.shade600 : AppTheme.statusVacant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatusCard(Room room, HotelStore store) {
    final statuses = [
      (RoomStatus.vacant, 'Vacant', Icons.check_circle_outline_rounded, AppTheme.statusVacant),
      (RoomStatus.maintenance, 'Maintenance', Icons.build_outlined, Colors.red.shade400),
      (RoomStatus.reserved, 'Reserved', Icons.event_outlined, AppTheme.statusReserved),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, size: 16, color: AppTheme.brandPrimary),
              const SizedBox(width: 8),
              Text('Quick Status Change', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slateDark)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: statuses.map((e) {
              final (status, label, icon, color) = e;
              final isCurrentStatus = room.status == status;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: isCurrentStatus ? null : () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: Text('Change Status', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                          content: Text('Mark Room ${room.roomNumber} as "$label"?', style: GoogleFonts.inter()),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: color),
                              onPressed: () {
                                store.updateRoomStatus(room.id, status);
                                Navigator.pop(ctx);
                              },
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isCurrentStatus ? color.withValues(alpha: 0.15) : AppTheme.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCurrentStatus ? color : AppTheme.slateBorder,
                          width: isCurrentStatus ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(icon, size: 18, color: isCurrentStatus ? color : AppTheme.slateMuted),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isCurrentStatus ? color : AppTheme.slateMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.slateMuted));
  }

  Widget _buildStaticField(String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.slateMuted),
          const SizedBox(width: 8),
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.slateDark)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted)),
          Text(value, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.slateDark)),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: AppTheme.slateMuted),
      prefixIcon: Icon(icon, size: 16, color: AppTheme.slateMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.slateBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.slateBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.brandPrimary, width: 2)),
    );
  }
}
