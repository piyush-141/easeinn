import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
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
  /// Generate a clean, editorial, minimal PDF invoice document matching reference aesthetics.
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
    final successGreen = PdfColor.fromHex('#15803D');
    final successBg = PdfColor.fromHex('#DCFCE7');
    final successBorder = PdfColor.fromHex('#86EFAC');
    final warningAmber = PdfColor.fromHex('#B45309');
    final warningBg = PdfColor.fromHex('#FEF3C7');
    final warningBorder = PdfColor.fromHex('#FDE68A');

    // Load panoramic scenic header banner if available
    Uint8List? bannerBytes;
    try {
      final byteData = await rootBundle.load('assets/images/invoice_banner.jpg');
      bannerBytes = byteData.buffer.asUint8List();
    } catch (_) {}

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 30),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ── 1. Top Panoramic Header Banner ─────────────────────────────
              if (bannerBytes != null)
                pw.ClipRRect(
                  horizontalRadius: 10,
                  verticalRadius: 10,
                  child: pw.Image(
                    pw.MemoryImage(bannerBytes),
                    height: 100,
                    fit: pw.BoxFit.cover,
                  ),
                )
              else
                pw.Container(
                  height: 100,
                  decoration: pw.BoxDecoration(
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                    gradient: pw.LinearGradient(
                      colors: [
                        PdfColor.fromHex('#E2E8F0'),
                        PdfColor.fromHex('#F8FAFC'),
                      ],
                    ),
                  ),
                ),

              pw.SizedBox(height: 16),

              // ── 2. Brand Monogram, INVOICE title & Status ──────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Monogram Icon
                      pw.Container(
                        width: 32,
                        height: 32,
                        decoration: pw.BoxDecoration(
                          color: darkSlate,
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(8),
                          ),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            property.name.isNotEmpty ? property.name[0].toUpperCase() : 'E',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      pw.Text(
                        'INVOICE',
                        style: pw.TextStyle(
                          fontSize: 30,
                          fontWeight: pw.FontWeight.bold,
                          color: darkSlate,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        '#$invoiceNo',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: darkSlate,
                        ),
                      ),
                      pw.SizedBox(height: 6),
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
                            color: balanceDue <= 0 ? successBorder : warningBorder,
                            width: 0.8,
                          ),
                        ),
                        child: pw.Text(
                          balanceDue <= 0 ? 'PAID IN FULL' : 'PAYMENT DUE',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: balanceDue <= 0 ? successGreen : warningAmber,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 18),

              // ── 3. Clean 3-Column Metadata (FROM, BILL TO, DATES) ──────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Column 1: FROM
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'FROM',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: mutedSlate,
                            letterSpacing: 0.8,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          property.name,
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: darkSlate,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        if (property.email.isNotEmpty)
                          pw.Text(
                            property.email,
                            style: pw.TextStyle(fontSize: 8.5, color: mutedSlate),
                          ),
                        pw.Text(
                          '${property.address}, ${property.city}',
                          style: pw.TextStyle(fontSize: 8.5, color: mutedSlate),
                        ),
                        pw.Text(
                          '${property.state} - ${property.pincode}',
                          style: pw.TextStyle(fontSize: 8.5, color: mutedSlate),
                        ),
                        if (property.phone.isNotEmpty)
                          pw.Text(
                            'Ph: ${property.phone}',
                            style: pw.TextStyle(fontSize: 8.5, color: mutedSlate),
                          ),
                        if (property.gstNumber.isNotEmpty)
                          pw.Text(
                            'GSTIN: ${property.gstNumber}',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              color: darkSlate,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 14),

                  // Column 2: BILL TO
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'BILL TO',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: mutedSlate,
                            letterSpacing: 0.8,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          guest?.fullName ?? 'Valued Guest',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: darkSlate,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        if (guest != null && guest.email != null && guest.email!.trim().isNotEmpty)
                          pw.Text(
                            guest.email!,
                            style: pw.TextStyle(fontSize: 8.5, color: mutedSlate),
                          ),
                        if (guest != null && guest.phone.trim().isNotEmpty)
                          pw.Text(
                            guest.phone,
                            style: pw.TextStyle(fontSize: 8.5, color: mutedSlate),
                          ),
                        pw.Text(
                          'Room: ${room?.roomNumber ?? stay.room?.roomNumber ?? "N/A"} (${room?.categoryName ?? stay.room?.categoryName ?? "Standard"})',
                          style: pw.TextStyle(fontSize: 8.5, color: mutedSlate),
                        ),
                        if (guest != null && guest.displayIdNumber.isNotEmpty)
                          pw.Text(
                            '${guest.idType.toUpperCase()}: ${guest.displayIdNumber}',
                            style: pw.TextStyle(fontSize: 8.5, color: mutedSlate),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 14),

                  // Column 3: DATES (Right aligned)
                  pw.Expanded(
                    flex: 3,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'ISSUED',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: mutedSlate,
                            letterSpacing: 0.8,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          issueDate,
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            color: darkSlate,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'CHECK-IN',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: mutedSlate,
                            letterSpacing: 0.8,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          checkIn,
                          style: pw.TextStyle(fontSize: 8.5, color: darkSlate),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'CHECK-OUT',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: mutedSlate,
                            letterSpacing: 0.8,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          checkOut,
                          style: pw.TextStyle(fontSize: 8.5, color: darkSlate),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 22),

              // ── 4. Itemized Particulars Table ─────────────────────────────
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: borderSlate, width: 0.8),
                    bottom: pw.BorderSide(color: borderSlate, width: 0.8),
                  ),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: pw.Text(
                        'DESCRIPTION',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: mutedSlate,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'QTY',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: mutedSlate,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'RATE (Rs.)',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: mutedSlate,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'AMOUNT (Rs.)',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: mutedSlate,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Table Row
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
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
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Room ${room?.roomNumber ?? stay.room?.roomNumber ?? ""} · ${room?.categoryName ?? stay.room?.categoryName ?? "Standard Room"}',
                            style: pw.TextStyle(
                              fontSize: 8,
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
                        style: pw.TextStyle(fontSize: 8.5, color: darkSlate),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'Rs. ${stay.nightlyRate.toInt()}',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: 8.5, color: darkSlate),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'Rs. ${(stay.nightlyRate * nights).toInt()}',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: darkSlate,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              pw.Divider(thickness: 0.8, color: borderSlate),

              pw.SizedBox(height: 8),

              // ── 5. Financial Summary (Right-Aligned) ───────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.SizedBox(
                    width: 220,
                    child: pw.Column(
                      children: [
                        _summaryRow('Subtotal (Taxable)', 'Rs. $baseAmount', darkSlate),
                        _summaryRow('Tax (12% GST)', 'Rs. ${cgst + sgst}', mutedSlate),
                        pw.SizedBox(height: 3),
                        pw.Divider(thickness: 0.8, color: borderSlate),
                        pw.SizedBox(height: 3),
                        _summaryRow(
                          'Total',
                          'Rs. ${totalBilled.toInt()}',
                          darkSlate,
                          isBold: true,
                          fontSize: 9.5,
                        ),
                        if (advancePaid > 0)
                          _summaryRow(
                            'Advance Deposit',
                            '(-) Rs. ${advancePaid.toInt()}',
                            successGreen,
                          ),
                        if (balancePaid > 0)
                          _summaryRow(
                            'Paid at Check-Out (${paymentMethod.toUpperCase()})',
                            '(-) Rs. ${balancePaid.toInt()}',
                            successGreen,
                          ),
                        pw.SizedBox(height: 3),
                        pw.Divider(thickness: 0.8, color: borderSlate),
                        pw.SizedBox(height: 3),
                        _summaryRow(
                          'Balance Due',
                          'Rs. ${balanceDue.toInt()}',
                          balanceDue <= 0 ? successGreen : warningAmber,
                          isBold: true,
                          fontSize: 10.5,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              pw.Spacer(),

              // ── 6. Bottom Payment Details & Notes ─────────────────────────
              pw.Divider(thickness: 0.8, color: borderSlate),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'PAYMENT DETAILS',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: mutedSlate,
                            letterSpacing: 0.6,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Method: ${paymentMethod.toUpperCase()}',
                          style: pw.TextStyle(fontSize: 8, color: darkSlate),
                        ),
                        if (property.upiPayeeName.isNotEmpty)
                          pw.Text(
                            'Payee: ${property.upiPayeeName}',
                            style: pw.TextStyle(fontSize: 8, color: darkSlate),
                          ),
                        if (property.upiId.isNotEmpty)
                          pw.Text(
                            'UPI ID: ${property.upiId}',
                            style: pw.TextStyle(fontSize: 8, color: darkSlate),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'NOTES',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: mutedSlate,
                            letterSpacing: 0.6,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Thank you for staying at ${property.name}!',
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: darkSlate,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        ),
                        pw.Text(
                          'Official computer-generated GST tax invoice issued via EaseInn PMS.',
                          style: pw.TextStyle(fontSize: 7, color: mutedSlate),
                        ),
                      ],
                    ),
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
    double fontSize = 8.5,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isBold ? PdfColor.fromHex('#0F172A') : PdfColor.fromHex('#64748B'),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static const _downloadsChannel = MethodChannel('com.easeinn.mobile/downloads');

  /// Save PDF file to public Downloads (on Android) and return a local File
  static Future<File> saveInvoicePdfToFile({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    // 1. Write to local cache/documents so Share & local viewers have a direct File path
    final tempDir = await getTemporaryDirectory();
    final localFile = File('${tempDir.path}/$fileName');
    await localFile.writeAsBytes(pdfBytes, flush: true);

    // 2. Save directly to Android public Downloads via MediaStore so it appears in the Downloads app
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _downloadsChannel.invokeMethod<String>('saveToDownloads', {
          'fileName': fileName,
          'mimeType': 'application/pdf',
          'bytes': pdfBytes,
        });
      } catch (_) {
        try {
          final publicDownload = Directory('/storage/emulated/0/Download/EaseInn');
          if (!publicDownload.existsSync()) {
            publicDownload.createSync(recursive: true);
          }
          final dlFile = File('${publicDownload.path}/$fileName');
          await dlFile.writeAsBytes(pdfBytes, flush: true);
        } catch (_) {}
      }
    } else if (!kIsWeb) {
      try {
        final dlDir = await getDownloadsDirectory();
        if (dlDir != null) {
          final dlFile = File('${dlDir.path}/$fileName');
          await dlFile.writeAsBytes(pdfBytes, flush: true);
        }
      } catch (_) {}
    }

    return localFile;
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
