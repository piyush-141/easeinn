import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/hotel_store.dart';
import '../theme/app_theme.dart';
import 'calendar_screen.dart';
import 'booking_checkout_screen.dart';
import 'check_in_screen.dart';

class DashboardScreen extends StatelessWidget {
  final void Function(int tabIndex, {BookingMode? initialMode}) onNavigateTab;
  const DashboardScreen({super.key, required this.onNavigateTab});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 300));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Welcome Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.slateDark, Color(0xFF1E1B4B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.brandPrimary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.brandPrimary.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.document_scanner_rounded, color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  'EaseInn PMS',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            DateFormat('EEE, d MMM yyyy').format(DateTime.now()),
                            style: GoogleFonts.inter(
                              color: Colors.white60,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Shift Operations',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Logged in as ${store.staffName} (${store.staffRole})',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ── TOP 4 OPTIONS (QUICK ACTIONS) - Matching media_1792076991413.png ──
                Text(
                  'Quick Actions',
                  style: GoogleFonts.outfit(
                    color: AppTheme.slateDark,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // 2x2 Gradient Quick Action Cards
                Row(
                  children: [
                    // Top Left: Reservation (Teal/Cyan Gradient)
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'Reservation',
                        icon: Icons.event_available_rounded,
                        gradientColors: const [Color(0xFF00C9A7), Color(0xFF00B4D8)],
                        onTap: () => onNavigateTab(2, initialMode: BookingMode.reservation),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Top Right: Quick Check-in (Magenta/Pink Gradient)
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'Quick Check-in',
                        icon: Icons.person_add_alt_1_rounded,
                        gradientColors: const [Color(0xFFFF3366), Color(0xFFFF5E7E)],
                        onTap: () => onNavigateTab(2, initialMode: BookingMode.checkIn),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Bottom Left: Guest Details (Orange/Amber Gradient)
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'Guest Details',
                        icon: Icons.people_alt_rounded,
                        gradientColors: const [Color(0xFFFF9F1C), Color(0xFFFF6B35)],
                        onTap: () => onNavigateTab(4), // Guests tab
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Bottom Right: Insights (Purple/Indigo Gradient)
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'Insights',
                        icon: Icons.bar_chart_rounded,
                        gradientColors: const [Color(0xFF4361EE), Color(0xFF7209B7)],
                        onTap: () => _showInsightsSheet(context, store),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // ── DYNAMIC ROOM TIMELINE & CALENDAR BANNER ──
                InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CalendarScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.brandLight, Colors.white],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.brandPrimary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.brandPrimary,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.brandPrimary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dynamic Room Timeline',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                              Text(
                                'Weekly, 3 Days & Today schedule matrix',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.brandPrimary),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // ── DYNAMIC METRICS GRID ──
                Row(
                  children: [
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Occupied',
                        value: '${store.occupiedRooms}',
                        subtitle: '${store.occupancyRate}% Rate',
                        icon: Icons.hotel_rounded,
                        color: AppTheme.statusOccupied,
                        bgColor: AppTheme.statusOccupiedBg,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Vacant',
                        value: '${store.vacantRooms}',
                        subtitle: 'Ready to check-in',
                        icon: Icons.check_circle_outline_rounded,
                        color: AppTheme.statusVacant,
                        bgColor: AppTheme.statusVacantBg,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Needs Cleaning',
                        value: '${store.cleaningRooms}',
                        subtitle: 'Housekeeping alert',
                        icon: Icons.cleaning_services_rounded,
                        color: AppTheme.statusCleaning,
                        bgColor: AppTheme.statusCleaningBg,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildKpiCard(
                        title: 'Today Collected',
                        value: currencyFormat.format(store.revenueToday),
                        subtitle: '${store.activeGuests} In-house guests',
                        icon: Icons.payments_outlined,
                        color: AppTheme.brandPrimary,
                        bgColor: AppTheme.brandLight,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // ── ACTIVE STAYS SECTION ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'In-House Guests (${store.activeStays.length})',
                      style: GoogleFonts.outfit(
                        color: AppTheme.slateDark,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (store.activeStays.isNotEmpty)
                      InkWell(
                        onTap: () => onNavigateTab(4),
                        child: Text(
                          'View all',
                          style: GoogleFonts.inter(
                            color: AppTheme.brandPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Active stays list or Empty State
                if (store.activeStays.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.slateBorder),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.bed_outlined, color: AppTheme.slateMuted.withValues(alpha: 0.5), size: 40),
                        const SizedBox(height: 8),
                        Text(
                          'No Guests In-House',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.slateDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "Quick Check-in" above to scan an ID and assign a room.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: AppTheme.slateMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: store.activeStays.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final stay = store.activeStays[index];

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.slateBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.brandLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  stay.room?.roomNumber ?? '-',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppTheme.brandPrimary,
                                  ),
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
                                      Expanded(
                                        child: Text(
                                          stay.guest?.fullName ?? 'Guest',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: AppTheme.slateDark,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(Icons.verified_rounded, size: 12, color: Color(0xFF16A34A)),
                                    ],
                                  ),
                                  Text(
                                    '${stay.room?.categoryName} • ${stay.actualNights}n • ₹${stay.nightlyRate.toInt()}/n',
                                    style: GoogleFonts.inter(
                                      color: AppTheme.slateMuted,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'In: ${DateFormat('d MMM, hh:mm a').format(stay.checkInAt)} • Out: ${DateFormat('d MMM, hh:mm a').format(stay.expectedCheckOut)}',
                                    style: GoogleFonts.inter(
                                      color: AppTheme.brandPrimary,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    stay.guestSummary,
                                    style: GoogleFonts.inter(
                                      color: AppTheme.slateDark,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => BookingCheckOutScreen(stay: stay)),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.brandPrimary,
                                side: const BorderSide(color: AppTheme.brandPrimary),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('Checkout', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Quick Action Card Component (Matching ui_inspo/quick_actions) ──
  Widget _buildGradientQuickCard({
    required String title,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: gradientColors.last.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Right Translucent Icon Badge
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
              ),
            ),

            // Bottom Left Bold Label
            Text(
              title,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  color: AppTheme.slateMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.slateDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Insights Bottom Sheet ──
  void _showInsightsSheet(BuildContext context, HotelStore store) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
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
                  'Hotel Insights & Analytics',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.slateDark,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.brandLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Realtime',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.brandPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${store.currentProperty.name} (${store.currentProperty.city})',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
            ),
            const SizedBox(height: 16),

            // Occupancy Progress Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.slateBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Room Occupancy Rate',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${store.occupancyRate}%',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.brandPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: store.totalRooms > 0 ? (store.occupiedRooms / store.totalRooms) : 0,
                      backgroundColor: AppTheme.slateBorder,
                      valueColor: const AlwaysStoppedAnimation(AppTheme.brandPrimary),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${store.occupiedRooms} occupied • ${store.vacantRooms} vacant • ${store.cleaningRooms} cleaning of ${store.totalRooms} rooms',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Revenue and ADR Grid
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.slateBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Revenue Today', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted)),
                        const SizedBox(height: 4),
                        Text(
                          '₹${store.revenueToday.toInt()}',
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.slateBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Avg Room Rate (ADR)', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted)),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) {
                            final adr = store.occupiedRooms > 0
                                ? (store.activeStays.fold<double>(0.0, (sum, s) => sum + s.nightlyRate) / store.occupiedRooms).round()
                                : (store.rooms.isNotEmpty
                                    ? (store.rooms.fold<double>(0.0, (sum, r) => sum + r.baseRate) / store.rooms.length).round()
                                    : 0);
                            return Text(
                              '₹$adr',
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Button to open Full Timeline Calendar
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                );
              },
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: const Text('Open Dynamic Calendar Timeline'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppTheme.brandPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
