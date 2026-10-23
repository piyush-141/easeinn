import 'dart:math' as math;
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _currentIndex;
  String? _preselectedRoomId;
  BookingMode _initialBookingMode = BookingMode.checkIn;
  bool _redirectedFromRooms = false;
  DateTime? _lastHomeBackPress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final store = context.read<HotelStore>();
        store.startAutoSync();
        store.syncData(isBackground: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final store = context.read<HotelStore>();
      store.startAutoSync();
      store.syncData(isBackground: true);
    }
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
        body: _SmoothScreenSwitcher(
          currentIndex: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: _buildGlassNavigationBar(store),
      ),
    );
  }

  int get _selectedNavigationSlot => switch (_currentIndex) {
    0 => 0, // Home
    1 => 1, // Rooms
    3 => 2, // Check-Out
    4 => 3, // Guests
    _ => 0,
  };

  Widget _buildGlassNavigationBar(HotelStore store) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return AnimatedSlide(
      offset: keyboardVisible ? const Offset(0, 1.8) : Offset.zero,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            math.max(8, MediaQuery.of(context).padding.bottom),
          ),
          child: Row(
            children: [
              Expanded(child: _buildPrimaryGlassPill(store, isDark)),
              const SizedBox(width: 10),
              _buildCheckInActionButton(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryGlassPill(HotelStore store, bool isDark) {
    const itemCount = 4;
    final baseGlassColor = isDark
        ? const Color(0xFF1E2430).withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.82);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / itemCount;
        return Container(
          height: 64,
          decoration: BoxDecoration(
            color: baseGlassColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: borderColor, width: isDark ? 0.8 : 1.2),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.35)
                    : const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
              if (!isDark)
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.88),
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Stack(
                children: [
                  // Top specular sheen highlight
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: isDark ? 0.12 : 0.45),
                            Colors.white.withValues(alpha: isDark ? 0.02 : 0.08),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Fluid spring sliding indicator with directional stretch
                  _FluidGlassIndicator(
                    selectedSlot: _selectedNavigationSlot,
                    itemWidth: itemWidth,
                    isVisible: _currentIndex != 2,
                  ),

                  // 4 Primary Navigation Destinations with Icon + Text below
                  Row(
                    children: [
                      _buildPillTabItem(
                        index: 0,
                        activeIcon: Icons.home_rounded,
                        inactiveIcon: Icons.home_outlined,
                        label: 'Home',
                        isDark: isDark,
                      ),
                      _buildPillTabItem(
                        index: 1,
                        activeIcon: Icons.bed_rounded,
                        inactiveIcon: Icons.bed_outlined,
                        label: 'Rooms',
                        badgeCount: store.cleaningRooms > 0
                            ? store.cleaningRooms
                            : null,
                        badgeColor: AppTheme.statusCleaning,
                        isDark: isDark,
                      ),
                      _buildPillTabItem(
                        index: 3,
                        activeIcon: Icons.logout_rounded,
                        inactiveIcon: Icons.logout_rounded,
                        label: 'Check-Out',
                        badgeCount: store.occupiedRooms > 0
                            ? store.occupiedRooms
                            : null,
                        badgeColor: isDark ? AppTheme.brandAccent : const Color(0xFF0284C7),
                        isDark: isDark,
                      ),
                      _buildPillTabItem(
                        index: 4,
                        activeIcon: Icons.people_rounded,
                        inactiveIcon: Icons.people_outline_rounded,
                        label: 'Guests',
                        isDark: isDark,
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
    required IconData activeIcon,
    required IconData inactiveIcon,
    required String label,
    required bool isDark,
    int? badgeCount,
    Color? badgeColor,
  }) {
    final isSelected = _currentIndex == index;
    final inactiveColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF475569);
    final iconColor = isSelected ? Colors.white : inactiveColor;

    return Expanded(
      child: _PressableGlassItem(
        tooltip: label,
        onTap: () => _onTabSelected(index),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  _BouncingTabIcon(
                    isSelected: isSelected,
                    child: TweenAnimationBuilder<Color?>(
                      duration: const Duration(milliseconds: 200),
                      tween: ColorTween(end: iconColor),
                      builder: (context, color, _) {
                        return Icon(
                          isSelected ? activeIcon : inactiveIcon,
                          size: 21,
                          color: color,
                        );
                      },
                    ),
                  ),
                  if (badgeCount != null && badgeCount > 0)
                    Positioned(
                      top: -2,
                      right: -5,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: badgeColor ?? AppTheme.statusCleaning,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (badgeColor ?? AppTheme.statusCleaning)
                                  .withValues(alpha: 0.6),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : inactiveColor,
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
    );
  }

  Widget _buildCheckInActionButton(bool isDark) {
    final isSelected = _currentIndex == 2;
    final baseGlassColor = isDark
        ? const Color(0xFF1E2430).withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.82);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.white;

    return _PressableGlassItem(
      tooltip: 'Check-In',
      onTap: () => _onTabSelected(2),
      child: SizedBox(
        width: 62,
        height: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected ? null : baseGlassColor,
                shape: BoxShape.circle,
                gradient: isSelected
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.brandAccent,
                          AppTheme.brandPrimary,
                        ],
                      )
                    : null,
                border: Border.all(
                  color: isSelected ? Colors.white : borderColor,
                  width: isDark ? 0.8 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? AppTheme.brandPrimary.withValues(alpha: 0.40)
                        : (isDark
                            ? Colors.black.withValues(alpha: 0.35)
                            : const Color(0xFF0F172A).withValues(alpha: 0.08)),
                    blurRadius: isSelected ? 12 : 16,
                    offset: const Offset(0, 4),
                  ),
                  if (!isDark && !isSelected)
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.88),
                      blurRadius: 3,
                      offset: const Offset(0, -1),
                    ),
                ],
              ),
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Center(
                    child: _BouncingTabIcon(
                      isSelected: isSelected,
                      child: _SfCheckInIcon(
                        isSelected: isSelected,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF334155)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? AppTheme.brandPrimary
                    : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF475569)),
                letterSpacing: -0.2,
              ),
              child: const Text(
                'Check-In',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fluid, spring-based sliding tab indicator that subtly stretches along the travel direction
class _FluidGlassIndicator extends StatefulWidget {
  final int selectedSlot;
  final double itemWidth;
  final bool isVisible;

  const _FluidGlassIndicator({
    required this.selectedSlot,
    required this.itemWidth,
    required this.isVisible,
  });

  @override
  State<_FluidGlassIndicator> createState() => _FluidGlassIndicatorState();
}

class _FluidGlassIndicatorState extends State<_FluidGlassIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _headCurve;
  late final CurvedAnimation _tailCurve;

  double _fromSlot = 0.0;
  double _toSlot = 0.0;

  @override
  void initState() {
    super.initState();
    _fromSlot = widget.selectedSlot.toDouble();
    _toSlot = widget.selectedSlot.toDouble();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    // Leading edge accelerates rapidly
    _headCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.82, curve: Curves.easeOutCubic),
    );

    // Trailing edge lags slightly and finishes with an elastic spring overshoot
    _tailCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.10, 1.0, curve: Curves.easeOutBack),
    );

    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _FluidGlassIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSlot != oldWidget.selectedSlot) {
      _fromSlot = _calculateCurrentVisualSlot();
      _toSlot = widget.selectedSlot.toDouble();
      _controller.forward(from: 0.0);
    }
  }

  double _calculateCurrentVisualSlot() {
    if (_controller.isCompleted) return _toSlot;
    final tailVal = _tailCurve.value;
    return _fromSlot + (_toSlot - _fromSlot) * tailVal;
  }

  @override
  void dispose() {
    _headCurve.dispose();
    _tailCurve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double dist = _toSlot - _fromSlot;
        final double targetW = widget.itemWidth - 8;
        final double startLeft = _fromSlot * widget.itemWidth + 4;
        final double endLeft = _toSlot * widget.itemWidth + 4;

        double left;
        double width;

        if (dist.abs() < 0.001) {
          left = _toSlot * widget.itemWidth + 4;
          width = targetW;
        } else if (dist > 0) {
          // Navigating to the RIGHT:
          // Right edge (leading) moves first, left edge (trailing) follows with spring
          final double headVal = _headCurve.value;
          final double tailVal = _tailCurve.value;
          final double delta = endLeft - startLeft;

          // Subtle fluid stretch along travel direction (clamped to max 32% stretch)
          final double stretch =
              ((headVal - tailVal) * delta).clamp(0.0, targetW * 0.32);

          left = startLeft + delta * tailVal;
          width = targetW + stretch;
        } else {
          // Navigating to the LEFT:
          // Left edge (leading) moves first, right edge (trailing) follows with spring
          final double headVal = _headCurve.value;
          final double tailVal = _tailCurve.value;
          final double delta = startLeft - endLeft;

          final double stretch =
              ((headVal - tailVal) * delta).clamp(0.0, targetW * 0.32);

          // Right edge position
          final double rightEdge =
              (startLeft + targetW) + (endLeft - startLeft) * tailVal;
          width = targetW + stretch;
          left = rightEdge - width;
        }

        return Positioned(
          left: left,
          top: 4,
          bottom: 4,
          width: width,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: widget.isVisible ? 1.0 : 0.0,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.brandAccent,
                    AppTheme.brandPrimary,
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Subtle 200–300ms fade-and-slide screen transition while preserving routes & state
class _SmoothScreenSwitcher extends StatefulWidget {
  final int currentIndex;
  final List<Widget> children;

  const _SmoothScreenSwitcher({
    required this.currentIndex,
    required this.children,
  });

  @override
  State<_SmoothScreenSwitcher> createState() => _SmoothScreenSwitcherState();
}

class _SmoothScreenSwitcherState extends State<_SmoothScreenSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.015),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _SmoothScreenSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: IndexedStack(
          index: widget.currentIndex,
          children: widget.children,
        ),
      ),
    );
  }
}

