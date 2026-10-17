// src/controllers/whatsapp.controller.js
const whatsappService = require("../services/whatsapp.service");
const invoiceService = require("../services/invoice.service");
const { DEFAULT_TEMPLATES } = require("../config/whatsapp.config");

/**
 * GET /api/whatsapp/status
 */
exports.getStatus = async (req, res) => {
  try {
    const status = whatsappService.getStatus();
    return res.json({ success: true, ...status });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * POST /api/whatsapp/connect
 */
exports.connect = async (req, res) => {
  try {
    // Non-blocking trigger so HTTP request doesn't wait for full QR scan
    const current = whatsappService.getStatus();
    if (current.isConnected || current.hasActiveQr || current.status === "INITIALIZING" || current.status === "AUTHENTICATED") {
      return res.json({ success: true, message: "WhatsApp connection is already active or initializing.", status: current.status });
    }
    whatsappService.initializeWhatsAppClient().catch((err) => {
      console.error("[WhatsApp] Error during connect:", err.message);
    });
    return res.json({
      success: true,
      message: "WhatsApp client initialization started. Poll /api/whatsapp/status for QR code.",
      status: "INITIALIZING",
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * POST /api/whatsapp/disconnect
 */
exports.disconnect = async (req, res) => {
  try {
    const result = await whatsappService.disconnectWhatsAppClient();
    return res.json({ success: true, ...result });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * GET /api/whatsapp/templates
 */
exports.getTemplates = async (req, res) => {
  try {
    const templates = whatsappService.getTemplates();
    return res.json({
      success: true,
      templates,
      placeholders: whatsappService.SUPPORTED_PLACEHOLDERS,
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * PUT /api/whatsapp/templates/:templateId
 */
exports.updateTemplate = async (req, res) => {
  try {
    const { templateId } = req.params;
    const { template, enabled, name, description } = req.body;

    const templates = whatsappService.getTemplates();
    if (!templates[templateId]) {
      return res.status(404).json({ success: false, error: `Template "${templateId}" not found.` });
    }

    if (typeof template === "string") templates[templateId].template = template;
    if (typeof enabled === "boolean") templates[templateId].enabled = enabled;
    if (name) templates[templateId].name = name;
    if (description) templates[templateId].description = description;

    whatsappService.saveTemplates(templates);
    return res.json({
      success: true,
      message: `Template "${templateId}" updated successfully.`,
      template: templates[templateId],
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * POST /api/whatsapp/templates/reset
 */
exports.resetTemplates = async (req, res) => {
  try {
    whatsappService.saveTemplates(DEFAULT_TEMPLATES);
    return res.json({
      success: true,
      message: "Reset all templates to factory defaults.",
      templates: DEFAULT_TEMPLATES,
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * POST /api/whatsapp/preview
 */
exports.previewTemplate = async (req, res) => {
  try {
    const { templateId, templateString, context, variables } = req.body;
    let rawText = templateString;

    if (!rawText && templateId) {
      const templates = whatsappService.getTemplates();
      rawText = templates[templateId]?.template;
    }

    if (!rawText) {
      return res.status(400).json({ success: false, error: "Missing templateId or templateString" });
    }

    const userContext = context || variables || {};
    const preview = whatsappService.interpolateTemplate(rawText, { isSample: true, ...userContext });
    return res.json({ success: true, preview });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * POST /api/whatsapp/send
 */
exports.sendMessage = async (req, res) => {
  try {
    const {
      templateId,
      recipientPhone,
      customMessage,
      context,
      variables,
      bypassDuplicateCheck,
      stayId,
      pdfBase64,
      pdfFileName,
    } = req.body;
    const ctx = context || variables || {};

    if (!recipientPhone) {
      return res.status(400).json({ success: false, error: "recipientPhone is required." });
    }

    const document = pdfBase64
      ? {
          buffer: Buffer.from(pdfBase64, "base64"),
          fileName: pdfFileName || "Tax_Invoice.pdf",
          mimetype: "application/pdf",
        }
      : undefined;

    const result = await whatsappService.sendWhatsAppNotification({
      templateId,
      recipientPhone,
      customMessage,
      context: ctx,
      bypassDuplicateCheck,
      stayId,
      document,
    });

    const statusCode = result.success ? 200 : ["NOT_CONNECTED", "SEND_OUTCOME_UNKNOWN", "SEND_IN_PROGRESS"].includes(result.code) ? 503 : result.code === "SEND_FAILED" ? 502 : 400;
    return res.status(statusCode).json(result);
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * GET /api/whatsapp/logs
 */
exports.getLogs = async (req, res) => {
  try {
    const requestedLimit = Number.parseInt(req.query.limit, 10);
    const limit = Number.isFinite(requestedLimit) ? Math.max(1, Math.min(requestedLimit, 200)) : 50;
    const logs = whatsappService.getLogs(limit);
    return res.json({ success: true, logs });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * POST /api/whatsapp/hook/checkin
 * Automated trigger when check-in completes
 */
exports.onCheckIn = async (req, res) => {
  try {
    const { guestName, phone, hotelName, roomNumber, checkInDate, checkOutDate, stayId } = req.body;
    if (!phone) {
      return res.status(400).json({ success: false, error: "Guest phone number is required" });
    }

    const result = await whatsappService.sendWhatsAppNotification({
      templateId: "checkin_welcome",
      recipientPhone: phone,
      stayId,
      context: {
        guestName,
        hotelName,
        roomNumber,
        checkInDate,
        checkOutDate,
      },
    });

    return res.json(result);
  } catch (err) {
    console.warn("[WhatsApp Hook Check-in Non-Blocking Error]", err.message);
    return res.json({ success: false, error: err.message, nonBlocking: true });
  }
};

/**
 * POST /api/whatsapp/hook/checkout
 * Automated trigger when checkout completes
 */
exports.onCheckOut = async (req, res) => {
  try {
    const {
      guestName,
      phone,
      hotelName,
      roomNumber,
      checkInDate,
      checkOutDate,
      stayId,
      pdfBase64,
      pdfFileName,
      totalAmount,
      amountPaid,
      balanceDue,
      paymentMethod,
    } = req.body;
    if (!phone) {
      return res.json({ success: false, error: "Guest phone number is required", nonBlocking: true });
    }

    let document;
    if (pdfBase64 && typeof pdfBase64 === "string" && pdfBase64.trim().length > 50) {
      const cleanB64 = pdfBase64.includes(";base64,") ? pdfBase64.split(";base64,").pop().trim() : pdfBase64.trim();
      document = {
        buffer: Buffer.from(cleanB64, "base64"),
        fileName: pdfFileName || `Tax_Invoice_${roomNumber || "checkout"}.pdf`,
        mimetype: "application/pdf",
      };
    } else {
      // Auto-generate detailed PDF invoice on the server so the guest ALWAYS receives their invoice
      try {
        const generatedBuffer = await invoiceService.generateInvoicePdfBuffer({
          guestName: guestName || "Valued Guest",
          guestPhone: phone,
          hotelName: hotelName || "EaseInn Hotel",
          roomNumber: roomNumber || "101",
          checkInDate: checkInDate || "Today",
          checkOutDate: checkOutDate || "Tomorrow",
          invoiceNo: pdfFileName ? pdfFileName.replace(/\.pdf$/i, "") : undefined,
          totalAmount: Number(totalAmount) || 2500,
          amountPaid: amountPaid !== undefined ? Number(amountPaid) : 2500,
          balanceDue: balanceDue !== undefined ? Number(balanceDue) : 0,
          paymentMethod: paymentMethod || "UPI",
        });
        document = {
          buffer: generatedBuffer,
          fileName: pdfFileName || `Tax_Invoice_${roomNumber || "checkout"}.pdf`,
          mimetype: "application/pdf",
        };
      } catch (genErr) {
        console.warn("[WhatsApp] Could not auto-generate invoice PDF:", genErr.message);
      }
    }

    const result = await whatsappService.sendWhatsAppNotification({
      templateId: "checkout_thankyou",
      recipientPhone: phone,
      stayId,
      document,
      context: {
        guestName,
        hotelName,
        roomNumber,
        checkInDate,
        checkOutDate,
      },
    });

    return res.json(result);
  } catch (err) {
    console.warn("[WhatsApp Hook Check-out Non-Blocking Error]", err.message);
    return res.json({ success: false, error: err.message, nonBlocking: true });
  }
};

/**
 * POST /api/whatsapp/hook/reservation
 * Automated trigger when reservation is confirmed
 */
exports.onReservation = async (req, res) => {
  try {
    const { guestName, phone, hotelName, roomNumber, checkInDate, checkOutDate, stayId } = req.body;
    if (!phone) {
      return res.json({ success: false, error: "Guest phone number is required", nonBlocking: true });
    }

    const result = await whatsappService.sendWhatsAppNotification({
      templateId: "booking_confirmation",
      recipientPhone: phone,
      stayId,
      context: {
        guestName,
        hotelName,
        roomNumber,
        checkInDate,
        checkOutDate,
      },
    });

    return res.json(result);
  } catch (err) {
    console.warn("[WhatsApp Hook Reservation Non-Blocking Error]", err.message);
    return res.json({ success: false, error: err.message, nonBlocking: true });
  }
};
