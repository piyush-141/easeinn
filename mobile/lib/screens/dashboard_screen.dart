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
import 'finance_screen.dart';
import '../services/whatsapp_service.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchWhatsAppStatus();
    });
  }

  void _fetchWhatsAppStatus() {
    try {
      final store = context.read<HotelStore>();
      if (store.currentProperty.id.isNotEmpty) {
        WhatsAppService.currentHotelId = store.currentProperty.id;
      }
      WhatsAppService.getStatus().catchError((_) => WhatsAppStatusData.initial());
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _fetchWhatsAppStatus();
    }
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
            _fetchWhatsAppStatus();
            await store.syncData();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 1. GREETING & TODAY'S OVERVIEW INFO (NO BG CARD - MATCHING IMAGE 1) ──
                _buildGreetingOverview(context, store),

                // ── 2. QUICK ACTIONS (KEPT EXACTLY AS IT WAS) ──
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
                    // Top Left: New Reservation
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'New Reservation',
                        icon: Icons.edit_calendar_rounded,
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
                    // Top Right: Guest Check-in
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'Guest Check-in',
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
                    // Bottom Left: Booking Records
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'Booking Records',
                        icon: Icons.assignment_outlined,
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
                    // Bottom Right: Activity Timeline
                    Expanded(
                      child: _buildGradientQuickCard(
                        title: 'Activity Timeline',
                        icon: Icons.history_rounded,
                        gradientColors: const [
                          Color(0xFF0369A1),
                          Color(0xFF1E3A8A),
                        ],
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CalendarScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // ── 3. OVERVIEW SECTION TITLE ──
                Text(
                  'Overview',
                  style: GoogleFonts.outfit(
                    color: AppTheme.slateDark,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // ── 1x2 ROOM STATUS & TODAY'S COLLECTION WIDGETS ──
                _buildDualSummaryCards(context, store, currencyFormat),

                const SizedBox(height: 16),

                // ── 3. WHATSAPP AUTOMATION QUICK LINK ──
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.slateBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: PressableScale(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const WhatsAppScreen(),
                        ),
                      );
                      _fetchWhatsAppStatus();
                    },
                    child: ValueListenableBuilder<WhatsAppStatusData?>(
                      valueListenable: WhatsAppService.statusNotifier,
                      builder: (context, status, _) {
                        return _buildWhatsAppShortcutRow(status);
                      },
                    ),
                  ),
                ),

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

                const SizedBox(height: 84),
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
                      // Greeting Header
                      Column(
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

  String _formatWhatsAppNumber(String raw) {
    var clean = raw.trim();
    if (clean.contains('@')) {
      clean = clean.split('@').first;
    }
    if (clean.contains(':')) {
      clean = clean.split(':').first;
    }
    if (clean.startsWith('+')) {
      clean = clean.substring(1);
    }
    clean = clean.replaceAll(RegExp(r'\D'), '');
    if (clean.length == 12 && clean.startsWith('91')) {
      return '+91 ${clean.substring(2, 7)} ${clean.substring(7)}';
    } else if (clean.length == 10) {
      return '+91 ${clean.substring(0, 5)} ${clean.substring(5)}';
    } else if (clean.isNotEmpty) {
      return '+$clean';
    }
    return raw.trim();
  }

  Widget _buildWhatsAppShortcutRow(WhatsAppStatusData? status) {
    final isConnected = status != null &&
        (status.isReady || status.isConnected || status.status == 'CONNECTED');

    final rawNumber = status?.connectedNumber?.trim() ?? '';
    final pushName = status?.connectedPushname?.trim() ?? '';

    String displayNumber = '';
    if (isConnected) {
      if (rawNumber.isNotEmpty) {
        displayNumber = _formatWhatsAppNumber(rawNumber);
      } else if (pushName.isNotEmpty) {
        displayNumber = pushName;
      } else {
        displayNumber = 'WhatsApp Connected';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isConnected ? const Color(0xFFDCFCE7) : const Color(0xFFF1F3F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.chat_rounded,
              color: isConnected ? const Color(0xFF16A34A) : AppTheme.slateDark,
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
                  'WhatsApp Automation',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.slateDark,
                  ),
                ),
                const SizedBox(height: 4),
                // Status / Connected Number Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isConnected ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isConnected ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isConnected ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          isConnected ? displayNumber : 'Not connected',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: isConnected ? FontWeight.w600 : FontWeight.w500,
                            color: isConnected
                                ? const Color(0xFF15803D)
                                : const Color(0xFF64748B), // Simple neutral grey - no red or yellow!
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isConnected) ...[
                        const SizedBox(width: 4),
                        Text(
                          '• Active',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isConnected
                      ? 'Automated guest alerts, templates & logs'
                      : 'Pair QR code, edit templates & view logs',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: AppTheme.slateMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: AppTheme.slateMuted,
          ),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Center(child: Icon(icon, color: Colors.white, size: 22)),
            ),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 1x2 DUAL SUMMARY CARDS (ROOM STATUS & TODAY'S COLLECTION) ──
  Widget _buildDualSummaryCards(
    BuildContext context,
    HotelStore store,
    NumberFormat currencyFormat,
  ) {
    // 1. Pending dues & count of distinct guests with outstanding balances
    double pendingDues = 0.0;
    final pendingGuestIds = <String>{};
    for (final bill in store.bills) {
      if (bill.outstanding > 0) {
        pendingDues += bill.outstanding;
        final stay = store.stays.where((s) => s.id == bill.stayId).firstOrNull;
        if (stay != null && stay.guestId.isNotEmpty) {
          pendingGuestIds.add(stay.guestId);
        } else {
          pendingGuestIds.add(bill.id);
        }
      }
    }
    final pendingGuestsCount = pendingGuestIds.length;

    // 2. Today's bookings count
    final now = DateTime.now();
    final todayBookingsCount = store.stays.where((s) {
      return s.checkInAt.year == now.year &&
          s.checkInAt.month == now.month &&
          s.checkInAt.day == now.day;
    }).length;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── LEFT: Room Status ──
          Expanded(
            child: _buildRoomStatusWidget(context, store),
          ),
          const SizedBox(width: 12),
          // ── RIGHT: Today's Collection ──
          Expanded(
            child: _buildCollectionSummaryWidget(
              context,
              store,
              currencyFormat,
              pendingDues: pendingDues,
              pendingGuestsCount: pendingGuestsCount,
              todayBookingsCount: todayBookingsCount,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomStatusWidget(BuildContext context, HotelStore store) {
    return PressableScale(
      onTap: () => _showOccupancyDrawer(context, store, initialFilter: 'all'),
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF334155).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.bed_rounded,
                        color: Color(0xFF2563EB),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Room Status',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Occupancy Rate
                Text(
                  '${store.occupancyRate}%',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: store.totalRooms > 0
                        ? (store.occupiedRooms / store.totalRooms).clamp(0.0, 1.0)
                        : 0.0,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFDBEAFE).withValues(alpha: 0.7),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${store.occupiedRooms} of ${store.totalRooms} rooms occupied',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: AppTheme.slateMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 10),
                const Divider(height: 1, thickness: 0.6, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 10),

                // Status rows (Clean, no icons, neutral numbers)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showOccupancyDrawer(context, store, initialFilter: 'free'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Vacant & ready',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${store.vacantRooms}',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showOccupancyDrawer(context, store, initialFilter: 'cleaning'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Needs cleaning',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${store.cleaningRooms}',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Bottom Redirection Button (Same styling)
            _buildCardRedirectAction(
              label: 'View room status',
              onTap: () => _showOccupancyDrawer(context, store, initialFilter: 'all'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionSummaryWidget(
    BuildContext context,
    HotelStore store,
    NumberFormat currencyFormat, {
    required double pendingDues,
    required int pendingGuestsCount,
    required int todayBookingsCount,
  }) {
    return PressableScale(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FinanceScreen()),
        );
      },
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF334155).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Color(0xFF2563EB),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Today's Collection",
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Revenue Metric
                Text(
                  currencyFormat.format(store.revenueToday),
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),

                // Height matching container bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 5,
                    color: const Color(0xFFEFF6FF),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Payments received today',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: AppTheme.slateMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 10),
                const Divider(height: 1, thickness: 0.6, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 10),

                // Row 1: Pending Dues (Clean, no icons, neutral numbers)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FinanceScreen(initialTab: 2),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pending dues',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        currencyFormat.format(pendingDues),
                        style: GoogleFonts.outfit(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Row 2: Today's Bookings (Clean, no icons, neutral numbers)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Today's bookings",
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$todayBookingsCount',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Bottom Redirection Button (Same styling)
            _buildCardRedirectAction(
              label: 'View money status',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FinanceScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── UNIFIED CARD REDIRECTION ACTION (IDENTICAL STYLING) ──
  Widget _buildCardRedirectAction({
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        height: 34,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 13,
                color: Colors.white,
              ),
            ],
          ),
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
                Text(
                  'Today\'s Expected Arrivals',
                  style: GoogleFonts.outfit(
                    fontSize: 19,
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
                Text(
                  'Today\'s Expected Departures',
                  style: GoogleFonts.outfit(
                    fontSize: 19,
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
    String activeFilter = initialFilter;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {

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
                      Text(
                        'Room Occupancy Directory',
                        style: GoogleFonts.outfit(
                          fontSize: 19,
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
}
