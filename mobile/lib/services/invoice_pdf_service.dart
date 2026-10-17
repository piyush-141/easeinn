import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/bill.dart';
import '../models/property.dart';
import '../models/room.dart';
import '../models/stay.dart';

class InvoicePdfService {
  /// Generate a clean, detailed, Apple-minimalist PDF invoice document.
  static Future<Uint8List> generateInvoicePdf({
    required Property property,
    required Stay stay,
    required Bill? bill,
    required double totalBilled,
    required double advancePaid,
    required double balancePaid,
    required double balanceDue,
    required Room? room,
    required String paymentMethod,
  }) async {
    final pdf = pw.Document();

    final guest = stay.guest;
    final nights = stay.actualNights;
    final baseAmount = (totalBilled / 1.12).round();
    final cgst = ((totalBilled / 1.12) * 0.06).round();
    final sgst = ((totalBilled / 1.12) * 0.06).round();

    final invoiceNo = bill != null &&
            bill.billNumber.isNotEmpty &&
            bill.billNumber != 'INV-DRAFT'
        ? bill.billNumber
        : 'INV-${DateTime.now().year}-${stay.id.replaceAll(RegExp(r'[^0-9]'), '').padLeft(4, '0')}';

    final issueDate = DateFormat('dd MMM yyyy, hh:mm a').format(
      bill?.createdAt ?? DateTime.now(),
    );
    final checkIn = DateFormat('dd MMM yyyy, hh:mm a').format(stay.checkInAt);
    final checkOut = DateFormat('dd MMM yyyy, hh:mm a').format(
      stay.checkOutAt ?? stay.expectedCheckOut,
    );

    // Color definitions
    final darkSlate = PdfColor.fromHex('#0F172A');
    final mutedSlate = PdfColor.fromHex('#64748B');
    final borderSlate = PdfColor.fromHex('#E2E8F0');
    final bgLight = PdfColor.fromHex('#F8FAFC');
    final brandPrimary = PdfColor.fromHex('#1E293B');
    final successGreen = PdfColor.fromHex('#15803D');
    final successBg = PdfColor.fromHex('#DCFCE7');
    final successBorder = PdfColor.fromHex('#86EFAC');
    final warningAmber = PdfColor.fromHex('#B45309');
    final warningBg = PdfColor.fromHex('#FEF3C7');
    final warningBorder = PdfColor.fromHex('#FDE68A');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ── 1. Top Hotel Header & Invoice Badge ────────────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          property.name,
                          style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: darkSlate,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          '${property.address}, ${property.city}, ${property.state} - ${property.pincode}',
                          style: pw.TextStyle(fontSize: 9.5, color: mutedSlate),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'GSTIN: ${property.gstNumber}  |  Ph: ${property.phone}  |  ${property.email}',
                          style: pw.TextStyle(
                            fontSize: 9.5,
                            color: mutedSlate,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: pw.BoxDecoration(
                          color: balanceDue <= 0 ? successBg : warningBg,
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(12),
                          ),
                          border: pw.Border.all(
                            color: balanceDue <= 0
                                ? successBorder
                                : warningBorder,
                            width: 0.8,
                          ),
                        ),
                        child: pw.Text(
                          balanceDue <= 0 ? 'PAID IN FULL' : 'PAYMENT DUE',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: balanceDue <= 0
                                ? successGreen
                                : warningAmber,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'TAX INVOICE',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: brandPrimary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      pw.Text(
                        '#$invoiceNo',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: darkSlate,
                        ),
                      ),
                      pw.Text(
                        'Date: $issueDate',
                        style: pw.TextStyle(fontSize: 8.5, color: mutedSlate),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 14),
              pw.Divider(thickness: 1, color: borderSlate),
              pw.SizedBox(height: 10),

              // ── 2. Guest Info & Stay Details (2-Column Card) ───────────────
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: bgLight,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8),
                  ),
                  border: pw.Border.all(color: borderSlate, width: 0.8),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Left: Guest Info
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'BILLED TO (GUEST)',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: mutedSlate,
                              letterSpacing: 0.6,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            guest?.fullName ?? 'Valued Guest',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: darkSlate,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Phone: ${guest?.phone ?? "N/A"}',
                            style: pw.TextStyle(
                              fontSize: 9,
                              color: darkSlate,
                            ),
                          ),
                          if (guest?.email != null &&
                              guest!.email!.trim().isNotEmpty)
                            pw.Text(
                              'Email: ${guest.email}',
                              style: pw.TextStyle(
                                fontSize: 9,
                                color: darkSlate,
                              ),
                            ),
                          if (guest?.displayIdNumber != null &&
                              guest!.displayIdNumber.isNotEmpty)
                            pw.Text(
                              'ID: ${guest.idType.toUpperCase()} - ${guest.displayIdNumber}',
                              style: pw.TextStyle(
                                fontSize: 9,
                                color: darkSlate,
                              ),
                            ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    // Right: Stay Info
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'STAY & RESERVATION DETAILS',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: mutedSlate,
                              letterSpacing: 0.6,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Room ${room?.roomNumber ?? stay.room?.roomNumber ?? "N/A"} (${room?.categoryName ?? stay.room?.categoryName ?? "Standard"})',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: darkSlate,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Duration: $nights Night${nights > 1 ? "s" : ""}  |  ${stay.guestSummary}',
                            style: pw.TextStyle(
                              fontSize: 9,
                              color: darkSlate,
                            ),
                          ),
                          pw.Text(
                            'Check-In:  $checkIn',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              color: mutedSlate,
                            ),
                          ),
                          pw.Text(
                            'Check-Out: $checkOut',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              color: mutedSlate,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 14),

              // ── 3. Itemized Particulars Table ─────────────────────────────
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderSlate, width: 0.8),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                ),
                child: pw.Column(
                  children: [
                    // Table Header
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      color: PdfColor.fromHex('#F1F5F9'),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            flex: 5,
                            child: pw.Text(
                              'DESCRIPTION',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: mutedSlate,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              'QTY',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: mutedSlate,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              'RATE (Rs.)',
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: mutedSlate,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              'AMOUNT (Rs.)',
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: mutedSlate,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Divider(thickness: 0.8, color: borderSlate, height: 1),
                    // Table Row 1: Accommodation
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            flex: 5,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'Room Accommodation',
                                  style: pw.TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: darkSlate,
                                  ),
                                ),
                                pw.Text(
                                  'Room ${room?.roomNumber ?? stay.room?.roomNumber ?? ""} - ${room?.categoryName ?? stay.room?.categoryName ?? "Standard Room"}',
                                  style: pw.TextStyle(
                                    fontSize: 8.5,
                                    color: mutedSlate,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              '$nights Night${nights > 1 ? "s" : ""}',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                fontSize: 9,
                                color: darkSlate,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              'Rs. ${stay.nightlyRate.toInt()}',
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                fontSize: 9,
                                color: darkSlate,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              'Rs. ${(stay.nightlyRate * nights).toInt()}',
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                                color: darkSlate,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 12),

              // ── 4. Tax & Settlement Summary ───────────────────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left note / Bank details
                  pw.Expanded(
                    flex: 3,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: bgLight,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(6),
                        ),
                        border: pw.Border.all(color: borderSlate, width: 0.8),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'PAYMENT & BANKING DETAILS',
                            style: pw.TextStyle(
                              fontSize: 7.5,
                              fontWeight: pw.FontWeight.bold,
                              color: mutedSlate,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Payee: ${property.upiPayeeName}',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              color: darkSlate,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'UPI VPA: ${property.upiId}',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              color: darkSlate,
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            'Remarks: Folio settled upon check-out via ${paymentMethod.toUpperCase()}.',
                            style: pw.TextStyle(
                              fontSize: 8,
                              color: mutedSlate,
                              fontStyle: pw.FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 14),
                  // Right financial rows
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      children: [
                        _summaryRow(
                          'Base Room Tariff (Taxable)',
                          'Rs. $baseAmount',
                          darkSlate,
                        ),
                        _summaryRow(
                          'CGST (6.0%)',
                          'Rs. $cgst',
                          mutedSlate,
                        ),
                        _summaryRow(
                          'SGST (6.0%)',
                          'Rs. $sgst',
                          mutedSlate,
                        ),
                        pw.Divider(thickness: 0.8, color: borderSlate, height: 8),
                        _summaryRow(
                          'Total Invoice Amount (GST Incl.)',
                          'Rs. ${totalBilled.toInt()}',
                          darkSlate,
                          isBold: true,
                        ),
                        _summaryRow(
                          'Advance Deposit Received',
                          '(-) Rs. ${advancePaid.toInt()}',
                          successGreen,
                        ),
                        if (balancePaid > 0)
                          _summaryRow(
                            'Settlement (${paymentMethod.toUpperCase()})',
                            '(-) Rs. ${balancePaid.toInt()}',
                            successGreen,
                          ),
                        pw.Divider(thickness: 1, color: borderSlate, height: 8),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          decoration: pw.BoxDecoration(
                            color: balanceDue <= 0 ? successBg : warningBg,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'NET BALANCE DUE',
                                style: pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: balanceDue <= 0
                                      ? successGreen
                                      : warningAmber,
                                ),
                              ),
                              pw.Text(
                                'Rs. ${balanceDue.toInt()}',
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                  color: balanceDue <= 0
                                      ? successGreen
                                      : warningAmber,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              pw.Spacer(),

              // ── 5. Terms, Conditions & Footer ─────────────────────────────
              pw.Divider(thickness: 0.8, color: borderSlate),
              pw.SizedBox(height: 6),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Terms & Conditions:',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: darkSlate,
                          ),
                        ),
                        pw.Text(
                          '1. All tariffs are inclusive of Goods & Services Tax (GST). All disputes subject to local jurisdiction.',
                          style: pw.TextStyle(fontSize: 7, color: mutedSlate),
                        ),
                        pw.Text(
                          '2. Check-out time is strictly ${property.defaultCheckOutTime}. Late check-out is subject to prior availability.',
                          style: pw.TextStyle(fontSize: 7, color: mutedSlate),
                        ),
                        pw.Text(
                          '3. This is an authentic computer-generated GST tax invoice issued via EaseInn PMS and requires no signature.',
                          style: pw.TextStyle(fontSize: 7, color: mutedSlate),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Thank you for staying with us!',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: darkSlate,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                      pw.Text(
                        'EaseInn PMS • Verified Property Management System',
                        style: pw.TextStyle(fontSize: 7, color: mutedSlate),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _summaryRow(
    String label,
    String value,
    PdfColor color, {
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Save PDF file to temporary or documents storage
  static Future<File> saveInvoicePdfToFile({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(pdfBytes, flush: true);
    return file;
  }

  /// Print or open standard Android/iOS print spooler preview
  static Future<void> printInvoicePdf({
    required Uint8List pdfBytes,
    required String documentName,
  }) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: documentName,
    );
  }

  /// Share straight PDF document to WhatsApp, email, or any app
  static Future<void> shareInvoicePdf({
    required Uint8List pdfBytes,
    required String fileName,
    required String guestName,
  }) async {
    final file = await saveInvoicePdfToFile(
      pdfBytes: pdfBytes,
      fileName: fileName,
    );

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'application/pdf',
          name: fileName,
        ),
      ],
      subject: 'Tax Invoice - $guestName',
      text: 'Official Tax Invoice & Guest Folio for $guestName',
    );
  }

  /// Base64 representation of PDF bytes for sending via API / WhatsApp backend
  static String toBase64(Uint8List pdfBytes) {
    return base64Encode(pdfBytes);
  }
}
