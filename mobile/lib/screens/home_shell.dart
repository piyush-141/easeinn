import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/hotel_store.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'rooms_screen.dart';
import 'check_in_screen.dart';
import 'check_out_screen.dart';
import 'guests_screen.dart';
import 'calendar_screen.dart';
import 'manager_profile_screen.dart';
import 'hotels_screen.dart';
import 'whatsapp_screen.dart';

class HomeShell extends StatefulWidget {
  final int initialIndex;
  const HomeShell({super.key, this.initialIndex = 0});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _currentIndex;
  String? _preselectedRoomId;
  BookingMode _initialBookingMode = BookingMode.checkIn;
  bool _redirectedFromRooms = false;
  DateTime? _lastHomeBackPress;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTabSelected(
    int index, {
    String? preselectedRoomId,
    bool fromRooms = false,
    BookingMode? initialMode,
  }) {
    _lastHomeBackPress = null;
    setState(() {
      _preselectedRoomId = preselectedRoomId;
      _redirectedFromRooms = fromRooms;
      _initialBookingMode = initialMode ?? BookingMode.checkIn;
      _currentIndex = index;
    });
  }

  void _handleSystemBack() {
    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
        _preselectedRoomId = null;
        _redirectedFromRooms = false;
        _initialBookingMode = BookingMode.checkIn;
      });
      _lastHomeBackPress = null;
      return;
    }

    final now = DateTime.now();
    final lastPress = _lastHomeBackPress;
    if (lastPress != null &&
        now.difference(lastPress) <= const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }

    _lastHomeBackPress = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit EaseInn.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();

    final screens = [
      DashboardScreen(
        onNavigateTab: (idx, {initialMode, preselectedRoomId}) =>
            _onTabSelected(
              idx,
              initialMode: initialMode,
              preselectedRoomId: preselectedRoomId,
            ),
      ),
      RoomsScreen(
        onNavigateTab: (idx, {preselectedRoomId, initialMode}) =>
            _onTabSelected(
              idx,
              preselectedRoomId: preselectedRoomId,
              fromRooms: true,
              initialMode: initialMode,
            ),
      ),
      CheckInScreen(
        key: ValueKey('checkin_${_initialBookingMode}_$_preselectedRoomId'),
        preselectedRoomId: _preselectedRoomId,
        initialMode: _initialBookingMode,
        onReturnHome: () => _onTabSelected(0),
        onBack: _redirectedFromRooms
            ? () {
                setState(() {
                  _redirectedFromRooms = false;
                  _preselectedRoomId = null;
                });
                _onTabSelected(1);
              }
            : null,
      ),
      const CheckOutScreen(),
      const GuestsScreen(),
    ];

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleSystemBack();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: InkWell(
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const HotelsScreen()));
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.brandPrimary.withValues(alpha: 0.2),
                        width: 0.8,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        'assets/images/easeinn_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.hotel_rounded,
                          color: AppTheme.brandPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                store.currentProperty.name,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: AppTheme.slateMuted,
                            ),
                          ],
                        ),
                        Text(
                          '${store.currentProperty.city} • ${store.rooms.length} Rooms',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(
                Icons.chat_rounded,
                color: Color(0xFF25D366),
                size: 21,
              ),
              tooltip: 'WhatsApp Automation',
              onPressed: () {
                _lastHomeBackPress = null;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WhatsAppScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(
                Icons.calendar_month_rounded,
                color: AppTheme.brandPrimary,
                size: 22,
              ),
              tooltip: 'Dynamic Room Timeline & Calendar',
              onPressed: () {
                _lastHomeBackPress = null;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                );
              },
            ),
            // Shift Staff Badge / Manager Profile Button
            InkWell(
              onTap: () {
                _lastHomeBackPress = null;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ManagerProfileScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.only(right: 16, left: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.brandPrimary,
                      child: Text(
                        store.staffName.isNotEmpty
                            ? store.staffName.substring(0, 1)
                            : 'D',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: IndexedStack(index: _currentIndex, children: screens),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                // Left Floating Pill Container holding primary tabs
                Expanded(
                  child: Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: const Color(0xFFE8ECEF),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _buildPillTabItem(
                          index: 0,
                          icon: Icons.home_outlined,
                          activeIcon: Icons.home_rounded,
                          label: 'Home',
                        ),
                        _buildPillTabItem(
                          index: 1,
                          icon: Icons.meeting_room_outlined,
                          activeIcon: Icons.meeting_room_rounded,
                          label: 'Rooms',
                          badgeCount: store.cleaningRooms > 0
                              ? store.cleaningRooms
                              : null,
                          badgeColor: AppTheme.statusCleaning,
                        ),
                        _buildPillTabItem(
                          index: 3,
                          icon: Icons.logout_rounded,
                          activeIcon: Icons.logout_rounded,
                          label: 'Check-Out',
                          badgeCount: store.occupiedRooms > 0
                              ? store.occupiedRooms
                              : null,
                          badgeColor: AppTheme.brandPrimary,
                        ),
                        _buildPillTabItem(
                          index: 4,
                          icon: Icons.people_outline_rounded,
                          activeIcon: Icons.people_rounded,
                          label: 'Guests',
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Right Circular Action Button dedicated to Check-In (+ / Check-in icon)
                _buildCheckInActionButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillTabItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    int? badgeCount,
    Color? badgeColor,
  }) {
    final isSelected = _currentIndex == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _onTabSelected(index),
          splashColor: Colors.black.withValues(alpha: 0.04),
          highlightColor: Colors.black.withValues(alpha: 0.02),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE2E8F0) : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedScale(
                      scale: isSelected ? 1.04 : 1.0,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        isSelected ? activeIcon : icon,
                        size: 21,
                        color: isSelected
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF334155),
                      ),
                    ),
                    if (badgeCount != null && badgeCount > 0)
                      Positioned(
                        top: -3,
                        right: -7,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: badgeColor ?? const Color(0xFF0F172A),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF64748B),
                    letterSpacing: -0.2,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInActionButton() {
    final isSelected = _currentIndex == 2;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onTabSelected(2),
        borderRadius: BorderRadius.circular(28),
        splashColor: Colors.black.withValues(alpha: 0.05),
        highlightColor: Colors.black.withValues(alpha: 0.03),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0F172A) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? const Color(0xFF0F172A).withValues(alpha: 0.25)
                          : Colors.black.withValues(alpha: 0.05),
                      blurRadius: isSelected ? 12 : 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: AnimatedScale(
                  scale: isSelected ? 1.04 : 1.0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // User Check-In registration icon
                      Icon(
                        Icons.how_to_reg_rounded,
                        size: 22,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF0F172A),
                      ),
                      // Sleek '+' micro badge conveying immediate new check-in
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.brandPrimary
                                : const Color(0xFF0F172A),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 8,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF475569),
                  letterSpacing: -0.2,
                ),
                child: const Text('Check-In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
