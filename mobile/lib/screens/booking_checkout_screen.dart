import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/stay.dart';
import '../models/bill.dart';
import '../models/room.dart';
import '../services/hotel_store.dart';
import '../services/whatsapp_service.dart';
import '../services/invoice_pdf_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable_scale.dart';

class BookingCheckOutScreen extends StatefulWidget {
  final Stay stay;
  const BookingCheckOutScreen({super.key, required this.stay});

  @override
  State<BookingCheckOutScreen> createState() => _BookingCheckOutScreenState();
}

class _BookingCheckOutScreenState extends State<BookingCheckOutScreen> {
  String _paymentMethod = 'upi';
  final TextEditingController _remarkController = TextEditingController();
  bool _remarkAdded = false;
  bool _sendWhatsAppMessage = true;

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  void _showAddRemarkDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
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
                  decoration: BoxDecoration(
                    color: AppTheme.slateBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add Remark',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Leave a note for housekeeping or management',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.slateMuted,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _remarkController,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText:
                      'e.g. Room needs deep cleaning, guest left early...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.slateMuted,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.slateBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.brandPrimary,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () {
                  setState(
                    () =>
                        _remarkAdded = _remarkController.text.trim().isNotEmpty,
                  );
                  Navigator.pop(ctx);
                  if (_remarkController.text.trim().isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Remark saved'),
                        backgroundColor: AppTheme.statusVacant,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Save Remark'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _getPdfBytes({
    required Stay stay,
    required Bill? bill,
    required double totalBilled,
    required double advancePaid,
    required double balancePaid,
    required double balanceDue,
    required Room? room,
  }) {
    final store = context.read<HotelStore>();
    return InvoicePdfService.generateInvoicePdf(
      property: store.currentProperty,
      stay: stay,
      bill: bill,
      totalBilled: totalBilled,
      advancePaid: advancePaid,
      balancePaid: balancePaid,
      balanceDue: balanceDue,
      room: room,
      paymentMethod: _paymentMethod,
    );
  }

