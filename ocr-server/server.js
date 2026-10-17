// server.js
require("dotenv").config();

const express = require("express");
const cors = require("cors");
const path = require("path");
const fs = require("fs");
const apiRoutes = require("./src/routes/api.routes");
const whatsappRoutes = require("./src/routes/whatsapp.routes");
const whatsappService = require("./src/services/whatsapp.service");
const { errorHandler } = require("./src/middleware/error.middleware");

const app = express();
const PORT = process.env.PORT || 3001;

// Create required directories on startup
["uploads", "processed", "data"].forEach((dir) => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    console.log(`Created directory: ${dir}/`);
  }
});

// Middleware
app.use(cors());
app.use(express.json({ limit: "20mb" }));
app.use(express.urlencoded({ extended: true, limit: "20mb" }));

// Serve processed files statically (for debugging/download)
app.use("/processed", express.static(path.join(__dirname, "processed")));

// Health check
app.get("/", (req, res) => {
  const wa = whatsappService.getStatus();
  res.json({
    service: "EaseInn Backend & Document Verification API",
    version: "2.2.0",
    status: "running",
    whatsapp: {
      engine: wa.engine,
      status: wa.status,
      isConnected: wa.isConnected,
      hasPersistedSession: wa.hasPersistedSession,
    },
    endpoints: {
      upload: "POST /api/upload",
      process: "POST /api/process",
      extract: "POST /api/extract",
      verify: "POST /api/verify",
      full_pipeline: "POST /api/pipeline",
      scan_document: "POST /api/scan-document",
      whatsapp_status: "GET /api/whatsapp/status",
      whatsapp_connect: "POST /api/whatsapp/connect",
      whatsapp_templates: "GET /api/whatsapp/templates",
      whatsapp_send: "POST /api/whatsapp/send",
    },
  });
});

// API Routes
app.use("/api", apiRoutes);
app.use("/api/whatsapp", whatsappRoutes);

// Global error handler
app.use(errorHandler);

// Log asynchronous server failures without falsely treating them as successful sends.
process.on("unhandledRejection", (reason) => {
  console.error("[Server Unhandled Rejection]", reason);
});

process.on("uncaughtException", (err) => {
  console.error("[Server Uncaught Exception]", err);
  process.exit(1);
});

const httpServer = app.listen(PORT, () => {
  const geminiActive = Boolean(process.env.GEMINI_API_KEY && process.env.GEMINI_API_KEY.trim().length > 5);
  const openRouterActive = Boolean(process.env.OPENROUTER_API_KEY && process.env.OPENROUTER_API_KEY.trim().length > 5);

  console.log(`\n========================================`);
  console.log(`  EaseInn Backend & Document API v2.2.0`);
  console.log(`  Running on: http://localhost:${PORT}`);
  console.log(`  Gemini Vision:     ${geminiActive ? "ENABLED (High Speed ~1s)" : "Disabled (Add GEMINI_API_KEY to .env)"}`);
  console.log(`  OpenRouter Vision: ${openRouterActive ? "ENABLED" : "Disabled"}`);
  console.log(`  Ollama (Local):    ${process.env.OLLAMA_API_BASE_URL || "http://localhost:11434"}`);
  console.log(`  WhatsApp engine:   Baileys (session auto-restore)`);
  console.log(`========================================\n`);

  // Restore WhatsApp session on boot so a Render/process restart stays linked
  whatsappService.initializeWhatsAppClient().catch((err) => {
    console.warn("[WhatsApp] Auto-restore on boot failed:", err.message);
  });
});

async function shutdown(signal) {
  console.log(`[Server] ${signal} received. Closing WhatsApp and HTTP server.`);
  httpServer.close();
  try {
    await whatsappService.disconnectWhatsAppClient({ preserveSession: true });
  } finally {
    process.exit(0);
  }
}

process.once("SIGTERM", () => shutdown("SIGTERM"));
process.once("SIGINT", () => shutdown("SIGINT"));

module.exports = app;
