import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../services/hotel_store.dart';
import '../services/export_file_service.dart';
import '../models/guest.dart';
import '../models/stay.dart';
import '../models/room.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable_scale.dart';

enum GuestDateFilter { all, today, thisWeek, thisMonth, customRange }

class GuestsScreen extends StatefulWidget {
  const GuestsScreen({super.key});

  @override
  State<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends State<GuestsScreen> {
  final _searchController = TextEditingController();
  String _filter = 'all'; // 'all', 'in_house', 'past'
  String _roomFilter = 'all'; // 'all' or roomId/roomNumber
  String _idTypeFilter = 'all';
  GuestDateFilter _dateFilter = GuestDateFilter.all;
  DateTimeRange? _customDateRange;
  String _sortBy = 'recent'; // 'recent', 'name', 'room', 'status'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Find linked stay for a guest (active stay takes precedence, then latest stay)
  Stay? _findStayForGuest(HotelStore store, String guestId) {
    // 1. Look for active stay
    for (final s in store.stays) {
      if (s.status == StayStatus.active) {
        if (s.guestId == guestId || s.coGuests.any((cg) => cg.id == guestId)) {
          return s;
        }
      }
    }
    // 2. Otherwise return most recent stay
    for (final s in store.stays) {
      if (s.guestId == guestId || s.coGuests.any((cg) => cg.id == guestId)) {
        return s;
      }
    }
    return null;
  }

  // ── DETAILED GUEST PROFILE MODAL (ALL ID SCAN DETAILS) ──
  void _showGuestProfile(BuildContext context, Guest guest, HotelStore store) {
    final stay = _findStayForGuest(store, guest.id);
    final isCoGuest =
        stay != null && stay.coGuests.any((cg) => cg.id == guest.id);

    // Calculate age if DOB available
    String ageText = '';
    if (guest.dateOfBirth != null && guest.dateOfBirth!.isNotEmpty) {
      try {
        final dob = DateTime.parse(guest.dateOfBirth!);
        final now = DateTime.now();
        int age = now.year - dob.year;
        if (now.month < dob.month ||
            (now.month == dob.month && now.day < dob.day)) {
          age--;
        }
        if (age > 0) ageText = ' ($age yrs)';
      } catch (_) {}
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Scrollable content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    // Header Row
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppTheme.brandPrimary,
                          child: Text(
                            guest.fullName.isNotEmpty
                                ? guest.fullName.substring(0, 1).toUpperCase()
                                : 'G',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                guest.fullName,
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                guest.phone.isNotEmpty
                                    ? guest.phone
                                    : 'No phone recorded',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                              if (guest.email != null &&
                                  guest.email!.isNotEmpty)
                                Text(
                                  guest.email!,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppTheme.brandPrimary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.verified_rounded,
                                color: Color(0xFF16A34A),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Verified ID',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF16A34A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // ── 1. GOVERNMENT ID RECORD (EXTRACTED VIA OCR) ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.brandPrimary.withValues(alpha: 0.08),
                            const Color(0xFF1E1B4B).withValues(alpha: 0.04),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.brandPrimary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.badge_outlined,
                                    color: AppTheme.brandPrimary,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'GOVERNMENT ID RECORD',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.brandPrimary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.brandPrimary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  guest.idType.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  guest.displayIdNumber,
                                  style: GoogleFonts.firaCode(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.slateDark,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.copy_rounded,
                                  size: 18,
                                  color: AppTheme.slateMuted,
                                ),
                                tooltip: 'Copy ID Number',
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: guest.displayIdNumber),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('ID number copied!'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          if (guest.fatherName != null &&
                              guest.fatherName!.isNotEmpty) ...[
                            const Divider(height: 16),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 14,
                                  color: AppTheme.slateMuted,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Father / Care of: ',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.slateDark,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    guest.fatherName!,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── 2. PERSONAL IDENTITY PARTICULARS ──
                    Text(
                      'Personal Details (Scanned Record)',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            Icons.cake_outlined,
                            'Date of Birth',
                            (guest.dateOfBirth != null &&
                                    guest.dateOfBirth!.isNotEmpty)
                                ? '${guest.dateOfBirth!}$ageText'
                                : 'Not recorded in scan',
                          ),
                          const Divider(height: 12),
                          _buildDetailRow(
                            Icons.wc_outlined,
                            'Gender',
                            (guest.gender != null && guest.gender!.isNotEmpty)
                                ? guest.gender!
                                : 'Not specified',
                          ),
                          const Divider(height: 12),
                          _buildDetailRow(
                            Icons.phone_android_outlined,
                            'Mobile Phone',
                            guest.phone.isNotEmpty
                                ? guest.phone
                                : 'Not provided',
                          ),
                          if (guest.email != null &&
                              guest.email!.isNotEmpty) ...[
                            const Divider(height: 12),
                            _buildDetailRow(
                              Icons.email_outlined,
                              'Email',
                              guest.email!,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── 3. RESIDENTIAL ADDRESS (FROM ID BACK) ──
                    Text(
                      'Residential Address (Govt Registered)',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: AppTheme.brandPrimary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (guest.address != null &&
                                          guest.address!.isNotEmpty)
                                      ? guest.address!
                                      : 'Full address not parsed from ID document',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: AppTheme.slateDark,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (guest.pincode != null &&
                              guest.pincode!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      'PINCODE: ${guest.pincode!}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── 4. HOTEL STAY & ROOM HISTORY ──
                    Text(
                      'Stay & Room History',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (stay != null) ...[
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.slateDark,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Room ${stay.room?.roomNumber ?? "—"}',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${stay.room?.categoryName ?? "Standard"} (Floor ${stay.room?.floor ?? 1})',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.slateDark,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: stay.status == StayStatus.active
                                        ? const Color(0xFFDCFCE7)
                                        : stay.status == StayStatus.checkedOut
                                        ? const Color(0xFFE0E7FF)
                                        : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    stay.status == StayStatus.active
                                        ? 'In-House'
                                        : stay.status == StayStatus.checkedOut
                                        ? 'Checked Out'
                                        : 'Reserved',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: stay.status == StayStatus.active
                                          ? const Color(0xFF16A34A)
                                          : stay.status == StayStatus.checkedOut
                                          ? const Color(0xFF4338CA)
                                          : const Color(0xFFD97706),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            _buildDetailRow(
                              Icons.login_rounded,
                              'Check-In',
                              DateFormat(
                                'd MMM yyyy, hh:mm a',
                              ).format(stay.checkInAt),
                            ),
                            const Divider(height: 12),
                            _buildDetailRow(
                              Icons.logout_rounded,
                              'Check-Out',
                              DateFormat('d MMM yyyy, hh:mm a').format(
                                stay.checkOutAt ?? stay.expectedCheckOut,
                              ),
                            ),
                            const Divider(height: 12),
                            _buildDetailRow(
                              Icons.nights_stay_outlined,
                              'Stay Duration',
                              '${stay.actualNights} Night(s)',
                            ),
                            if (isCoGuest) ...[
                              const Divider(height: 12),
                              _buildDetailRow(
                                Icons.person_pin_rounded,
                                'Primary Guest',
                                stay.guest?.fullName ?? 'Primary',
                              ),
                            ],
                            if (stay.coGuests.isNotEmpty) ...[
                              const Divider(height: 12),
                              _buildDetailRow(
                                Icons.groups_outlined,
                                'Co-Guests',
                                stay.coGuests
                                    .map((cg) => cg.fullName)
                                    .join(', '),
                              ),
                            ],
                          ] else ...[
                            Text(
                              'No active reservation currently linked. Total lifetime stays: ${guest.staysCount}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          ],
                          const Divider(height: 12),
                          _buildDetailRow(
                            Icons.history_rounded,
                            'Total Visits',
                            '${guest.staysCount} stay(s) recorded at EaseInn',
                          ),
                        ],
                      ),
                    ),

                    if (guest.notes != null && guest.notes!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Front Desk Notes',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Text(
                          guest.notes!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Actions Row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final stayData = stay != null
                                  ? 'Room ${stay.room?.roomNumber ?? "N/A"} (${DateFormat('d MMM yyyy').format(stay.checkInAt)})'
                                  : 'N/A';
                              final guestSummary =
                                  '''
EaseInn Guest Record:
Name: ${guest.fullName}
Phone: ${guest.phone}
ID Type: ${guest.idType.toUpperCase()}
ID Number: ${guest.displayIdNumber}
DOB: ${guest.dateOfBirth ?? "N/A"}
Gender: ${guest.gender ?? "N/A"}
Care Of: ${guest.fatherName ?? "N/A"}
Address: ${guest.address ?? "N/A"} - ${guest.pincode ?? ""}
Stay: $stayData
''';
                              Clipboard.setData(
                                ClipboardData(text: guestSummary),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Guest details copied to clipboard!',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copy Details'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.slateDark,
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.slateDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppTheme.brandPrimary),
        const SizedBox(width: 8),
        SizedBox(
          width: 95,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.slateMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.slateDark,
            ),
          ),
        ),
      ],
    );
  }

  // ── 2. EXPORT GUEST SHEETS WITH ALL DETAILS TAKEN (DATE / ROOM / TIME WISE) ──
  List<Guest> _filterGuestsForExport(HotelStore store) {
    final query = _searchController.text.trim().toLowerCase();
    final activeGuestIds = <String>{
      for (final stay in store.activeStays) ...[
        stay.guestId,
        ...stay.coGuests.map((guest) => guest.id),
      ],
    };
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final list = store.guests.where((g) {
      // 1. Search Query
      if (query.isNotEmpty) {
        final stay = _findStayForGuest(store, g.id);
        final room = stay?.room ??
            (stay != null
                ? store.rooms
                    .cast<Room?>()
                    .firstWhere((r) => r?.id == stay.roomId, orElse: () => null)
                : null);
        final matches =
            g.fullName.toLowerCase().contains(query) ||
            g.phone.contains(query) ||
            g.displayIdNumber.toLowerCase().contains(query) ||
            g.idNumberMasked.toLowerCase().contains(query) ||
            (g.address?.toLowerCase().contains(query) ?? false) ||
            (room != null && room.roomNumber.toLowerCase().contains(query));
        if (!matches) return false;
      }

      // 2. Status Filter
      final isInHouse = activeGuestIds.contains(g.id);
      if (_filter == 'in_house' && !isInHouse) return false;
      if (_filter == 'past' && isInHouse) return false;
      if (_idTypeFilter != 'all' &&
          g.idType.toLowerCase() != _idTypeFilter) {
        return false;
      }

      // 3. Room & Date Filter (via linked stay)
      final stay = _findStayForGuest(store, g.id);

      if (_roomFilter != 'all') {
        if (stay == null ||
            (stay.roomId != _roomFilter &&
                stay.room?.roomNumber != _roomFilter)) {
          return false;
        }
      }

      if (_dateFilter != GuestDateFilter.all) {
        if (stay == null) return false;
        final checkInDate = DateTime(
          stay.checkInAt.year,
          stay.checkInAt.month,
          stay.checkInAt.day,
        );

        switch (_dateFilter) {
          case GuestDateFilter.all:
            break;
          case GuestDateFilter.today:
            if (checkInDate != today) return false;
            break;
          case GuestDateFilter.thisWeek:
            final startOfWeek = today.subtract(
              Duration(days: today.weekday - 1),
            );
            final endOfWeek = startOfWeek.add(const Duration(days: 6));
            if (checkInDate.isBefore(startOfWeek) ||
                checkInDate.isAfter(endOfWeek)) {
              return false;
            }
            break;
          case GuestDateFilter.thisMonth:
            if (checkInDate.year != now.year ||
                checkInDate.month != now.month) {
              return false;
            }
            break;
          case GuestDateFilter.customRange:
            if (_customDateRange != null) {
              final start = DateTime(
                _customDateRange!.start.year,
                _customDateRange!.start.month,
                _customDateRange!.start.day,
              );
              final end = DateTime(
                _customDateRange!.end.year,
                _customDateRange!.end.month,
                _customDateRange!.end.day,
                23,
                59,
                59,
              );
              if (checkInDate.isBefore(start) || stay.checkInAt.isAfter(end)) {
                return false;
              }
            }
            break;
        }
      }

      return true;
    }).toList();

    // 4. Sorting
    if (_sortBy == 'name') {
      list.sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    } else if (_sortBy == 'room') {
      list.sort((a, b) {
        final stayA = _findStayForGuest(store, a.id);
        final roomA = stayA?.room?.roomNumber ??
            (stayA != null
                ? store.rooms
                    .cast<Room?>()
                    .firstWhere((r) => r?.id == stayA.roomId, orElse: () => null)
                    ?.roomNumber
                : '') ??
            '';
        final stayB = _findStayForGuest(store, b.id);
        final roomB = stayB?.room?.roomNumber ??
            (stayB != null
                ? store.rooms
                    .cast<Room?>()
                    .firstWhere((r) => r?.id == stayB.roomId, orElse: () => null)
                    ?.roomNumber
                : '') ??
            '';
        return roomA.compareTo(roomB);
      });
    } else if (_sortBy == 'status') {
      list.sort((a, b) {
        final aIn = activeGuestIds.contains(a.id) ? 0 : 1;
        final bIn = activeGuestIds.contains(b.id) ? 0 : 1;
        return aIn.compareTo(bIn);
      });
    }

    return list;
  }

  String _generateGuestSheetCsv(List<Guest> guests, HotelStore store) {
    final buffer = StringBuffer();
    // UTF-8 BOM for Excel compatibility
    buffer.write('\uFEFF');

    final headers = [
      'Stay Group ID',
      'Primary Guest ID',
      'Guest Role',
      'Accompanying Guest Count',
      'Accompanying Guests With Details',
      'Guest ID',
      'Full Name',
      'Phone Number',
      'Email',
      'Government ID Type',
      'Government ID Number',
      'Date of Birth',
      'Gender',
      'Father / Care of Name',
      'Residential Address',
      'Pincode',
      'Assigned Room Number',
      'Room Category',
      'Floor',
      'Check-In Date',
      'Check-In Time',
      'Check-Out Date',
      'Check-Out Time',
      'Stay Duration (Nights)',
      'Guest Current Status',
      'Total Lifetime Visits',
      'Special Notes',
    ];

    buffer.writeln(headers.map(_escapeCsv).join(','));

    for (final guest in guests) {
      final stay = _findStayForGuest(store, guest.id);
      final isPrimaryGuest = stay == null || stay.guestId == guest.id;
      final accompanyingWithDetails =
          stay?.coGuests.where(_hasRecordedGuestDetails).length ?? 0;

      final checkInDate = stay != null
          ? DateFormat('yyyy-MM-dd').format(stay.checkInAt)
          : 'N/A';
      final checkInTime = stay != null
          ? DateFormat('hh:mm a').format(stay.checkInAt)
          : 'N/A';
      final outDateObj = stay != null
          ? (stay.checkOutAt ?? stay.expectedCheckOut)
          : null;
      final checkOutDate = outDateObj != null
          ? DateFormat('yyyy-MM-dd').format(outDateObj)
          : 'N/A';
      final checkOutTime = outDateObj != null
          ? DateFormat('hh:mm a').format(outDateObj)
          : 'N/A';

      final statusStr = stay != null
          ? (stay.status == StayStatus.active
                ? 'In-House'
                : stay.status == StayStatus.checkedOut
                ? 'Checked Out'
                : 'Reserved')
          : 'Registered';

      final row = [
        stay?.id ?? guest.id,
        stay?.guestId ?? guest.id,
        stay == null
            ? 'Registered'
            : isPrimaryGuest
            ? 'Primary'
            : 'Accompanying',
        stay != null && isPrimaryGuest ? stay.coGuests.length.toString() : '',
        stay != null && isPrimaryGuest
            ? accompanyingWithDetails.toString()
            : '',
        guest.id,
        guest.fullName,
        guest.phone,
        guest.email ?? 'N/A',
        guest.idType.toUpperCase(),
        guest.displayIdNumber,
        guest.dateOfBirth ?? 'N/A',
        guest.gender ?? 'N/A',
        guest.fatherName ?? 'N/A',
        guest.address ?? 'N/A',
        guest.pincode ?? 'N/A',
        stay?.room?.roomNumber ?? 'N/A',
        stay?.room?.categoryName ?? 'N/A',
        stay?.room?.floor.toString() ?? 'N/A',
        checkInDate,
        checkInTime,
        checkOutDate,
        checkOutTime,
        stay?.actualNights.toString() ?? 'N/A',
        statusStr,
        guest.staysCount.toString(),
        guest.notes ?? 'None',
      ];

      buffer.writeln(row.map(_escapeCsv).join(','));
    }

    return buffer.toString();
  }

  bool _hasRecordedGuestDetails(Guest guest) =>
      (guest.idNumber?.trim().isNotEmpty ?? false) ||
      guest.phone.trim().isNotEmpty ||
      (guest.email?.trim().isNotEmpty ?? false) ||
      (guest.dateOfBirth?.trim().isNotEmpty ?? false) ||
      (guest.gender?.trim().isNotEmpty ?? false) ||
      (guest.address?.trim().isNotEmpty ?? false) ||
      (guest.pincode?.trim().isNotEmpty ?? false) ||
      (guest.fatherName?.trim().isNotEmpty ?? false);

  String _escapeCsv(dynamic value) {
    if (value == null) return '""';
    final str = value.toString();
    if (str.contains(',') ||
        str.contains('"') ||
        str.contains('\n') ||
        str.contains('\r')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return '"$str"';
  }

  Future<void> _exportGuestSheet(BuildContext context, HotelStore store) async {
    final filteredGuests = _filterGuestsForExport(store);
    final selectedIds = filteredGuests.map((guest) => guest.id).toSet();
    final exportGuestsById = {
      for (final guest in store.guests) guest.id: guest,
    };
    for (final stay in store.stays) {
      final groupIds = {
        stay.guestId,
        ...stay.coGuests.map((guest) => guest.id),
      };
      if (groupIds.any(selectedIds.contains)) {
        selectedIds.addAll(groupIds);
        if (stay.guest != null) exportGuestsById[stay.guestId] = stay.guest!;
        for (final coGuest in stay.coGuests) {
          exportGuestsById[coGuest.id] = coGuest;
        }
      }
    }
    final guestsToExport = exportGuestsById.values
        .where((guest) => selectedIds.contains(guest.id))
        .toList();
    if (guestsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No guests match the current filters to export.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final csvData = _generateGuestSheetCsv(guestsToExport, store);
    final nowStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'EaseInn_Guest_Register_$nowStr.xlsx';
    final selectedPeriod = switch (_dateFilter) {
      GuestDateFilter.all => 'All Time',
      GuestDateFilter.today =>
        'Today (${DateFormat('d MMM yyyy').format(DateTime.now())})',
      GuestDateFilter.thisWeek => 'This Week',
      GuestDateFilter.thisMonth =>
        'This Month (${DateFormat('MMMM yyyy').format(DateTime.now())})',
      GuestDateFilter.customRange when _customDateRange != null =>
        '${DateFormat('d MMM yyyy').format(_customDateRange!.start)} – ${DateFormat('d MMM yyyy').format(_customDateRange!.end)}',
      GuestDateFilter.customRange => 'Custom Date Range',
    };
    final workbook = ExportFileService.createWorkbook(
      csvData: csvData,
      reportTitle: 'Guest Register',
      hotelName: store.currentProperty.name,
      selectedPeriod: selectedPeriod,
      recordCount: guestsToExport.length,
      additionalDetails:
          'Room: ${_roomFilter == 'all' ? 'All Rooms' : _roomFilter}  |  Guest status: $_filter',
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: AppTheme.brandPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export ${guestsToExport.length} Guest Records',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      Text(
                        'Includes full ID records, DOB, address, room & check-in details',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.slateMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Primary Action: Download, Save & Share all at once
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _shareGuestWorkbook(workbook, fileName);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.brandPrimary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.download_done_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Download, Save & Share Excel',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Saves copy in Downloads/EaseInn & opens share sheet',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Copy to Clipboard
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.copy_rounded,
                  color: AppTheme.brandPrimary,
                  size: 22,
                ),
              ),
              title: Text(
                'Copy Sheet to Clipboard',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                'Paste into Google Sheets or Notes',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.slateMuted,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppTheme.slateMuted,
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                Clipboard.setData(ClipboardData(text: csvData));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${guestsToExport.length} guest records copied as CSV!',
                    ),
                    backgroundColor: const Color(0xFF16A34A),
                  ),
                );
              },
            ),

            const Divider(height: 16),

            // Raw preview
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.remove_red_eye_outlined,
                  color: Colors.amber,
                  size: 22,
                ),
              ),
              title: Text(
                'Preview Guest Register Table',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                'Inspect Form C compliance and columns',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.slateMuted,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppTheme.slateMuted,
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _showPreviewDialog(csvData);
              },
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _shareGuestWorkbook(Uint8List workbook, String fileName) async {
    try {
      if (!kIsWeb) {
        await ExportFileService.saveToDownloads(
          fileName: fileName,
          bytes: workbook,
        );
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(workbook, flush: true);
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [
            XFile(
              file.path,
              mimeType: ExportFileService.xlsxMimeType,
              name: fileName,
            ),
          ],
          subject: 'EaseInn Hotel Guest Register',
          text:
              'Attached is the formatted guest register from EaseInn PMS. A copy is also saved in Downloads/EaseInn.',
        );
      } else {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [
            XFile.fromData(
              workbook,
              mimeType: ExportFileService.xlsxMimeType,
              name: fileName,
            ),
          ],
          subject: 'EaseInn Hotel Guest Register',
          text: 'EaseInn Hotel Guest Register Export ($fileName)',
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share export: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showPreviewDialog(String csvData) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Guest Sheet CSV Preview',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: SelectableText(
                csvData,
                style: GoogleFonts.firaCode(
                  fontSize: 11,
                  color: AppTheme.slateDark,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvData));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard!')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy CSV'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandPrimary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── MAIN SCREEN BUILDER ──
  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final activeGuestIds = <String>{
      for (final stay in store.activeStays) ...[
        stay.guestId,
        ...stay.coGuests.map((guest) => guest.id),
      ],
    };
    final inHouseGuestCount = store.guests
        .where((guest) => activeGuestIds.contains(guest.id))
        .length;
    final filtered = _filterGuestsForExport(store);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guest Directory',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.slateDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${store.guests.length} guests · $inHouseGuestCount in-house',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PressableScale(
                    pressedScale: 0.96,
                    child: ElevatedButton.icon(
                      onPressed: () => _exportGuestSheet(context, store),
                      icon: const Icon(Icons.file_download_outlined, size: 16),
                      label: Text(
                        'Export',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brandPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Search Bar with Sliders/Tune Icon
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.slateDark,
                ),
                decoration: InputDecoration(
                  hintText: 'Name, phone, Aadhaar, room...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.slateMuted,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 21,
                    color: AppTheme.slateMuted,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: AppTheme.slateMuted,
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                      IconButton(
                        tooltip: 'Filters',
                        icon: const Icon(Icons.tune_rounded, size: 20),
                        color: AppTheme.slateMuted,
                        onPressed: () => _showFilterBottomSheet(context),
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.slateBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.slateBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppTheme.brandPrimary,
                      width: 1.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Primary Category Chips: All (7), In-House (3), Past Guests
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildChip('all', 'All (${store.guests.length})'),
                    const SizedBox(width: 8),
                    _buildChip(
                      'in_house',
                      'In-House ($inHouseGuestCount)',
                    ),
                    const SizedBox(width: 8),
                    _buildChip(
                      'past',
                      'Past Guests',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Secondary Filter Chips: All Rooms, All Time, ID Type
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildRoomFilterChip(store),
                    const SizedBox(width: 8),
                    _buildDateFilterChip(),
                    const SizedBox(width: 8),
                    _buildIdTypeFilterChip(store),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Section Header: "Guest records" + "View by"
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Guest records',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ),
                  _buildViewByButton(),
                ],
              ),
              const SizedBox(height: 12),

              // Guest Records List
              if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 36,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.slateBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.people_outline_rounded,
                        size: 36,
                        color: AppTheme.slateMuted,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        store.guests.isEmpty
                            ? 'No guests yet'
                            : 'No matching guests',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        store.guests.isEmpty
                            ? 'Guests will appear here after check-in.'
                            : 'Try another search or filter.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.slateMuted,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final guest = filtered[index];
                    final stay = _findStayForGuest(store, guest.id);
                    final isInHouse = activeGuestIds.contains(guest.id);
                    final statusLabel = isInHouse
                        ? 'In-House'
                        : stay?.status == StayStatus.reserved
                        ? 'Reservation'
                        : 'Past Guest';
                    final statusColor = isInHouse
                        ? const Color(0xFF16834A)
                        : stay?.status == StayStatus.reserved
                        ? const Color(0xFF2563EB)
                        : AppTheme.slateMuted;
                    final statusBackground = isInHouse
                        ? const Color(0xFFE8F9ED)
                        : stay?.status == StayStatus.reserved
                        ? const Color(0xFFE5F0FF)
                        : const Color(0xFFF1F5F9);

                    final room = stay?.room ??
                        (stay != null
                            ? store.rooms
                                .cast<Room?>()
                                .firstWhere(
                                  (r) => r?.id == stay.roomId,
                                  orElse: () => null,
                                )
                            : null);
                    final roomLabel = room != null
                        ? 'Room ${room.roomNumber}'
                        : guest.phone.isNotEmpty
                        ? guest.phone
                        : 'Guest record';

                    return PressableScale(
                      onTap: () => _showGuestProfile(context, guest, store),
                      pressedScale: 0.985,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                AppTheme.slateBorder.withValues(alpha: 0.85),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFFE5F0FF),
                              child: Text(
                                guest.fullName.isNotEmpty
                                    ? guest.fullName[0].toUpperCase()
                                    : 'G',
                                style: GoogleFonts.inter(
                                  color: AppTheme.brandPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    guest.fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    roomLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: AppTheme.slateMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusBackground,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppTheme.slateMuted,
                                  size: 18,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String id, String label) {
    final isSel = _filter == id;
    return PressableScale(
      onTap: () => setState(() => _filter = id),
      pressedScale: 0.94,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSel ? AppTheme.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSel ? AppTheme.brandPrimary : AppTheme.slateBorder,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSel ? Colors.white : AppTheme.slateDark,
          ),
        ),
      ),
    );
  }

  Widget _buildViewByButton() {
    String currentSortLabel = 'View by';
    if (_sortBy == 'name') currentSortLabel = 'By Name';
    if (_sortBy == 'room') currentSortLabel = 'By Room';
    if (_sortBy == 'status') currentSortLabel = 'By Status';

    return PressableScale(
      pressedScale: 0.94,
      child: PopupMenuButton<String>(
        onSelected: (val) => setState(() => _sortBy = val),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'recent', child: Text('Recent / Default')),
          PopupMenuItem(value: 'name', child: Text('Name (A - Z)')),
          PopupMenuItem(value: 'room', child: Text('Room Number')),
          PopupMenuItem(value: 'status', child: Text('Status (In-House first)')),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.slateBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.filter_list_rounded,
                size: 14,
                color: AppTheme.slateMuted,
              ),
              const SizedBox(width: 5),
              Text(
                currentSortLabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: AppTheme.slateMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomFilterChip(HotelStore store) {
    final isFiltered = _roomFilter != 'all';
    final label = isFiltered
        ? (store.rooms.any((r) => r.id == _roomFilter || r.roomNumber == _roomFilter)
            ? 'Room ${store.rooms.firstWhere((r) => r.id == _roomFilter || r.roomNumber == _roomFilter).roomNumber}'
            : 'Room: $_roomFilter')
        : 'All Rooms';

    return PressableScale(
      pressedScale: 0.94,
      child: PopupMenuButton<String>(
        onSelected: (val) => setState(() => _roomFilter = val),
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'all', child: Text('All Rooms')),
          ...store.rooms.map(
            (r) => PopupMenuItem(
              value: r.roomNumber,
              child: Text('Room ${r.roomNumber} (${r.categoryName})'),
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isFiltered ? AppTheme.brandPrimary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isFiltered ? AppTheme.brandPrimary : AppTheme.slateBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bed_outlined,
                size: 14,
                color: isFiltered ? Colors.white : AppTheme.slateMuted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isFiltered ? Colors.white : AppTheme.slateDark,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: isFiltered ? Colors.white : AppTheme.slateMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdTypeFilterChip(HotelStore store) {
    final idTypes = store.guests
        .map((guest) => guest.idType.trim().toLowerCase())
        .where((idType) => idType.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final isFiltered = _idTypeFilter != 'all';
    final label = isFiltered
        ? '${_idTypeFilter[0].toUpperCase()}${_idTypeFilter.substring(1)}'
        : 'ID Type';

    return PressableScale(
      pressedScale: 0.94,
      child: PopupMenuButton<String>(
        onSelected: (value) => setState(() => _idTypeFilter = value),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'all', child: Text('All ID Types')),
          ...idTypes.map(
            (idType) => PopupMenuItem(
              value: idType,
              child: Text('${idType[0].toUpperCase()}${idType.substring(1)}'),
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isFiltered ? AppTheme.brandPrimary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isFiltered ? AppTheme.brandPrimary : AppTheme.slateBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.badge_outlined,
                size: 14,
                color: isFiltered ? Colors.white : AppTheme.slateMuted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isFiltered ? Colors.white : AppTheme.slateDark,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: isFiltered ? Colors.white : AppTheme.slateMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateFilterChip() {
    final isFiltered = _dateFilter != GuestDateFilter.all;
    String label = 'All Time';
    if (_dateFilter == GuestDateFilter.today) label = 'Today';
    if (_dateFilter == GuestDateFilter.thisWeek) label = 'This Week';
    if (_dateFilter == GuestDateFilter.thisMonth) label = 'This Month';
    if (_dateFilter == GuestDateFilter.customRange &&
        _customDateRange != null) {
      label =
          '${DateFormat('d MMM').format(_customDateRange!.start)} - ${DateFormat('d MMM').format(_customDateRange!.end)}';
    }

    return PressableScale(
      pressedScale: 0.94,
      child: PopupMenuButton<GuestDateFilter>(
        onSelected: (val) async {
          if (val == GuestDateFilter.customRange) {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2024),
              lastDate: DateTime(2030),
              initialDateRange:
                  _customDateRange ??
                  DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 7)),
                    end: DateTime.now(),
                  ),
            );
            if (range != null) {
              setState(() {
                _dateFilter = GuestDateFilter.customRange;
                _customDateRange = range;
              });
            }
          } else {
            setState(() => _dateFilter = val);
          }
        },
        itemBuilder: (ctx) => const [
          PopupMenuItem(value: GuestDateFilter.all, child: Text('All Time')),
          PopupMenuItem(value: GuestDateFilter.today, child: Text('Today')),
          PopupMenuItem(
            value: GuestDateFilter.thisWeek,
            child: Text('This Week'),
          ),
          PopupMenuItem(
            value: GuestDateFilter.thisMonth,
            child: Text('This Month'),
          ),
          PopupMenuItem(
            value: GuestDateFilter.customRange,
            child: Text('Custom Date Range...'),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isFiltered ? AppTheme.brandPrimary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isFiltered ? AppTheme.brandPrimary : AppTheme.slateBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 13,
                color: isFiltered ? Colors.white : AppTheme.slateMuted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isFiltered ? Colors.white : AppTheme.slateDark,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: isFiltered ? Colors.white : AppTheme.slateMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.slateBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Guest Directory Filters',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.slateDark,
                    ),
                  ),
                  if (_filter != 'all' ||
                      _roomFilter != 'all' ||
                      _idTypeFilter != 'all' ||
                      _dateFilter != GuestDateFilter.all ||
                      _searchController.text.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _filter = 'all';
                          _roomFilter = 'all';
                          _idTypeFilter = 'all';
                          _dateFilter = GuestDateFilter.all;
                          _customDateRange = null;
                          _searchController.clear();
                        });
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        'Reset All',
                        style: GoogleFonts.inter(
                          color: AppTheme.brandPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Filter guests easily using the category and status chips above the list.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.slateMuted,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brandPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
