import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../services/hotel_store.dart';
import '../services/export_file_service.dart';
import '../models/stay.dart';
import '../models/guest.dart';
import '../models/bill.dart';
import '../theme/app_theme.dart';
import 'booking_checkout_screen.dart';

enum DateFilterPreset {
  all,
  today,
  yesterday,
  thisWeek,
  thisMonth,
  lastMonth,
  customMonth,
  customRange,
}

class BookingExportScreen extends StatefulWidget {
  final String? initialRoomId;
  final DateFilterPreset initialPreset;

  const BookingExportScreen({
    super.key,
    this.initialRoomId,
    this.initialPreset = DateFilterPreset.all,
  });

  @override
  State<BookingExportScreen> createState() => _BookingExportScreenState();
}

class _BookingExportScreenState extends State<BookingExportScreen> {
  DateFilterPreset _selectedPreset = DateFilterPreset.all;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  DateTime? _selectedMonth; // When customMonth is chosen

  String _selectedRoomFilter = 'all'; // 'all' or roomId
  String _selectedStatusFilter =
      'all'; // 'all', 'active', 'checkedOut', 'reserved'
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedPreset = widget.initialPreset;
    if (widget.initialRoomId != null) {
      _selectedRoomFilter = widget.initialRoomId!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── FILTER LOGIC ──
  List<Stay> _filterStays(HotelStore store) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return store.stays.where((stay) {
      // 1. Room filter
      if (_selectedRoomFilter != 'all') {
        if (stay.roomId != _selectedRoomFilter &&
            stay.room?.roomNumber != _selectedRoomFilter) {
          return false;
        }
      }

      // 2. Status filter
      if (_selectedStatusFilter != 'all') {
        if (_selectedStatusFilter == 'active' &&
            stay.status != StayStatus.active) {
          return false;
        }
        if (_selectedStatusFilter == 'checkedOut' &&
            stay.status != StayStatus.checkedOut) {
          return false;
        }
        if (_selectedStatusFilter == 'reserved' &&
            stay.status != StayStatus.reserved) {
          return false;
        }
      }

      // 3. Date / Month filter (applies against stay checkInAt / expectedCheckOut)
      final checkIn = stay.checkInAt;
      final checkInDate = DateTime(checkIn.year, checkIn.month, checkIn.day);

      switch (_selectedPreset) {
        case DateFilterPreset.all:
          break;
        case DateFilterPreset.today:
          if (checkInDate != today) return false;
          break;
        case DateFilterPreset.yesterday:
          final yesterday = today.subtract(const Duration(days: 1));
          if (checkInDate != yesterday) return false;
          break;
        case DateFilterPreset.thisWeek:
          final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 6));
          if (checkInDate.isBefore(startOfWeek) ||
              checkInDate.isAfter(endOfWeek)) {
            return false;
          }
          break;
        case DateFilterPreset.thisMonth:
          if (checkIn.year != now.year || checkIn.month != now.month) {
            return false;
          }
          break;
        case DateFilterPreset.lastMonth:
          final lastMonthDate = DateTime(now.year, now.month - 1, 1);
          if (checkIn.year != lastMonthDate.year ||
              checkIn.month != lastMonthDate.month) {
            return false;
          }
          break;
        case DateFilterPreset.customMonth:
          if (_selectedMonth != null) {
            if (checkIn.year != _selectedMonth!.year ||
                checkIn.month != _selectedMonth!.month) {
              return false;
            }
          }
          break;
        case DateFilterPreset.customRange:
          if (_customStartDate != null) {
            final start = DateTime(
              _customStartDate!.year,
              _customStartDate!.month,
              _customStartDate!.day,
            );
            if (checkInDate.isBefore(start)) return false;
          }
          if (_customEndDate != null) {
            final end = DateTime(
              _customEndDate!.year,
              _customEndDate!.month,
              _customEndDate!.day,
              23,
              59,
              59,
            );
            if (checkIn.isAfter(end)) return false;
          }
          break;
      }

      // 4. Search query (matches primary guest name, co-guest name, phone, room number, or booking id)
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final primaryMatch =
            (stay.guest?.fullName.toLowerCase().contains(q) ?? false) ||
            (stay.guest?.phone.toLowerCase().contains(q) ?? false) ||
            (stay.guest?.displayIdNumber.toLowerCase().contains(q) ?? false) ||
            (stay.guest?.idNumberMasked.toLowerCase().contains(q) ?? false);

        final coGuestMatch = stay.coGuests.any(
          (cg) =>
              cg.fullName.toLowerCase().contains(q) ||
              cg.phone.toLowerCase().contains(q) ||
              cg.displayIdNumber.toLowerCase().contains(q) ||
              cg.idNumberMasked.toLowerCase().contains(q),
        );

        final roomMatch =
            (stay.room?.roomNumber.toLowerCase().contains(q) ?? false) ||
            (stay.room?.categoryName.toLowerCase().contains(q) ?? false);

        final idMatch = stay.id.toLowerCase().contains(q);

        if (!primaryMatch && !coGuestMatch && !roomMatch && !idMatch) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  // ── CSV EXPORT BUILDER ──
  String _generateCsv(List<Stay> stays, HotelStore store) {
    final buffer = StringBuffer();

    // UTF-8 BOM so Microsoft Excel automatically recognizes Indian characters and symbols properly
    buffer.write('\uFEFF');

    // Headers
    final headers = [
      'Booking ID',
      'Invoice Number',
      'Status',
      'Room Number',
      'Room Category',
      'Floor',
      'Check-In Date',
      'Check-In Time',
      'Check-Out Date',
      'Check-Out Time',
      'Total Nights',
      'Total Guests',
      'Adults',
      'Children',
      'Primary Guest Name',
      'Primary Guest Phone',
      'Primary Guest Email',
      'Primary Guest ID Type',
      'Primary Guest ID Number',
      'Primary Guest Address',
      'Accompanying Guests Count',
      'All Co-Guests Details',
      'Co-Guest 1 Name',
      'Co-Guest 1 Phone',
      'Co-Guest 1 ID',
      'Co-Guest 2 Name',
      'Co-Guest 2 Phone',
      'Co-Guest 2 ID',
      'Co-Guest 3 Name',
      'Co-Guest 3 Phone',
      'Co-Guest 3 ID',
      'Nightly Tariff (₹)',
      'Total Amount (₹)',
      'Amount Paid (₹)',
      'Outstanding Balance (₹)',
      'Payment Status',
    ];

    buffer.writeln(headers.map(_escapeCsv).join(','));

    for (final stay in stays) {
      // Find linked bill
      Bill? bill;
      try {
        bill = store.bills.firstWhere((b) => b.stayId == stay.id);
      } catch (_) {
        bill = null;
      }

      final checkInDate = DateFormat('yyyy-MM-dd').format(stay.checkInAt);
      final checkInTime = DateFormat('hh:mm a').format(stay.checkInAt);
      final outDateObj = stay.checkOutAt ?? stay.expectedCheckOut;
      final checkOutDate = DateFormat('yyyy-MM-dd').format(outDateObj);
      final checkOutTime = DateFormat('hh:mm a').format(outDateObj);

      final statusStr = stay.status == StayStatus.active
          ? 'Active / In-House'
          : stay.status == StayStatus.checkedOut
          ? 'Checked Out'
          : 'Reserved';

      // Accompanying guests summary
      final coGuests = stay.coGuests;
      final coGuestsSummary = coGuests
          .map((cg) {
            final phone = cg.phone.isNotEmpty ? ' [${cg.phone}]' : '';
            final id = cg.displayIdNumber.isNotEmpty
                ? ' (${cg.idType.toUpperCase()}: ${cg.displayIdNumber})'
                : '';
            return '${cg.fullName}$phone$id';
          })
          .join('; ');

      // Specific co-guest slots
      final cg1Name = coGuests.isNotEmpty ? coGuests[0].fullName : '';
      final cg1Phone = coGuests.isNotEmpty ? coGuests[0].phone : '';
      final cg1Id = coGuests.isNotEmpty
          ? '${coGuests[0].idType.toUpperCase()}: ${coGuests[0].displayIdNumber}'
          : '';

      final cg2Name = coGuests.length > 1 ? coGuests[1].fullName : '';
      final cg2Phone = coGuests.length > 1 ? coGuests[1].phone : '';
      final cg2Id = coGuests.length > 1
          ? '${coGuests[1].idType.toUpperCase()}: ${coGuests[1].displayIdNumber}'
          : '';

      final cg3Name = coGuests.length > 2 ? coGuests[2].fullName : '';
      final cg3Phone = coGuests.length > 2 ? coGuests[2].phone : '';
      final cg3Id = coGuests.length > 2
          ? '${coGuests[2].idType.toUpperCase()}: ${coGuests[2].displayIdNumber}'
          : '';

      final subtotal = bill?.subtotal ?? (stay.nightlyRate * stay.actualNights);
      final amountPaid = bill?.amountPaid ?? 0.0;
      final outstanding = bill?.outstanding ?? (subtotal - amountPaid);
      final billStatus =
          bill?.status ?? (outstanding <= 0 ? 'paid' : 'pending');

      final row = [
        stay.id,
        bill?.billNumber ?? 'N/A',
        statusStr,
        stay.room?.roomNumber ?? 'N/A',
        stay.room?.categoryName ?? 'Standard',
        stay.room?.floor.toString() ?? '1',
        checkInDate,
        checkInTime,
        checkOutDate,
        checkOutTime,
        stay.actualNights.toString(),
        (stay.numGuests > 0 ? stay.numGuests : (stay.numAdults + stay.numKids))
            .toString(),
        stay.numAdults.toString(),
        stay.numKids.toString(),
        stay.guest?.fullName ?? 'N/A',
        stay.guest?.phone ?? 'N/A',
        stay.guest?.email ?? 'N/A',
        stay.guest?.idType.toUpperCase() ?? 'AADHAAR',
        stay.guest?.displayIdNumber ?? 'XXXX',
        stay.guest?.address ?? 'N/A',
        coGuests.length.toString(),
        coGuestsSummary.isNotEmpty ? coGuestsSummary : 'None',
        cg1Name,
        cg1Phone,
        cg1Id,
        cg2Name,
        cg2Phone,
        cg2Id,
        cg3Name,
        cg3Phone,
        cg3Id,
        stay.nightlyRate.toStringAsFixed(2),
        subtotal.toStringAsFixed(2),
        amountPaid.toStringAsFixed(2),
        outstanding.toStringAsFixed(2),
        billStatus.toUpperCase(),
      ];

      buffer.writeln(row.map(_escapeCsv).join(','));
    }

    return buffer.toString();
  }

  String _escapeCsv(dynamic value) {
    if (value == null) return '""';
    final str = value.toString();
    if (str.contains(',') ||
        str.contains('"') ||
        str.contains('\n') ||
        str.contains('\r')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return '"$str"';
  }

  // ── SHARING & EXPORT ACTIONS ──
  String _selectedPeriodLabel() {
    switch (_selectedPreset) {
      case DateFilterPreset.all:
        return 'All Time';
      case DateFilterPreset.today:
        return 'Today (${DateFormat('d MMM yyyy').format(DateTime.now())})';
      case DateFilterPreset.yesterday:
        return 'Yesterday (${DateFormat('d MMM yyyy').format(DateTime.now().subtract(const Duration(days: 1)))})';
      case DateFilterPreset.thisWeek:
        return 'This Week';
      case DateFilterPreset.thisMonth:
        return 'This Month (${DateFormat('MMMM yyyy').format(DateTime.now())})';
      case DateFilterPreset.lastMonth:
        return 'Last Month';
      case DateFilterPreset.customMonth:
        return _selectedMonth == null
            ? 'Custom Month'
            : DateFormat('MMMM yyyy').format(_selectedMonth!);
      case DateFilterPreset.customRange:
        if (_customStartDate == null || _customEndDate == null) {
          return 'Custom Range';
        }
        return '${DateFormat('d MMM yyyy').format(_customStartDate!)} – ${DateFormat('d MMM yyyy').format(_customEndDate!)}';
    }
  }

  Future<void> _exportData(List<Stay> filteredStays, HotelStore store) async {
    if (filteredStays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bookings match the selected filters to export.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final csvData = _generateCsv(filteredStays, store);
    final nowStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'EaseInn_Bookings_Register_$nowStr.xlsx';
    final workbook = ExportFileService.createWorkbook(
      csvData: csvData,
      reportTitle: 'Booking Register',
      hotelName: store.currentProperty.name,
      selectedPeriod: _selectedPeriodLabel(),
      recordCount: filteredStays.length,
      additionalDetails:
          'Room: ${_selectedRoomFilter == 'all' ? 'All Rooms' : _selectedRoomFilter}  |  Status: ${_selectedStatusFilter == 'all' ? 'All Statuses' : _selectedStatusFilter}',
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.table_chart_rounded,
                    color: AppTheme.brandPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export ${filteredStays.length} Bookings',
                        style: GoogleFonts.outfit(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slateDark,
                        ),
                      ),
                      Text(
                        'Formatted Excel workbook with your selected filters',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.slateMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Primary Action: Download, Save & Share all at once
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _shareWorkbook(workbook, fileName);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.brandPrimary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.download_done_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Download, Save & Share Excel',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Saves copy in Downloads/EaseInn & opens share sheet',
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

            const SizedBox(height: 12),

            // Option: Copy to Clipboard
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.slateBorder.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.copy_rounded,
                  color: AppTheme.slateDark,
                  size: 20,
                ),
              ),
              title: Text(
                'Copy CSV to Clipboard',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                'Paste directly into Sheets or Notes',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.slateMuted,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: AppTheme.slateMuted,
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                Clipboard.setData(ClipboardData(text: csvData));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${filteredStays.length} booking records copied to clipboard!',
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: const Color(0xFF16A34A),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),

            const Divider(height: 8),

            // Option: View Raw CSV Preview
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.slateBorder.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.remove_red_eye_outlined,
                  color: AppTheme.slateDark,
                  size: 20,
                ),
              ),
              title: Text(
                'View Raw CSV Preview',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                'Inspect raw table data and columns',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.slateMuted,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: AppTheme.slateMuted,
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _showRawCsvDialog(csvData);
              },
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }



