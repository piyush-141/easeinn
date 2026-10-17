import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show ImageFilter;
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/hotel_store.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'rooms_screen.dart';
import 'check_in_screen.dart';
import 'check_out_screen.dart';
import 'guests_screen.dart';
import 'manager_profile_screen.dart';
import 'hotels_screen.dart';

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
        extendBody: true,
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
        bottomNavigationBar: _buildGlassNavigationBar(store),
      ),
    );
  }

  int get _selectedNavigationSlot => switch (_currentIndex) {
    0 => 0,
    1 => 1,
    3 => 2,
    4 => 3,
    2 => 0,
    _ => 0,
  };

  Widget _buildGlassNavigationBar(HotelStore store) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: Row(
          children: [
            Expanded(child: _buildPrimaryGlassPill(store)),
            const SizedBox(width: 10),
            _buildCheckInActionButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryGlassPill(HotelStore store) {
    const itemCount = 4;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / itemCount;
        return Container(
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: Colors.white.withValues(alpha: 0.84)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF334155).withValues(alpha: 0.13),
                blurRadius: 22,
                offset: const Offset(0, 7),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.60),
                blurRadius: 7,
                offset: const Offset(-2, -2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.58),
                            Colors.white.withValues(alpha: 0.34),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOutCubic,
                    left: itemWidth * _selectedNavigationSlot + 4,
                    top: 4,
                    bottom: 4,
                    width: itemWidth - 8,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _currentIndex == 2 ? 0 : 1,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.98),
                              Colors.white.withValues(alpha: 0.72),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.96),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF334155,
                              ).withValues(alpha: 0.10),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.88),
                              blurRadius: 3,
                              offset: const Offset(0, -1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Row(
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
                ],
              ),
            ),
          ),
        );
      },
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
          child: Padding(
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
    return SizedBox(
      width: 66,
      height: 64,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onTabSelected(2),
          borderRadius: BorderRadius.circular(30),
          splashColor: Colors.black.withValues(alpha: 0.05),
          highlightColor: Colors.black.withValues(alpha: 0.03),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.96)
                      : Colors.white.withValues(alpha: 0.42),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: isSelected ? 0.98 : 0.78,
                    ),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF334155,
                      ).withValues(alpha: isSelected ? 0.14 : 0.08),
                      blurRadius: isSelected ? 12 : 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Center(
                      child: AnimatedScale(
                        scale: isSelected ? 1.08 : 1,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.how_to_reg_rounded
                                  : Icons.how_to_reg_outlined,
                              size: 22,
                              color: const Color(0xFF0F172A),
                            ),
                            Positioned(
                              top: 2,
                              right: 1,
                              child: Container(
                                padding: const EdgeInsets.all(1),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0F172A),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.add,
                                  size: 7,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF64748B),
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
