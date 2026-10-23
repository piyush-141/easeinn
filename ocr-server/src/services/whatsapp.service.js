// src/services/whatsapp.service.js
// WhatsApp engine for EaseInn — Baileys multi-device with Multi-Tenant Session Management & Pairing Code Support
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
  sanitizeHotelId,
  getHotelAuthDir,
  getHotelTemplatesFile,
  getHotelLogsFile,
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

const configuredSendTimeout = Number(process.env.WHATSAPP_SEND_TIMEOUT_MS || 90000);
const SEND_TIMEOUT_MS = Number.isFinite(configuredSendTimeout) && configuredSendTimeout >= 10000 && configuredSendTimeout <= 180000
  ? configuredSendTimeout
  : 90000;

// Maximum cached messages for Signal protocol retry receipts
const MAX_CACHED_MESSAGES = 1500;

/**
 * HotelWhatsAppSession represents a completely isolated WhatsApp connection,
 * credentials folder, logs, templates, and message store for a single hotel/account.
 */
class HotelWhatsAppSession {
  constructor(hotelId) {
    this.hotelId = sanitizeHotelId(hotelId);
    this.authDir = getHotelAuthDir(this.hotelId);
    this.templatesFile = getHotelTemplatesFile(this.hotelId);
    this.logsFile = getHotelLogsFile(this.hotelId);
    this.sock = null;
    this.clientStatus = "DISCONNECTED"; // DISCONNECTED | INITIALIZING | QR_READY | PAIRING_CODE_READY | AUTHENTICATED | CONNECTED | ERROR
    this.isInitializing = false;
    this.allowReconnect = true;
    this.reconnectTimer = null;
    this.currentQrCodeDataUrl = null;
    this.currentQrRawString = null;
    this.pairingCode = null;
    this.connectedNumber = null;
    this.connectedPushname = null;
    this.lastStatusChange = new Date().toISOString();
    this.initializationError = null;
    this.duplicateCache = new Map();
    this.initializePromise = null;
    this.sendQueue = Promise.resolve();
    this.generation = 0;
    this.pendingSends = new Map();
    this.earlyDeliveryReceipts = new Map();
    this.messageStore = new Map();

    this.ensureDirs();
    this.loadAcceptedMessages();
  }

  ensureDirs() {
    try {
      if (!fs.existsSync(this.authDir)) {
        fs.mkdirSync(this.authDir, { recursive: true, mode: 0o700 });
      }
      const dataDir = path.dirname(this.templatesFile);
      if (!fs.existsSync(dataDir)) {
        fs.mkdirSync(dataDir, { recursive: true });
      }
    } catch (_) {}
  }

  secureAuthFiles() {
    if (process.platform === "win32") return;
    try {
      fs.chmodSync(this.authDir, 0o700);
      for (const name of fs.readdirSync(this.authDir)) {
        const file = path.join(this.authDir, name);
        if (fs.statSync(file).isFile()) fs.chmodSync(file, 0o600);
      }
    } catch (err) {
      console.warn(`[WhatsApp] [${this.hotelId}] Could not restrict session file permissions:`, err.message);
    }
  }

  setStatus(next, extra = {}) {
    this.clientStatus = next;
    this.lastStatusChange = new Date().toISOString();
    if (extra.error !== undefined) this.initializationError = extra.error;
  }

  hasAuthFiles() {
    try {
      return fs.existsSync(path.join(this.authDir, "creds.json"));
    } catch (_) {
      return false;
    }
  }

  cacheMessage(id, message) {
    if (!id || !message) return;
    if (this.messageStore.size >= MAX_CACHED_MESSAGES) {
      const oldestKey = this.messageStore.keys().next().value;
      this.messageStore.delete(oldestKey);
    }
    this.messageStore.set(id, message);
  }