/// Spring bounce animation: selected icon scales 1.0 → 1.15 → 1.0 on tab selection
class _BouncingTabIcon extends StatefulWidget {
  final bool isSelected;
  final Widget child;

  const _BouncingTabIcon({
    required this.isSelected,
    required this.child,
  });

  @override
  State<_BouncingTabIcon> createState() => _BouncingTabIconState();
}

class _BouncingTabIconState extends State<_BouncingTabIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.15)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.15, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 55,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant _BouncingTabIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}

/// Tactile press feedback: scales down to 0.94 on tap down, springs back to 1.0
class _PressableGlassItem extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  const _PressableGlassItem({
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  @override
  State<_PressableGlassItem> createState() => _PressableGlassItemState();
}

class _PressableGlassItemState extends State<_PressableGlassItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    Widget content = AnimatedScale(
      scale: _isPressed ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutBack,
      child: widget.child,
    );

    if (widget.tooltip != null) {
      content = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: content,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: content,
    );
  }
}

/// SF Symbols-inspired `person.crop.circle.badge.checkmark`
class _SfCheckInIcon extends StatelessWidget {
  final bool isSelected;
  final Color color;

  const _SfCheckInIcon({
    required this.isSelected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            isSelected
                ? Icons.account_circle_rounded
                : Icons.account_circle_outlined,
            size: 24,
            color: color,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : AppTheme.brandPrimary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.brandPrimary : Colors.white,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                Icons.check_rounded,
                size: 8,
                color: isSelected ? AppTheme.brandPrimary : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
