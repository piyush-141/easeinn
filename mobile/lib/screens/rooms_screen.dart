import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/hotel_store.dart';
import '../models/room.dart';
import '../theme/app_theme.dart';
import 'check_in_screen.dart';
import 'room_detail_screen.dart';
import 'booking_checkout_screen.dart';
import '../widgets/pressable_scale.dart';

class RoomsScreen extends StatefulWidget {
  final void Function(int tabIndex, {String? preselectedRoomId, BookingMode? initialMode})? onNavigateTab;
  const RoomsScreen({super.key, this.onNavigateTab});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  RoomStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final floors = store.floors;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Screen Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rooms & Floors',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
                        ),
                        Text(
                          '${store.occupiedRooms} Occupied • ${store.vacantRooms} Vacant • ${store.cleaningRooms} Cleaning',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.slateMuted,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Inventory Settings Button
                  IconButton(
                    onPressed: () => _showInventorySettings(context, store),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(8),
                      side: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    icon: const Icon(Icons.tune_rounded, color: AppTheme.slateDark, size: 20),
                    tooltip: 'Manage Floors & Rooms Settings',
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Status Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(
                      label: 'All (${store.totalRooms})',
                      isSelected: _statusFilter == null,
                      onTap: () => setState(() => _statusFilter = null),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Vacant (${store.vacantRooms})',
                      isSelected: _statusFilter == RoomStatus.vacant,
                      color: AppTheme.statusVacant,
                      onTap: () => setState(() => _statusFilter = RoomStatus.vacant),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Occupied (${store.occupiedRooms})',
                      isSelected: _statusFilter == RoomStatus.occupied,
                      color: AppTheme.statusOccupied,
                      onTap: () => setState(() => _statusFilter = RoomStatus.occupied),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Reserved (${store.reservedRooms})',
                      isSelected: _statusFilter == RoomStatus.reserved,
                      color: AppTheme.statusReserved,
                      onTap: () => setState(() => _statusFilter = RoomStatus.reserved),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Cleaning (${store.cleaningRooms})',
                      isSelected: _statusFilter == RoomStatus.needsCleaning,
                      color: AppTheme.statusCleaning,
                      onTap: () => setState(() => _statusFilter = RoomStatus.needsCleaning),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── FLOOR BY FLOOR SECTIONS (Floor 1, Floor 2, ... horizontally scrollable) ──
              ...floors.map((floor) {
                final floorRooms = store.rooms.where((r) {
                  final matchesFloor = r.floor == floor;
                  final matchesStatus = _statusFilter == null || r.status == _statusFilter;
                  return matchesFloor && matchesStatus;
                }).toList();

                if (floorRooms.isEmpty && _statusFilter != null) {
                  return const SizedBox.shrink();
                }

                final totalOnFloor = store.rooms.where((r) => r.floor == floor).length;
                final occupiedOnFloor = store.rooms.where((r) => r.floor == floor && r.status == RoomStatus.occupied).length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Floor Header
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppTheme.brandPrimary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '$floor',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.brandPrimary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Floor $floor',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.slateBorder),
                            ),
                            child: Text(
                              '$totalOnFloor Rooms • $occupiedOnFloor Occupied',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Horizontally Scrollable Room Cards
                    if (floorRooms.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'No rooms on Floor $floor match the filter',
                            style: GoogleFonts.inter(color: AppTheme.slateMuted, fontSize: 12),
                          ),
                        ),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: floorRooms.map((room) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _buildDecentRoomCard(context, room, store),
                            );
                          }).toList(),
                        ),
                      ),

                    const SizedBox(height: 20),
                  ],
                );
              }),

              const SizedBox(height: 84),
            ],
          ),
        ),
      ),
    );
  }

  // Filter Chip Component
  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    Color? color,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? (color ?? AppTheme.slateDark) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? (color ?? AppTheme.slateDark) : AppTheme.slateBorder,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : AppTheme.slateDark,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ── DECENT, CLEAN, HORIZONTALLY SCROLLABLE ROOM CARD ──
  Widget _buildDecentRoomCard(BuildContext context, Room room, HotelStore store) {
    final isCleaning = room.status == RoomStatus.needsCleaning;
    final isOccupied = room.status == RoomStatus.occupied;
    final isVacant = room.status == RoomStatus.vacant;
    final isReserved = room.status == RoomStatus.reserved;

    Color badgeColor;
    Color badgeBg;
    switch (room.status) {
      case RoomStatus.occupied:
        badgeColor = AppTheme.statusOccupied;
        badgeBg = AppTheme.statusOccupiedBg;
        break;
      case RoomStatus.needsCleaning:
        badgeColor = AppTheme.statusCleaning;
        badgeBg = AppTheme.statusCleaningBg;
        break;
      case RoomStatus.reserved:
        badgeColor = AppTheme.statusReserved;
        badgeBg = AppTheme.statusReservedBg;
        break;
      case RoomStatus.vacant:
      default:
        badgeColor = AppTheme.statusVacant;
        badgeBg = AppTheme.statusVacantBg;
        break;
    }

    // Active stay with timestamps
    final activeStay = store.activeStays.where((s) => s.roomId == room.id).firstOrNull;
    final reservedStay = store.upcomingStays.where((s) => s.roomId == room.id).firstOrNull;

    return PressableScale(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
        );
      },
      pressedScale: 0.96,
      child: Container(
        width: 180,
        height: 230,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCleaning
                ? AppTheme.statusCleaning
                : (isOccupied
                    ? AppTheme.statusOccupied.withValues(alpha: 0.35)
                    : (isReserved ? AppTheme.statusReserved.withValues(alpha: 0.35) : AppTheme.slateBorder)),
            width: isCleaning ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isCleaning
                  ? AppTheme.statusCleaning.withValues(alpha: 0.08)
                  : (isReserved
                      ? AppTheme.statusReserved.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.025)),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Row: Room number & status badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      room.roomNumber,
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_note_rounded, size: 14, color: AppTheme.slateMuted),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    room.status.label,
                    style: GoogleFonts.inter(
                      color: badgeColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            // Category & Pricing
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.categoryName,
                  style: GoogleFonts.inter(
                    color: AppTheme.slateDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '₹${room.baseRate.toInt()}/night',
                  style: GoogleFonts.inter(
                    color: AppTheme.brandPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            // Status / Occupant Details with Timestamps
            if (isOccupied && room.currentGuestName != null)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.statusOccupiedBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_rounded, size: 11, color: AppTheme.statusOccupied),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            room.currentGuestName!,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.statusOccupied,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.verified_rounded, size: 10, color: Color(0xFF16A34A)),
                      ],
                    ),
                    if (activeStay != null) ...[
                      const SizedBox(height: 2),
                      // Check-in and Check-out Timestamps
                      Text(
                        'In: ${DateFormat('d MMM, hh:mm a').format(activeStay.checkInAt)}',
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          color: AppTheme.slateDark,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Out: ${DateFormat('d MMM, hh:mm a').format(activeStay.expectedCheckOut)}',
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          color: AppTheme.brandPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        activeStay.guestSummary,
                        style: GoogleFonts.inter(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              )
            else if (isCleaning)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.statusCleaningBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cleaning_services_rounded, size: 12, color: AppTheme.statusCleaning),
                    const SizedBox(width: 4),
                    Text(
                      'Turnover required',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.statusCleaning,
                      ),
                    ),
                  ],
                ),
              )
            else if (isReserved)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.statusReservedBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_available_rounded, size: 11, color: AppTheme.statusReserved),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            reservedStay?.guest?.fullName ?? 'Reserved Guest',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.statusReserved,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Arrival: ${DateFormat('d MMM, hh:mm a').format(reservedStay?.checkInAt ?? DateTime.now())}',
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        color: AppTheme.slateDark,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Dep: ${DateFormat('d MMM, hh:mm a').format(reservedStay?.expectedCheckOut ?? DateTime.now().add(const Duration(days: 1)))}',
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        color: AppTheme.brandPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.statusVacantBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 11, color: AppTheme.statusVacant),
                    const SizedBox(width: 4),
                    Text(
                      'Ready for guest',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.statusVacant,
                      ),
                    ),
                  ],
                ),
              ),

            // Action Button at Bottom
            if (isCleaning)
              SizedBox(
                width: double.infinity,
                height: 30,
                child: PressableScale(
                  pressedScale: 0.95,
                  child: ElevatedButton.icon(
                    onPressed: () => store.markRoomClean(room.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.statusCleaning,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 13),
                    label: const Text('Mark Clean', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              )
            else if (isVacant)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: PressableScale(
                        pressedScale: 0.94,
                        child: ElevatedButton(
                          onPressed: () {
                            if (widget.onNavigateTab != null) {
                              widget.onNavigateTab!(2, preselectedRoomId: room.id, initialMode: BookingMode.checkIn);
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CheckInScreen(preselectedRoomId: room.id, initialMode: BookingMode.checkIn),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandPrimary,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Check-In', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: PressableScale(
                        pressedScale: 0.94,
                        child: OutlinedButton(
                          onPressed: () {
                            if (widget.onNavigateTab != null) {
                              widget.onNavigateTab!(2, preselectedRoomId: room.id, initialMode: BookingMode.reservation);
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CheckInScreen(preselectedRoomId: room.id, initialMode: BookingMode.reservation),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.slateDark,
                            side: const BorderSide(color: AppTheme.slateBorder),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Reserve', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else if (isReserved && reservedStay != null)
              SizedBox(
                width: double.infinity,
                height: 30,
                child: PressableScale(
                  pressedScale: 0.95,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      store.checkInReservedStay(reservedStay.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${reservedStay.guest?.fullName ?? "Guest"} checked in to Room ${room.roomNumber}!'),
                          backgroundColor: AppTheme.slateDark,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandPrimary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.how_to_reg_rounded, size: 12),
                    label: const Text('Check-In Guest', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              )
            else if (isOccupied && activeStay != null)
              SizedBox(
                width: double.infinity,
                height: 30,
                child: PressableScale(
                  pressedScale: 0.95,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookingCheckOutScreen(stay: activeStay),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandPrimary,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Checkout', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 30,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.slateBorder.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      room.status.label,
                      style: GoogleFonts.inter(fontSize: 10, color: AppTheme.slateMuted, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── INVENTORY & FLOORS SETTINGS MODAL (Floors & Rooms Added/Deleted Here) ──
  void _showInventorySettings(BuildContext context, HotelStore store) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: AppTheme.slateBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Rooms & Inventory Settings',
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Manage floors, add/delete rooms, and configure default check-in/out times',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
              ),
              const SizedBox(height: 18),

              // ── 1. Default Hotel Timings ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default Hotel Timings',
                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickTime(context, store, isCheckIn: true),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.slateBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Default Check-In', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.slateMuted)),
                                  const SizedBox(height: 2),
                                  Text(store.defaultCheckInTime, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickTime(context, store, isCheckIn: false),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.slateBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Default Check-Out', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.slateMuted)),
                                  const SizedBox(height: 2),
                                  Text(store.defaultCheckOutTime, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── 2. Floors Management ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Floors (${store.floors.length})',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                  ),
                  TextButton.icon(
                    onPressed: () => _showAddFloorDialog(context, store),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Floor'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...store.floors.map((fl) {
                final count = store.rooms.where((r) => r.floor == fl).length;
                final hasOccupied = store.rooms.any((r) => r.floor == fl && r.status == RoomStatus.occupied);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.slateBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.brandLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text('$fl', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.brandPrimary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Floor $fl — $count room${count != 1 ? "s" : ""}',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                        tooltip: 'Delete Floor',
                        onPressed: hasOccupied
                            ? null
                            : () {
                                final deleted = store.deleteFloor(fl);
                                if (!deleted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Cannot delete floor with active guests')),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 18),

              // ── 3. Rooms Management ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Rooms Inventory (${store.rooms.length})',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showAddRoomDialog(context, store),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Room', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ...store.rooms.map((room) {
                final isOccupied = room.status == RoomStatus.occupied;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.slateBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isOccupied ? AppTheme.statusOccupiedBg : AppTheme.statusVacantBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            room.roomNumber,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              color: isOccupied ? AppTheme.statusOccupied : AppTheme.statusVacant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${room.categoryName} • Floor ${room.floor}',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                            ),
                            Text(
                              '₹${room.baseRate.toInt()}/night • ${room.status.label}',
                              style: GoogleFonts.inter(fontSize: 10, color: AppTheme.slateMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.slateDark),
                        tooltip: 'Edit Room',
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                        tooltip: 'Delete Room',
                        onPressed: isOccupied
                            ? null
                            : () {
                                final success = store.deleteRoom(room.id);
                                if (!success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Cannot delete an occupied room')),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // Pick checkin/checkout default time
  Future<void> _pickTime(BuildContext context, HotelStore store, {required bool isCheckIn}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isCheckIn ? const TimeOfDay(hour: 12, minute: 0) : const TimeOfDay(hour: 11, minute: 0),
    );
    if (picked != null && context.mounted) {
      final formatted = picked.format(context);
      if (isCheckIn) {
        store.updateDefaultTimes(checkInTime: formatted);
      } else {
        store.updateDefaultTimes(checkOutTime: formatted);
      }
    }
  }

  // Dialog to Add a Floor
  void _showAddFloorDialog(BuildContext context, HotelStore store) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add New Floor', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Floor Number (e.g. 3, 4)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final fl = int.tryParse(controller.text.trim());
              if (fl != null) {
                store.addFloor(fl);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add Floor'),
          ),
        ],
      ),
    );
  }

  // Dialog to Add a Room
  void _showAddRoomDialog(BuildContext context, HotelStore store) {
    final roomNumberCtrl = TextEditingController();
    final rateCtrl = TextEditingController(text: '2500');
    int selectedFloor = store.floors.first;
    String selectedCategory = 'Standard Room';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Add New Room', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: roomNumberCtrl,
                  decoration: const InputDecoration(labelText: 'Room Number (e.g. 301)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: selectedFloor,
                  decoration: const InputDecoration(labelText: 'Floor'),
                  items: store.floors.map((f) => DropdownMenuItem(value: f, child: Text('Floor $f'))).toList(),
                  onChanged: (val) => setDialogState(() => selectedFloor = val ?? selectedFloor),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(labelText: 'Room Category'),
                  items: const [
                    DropdownMenuItem(value: 'Standard Room', child: Text('Standard Room')),
                    DropdownMenuItem(value: 'Deluxe Room', child: Text('Deluxe Room')),
                    DropdownMenuItem(value: 'Executive Suite', child: Text('Executive Suite')),
                    DropdownMenuItem(value: 'Super Deluxe', child: Text('Super Deluxe')),
                  ],
                  onChanged: (val) => setDialogState(() => selectedCategory = val ?? selectedCategory),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rateCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Base Rate per Night (₹)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final rNum = roomNumberCtrl.text.trim();
                final rate = double.tryParse(rateCtrl.text.trim()) ?? 2500.0;
                if (rNum.isNotEmpty) {
                  store.addRoom(
                    roomNumber: rNum,
                    floor: selectedFloor,
                    categoryName: selectedCategory,
                    baseRate: rate,
                  );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Create Room'),
            ),
          ],
        ),
      ),
    );
  }
}
