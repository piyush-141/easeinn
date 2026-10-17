import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

enum AirbnbPickerMode { dates, flexible }

class AirbnbDatePickerSheet extends StatefulWidget {
  final DateTime initialCheckIn;
  final DateTime initialCheckOut;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String title;
  final bool isRange;
  final String? roomName;
  final String? guestCountSummary;

  const AirbnbDatePickerSheet({
    super.key,
    required this.initialCheckIn,
    required this.initialCheckOut,
    this.firstDate,
    this.lastDate,
    this.title = 'When will you be staying?',
    this.isRange = true,
    this.roomName,
    this.guestCountSummary,
  });

  /// Static helper to show the Airbnb Date Range Picker bottom sheet
  /// Static helper to show the standard Android / Material Date Range Picker
  static Future<DateTimeRange?> show(
    BuildContext context, {
    required DateTime initialCheckIn,
    required DateTime initialCheckOut,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = 'Select Dates',
    String? roomName,
    String? guestCountSummary,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final minD = firstDate ?? today.subtract(const Duration(days: 365));
    final maxD = lastDate ?? today.add(const Duration(days: 730));

    return showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: initialCheckIn.isBefore(minD) ? minD : initialCheckIn,
        end: initialCheckOut.isAfter(maxD) ? maxD : initialCheckOut,
      ),
      firstDate: minD,
      lastDate: maxD,
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: title,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0066CC),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1D1D1F),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  /// Static helper to pick a single date with standard Android / Material Month view
  static Future<DateTime?> showSingleDate(
    BuildContext context, {
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = 'Select Date',
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final minD = firstDate ?? today.subtract(const Duration(days: 365));
    final maxD = lastDate ?? today.add(const Duration(days: 730));

    return showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(minD) ? minD : (initialDate.isAfter(maxD) ? maxD : initialDate),
      firstDate: minD,
      lastDate: maxD,
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: title,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0066CC),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1D1D1F),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  @override
  State<AirbnbDatePickerSheet> createState() => _AirbnbDatePickerSheetState();
}