  Future<void> _shareWorkbook(Uint8List workbook, String fileName) async {
    try {
      if (!kIsWeb) {
        await ExportFileService.saveToDownloads(
          fileName: fileName,
          bytes: workbook,
        );
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(workbook, flush: true);
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [
            XFile(
              file.path,
              mimeType: ExportFileService.xlsxMimeType,
              name: fileName,
            ),
          ],
          subject: 'EaseInn Hotel Booking Register',
          text:
              'Attached is the formatted booking register saved in Downloads/EaseInn.',
        );
        return;
      }

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [
          XFile.fromData(
            workbook,
            mimeType: ExportFileService.xlsxMimeType,
            name: fileName,
          ),
        ],
        subject: 'EaseInn Hotel Booking Register',
        text: 'EaseInn Hotel Booking Register ($fileName)',
      );
    } catch (e) {
      debugPrint('[BookingExport] Share error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save/share export: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showRawCsvDialog(String csvData) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'CSV Data Preview',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: SelectableText(
                csvData,
                style: GoogleFonts.firaCode(
                  fontSize: 11,
                  color: AppTheme.slateDark,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvData));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CSV copied to clipboard!')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy All'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandPrimary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── DATE SELECTION DIALOGS ──
  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now(),
            ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.brandPrimary,
              onPrimary: Colors.white,
              onSurface: AppTheme.slateDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedPreset = DateFilterPreset.customRange;
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
    }
  }

  void _showMonthPickerSheet() {
    final now = DateTime.now();
    final months = <DateTime>[];
    // Generate past 12 months + current + next 2 months
    for (int i = -12; i <= 2; i++) {
      months.add(DateTime(now.year, now.month + i, 1));
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Month to Export',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: months.length,
                itemBuilder: (ctx, i) {
                  final m = months[i];
                  final isSelected =
                      _selectedPreset == DateFilterPreset.customMonth &&
                      _selectedMonth?.year == m.year &&
                      _selectedMonth?.month == m.month;

                  return ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: isSelected
                        ? AppTheme.brandPrimary.withValues(alpha: 0.1)
                        : null,
                    leading: Icon(
                      Icons.calendar_month_rounded,
                      color: isSelected
                          ? AppTheme.brandPrimary
                          : AppTheme.slateMuted,
                    ),
                    title: Text(
                      DateFormat('MMMM yyyy').format(m),
                      style: GoogleFonts.inter(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.brandPrimary
                            : AppTheme.slateDark,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppTheme.brandPrimary,
                          )
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedPreset = DateFilterPreset.customMonth;
                        _selectedMonth = m;
                      });
                      Navigator.of(ctx).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final filteredStays = _filterStays(store);

    // Compute aggregated metrics for the filtered selection
    int totalGuestsCount = 0;
    double totalBilled = 0.0;
    double totalCollected = 0.0;

    for (final s in filteredStays) {
      totalGuestsCount += (s.numGuests > 0
          ? s.numGuests
          : (s.numAdults + s.numKids));
      try {
        final b = store.bills.firstWhere((x) => x.stayId == s.id);
        totalBilled += b.subtotal;
        totalCollected += b.amountPaid;
      } catch (_) {
        final sub = s.nightlyRate * s.actualNights;
        totalBilled += sub;
      }
    }

    final currencyFormat = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.slateDark,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bookings Register & Export',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.slateDark,
              ),
            ),
            Text(
              store.currentProperty.name,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.slateMuted,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: () => _exportData(filteredStays, store),
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: const Text('Export Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── FILTER HEADER SECTION ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search Bar
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search guest, phone, ID, room...',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: AppTheme.slateMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: AppTheme.brandPrimary,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              size: 18,
                              color: AppTheme.slateMuted,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.slateBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.brandPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Date Presets Horizontal Scroll
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPresetChip('All Time', DateFilterPreset.all),
                      const SizedBox(width: 6),
                      _buildPresetChip('Today', DateFilterPreset.today),
                      const SizedBox(width: 6),
                      _buildPresetChip('Yesterday', DateFilterPreset.yesterday),
                      const SizedBox(width: 6),
                      _buildPresetChip('This Week', DateFilterPreset.thisWeek),
                      const SizedBox(width: 6),
                      _buildPresetChip(
                        'This Month',
                        DateFilterPreset.thisMonth,
                      ),
                      const SizedBox(width: 6),
                      _buildPresetChip(
                        'Last Month',
                        DateFilterPreset.lastMonth,
                      ),
                      const SizedBox(width: 6),
                      _buildMonthSelectorChip(),
                      const SizedBox(width: 6),
                      _buildCustomRangeChip(),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Room & Status Filter Dropdowns Row
                Row(
                  children: [
                    // Room Filter
                    Expanded(
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.slateBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.meeting_room_outlined,
                              size: 15,
                              color: AppTheme.brandPrimary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedRoomFilter,
                                  isExpanded: true,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: AppTheme.slateMuted,
                                  ),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppTheme.slateDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: 'all',
                                      child: Text('All Rooms'),
                                    ),
                                    ...store.rooms.map(
                                      (r) => DropdownMenuItem(
                                        value: r.id,
                                        child: Text(
                                          'Room ${r.roomNumber} (${r.categoryName})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null)
                                      setState(() => _selectedRoomFilter = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Status Filter
                    Expanded(
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.slateBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.tune_rounded,
                              size: 15,
                              color: AppTheme.brandPrimary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedStatusFilter,
                                  isExpanded: true,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: AppTheme.slateMuted,
                                  ),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppTheme.slateDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text('All Statuses'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'active',
                                      child: Text('In-House'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'checkedOut',
                                      child: Text('Checked Out'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'reserved',
                                      child: Text('Reserved'),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null)
                                      setState(
                                        () => _selectedStatusFilter = val,
                                      );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── SUMMARY METRICS STRIP ──
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.slateBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetricItem(
                  'Bookings',
                  '${filteredStays.length}',
                  Icons.receipt_long_rounded,
                  AppTheme.brandPrimary,
                ),
                Container(width: 1, height: 26, color: AppTheme.slateBorder),
                _buildMetricItem(
                  'Guests',
                  '$totalGuestsCount',
                  Icons.groups_rounded,
                  const Color(0xFF2563EB),
                ),
                Container(width: 1, height: 26, color: AppTheme.slateBorder),
                _buildMetricItem(
                  'Billed Tariff',
                  currencyFormat.format(totalBilled),
                  Icons.payments_rounded,
                  const Color(0xFF0F172A),
                ),
                Container(width: 1, height: 26, color: AppTheme.slateBorder),
                _buildMetricItem(
                  'Collected',
                  currencyFormat.format(totalCollected),
                  Icons.check_circle_rounded,
                  const Color(0xFF16A34A),
                ),
              ],
            ),
          ),

          // ── BOOKINGS LIST VIEW ──
          Expanded(
            child: filteredStays.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredStays.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final stay = filteredStays[i];
                      return _buildBookingCard(stay, store, currencyFormat);
                    },
                  ),
          ),

          // ── BOTTOM FLOATING ACTION BAR ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final csv = _generateCsv(filteredStays, store);
                        Clipboard.setData(ClipboardData(text: csv));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${filteredStays.length} bookings copied as CSV table!',
                            ),
                            backgroundColor: const Color(0xFF16A34A),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy CSV'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.slateDark,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => _exportData(filteredStays, store),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: Text('Export ${filteredStays.length} Records'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brandPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── FILTER CHIPS ──
  Widget _buildPresetChip(String label, DateFilterPreset preset) {
    final isSelected = _selectedPreset == preset;
    return InkWell(
      onTap: () => setState(() => _selectedPreset = preset),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.brandPrimary : AppTheme.slateBorder,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_rounded, size: 12, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.slateDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelectorChip() {
    final isSelected = _selectedPreset == DateFilterPreset.customMonth;
    final label = isSelected && _selectedMonth != null
        ? DateFormat('MMM yyyy').format(_selectedMonth!)
        : 'Select Month';

    return InkWell(
      onTap: _showMonthPickerSheet,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.brandPrimary : AppTheme.slateBorder,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: 12,
              color: isSelected ? Colors.white : AppTheme.slateDark,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.slateDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomRangeChip() {
    final isSelected = _selectedPreset == DateFilterPreset.customRange;
    final label =
        isSelected && _customStartDate != null && _customEndDate != null
        ? '${DateFormat('d MMM').format(_customStartDate!)} - ${DateFormat('d MMM').format(_customEndDate!)}'
        : 'Custom Range';

    return InkWell(
      onTap: _pickCustomRange,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.brandPrimary : AppTheme.slateBorder,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.date_range_rounded,
              size: 12,
              color: isSelected ? Colors.white : AppTheme.slateDark,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.slateDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11.5, color: color),
            const SizedBox(width: 3.5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.slateMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: AppTheme.slateDark,
          ),
        ),
      ],
    );
  }

  // ── ELEVATED LUXURY BOOKING CARD ──
  Widget _buildBookingCard(
    Stay stay,
    HotelStore store,
    NumberFormat currencyFormat,
  ) {
    Bill? bill;
    try {
      bill = store.bills.firstWhere((b) => b.stayId == stay.id);
    } catch (_) {
      bill = null;
    }

    final totalGuests = stay.numGuests > 0
        ? stay.numGuests
        : (stay.numAdults + stay.numKids);

    // Status styling
    Color statusBg;
    Color statusFg;
    Color statusBorder;
    String statusLabel;
    if (stay.status == StayStatus.active) {
      statusBg = const Color(0xFFECFDF5);
      statusFg = const Color(0xFF059669);
      statusBorder = const Color(0xFFA7F3D0);
      statusLabel = 'In-House';
    } else if (stay.status == StayStatus.checkedOut) {
      statusBg = const Color(0xFFF1F5F9);
      statusFg = const Color(0xFF475569);
      statusBorder = const Color(0xFFCBD5E1);
      statusLabel = 'Checked Out';
    } else {
      statusBg = const Color(0xFFFFFBEB);
      statusFg = const Color(0xFFD97706);
      statusBorder = const Color(0xFFFDE68A);
      statusLabel = 'Reserved';
    }

    final subtotal = bill?.subtotal ?? (stay.nightlyRate * stay.actualNights);
    final amountPaid = bill?.amountPaid ?? 0.0;
    final outstanding = bill?.outstanding ?? (subtotal - amountPaid);
    final nights = stay.actualNights;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            _showBookingDetailsDrawer(context, stay, store, currencyFormat),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.slateBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Refined Room badge
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'ROOM',
                      style: GoogleFonts.inter(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.brandPrimary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      stay.room?.roomNumber ?? '—',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Guest Name, Dates, Nights & Room Type
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            stay.guest?.fullName ?? 'Unnamed Guest',
                            style: GoogleFonts.outfit(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slateDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (totalGuests > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFFBFDBFE),
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.people_alt_rounded,
                                  size: 10,
                                  color: Color(0xFF2563EB),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$totalGuests',
                                  style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF2563EB),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${DateFormat('d MMM').format(stay.checkInAt)} – ${DateFormat('d MMM').format(stay.checkOutAt ?? stay.expectedCheckOut)} • ${nights}n • ${stay.room?.categoryName ?? "Standard"}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.slateMuted,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Status & Financials
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusBorder, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: statusFg,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: GoogleFonts.inter(
                            color: statusFg,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currencyFormat.format(subtotal),
                    style: GoogleFonts.outfit(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.slateDark,
                    ),
                  ),
                  if (outstanding > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${currencyFormat.format(outstanding)} due',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    )
                  else
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Paid',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF16A34A),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppTheme.slateMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── COMPLETE BOOKING DETAIL DRAWER ──
  void _showBookingDetailsDrawer(
    BuildContext context,
    Stay stay,
    HotelStore store,
    NumberFormat currencyFormat,
  ) {
    Bill? bill;
    try {
      bill = store.bills.firstWhere((b) => b.stayId == stay.id);
    } catch (_) {
      bill = null;
    }

    final subtotal = bill?.subtotal ?? (stay.nightlyRate * stay.actualNights);
    final amountPaid = bill?.amountPaid ?? 0.0;
    final outstanding = bill?.outstanding ?? (subtotal - amountPaid);
    final totalGuests = stay.numGuests > 0
        ? stay.numGuests
        : (stay.numAdults + stay.numKids);

    // Status styling
    Color statusBg;
    Color statusFg;
    String statusLabel;
    if (stay.status == StayStatus.active) {
      statusBg = const Color(0xFFDCFCE7);
      statusFg = const Color(0xFF16A34A);
      statusLabel = 'In-House';
    } else if (stay.status == StayStatus.checkedOut) {
      statusBg = const Color(0xFFE0E7FF);
      statusFg = const Color(0xFF4338CA);
      statusLabel = 'Checked Out';
    } else {
      statusBg = const Color(0xFFFEF3C7);
      statusFg = const Color(0xFFD97706);
      statusLabel = 'Reserved';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (bottomSheetContext, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.slateDark,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Room ${stay.room?.roomNumber ?? "—"}',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      stay.room?.categoryName ?? 'Standard Room',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.slateMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(
                          color: statusFg,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(bottomSheetContext),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.8),

              // Scrollable Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    // ── SCHEDULE & DURATION CARD ──
                    Text(
                      'STAY DURATION & SCHEDULE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.slateBorder),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'CHECK-IN',
                                      style: GoogleFonts.inter(
                                        fontSize: 9.5,
                                        color: AppTheme.slateMuted,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      DateFormat(
                                        'd MMM yyyy, hh:mm a',
                                      ).format(stay.checkInAt),
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: AppTheme.slateMuted,
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'CHECK-OUT',
                                      style: GoogleFonts.inter(
                                        fontSize: 9.5,
                                        color: AppTheme.slateMuted,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      DateFormat('d MMM yyyy, hh:mm a').format(
                                        stay.checkOutAt ??
                                            stay.expectedCheckOut,
                                      ),
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20, thickness: 0.7),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildDrawerInfoItem(
                                'Duration',
                                '${stay.actualNights} Nights',
                                Icons.night_shelter_rounded,
                              ),
                              _buildDrawerInfoItem(
                                'Total Guests',
                                '$totalGuests Guests',
                                Icons.people_alt_rounded,
                              ),
                              _buildDrawerInfoItem(
                                'Nightly Rate',
                                currencyFormat.format(stay.nightlyRate),
                                Icons.sell_rounded,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── GUEST INFO (CLICKABLE FOR COMPLETE DETAILS) ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'GUEST INFORMATION',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateMuted,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Tap guest to view profile',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: AppTheme.brandPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Primary Guest Tile (Clickable)
                    InkWell(
                      onTap: () {
                        if (stay.guest != null) {
                          _showGuestProfileDialog(
                            context,
                            stay.guest!,
                            isPrimary: true,
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.slateBorder),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppTheme.brandPrimary,
                              child: Text(
                                stay.guest?.fullName.isNotEmpty == true
                                    ? stay.guest!.fullName[0].toUpperCase()
                                    : 'G',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
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
                                        stay.guest?.fullName ?? 'Primary Guest',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppTheme.slateDark,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.brandLight,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'Primary',
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.brandPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${stay.guest?.phone ?? "No phone"} • ${stay.guest?.idType.toUpperCase() ?? "ID"}: ${stay.guest?.displayIdNumber ?? "—"}',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppTheme.slateMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: AppTheme.slateMuted,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Co-Guests if any (Clickable)
                    if (stay.coGuests.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...stay.coGuests.map((cg) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: () => _showGuestProfileDialog(
                              context,
                              cg,
                              isPrimary: false,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.slateBorder),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppTheme.brandLight,
                                    child: Text(
                                      cg.fullName.isNotEmpty
                                          ? cg.fullName[0].toUpperCase()
                                          : 'C',
                                      style: GoogleFonts.outfit(
                                        color: AppTheme.brandPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cg.fullName,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: AppTheme.slateDark,
                                          ),
                                        ),
                                        Text(
                                          '${cg.phone.isNotEmpty ? cg.phone : "No phone"} • ${cg.idType.toUpperCase()}: ${cg.displayIdNumber}',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            color: AppTheme.slateMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 12,
                                    color: AppTheme.slateMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],

                    const SizedBox(height: 20),

                    // ── BILLING & FINANCIAL SUMMARY CARD ──
                    Text(
                      'BILLING & PAYMENTS',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.slateMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.slateBorder),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Room Charges (${stay.actualNights} nights × ${currencyFormat.format(stay.nightlyRate)})',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                              Text(
                                currencyFormat.format(subtotal),
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 18, thickness: 0.7),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Billed Tariff',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                              Text(
                                currencyFormat.format(subtotal),
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Amount Paid',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF16A34A),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                currencyFormat.format(amountPaid),
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF16A34A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Outstanding Balance',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: outstanding > 0
                                      ? Colors.redAccent
                                      : const Color(0xFF16A34A),
                                ),
                              ),
                              Text(
                                outstanding <= 0
                                    ? 'PAID'
                                    : currencyFormat.format(outstanding),
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: outstanding <= 0
                                      ? const Color(0xFF16A34A)
                                      : Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Drawer Footer Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppTheme.slateBorder)),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(bottomSheetContext);
                            _exportData([stay], store);
                          },
                          icon: const Icon(Icons.share_outlined, size: 16),
                          label: const Text('Export Excel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.slateDark,
                            side: const BorderSide(color: AppTheme.slateBorder),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      if (stay.status == StayStatus.active) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(bottomSheetContext);
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      BookingCheckOutScreen(stay: stay),
                                ),
                              );
                            },
                            icon: const Icon(Icons.output_rounded, size: 16),
                            label: const Text('Checkout'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.brandPrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── GUEST PROFILE DIALOG/SHEET (ACCESSED ONLY WHEN CLICKED) ──
  void _showGuestProfileDialog(
    BuildContext context,
    Guest guest, {
    required bool isPrimary,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isPrimary
                        ? AppTheme.brandPrimary
                        : AppTheme.slateMuted,
                    child: Text(
                      guest.fullName.isNotEmpty
                          ? guest.fullName[0].toUpperCase()
                          : 'G',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          guest.fullName,
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slateDark,
                          ),
                        ),
                        Text(
                          isPrimary ? 'Primary Guest' : 'Accompanying Guest',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: isPrimary
                                ? AppTheme.brandPrimary
                                : AppTheme.slateMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              _buildProfileDetailRow(
                'Phone Number',
                guest.phone.isNotEmpty ? guest.phone : 'Not provided',
                Icons.phone_rounded,
              ),
              if (guest.email != null && guest.email!.isNotEmpty)
                _buildProfileDetailRow(
                  'Email Address',
                  guest.email!,
                  Icons.email_rounded,
                ),
              _buildProfileDetailRow(
                'ID Document Type',
                guest.idType.toUpperCase(),
                Icons.badge_rounded,
              ),
              _buildProfileDetailRow(
                'ID Number',
                guest.displayIdNumber.isNotEmpty
                    ? guest.displayIdNumber
                    : 'Not provided',
                Icons.credit_card_rounded,
              ),
              if (guest.dateOfBirth != null && guest.dateOfBirth!.isNotEmpty)
                _buildProfileDetailRow(
                  'Date of Birth',
                  guest.dateOfBirth!,
                  Icons.cake_rounded,
                ),
              if (guest.gender != null && guest.gender!.isNotEmpty)
                _buildProfileDetailRow(
                  'Gender',
                  guest.gender!.toUpperCase(),
                  Icons.person_outline_rounded,
                ),
              if (guest.address != null && guest.address!.isNotEmpty)
                _buildProfileDetailRow(
                  'Residential Address',
                  '${guest.address!}${guest.pincode != null ? " - ${guest.pincode}" : ""}',
                  Icons.location_on_rounded,
                ),
              if (guest.fatherName != null && guest.fatherName!.isNotEmpty)
                _buildProfileDetailRow(
                  'Father / Guardian',
                  guest.fatherName!,
                  Icons.family_restroom_rounded,
                ),
              if (guest.notes != null && guest.notes!.isNotEmpty)
                _buildProfileDetailRow(
                  'Notes & Preferences',
                  guest.notes!,
                  Icons.notes_rounded,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppTheme.brandPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: AppTheme.slateMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slateDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerInfoItem(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.brandPrimary),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppTheme.slateMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.slateDark,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 36,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Bookings Found',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No reservations match your current date, room, or search filters. Try selecting "All Time" or reset filters.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _selectedPreset = DateFilterPreset.all;
                  _selectedRoomFilter = 'all';
                  _selectedStatusFilter = 'all';
                  _searchQuery = '';
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.slateDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Reset All Filters'),
            ),
          ],
        ),
      ),
    );
  }
}
