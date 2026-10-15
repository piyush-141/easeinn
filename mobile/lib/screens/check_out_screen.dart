import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/hotel_store.dart';
import '../models/stay.dart';
import '../models/bill.dart';
import '../theme/app_theme.dart';
import 'booking_checkout_screen.dart';

class CheckOutScreen extends StatelessWidget {
  final String? initialStayId;
  const CheckOutScreen({super.key, this.initialStayId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final activeStays = store.activeStays;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Check-Out',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.slateDark,
                    ),
                  ),
                  Text(
                    '${activeStays.length} booking${activeStays.length != 1 ? "s" : ""} pending check-out',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.slateMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Summary strip
            if (activeStays.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildSummaryStrip(activeStays, store),
              ),

            const SizedBox(height: 14),

            // Bookings list
            Expanded(
              child: activeStays.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      itemCount: activeStays.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final stay = activeStays[index];
                        return _buildBookingCard(context, stay, store);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStrip(List<Stay> stays, HotelStore store) {
    double totalDue = 0;
    for (final stay in stays) {
      Bill? bill;
      try {
        bill = store.bills.firstWhere((b) => b.stayId == stay.id);
      } catch (_) {}
      final nights = stay.actualNights;
      final roomTotal = nights * stay.nightlyRate;
      final paid = bill?.amountPaid ?? 0.0;
      totalDue += (roomTotal - paid).clamp(0.0, roomTotal);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.brandLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.hotel_rounded, size: 19, color: AppTheme.brandPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Rooms Pending',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.slateMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${stays.length}',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 34,
            color: const Color(0xFFE2E8F0),
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: totalDue > 0 ? const Color(0xFFFEF3C7) : AppTheme.statusVacantBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.payments_rounded,
                    size: 19,
                    color: totalDue > 0 ? const Color(0xFFD97706) : AppTheme.statusVacant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Total Outstanding',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.slateMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '₹${totalDue.toInt()}',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: totalDue > 0 ? const Color(0xFFD97706) : AppTheme.statusVacant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCard(BuildContext context, Stay stay, HotelStore store) {
    Bill? bill;
    try {
      bill = store.bills.firstWhere((b) => b.stayId == stay.id);
    } catch (_) {}

    final nights = stay.actualNights;
    final roomTotal = nights * stay.nightlyRate;
    final advancePaid = bill?.amountPaid ?? 0.0;
    final balanceDue = (roomTotal - advancePaid).clamp(0.0, roomTotal);
    final isOverdue = stay.expectedCheckOut.isBefore(DateTime.now());

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BookingCheckOutScreen(stay: stay)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOverdue ? Colors.red.shade200 : AppTheme.slateBorder,
            width: isOverdue ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Room badge
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.brandPrimary, AppTheme.brandAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      stay.room?.roomNumber ?? '?',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            stay.guest?.fullName ?? 'Guest',
                            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded, size: 13, color: Color(0xFF16A34A)),
                          if (isOverdue) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('OVERDUE', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.red.shade600)),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${stay.room?.categoryName ?? "Room"} • ${stay.guestSummary}',
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Due', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.slateMuted)),
                    Text(
                      '₹${balanceDue.toInt()}',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: balanceDue > 0 ? AppTheme.brandPrimary : AppTheme.statusVacant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.slateBorder),
            const SizedBox(height: 10),

            // Duration & Navigation Row
            Row(
              children: [
                _infoChip(Icons.dark_mode_rounded, '$nights night${nights > 1 ? "s" : ""}'),
                if (stay.coGuests.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _infoChip(
                      Icons.group_rounded,
                      '+ ${stay.coGuests.map((g) => g.fullName).join(", ")}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.brandLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.arrow_forward_rounded, size: 14, color: AppTheme.brandPrimary),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // In and Out dates moved below in a neat dedicated pill container
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.login_rounded, size: 12, color: AppTheme.statusVacant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'In: ${DateFormat('d MMM, hh:mm a').format(stay.checkInAt)}',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slateDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 14, color: AppTheme.slateBorder, margin: const EdgeInsets.symmetric(horizontal: 6)),
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 12,
                          color: isOverdue ? const Color(0xFFDC2626) : AppTheme.brandPrimary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Out: ${DateFormat('d MMM, hh:mm a').format(stay.expectedCheckOut)}',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isOverdue ? const Color(0xFFDC2626) : AppTheme.slateDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, {TextOverflow? overflow}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppTheme.slateMuted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
            overflow: overflow,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppTheme.statusVacantBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_rounded, color: AppTheme.statusVacant, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              'No Check-Outs Pending',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
            ),
            const SizedBox(height: 6),
            Text(
              'All rooms are currently vacant or in housekeeping. Active bookings will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
            ),
          ],
        ),
      ),
    );
  }
}