class _AirbnbDatePickerSheetState extends State<AirbnbDatePickerSheet>
    with SingleTickerProviderStateMixin {
  AirbnbPickerMode _mode = AirbnbPickerMode.dates;
  late DateTime _checkIn;
  DateTime? _checkOut;
  late PageController _pageController;
  int _flexibilityDays = 0; // 0 = exact, 1 = ±1d, 2 = ±2d, 3 = ±3d, 7 = ±7d, 14 = ±14d
  String _flexibleDuration = 'week'; // 'weekend', 'week', 'month'

  late final DateTime _minDate;
  late final DateTime _maxDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _minDate = widget.firstDate ?? today;
    _maxDate = widget.lastDate ?? today.add(const Duration(days: 730));

    _checkIn = DateTime(widget.initialCheckIn.year, widget.initialCheckIn.month, widget.initialCheckIn.day);
    if (widget.isRange) {
      _checkOut = DateTime(widget.initialCheckOut.year, widget.initialCheckOut.month, widget.initialCheckOut.day);
      if (_checkOut!.isBefore(_checkIn)) {
        _checkOut = _checkIn.add(const Duration(days: 1));
      }
    }

    final initialPage = (_checkIn.year - _minDate.year) * 12 + (_checkIn.month - _minDate.month);
    _pageController = PageController(initialPage: initialPage.clamp(0, 24));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _nights {
    if (_checkOut == null) return 0;
    return _checkOut!.difference(_checkIn).inDays;
  }

  String get _whenSummary {
    if (_checkOut == null) {
      return DateFormat('d MMM').format(_checkIn);
    }
    return '${DateFormat('d MMM').format(_checkIn)} - ${DateFormat('d MMM').format(_checkOut!)}';
  }

  void _onDateTapped(DateTime date) {
    if (date.isBefore(_minDate) || date.isAfter(_maxDate)) return;

    setState(() {
      if (!widget.isRange) {
        _checkIn = date;
        _checkOut = date;
        return;
      }

      if (_checkOut != null) {
        // Both were set, start new selection
        _checkIn = date;
        _checkOut = null;
      } else {
        // CheckIn is set, waiting for CheckOut
        if (date.isBefore(_checkIn)) {
          // Tapped earlier date, restart checkin
          _checkIn = date;
          _checkOut = null;
        } else if (date.isAtSameMomentAs(_checkIn)) {
          // Tapped same date, treat as 1 night check-out tomorrow
          _checkOut = date.add(const Duration(days: 1));
        } else {
          // Valid range
          _checkOut = date;
        }
      }
    });
  }

  void _applyFlexiblePreset(String preset) {
    setState(() {
      _flexibleDuration = preset;
      final today = DateTime.now();
      if (preset == 'weekend') {
        // Upcoming Friday to Sunday
        final daysUntilFriday = (DateTime.friday - today.weekday + 7) % 7;
        _checkIn = DateTime(today.year, today.month, today.day).add(Duration(days: daysUntilFriday == 0 ? 7 : daysUntilFriday));
        _checkOut = _checkIn.add(const Duration(days: 2));
      } else if (preset == 'week') {
        _checkIn = DateTime(today.year, today.month, today.day);
        _checkOut = _checkIn.add(const Duration(days: 7));
      } else if (preset == 'month') {
        _checkIn = DateTime(today.year, today.month, today.day);
        _checkOut = _checkIn.add(const Duration(days: 30));
      }
      _mode = AirbnbPickerMode.dates;
    });
  }

  void _applyFlexTolerance(int days) {
    setState(() {
      _flexibilityDays = days;
      if (days > 0 && _checkOut != null) {
        _checkOut = _checkIn.add(Duration(days: _nights + days));
      }
    });
  }

  void _resetDates() {
    setState(() {
      final now = DateTime.now();
      _checkIn = DateTime(now.year, now.month, now.day);
      _checkOut = _checkIn.add(const Duration(days: 1));
      _flexibilityDays = 0;
    });
  }

  void _confirmSelection() {
    final finalCheckOut = _checkOut ?? _checkIn.add(const Duration(days: 1));
    Navigator.of(context).pop(
      DateTimeRange(
        start: _checkIn,
        end: finalCheckOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return DraggableScrollableSheet(
      initialChildSize: screenHeight > 800 ? 0.88 : 0.94,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 24,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDDDDD),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),

            // Top Airbnb Capsule Search Strip (Matching Screenshot)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: _buildAirbnbTopCapsule(),
            ),

            // Mode Selector Pill: [ Dates | Flexible ]
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: _buildModeTogglePill(),
            ),

            const Divider(height: 1, color: Color(0xFFEBEBEB)),

            // Main Content: Dates PageView vs Flexible View
            Expanded(
              child: _mode == AirbnbPickerMode.dates
                  ? _buildDatesCalendarView()
                  : _buildFlexibleOptionsView(),
            ),

            // Bottom Tolerance Filter Pills (Exact dates, ± 1 day, etc.)
            if (_mode == AirbnbPickerMode.dates && widget.isRange) ...[
              const Divider(height: 1, color: Color(0xFFEBEBEB)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: _buildTolerancePills(),
              ),
            ],

            // Bottom Footer (Reset + Save Dates Button)
            _buildBottomFooter(),
          ],
        ),
      ),
    );
  }

  // ── 1. Top Airbnb Search Capsule Strip ──────────────────────────────────────
  Widget _buildAirbnbTopCapsule() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: const Color(0xFFDDDDDD), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // Where section
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Where',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF222222),
                  ),
                ),
                Text(
                  widget.roomName ?? 'EaseInn Bengaluru',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF717171),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(width: 1, height: 28, color: const Color(0xFFEBEBEB)),
          const SizedBox(width: 10),

          // When (Active Capsule)
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'When',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF222222),
                          ),
                        ),
                        Text(
                          _whenSummary,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF222222),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_checkOut != null)
                    GestureDetector(
                      onTap: _resetDates,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFFDDDDDD),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, size: 12, color: Color(0xFF222222)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 28, color: const Color(0xFFEBEBEB)),

          // Who section
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Who',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF222222),
                    ),
                  ),
                  Text(
                    widget.guestCountSummary ?? 'Guests',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF717171),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Airbnb Red Search Action Icon
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF385C), Color(0xFFE00B41)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_rounded, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  // ── 2. Top Mode Selector Pill: [ Dates | Flexible ] ─────────────────────────
  Widget _buildModeTogglePill() {
    return Container(
      width: 240,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFFEBEBEB),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(3),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            alignment: _mode == AirbnbPickerMode.dates
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Container(
              width: 116,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _mode = AirbnbPickerMode.dates),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Text(
                      'Dates',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _mode == AirbnbPickerMode.dates
                            ? const Color(0xFF222222)
                            : const Color(0xFF717171),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _mode = AirbnbPickerMode.flexible),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Text(
                      'Flexible',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _mode == AirbnbPickerMode.flexible
                            ? const Color(0xFF222222)
                            : const Color(0xFF717171),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 3. Dates Calendar PageView (Month Grid with Airbnb Animations) ─────────
  Widget _buildDatesCalendarView() {
    final totalMonths = (_maxDate.year - _minDate.year) * 12 + (_maxDate.month - _minDate.month) + 1;

    return Column(
      children: [
        // Weekday Initials: S  M  T  W  T  F  S
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((day) {
              return SizedBox(
                width: 36,
                child: Center(
                  child: Text(
                    day,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF717171),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // PageView of Months
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: totalMonths.clamp(1, 48),
            itemBuilder: (context, pageIndex) {
              final month = DateTime(_minDate.year, _minDate.month + pageIndex, 1);
              return _buildMonthPage(month);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthPage(DateTime month) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7; // 0 = Sun

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month Header with Chevrons
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 24, color: Color(0xFF222222)),
                  onPressed: () {
                    if (_pageController.hasClients && _pageController.page! > 0) {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                ),
                Text(
                  DateFormat('MMMM yyyy').format(month),
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF222222),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 24, color: Color(0xFF222222)),
                  onPressed: () {
                    if (_pageController.hasClients) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // Days Grid (7 columns)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (ctx, index) {
              final dayNumber = index - firstWeekday + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const SizedBox.shrink();
              }

              final date = DateTime(month.year, month.month, dayNumber);
              return _buildAirbnbDayCell(date);
            },
          ),
        ],
      ),
    );
  }

  // ── 4. Airbnb Day Cell with Connected Range Strip ─────────────────────────
  Widget _buildAirbnbDayCell(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isPast = date.isBefore(today);

    final isStart = date.isAtSameMomentAs(_checkIn);
    final isEnd = _checkOut != null && date.isAtSameMomentAs(_checkOut!);
    final isMiddle = _checkOut != null && date.isAfter(_checkIn) && date.isBefore(_checkOut!);

    final isSelected = isStart || isEnd;

    // Background range bridge color
    Widget? bridge;
    if (_checkOut != null && _checkOut!.isAfter(_checkIn)) {
      if (isStart) {
        bridge = Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 24,
            height: 40,
            color: const Color(0xFFF7F7F7),
          ),
        );
      } else if (isEnd) {
        bridge = Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 40,
            color: const Color(0xFFF7F7F7),
          ),
        );
      } else if (isMiddle) {
        bridge = Container(
          height: 40,
          color: const Color(0xFFF7F7F7),
        );
      }
    }

    return GestureDetector(
      onTap: isPast ? null : () => _onDateTapped(date),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Range bridge strip
          if (bridge != null) bridge,

          // Black Circle for Start & End Date (Airbnb Style)
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: isSelected ? 42 : 38,
            height: isSelected ? 42 : 38,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF222222) : Colors.transparent,
              shape: BoxShape.circle,
              border: (date.isAtSameMomentAs(today) && !isSelected)
                  ? Border.all(color: const Color(0xFF222222), width: 1.2)
                  : null,
            ),
            child: Center(
              child: Text(
                '${date.day}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : (isPast ? FontWeight.normal : FontWeight.w500),
                  color: isSelected
                      ? Colors.white
                      : (isPast ? const Color(0xFFCCCCCC) : const Color(0xFF222222)),
                  decoration: isPast ? TextDecoration.lineThrough : null,
                  decorationColor: const Color(0xFFCCCCCC),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 5. Bottom Tolerance Pills (Exact dates, ± 1 day, ± 2 days, etc.) ────────
  Widget _buildTolerancePills() {
    final tolerances = [
      {'label': 'Exact dates', 'val': 0},
      {'label': '± 1 day', 'val': 1},
      {'label': '± 2 days', 'val': 2},
      {'label': '± 3 days', 'val': 3},
      {'label': '± 7 days', 'val': 7},
      {'label': '± 14 days', 'val': 14},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: tolerances.map((t) {
          final isSelected = _flexibilityDays == t['val'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _applyFlexTolerance(t['val'] as int),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF222222) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF222222) : const Color(0xFFDDDDDD),
                    width: 1.2,
                  ),
                ),
                child: Text(
                  t['label'] as String,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF222222),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 6. Flexible View (Presets like Weekend, Week, Month) ───────────────────
  Widget _buildFlexibleOptionsView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stay for how long?',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF222222),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _flexDurationCard('weekend', 'Weekend', '2 nights'),
              const SizedBox(width: 10),
              _flexDurationCard('week', 'A week', '7 nights'),
              const SizedBox(width: 10),
              _flexDurationCard('month', 'A month', '30 nights'),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'When do you want to go?',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF222222),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(6, (i) {
              final month = DateTime(DateTime.now().year, DateTime.now().month + i);
              return Container(
                width: 100,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDDDDDD)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_month_outlined, size: 24, color: Color(0xFF717171)),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('MMMM').format(month),
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF222222)),
                    ),
                    Text(
                      DateFormat('yyyy').format(month),
                      style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF717171)),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _flexDurationCard(String key, String title, String subtitle) {
    final isSelected = _flexibleDuration == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => _applyFlexiblePreset(key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF7F7F7) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF222222) : const Color(0xFFDDDDDD),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF222222),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF717171),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 7. Bottom Footer (Reset + Save Dates Button) ───────────────────────────
  Widget _buildBottomFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEBEBEB))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Reset / Clear
            TextButton(
              onPressed: _resetDates,
              child: Text(
                'Reset',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF222222),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),

            // Summary of Nights & Dates + Airbnb Black Save Button
            ElevatedButton(
              onPressed: _confirmSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF222222),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _nights > 0
                        ? 'Set $_nights night${_nights > 1 ? "s" : ""}'
                        : 'Set Dates',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
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
}
