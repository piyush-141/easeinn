import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/stay.dart';
import '../models/bill.dart';
import '../services/hotel_store.dart';
import '../theme/app_theme.dart';

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

  void _showGenerateInvoice(Stay stay, Bill? bill, double roomTotal) {
    final nights = stay.actualNights;
    final advancePaid = bill?.amountPaid ?? 0.0;
    final balance = (roomTotal - advancePaid).clamp(0.0, roomTotal);

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
            // Invoice header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.brandPrimary, AppTheme.brandAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'INVOICE',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        bill?.billNumber ?? 'INV-DRAFT',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.read<HotelStore>().currentProperty.name,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Invoice rows
            _invoiceRow('Guest', stay.guest?.fullName ?? 'Guest'),
            _invoiceRow(
              'Room',
              '${stay.room?.roomNumber} (${stay.room?.categoryName})',
            ),
            _invoiceRow(
              'Check-In',
              DateFormat('d MMM yyyy, hh:mm a').format(stay.checkInAt),
            ),
            _invoiceRow(
              'Check-Out',
              DateFormat('d MMM yyyy, hh:mm a').format(stay.expectedCheckOut),
            ),
            _invoiceRow('Duration', '$nights night${nights > 1 ? "s" : ""}'),
            _invoiceRow('Rate/Night', '₹${stay.nightlyRate.toInt()}'),
            const Divider(color: AppTheme.slateBorder),
            _invoiceRow('Subtotal', '₹${roomTotal.toInt()}', bold: true),
            _invoiceRow('Advance Paid', '₹${advancePaid.toInt()}'),
            const Divider(color: AppTheme.slateBorder),
            _invoiceRow(
              'Balance Due',
              '₹${balance.toInt()}',
              bold: true,
              color: balance > 0 ? Colors.red.shade600 : AppTheme.statusVacant,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invoice printed/shared 🖨️')),
                );
              },
              icon: const Icon(Icons.print_rounded, size: 16),
              label: const Text('Print / Share Invoice'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.brandPrimary),
                foregroundColor: AppTheme.brandPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                final finalBill = store.checkOutGuest(
                  stayId: stay.id,
                  paymentAmount: balanceDue,
                  paymentMethod: _paymentMethod,
                );
                _showSuccessDialog(stay, finalBill);
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invoice printed 🖨️')),
                        );
                      },
                      icon: const Icon(Icons.print_rounded, size: 14),
                      label: const Text(
                        'Print',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
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
            GestureDetector(
              onTap: () => _confirmCheckout(store, stay!, bill, balanceDue),
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
    return GestureDetector(
      onTap: onTap,
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
