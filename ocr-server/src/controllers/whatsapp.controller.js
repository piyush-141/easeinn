// src/controllers/whatsapp.controller.js
const whatsappService = require("../services/whatsapp.service");
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

    const preview = whatsappService.interpolateTemplate(rawText, context || variables || {});
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
    const { templateId, recipientPhone, customMessage, context, variables, bypassDuplicateCheck, stayId } = req.body;
    const ctx = context || variables || {};

    if (!recipientPhone) {
      return res.status(400).json({ success: false, error: "recipientPhone is required." });
    }

    const result = await whatsappService.sendWhatsAppNotification({
      templateId,
      recipientPhone,
      customMessage,
      context: ctx,
      bypassDuplicateCheck,
      stayId,
    });

    return res.json(result);
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * GET /api/whatsapp/logs
 */
exports.getLogs = async (req, res) => {
  try {
    const limit = parseInt(req.query.limit, 10) || 50;
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
    return res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * POST /api/whatsapp/hook/checkout
 * Automated trigger when checkout completes
 */
exports.onCheckOut = async (req, res) => {
  try {
    const { guestName, phone, hotelName, roomNumber, checkInDate, checkOutDate, stayId } = req.body;
    if (!phone) {
      return res.status(400).json({ success: false, error: "Guest phone number is required" });
    }

    const result = await whatsappService.sendWhatsAppNotification({
      templateId: "checkout_thankyou",
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
    return res.status(500).json({ success: false, error: err.message });
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
      return res.status(400).json({ success: false, error: "Guest phone number is required" });
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
    return res.status(500).json({ success: false, error: err.message });
  }
};
