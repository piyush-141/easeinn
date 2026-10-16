// src/services/whatsapp.service.js
const fs = require("fs");
const path = require("path");
const qrcode = require("qrcode");
const {
  DATA_DIR,
  TEMPLATES_FILE,
  LOGS_FILE,
  AUTH_DIR,
  DEFAULT_TEMPLATES,
  SUPPORTED_PLACEHOLDERS,
} = require("../config/whatsapp.config");

// In-memory state tracking
let clientInstance = null;
let clientStatus = "DISCONNECTED"; // DISCONNECTED | INITIALIZING | QR_READY | AUTHENTICATED | CONNECTED | ERROR
let currentQrCodeDataUrl = null;
let currentQrRaw = null;
let connectedNumber = null;
let connectedPushname = null;
let lastStatusChange = new Date().toISOString();
let initializationError = null;
let duplicateCache = new Map(); // key: "${stayId || phone}_${templateId}" -> timestamp

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

/**
 * Clean & normalize phone number for WhatsApp
 * Accepts "+91 98765 43210", "9876543210", etc.
 * Returns { cleanPhone: "919876543210", chatId: "919876543210@c.us" }
 */
function normalizePhoneNumber(rawPhone) {
  if (!rawPhone || typeof rawPhone !== "string") {
    return null;
  }
  // Strip all non-digit characters
  let digits = rawPhone.replace(/\D/g, "");
  if (!digits) return null;

  // If 10 digits (Standard Indian mobile), prepend 91
  if (digits.length === 10) {
    digits = "91" + digits;
  }
  // If 11 digits starting with 0 (e.g. 09876543210), replace leading 0 with 91
  if (digits.length === 11 && digits.startsWith("0")) {
    digits = "91" + digits.slice(1);
  }

  // Minimum valid phone length is 10 digits
  if (digits.length < 10) return null;

  return {
    cleanPhone: digits,
    chatId: `${digits}@c.us`,
  };
}

/**
 * Load or initialize template configuration
 */
function getTemplates() {
  try {
    if (fs.existsSync(TEMPLATES_FILE)) {
      const data = fs.readFileSync(TEMPLATES_FILE, "utf-8");
      return JSON.parse(data);
    }
  } catch (err) {
    console.error("[WhatsApp] Error reading templates file:", err.message);
  }
  // Initialize with defaults if missing
  saveTemplates(DEFAULT_TEMPLATES);
  return { ...DEFAULT_TEMPLATES };
}

/**
 * Save template configuration to file
 */
function saveTemplates(templates) {
  try {
    fs.writeFileSync(TEMPLATES_FILE, JSON.stringify(templates, null, 2), "utf-8");
    return true;
  } catch (err) {
    console.error("[WhatsApp] Error saving templates file:", err.message);
    return false;
  }
}

/**
 * Load recent dispatch logs
 */
function getLogs(limit = 50) {
  try {
    if (fs.existsSync(LOGS_FILE)) {
      const data = fs.readFileSync(LOGS_FILE, "utf-8");
      const logs = JSON.parse(data);
      return Array.isArray(logs) ? logs.slice(-limit) : [];
    }
  } catch (err) {
    console.error("[WhatsApp] Error reading logs file:", err.message);
  }
  return [];
}

/**
 * Record a dispatch event to log file
 */
