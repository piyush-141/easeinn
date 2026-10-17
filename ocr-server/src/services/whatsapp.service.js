// src/services/whatsapp.service.js
// WhatsApp engine for EaseInn — Baileys multi-device (no Chromium)
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const qrcodeLib = require("qrcode");
const pino = require("pino");
const {
  DATA_DIR,
  TEMPLATES_FILE,
  LOGS_FILE,
  AUTH_DIR,
  DEFAULT_TEMPLATES,
  SUPPORTED_PLACEHOLDERS,
} = require("../config/whatsapp.config");

const baileys = require("@whiskeysockets/baileys");
const whatsappEngine = process.env.WHATSAPP_ENGINE_MODULE
  ? require(path.resolve(process.env.WHATSAPP_ENGINE_MODULE))
  : baileys;
const makeWASocket = whatsappEngine.default || whatsappEngine.makeWASocket;
const {
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  Browsers,
  makeCacheableSignalKeyStore,
} = whatsappEngine;

const logger = pino({ level: process.env.WA_LOG_LEVEL || "silent" });

let sock = null;
let clientStatus = "DISCONNECTED"; // DISCONNECTED | INITIALIZING | QR_READY | CONNECTED | ERROR
let isInitializing = false;
let allowReconnect = true;
let reconnectTimer = null;
let currentQrCodeDataUrl = null;
let connectedNumber = null;
let connectedPushname = null;
let lastStatusChange = new Date().toISOString();
let initializationError = null;
let duplicateCache = new Map();
let initializePromise = null;
let sendQueue = Promise.resolve();
let generation = 0;
let pendingSends = new Map();
const configuredSendTimeout = Number(process.env.WHATSAPP_SEND_TIMEOUT_MS || 90000);
const SEND_TIMEOUT_MS = Number.isFinite(configuredSendTimeout) && configuredSendTimeout >= 10000 && configuredSendTimeout <= 180000
  ? configuredSendTimeout
  : 90000;