  getTemplates() {
    try {
      if (fs.existsSync(this.templatesFile)) {
        const data = fs.readFileSync(this.templatesFile, "utf-8");
        const parsed = JSON.parse(data);
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
          return parsed;
        }
      }
    } catch (err) {
      console.error(`[WhatsApp] [${this.hotelId}] Error reading templates:`, err.message);
    }
    this.saveTemplates(DEFAULT_TEMPLATES);
    return { ...DEFAULT_TEMPLATES };
  }

  saveTemplates(templates) {
    try {
      const tempFile = `${this.templatesFile}.${process.pid}.tmp`;
      fs.writeFileSync(tempFile, JSON.stringify(templates, null, 2), { encoding: "utf-8", mode: 0o600 });
      fs.renameSync(tempFile, this.templatesFile);
      return true;
    } catch (err) {
      console.error(`[WhatsApp] [${this.hotelId}] Error saving templates:`, err.message);
      return false;
    }
  }

  getLogs(limit = 50) {
    try {
      if (fs.existsSync(this.logsFile)) {
        const data = fs.readFileSync(this.logsFile, "utf-8");
        const logs = JSON.parse(data);
        if (Array.isArray(logs)) {
          const sorted = [...logs].reverse();
          return sorted.slice(0, Math.max(1, Math.min(Number(limit) || 50, 200)));
        }
      }
    } catch (err) {
      console.error(`[WhatsApp] [${this.hotelId}] Error reading logs:`, err.message);
    }
    return [];
  }

  appendLog(logEntry) {
    try {
      const existing = this.getLogs(200);
      const updated = [
        ...existing,
        {
          id: `log-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
          timestamp: new Date().toISOString(),
          hotelId: this.hotelId,
          ...logEntry,
          errorMessage: logEntry.errorMessage || logEntry.error || null,
          messageText: logEntry.messageText || logEntry.preview || "",
        },
      ];
      const tempFile = `${this.logsFile}.${process.pid}.tmp`;
      fs.writeFileSync(tempFile, JSON.stringify(updated.slice(-100), null, 2), { encoding: "utf-8", mode: 0o600 });
      fs.renameSync(tempFile, this.logsFile);
    } catch (err) {
      console.error(`[WhatsApp] [${this.hotelId}] Error appending log:`, err.message);
    }
  }

  updateLogDelivery(messageId, deliveryStatus) {
    try {
      const logs = this.getLogs(1000);
      const index = logs.findIndex((entry) => entry.messageId === messageId);
      if (index < 0) return false;
      const previousStatus = logs[index].deliveryStatus;
      const rank = { PENDING: 0, DELIVERED: 1, READ: 2 };
      if ((rank[previousStatus] || 0) > (rank[deliveryStatus] || 0)) return true;
      logs[index] = {
        ...logs[index],
        deliveryStatus,
        delivered: deliveryStatus === "DELIVERED" || deliveryStatus === "READ",
        deliveredAt: new Date().toISOString(),
      };
      const tempFile = `${this.logsFile}.${process.pid}.tmp`;
      fs.writeFileSync(tempFile, JSON.stringify(logs.slice(-100), null, 2), { mode: 0o600 });
      fs.renameSync(tempFile, this.logsFile);
      return true;
    } catch (err) {
      console.error(`[WhatsApp] [${this.hotelId}] Could not update delivery receipt:`, err.message);
      return false;
    }
  }

  recordDeliveryReceipt(messageId, deliveryStatus) {
    if (this.updateLogDelivery(messageId, deliveryStatus)) return;
    const now = Date.now();
    for (const [id, receipt] of this.earlyDeliveryReceipts) {
      if (now - receipt.timestamp > 5 * 60 * 1000) this.earlyDeliveryReceipts.delete(id);
    }
    const existing = this.earlyDeliveryReceipts.get(messageId);
    const rank = { DELIVERED: 1, READ: 2 };
    if (!existing || (rank[deliveryStatus] || 0) > (rank[existing.status] || 0)) {
      this.earlyDeliveryReceipts.set(messageId, { status: deliveryStatus, timestamp: now });
    }
    while (this.earlyDeliveryReceipts.size > 500) {
      this.earlyDeliveryReceipts.delete(this.earlyDeliveryReceipts.keys().next().value);
    }
  }

  persistAcceptedMessage(entry) {
    try {
      const file = path.join(path.dirname(this.logsFile), "whatsapp_idempotency.json");
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
      console.error(`[WhatsApp] [${this.hotelId}] Idempotency persist failed:`, err.message);
    }
  }

  loadAcceptedMessages() {
    try {
      const file = path.join(path.dirname(this.logsFile), "whatsapp_idempotency.json");
      if (!fs.existsSync(file)) return;
      const rows = JSON.parse(fs.readFileSync(file, "utf8"));
      if (!Array.isArray(rows)) return;
      for (const row of rows) {
        if (row && row.dedupeKey && Number.isFinite(row.timestamp) && Date.now() - row.timestamp < 300000) {
          this.duplicateCache.set(row.dedupeKey, row);
        }
      }
    } catch (_) {}
  }

  scheduleReconnect(delayMs = 3000) {
    if (!this.allowReconnect || this.isInitializing) return;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.initializeWhatsAppClient().catch((err) => {
        console.error(`[WhatsApp] [${this.hotelId}] Reconnect failed:`, err.message);
      });
    }, delayMs);
  }

  bindSocketEvents(client, saveCreds) {
    client.ev.on("creds.update", async () => {
      if (this.sock === client && typeof saveCreds === "function") {
        try {
          await saveCreds();
        } catch (err) {
          console.warn(`[WhatsApp] [${this.hotelId}] Failed to persist session credentials:`, err.message);
        }
      }
    });

    client.ev.on("messages.update", (updates = []) => {
      for (const item of updates) {
        const status = item.update?.status;
        const messageId = item.key?.id;
        if (!messageId) continue;
        if (status === 3) this.recordDeliveryReceipt(messageId, "DELIVERED");
        else if (status >= 4) this.recordDeliveryReceipt(messageId, "READ");
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
        if (deliveryStatus) this.recordDeliveryReceipt(messageId, deliveryStatus);
      }
    });

    client.ev.on("messages.upsert", async ({ messages }) => {
      for (const msg of messages || []) {
        if (msg?.key?.id && msg?.message) {
          this.cacheMessage(msg.key.id, msg.message);
        }
      }
    });

    client.ev.on("connection.update", async (update) => {
      const { connection, lastDisconnect, qr } = update || {};
      if (this.sock !== client) return;

      if (qr) {
        try {
          this.currentQrRawString = qr;
          this.currentQrCodeDataUrl = await qrcodeLib.toDataURL(qr, {
            margin: 2,
            scale: 6,
            color: { dark: "#0F172A", light: "#FFFFFF" },
          });
          this.isInitializing = false;
          if (this.sock !== client) return;
          this.setStatus("QR_READY", { error: null });
          console.log(`[WhatsApp] [${this.hotelId}] QR ready. Scan from hotel WhatsApp (Linked devices).`);
        } catch (qrErr) {
          this.setStatus("ERROR", { error: `Could not generate WhatsApp QR code: ${qrErr.message}` });
          console.error(`[WhatsApp] [${this.hotelId}] Failed to render QR:`, qrErr.message);
        }
      }

      if (connection === "open") {
        if (this.sock !== client) return;
        this.isInitializing = false;
        this.currentQrCodeDataUrl = null;
        this.currentQrRawString = null;
        this.pairingCode = null;
        this.initializationError = null;
        const user = client.user || {};
        this.connectedNumber = extractPhoneFromJid(user.id) || extractPhoneFromJid(user.jid);
        this.connectedPushname = user.name || user.notify || this.connectedNumber || "Hotel Reception";
        this.setStatus("CONNECTED", { error: null });
        console.log(`[WhatsApp] [${this.hotelId}] Connected as ${this.connectedPushname} (+${this.connectedNumber || "unknown"})`);
      }

      if (connection === "close") {
        if (this.sock !== client) return;
        const statusCode =
          lastDisconnect?.error?.output?.statusCode ||
          lastDisconnect?.error?.statusCode ||
          null;
        // DisconnectReason.loggedOut = 401 (WhatsApp explicitly kicked us out)
        // ONLY delete session when we get an explicit 401 logout — NOT for network drops
        const loggedOut = statusCode === DisconnectReason.loggedOut; // 401
        const connectionReplaced = statusCode === 440; // Another device connected
        const reason = lastDisconnect?.error?.message || `code ${statusCode}`;
        console.warn(`[WhatsApp] [${this.hotelId}] Connection closed (${reason}). loggedOut=${loggedOut} code=${statusCode}`);

        this.sock = null;
        this.currentQrCodeDataUrl = null;
        this.currentQrRawString = null;
        this.pairingCode = null;
        this.connectedNumber = null;
        this.connectedPushname = null;
        this.isInitializing = false;

        if (loggedOut || connectionReplaced) {
          // Actual WhatsApp logout: clear credentials so user must re-scan
          this.allowReconnect = false;
          try {
            fs.rmSync(this.authDir, { recursive: true, force: true });
          } catch (err) {
            console.warn(`[WhatsApp] [${this.hotelId}] Could not clear invalid session files:`, err.message);
          }
          this.setStatus("DISCONNECTED", {
            error: loggedOut
              ? "WhatsApp session expired or was logged out from the phone. Please link your device again."
              : "WhatsApp was connected on another device. Please link again.",
          });
          return;
        }

        // Network drop / server restart / Render wakeup — preserve session files, reconnect
        this.setStatus("DISCONNECTED", { error: `Connection dropped: ${reason}. Auto-reconnecting...` });
        if (this.allowReconnect) {
          // Use exponential backoff: restart-required gets fast reconnect, others get 4s
          const delay = statusCode === DisconnectReason.restartRequired ? 1000 : 4000;
          this.scheduleReconnect(delay);
        }
      }
    });
  }

  async initializeWhatsAppClient(options = {}) {
    if (this.initializePromise) return this.initializePromise;
    this.initializePromise = this.initializeWhatsAppClientInternal(options);
    try {
      await this.initializePromise;
    } finally {
      this.initializePromise = null;
    }
  }

  async initializeWhatsAppClientInternal(options = {}) {
    const { usePairingCode = false, phoneNumber = null } = options;

    if (this.isInitializing) {
      console.log(`[WhatsApp] [${this.hotelId}] Initialization already in progress.`);
      return;
    }
    if (this.sock && this.clientStatus === "CONNECTED") {
      console.log(`[WhatsApp] [${this.hotelId}] Client already connected.`);
      return;
    }
    if (!usePairingCode && this.clientStatus === "QR_READY" && this.currentQrCodeDataUrl && this.sock) {
      console.log(`[WhatsApp] [${this.hotelId}] QR already waiting for scan.`);
      return;
    }
    if (usePairingCode && this.pairingCode && this.sock) {
      console.log(`[WhatsApp] [${this.hotelId}] Pairing code already active: ${this.pairingCode}`);
      return;
    }

    this.isInitializing = true;
    const currentGeneration = ++this.generation;
    this.allowReconnect = true;
    this.setStatus("INITIALIZING", { error: null });
    this.currentQrCodeDataUrl = null;
    this.currentQrRawString = null;
    this.pairingCode = null;

    try {
      if (this.sock) {
        try { this.sock.end(undefined); } catch (_) {}
        this.sock = null;
      }

      this.ensureDirs();
      const { state, saveCreds } = await useMultiFileAuthState(this.authDir);
      this.secureAuthFiles();
      if (currentGeneration !== this.generation) return;

      if (state.creds.registered) {
        this.setStatus("AUTHENTICATED", { error: null });
      }

      let version = [2, 3000, 1027934701];
      try {
        const fetched = await fetchLatestBaileysVersion();
        if (currentGeneration !== this.generation) return;
        if (fetched?.version) version = fetched.version;
      } catch (verErr) {
        console.warn(`[WhatsApp] [${this.hotelId}] Using fallback WA version:`, verErr.message);
      }

      // Browser descriptor: robust cross-platform detection
      const browser = (Browsers && typeof Browsers.windows === "function")
        ? Browsers.windows("Chrome")
        : (Browsers && typeof Browsers.macOS === "function")
          ? Browsers.macOS("Desktop")
          : ["EaseInn PMS", "Chrome", "122.0.6261.128"];

      const client = makeWASocket({
        version,
        logger,
        printQRInTerminal: false,
        auth: {
          creds: state.creds,
          keys: makeCacheableSignalKeyStore(state.keys, logger),
        },
        browser,
        markOnlineOnConnect: true,
        syncFullHistory: false,
        generateHighQualityLinkPreview: false,
        connectTimeoutMs: 60_000,
        keepAliveIntervalMs: 25_000,
        retryRequestDelayMs: 250,
        maxMsgRetryCount: 5,
        defaultQueryTimeoutMs: 60_000,
        getMessage: async (key) => {
          if (key && key.id && this.messageStore.has(key.id)) {
            return this.messageStore.get(key.id);
          }
          return undefined;
        },
      });

      if (currentGeneration !== this.generation) {
        try { client.end(undefined); } catch (_) {}
        return;
      }

      this.sock = client;
      this.bindSocketEvents(client, async () => {
        await saveCreds();
        this.secureAuthFiles();
      });

      console.log(
        `[WhatsApp] [${this.hotelId}] Socket started. Existing session: ${this.hasAuthFiles() ? "yes" : "no"}`
      );

      // Pairing code generation
      if (usePairingCode && phoneNumber && !state.creds.registered) {
        setTimeout(async () => {
          try {
            if (this.sock === client && !client.authState?.creds?.registered) {
              const rawCode = await client.requestPairingCode(phoneNumber);
              const formatted = rawCode?.match(/.{1,4}/g)?.join("-") || rawCode;
              this.pairingCode = formatted;
              this.setStatus("PAIRING_CODE_READY", { error: null });
              this.isInitializing = false;
              console.log(`[WhatsApp] [${this.hotelId}] Generated pairing code: ${formatted} for phone ${phoneNumber}`);
            }
          } catch (pairErr) {
            console.error(`[WhatsApp] [${this.hotelId}] Error requesting pairing code:`, pairErr.message);
            this.setStatus("ERROR", { error: `Failed to request pairing code: ${pairErr.message}` });
            this.isInitializing = false;
          }
        }, 1500);
      }
    } catch (err) {
      if (currentGeneration !== this.generation) return;
      this.isInitializing = false;
      this.sock = null;
      this.setStatus("ERROR", { error: err.message });
      console.error(`[WhatsApp] [${this.hotelId}] Initialization error:`, err);
      if (this.allowReconnect && this.hasAuthFiles()) this.scheduleReconnect(8000);
    }
  }

  async disconnectWhatsAppClient({ preserveSession = false } = {}) {
    this.generation += 1;
    this.isInitializing = false;
    this.allowReconnect = false;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.sock) {
      const socketToClose = this.sock;
      if (preserveSession) {
        try { socketToClose.end(undefined); } catch (_) {}
      } else {
        try {
          await socketToClose.logout();
        } catch (_) {
          try { socketToClose.end(undefined); } catch (__) {}
        }
      }
      this.sock = null;
    }

    this.currentQrCodeDataUrl = null;
    this.currentQrRawString = null;
    this.pairingCode = null;
    this.connectedNumber = null;
    this.connectedPushname = null;
    this.isInitializing = false;

    if (!preserveSession) {
      try {
        fs.rmSync(this.authDir, { recursive: true, force: true });
      } catch (err) {
        console.warn(`[WhatsApp] [${this.hotelId}] Could not clear session files:`, err.message);
      }
    }
    this.setStatus("DISCONNECTED", { error: null });
    return {
      success: true,
      message: preserveSession
        ? "WhatsApp socket stopped; saved session preserved."
        : "WhatsApp account unlinked and credentials removed.",
    };
  }

  async waitUntilConnected(timeoutMs = 30000) {
    if (this.sock && this.clientStatus === "CONNECTED") return true;
    if (!this.isInitializing && this.clientStatus !== "CONNECTED") {
      this.initializeWhatsAppClient().catch(() => {});
    }
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      if (this.sock && this.clientStatus === "CONNECTED") return true;
      await new Promise((r) => setTimeout(r, 400));
    }
    return !!(this.sock && this.clientStatus === "CONNECTED");
  }

  async resolveRecipientJid(cleanPhone) {
    if (!this.sock || this.clientStatus !== "CONNECTED") return { jid: null, exists: null };
    try {
      const results = await sendWithTimeout(this.sock.onWhatsApp(cleanPhone), 12000);
      if (Array.isArray(results) && results.length > 0) {
        const registered = results.find((r) => r && r.exists && r.jid) || results.find((r) => r && r.exists);
        if (registered) return { jid: registered.jid, exists: true };
        if (results.every((r) => r && r.exists === false)) return { jid: null, exists: false };
      }
    } catch (err) {
      console.warn(`[WhatsApp] [${this.hotelId}] onWhatsApp lookup notice:`, err.message);
      return { jid: null, exists: null, error: err.message };
    }
    return { jid: null, exists: null };
  }

  getStatus() {
    const templates = this.getTemplates();
    return {
      hotelId: this.hotelId,
      status: this.clientStatus,
      engine: "baileys",
      isConnected: this.clientStatus === "CONNECTED",
      isReady: this.clientStatus === "CONNECTED" && !!this.sock,
      qrCodeDataUrl: this.currentQrCodeDataUrl,
      qrRawString: this.currentQrRawString,
      pairingCode: this.pairingCode,
      hasActiveQr: Boolean(this.currentQrRawString || this.currentQrCodeDataUrl),
      connectedNumber: this.connectedNumber,
      connectedPushname: this.connectedPushname,
      lastStatusChange: this.lastStatusChange,
      initializationError: this.initializationError,
      hasPersistedSession: this.hasAuthFiles(),
      activeTemplatesCount: Object.values(templates).filter((t) => t.enabled).length,
      totalTemplatesCount: Object.values(templates).length,
      supportedPlaceholders: SUPPORTED_PLACEHOLDERS,
    };
  }
}

// Multi-tenant sessions registry
const sessions = new Map();

function getSession(hotelId = "default") {
  const sanitized = sanitizeHotelId(hotelId);
  if (!sessions.has(sanitized)) {
    sessions.set(sanitized, new HotelWhatsAppSession(sanitized));
  }
  return sessions.get(sanitized);
}

function extractPhoneFromJid(jid) {
  if (!jid || typeof jid !== "string") return null;
  const user = jid.split("@")[0] || "";
  const phone = user.split(":")[0];
  return phone || null;
}

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

function interpolateTemplate(templateString, context = {}) {
  let result = templateString || "";

  const rawRoom = context.roomNumber ? String(context.roomNumber).trim() : "";
  const unassignedValues = ["", "unassigned", "pending", "tbd", "n/a", "none", "null", "undefined"];
  const hasRoom = rawRoom !== "" && !unassignedValues.includes(rawRoom.toLowerCase());

  if (!hasRoom) {
    result = result.replace(/^[ \t]*[🛏️\s•\-\*]*Room:?\s*\{roomNumber\}[^\r\n]*(\r?\n)?/gim, "");
    result = result.replace(/^[ \t]*[🛏️\s•\-\*]*कमरा:?\s*\{roomNumber\}[^\r\n]*(\r?\n)?/gim, "");
    result = result.replace(/\s+in Room\s*\{roomNumber\}/gi, "");
    result = result.replace(/कमरे\s*\{roomNumber\}\s*में\s*/gi, "");
    result = result.replace(/to Room\s*\{roomNumber\}\s*/gi, "");
    result = result.replace(/कमरा\s*\{roomNumber\}\s*में\s*/gi, "");
    result = result.replace(/from Room\s*\{roomNumber\}\s*/gi, "");
    result = result.replace(/कमरा\s*\{roomNumber\}\s*से\s*/gi, "");
  }

  const sampleEn = "We have an update regarding your stay.";
  const sampleHi = "आपके प्रवास के संबंध में एक जानकारी।";
  const msgEn = context.message !== undefined && context.message !== null && String(context.message).trim() !== ""
    ? String(context.message)
    : (context.isSample ? sampleEn : "");
  const msgHi = context.messageHindi !== undefined && context.messageHindi !== null && String(context.messageHindi).trim() !== ""
    ? String(context.messageHindi)
    : (context.message ? String(context.message) : (context.isSample ? sampleHi : ""));

  const replacements = {
    "{guestName}": context.guestName || "Valued Guest",
    "{hotelName}": context.hotelName || "EaseInn Hotel",
    "{roomNumber}": hasRoom ? rawRoom : "",
    "{checkInDate}": context.checkInDate || "Today",
    "{checkOutDate}": context.checkOutDate || "Tomorrow",
    "{message}": msgEn,
    "{messageHindi}": msgHi,
  };

  for (const [placeholder, value] of Object.entries(replacements)) {
    result = result.split(placeholder).join(value);
  }
  return result;
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

function isConfirmedSendResult(sent) {
  if (!sent || typeof sent !== "object") return false;
  const key = sent.key;
  if (!key) return false;
  if (key.fromMe === false) return false;
  return Boolean(key.id);
}

// Unified Service APIs supporting both single-tenant & multi-tenant invocations

async function initializeWhatsAppClient(hotelId = "default", options = {}) {
  // Support calling initializeWhatsAppClient(options) directly for backward compatibility
  if (typeof hotelId === "object" && hotelId !== null) {
    options = hotelId;
    hotelId = options.hotelId || "default";
  }
  const session = getSession(hotelId);
  return session.initializeWhatsAppClient(options);
}

async function requestPairingCode(hotelId = "default", rawPhone) {
  if (typeof hotelId === "string" && !rawPhone && hotelId.length >= 10 && /^\+?\d+$/.test(hotelId)) {
    rawPhone = hotelId;
    hotelId = "default";
  }
  const norm = normalizePhoneNumber(rawPhone);
  if (!norm) {
    return { success: false, error: "Please enter a valid 10-digit Indian phone number.", code: "INVALID_PHONE" };
  }

  const session = getSession(hotelId);
  if (session.sock && session.clientStatus === "CONNECTED") {
    return {
      success: true,
      isConnected: true,
      connectedNumber: session.connectedNumber,
      message: "WhatsApp is already connected.",
    };
  }

  // If pairing code already available and still valid, return it
  if (session.pairingCode && session.clientStatus === "PAIRING_CODE_READY") {
    return {
      success: true,
      pairingCode: session.pairingCode,
      status: "PAIRING_CODE_READY",
    };
  }

  await session.initializeWhatsAppClient({ usePairingCode: true, phoneNumber: norm.cleanPhone });

  const start = Date.now();
  while (Date.now() - start < 12000) {
    if (session.pairingCode) {
      return {
        success: true,
        pairingCode: session.pairingCode,
        status: "PAIRING_CODE_READY",
      };
    }
    if (session.clientStatus === "ERROR") {
      return {
        success: false,
        error: session.initializationError || "Failed to generate pairing code",
        code: "PAIRING_CODE_FAILED",
      };
    }
    await new Promise((r) => setTimeout(r, 400));
  }

  if (session.pairingCode) {
    return {
      success: true,
      pairingCode: session.pairingCode,
      status: "PAIRING_CODE_READY",
    };
  }

  return {
    success: false,
    error: "Timed out generating pairing code. Please try again.",
    code: "TIMEOUT",
  };
}

async function disconnectWhatsAppClient(hotelId = "default", options = {}) {
  if (typeof hotelId === "object" && hotelId !== null) {
    options = hotelId;
    hotelId = options.hotelId || "default";
  }
  const session = getSession(hotelId);
  return session.disconnectWhatsAppClient(options);
}

function getStatus(hotelId = "default") {
  return getSession(hotelId).getStatus();
}

function getTemplates(hotelId = "default") {
  return getSession(hotelId).getTemplates();
}

function saveTemplates(hotelId = "default", templates) {
  if (typeof hotelId === "object" && !templates) {
    templates = hotelId;
    hotelId = "default";
  }
  return getSession(hotelId).saveTemplates(templates);
}

function getLogs(hotelId = "default", limit = 50) {
  if (typeof hotelId === "number") {
    limit = hotelId;
    hotelId = "default";
  }
  return getSession(hotelId).getLogs(limit);
}

async function sendWhatsAppNotification({
  hotelId = "default",
  templateId,
  recipientPhone,
  customMessage,
  context = {},
  bypassDuplicateCheck = false,
  stayId,
  document,
}) {
  const session = getSession(hotelId);
  const currentSend = session.sendQueue.then(() => sendWhatsAppNotificationNow(session, {
    templateId, recipientPhone, customMessage, context, bypassDuplicateCheck, stayId, document,
  }));
  session.sendQueue = currentSend.catch(() => {});
  return currentSend;
}

async function sendWhatsAppNotificationNow(session, {
  templateId,
  recipientPhone,
  customMessage,
  context = {},
  bypassDuplicateCheck = false,
  stayId,
  document,
}) {
  const norm = normalizePhoneNumber(recipientPhone);
  if (!norm) {
    const errorMsg = `Invalid phone number format: "${recipientPhone}". Needs at least 10 digits.`;
    session.appendLog({
      templateId: templateId || "custom",
      recipientPhone,
      status: "FAILED",
      error: errorMsg,
      delivered: false,
      context,
    });
    return { success: false, delivered: false, error: errorMsg, code: "INVALID_PHONE" };
  }
  const selfSend = session.connectedNumber === norm.cleanPhone;

  const templates = session.getTemplates();
  let messageBody = customMessage;

  if (templateId) {
    const templateConfig = templates[templateId];
    if (!templateConfig) {
      return { success: false, delivered: false, error: `Template "${templateId}" not found.`, code: "TEMPLATE_NOT_FOUND" };
    }
    if (!templateConfig.enabled) {
      return { success: false, delivered: false, error: `Template "${templateId}" is muted/disabled.`, code: "TEMPLATE_DISABLED" };
    }
    const effectiveContext = {
      ...context,
      message: (context && context.message) || customMessage || "",
      messageHindi: (context && context.messageHindi) || (context && context.message) || customMessage || "",
    };
    messageBody = interpolateTemplate(templateConfig.template, effectiveContext);
  }

  if (!messageBody || !messageBody.trim()) {
    if (document && document.buffer) {
      messageBody = document.caption || "Tax Invoice & Guest Folio";
    } else {
      return { success: false, delivered: false, error: "Cannot send empty WhatsApp message body.", code: "EMPTY_BODY" };
    }
  }

  if (Buffer.byteLength(messageBody, "utf8") > 65536) {
    return { success: false, accepted: false, error: "Message is too long. Keep it under 64 KB.", code: "MESSAGE_TOO_LARGE" };
  }

  const messageHash = stableMessageKey(messageBody);
  const dedupeKey = stayId
    ? `${stayId}_${templateId || "custom"}`
    : `content_${stableMessageKey(`${norm.cleanPhone}|${templateId || "custom"}|${messageHash}`)}`;
  if (!bypassDuplicateCheck && session.duplicateCache.has(dedupeKey)) {
    const previous = session.duplicateCache.get(dedupeKey);
    if (Date.now() - previous.timestamp < 300000) {
      console.warn(`[WhatsApp] [${session.hotelId}] Duplicate message suppressed for key: ${dedupeKey}`);
      return {
        success: false,
        delivered: false,
        suppressed: true,
        message: "Duplicate message skipped (already sent within 5 minutes).",
        code: "DUPLICATE_SUPPRESSED",
      };
    }
  }

  if (session.pendingSends.has(dedupeKey)) {
    return { success: false, accepted: false, delivered: false, suppressed: true, message: "This message is already being submitted. Check the WhatsApp chat before retrying.", code: "SEND_IN_PROGRESS" };
  }
  const sendAttempt = { outcomeUnknown: false };
  session.pendingSends.set(dedupeKey, sendAttempt);

  const ready = await session.waitUntilConnected(30000);
  if (!ready || !session.sock || session.clientStatus !== "CONNECTED") {
    const errorMsg = "WhatsApp is not connected. Open WhatsApp Automation and link your device.";
    session.appendLog({
      templateId: templateId || "custom",
      recipientPhone: norm.cleanPhone,
      status: "FAILED",
      error: errorMsg,
      preview: messageBody.slice(0, 100),
      delivered: false,
      context,
    });
    session.pendingSends.delete(dedupeKey);
    return { success: false, delivered: false, error: errorMsg, code: "NOT_CONNECTED" };
  }

  if (!bypassDuplicateCheck && session.duplicateCache.has(dedupeKey)) {
    const previous = session.duplicateCache.get(dedupeKey);
    if (Date.now() - previous.timestamp < 300000) {
      session.pendingSends.delete(dedupeKey);
      return { success: false, accepted: false, delivered: false, suppressed: true, messageId: previous.messageId, message: "Duplicate message skipped because WhatsApp already accepted it within the last 5 minutes.", code: "DUPLICATE_SUPPRESSED" };
    }
  }

  const resolved = await session.resolveRecipientJid(norm.cleanPhone);
  if (!resolved.jid) {
    const errorMsg = resolved.exists === false
      ? `+${norm.cleanPhone} is not registered on WhatsApp.`
      : "Could not verify this number with WhatsApp. Check the country code and try again.";
    session.appendLog({ templateId: templateId || "custom", recipientPhone: norm.cleanPhone, status: "FAILED", error: errorMsg, preview: messageBody.slice(0, 100), delivered: false, context });
    session.pendingSends.delete(dedupeKey);
    return { success: false, delivered: false, error: errorMsg, code: resolved.exists === false ? "NOT_ON_WHATSAPP" : "RECIPIENT_LOOKUP_FAILED" };
  }

  try {
    console.log(`[WhatsApp] [${session.hotelId}] Sending to ${resolved.jid}...`);
    const sendingSocket = session.sock;
    let sendPromise;

    if (document && document.buffer) {
      if (messageBody && messageBody.trim()) {
        try {
          const textMsg = await sendingSocket.sendMessage(resolved.jid, { text: messageBody });
          if (textMsg?.key?.id && textMsg?.message) {
            session.cacheMessage(textMsg.key.id, textMsg.message);
          }
        } catch (textErr) {
          console.warn(`[WhatsApp] [${session.hotelId}] Text notice dispatch note:`, textErr.message);
        }
      }

      const docPayload = {
        document: document.buffer,
        mimetype: document.mimetype || "application/pdf",
        fileName: document.fileName || "Tax_Invoice.pdf",
        caption: `📄 Tax Invoice & Guest Folio - ${document.fileName || "Invoice.pdf"}`,
      };
      sendPromise = sendingSocket.sendMessage(resolved.jid, docPayload);
    } else {
      sendPromise = sendingSocket.sendMessage(resolved.jid, { text: messageBody });
    }
    sendAttempt.promise = sendPromise;
    let acceptanceRecorded = false;

    const recordAccepted = (acceptedMessage) => {
      if (acceptanceRecorded || !isConfirmedSendResult(acceptedMessage)) return;
      if (acceptedMessage?.key?.id && acceptedMessage?.message) {
        session.cacheMessage(acceptedMessage.key.id, acceptedMessage.message);
      }
      acceptanceRecorded = true;
      const acceptedAt = Date.now();
      const acceptedMessageId = acceptedMessage.key.id;
      session.duplicateCache.set(dedupeKey, { timestamp: acceptedAt, messageId: acceptedMessageId });
      session.persistAcceptedMessage({ dedupeKey, timestamp: acceptedAt, messageId: acceptedMessageId });
      session.appendLog({
        templateId: templateId || "custom",
        recipientPhone: norm.cleanPhone,
        status: "ACCEPTED",
        messageId: acceptedMessageId,
        preview: messageBody.slice(0, 120),
        delivered: false,
        deliveryStatus: "PENDING",
        accepted: true,
        selfSend,
        context,
      });

      const earlyReceipt = session.earlyDeliveryReceipts.get(acceptedMessageId);
      if (earlyReceipt && Date.now() - earlyReceipt.timestamp <= 5 * 60 * 1000) {
        session.updateLogDelivery(acceptedMessageId, earlyReceipt.status);
        session.earlyDeliveryReceipts.delete(acceptedMessageId);
      }
    };

    sendPromise.then((lateResult) => {
      recordAccepted(lateResult);
      session.pendingSends.delete(dedupeKey);
    }, () => {
      session.pendingSends.delete(dedupeKey);
    });

    const sent = await sendWithTimeout(sendPromise, SEND_TIMEOUT_MS);
    if (!isConfirmedSendResult(sent)) {
      throw new Error("WhatsApp did not acknowledge the message. It was not delivered.");
    }

    const messageId = sent.key.id;
    recordAccepted(sent);
    console.log(`[WhatsApp] [${session.hotelId}] Accepted by WhatsApp for ${norm.cleanPhone}: ${messageId}`);
    return {
      success: true,
      accepted: true,
      delivered: false,
      deliveryStatus: "PENDING",
      message: selfSend
        ? "WhatsApp accepted this message to the connected account. Delivery has not been independently confirmed."
        : "WhatsApp accepted the message for sending.",
      messageId,
      recipient: norm.cleanPhone,
      selfSend,
    };
  } catch (sendErr) {
    const errMsg = sendErr.message || String(sendErr);
    if (sendErr.message?.includes("outcome is unknown")) sendAttempt.outcomeUnknown = true;
    if (sendAttempt.outcomeUnknown && session.duplicateCache.has(dedupeKey)) {
      const accepted = session.duplicateCache.get(dedupeKey);
      if (accepted.messageId) {
        return {
          success: true,
          accepted: true,
          delivered: false,
          deliveryStatus: "PENDING",
          message: "WhatsApp accepted the message before the response timed out.",
          messageId: accepted.messageId,
          recipient: norm.cleanPhone,
        };
      }
    }
    if (sendAttempt.outcomeUnknown) {
      const timestamp = Date.now();
      session.duplicateCache.set(dedupeKey, { timestamp, messageId: null });
      session.persistAcceptedMessage({ dedupeKey, timestamp, messageId: null });
    }
    console.error(`[WhatsApp] [${session.hotelId}] Send failed for ${norm.cleanPhone}:`, errMsg);
    session.appendLog({
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
    if (!sendAttempt.outcomeUnknown) session.pendingSends.delete(dedupeKey);
  }
}

/**
 * Auto-restore all previously saved sessions on startup.
 */
async function restoreAllSessions() {
  try {
    const authDir = AUTH_DIR;
    if (!fs.existsSync(authDir)) return;

    // Check if base auth dir has creds
    if (fs.existsSync(path.join(authDir, "creds.json"))) {
      console.log("[WhatsApp] Restoring default session on startup...");
      initializeWhatsAppClient("default").catch(() => {});
    }

    // Check hotel-specific session subfolders
    const entries = fs.readdirSync(authDir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory()) {
        const hotelCreds = path.join(authDir, entry.name, "creds.json");
        if (fs.existsSync(hotelCreds)) {
          console.log(`[WhatsApp] Restoring session for hotel: ${entry.name}`);
          initializeWhatsAppClient(entry.name).catch(() => {});
        }
      }
    }
  } catch (err) {
    console.warn("[WhatsApp] Session auto-restore error:", err.message);
  }
}

module.exports = {
  initializeWhatsAppClient,
  requestPairingCode,
  disconnectWhatsAppClient,
  sendWhatsAppNotification,
  getStatus,
  getTemplates,
  saveTemplates,
  getLogs,
  interpolateTemplate,
  normalizePhoneNumber,
  restoreAllSessions,
  SUPPORTED_PLACEHOLDERS,
  // Export for testing
  getSession,
  sessions,
};