function appendLog(logEntry) {
  try {
    const existing = getLogs(200);
    const updated = [
      ...existing,
      {
        id: `log-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
        timestamp: new Date().toISOString(),
        ...logEntry,
      },
    ];
    fs.writeFileSync(LOGS_FILE, JSON.stringify(updated.slice(-100), null, 2), "utf-8");
  } catch (err) {
    console.error("[WhatsApp] Error appending log:", err.message);
  }
}

/**
 * Interpolate placeholders into template string
 */
function interpolateTemplate(templateString, context = {}) {
  let result = templateString || "";
  const replacements = {
    "{guestName}": context.guestName || "Valued Guest",
    "{hotelName}": context.hotelName || "EaseInn Hotel",
    "{roomNumber}": context.roomNumber ? String(context.roomNumber) : "Unassigned",
    "{checkInDate}": context.checkInDate || "Today",
    "{checkOutDate}": context.checkOutDate || "Tomorrow",
  };

  for (const [placeholder, value] of Object.entries(replacements)) {
    result = result.split(placeholder).join(value);
  }
  return result;
}

/**
 * Initialize whatsapp-web.js Client instance
 */
async function initializeWhatsAppClient() {
  if (clientInstance) {
    try {
      await clientInstance.destroy();
    } catch (_) {}
    clientInstance = null;
  }

  clientStatus = "INITIALIZING";
  initializationError = null;
  currentQrCodeDataUrl = null;
  currentQrRaw = null;
  lastStatusChange = new Date().toISOString();

  let Client, LocalAuth;
  try {
    const wwebjs = require("whatsapp-web.js");
    Client = wwebjs.Client;
    LocalAuth = wwebjs.LocalAuth;
  } catch (requireErr) {
    clientStatus = "ERROR";
    initializationError = `whatsapp-web.js dependency not loaded: ${requireErr.message}`;
    console.error("[WhatsApp]", initializationError);
    return;
  }

  try {
    console.log("[WhatsApp] Initializing WhatsApp Web Client with LocalAuth session persistence...");
    clientInstance = new Client({
      authStrategy: new LocalAuth({
        dataPath: AUTH_DIR,
      }),
      puppeteer: {
        headless: true,
        args: [
          "--no-sandbox",
          "--disable-setuid-sandbox",
          "--disable-dev-shm-usage",
          "--disable-accelerated-2d-canvas",
          "--no-first-run",
          "--no-zygote",
          "--disable-gpu",
        ],
      },
    });

    // ── Client Event Listeners ──

    clientInstance.on("qr", async (qr) => {
      console.log("[WhatsApp] New QR code generated. Waiting for hotel phone scan...");
      currentQrRaw = qr;
      try {
        currentQrCodeDataUrl = await qrcode.toDataURL(qr, {
          margin: 2,
          scale: 6,
          color: {
            dark: "#0F172A",
            light: "#FFFFFF",
          },
        });
        clientStatus = "QR_READY";
        lastStatusChange = new Date().toISOString();
      } catch (qrErr) {
        console.error("[WhatsApp] Failed to render QR code data URL:", qrErr);
      }
    });

    clientInstance.on("authenticated", () => {
      console.log("[WhatsApp] Hotel WhatsApp session authenticated successfully!");
      clientStatus = "AUTHENTICATED";
      currentQrCodeDataUrl = null;
      currentQrRaw = null;
      initializationError = null;
      lastStatusChange = new Date().toISOString();
    });

    clientInstance.on("auth_failure", (msg) => {
      console.error("[WhatsApp] Authentication failure:", msg);
      clientStatus = "AUTH_FAILURE";
      initializationError = `Authentication failure: ${msg}`;
      lastStatusChange = new Date().toISOString();
    });

    clientInstance.on("ready", () => {
      console.log("[WhatsApp] Client is READY! Hotel WhatsApp automated one-way messaging active.");
      clientStatus = "CONNECTED";
      currentQrCodeDataUrl = null;
      currentQrRaw = null;
      initializationError = null;
      lastStatusChange = new Date().toISOString();

      try {
        if (clientInstance.info) {
          connectedNumber = clientInstance.info.wid ? clientInstance.info.wid.user : null;
          connectedPushname = clientInstance.info.pushname || null;
        }
      } catch (_) {}
    });

    clientInstance.on("disconnected", (reason) => {
      console.warn("[WhatsApp] Client was disconnected. Reason:", reason);
      clientStatus = "DISCONNECTED";
      currentQrCodeDataUrl = null;
      currentQrRaw = null;
      connectedNumber = null;
      connectedPushname = null;
      lastStatusChange = new Date().toISOString();
    });

    await clientInstance.initialize();
  } catch (err) {
    clientStatus = "ERROR";
    initializationError = err.message;
    console.error("[WhatsApp] Initialization error:", err);
  }
}

/**
 * Disconnect and clear active session
 */
async function disconnectWhatsAppClient() {
  if (clientInstance) {
    try {
      await clientInstance.logout();
    } catch (_) {}
    try {
      await clientInstance.destroy();
    } catch (_) {}
    clientInstance = null;
  }
  clientStatus = "DISCONNECTED";
  currentQrCodeDataUrl = null;
  currentQrRaw = null;
  connectedNumber = null;
  connectedPushname = null;
  lastStatusChange = new Date().toISOString();
  return { success: true, message: "WhatsApp client disconnected." };
}

/**
 * Send automated or custom message with template rendering and duplicate suppression
 */
async function sendWhatsAppNotification({
  templateId,
  recipientPhone,
  customMessage,
  context = {},
  bypassDuplicateCheck = false,
  stayId,
}) {
  const norm = normalizePhoneNumber(recipientPhone);
  if (!norm) {
    const errorMsg = `Invalid phone number format: "${recipientPhone}". Needs at least 10 digits.`;
    appendLog({
      templateId: templateId || "custom",
      recipientPhone,
      status: "FAILED",
      error: errorMsg,
      context,
    });
    return { success: false, error: errorMsg, code: "INVALID_PHONE" };
  }

  const templates = getTemplates();
  let messageBody = customMessage;

  if (templateId) {
    const templateConfig = templates[templateId];
    if (!templateConfig) {
      return { success: false, error: `Template "${templateId}" not found.`, code: "TEMPLATE_NOT_FOUND" };
    }
    if (!templateConfig.enabled) {
      appendLog({
        templateId,
        recipientPhone: norm.cleanPhone,
        status: "SKIPPED_DISABLED",
        preview: `Template "${templateConfig.name}" is disabled in settings.`,
        context,
      });
      return {
        success: false,
        skipped: true,
        reason: "TEMPLATE_DISABLED",
        message: `Template "${templateConfig.name}" is disabled in settings.`,
      };
    }
    messageBody = interpolateTemplate(templateConfig.template, context);
  } else if (!messageBody) {
    return { success: false, error: "Either templateId or customMessage must be supplied.", code: "NO_MESSAGE" };
  }

  // Duplicate suppression (Idempotency check within 10 minutes)
  const duplicateKey = `${stayId || norm.cleanPhone}_${templateId || "custom"}`;
  const now = Date.now();
  if (!bypassDuplicateCheck && duplicateCache.has(duplicateKey)) {
    const lastSent = duplicateCache.get(duplicateKey);
    const tenMinutes = 10 * 60 * 1000;
    if (now - lastSent < tenMinutes) {
      console.log(`[WhatsApp] Duplicate trigger suppressed for key "${duplicateKey}" (last sent ${(now - lastSent) / 1000}s ago).`);
      appendLog({
        templateId: templateId || "custom",
        recipientPhone: norm.cleanPhone,
        status: "SKIPPED_DUPLICATE",
        preview: messageBody.slice(0, 100) + "...",
        context,
      });
      return {
        success: false,
        skipped: true,
        reason: "DUPLICATE_SUPPRESSED",
        message: "Message already sent to this guest recently. Skipped duplicate trigger.",
      };
    }
  }

  // Check if client is actually connected
  if (clientStatus !== "CONNECTED" || !clientInstance) {
    console.warn(`[WhatsApp] Cannot send message: Client is in "${clientStatus}" state.`);
    appendLog({
      templateId: templateId || "custom",
      recipientPhone: norm.cleanPhone,
      status: "FAILED_CLIENT_NOT_CONNECTED",
      error: `WhatsApp client is not connected (current status: ${clientStatus}).`,
      preview: messageBody.slice(0, 100) + "...",
      context,
    });
    return {
      success: false,
      error: `WhatsApp is not connected on server (status: ${clientStatus}). Scan QR code in Settings.`,
      code: "CLIENT_NOT_READY",
      clientStatus,
    };
  }

  // Dispatch message via whatsapp-web.js
  try {
    const sentMessage = await clientInstance.sendMessage(norm.chatId, messageBody);
    duplicateCache.set(duplicateKey, now);

    appendLog({
      templateId: templateId || "custom",
      recipientPhone: norm.cleanPhone,
      status: "SENT",
      messageId: sentMessage.id ? sentMessage.id._serialized : null,
      preview: messageBody.slice(0, 100) + "...",
      context,
    });

    console.log(`[WhatsApp] Successfully delivered message to ${norm.cleanPhone} (Template: ${templateId || "custom"}).`);
    return {
      success: true,
      messageId: sentMessage.id ? sentMessage.id._serialized : null,
      recipient: norm.cleanPhone,
      dispatchedText: messageBody,
    };
  } catch (sendErr) {
    console.error(`[WhatsApp] Error delivering message to ${norm.cleanPhone}:`, sendErr.message);
    appendLog({
      templateId: templateId || "custom",
      recipientPhone: norm.cleanPhone,
      status: "FAILED",
      error: sendErr.message,
      preview: messageBody.slice(0, 100) + "...",
      context,
    });
    return {
      success: false,
      error: sendErr.message,
      code: "SEND_FAILED",
    };
  }
}

/**
 * Get current system status
 */
function getStatus() {
  const templates = getTemplates();
  return {
    status: clientStatus,
    isConnected: clientStatus === "CONNECTED",
    isReady: clientStatus === "CONNECTED",
    qrCodeDataUrl: currentQrCodeDataUrl,
    hasActiveQr: Boolean(currentQrCodeDataUrl),
    connectedNumber,
    connectedPushname,
    lastStatusChange,
    initializationError,
    activeTemplatesCount: Object.values(templates).filter((t) => t.enabled).length,
    totalTemplatesCount: Object.values(templates).length,
    supportedPlaceholders: SUPPORTED_PLACEHOLDERS,
  };
}

module.exports = {
  initializeWhatsAppClient,
  disconnectWhatsAppClient,
  sendWhatsAppNotification,
  getStatus,
  getTemplates,
  saveTemplates,
  getLogs,
  interpolateTemplate,
  normalizePhoneNumber,
  SUPPORTED_PLACEHOLDERS,
};