[DATA_DIR, AUTH_DIR].forEach((dir) => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

function setStatus(next, extra = {}) {
  clientStatus = next;
  lastStatusChange = new Date().toISOString();
  if (extra.error !== undefined) initializationError = extra.error;
}

function hasAuthFiles() {
  try {
    return fs.existsSync(path.join(AUTH_DIR, "creds.json"));
  } catch (_) {
    return false;
  }
}

function extractPhoneFromJid(jid) {
  if (!jid || typeof jid !== "string") return null;
  const user = jid.split("@")[0] || "";
  const phone = user.split(":")[0];
  return phone || null;
}

/**
 * Clean & normalize phone number for WhatsApp
 */
function normalizePhoneNumber(rawPhone) {
  if (!rawPhone || typeof rawPhone !== "string") {
    return null;
  }
  let digits = rawPhone.replace(/\D/g, "");
  if (!digits) return null;

  if (digits.length === 10) {
    digits = "91" + digits;
  } else if (digits.length === 11 && digits.startsWith("0")) {
    digits = "91" + digits.slice(1);
  } else if (!(digits.length === 12 && digits.startsWith("91"))) {
    return null;
  }

  return {
    cleanPhone: digits,
    chatId: `${digits}@s.whatsapp.net`,
  };
}

function getTemplates() {
  try {
    if (fs.existsSync(TEMPLATES_FILE)) {
      const data = fs.readFileSync(TEMPLATES_FILE, "utf-8");
      const parsed = JSON.parse(data);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Invalid template data format");
      return parsed;
    }
  } catch (err) {
    console.error("[WhatsApp] Error reading templates file:", err.message);
  }
  saveTemplates(DEFAULT_TEMPLATES);
  return { ...DEFAULT_TEMPLATES };
}

function saveTemplates(templates) {
  try {
    const tempFile = `${TEMPLATES_FILE}.${process.pid}.tmp`;
    fs.writeFileSync(tempFile, JSON.stringify(templates, null, 2), { encoding: "utf-8", mode: 0o600 });
    fs.renameSync(tempFile, TEMPLATES_FILE);
    return true;
  } catch (err) {
    console.error("[WhatsApp] Error saving templates file:", err.message);
    return false;
  }
}

function getLogs(limit = 50) {
  try {
    if (fs.existsSync(LOGS_FILE)) {
      const data = fs.readFileSync(LOGS_FILE, "utf-8");
      const logs = JSON.parse(data);
      return Array.isArray(logs) ? logs.slice(-Math.max(1, Math.min(Number(limit) || 50, 200))) : [];
    }
  } catch (err) {
    console.error("[WhatsApp] Error reading logs file:", err.message);
  }
  return [];
}

function appendLog(logEntry) {
  try {
    const existing = getLogs(200);
    const updated = [
      ...existing,
      {
        id: `log-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
        timestamp: new Date().toISOString(),
        ...logEntry,
        errorMessage: logEntry.errorMessage || logEntry.error || null,
        messageText: logEntry.messageText || logEntry.preview || "",
      },
    ];
    const tempFile = `${LOGS_FILE}.${process.pid}.tmp`;
    fs.writeFileSync(tempFile, JSON.stringify(updated.slice(-100), null, 2), { encoding: "utf-8", mode: 0o600 });
    fs.renameSync(tempFile, LOGS_FILE);
  } catch (err) {
    console.error("[WhatsApp] Error appending log:", err.message);
  }
}

function updateLogDelivery(messageId, deliveryStatus) {
  try {
    const logs = getLogs(1000);
    const index = logs.findIndex((entry) => entry.messageId === messageId);
    if (index < 0) return;
    logs[index] = {
      ...logs[index],
      deliveryStatus,
      delivered: deliveryStatus === "DELIVERED" || deliveryStatus === "READ",
      deliveredAt: new Date().toISOString(),
    };
    const tempFile = `${LOGS_FILE}.${process.pid}.tmp`;
    fs.writeFileSync(tempFile, JSON.stringify(logs.slice(-100), null, 2), { mode: 0o600 });
    fs.renameSync(tempFile, LOGS_FILE);
  } catch (err) {
    console.error("[WhatsApp] Could not update delivery receipt:", err.message);
  }
}

function stableMessageKey(input) {
  return crypto.createHash("sha256").update(input).digest("hex");
}

function sendWithTimeout(promise, timeoutMs) {
  let timeout;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timeout = setTimeout(() => reject(new Error("WhatsApp did not confirm acceptance before the timeout. The outcome is unknown; check the chat and logs before retrying.")), timeoutMs);
    }),
  ]).finally(() => clearTimeout(timeout));
}

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

function scheduleReconnect(delayMs = 3000) {
  if (!allowReconnect || isInitializing) return;
  if (reconnectTimer) clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    initializeWhatsAppClient().catch((err) => {
      console.error("[WhatsApp] Reconnect failed:", err.message);
    });
  }, delayMs);
}

function bindSocketEvents(client, saveCreds) {
  client.ev.on("creds.update", async () => {
    if (sock === client && typeof saveCreds === "function") {
      try {
        await saveCreds();
      } catch (err) {
        console.warn("[WhatsApp] Failed to persist session credentials:", err.message);
      }
    }
  });

  client.ev.on("messages.update", (updates = []) => {
    for (const item of updates) {
      const status = item.update?.status;
      const messageId = item.key?.id;
      if (!messageId) continue;
      if (status === 3) updateLogDelivery(messageId, "DELIVERED");
      else if (status >= 4) updateLogDelivery(messageId, "READ");
    }
  });

  client.ev.on("message-receipt.update", (updates = []) => {
    for (const item of updates) {
      const messageId = item.key?.id;
      const receipt = item.receipt || {};
      if (!messageId) continue;
      const deliveryStatus = receipt.readTimestamp || receipt.playedTimestamp
        ? "READ"
        : receipt.receiptTimestamp
          ? "DELIVERED"
          : null;
      if (deliveryStatus) updateLogDelivery(messageId, deliveryStatus);
    }
  });

  client.ev.on("connection.update", async (update) => {
    const { connection, lastDisconnect, qr } = update || {};
    if (sock !== client) return;

    if (qr) {
      try {
        currentQrCodeDataUrl = await qrcodeLib.toDataURL(qr, {
          margin: 2,
          scale: 6,
          color: { dark: "#0F172A", light: "#FFFFFF" },
        });
        isInitializing = false;
        if (sock !== client) return;
        setStatus("QR_READY", { error: null });
        console.log("[WhatsApp] QR ready. Scan from the hotel WhatsApp app (Linked devices).");
      } catch (qrErr) {
        setStatus("ERROR", { error: `Could not generate WhatsApp QR code: ${qrErr.message}` });
        console.error("[WhatsApp] Failed to render QR:", qrErr.message);
      }
    }

    if (connection === "open") {
      if (sock !== client) return;
      isInitializing = false;
      currentQrCodeDataUrl = null;
      initializationError = null;
      const user = client.user || {};
      connectedNumber = extractPhoneFromJid(user.id) || extractPhoneFromJid(user.jid);
      connectedPushname = user.name || user.notify || connectedNumber || "Hotel Reception";
      setStatus("CONNECTED", { error: null });
      console.log(`[WhatsApp] Connected as ${connectedPushname} (+${connectedNumber || "unknown"})`);
    }

    if (connection === "close") {
      if (sock !== client) return;
      const statusCode =
        lastDisconnect?.error?.output?.statusCode ||
        lastDisconnect?.error?.statusCode ||
        null;
      const loggedOut = statusCode === DisconnectReason.loggedOut;
      const reason = lastDisconnect?.error?.message || `code ${statusCode}`;
      console.warn(`[WhatsApp] Connection closed (${reason}). loggedOut=${loggedOut}`);

      sock = null;
      currentQrCodeDataUrl = null;
      connectedNumber = null;
      connectedPushname = null;
      isInitializing = false;

      if (loggedOut) {
        allowReconnect = false;
        try { fs.rmSync(AUTH_DIR, { recursive: true, force: true }); } catch (err) {
          console.warn("[WhatsApp] Could not clear invalid session files:", err.message);
        }
        setStatus("DISCONNECTED", { error: "WhatsApp session expired. Scan the QR code again." });
        return;
      }

      setStatus("DISCONNECTED", { error: `Connection dropped: ${reason}` });
      if (allowReconnect) {
        const delay = statusCode === DisconnectReason.restartRequired ? 1000 : 4000;
        scheduleReconnect(delay);
      }
    }
  });
}

async function initializeWhatsAppClient() {
  if (initializePromise) return initializePromise;
  initializePromise = initializeWhatsAppClientInternal();
  try {
    await initializePromise;
  } finally {
    initializePromise = null;
  }
}

async function initializeWhatsAppClientInternal() {
  if (isInitializing) {
    console.log("[WhatsApp] Initialization already in progress.");
    return;
  }
  if (sock && clientStatus === "CONNECTED") {
    console.log("[WhatsApp] Client already connected.");
    return;
  }
  if (clientStatus === "QR_READY" && currentQrCodeDataUrl && sock) {
    console.log("[WhatsApp] QR already waiting for scan.");
    return;
  }

  isInitializing = true;
  const currentGeneration = ++generation;
  allowReconnect = true;
  setStatus("INITIALIZING", { error: null });
  currentQrCodeDataUrl = null;

  try {
    if (sock) {
      try {
        sock.end(undefined);
      } catch (_) {}
      sock = null;
    }

    const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
    if (currentGeneration !== generation) return;
    if (!state.creds.registered && hasAuthFiles()) {
      fs.rmSync(AUTH_DIR, { recursive: true, force: true });
      fs.mkdirSync(AUTH_DIR, { recursive: true });
    }

    if (state.creds.registered) {
      setStatus("AUTHENTICATED", { error: null });
    }

    let version = [2, 3000, 1027934701];
    try {
      const fetched = await fetchLatestBaileysVersion();
      if (currentGeneration !== generation) return;
      if (fetched?.version) version = fetched.version;
    } catch (verErr) {
      console.warn("[WhatsApp] Using fallback WA version:", verErr.message);
    }

    const client = makeWASocket({
      version,
      logger,
      printQRInTerminal: false,
      auth: {
        creds: state.creds,
        keys: makeCacheableSignalKeyStore(state.keys, logger),
      },
      browser: Browsers.windows("EaseInn Hotel"),
      markOnlineOnConnect: false,
      syncFullHistory: false,
      generateHighQualityLinkPreview: false,
      connectTimeoutMs: 60_000,
      keepAliveIntervalMs: 25_000,
      retryRequestDelayMs: 250,
      defaultQueryTimeoutMs: 60_000,
    });

    if (currentGeneration !== generation) {
      try { client.end(undefined); } catch (_) {}
      return;
    }

    sock = client;
    bindSocketEvents(client, saveCreds);
    console.log(
      `[WhatsApp] Socket started. Existing session files: ${hasAuthFiles() ? "yes" : "no"}`
    );
  } catch (err) {
    if (currentGeneration !== generation) return;
    isInitializing = false;
    sock = null;
    setStatus("ERROR", { error: err.message });
    console.error("[WhatsApp] Initialization error:", err);
    if (allowReconnect && hasAuthFiles()) scheduleReconnect(8000);
  }
}

async function disconnectWhatsAppClient({ preserveSession = false } = {}) {
  generation += 1;
  isInitializing = false;
  allowReconnect = false;
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }

  if (sock) {
    const socketToClose = sock;
    if (preserveSession) {
      try { socketToClose.end(undefined); } catch (_) {}
    } else {
      try { await socketToClose.logout(); } catch (_) {
        try { socketToClose.end(undefined); } catch (__) {}
      }
    }
    sock = null;
  }

  currentQrCodeDataUrl = null;
  connectedNumber = null;
  connectedPushname = null;
  isInitializing = false;
  if (!preserveSession) {
    try { fs.rmSync(AUTH_DIR, { recursive: true, force: true }); } catch (err) {
      console.warn("[WhatsApp] Could not clear unlinked session files:", err.message);
    }
  }
  setStatus("DISCONNECTED", { error: null });
  return { success: true, message: preserveSession ? "WhatsApp socket stopped; saved session preserved." : "WhatsApp account unlinked and credentials removed." };
}

async function waitUntilConnected(timeoutMs = 30000) {
  if (sock && clientStatus === "CONNECTED") return true;
  if (!isInitializing && clientStatus !== "CONNECTED") {
    initializeWhatsAppClient().catch(() => {});
  }
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (sock && clientStatus === "CONNECTED") return true;
    await new Promise((r) => setTimeout(r, 400));
  }
  return !!(sock && clientStatus === "CONNECTED");
}

async function resolveRecipientJid(cleanPhone) {
  if (!sock || clientStatus !== "CONNECTED") return { jid: null, exists: null };

  try {
    const results = await sendWithTimeout(sock.onWhatsApp(cleanPhone), 12000);
    if (Array.isArray(results) && results.length > 0) {
      const registered = results.find((r) => r && r.exists && r.jid) || results.find((r) => r && r.exists);
      if (registered) {
        return { jid: registered.jid, exists: true };
      }
      if (results.every((r) => r && r.exists === false)) {
        return { jid: null, exists: false };
      }
    }
  } catch (err) {
    console.warn("[WhatsApp] onWhatsApp lookup failed:", err.message);
    return { jid: null, exists: null, error: err.message };
  }

  return { jid: null, exists: null };
}

function isConfirmedSendResult(sent) {
  if (!sent || typeof sent !== "object") return false;
  const key = sent.key;
  if (!key) return false;
  if (key.fromMe === false) return false;
  return Boolean(key.id);
}

async function sendWhatsAppNotification({
  templateId,
  recipientPhone,
  customMessage,
  context = {},
  bypassDuplicateCheck = false,
  stayId,
}) {
  const currentSend = sendQueue.then(() => sendWhatsAppNotificationNow({
    templateId, recipientPhone, customMessage, context, bypassDuplicateCheck, stayId,
  }));
  sendQueue = currentSend.catch(() => {});
  return currentSend;
}

async function sendWhatsAppNotificationNow({
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
      delivered: false,
      context,
    });
    return { success: false, delivered: false, error: errorMsg, code: "INVALID_PHONE" };
  }

  const templates = getTemplates();
  let messageBody = customMessage;

  if (templateId) {
    const templateConfig = templates[templateId];
    if (!templateConfig) {
      return { success: false, delivered: false, error: `Template "${templateId}" not found.`, code: "TEMPLATE_NOT_FOUND" };
    }
    if (!templateConfig.enabled) {
      return { success: false, delivered: false, error: `Template "${templateId}" is muted/disabled.`, code: "TEMPLATE_DISABLED" };
    }
    messageBody = interpolateTemplate(templateConfig.template, context);
  }

  if (!messageBody || !messageBody.trim()) {
    return { success: false, delivered: false, error: "Cannot send empty WhatsApp message body.", code: "EMPTY_BODY" };
  }

  if (Buffer.byteLength(messageBody, "utf8") > 65536) {
    return { success: false, accepted: false, error: "Message is too long. Keep it under 64 KB.", code: "MESSAGE_TOO_LARGE" };
  }

  const messageHash = stableMessageKey(messageBody);
  const dedupeKey = stayId
    ? `${stayId}_${templateId || "custom"}`
    : `content_${stableMessageKey(`${norm.cleanPhone}|${templateId || "custom"}|${messageHash}`)}`;
  if (!bypassDuplicateCheck && duplicateCache.has(dedupeKey)) {
    const previous = duplicateCache.get(dedupeKey);
    if (Date.now() - previous.timestamp < 300000) {
      console.warn(`[WhatsApp] Duplicate message suppressed for key: ${dedupeKey}`);
      return {
        success: false,
        delivered: false,
        suppressed: true,
        message: "Duplicate message skipped (already sent within 5 minutes).",
        code: "DUPLICATE_SUPPRESSED",
      };
    }
  }

  if (pendingSends.has(dedupeKey)) {
    return { success: false, accepted: false, delivered: false, suppressed: true, message: "This message is already being submitted. Check the WhatsApp chat before retrying.", code: "SEND_IN_PROGRESS" };
  }
  const sendAttempt = { outcomeUnknown: false };
  pendingSends.set(dedupeKey, sendAttempt);

  const ready = await waitUntilConnected(30000);
  if (!ready || !sock || clientStatus !== "CONNECTED") {
    const errorMsg = "WhatsApp is not connected. Open WhatsApp Automation and scan the QR code.";
    appendLog({
      templateId: templateId || "custom",
      recipientPhone: norm.cleanPhone,
      status: "FAILED",
      error: errorMsg,
      preview: messageBody.slice(0, 100),
      delivered: false,
      context,
    });
    pendingSends.delete(dedupeKey);
    return { success: false, delivered: false, error: errorMsg, code: "NOT_CONNECTED" };
  }

  if (!bypassDuplicateCheck && duplicateCache.has(dedupeKey)) {
    const previous = duplicateCache.get(dedupeKey);
    if (Date.now() - previous.timestamp < 300000) {
      pendingSends.delete(dedupeKey);
      return { success: false, accepted: false, delivered: false, suppressed: true, messageId: previous.messageId, message: "Duplicate message skipped because WhatsApp already accepted it within the last 5 minutes.", code: "DUPLICATE_SUPPRESSED" };
    }
  }

  if (!bypassDuplicateCheck && duplicateCache.has(dedupeKey)) {
    const previous = duplicateCache.get(dedupeKey);
    if (Date.now() - previous.timestamp < 300000) {
      return { success: false, accepted: false, delivered: false, suppressed: true, messageId: previous.messageId, message: "Duplicate message skipped because WhatsApp already accepted it within the last 5 minutes.", code: "DUPLICATE_SUPPRESSED" };
    }
  }

  const resolved = await resolveRecipientJid(norm.cleanPhone);
  if (!resolved.jid) {
    const errorMsg = resolved.exists === false
      ? `+${norm.cleanPhone} is not registered on WhatsApp.`
      : "Could not verify this number with WhatsApp. Check the country code and try again.";
    appendLog({ templateId: templateId || "custom", recipientPhone: norm.cleanPhone, status: "FAILED", error: errorMsg, preview: messageBody.slice(0, 100), delivered: false, context });
    pendingSends.delete(dedupeKey);
    return { success: false, delivered: false, error: errorMsg, code: resolved.exists === false ? "NOT_ON_WHATSAPP" : "RECIPIENT_LOOKUP_FAILED" };
  }
  try {
    console.log(`[WhatsApp] Sending to ${resolved.jid}...`);
    const sendingSocket = sock;
    const sendPromise = sendingSocket.sendMessage(resolved.jid, { text: messageBody });
    sendAttempt.promise = sendPromise;
    let acceptanceRecorded = false;
    const recordAccepted = (acceptedMessage) => {
      if (acceptanceRecorded || !isConfirmedSendResult(acceptedMessage)) return;
      acceptanceRecorded = true;
      const acceptedAt = Date.now();
      const acceptedMessageId = acceptedMessage.key.id;
      duplicateCache.set(dedupeKey, { timestamp: acceptedAt, messageId: acceptedMessageId });
      persistAcceptedMessage({ dedupeKey, timestamp: acceptedAt, messageId: acceptedMessageId });
      appendLog({
        templateId: templateId || "custom",
        recipientPhone: norm.cleanPhone,
        status: "ACCEPTED",
        messageId: acceptedMessageId,
        preview: messageBody.slice(0, 120),
        delivered: false,
        deliveryStatus: "PENDING",
        accepted: true,
        context,
      });
    };
    sendPromise.then((lateResult) => {
      recordAccepted(lateResult);
      pendingSends.delete(dedupeKey);
    }, () => {
      pendingSends.delete(dedupeKey);
    });
    const sent = await sendWithTimeout(sendPromise, SEND_TIMEOUT_MS);
    if (!isConfirmedSendResult(sent)) {
      throw new Error("WhatsApp did not acknowledge the message. It was not delivered.");
    }

    const messageId = sent.key.id;
    recordAccepted(sent);
    console.log(`[WhatsApp] Accepted by WhatsApp for ${norm.cleanPhone}: ${messageId}`);
    return {
      success: true,
      accepted: true,
      delivered: false,
      deliveryStatus: "PENDING",
      message: "WhatsApp accepted the message for sending. Recipient delivery has not been confirmed yet.",
      messageId,
      recipient: norm.cleanPhone,
    };
  } catch (sendErr) {
    const errMsg = sendErr.message || String(sendErr);
    if (sendErr.message?.includes("outcome is unknown")) sendAttempt.outcomeUnknown = true;
    if (sendAttempt.outcomeUnknown && duplicateCache.has(dedupeKey)) {
      const accepted = duplicateCache.get(dedupeKey);
      if (accepted.messageId) {
        return {
          success: true,
          accepted: true,
          delivered: false,
          deliveryStatus: "PENDING",
          message: "WhatsApp accepted the message before the response timed out. Recipient delivery is not confirmed yet.",
          messageId: accepted.messageId,
          recipient: norm.cleanPhone,
        };
      }
    }
    if (sendAttempt.outcomeUnknown) {
      const timestamp = Date.now();
      duplicateCache.set(dedupeKey, { timestamp, messageId: null });
      persistAcceptedMessage({ dedupeKey, timestamp, messageId: null });
    }
    console.error(`[WhatsApp] Send failed for ${norm.cleanPhone}:`, errMsg);
    appendLog({
      templateId: templateId || "custom",
      recipientPhone: norm.cleanPhone,
      status: sendAttempt.outcomeUnknown ? "UNKNOWN" : "FAILED",
      error: errMsg,
      preview: messageBody.slice(0, 100),
      delivered: false,
      context,
    });
    return {
      success: false,
      delivered: false,
      error: errMsg,
      code: sendAttempt.outcomeUnknown ? "SEND_OUTCOME_UNKNOWN" : "SEND_FAILED",
    };
  } finally {
    if (!sendAttempt.outcomeUnknown) pendingSends.delete(dedupeKey);
  }
}

function persistAcceptedMessage(entry) {
  try {
    const file = path.join(DATA_DIR, "whatsapp_idempotency.json");
    let rows = [];
    if (fs.existsSync(file)) {
      const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
      if (Array.isArray(parsed)) rows = parsed;
    }
    rows = rows.filter((row) => row.dedupeKey !== entry.dedupeKey && Date.now() - row.timestamp < 86400000);
    rows.push(entry);
    const tempFile = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(tempFile, JSON.stringify(rows.slice(-2000)), { mode: 0o600 });
    fs.renameSync(tempFile, file);
  } catch (err) {
    console.error("[WhatsApp] Could not persist duplicate protection:", err.message);
  }
}

function loadAcceptedMessages() {
  try {
    const file = path.join(DATA_DIR, "whatsapp_idempotency.json");
    if (!fs.existsSync(file)) return;
    const rows = JSON.parse(fs.readFileSync(file, "utf8"));
    if (!Array.isArray(rows)) return;
    for (const row of rows) {
      if (row && row.dedupeKey && Number.isFinite(row.timestamp) && Date.now() - row.timestamp < 300000) {
        duplicateCache.set(row.dedupeKey, row);
      }
    }
  } catch (err) {
    console.error("[WhatsApp] Could not load duplicate protection:", err.message);
  }
}

loadAcceptedMessages();

function getStatus() {
  const templates = getTemplates();
  return {
    status: clientStatus,
    engine: "baileys",
    isConnected: clientStatus === "CONNECTED",
    isReady: clientStatus === "CONNECTED",
    qrCodeDataUrl: currentQrCodeDataUrl,
    hasActiveQr: Boolean(currentQrCodeDataUrl),
    connectedNumber,
    connectedPushname,
    lastStatusChange,
    initializationError,
    hasPersistedSession: hasAuthFiles(),
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