  Future<void> _sharePdfInvoice({
    required Stay stay,
    required Bill? bill,
    required double totalBilled,
    required double advancePaid,
    required double balancePaid,
    required double balanceDue,
    required Room? room,
    required String invoiceNo,
  }) async {
    try {
      final pdfBytes = await _getPdfBytes(
        stay: stay,
        bill: bill,
        totalBilled: totalBilled,
        advancePaid: advancePaid,
        balancePaid: balancePaid,
        balanceDue: balanceDue,
        room: room,
      );
      await InvoicePdfService.shareInvoicePdf(
        pdfBytes: pdfBytes,
        fileName: 'Invoice_$invoiceNo.pdf',
        guestName: stay.guest?.fullName ?? 'Guest',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not share PDF: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _sendInvoicePdfViaWhatsApp({
    required Stay stay,
    required Bill? bill,
    required double totalBilled,
    required double advancePaid,
    required double balancePaid,
    required double balanceDue,
    required Room? room,
    required String invoiceNo,
  }) async {
    final phone = stay.guest?.phone;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No guest phone number available to send WhatsApp.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final store = context.read<HotelStore>();
      final df = DateFormat('dd MMM yyyy');
      final pdfBytes = await _getPdfBytes(
        stay: stay,
        bill: bill,
        totalBilled: totalBilled,
        advancePaid: advancePaid,
        balancePaid: balancePaid,
        balanceDue: balanceDue,
        room: room,
      );
      final pdfBase64 = InvoicePdfService.toBase64(pdfBytes);
      final fileName = 'Invoice_$invoiceNo.pdf';

      final success = await WhatsAppService.triggerCheckOut(
        guestName: stay.guest?.fullName ?? 'Valued Guest',
        phone: phone,
        hotelName: store.currentProperty.name,
        roomNumber: room?.roomNumber ?? stay.room?.roomNumber ?? '',
        checkInDate: df.format(stay.checkInAt),
        checkOutDate: df.format(stay.checkOutAt ?? DateTime.now()),
        stayId: stay.id,
        pdfBase64: pdfBase64,
        pdfFileName: fileName,
      );

      await InvoicePdfService.shareInvoicePdf(
        pdfBytes: pdfBytes,
        fileName: fileName,
        guestName: stay.guest?.fullName ?? 'Guest',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Invoice PDF dispatched via WhatsApp to ${stay.guest?.fullName}!'
                : 'Invoice PDF prepared for ${stay.guest?.fullName}!'),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error dispatching PDF: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _saveInvoicePdf({
    required Stay stay,
    required Bill? bill,
    required double totalBilled,
    required double advancePaid,
    required double balancePaid,
    required double balanceDue,
    required Room? room,
    required String invoiceNo,
  }) async {
    try {
      final pdfBytes = await _getPdfBytes(
        stay: stay,
        bill: bill,
        totalBilled: totalBilled,
        advancePaid: advancePaid,
        balancePaid: balancePaid,
        balanceDue: balanceDue,
        room: room,
      );
      final fileName = 'Invoice_$invoiceNo.pdf';
      final file = await InvoicePdfService.saveInvoicePdfToFile(
        pdfBytes: pdfBytes,
        fileName: fileName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF Invoice saved: ${file.path.split("/").last}'),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => InvoicePdfService.shareInvoicePdf(
                pdfBytes: pdfBytes,
                fileName: fileName,
                guestName: stay.guest?.fullName ?? 'Guest',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving PDF: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _printInvoicePdf({
    required Stay stay,
    required Bill? bill,
    required double totalBilled,
    required double advancePaid,
    required double balancePaid,
    required double balanceDue,
    required Room? room,
    required String invoiceNo,
  }) async {
    try {
      final pdfBytes = await _getPdfBytes(
        stay: stay,
        bill: bill,
        totalBilled: totalBilled,
        advancePaid: advancePaid,
        balancePaid: balancePaid,
        balanceDue: balanceDue,
        room: room,
      );
      await InvoicePdfService.printInvoicePdf(
        pdfBytes: pdfBytes,
        documentName: 'Invoice_$invoiceNo.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open print spooler: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showGenerateInvoice(Stay stay, Bill? bill, double roomTotal, {bool isFinalized = false}) {
    final store = context.read<HotelStore>();
    final property = store.currentProperty;
    final guest = stay.guest;
    final nights = stay.actualNights;
    final advancePaid = bill?.amountPaid ?? 0.0;

    final double totalBilled = isFinalized ? (bill?.subtotal ?? roomTotal) : roomTotal;
    final double balanceDue = isFinalized ? (bill?.outstanding ?? 0.0) : (roomTotal - advancePaid).clamp(0.0, roomTotal);
    final double balancePaid = isFinalized ? (totalBilled - advancePaid).clamp(0.0, totalBilled) : 0.0;

    final room = stay.room ??
        store.rooms.cast<Room?>().firstWhere((r) => r?.id == stay.roomId, orElse: () => null);

    final invoiceNo = bill != null && bill.billNumber.isNotEmpty && bill.billNumber != 'INV-DRAFT'
        ? bill.billNumber
        : 'INV-${DateTime.now().year}-${stay.id.replaceAll(RegExp(r'[^0-9]'), '').padLeft(4, '0')}';
    final issueDate = DateFormat('dd MMM yyyy, hh:mm a').format(bill?.createdAt ?? DateTime.now());
    final checkIn = DateFormat('dd MMM yyyy, hh:mm a').format(stay.checkInAt);
    final checkOut = DateFormat('dd MMM yyyy, hh:mm a').format(stay.checkOutAt ?? stay.expectedCheckOut);

    final baseAmount = (totalBilled / 1.12).round();
    final cgst = ((totalBilled / 1.12) * 0.06).round();
    final sgst = ((totalBilled / 1.12) * 0.06).round();

    final sheetFuture = showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.6,
        maxChildSize: 0.96,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle & top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 6),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.slateBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppTheme.brandLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            size: 18,
                            color: AppTheme.brandPrimary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tax Invoice & Guest Folio',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                              Text(
                                '${property.name} • Official GST Bill',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          color: AppTheme.slateMuted,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.slateBorder),

              // Scrollable Paper Invoice Card
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.slateBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Hotel Header & Status Badge
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      property.name,
                                      style: GoogleFonts.outfit(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${property.address}, ${property.city}, ${property.state} - ${property.pincode}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppTheme.slateMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'GSTIN: ${property.gstNumber}  •  Ph: ${property.phone}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppTheme.slateMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: balanceDue <= 0
                                      ? const Color(0xFFDCFCE7)
                                      : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: balanceDue <= 0
                                        ? const Color(0xFF86EFAC)
                                        : const Color(0xFFFDE68A),
                                  ),
                                ),
                                child: Text(
                                  balanceDue <= 0 ? 'PAID IN FULL' : 'PAYMENT DUE',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: balanceDue <= 0
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, color: AppTheme.slateBorder),

                          // 2. Invoice Meta & Guest Info
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'BILLED TO',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateMuted,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      guest?.fullName ?? 'Valued Guest',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      guest?.phone ?? 'No phone recorded',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppTheme.slateMuted,
                                      ),
                                    ),
                                    if (guest?.displayIdNumber != null &&
                                        guest!.displayIdNumber.isNotEmpty)
                                      Text(
                                        '${guest.idType.toUpperCase()}: ${guest.displayIdNumber}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppTheme.slateMuted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'INVOICE NO.',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateMuted,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      invoiceNo,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.brandPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Issued: $issueDate',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        color: AppTheme.slateMuted,
                                      ),
                                    ),
                                    Text(
                                      'Stay ID: #${stay.id.toUpperCase()}',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        color: AppTheme.slateMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // 3. Stay Details Banner
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Room ${room?.roomNumber ?? stay.room?.roomNumber ?? "N/A"} (${room?.categoryName ?? stay.room?.categoryName ?? "Standard"})',
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.slateDark,
                                      ),
                                    ),
                                    Text(
                                      '$nights Night${nights > 1 ? "s" : ""} · ${stay.guestSummary}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.brandPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'In: $checkIn',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        color: AppTheme.slateMuted,
                                      ),
                                    ),
                                    Text(
                                      'Out: $checkOut',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        color: AppTheme.slateMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 4. Itemized Charges Table
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    'PARTICULARS',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.slateMuted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'QTY',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.slateMuted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'RATE',
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.slateMuted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'AMOUNT',
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.slateMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Room Accommodation',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.slateDark,
                                        ),
                                      ),
                                      Text(
                                        'Room ${room?.roomNumber} (${room?.categoryName})',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppTheme.slateMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '$nights N',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '₹${stay.nightlyRate.toInt()}',
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    '₹${(stay.nightlyRate * nights).toInt()}',
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.slateDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 16, color: AppTheme.slateBorder),

                          // Tax Breakdown
                          _subDetailRow('Base Room Charges', '₹$baseAmount'),
                          _subDetailRow('CGST (6%)', '₹$cgst'),
                          _subDetailRow('SGST (6%)', '₹$sgst'),
                          _subDetailRow(
                            'Total Room Tariff (GST Inclusive)',
                            '₹${totalBilled.toInt()}',
                            isBold: true,
                          ),
                          const Divider(height: 16, color: AppTheme.slateBorder),

                          // Settlement Breakdown
                          _subDetailRow(
                            'Advance Deposit Received',
                            '-₹${advancePaid.toInt()}',
                            color: const Color(0xFF16A34A),
                          ),
                          if (balancePaid > 0)
                            _subDetailRow(
                              'Paid at Check-Out (${_paymentMethod.toUpperCase()})',
                              '-₹${balancePaid.toInt()}',
                              color: const Color(0xFF16A34A),
                            ),
                          const Divider(height: 16, color: AppTheme.slateBorder),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'NET BALANCE DUE',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.slateDark,
                                ),
                              ),
                              Text(
                                '₹${balanceDue.toInt()}',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: balanceDue > 0
                                      ? Colors.red.shade700
                                      : const Color(0xFF16A34A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Terms & Declaration
                          Text(
                            'Thank you for staying with us at ${property.name}!',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Official computer-generated GST tax invoice issued via EaseInn PMS.',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Action Buttons Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.slateBorder),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _sharePdfInvoice(
                                    stay: stay,
                                    bill: bill,
                                    totalBilled: totalBilled,
                                    advancePaid: advancePaid,
                                    balancePaid: balancePaid,
                                    balanceDue: balanceDue,
                                    room: room,
                                    invoiceNo: invoiceNo,
                                  ),
                                  icon: const Icon(Icons.share_rounded, size: 16),
                                  label: const Text('Share PDF'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.slateDark,
                                    side: const BorderSide(color: AppTheme.slateBorder),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _sendInvoicePdfViaWhatsApp(
                                    stay: stay,
                                    bill: bill,
                                    totalBilled: totalBilled,
                                    advancePaid: advancePaid,
                                    balancePaid: balancePaid,
                                    balanceDue: balanceDue,
                                    room: room,
                                    invoiceNo: invoiceNo,
                                  ),
                                  icon: const Icon(Icons.chat_rounded, size: 16),
                                  label: const Text('WhatsApp PDF'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _saveInvoicePdf(
                                    stay: stay,
                                    bill: bill,
                                    totalBilled: totalBilled,
                                    advancePaid: advancePaid,
                                    balancePaid: balancePaid,
                                    balanceDue: balanceDue,
                                    room: room,
                                    invoiceNo: invoiceNo,
                                  ),
                                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                                  label: const Text('Save PDF'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.slateDark,
                                    side: const BorderSide(color: AppTheme.slateBorder),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _printInvoicePdf(
                                    stay: stay,
                                    bill: bill,
                                    totalBilled: totalBilled,
                                    advancePaid: advancePaid,
                                    balancePaid: balancePaid,
                                    balanceDue: balanceDue,
                                    room: room,
                                    invoiceNo: invoiceNo,
                                  ),
                                  icon: const Icon(Icons.print_rounded, size: 16),
                                  label: const Text('Print PDF'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.brandPrimary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isFinalized) {
      sheetFuture.then((_) {
        if (mounted) {
          Navigator.pop(context, true);
        }
      });
    }
  }

  Widget _subDetailRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? AppTheme.slateDark : AppTheme.slateMuted,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _invoiceRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: color ?? AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmCheckout(
    HotelStore store,
    Stay stay,
    Bill? bill,
    double balanceDue,
  ) {
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
            Text(
              'Confirm Check-Out',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select payment method for balance due',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 16),
            // Payment method selector
            if (balanceDue > 0) ...[
              Text(
                'Balance Due: ₹${balanceDue.toInt()}',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _payMethodChip(
                    'upi',
                    'UPI',
                    Icons.qr_code_scanner_rounded,
                    ctx,
                  ),
                  const SizedBox(width: 8),
                  _payMethodChip('cash', 'Cash', Icons.payments_rounded, ctx),
                  const SizedBox(width: 8),
                  _payMethodChip(
                    'card',
                    'Card',
                    Icons.credit_card_rounded,
                    ctx,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.statusVacantBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.statusVacant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'All dues cleared! ₹0 balance.',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.statusVacant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _sendWhatsAppMessage ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _sendWhatsAppMessage ? const Color(0xFFBBF7D0) : AppTheme.slateBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_rounded,
                      size: 16,
                      color: _sendWhatsAppMessage ? const Color(0xFF16A34A) : AppTheme.slateMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Send WhatsApp Thank-You & Bill',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateDark,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: _sendWhatsAppMessage,
                      activeTrackColor: const Color(0xFF16A34A),
                      activeThumbColor: Colors.white,
                      onChanged: (val) {
                        setState(() => _sendWhatsAppMessage = val);
                        (ctx as Element).markNeedsBuild();
                      },
                    ),
                  ],
                ),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () async {
                Navigator.pop(ctx);

                String? pdfBase64;
                String? pdfFileName;
                final room = stay.room ??
                    store.rooms.cast<Room?>().firstWhere(
                          (r) => r?.id == stay.roomId,
                          orElse: () => null,
                        );
                final totalBilled =
                    bill?.subtotal ?? (stay.actualNights * stay.nightlyRate);
                final advancePaid = bill?.amountPaid ?? 0.0;
                final balancePaid =
                    (totalBilled - advancePaid).clamp(0.0, totalBilled);
                final invoiceNo = bill != null &&
                        bill.billNumber.isNotEmpty &&
                        bill.billNumber != 'INV-DRAFT'
                    ? bill.billNumber
                    : 'INV-${DateTime.now().year}-${stay.id.replaceAll(RegExp(r'[^0-9]'), '').padLeft(4, '0')}';

                try {
                  final pdfBytes = await InvoicePdfService.generateInvoicePdf(
                    property: store.currentProperty,
                    stay: stay,
                    bill: bill,
                    totalBilled: totalBilled,
                    advancePaid: advancePaid,
                    balancePaid: balancePaid,
                    balanceDue: balanceDue,
                    room: room,
                    paymentMethod: _paymentMethod,
                  );
                  pdfBase64 = InvoicePdfService.toBase64(pdfBytes);
                  pdfFileName = 'Invoice_$invoiceNo.pdf';
                } catch (e) {
                  debugPrint('Could not pre-generate PDF for checkout hook: $e');
                }

                final finalBill = store.checkOutGuest(
                  stayId: stay.id,
                  paymentAmount: balanceDue,
                  paymentMethod: _paymentMethod,
                  sendWhatsApp: _sendWhatsAppMessage,
                  pdfBase64: pdfBase64,
                  pdfFileName: pdfFileName,
                );
                if (mounted) {
                  _showSuccessDialog(stay, finalBill);
                }
              },
              child: Text(
                'Confirm Check-Out',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _payMethodChip(
    String value,
    String label,
    IconData icon,
    BuildContext ctx,
  ) {
    final isSelected = _paymentMethod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _paymentMethod = value);
          (ctx as Element).markNeedsBuild();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.brandLight : AppTheme.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.brandPrimary : AppTheme.slateBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? AppTheme.brandPrimary : AppTheme.slateMuted,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? AppTheme.brandPrimary
                      : AppTheme.slateMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessDialog(Stay stay, Bill finalBill) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppTheme.statusVacantBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.statusVacant,
                  size: 40,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Checked Out!',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${stay.guest?.fullName} — Room ${stay.room?.roomNumber}\nFolio settled. Room flagged for cleaning.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.slateMuted,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: Column(
                  children: [
                    _invoiceRow('Invoice', finalBill.billNumber),
                    _invoiceRow(
                      'Total Billed',
                      '₹${finalBill.subtotal.toInt()}',
                    ),
                    _invoiceRow(
                      'Total Paid',
                      '₹${finalBill.amountPaid.toInt()}',
                    ),
                    _invoiceRow(
                      'Outstanding',
                      '₹${finalBill.outstanding.toInt()}',
                      bold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showGenerateInvoice(
                          stay,
                          finalBill,
                          finalBill.subtotal,
                          isFinalized: true,
                        );
                      },
                      icon: const Icon(Icons.receipt_long_rounded, size: 14),
                      label: const Text(
                        'View / Share Folio',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.slateDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: const BorderSide(color: AppTheme.slateBorder),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pop(
                          context,
                          true,
                        ); // Return true to refresh checkout list
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.slateDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();

    // Get latest stay from store (in case it was updated)
    Stay? stay;
    try {
      stay = store.activeStays.firstWhere((s) => s.id == widget.stay.id);
    } catch (_) {
      stay = null;
    }

    if (stay == null) {
      // Stay no longer active — already checked out
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Check-Out',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.done_all_rounded,
                size: 56,
                color: AppTheme.statusVacant,
              ),
              const SizedBox(height: 12),
              Text(
                'Already Checked Out',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.slateDark,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Bill? bill;
    try {
      bill = store.bills.firstWhere((b) => b.stayId == stay!.id);
    } catch (_) {}

    final nights = stay.actualNights;
    final roomTotal = nights * stay.nightlyRate;
    final advancePaid = bill?.amountPaid ?? 0.0;
    final balanceDue = (roomTotal - advancePaid).clamp(0.0, roomTotal);
    final amountDue = balanceDue;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Check-Out',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: AppTheme.slateDark,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.slateBorder),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Guest & Room Info Card ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFEEEEFF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Room ${stay.room?.roomNumber}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.brandPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stay.guest?.fullName ?? 'Guest',
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Amount Due',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.slateMuted,
                            ),
                          ),
                          Text(
                            '₹${amountDue.toInt()}',
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: amountDue > 0
                                  ? AppTheme.brandPrimary
                                  : AppTheme.statusVacant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _roomInfoRow(
                    Icons.dark_mode_rounded,
                    '$nights night${nights > 1 ? "s" : ""}',
                  ),
                  _roomInfoRow(
                    Icons.login_rounded,
                    'Check-In: ${DateFormat('d MMM yyyy, hh:mm a').format(stay.checkInAt)}',
                  ),
                  const SizedBox(height: 4),
                  _roomInfoRow(
                    Icons.logout_rounded,
                    'Check-Out: ${DateFormat('d MMM yyyy, hh:mm a').format(stay.expectedCheckOut)}',
                  ),
                  const SizedBox(height: 4),
                  _roomInfoRow(Icons.people_rounded, stay.guestSummary),
                  if (stay.coGuests.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _roomInfoRow(
                      Icons.group_rounded,
                      '+ ${stay.coGuests.map((g) => g.fullName).join(", ")}',
                    ),
                  ],
                  const SizedBox(height: 4),
                  _roomInfoRow(
                    Icons.hotel_rounded,
                    '${stay.room?.categoryName} • Floor ${stay.room?.floor ?? "-"}',
                  ),
                  const SizedBox(height: 14),
                  // Billing breakdown
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _billingRow(
                          'Rate/Night',
                          '₹${stay.nightlyRate.toInt()}',
                        ),
                        _billingRow(
                          'Total (${nights}N)',
                          '₹${roomTotal.toInt()}',
                        ),
                        _billingRow('Advance Paid', '-₹${advancePaid.toInt()}'),
                        const Divider(height: 10, color: AppTheme.slateBorder),
                        _billingRow(
                          'Balance Due',
                          '₹${amountDue.toInt()}',
                          bold: true,
                          color: amountDue > 0
                              ? Colors.red.shade600
                              : AppTheme.statusVacant,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () =>
                        _showGenerateInvoice(stay!, bill, roomTotal),
                    style: TextButton.styleFrom(
                      backgroundColor: AppTheme.brandPrimary.withValues(
                        alpha: 0.12,
                      ),
                      foregroundColor: AppTheme.brandPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      'View Full Details',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // ── Quick Actions ───────────────────────────────────────────────
            Text(
              'Quick Actions',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              label: 'Generate Invoice',
              icon: Icons.receipt_long_rounded,
              onTap: () => _showGenerateInvoice(stay!, bill, roomTotal),
            ),
            const SizedBox(height: 10),
            _buildActionButton(
              label: _remarkAdded ? 'Remark Added ✓' : 'Add Remarks',
              icon: _remarkAdded
                  ? Icons.check_circle_rounded
                  : Icons.comment_rounded,
              onTap: _showAddRemarkDialog,
              highlight: _remarkAdded,
            ),
            const SizedBox(height: 24),

            // ── Confirm Check-Out Button ────────────────────────────────────
            PressableScale(
              onTap: () => _confirmCheckout(store, stay!, bill, balanceDue),
              pressedScale: 0.96,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.brandPrimary, AppTheme.brandAccent],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.logout_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Confirm Check-Out',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _roomInfoRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.slateMuted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateCard),
          ),
        ),
      ],
    );
  }

  Widget _billingRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: color ?? AppTheme.slateDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: highlight ? AppTheme.statusVacantBg : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlight ? AppTheme.statusVacant : AppTheme.slateBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: highlight ? AppTheme.statusVacant : AppTheme.slateDark,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: highlight ? AppTheme.statusVacant : AppTheme.slateDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
