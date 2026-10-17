import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/hotel_store.dart';
import '../models/room.dart';
import '../models/stay.dart';
import '../models/bill.dart';
import '../theme/app_theme.dart';
import 'check_in_screen.dart';
import 'booking_checkout_screen.dart';
import 'room_detail_screen.dart';
import '../widgets/airbnb_date_picker_sheet.dart';

enum TimelineViewMode { weekly, threeDays, today }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  TimelineViewMode _viewMode = TimelineViewMode.weekly;
  late DateTime _startDate;
  String _selectedCategory = 'All';
  final ScrollController _horizontalTimelineController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Start at beginning of current week (Monday)
    final diff = now.weekday - DateTime.monday;
    _startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: diff));
  }

  @override
  void dispose() {
    _horizontalTimelineController.dispose();
    super.dispose();
  }

  int get _daysCount {
    switch (_viewMode) {
      case TimelineViewMode.weekly:
        return 7;
      case TimelineViewMode.threeDays:
        return 3;
      case TimelineViewMode.today:
        return 1;
    }
  }

  List<DateTime> get _visibleDates {
    return List.generate(_daysCount, (index) => _startDate.add(Duration(days: index)));
  }

  void _previousPeriod() {
    setState(() {
      _startDate = _startDate.subtract(Duration(days: _daysCount));
    });
  }

  void _nextPeriod() {
    setState(() {
      _startDate = _startDate.add(Duration(days: _daysCount));
    });
  }

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      if (_viewMode == TimelineViewMode.weekly) {
        final diff = now.weekday - DateTime.monday;
        _startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: diff));
      } else {
        _startDate = DateTime(now.year, now.month, now.day);
      }
    });
  }

  Future<void> _pickCustomDate() async {
    final picked = await AirbnbDatePickerSheet.showSingleDate(
      context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      title: 'Jump to Timeline Date',
    );
    if (picked != null) {
      setState(() {
        if (_viewMode == TimelineViewMode.weekly) {
          final diff = picked.weekday - DateTime.monday;
          _startDate = DateTime(picked.year, picked.month, picked.day).subtract(Duration(days: diff));
        } else {
          _startDate = DateTime(picked.year, picked.month, picked.day);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final rooms = store.rooms.where((r) {
      if (_selectedCategory == 'All') return true;
      return r.categoryName == _selectedCategory;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.slateDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Dynamic Room Timeline',
          style: GoogleFonts.outfit(
            color: AppTheme.slateDark,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_rounded, color: AppTheme.brandPrimary),
            tooltip: 'Jump to Today',
            onPressed: _jumpToToday,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined, color: AppTheme.slateMuted),
            tooltip: 'Pick Date',
            onPressed: _pickCustomDate,
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppTheme.slateBorder, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),

            // ── REPLACED TOP 4 ACTION PILLS (Matching user specifications) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTopActionPills(context, store),
            ),

            const SizedBox(height: 20),

            // ── DYNAMIC TIMELINE SECTION HEADER ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Dynamic Timeline',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildViewModeToggle(),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── DATE NAVIGATOR STRIP ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildDateNavigator(),
            ),

            const SizedBox(height: 12),

            // ── CATEGORY FILTER CHIPS ──
            _buildCategoryFilterChips(),

            const SizedBox(height: 14),

            // ── TIMELINE MATRIX (Accurately Scaled According to Time) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _buildTimelineMatrix(rooms, store),
            ),

            const SizedBox(height: 16),

            // ── TIMELINE LEGEND & STATS ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildLegendAndStats(store),
            ),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  // ── 1. The 4 Requested Options (Availability, Today's Activity, Upcoming Stays, Date Insights) ──
  Widget _buildTopActionPills(BuildContext context, HotelStore store) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildGridCard(
                label: 'Availability',
                subtitle: 'Calendar & stays',
                icon: Icons.event_available_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
                onTap: () => _showAvailabilityDialog(context, store),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGridCard(
                label: "Today's Activity",
                subtitle: '${store.arrivalsToday} in • ${store.departuresToday} out',
                icon: Icons.departure_board_rounded,
                iconColor: const Color(0xFF0284C7),
                iconBg: const Color(0xFFF0F9FF),
                badgeText: (store.arrivalsToday + store.departuresToday) > 0
                    ? '${store.arrivalsToday + store.departuresToday}'
                    : null,
                badgeBg: const Color(0xFF0284C7),
                onTap: () => _showTodaysActivitySheet(context, store),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildGridCard(
                label: 'Upcoming Stays',
                subtitle: '${store.upcomingStays.length} upcoming',
                icon: Icons.upcoming_rounded,
                iconColor: AppTheme.brandPrimary,
                iconBg: AppTheme.brandLight,
                badgeText: store.upcomingStays.isNotEmpty ? '${store.upcomingStays.length}' : null,
                badgeBg: AppTheme.brandPrimary,
                onTap: () => _showUpcomingStaysSheet(context, store),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGridCard(
                label: 'Date Insights',
                subtitle: '${store.occupancyRate}% occupancy',
                icon: Icons.analytics_rounded,
                iconColor: const Color(0xFF059669),
                iconBg: const Color(0xFFECFDF5),
                badgeText: '${store.occupancyRate}%',
                badgeBg: const Color(0xFF059669),
                onTap: () => _showDateInsightsDialog(context, store),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGridCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    String? badgeText,
    Color? badgeBg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.slateBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 8,
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
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                ),
                if (badgeText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: (badgeBg ?? iconColor).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeText,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: badgeBg ?? iconColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.slateDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
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

  // ── 2. View Mode Toggle (Weekly / 3 Days / Today) ──
  Widget _buildViewModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleItem('Weekly', TimelineViewMode.weekly),
          _buildToggleItem('3 Days', TimelineViewMode.threeDays),
          _buildToggleItem('Today', TimelineViewMode.today),
        ],
      ),
    );
  }

  Widget _buildToggleItem(String label, TimelineViewMode mode) {
    final isSelected = _viewMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _viewMode = mode;
          if (mode == TimelineViewMode.today) {
            final now = DateTime.now();
            _startDate = DateTime(now.year, now.month, now.day);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppTheme.slateDark : AppTheme.slateMuted,
          ),
        ),
      ),
    );
  }

  // ── 3. Date Navigator ──
  Widget _buildDateNavigator() {
    final dates = _visibleDates;
    final formatter = DateFormat('d MMM');
    final rangeText = dates.length == 1
        ? DateFormat('EEEE, d MMMM yyyy').format(dates.first)
        : '${formatter.format(dates.first)} – ${formatter.format(dates.last)}, ${dates.first.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.slateDark),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _previousPeriod,
          ),
          Expanded(
            child: InkWell(
              onTap: _pickCustomDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.brandPrimary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        rangeText,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.slateDark),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _nextPeriod,
          ),
        ],
      ),
    );
  }

  // ── 4. Category Filter Chips ──
  Widget _buildCategoryFilterChips() {
    final categories = ['All', 'Standard Room', 'Deluxe Room', 'Executive Suite'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _selectedCategory = cat),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.slateDark : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppTheme.slateDark : AppTheme.slateBorder,
                  ),
                ),
                child: Text(
                  cat,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : AppTheme.slateDark,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 5. Timeline Matrix with Accurately Time-Scaled Capsules ──
  Widget _buildTimelineMatrix(List<Room> rooms, HotelStore store) {
    final dates = _visibleDates;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Calculate column width depending on view mode
    final double colWidth = _viewMode == TimelineViewMode.weekly
        ? 88.0
        : (_viewMode == TimelineViewMode.threeDays ? 120.0 : 280.0);
    const double roomColWidth = 72.0;
    const double rowHeight = 64.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.slateBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fixed Left Column: "Room" Header + Room Label Cells ──
            Container(
              width: roomColWidth,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppTheme.slateBorder)),
              ),
              child: Column(
                children: [
                  // Top-left "Room" header
                  Container(
                    width: roomColWidth,
                    height: 52,
                    padding: const EdgeInsets.all(8),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(bottom: BorderSide(color: AppTheme.slateBorder)),
                    ),
                    child: Text(
                      'Room',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ),
                  // Room cells
                  ...rooms.map((room) => _buildRoomCell(room, roomColWidth, rowHeight)),
                ],
              ),
            ),

            // ── Synchronized Horizontally Scrollable Grid: Date Headers + ALL Room Timeline Rows ──
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _horizontalTimelineController,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: colWidth * dates.length,
                  child: Column(
                    children: [
                      // Date Headers Row
                      Row(
                        children: dates.map((d) {
                          final isToday = d.year == today.year && d.month == today.month && d.day == today.day;
                          return Container(
                            width: colWidth,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isToday ? const Color(0xFFF5F3FF) : const Color(0xFFF8FAFC),
                              border: const Border(
                                bottom: BorderSide(color: AppTheme.slateBorder),
                                right: BorderSide(color: Color(0xFFF1F5F9)),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat('E').format(d), // Thu, Fri...
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isToday ? AppTheme.brandPrimary : AppTheme.slateMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isToday ? AppTheme.brandPrimary : Colors.transparent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      DateFormat('d').format(d), // 15, 16...
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isToday ? Colors.white : AppTheme.slateDark,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),

                      // Room Timeline Rows (synchronized in this single horizontal scroll view!)
                      ...rooms.map((room) {
                        return _buildRoomTimelineRow(room, dates, colWidth, rowHeight, store);
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCell(Room room, double roomColWidth, double rowHeight) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
        );
      },
      child: Container(
        width: roomColWidth,
        height: rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  room.roomNumber,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.slateDark,
                  ),
                ),
                const Spacer(),
                _buildRoomStatusDot(room.status),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Fl ${room.floor} • ${room.categoryName.replaceAll(" Room", "").replaceAll(" Suite", " St")}',
              style: GoogleFonts.inter(
                fontSize: 8,
                color: AppTheme.slateMuted,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomTimelineRow(
    Room room,
    List<DateTime> dates,
    double colWidth,
    double rowHeight,
    HotelStore store,
  ) {
    final roomStays = store.stays.where((s) {
      if (s.roomId != room.id) return false;
      if (s.status == StayStatus.checkedOut) return false;
      return true;
    }).toList();

    return Container(
      width: colWidth * dates.length,
      height: rowHeight,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Stack(
        children: [
          // Background grid slots
          Row(
            children: dates.map((d) {
              return GestureDetector(
                onTap: () => _handleEmptySlotTap(room, d, store),
                child: Container(
                  width: colWidth,
                  height: rowHeight,
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0xFFF8FAFC))),
                  ),
                ),
              );
            }).toList(),
          ),

          // Active & Reserved Stay Capsules - Accurately Scaled by Time
          ...roomStays.map((stay) {
            return _buildTimeScaledStayPill(room, stay, dates, colWidth, rowHeight, store);
          }),
        ],
      ),
    );
  }

  Widget _buildRoomStatusDot(RoomStatus status) {
    Color dotColor;
    switch (status) {
      case RoomStatus.occupied:
        dotColor = AppTheme.statusOccupied;
        break;
      case RoomStatus.needsCleaning:
        dotColor = AppTheme.statusCleaning;
        break;
      case RoomStatus.reserved:
        dotColor = AppTheme.statusReserved;
        break;
      default:
        dotColor = AppTheme.statusVacant;
    }
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
    );
  }

  // ── 6. TIME-SCALED BOOKING CAPSULE (Matching Image 2: [👤 2 Ethan Harper]) ──
  Widget _buildTimeScaledStayPill(
    Room room,
    Stay stay,
    List<DateTime> visibleDates,
    double colWidth,
    double rowHeight,
    HotelStore store,
  ) {
    final timelineStart = DateTime(visibleDates.first.year, visibleDates.first.month, visibleDates.first.day, 0, 0);
    final timelineEnd = DateTime(visibleDates.last.year, visibleDates.last.month, visibleDates.last.day, 23, 59, 59);

    final checkIn = stay.checkInAt;
    final checkOut = stay.checkOutAt ?? stay.expectedCheckOut;

    // Outside visible range?
    if (checkOut.isBefore(timelineStart) || checkIn.isAfter(timelineEnd)) {
      return const SizedBox.shrink();
    }

    // Mathematical time scaling:
    // Fraction of minutes from start of timeline / 1440.0 minutes per day * colWidth
    final double inMinutes = checkIn.difference(timelineStart).inMinutes.toDouble();
    final double outMinutes = checkOut.difference(timelineStart).inMinutes.toDouble();

    final double startDayFraction = (inMinutes / 1440.0).clamp(0.0, visibleDates.length.toDouble());
    final double endDayFraction = (outMinutes / 1440.0).clamp(0.0, visibleDates.length.toDouble());

    final double totalTimelineWidth = visibleDates.length * colWidth;
    final double leftOffset = (startDayFraction * colWidth + 2.0).clamp(0.0, totalTimelineWidth);
    final double rightOffset = (endDayFraction * colWidth - 2.0).clamp(leftOffset, totalTimelineWidth);
    final double maxAvailableWidth = (totalTimelineWidth - leftOffset).clamp(0.0, totalTimelineWidth);
    final double rawWidth = (rightOffset - leftOffset);
    final double pillWidth = maxAvailableWidth <= 0.0
        ? 0.0
        : (maxAvailableWidth < 42.0 ? maxAvailableWidth : rawWidth.clamp(42.0, maxAvailableWidth));

    // Color theme matching image 2: Emerald Green (#16A34A / #22C55E) for occupied
    Color pillColor;
    if (stay.status == StayStatus.reserved) {
      pillColor = const Color(0xFFF59E0B); // Amber for reserved
    } else if (room.categoryName.contains('Suite')) {
      pillColor = const Color(0xFF0066CC); // Apple Action Blue for suite
    } else {
      pillColor = const Color(0xFF22C55E); // Green matching inspiration image 2
    }

    return Positioned(
      left: leftOffset,
      top: 13,
      width: pillWidth,
      height: 38,
      child: GestureDetector(
        onTap: () => _showStayDetailsSheet(context, stay, room),
        child: Container(
          decoration: BoxDecoration(
            color: pillColor,
            borderRadius: BorderRadius.circular(22), // Circular capsule matching image 2
            boxShadow: [
              BoxShadow(
                color: pillColor.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(
                stay.status == StayStatus.reserved ? Icons.event_available_rounded : Icons.person_rounded,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                '${stay.numGuests}',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (pillWidth > 80 && stay.guest != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    stay.status == StayStatus.reserved ? 'RES: ${stay.guest!.fullName}' : stay.guest!.fullName,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── 7. Stay Details Bottom Sheet with Detailed Timestamps ──
  void _showStayDetailsSheet(BuildContext context, Stay stay, Room room) {
    final store = Provider.of<HotelStore>(context, listen: false);
    Bill? bill;
    try {
      bill = store.bills.firstWhere((b) => b.stayId == stay.id);
    } catch (_) {}

    final nights = stay.actualNights;
    final roomTotal = nights * stay.nightlyRate;
    final advance = bill?.amountPaid ?? 0.0;
    final balance = (roomTotal - advance).clamp(0.0, roomTotal);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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

            // Top Guest Header
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.brandLight,
                  child: Text(
                    (stay.guest?.fullName ?? 'G').substring(0, 1),
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.brandPrimary,
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
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      Text(
                        'Room ${room.roomNumber} • ${room.categoryName}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.brandPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: stay.status == StayStatus.reserved ? AppTheme.statusReservedBg : AppTheme.statusOccupiedBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    stay.status == StayStatus.reserved ? 'Reserved' : 'Occupied',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: stay.status == StayStatus.reserved ? AppTheme.statusReserved : AppTheme.statusOccupied,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(color: AppTheme.slateBorder),
            const SizedBox(height: 8),

            // Booking Details Grid with Exact Timestamps
            _detailRow(Icons.login_rounded, 'Check-In', DateFormat('d MMM yyyy, hh:mm a').format(stay.checkInAt)),
            const SizedBox(height: 8),
            _detailRow(Icons.logout_rounded, 'Check-Out', DateFormat('d MMM yyyy, hh:mm a').format(stay.expectedCheckOut)),
            const SizedBox(height: 8),
            _detailRow(Icons.dark_mode_rounded, 'Duration', '$nights night${nights > 1 ? "s" : ""}'),
            const SizedBox(height: 8),
            _detailRow(Icons.people_rounded, 'Occupants', stay.guestSummary),
            if (stay.coGuests.isNotEmpty) ...[
              const SizedBox(height: 8),
              _detailRow(Icons.group_rounded, 'Co-Guests', stay.coGuests.map((g) => g.fullName).join(", ")),
            ],
            const SizedBox(height: 8),
            _detailRow(Icons.phone_rounded, 'Contact', stay.guest?.phone ?? 'Not provided'),
            const SizedBox(height: 8),
            _detailRow(Icons.payments_rounded, 'Billing',
                '₹${roomTotal.toInt()} (Paid: ₹${advance.toInt()}, Due: ₹${balance.toInt()})'),

            const SizedBox(height: 20),

            // Quick Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
                      );
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    label: const Text('Edit Room'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppTheme.slateBorder),
                      foregroundColor: AppTheme.slateDark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: stay.status == StayStatus.reserved
                      ? ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            store.checkInReservedStay(stay.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${stay.guest?.fullName ?? "Guest"} checked in to Room ${room.roomNumber}!'),
                                backgroundColor: AppTheme.slateDark,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                          label: const Text('Check-In Guest'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: AppTheme.brandPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => BookingCheckOutScreen(stay: stay)),
                            );
                          },
                          icon: const Icon(Icons.receipt_long_rounded, size: 16),
                          label: const Text('Check-Out'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: AppTheme.brandPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppTheme.slateMuted),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted)),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
          ),
        ),
      ],
    );
  }

  // ── 8. Empty Slot Tap (Quick Booking / Check-In) ──
  void _handleEmptySlotTap(Room room, DateTime date, HotelStore store) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.slateBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Room ${room.roomNumber} — ${DateFormat('EEE, d MMM yyyy').format(date)}',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
            ),
            const SizedBox(height: 4),
            Text(
              '${room.categoryName} • ₹${room.baseRate.toInt()}/night • Floor ${room.floor}',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
            ),
            const SizedBox(height: 18),
            if (DateTime(date.year, date.month, date.day).isAfter(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))) ...[
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CheckInScreen(
                        preselectedRoomId: room.id,
                        initialMode: BookingMode.reservation,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.event_available_rounded, size: 18),
                label: Text('Reserve Room for ${DateFormat('d MMM').format(date)}'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppTheme.brandPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CheckInScreen(
                              preselectedRoomId: room.id,
                              initialMode: BookingMode.checkIn,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                      label: const Text('Check-In Now'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        backgroundColor: AppTheme.brandPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CheckInScreen(
                              preselectedRoomId: room.id,
                              initialMode: BookingMode.reservation,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.event_available_rounded, size: 16),
                      label: const Text('Reserve'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: AppTheme.slateBorder),
                        foregroundColor: AppTheme.slateDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
                );
              },
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('View / Edit Room Details'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppTheme.slateBorder),
                foregroundColor: AppTheme.slateDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── OPTION 1: AVAILABILITY SCREEN (Week, Month, Year & Color-coded dates) ──
  void _showAvailabilityDialog(BuildContext context, HotelStore store) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AvailabilityCalendarSheet(store: store),
    );
  }

  // ── OPTION 2: TODAY'S ACTIVITY SCREEN (Direct Arrivals & Departures with Timestamps) ──
  void _showTodaysActivitySheet(BuildContext context, HotelStore store) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TodaysActivitySheet(store: store),
    );
  }

  // ── OPTION 3: UPCOMING STAYS SCREEN (7, 15, 30 Days Anticipation) ──
  void _showUpcomingStaysSheet(BuildContext context, HotelStore store) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UpcomingStaysSheet(store: store),
    );
  }

  // ── OPTION 4: DATE INSIGHTS SCREEN (Dynamic summary for selected date) ──
  void _showDateInsightsDialog(BuildContext context, HotelStore store) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DateInsightsSheet(store: store),
    );
  }

  // ── 10. Legend & Occupancy Summary ──
  Widget _buildLegendAndStats(HotelStore store) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Timeline Legend',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.slateDark,
                ),
              ),
              Flexible(
                child: Text(
                  '${store.occupiedRooms}/${store.totalRooms} Rooms Occupied (${store.occupancyRate}%)',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.brandPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _legendDot(const Color(0xFF22C55E), 'Occupied Stay'),
              _legendDot(const Color(0xFFF59E0B), 'Reserved Stay'),
              _legendDot(AppTheme.brandPrimary, 'Executive Suite'),
              _legendDot(AppTheme.slateBorder, 'Vacant Slot (Tap to book)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppTheme.slateMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. AVAILABILITY CALENDAR SHEET (Week, Month, Year & Color Heatmap)
// ─────────────────────────────────────────────────────────────────────────────
class _AvailabilityCalendarSheet extends StatefulWidget {
  final HotelStore store;
  const _AvailabilityCalendarSheet({required this.store});

  @override
  State<_AvailabilityCalendarSheet> createState() => _AvailabilityCalendarSheetState();
}

class _AvailabilityCalendarSheetState extends State<_AvailabilityCalendarSheet> {
  String _timeScale = 'Month'; // Week, Month, Year
  DateTime _currentMonth = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
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
            const SizedBox(height: 14),

            // Header & Scale Switcher
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Room Availability',
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: ['Week', 'Month', 'Year'].map((scale) {
                      final isSel = _timeScale == scale;
                      return GestureDetector(
                        onTap: () => setState(() => _timeScale = scale),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSel ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: isSel ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)] : null,
                          ),
                          child: Text(
                            scale,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                              color: isSel ? AppTheme.slateDark : AppTheme.slateMuted,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Color indicates room occupancy: Green (vacant), Yellow (partially booked), Red (fully booked)',
              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
            ),
            const SizedBox(height: 12),

            // Color Heatmap Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _heatLegend(const Color(0xFFDCFCE7), const Color(0xFF16A34A), 'No Bookings (0%)'),
                _heatLegend(const Color(0xFFFEF3C7), const Color(0xFFD97706), 'Half Booked (1-74%)'),
                _heatLegend(const Color(0xFFFEE2E2), const Color(0xFFDC2626), 'Fully Booked (≥75%)'),
              ],
            ),
            const SizedBox(height: 16),

            // Month Navigator if Month view
            if (_timeScale == 'Month') ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1)),
                  ),
                  Text(
                    DateFormat('MMMM yyyy').format(_currentMonth),
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildMonthGrid(context),
            ] else if (_timeScale == 'Week') ...[
              _buildWeekAvailabilityList(context),
            ] else ...[
              _buildYearOverview(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _heatLegend(Color bg, Color text, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: bg, border: Border.all(color: text.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 9.5, color: AppTheme.slateDark, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildMonthGrid(BuildContext context) {
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday; // 1 = Mon

    return Column(
      children: [
        // Days of week header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) {
            return SizedBox(
              width: 42,
              child: Center(
                child: Text(d, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slateMuted)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),

        // Grid of dates
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.9,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemBuilder: (ctx, index) {
            final dayNumber = index - (startWeekday - 2);
            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox.shrink();
            }

            final date = DateTime(_currentMonth.year, _currentMonth.month, dayNumber);
            final insights = widget.store.getDateInsights(date);
            final int occPct = insights['occupancyPct'];

            Color bg;
            Color border;
            Color textColor;
            if (occPct == 0) {
              bg = const Color(0xFFDCFCE7); // Light green
              border = const Color(0xFF86EFAC);
              textColor = const Color(0xFF16A34A);
            } else if (occPct < 75) {
              bg = const Color(0xFFFEF3C7); // Light yellow
              border = const Color(0xFFFDE68A);
              textColor = const Color(0xFFD97706);
            } else {
              bg = const Color(0xFFFEE2E2); // Light red
              border = const Color(0xFFFCA5A5);
              textColor = const Color(0xFFDC2626);
            }

            final arrivals = insights['arrivalsCount'] as int;
            final departures = insights['departuresCount'] as int;

            return GestureDetector(
              onTap: () => _showDateActivityDetail(context, date),
              child: Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border),
                ),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$dayNumber',
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                    ),
                    Text(
                      '$occPct%',
                      style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    if (arrivals > 0 || departures > 0)
                      Text(
                        '${arrivals > 0 ? "↓$arrivals " : ""}${departures > 0 ? "↑$departures" : ""}',
                        style: GoogleFonts.inter(fontSize: 7.5, fontWeight: FontWeight.w600, color: AppTheme.slateDark),
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWeekAvailabilityList(BuildContext context) {
    final now = DateTime.now();
    final dates = List.generate(7, (i) => now.add(Duration(days: i)));

    return Column(
      children: dates.map((d) {
        final insights = widget.store.getDateInsights(d);
        final occPct = insights['occupancyPct'] as int;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            onTap: () => _showDateActivityDetail(context, d),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: occPct >= 75 ? const Color(0xFFFEE2E2) : (occPct > 0 ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text('$occPct%', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            title: Text(DateFormat('EEEE, d MMMM').format(d), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text(
              '${insights['occupiedCount']} occupied • ${insights['arrivalsCount']} check-ins • ${insights['departuresCount']} check-outs',
              style: GoogleFonts.inter(fontSize: 11),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildYearOverview(BuildContext context) {
    return Column(
      children: [
        Text('12-Month Availability Heatmap', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 12,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.5, crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemBuilder: (_, i) {
            final month = DateTime(DateTime.now().year, i + 1);
            final monthStays = widget.store.stays.where((s) =>
              (s.checkInAt.year == month.year && s.checkInAt.month == month.month) ||
              (s.expectedCheckOut.year == month.year && s.expectedCheckOut.month == month.month)
            ).length;
            final isCurrentMonth = month.year == DateTime.now().year && month.month == DateTime.now().month;
            return Container(
              decoration: BoxDecoration(
                color: isCurrentMonth ? AppTheme.brandLight.withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isCurrentMonth ? AppTheme.brandPrimary.withValues(alpha: 0.5) : AppTheme.slateBorder),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('MMM').format(month), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    monthStays > 0 ? '$monthStays Stays' : 'Open',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: monthStays > 0 ? AppTheme.brandPrimary : AppTheme.statusVacant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Show Check-Ins and Check-Outs in TWO SEPARATE TABS for that date ──
  void _showDateActivityDetail(BuildContext context, DateTime date) {
    final arrivals = widget.store.getArrivalsForDate(date);
    final departures = widget.store.getDeparturesForDate(date);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: AppTheme.slateBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(date),
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
              ),
              const SizedBox(height: 10),

              // Two Tabs: Check-Ins & Check-Outs
              TabBar(
                labelColor: AppTheme.brandPrimary,
                unselectedLabelColor: AppTheme.slateMuted,
                indicatorColor: AppTheme.brandPrimary,
                tabs: [
                  Tab(text: 'Check-Ins (${arrivals.length})'),
                  Tab(text: 'Check-Outs (${departures.length})'),
                ],
              ),
              const SizedBox(height: 10),

              Expanded(
                child: TabBarView(
                  children: [
                    // Tab 1: Check-Ins
                    arrivals.isEmpty
                        ? Center(child: Text('No check-ins on this date', style: GoogleFonts.inter(color: AppTheme.slateMuted)))
                        : ListView.separated(
                            itemCount: arrivals.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final stay = arrivals[i];
                              return Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.statusVacantBg,
                                    child: const Icon(Icons.login_rounded, color: AppTheme.statusVacant),
                                  ),
                                  title: Text(stay.guest?.fullName ?? 'Guest', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                    'Room ${stay.room?.roomNumber} • In: ${DateFormat('d MMM, hh:mm a').format(stay.checkInAt)}',
                                    style: GoogleFonts.inter(fontSize: 11),
                                  ),
                                  trailing: Text('${stay.numGuests} guests', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              );
                            },
                          ),

                    // Tab 2: Check-Outs
                    departures.isEmpty
                        ? Center(child: Text('No check-outs on this date', style: GoogleFonts.inter(color: AppTheme.slateMuted)))
                        : ListView.separated(
                            itemCount: departures.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final stay = departures[i];
                              return Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.statusOccupiedBg,
                                    child: const Icon(Icons.logout_rounded, color: AppTheme.statusOccupied),
                                  ),
                                  title: Text(stay.guest?.fullName ?? 'Guest', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                    'Room ${stay.room?.roomNumber} • Out: ${DateFormat('d MMM, hh:mm a').format(stay.expectedCheckOut)}',
                                    style: GoogleFonts.inter(fontSize: 11),
                                  ),
                                  trailing: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      backgroundColor: AppTheme.brandPrimary,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => BookingCheckOutScreen(stay: stay)),
                                      );
                                    },
                                    child: const Text('Checkout', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              );
                            },
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
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. TODAY'S ACTIVITY SHEET (Direct Arrivals & Departures with Full Timestamps)
// ─────────────────────────────────────────────────────────────────────────────
class _TodaysActivitySheet extends StatelessWidget {
  final HotelStore store;
  const _TodaysActivitySheet({required this.store});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final arrivals = store.getArrivalsForDate(now);
    final departures = store.getDeparturesForDate(now);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
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
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Today's Activity",
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppTheme.brandLight, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    DateFormat('d MMM yyyy').format(now),
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${arrivals.length} Arrival${arrivals.length != 1 ? "s" : ""} • ${departures.length} Departure${departures.length != 1 ? "s" : ""} scheduled for today',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
            ),
            const SizedBox(height: 18),

            // ── Section 1: Today's Arrivals ──
            Text('Arrivals / Check-Ins', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slateDark)),
            const SizedBox(height: 8),
            if (arrivals.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text('No check-ins today', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted))),
              )
            else
              ...arrivals.map((stay) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFDCFCE7),
                      child: Icon(Icons.login_rounded, color: Color(0xFF16A34A)),
                    ),
                    title: Text(stay.guest?.fullName ?? 'Guest', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Room ${stay.room?.roomNumber} • Arrival: ${DateFormat('d MMM yyyy, hh:mm a').format(stay.checkInAt)}',
                      style: GoogleFonts.inter(fontSize: 11),
                    ),
                    trailing: Text(stay.status == StayStatus.active ? 'Checked In' : 'Expected',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary)),
                  ),
                );
              }),

            const SizedBox(height: 18),

            // ── Section 2: Today's Departures ──
            Text('Departures / Check-Outs', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slateDark)),
            const SizedBox(height: 8),
            if (departures.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text('No departures today', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted))),
              )
            else
              ...departures.map((stay) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFEE2E2),
                      child: Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
                    ),
                    title: Text(stay.guest?.fullName ?? 'Guest', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Room ${stay.room?.roomNumber} • Departure: ${DateFormat('d MMM yyyy, hh:mm a').format(stay.expectedCheckOut)}',
                      style: GoogleFonts.inter(fontSize: 11),
                    ),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        backgroundColor: AppTheme.brandPrimary,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => BookingCheckOutScreen(stay: stay)),
                        );
                      },
                      child: const Text('Checkout', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. UPCOMING STAYS SHEET (7, 15, 30 Days Anticipation)
// ─────────────────────────────────────────────────────────────────────────────
class _UpcomingStaysSheet extends StatefulWidget {
  final HotelStore store;
  const _UpcomingStaysSheet({required this.store});

  @override
  State<_UpcomingStaysSheet> createState() => _UpcomingStaysSheetState();
}

class _UpcomingStaysSheetState extends State<_UpcomingStaysSheet> {
  int _rangeDays = 7; // 7, 15, 30

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: _rangeDays));

    final upcoming = widget.store.upcomingStays.where((s) {
      return s.checkInAt.isBefore(cutoff);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
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
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Upcoming Stays',
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                ),
                Container(
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [7, 15, 30].map((days) {
                      final isSel = _rangeDays == days;
                      return GestureDetector(
                        onTap: () => setState(() => _rangeDays = days),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSel ? AppTheme.brandPrimary : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$days d',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                              color: isSel ? Colors.white : AppTheme.slateDark,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Bookings arriving over the next $_rangeDays days (ordered by arrival date)',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
            ),
            const SizedBox(height: 16),

            if (upcoming.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text('No upcoming stays scheduled for the next $_rangeDays days', style: GoogleFonts.inter(color: AppTheme.slateMuted)),
                ),
              )
            else
              ...upcoming.map((stay) {
                final daysUntil = stay.checkInAt.difference(now).inDays;
                final tag = daysUntil <= 0
                    ? 'Arriving Today'
                    : (daysUntil == 1 ? 'Tomorrow' : 'In $daysUntil days');

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppTheme.slateBorder),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(stay.guest?.fullName ?? 'Guest', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.brandLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(tag, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Room ${stay.room?.roomNumber} (${stay.room?.categoryName}) • ${stay.actualNights} nights',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Check-In', style: GoogleFonts.inter(fontSize: 9, color: AppTheme.slateMuted)),
                                  Text(
                                    DateFormat('d MMM yyyy, hh:mm a').format(stay.checkInAt),
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const Icon(Icons.arrow_forward_rounded, size: 14, color: AppTheme.slateMuted),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Check-Out', style: GoogleFonts.inter(fontSize: 9, color: AppTheme.slateMuted)),
                                  Text(
                                    DateFormat('d MMM yyyy, hh:mm a').format(stay.expectedCheckOut),
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. DATE INSIGHTS SHEET (Dynamic Summary for Manager-Selected Date)
// ─────────────────────────────────────────────────────────────────────────────
class _DateInsightsSheet extends StatefulWidget {
  final HotelStore store;
  const _DateInsightsSheet({required this.store});

  @override
  State<_DateInsightsSheet> createState() => _DateInsightsSheetState();
}

class _DateInsightsSheetState extends State<_DateInsightsSheet> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final insights = widget.store.getDateInsights(_selectedDate);
    final occPct = insights['occupancyPct'] as int;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
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
            const SizedBox(height: 14),
            Text(
              'Date Insights',
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
            ),
            const SizedBox(height: 4),
            Text(
              'Live schedule summary for selected date. Updates dynamically as date changes.',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
            ),
            const SizedBox(height: 14),

            // Date Selector Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.slateBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: () => setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1))),
                  ),
                  InkWell(
                    onTap: () async {
                      final picked = await AirbnbDatePickerSheet.showSingleDate(
                        context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        title: 'Date Insights Calendar',
                      );
                      if (picked != null) setState(() => _selectedDate = picked);
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.brandPrimary),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('EEEE, d MMMM yyyy').format(_selectedDate),
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: () => setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1))),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Expected Occupancy Progress
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.slateBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Expected Occupancy Rate', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      Text('$occPct%', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: occPct / 100.0,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: AlwaysStoppedAnimation(occPct >= 75 ? Colors.redAccent : (occPct > 0 ? AppTheme.brandPrimary : Colors.green)),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 4 Insight Metrics Grid
            Row(
              children: [
                Expanded(
                  child: _kpiTile('Occupied Rooms', '${insights['occupiedCount']}', Icons.hotel_rounded, AppTheme.statusOccupied),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _kpiTile('Vacant Rooms', '${insights['vacantCount']}', Icons.check_circle_outline_rounded, AppTheme.statusVacant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _kpiTile('Arrivals (Check-Ins)', '${insights['arrivalsCount']}', Icons.login_rounded, const Color(0xFF2563EB)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _kpiTile('Departures (Check-Outs)', '${insights['departuresCount']}', Icons.logout_rounded, const Color(0xFFD97706)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiTile(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.slateBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.slateMuted, fontWeight: FontWeight.w600)),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(val, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.slateDark)),
        ],
      ),
    );
  }
}
