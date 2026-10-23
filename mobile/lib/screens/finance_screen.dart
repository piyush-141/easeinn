import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/bill.dart';
import '../models/expense.dart';
import '../services/hotel_store.dart';
import '../services/supabase_sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Date range options
// ─────────────────────────────────────────────────────────────────────────────
enum _DateRange { today, week, month, custom }

extension _DateRangeLabel on _DateRange {
  String get label => switch (this) {
        _DateRange.today => 'Today',
        _DateRange.week => 'This Week',
        _DateRange.month => 'This Month',
        _DateRange.custom => 'Custom',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction type for unified history list
// ─────────────────────────────────────────────────────────────────────────────
enum _TxType { all, collection, expense }

/// Alias for [FinanceScreen] under the "Payments" branding.
typedef PaymentsScreen = FinanceScreen;

class FinanceScreen extends StatefulWidget {
  final int initialTab;
  const FinanceScreen({super.key, this.initialTab = 0});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  _DateRange _dateRange = _DateRange.today;
  DateTimeRange? _customRange;
  _TxType _txFilter = _TxType.all;
  bool _isRefreshing = false;

  final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _refreshExpenses();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    return switch (_dateRange) {
      _DateRange.today => (
          DateTime(now.year, now.month, now.day),
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        ),
      _DateRange.week => (
          now.subtract(Duration(days: now.weekday - 1))
              .copyWith(hour: 0, minute: 0, second: 0),
          now.copyWith(hour: 23, minute: 59, second: 59),
        ),
      _DateRange.month => (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        ),
      _DateRange.custom => _customRange != null
          ? (
              _customRange!.start.copyWith(hour: 0, minute: 0),
              _customRange!.end.copyWith(hour: 23, minute: 59, second: 59),
            )
          : (DateTime(now.year, now.month, now.day), now),
    };
  }

  Future<void> _refreshExpenses() async {
    final store = context.read<HotelStore>();
    if (!SupabaseSyncService.isValidUuid(store.currentProperty.id)) return;
    setState(() => _isRefreshing = true);
    try {
      final remote = await SupabaseSyncService.pullExpenses(store.currentProperty.id);
      for (final raw in remote) {
        final exp = Expense.fromJson(raw);
        if (!store.expenses.any((e) => e.id == exp.id)) {
          store.expenses;
        }
      }
      store.mergeRemoteExpenses(remote);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  // ──────────────────────────────────────────
  // Computed aggregates
  // ──────────────────────────────────────────
  Map<String, dynamic> _aggregates(HotelStore store) {
    final (from, to) = _range;

    double totalCollections = 0;
    double totalExpenses = 0;
    double totalOutstanding = 0;
    int dueBookingsCount = 0;

    // Collections from payments in the date range
    for (final bill in store.bills) {
      for (final pay in bill.payments) {
        if (!pay.recordedAt.isBefore(from) && !pay.recordedAt.isAfter(to)) {
          totalCollections += pay.amount;
        }
      }
      // Outstanding from active/finalized bills
      if (bill.outstanding > 0) {
        totalOutstanding += bill.outstanding;
        dueBookingsCount++;
      }
    }

    // Expenses in range
    for (final exp in store.expenses) {
      if (!exp.recordedAt.isBefore(from) && !exp.recordedAt.isAfter(to)) {
        totalExpenses += exp.amount;
      }
    }

    return {
      'collections': totalCollections,
      'expenses': totalExpenses,
      'outstanding': totalOutstanding,
      'dueCount': dueBookingsCount,
      'net': totalCollections - totalExpenses,
    };
  }

  // ──────────────────────────────────────────
  // Date formatting helpers
  // ──────────────────────────────────────────
  String _formatTxDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final txDay = DateTime(dt.year, dt.month, dt.day);
    final timeStr = DateFormat('h:mm a').format(dt);

    if (txDay == today) {
      return 'Today, $timeStr';
    } else if (txDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return DateFormat('dd MMM').format(dt);
    }
  }

  String _bookingOrRoom(HotelStore store, String stayId, String fallbackBillNumber) {
    try {
      final stay = store.stays.firstWhere((s) => s.id == stayId);
      if (fallbackBillNumber.startsWith('BK-')) {
        return fallbackBillNumber;
      }
      if (stay.room?.roomNumber != null && stay.room!.roomNumber.isNotEmpty) {
        return 'BK-${stay.room!.roomNumber.padLeft(4, '0')}';
      }
      return fallbackBillNumber;
    } catch (_) {
      return fallbackBillNumber;
    }
  }

  // ──────────────────────────────────────────
  // Unified transaction list
  // ──────────────────────────────────────────
  List<_TxItem> _transactions(HotelStore store) {
    final (from, to) = _range;
    final items = <_TxItem>[];

    if (_txFilter != _TxType.expense) {
      for (final bill in store.bills) {
        final guestName = _guestNameForBill(store, bill.stayId);
        final bookingOrRoom = _bookingOrRoom(store, bill.stayId, bill.billNumber);

        for (final pay in bill.payments) {
          if (!pay.recordedAt.isBefore(from) && !pay.recordedAt.isAfter(to)) {
            final isAdvance = pay.paymentType == 'advance';
            final title = guestName.isNotEmpty ? guestName : bookingOrRoom;
            final prefix = isAdvance ? 'Advance received' : 'Payment received';
            final detailsLine = bookingOrRoom.isNotEmpty ? '$prefix · $bookingOrRoom' : prefix;

            items.add(_TxItem(
              id: pay.id,
              type: _TxType.collection,
              title: title,
              detailsLine: detailsLine,
              dateString: _formatTxDate(pay.recordedAt),
              methodLabel: _methodLabel(pay.method),
              amount: pay.amount,
              date: pay.recordedAt,
              isPayment: true,
            ));
          }
        }
      }
    }

    if (_txFilter != _TxType.collection) {
      for (final exp in store.expenses) {
        if (!exp.recordedAt.isBefore(from) && !exp.recordedAt.isAfter(to)) {
          final catLabel = Expense.categoryLabel(exp.category);
          final hasNotes = exp.notes != null && exp.notes!.trim().isNotEmpty;
          final title = hasNotes ? exp.notes!.trim() : catLabel;
          final detailsLine = hasNotes ? 'Expense · $catLabel' : 'Expense';

          items.add(_TxItem(
            id: exp.id,
            type: _TxType.expense,
            title: title,
            detailsLine: detailsLine,
            dateString: _formatTxDate(exp.recordedAt),
            methodLabel: _methodLabel(exp.paymentMethod),
            amount: exp.amount,
            date: exp.recordedAt,
            expenseId: exp.id,
            isPayment: false,
          ));
        }
      }
    }

    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  String _guestNameForBill(HotelStore store, String stayId) {
    try {
      final stay = store.stays.firstWhere((s) => s.id == stayId);
      return stay.guest?.fullName ?? '';
    } catch (_) {
      return '';
    }
  }

  String _roomForBill(HotelStore store, String stayId) {
    try {
      final stay = store.stays.firstWhere((s) => s.id == stayId);
      return stay.room?.roomNumber ?? '';
    } catch (_) {
      return '';
    }
  }

  String _methodLabel(String method) => switch (method) {
        'upi' => 'UPI',
        'card' => 'Card',
        'bank_transfer' => 'Bank Transfer',
        _ => 'Cash',
      };

  // ──────────────────────────────────────────
  // UI Build
  // ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final agg = _aggregates(store);
    final transactions = _transactions(store);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Text(
          'Payments',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A6CFF)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22, color: Color(0xFF0F172A)),
              onPressed: _refreshExpenses,
              tooltip: 'Refresh',
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(98),
          child: Column(
            children: [
              _buildDateRangeChips(),
              TabBar(
                controller: _tab,
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
                labelColor: const Color(0xFF1A6CFF),
                unselectedLabelColor: const Color(0xFF64748B),
                indicatorColor: const Color(0xFF1A6CFF),
                indicatorWeight: 2.5,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'History'),
                  Tab(text: 'Guest Dues'),
                ],
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildOverview(store, agg, transactions),
          _buildHistory(store, transactions),
          _buildDues(store),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(store),
    );
  }

  // ── Date Range Filter Pills ───────────────────────────────────────────────
  Widget _buildDateRangeChips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: _DateRange.values.map((range) {
          final selected = _dateRange == range;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () async {
                if (range == _DateRange.custom) {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDateRange: _customRange,
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.light(primary: Color(0xFF1A6CFF)),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setState(() {
                      _customRange = picked;
                      _dateRange = _DateRange.custom;
                    });
                  }
                  return;
                }
                setState(() => _dateRange = range);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF1A6CFF) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: selected ? const Color(0xFF1A6CFF) : const Color(0xFFE2E8F0),
                    width: 1.0,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  range.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Overview Tab ──────────────────────────────────────────────────────────
  Widget _buildOverview(HotelStore store, Map<String, dynamic> agg, List<_TxItem> transactions) {
    final dueCount = agg['dueCount'] as int;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // 1. Top Collections Card (Sky Blue with wallet icon & rising chart bars)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 24,
                  color: Color(0xFF1A6CFF),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dateRange == _DateRange.today
                          ? 'Collections Today'
                          : 'Collections (${_dateRange.label})',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${_fmt.format(agg['collections']!).replaceAll('₹', '')}',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Payments received ${_dateRange == _DateRange.today ? 'today' : 'this period'}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              // 5 rising rounded vertical bars (bar wave chart)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [10.0, 16.0, 24.0, 32.0, 42.0].map((h) => Container(
                  width: 4.5,
                  height: h,
                  margin: const EdgeInsets.only(left: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF93C5FD).withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                )).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 2. Row of 2 Grid Cards Side-by-Side (Guest Dues & Expenses)
        Row(
          children: [
            // Left Card: Guest Dues
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _tab.animateTo(2),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.access_time_rounded,
                              size: 20,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: Color(0xFF94A3B8),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Guest Dues',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${_fmt.format(agg['outstanding']!).replaceAll('₹', '')}',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dueCount == 0
                            ? 'No pending dues'
                            : 'Across $dueCount ${dueCount == 1 ? 'booking' : 'bookings'}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Right Card: Expenses
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  setState(() => _txFilter = _TxType.expense);
                  _tab.animateTo(1);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.description_outlined,
                              size: 20,
                              color: Color(0xFF475569),
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: Color(0xFF94A3B8),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Expenses',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${_fmt.format(agg['expenses']!).replaceAll('₹', '')}',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Recorded this period',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // 3. Card 3: Recent Transactions Container
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Recent Transactions',
                    style: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => _tab.animateTo(1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View all',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A6CFF),
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Color(0xFF1A6CFF),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 46,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No transactions for this period',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Payments and expenses will appear here.',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                for (int i = 0; i < transactions.take(6).length; i++) ...[
                  _buildTransactionRow(transactions[i]),
                  if (i < transactions.take(6).length - 1)
                    const Divider(height: 24, thickness: 1, color: Color(0xFFF1F5F9)),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Unified Transaction Row Component ─────────────────────────────────────
  Widget _buildTransactionRow(_TxItem tx, {VoidCallback? onDelete}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: tx.isPayment ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            tx.isPayment ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            color: tx.isPayment ? const Color(0xFF16A34A) : const Color(0xFF475569),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tx.title,
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                tx.detailsLine,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${tx.dateString} · ${tx.methodLabel}',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: const Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${tx.isPayment ? '+' : '–'}₹${_fmt.format(tx.amount).replaceAll('₹', '')}',
              style: GoogleFonts.outfit(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: tx.isPayment ? const Color(0xFF16A34A) : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: tx.isPayment ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tx.isPayment ? 'Payment' : 'Expense',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: tx.isPayment ? const Color(0xFF15803D) : const Color(0xFF475569),
                    ),
                  ),
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── History Tab ───────────────────────────────────────────────────────────
  Widget _buildHistory(HotelStore store, List<_TxItem> transactions) {
    return Column(
      children: [
        // Filter chips: All, Collections, Expenses
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: _TxType.values.map((t) {
              final selected = _txFilter == t;
              final label = switch (t) {
                _TxType.all => 'All',
                _TxType.collection => 'Collections',
                _TxType.expense => 'Expenses',
              };
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _txFilter = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF18181B) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? const Color(0xFF18181B) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Unified transactions list
        Expanded(
          child: transactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        size: 48,
                        color: Color(0xFFCBD5E1),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No transactions for this filter',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF64748B),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: transactions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final tx = transactions[i];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: _buildTransactionRow(
                        tx,
                        onDelete: !tx.isPayment && tx.expenseId != null
                            ? () => _confirmDeleteExpense(ctx, tx.expenseId!, store)
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _confirmDeleteExpense(BuildContext ctx, String expenseId, HotelStore store) {
    showDialog(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text('Delete Expense?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('This will permanently remove this expense record.', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3B30)),
            onPressed: () async {
              Navigator.pop(dctx);
              await store.deleteExpense(expenseId);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Guest Dues Tab ────────────────────────────────────────────────────────
  Widget _buildDues(HotelStore store) {
    final dueBills = store.bills.where((b) => b.outstanding > 0).toList()
      ..sort((a, b) => b.outstanding.compareTo(a.outstanding));

    if (dueBills.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F9ED),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 36,
                color: Color(0xFF34C759),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'All Dues Cleared!',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No outstanding dues at this time.',
              style: GoogleFonts.inter(color: const Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: dueBills.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final bill = dueBills[i];
        final guestName = _guestNameForBill(store, bill.stayId);
        final roomNum = _roomForBill(store, bill.stayId);
        return _dueCard(ctx, bill, guestName, roomNum, store);
      },
    );
  }

  Widget _dueCard(BuildContext ctx, Bill bill, String guest, String room, HotelStore store) {
    final pct = bill.subtotal > 0 ? bill.amountPaid / bill.subtotal : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  bill.billNumber,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFD97706),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '₹${_fmt.format(bill.outstanding).replaceAll('₹', '')}',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFF3B30),
                ),
              ),
              Text(' due', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 14, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  guest.isNotEmpty ? guest : 'Guest',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (room.isNotEmpty) ...[
                const Icon(Icons.meeting_room_outlined, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Text('Room $room', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Payment progress
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Paid: ₹${_fmt.format(bill.amountPaid).replaceAll('₹', '')}',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
              ),
              Text(
                'Total: ₹${_fmt.format(bill.subtotal).replaceAll('₹', '')}',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF16A34A)),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showRecordPaymentSheet(ctx, bill, store),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Record Payment'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1A6CFF),
                side: const BorderSide(color: Color(0xFF1A6CFF)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Fixed Action Bar ───────────────────────────────────────────────
  Widget _buildBottomBar(HotelStore store) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFF1F5F9), width: 1.2),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _handleRecordPaymentPressed(context, store),
                    icon: const Icon(Icons.credit_card_outlined, size: 19),
                    label: Text(
                      'Record Payment',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A6CFF),
                      side: const BorderSide(color: Color(0xFF1A6CFF), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddExpenseSheet(context, store),
                    icon: const Icon(Icons.add_rounded, size: 20, color: Colors.white),
                    label: Text(
                      'Add Expense',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF18181B),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom Action Trigger for Record Payment ──────────────────────────────
  void _handleRecordPaymentPressed(BuildContext ctx, HotelStore store) {
    final dueBills = store.bills.where((b) => b.outstanding > 0).toList()
      ..sort((a, b) => b.outstanding.compareTo(a.outstanding));

    if (dueBills.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text(
            'All dues are cleared! No outstanding guest folios.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
        ),
      );
      return;
    }

    if (dueBills.length == 1) {
      _showRecordPaymentSheet(ctx, dueBills.first, store);
      return;
    }

    // Multiple due bills: show select sheet
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Select Guest Due',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(bctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(bctx).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: dueBills.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, idx) {
                  final bill = dueBills[idx];
                  final guest = _guestNameForBill(store, bill.stayId);
                  final room = _roomForBill(store, bill.stayId);
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.pop(bctx);
                      _showRecordPaymentSheet(ctx, bill, store);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  guest.isNotEmpty ? guest : bill.billNumber,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                if (room.isNotEmpty)
                                  Text(
                                    'Room $room · ${bill.billNumber}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '₹${_fmt.format(bill.outstanding).replaceAll('₹', '')}',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFFF3B30),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF94A3B8),
                            size: 20,
                          ),
                        ],
                      ),
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

  // ── Add Expense Sheet ─────────────────────────────────────────────────────
  void _showAddExpenseSheet(BuildContext ctx, HotelStore store) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddExpenseSheet(store: store),
    );
  }

  // ── Record Payment Sheet ──────────────────────────────────────────────────
  void _showRecordPaymentSheet(BuildContext ctx, Bill bill, HotelStore store) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecordPaymentSheet(bill: bill, store: store),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction item model (local view model)
// ─────────────────────────────────────────────────────────────────────────────
class _TxItem {
  final String id;
  final _TxType type;
  final String title;
  final String detailsLine;
  final String dateString;
  final String methodLabel;
  final double amount;
  final DateTime date;
  final String? expenseId;
  final bool isPayment;

  const _TxItem({
    required this.id,
    required this.type,
    required this.title,
    required this.detailsLine,
    required this.dateString,
    required this.methodLabel,
    required this.amount,
    required this.date,
    this.expenseId,
    required this.isPayment,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Expense Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _AddExpenseSheet extends StatefulWidget {
  final HotelStore store;
  const _AddExpenseSheet({required this.store});

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  String _category = 'other';
  String _method = 'cash';
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Text('Add Expense', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Amount
                      _fieldLabel('Amount *'),
                      TextFormField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                        decoration: _inputDeco('e.g. 1500', prefix: '₹ '),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          if (n == null || n <= 0) return 'Enter a valid amount';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Category
                      _fieldLabel('Category *'),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: _inputDeco('Select category'),
                        items: Expense.categories.map((c) {
                          final db = Expense.categoryDbValue(c);
                          return DropdownMenuItem(value: db, child: Text(c, style: GoogleFonts.inter(fontSize: 14)));
                        }).toList(),
                        onChanged: (v) => setState(() => _category = v ?? 'other'),
                      ),
                      const SizedBox(height: 16),

                      // Payment method
                      _fieldLabel('Payment Method *'),
                      DropdownButtonFormField<String>(
                        initialValue: _method,
                        decoration: _inputDeco('Select method'),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('Cash')),
                          DropdownMenuItem(value: 'upi', child: Text('UPI')),
                          DropdownMenuItem(value: 'card', child: Text('Card')),
                          DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                        ],
                        onChanged: (v) => setState(() => _method = v ?? 'cash'),
                      ),
                      const SizedBox(height: 16),

                      // Date
                      _fieldLabel('Date'),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: _date,
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 8),
                              Text(DateFormat('dd MMM yyyy').format(_date), style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Reference (optional)
                      _fieldLabel('Reference / Transaction ID'),
                      TextFormField(
                        controller: _refCtrl,
                        decoration: _inputDeco('Optional'),
                      ),
                      const SizedBox(height: 16),

                      // Notes / Title
                      _fieldLabel('Notes / Item Description'),
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 2,
                        decoration: _inputDeco('e.g. Laundry Services, Electricity Bill'),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF18181B),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _saving ? null : _submit,
                          child: _saving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text('Save Expense', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                        ),
                      ),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.store.addExpense(
        amount: double.parse(_amountCtrl.text),
        category: _category,
        paymentMethod: _method,
        reference: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        recordedAt: _date,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _fieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
      );

  InputDecoration _inputDeco(String hint, {String? prefix}) => InputDecoration(
        hintText: hint,
        prefixText: prefix,
        hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A6CFF), width: 1.5)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Record Payment Bottom Sheet (for outstanding dues)
// ─────────────────────────────────────────────────────────────────────────────
class _RecordPaymentSheet extends StatefulWidget {
  final Bill bill;
  final HotelStore store;
  const _RecordPaymentSheet({required this.bill, required this.store});

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  String _method = 'cash';
  bool _saving = false;
  final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.bill.outstanding.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Record Payment', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                      Text(widget.bill.billNumber, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                    ],
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Outstanding display
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Outstanding due', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFD97706), fontWeight: FontWeight.w600)),
                          Text('₹${_fmt.format(widget.bill.outstanding).replaceAll('₹', '')}', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFFFF3B30))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Amount field
                    Text('Payment Amount *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1A6CFF), width: 1.5)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                      ),
                      validator: (v) {
                        final n = double.tryParse(v ?? '');
                        if (n == null || n <= 0) return 'Enter a valid amount';
                        if (n > widget.bill.outstanding + 0.01) return 'Cannot exceed outstanding due';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Payment method
                    Text('Method *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _method,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'upi', child: Text('UPI')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                      ],
                      onChanged: (v) => setState(() => _method = v ?? 'cash'),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A6CFF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text('Confirm Payment', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final amount = double.parse(_amountCtrl.text);
      widget.store.recordPartialPayment(
        billId: widget.bill.id,
        amount: amount,
        method: _method,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
