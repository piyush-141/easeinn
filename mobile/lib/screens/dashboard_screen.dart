import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/hotel_store.dart';
import '../models/room.dart';
import '../models/stay.dart';
import '../theme/app_theme.dart';
import 'calendar_screen.dart';
import 'booking_checkout_screen.dart';
import 'check_in_screen.dart';
import 'booking_export_screen.dart';
import 'whatsapp_screen.dart';
import '../widgets/pressable_scale.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(
    int tabIndex, {
    BookingMode? initialMode,
    String? preselectedRoomId,
  })
  onNavigateTab;
  const DashboardScreen({super.key, required this.onNavigateTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    super.dispose();
  }

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Good night';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 300));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 1. GREETING & TODAY'S OVERVIEW INFO (NO BG CARD - MATCHING IMAGE 1) ──
                _buildGreetingOverview(context, store),

                const SizedBox(height: 20),

                // ── 2. QUICK ACTIONS (KEPT EXACTLY AS IT IS) ──
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
                        gradientColors: const [
                          Color(0xFF00C9A7),
                          Color(0xFF00B4D8),
                        ],
                        onTap: () => widget.onNavigateTab(
                          2,
                          initialMode: BookingMode.reservation,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Top Right: Quick Check-in (Magenta/Pink Gradient)
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'Quick Check-in',
                        icon: Icons.person_add_alt_1_rounded,
                        gradientColors: const [
                          Color(0xFFFF3366),
                          Color(0xFFFF5E7E),
                        ],
                        onTap: () => widget.onNavigateTab(
                          2,
                          initialMode: BookingMode.checkIn,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Bottom Left: Booking Register (Orange/Amber Gradient)
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'Booking Register',
                        icon: Icons.table_chart_rounded,
                        gradientColors: const [
                          Color(0xFFFF9F1C),
                          Color(0xFFFF6B35),
                        ],
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BookingExportScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Bottom Right: Insights (Purple/Indigo Gradient)
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'Insights',
                        icon: Icons.bar_chart_rounded,
                        gradientColors: const [
                          Color(0xFF4361EE),
                          Color(0xFF7209B7),
                        ],
                        onTap: () => _showInsightsSheet(context, store),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // ── 3. DYNAMIC ROOM TIMELINE BANNER ──
                PressableScale(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CalendarScreen()),
                    );
                  },
                  pressedScale: 0.96,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF0369A1),
                          Color(0xFF1D4ED8),
                          Color(0xFF1E3A8A),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF60A5FA),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF1D4ED8,
                          ).withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF38BDF8), Color(0xFF2563EB)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.16),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.calendar_month_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
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
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Weekly, 3 Days & Today schedule matrix',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.84),
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

                // ── WHATSAPP AUTOMATION BANNER ──
                PressableScale(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WhatsAppScreen()),
                    );
                  },
                  pressedScale: 0.96,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F5132), Color(0xFF198754)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF198754,
                          ).withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.chat_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'WhatsApp Automation',
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Container(
                                  //   padding: const EdgeInsets.symmetric(
                                  //     horizontal: 6,
                                  //     vertical: 2,
                                  // ),
                                  // decoration: BoxDecoration(
                                  //   color: Colors.white.withValues(
                                  //     alpha: 0.25,
                                  //   ),
                                  //   borderRadius: BorderRadius.circular(6),
                                  // ),
                                  // child: const Text(
                                  //   'AUTO',
                                  //   style: TextStyle(
                                  //     color: Colors.white,
                                  //     fontSize: 9,
                                  //     fontWeight: FontWeight.bold,
                                  //     letterSpacing: 0.5,
                                  //   ),
                                  // ),
                                  // ),
                                ],
                              ),
                              Text(
                                'Pair QR code, edit templates & view logs',
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

                const SizedBox(height: 18),

                // ── 4. 2x2 STATUS CARDS (CLEAN & MINIMAL WHITE CARDS) ──
                _buildStatusCardsGrid(context, store, currencyFormat),

                const SizedBox(height: 24),

                // ── 5. IN-HOUSE GUESTS SECTION ──
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
                        onTap: () => widget.onNavigateTab(4),
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
                    padding: const EdgeInsets.symmetric(
                      vertical: 28,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.slateBorder),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.bed_outlined,
                          color: AppTheme.slateMuted.withValues(alpha: 0.4),
                          size: 38,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No Guests Currently In-House',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.slateDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap "Quick Check-in" above to scan guest ID and allocate a room.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: AppTheme.slateMuted,
                            fontSize: 12,
                          ),
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
                                      const Icon(
                                        Icons.verified_rounded,
                                        size: 12,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${stay.room?.categoryName} • ${stay.actualNights}n • ₹${stay.nightlyRate.toInt()}/n',
                                    style: GoogleFonts.inter(
                                      color: AppTheme.slateMuted,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'In: ${DateFormat('d MMM, hh:mm a').format(stay.checkInAt)}',
                                        style: GoogleFonts.inter(
                                          color: AppTheme.slateMuted,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Out: ${DateFormat('d MMM, hh:mm a').format(stay.expectedCheckOut)}',
                                        style: GoogleFonts.inter(
                                          color: AppTheme.brandPrimary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
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
                            PressableScale(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        BookingCheckOutScreen(stay: stay),
                                  ),
                                );
                              },
                              pressedScale: 0.92,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppTheme.brandPrimary,
                                  ),
                                ),
                                child: const Text(
                                  'Checkout',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.brandPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 1. GREETING OVERVIEW (WRAPPED IN ONE MINIMAL CARD) ──
  Widget _buildGreetingOverview(BuildContext context, HotelStore store) {
    final staffFirstName = store.staffName.split(' ').first;
    final now = DateTime.now();
    final formattedDate = DateFormat('EEEE, d MMMM').format(now);
    final hour = now.hour;
    final IconData timeIcon;
    if (hour < 5 || hour >= 21) {
      timeIcon = Icons.nightlight_round;
    } else if (hour < 12) {
      timeIcon = Icons.wb_sunny_rounded;
    } else if (hour < 17) {
      timeIcon = Icons.wb_sunny_rounded;
    } else {
      timeIcon = Icons.wb_twilight_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.92),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withValues(alpha: 0.12),
            blurRadius: 22,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.72),
            blurRadius: 5,
            offset: const Offset(-2, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.58),
                  Colors.white.withValues(alpha: 0.38),
                  Colors.white.withValues(alpha: 0.68),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Greeting Row with a restrained time-of-day accent.
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.66),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              timeIcon,
                              color: const Color(0xFF475569),
                              size: 23,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_getTimeGreeting()}, $staffFirstName',
                                  style: GoogleFonts.outfit(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.slateDark,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$formattedDate · Today\'s overview',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // 3 Info Columns (Arrivals, Departures, Occupancy)
                      Row(
                        children: [
                          // Arrivals
                          Expanded(
                            child: _buildInfoItem(
                              label: 'Arrivals',
                              value: '${store.arrivalsToday}',
                              valueColor: const Color(
                                0xFF2563EB,
                              ), // Blue accent
                              caption: 'Expected today',
                              onTap: () => _showArrivalsDrawer(context, store),
                            ),
                          ),
                          // Departures
                          Expanded(
                            child: _buildInfoItem(
                              label: 'Departures',
                              value: '${store.departuresToday}',
                              valueColor: const Color(0xFFFF9500),
                              caption: 'Expected today',
                              onTap: () =>
                                  _showDeparturesDrawer(context, store),
                            ),
                          ),
                          // Occupancy
                          Expanded(
                            child: _buildInfoItem(
                              label: 'Occupancy',
                              value: '${store.occupancyRate}%',
                              valueColor: AppTheme.slateDark,
                              caption:
                                  '${store.occupiedRooms} of ${store.totalRooms} rooms',
                              onTap: () => _showOccupancyDrawer(context, store),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 22,
                  right: 22,
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.98),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required String label,
    required String value,
    required Color valueColor,
    required String caption,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.93,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: valueColor,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.slateMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── QUICK ACTIONS GRADIENT CARD COMPONENT ──
  Widget _buildGradientQuickCard({
    required String title,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.94,
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
                child: Center(child: Icon(icon, color: Colors.white, size: 18)),
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

  // ── 4. 2x2 STATUS CARDS (CLEAN & MINIMAL WHITE CARDS) ──
  Widget _buildStatusCardsGrid(
    BuildContext context,
    HotelStore store,
    NumberFormat currencyFormat,
  ) {
    return Column(
      children: [
        Row(
          children: [
            // Card 1: Occupied
            Expanded(
              child: _buildMinimalStatusCard(
                icon: Icons.bed_rounded,
                iconColor: const Color(0xFF3B82F6), // Blue
                title: 'Occupied',
                subtitle: 'Current rooms in use',
                metric: store.occupiedRooms == 1
                    ? '1 room'
                    : '${store.occupiedRooms} rooms',
                onTap: () => _showOccupancyDrawer(
                  context,
                  store,
                  initialFilter: 'booked',
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Card 2: Vacant
            Expanded(
              child: _buildMinimalStatusCard(
                icon: Icons.check_circle_outline_rounded,
                iconColor: const Color(0xFF10B981), // Green
                title: 'Vacant',
                subtitle: 'Ready to sell',
                metric: store.vacantRooms == 1
                    ? '1 room'
                    : '${store.vacantRooms} rooms',
                onTap: () =>
                    _showOccupancyDrawer(context, store, initialFilter: 'free'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Card 3: Needs Cleaning
            Expanded(
              child: _buildMinimalStatusCard(
                icon: Icons.cleaning_services_outlined,
                iconColor: const Color(0xFFF59E0B), // Orange / Amber
                title: 'Needs Cleaning',
                subtitle: 'Housekeeping status',
                metric: store.cleaningRooms == 1
                    ? '1 room'
                    : '${store.cleaningRooms} rooms',
                onTap: () => _showOccupancyDrawer(
                  context,
                  store,
                  initialFilter: 'cleaning',
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Card 4: Today's Collection
            Expanded(
              child: _buildMinimalStatusCard(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: const Color(0xFFA855F7), // Purple
                title: 'Today\'s Collection',
                subtitle: 'Payments recorded today',
                metric: currencyFormat.format(store.revenueToday),
                onTap: () => _showCollectionDrawer(context, store),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMinimalStatusCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String metric,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.95,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.slateBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
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
                Icon(icon, color: iconColor, size: 21),
                Text(
                  metric,
                  style: GoogleFonts.outfit(
                    color: AppTheme.slateDark,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: GoogleFonts.outfit(
                color: AppTheme.slateDark,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                color: AppTheme.slateMuted,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── ARRIVALS DRAWER ──
  void _showArrivalsDrawer(BuildContext context, HotelStore store) {
    final now = DateTime.now();
    final arrivals = store.stays.where((s) {
      return s.checkInAt.year == now.year &&
          s.checkInAt.month == now.month &&
          s.checkInAt.day == now.day;
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Expected Arrivals',
                      style: GoogleFonts.outfit(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    Text(
                      '${arrivals.length} check-in${arrivals.length == 1 ? '' : 's'} scheduled for today',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${arrivals.length}',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2563EB),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: arrivals.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_available_rounded,
                            size: 48,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No Arrivals Scheduled for Today',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap "Quick Check-in" above to register a walk-in guest.',
                            style: GoogleFonts.inter(
                              color: AppTheme.slateMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: arrivals.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final stay = arrivals[i];
                        final isAlreadyInHouse =
                            stay.status == StayStatus.active;

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.slateBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    stay.room?.roomNumber ?? '-',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: const Color(0xFF2563EB),
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
                                      stay.guest?.fullName ?? 'Guest',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                    Text(
                                      '${stay.room?.categoryName} • ${stay.numGuests} Guest${stay.numGuests > 1 ? 's' : ''}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppTheme.slateMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Arrival Time: ${DateFormat('hh:mm a').format(stay.checkInAt)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        color: const Color(0xFF2563EB),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isAlreadyInHouse)
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    widget.onNavigateTab(
                                      2,
                                      initialMode: BookingMode.checkIn,
                                      preselectedRoomId: stay.roomId,
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.brandPrimary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Check In',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'In-House',
                                    style: TextStyle(
                                      color: Color(0xFF059669),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DEPARTURES DRAWER ──
  void _showDeparturesDrawer(BuildContext context, HotelStore store) {
    final now = DateTime.now();
    final departures = store.stays.where((s) {
      return s.status == StayStatus.active &&
          s.expectedCheckOut.year == now.year &&
          s.expectedCheckOut.month == now.month &&
          s.expectedCheckOut.day == now.day;
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Expected Departures',
                      style: GoogleFonts.outfit(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    Text(
                      '${departures.length} check-out${departures.length == 1 ? '' : 's'} scheduled for today',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${departures.length}',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFFF9500),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: departures.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.luggage_outlined,
                            size: 48,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No Departures Remaining Today',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'All scheduled check-outs are complete.',
                            style: GoogleFonts.inter(
                              color: AppTheme.slateMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: departures.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final stay = departures[i];

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
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
                                    Text(
                                      stay.guest?.fullName ?? 'Guest',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                    Text(
                                      '${stay.room?.categoryName} • In-house',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppTheme.slateMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Due Out: ${DateFormat('hh:mm a').format(stay.expectedCheckOut)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        color: const Color(0xFFFF9500),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BookingCheckOutScreen(stay: stay),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.brandPrimary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Checkout',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── OCCUPANCY DRAWER: SHOWS WHICH ROOM IS BOOKED AND FREE ──
  void _showOccupancyDrawer(
    BuildContext context,
    HotelStore store, {
    String initialFilter = 'all',
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            String activeFilter = initialFilter;

            final rooms = store.rooms;
            final bookedRooms = rooms
                .where(
                  (r) =>
                      r.status == RoomStatus.occupied ||
                      r.status == RoomStatus.reserved,
                )
                .toList();
            final freeRooms = rooms
                .where((r) => r.status == RoomStatus.vacant)
                .toList();
            final cleaningRooms = rooms
                .where((r) => r.status == RoomStatus.needsCleaning)
                .toList();

            List<Room> displayedRooms;
            if (activeFilter == 'booked') {
              displayedRooms = bookedRooms;
            } else if (activeFilter == 'free') {
              displayedRooms = freeRooms;
            } else if (activeFilter == 'cleaning') {
              displayedRooms = cleaningRooms;
            } else {
              displayedRooms = rooms;
            }

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.82,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Room Occupancy Directory',
                            style: GoogleFonts.outfit(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          Text(
                            '${bookedRooms.length} Booked • ${freeRooms.length} Free • ${cleaningRooms.length} Cleaning',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.brandLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${store.occupancyRate}%',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.brandPrimary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Filter Segment Tabs
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(
                          'all',
                          'All Rooms (${rooms.length})',
                          activeFilter,
                          (val) {
                            setModalState(() => activeFilter = val);
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          'booked',
                          'Booked (${bookedRooms.length})',
                          activeFilter,
                          (val) {
                            setModalState(() => activeFilter = val);
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          'free',
                          'Free (${freeRooms.length})',
                          activeFilter,
                          (val) {
                            setModalState(() => activeFilter = val);
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          'cleaning',
                          'Cleaning (${cleaningRooms.length})',
                          activeFilter,
                          (val) {
                            setModalState(() => activeFilter = val);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Room Directory Cards
                  Expanded(
                    child: displayedRooms.isEmpty
                        ? Center(
                            child: Text(
                              'No rooms in this category',
                              style: GoogleFonts.inter(
                                color: AppTheme.slateMuted,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: displayedRooms.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final room = displayedRooms[i];
                              final isOccupied =
                                  room.status == RoomStatus.occupied;
                              final isVacant = room.status == RoomStatus.vacant;
                              final isCleaning =
                                  room.status == RoomStatus.needsCleaning;
                              final isReserved =
                                  room.status == RoomStatus.reserved;

                              // Find associated stay if booked
                              final activeStay =
                                  store.activeStays
                                      .where((s) => s.roomId == room.id)
                                      .firstOrNull ??
                                  store.stays
                                      .where(
                                        (s) =>
                                            s.roomId == room.id &&
                                            s.status != StayStatus.checkedOut,
                                      )
                                      .firstOrNull;

                              Color badgeBg;
                              Color badgeColor;
                              String badgeText;

                              if (isOccupied) {
                                badgeBg = const Color(0xFFEFF6FF);
                                badgeColor = const Color(0xFF2563EB);
                                badgeText = 'BOOKED / IN-USE';
                              } else if (isVacant) {
                                badgeBg = const Color(0xFFECFDF5);
                                badgeColor = const Color(0xFF059669);
                                badgeText = 'FREE / READY';
                              } else if (isCleaning) {
                                badgeBg = const Color(0xFFFEF3C7);
                                badgeColor = const Color(0xFFD97706);
                                badgeText = 'NEEDS CLEANING';
                              } else if (isReserved) {
                                badgeBg = const Color(0xFFE0F2FE);
                                badgeColor = const Color(0xFF0284C7);
                                badgeText = 'RESERVED';
                              } else {
                                badgeBg = const Color(0xFFF1F5F9);
                                badgeColor = AppTheme.slateMuted;
                                badgeText = 'MAINTENANCE';
                              }

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isOccupied
                                        ? const Color(0xFFBFDBFE)
                                        : isVacant
                                        ? const Color(0xFFA7F3D0)
                                        : AppTheme.slateBorder,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppTheme.slateBorder,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          room.roomNumber,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17,
                                            color: AppTheme.slateDark,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: badgeBg,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  badgeText,
                                                  style: GoogleFonts.inter(
                                                    color: badgeColor,
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Floor ${room.floor}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 10.5,
                                                  color: AppTheme.slateMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            room.categoryName,
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: AppTheme.slateDark,
                                            ),
                                          ),
                                          if (isOccupied &&
                                              activeStay?.guest != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Guest: ${activeStay!.guest!.fullName}',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: const Color(0xFF2563EB),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ] else ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Base Rate: ₹${room.baseRate.toInt()}/night',
                                              style: GoogleFonts.inter(
                                                fontSize: 10.5,
                                                color: AppTheme.slateMuted,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (isVacant)
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          widget.onNavigateTab(
                                            2,
                                            initialMode: BookingMode.checkIn,
                                            preselectedRoomId: room.id,
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF059669,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          elevation: 0,
                                        ),
                                        child: const Text(
                                          'Book',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    else if (isCleaning)
                                      ElevatedButton(
                                        onPressed: () {
                                          store.updateRoomStatus(
                                            room.id,
                                            RoomStatus.vacant,
                                          );
                                          setModalState(() {});
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Room ${room.roomNumber} marked clean & ready to sell.',
                                              ),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFD97706,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          elevation: 0,
                                        ),
                                        child: const Text(
                                          'Mark Clean',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    else if (isOccupied && activeStay != null)
                                      OutlinedButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  BookingCheckOutScreen(
                                                    stay: activeStay,
                                                  ),
                                            ),
                                          );
                                        },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xFF2563EB,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFF2563EB),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'Folio',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
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

  Widget _buildFilterChip(
    String key,
    String title,
    String activeFilter,
    ValueChanged<String> onSelected,
  ) {
    final isSelected = activeFilter == key;
    return InkWell(
      onTap: () => onSelected(key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.slateDark : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.slateMuted,
          ),
        ),
      ),
    );
  }

  // ── TODAY'S COLLECTION DRAWER ──
  void _showCollectionDrawer(BuildContext context, HotelStore store) {
    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    final now = DateTime.now();
    final todayPayments = store.payments.where((p) {
      return p.recordedAt.year == now.year &&
          p.recordedAt.month == now.month &&
          p.recordedAt.day == now.day;
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.65,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Payment Receipts',
                      style: GoogleFonts.outfit(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                      ),
                    ),
                    Text(
                      'Total Collected: ${currencyFormat.format(store.revenueToday)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F9ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    currencyFormat.format(store.revenueToday),
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF34C759),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: todayPayments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 48,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No Payments Recorded Today',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppTheme.slateDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Payments from advance check-ins or checkout settlements appear here.',
                            style: GoogleFonts.inter(
                              color: AppTheme.slateMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: todayPayments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final p = todayPayments[i];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.slateBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${p.method.toUpperCase()} • ${p.paymentType.toUpperCase()}',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                  Text(
                                    'Recorded: ${DateFormat('hh:mm a').format(p.recordedAt)} ${p.reference != null ? '• Ref: ${p.reference}' : ''}',
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      color: AppTheme.slateMuted,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                currencyFormat.format(p.amount),
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: const Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── INSIGHTS BOTTOM SHEET ──
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.slateMuted,
              ),
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
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
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
                      value: store.totalRooms > 0
                          ? (store.occupiedRooms / store.totalRooms)
                          : 0,
                      backgroundColor: AppTheme.slateBorder,
                      valueColor: const AlwaysStoppedAnimation(
                        AppTheme.brandPrimary,
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${store.occupiedRooms} occupied • ${store.vacantRooms} vacant • ${store.cleaningRooms} cleaning of ${store.totalRooms} rooms',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.slateMuted,
                    ),
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
                        Text(
                          'Revenue Today',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${store.revenueToday.toInt()}',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
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
                        Text(
                          'Avg Room Rate (ADR)',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) {
                            final adr = store.occupiedRooms > 0
                                ? (store.activeStays.fold<double>(
                                            0.0,
                                            (sum, s) => sum + s.nightlyRate,
                                          ) /
                                          store.occupiedRooms)
                                      .round()
                                : (store.rooms.isNotEmpty
                                      ? (store.rooms.fold<double>(
                                                  0.0,
                                                  (sum, r) => sum + r.baseRate,
                                                ) /
                                                store.rooms.length)
                                            .round()
                                      : 0);
                            return Text(
                              '₹$adr',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.slateDark,
                              ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
