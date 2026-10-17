// src/services/invoice.service.js
const PDFDocument = require("pdfkit");

/**
 * Generate a clean, professional, detailed A4 PDF Tax Invoice Buffer
 * @param {Object} options
 * @returns {Promise<Buffer>}
 */
function generateInvoicePdfBuffer(options = {}) {
  return new Promise((resolve, reject) => {
    try {
      const {
        hotelName = "EaseInn Hotel",
        hotelPhone = "+91 98765 43210",
        hotelEmail = "frontdesk@easeinn.com",
        hotelAddress = "Civil Lines, Near Clock Tower",
        hotelGstin = "09AAAAA0000A1Z5",
        invoiceNo = `INV-${new Date().getFullYear()}-${Math.floor(1000 + Math.random() * 9000)}`,
        issueDate = new Date().toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" }),
        guestName = "Valued Guest",
        guestPhone = "",
        roomNumber = "101",
        checkInDate = "Today",
        checkOutDate = "Tomorrow",
        nights = 1,
        totalAmount = 2500,
        amountPaid = 2500,
        balanceDue = 0,
        paymentMethod = "UPI",
      } = options;

      const baseAmount = Math.round(totalAmount / 1.12);
      const cgst = Math.round((totalAmount / 1.12) * 0.06);
      const sgst = Math.round((totalAmount / 1.12) * 0.06);

      const doc = new PDFDocument({
        size: "A4",
        margin: 40,
        info: {
          Title: `Tax Invoice - ${invoiceNo}`,
          Author: hotelName,
          Subject: "Hotel Stay Invoice & Guest Folio",
        },
      });

      const chunks = [];
      doc.on("data", (chunk) => chunks.push(chunk));
      doc.on("end", () => resolve(Buffer.concat(chunks)));
      doc.on("error", (err) => reject(err));

      // Primary Colors
      const primaryColor = "#0F172A"; // Slate 900
      const accentColor = "#1E293B";  // Slate 800
      const mutedColor = "#64748B";   // Slate 500
      const lightBg = "#F8FAFC";      // Slate 50
      const borderColor = "#E2E8F0";  // Slate 200
      const successColor = "#16A34A"; // Green 600

      // Top Banner
      doc.rect(40, 40, 515, 6).fill(primaryColor);

      // Header: Hotel Branding & Invoice Info
      doc.fillColor(primaryColor).fontSize(20).font("Helvetica-Bold").text(hotelName, 40, 58);
      doc.fillColor(mutedColor).fontSize(9).font("Helvetica").text(hotelAddress, 40, 82);
      doc.text(`Phone: ${hotelPhone}  |  Email: ${hotelEmail}`, 40, 95);
      doc.text(`GSTIN: ${hotelGstin}`, 40, 108);

      // Status Badge (Paid in Full vs Payment Due)
      const badgeText = balanceDue <= 0 ? "PAID IN FULL" : "PAYMENT DUE";
      const badgeColor = balanceDue <= 0 ? successColor : "#DC2626";
      doc.rect(420, 56, 135, 24).fillAndStroke(lightBg, borderColor);
      doc.fillColor(badgeColor).fontSize(10).font("Helvetica-Bold").text(badgeText, 420, 63, { width: 135, align: "center" });

      doc.fillColor(primaryColor).fontSize(12).font("Helvetica-Bold").text("TAX INVOICE", 420, 88, { width: 135, align: "right" });
      doc.fillColor(mutedColor).fontSize(8.5).font("Helvetica").text(`Invoice No: ${invoiceNo}`, 350, 104, { width: 205, align: "right" });
      doc.text(`Date: ${issueDate}`, 350, 116, { width: 205, align: "right" });

      // Divider
      doc.strokeColor(borderColor).lineWidth(1).moveTo(40, 134).lineTo(555, 134).stroke();

      // Two Column Cards: Guest Info & Stay Info
      // Card 1: Guest Information
      doc.rect(40, 145, 248, 90).fillAndStroke(lightBg, borderColor);
      doc.fillColor(accentColor).fontSize(10).font("Helvetica-Bold").text("GUEST DETAILS", 52, 155);
      doc.fillColor(mutedColor).fontSize(8.5).font("Helvetica");
      doc.text("Guest Name:", 52, 172);
      doc.fillColor(primaryColor).font("Helvetica-Bold").text(guestName, 120, 172);
      doc.fillColor(mutedColor).font("Helvetica").text("Contact Phone:", 52, 187);
      doc.fillColor(primaryColor).font("Helvetica").text(guestPhone || "Not Provided", 120, 187);
      doc.fillColor(mutedColor).text("Assigned Room:", 52, 202);
      doc.fillColor(primaryColor).font("Helvetica-Bold").text(`Room ${roomNumber}`, 120, 202);
      doc.fillColor(mutedColor).font("Helvetica").text("Payment Mode:", 52, 217);
      doc.fillColor(primaryColor).font("Helvetica").text(paymentMethod.toUpperCase(), 120, 217);

      // Card 2: Stay Information
      doc.rect(307, 145, 248, 90).fillAndStroke(lightBg, borderColor);
      doc.fillColor(accentColor).fontSize(10).font("Helvetica-Bold").text("STAY PARTICULARS", 319, 155);
      doc.fillColor(mutedColor).fontSize(8.5).font("Helvetica");
      doc.text("Check-in:", 319, 172);
      doc.fillColor(primaryColor).font("Helvetica").text(checkInDate, 385, 172);
      doc.fillColor(mutedColor).text("Check-out:", 319, 187);
      doc.fillColor(primaryColor).font("Helvetica").text(checkOutDate, 385, 187);
      doc.fillColor(mutedColor).text("Duration:", 319, 202);
      doc.fillColor(primaryColor).font("Helvetica-Bold").text(`${nights} Night(s)`, 385, 202);
      doc.fillColor(mutedColor).font("Helvetica").text("Billing Status:", 319, 217);
      doc.fillColor(badgeColor).font("Helvetica-Bold").text(badgeText, 385, 217);

      // Table Header
      const tableTop = 250;
      doc.rect(40, tableTop, 515, 22).fill(accentColor);
      doc.fillColor("#FFFFFF").fontSize(9).font("Helvetica-Bold");
      doc.text("PARTICULARS", 52, tableTop + 6);
      doc.text("QTY", 330, tableTop + 6, { width: 40, align: "center" });
      doc.text("RATE (RS.)", 380, tableTop + 6, { width: 75, align: "right" });
      doc.text("TOTAL (RS.)", 465, tableTop + 6, { width: 80, align: "right" });

      // Row 1: Accommodation
      const row1Top = tableTop + 24;
      doc.rect(40, row1Top, 515, 26).fillAndStroke(lightBg, borderColor);
      doc.fillColor(primaryColor).fontSize(9).font("Helvetica-Bold");
      doc.text(`Room Accommodation - Room ${roomNumber}`, 52, row1Top + 8);
      doc.fillColor(mutedColor).font("Helvetica");
      doc.text(String(nights), 330, row1Top + 8, { width: 40, align: "center" });
      doc.text(`${(baseAmount / Math.max(1, nights)).toFixed(2)}`, 380, row1Top + 8, { width: 75, align: "right" });
      doc.fillColor(primaryColor).font("Helvetica-Bold");
      doc.text(`${baseAmount.toFixed(2)}`, 465, row1Top + 8, { width: 80, align: "right" });

      // Row 2: CGST
      const row2Top = row1Top + 26;
      doc.rect(40, row2Top, 515, 22).fillAndStroke("#FFFFFF", borderColor);
      doc.fillColor(mutedColor).fontSize(8.5).font("Helvetica").text("CGST (Central Tax @ 6.0%)", 52, row2Top + 6);
      doc.text("1", 330, row2Top + 6, { width: 40, align: "center" });
      doc.text(`${cgst.toFixed(2)}`, 380, row2Top + 6, { width: 75, align: "right" });
      doc.text(`${cgst.toFixed(2)}`, 465, row2Top + 6, { width: 80, align: "right" });

      // Row 3: SGST
      const row3Top = row2Top + 22;
      doc.rect(40, row3Top, 515, 22).fillAndStroke(lightBg, borderColor);
      doc.fillColor(mutedColor).fontSize(8.5).font("Helvetica").text("SGST (State Tax @ 6.0%)", 52, row3Top + 6);
      doc.text("1", 330, row3Top + 6, { width: 40, align: "center" });
      doc.text(`${sgst.toFixed(2)}`, 380, row3Top + 6, { width: 75, align: "right" });
      doc.text(`${sgst.toFixed(2)}`, 465, row3Top + 6, { width: 80, align: "right" });

      // Financial Summary Block
      const sumTop = row3Top + 32;
      doc.rect(320, sumTop, 235, 120).fillAndStroke("#FFFFFF", borderColor);

      const writeSummaryRow = (label, val, y, isBold = false, isAccent = false) => {
        doc.fillColor(isAccent ? primaryColor : mutedColor).fontSize(isBold ? 9.5 : 8.5).font(isBold ? "Helvetica-Bold" : "Helvetica");
        doc.text(label, 332, y);
        doc.text(val, 440, y, { width: 105, align: "right" });
      };

      writeSummaryRow("Net Taxable Amount:", `Rs. ${baseAmount.toFixed(2)}`, sumTop + 10);
      writeSummaryRow("Total Tax (GST 12%):", `Rs. ${(cgst + sgst).toFixed(2)}`, sumTop + 26);
      writeSummaryRow("Total Invoice Value:", `Rs. ${totalAmount.toFixed(2)}`, sumTop + 42, true, true);
      writeSummaryRow("Amount Paid / Settled:", `Rs. ${amountPaid.toFixed(2)}`, sumTop + 58);
      
      doc.strokeColor(borderColor).moveTo(332, sumTop + 74).lineTo(545, sumTop + 74).stroke();
      doc.fillColor(badgeColor).fontSize(10).font("Helvetica-Bold");
      doc.text("Balance Due:", 332, sumTop + 84);
      doc.text(`Rs. ${balanceDue.toFixed(2)}`, 440, sumTop + 84, { width: 105, align: "right" });

      // Terms & Bank / UPI Note on Left
      doc.rect(40, sumTop, 265, 120).fillAndStroke(lightBg, borderColor);
      doc.fillColor(accentColor).fontSize(9.5).font("Helvetica-Bold").text("TERMS & INSTRUCTIONS", 52, sumTop + 10);
      doc.fillColor(mutedColor).fontSize(8).font("Helvetica");
      doc.text("1. All tariffs are inclusive of standard applicable Goods & Services Tax (GST).", 52, sumTop + 26, { width: 245 });
      doc.text("2. Standard check-out time is 11:00 AM. Late check-out subject to availability.", 52, sumTop + 46, { width: 245 });
      doc.text("3. Thank you for staying with EaseInn. We look forward to hosting you again!", 52, sumTop + 66, { width: 245 });
      doc.fillColor(primaryColor).font("Helvetica-Bold").text("For queries: support@easeinn.com", 52, sumTop + 92);

      // Computer Generated Disclaimer Footer
      doc.strokeColor(borderColor).lineWidth(1).moveTo(40, 520).lineTo(555, 520).stroke();
      doc.fillColor(mutedColor).fontSize(7.5).font("Helvetica");
      doc.text(
        "This is a system-generated electronic tax invoice and guest folio. No physical signature is required.",
        40,
        530,
        { width: 515, align: "center" }
      );
      doc.text(
        `Generated by ${hotelName} Property Management System | ${issueDate}`,
        40,
        542,
        { width: 515, align: "center" }
      );

      doc.end();
    } catch (err) {
      reject(err);
    }
  });
}

module.exports = {
  generateInvoicePdfBuffer,
};
