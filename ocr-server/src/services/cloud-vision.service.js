// src/services/cloud-vision.service.js
const fs     = require("fs");
const path   = require("path");
const https  = require("https");
const fetch  = require("node-fetch"); // v2, already in package.json
require("dotenv").config();

// ── Keep-alive HTTPS agents ─────────────────────────────────────────────────
// node-fetch v2 accepts an https.Agent, which enables TCP connection reuse
// across consecutive calls to the same upstream. Eliminates TLS handshake
// overhead on repeated requests (~50-150ms saved per call after the first).
const geminiAgent = new https.Agent({
  keepAlive:    true,
  maxSockets:   4,
  maxFreeSockets: 2,
});

const openRouterAgent = new https.Agent({
  keepAlive:    true,
  maxSockets:   4,
  maxFreeSockets: 2,
});

// Per-attempt timeout in ms. With 2 Gemini models + 3 OpenRouter models the
// worst-case wall time before local OCR is (6s x 5) + (400ms x 4 delays)
// = ~32s — comfortably inside the client's 120s hard timeout.
const ATTEMPT_TIMEOUT_MS = 6_000;
const RETRY_DELAY_MS     = 400;

// ── Helpers ─────────────────────────────────────────────────────────────────

function getMimeType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === ".png")  return "image/png";
  if (ext === ".webp") return "image/webp";
  return "image/jpeg";
}

function stripCodeFences(text) {
  return text.replace(/```json/gi, "").replace(/```/g, "").trim();
}

function parseFirstJsonObject(text) {
  const cleaned = stripCodeFences(text);
  try {
    return JSON.parse(cleaned);
  } catch (_) {
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (!match) throw new Error("No JSON object found in vision response");
    return JSON.parse(match[0]);
  }
}

function normalizeNullStrings(value) {
  if (Array.isArray(value)) return value.map(normalizeNullStrings);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, normalizeNullStrings(v)])
    );
  }
  if (typeof value === "string" && value.trim().toLowerCase() === "null") return null;
  return value;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// ── Prompt ───────────────────────────────────────────────────────────────────
// Trimmed to 8 output fields — removes district, state, aadhaar_number (dup),
// pan_number (dup).  Saves ~30-50 output tokens and reduces model reasoning
// time without losing any field the mobile client actually reads.

const DOCUMENT_EXTRACTION_PROMPT = `You are an expert OCR system for Indian government identity documents.

Analyze the image and extract all visible fields. Translate Hindi/regional text to English.
Supported: Aadhaar (front/back), PAN, Passport, Voter ID (EPIC), Driving Licence.

ID number formats:
- Aadhaar: 'XXXX XXXX XXXX' (12 digits, groups of 4)
- PAN: 'ABCDE1234F' (10 chars)
- Passport: 1 letter + 7 digits
- Voter ID (EPIC): 3 letters + 7 digits
- Driving Licence: state code + numbers

Return ONLY valid JSON, no explanation, no markdown:
{
  "document_type": "aadhaar|pan|passport|voter_id|driving_license|unknown",
  "name": "Full name in English or null",
  "dob": "DD/MM/YYYY or null",
  "gender": "MALE or FEMALE or null",
  "id_number": "Primary ID number formatted or null",
  "address": "Full address in English or null",
  "pincode": "6-digit pincode or null",
  "father_name": "Father or husband name or null"
}`;

// ── Gemini Direct ────────────────────────────────────────────────────────────

async function extractWithGemini(base64Image, mimeType) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return null;

  const models = [
    { name: "gemini-2.5-flash", thinkingBudget: 0 },
    { name: "gemini-3.5-flash-lite", thinkingBudget: null },
  ];

  let lastError = null;

  for (const entry of models) {
    const model = entry.name;
    try {
      console.log(`[CloudVision] Gemini → "${model}"${entry.thinkingBudget !== null ? ` (thinkingBudget: ${entry.thinkingBudget})` : ""}...`);
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

      const generationConfig = {
        temperature:      0.1,
        responseMimeType: "application/json",
        maxOutputTokens:  400,
      };

      if (entry.thinkingBudget !== null) {
        generationConfig.thinkingConfig = {
          thinkingBudget: entry.thinkingBudget,
        };
      }

      const response = await fetch(url, {
        method:  "POST",
        agent:   geminiAgent,
        timeout: ATTEMPT_TIMEOUT_MS,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{
            role:  "user",
            parts: [
              { inline_data: { mime_type: mimeType, data: base64Image } },
              { text: DOCUMENT_EXTRACTION_PROMPT },
            ],
          }],
          generationConfig,
        }),
      });

      // Rate-limit or overload — pause briefly then try next model
      if (response.status === 429 || response.status === 503) {
        console.warn(`[CloudVision] Gemini "${model}" ${response.status} — trying next model after ${RETRY_DELAY_MS}ms`);
        lastError = new Error(`Gemini ${response.status}`);
        await sleep(RETRY_DELAY_MS);
        continue;
      }

      if (!response.ok) {
        const errText = await response.text();
        console.warn(`[CloudVision] Gemini "${model}" HTTP ${response.status} — trying next model`);
        lastError = new Error(`Gemini ${response.status}: ${errText.slice(0, 120)}`);
        continue;
      }

      const data = await response.json();
      const candidateText = data.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!candidateText) {
        console.warn(`[CloudVision] Gemini "${model}" empty response — trying next model`);
        continue;
      }

      const parsed = normalizeNullStrings(parseFirstJsonObject(candidateText));
      console.log(`[CloudVision] ✓ Gemini (${model})`);
      return parsed;
    } catch (err) {
      // AbortError = timeout; log and try next
      lastError = err;
      console.warn(`[CloudVision] Gemini "${model}" failed: ${err.message} — trying next model`);
    }
  }

  throw lastError || new Error("All Gemini models failed");
}

// ── OpenRouter ───────────────────────────────────────────────────────────────

async function extractWithOpenRouter(base64Image, mimeType) {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) return null;

  const candidateModels = [
    process.env.OPENROUTER_MODEL || "google/gemini-2.5-flash",
    "google/gemini-2.5-flash-lite",
    "qwen/qwen3-vl-8b-instruct",
  ];

  let lastError = null;

  for (const model of candidateModels) {
    try {
      console.log(`[CloudVision] OpenRouter → "${model}"...`);

      const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method:  "POST",
        agent:   openRouterAgent,
        timeout: ATTEMPT_TIMEOUT_MS,
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type":  "application/json",
          "HTTP-Referer":  process.env.OPENROUTER_SITE_URL || "http://localhost:3001",
          "X-Title":       "EaseInn DigiPramaan OCR",
        },
        body: JSON.stringify({
          model,
          messages: [{
            role:    "user",
            content: [
              {
                type:      "image_url",
                image_url: { url: `data:${mimeType};base64,${base64Image}` },
              },
              { type: "text", text: DOCUMENT_EXTRACTION_PROMPT },
            ],
          }],
          max_tokens:  400,
          temperature: 0.1,
        }),
      });

      if (response.status === 429 || response.status === 503) {
        console.warn(`[CloudVision] OpenRouter "${model}" ${response.status} — trying next model after ${RETRY_DELAY_MS}ms`);
        lastError = new Error(`OpenRouter ${response.status}`);
        await sleep(RETRY_DELAY_MS);
        continue;
      }

      if (!response.ok) {
        const errText = await response.text();
        console.warn(`[CloudVision] OpenRouter "${model}" HTTP ${response.status} — trying next model`);
        lastError = new Error(`OpenRouter ${response.status}: ${errText.slice(0, 120)}`);
        continue;
      }

      const data = await response.json();
      const rawText = data.choices?.[0]?.message?.content;
      if (!rawText) {
        console.warn(`[CloudVision] OpenRouter "${model}" empty response — trying next model`);
        continue;
      }

      const parsed = normalizeNullStrings(parseFirstJsonObject(rawText));
      console.log(`[CloudVision] ✓ OpenRouter (${model})`);
      return parsed;
    } catch (err) {
      lastError = err;
      console.warn(`[CloudVision] OpenRouter "${model}" failed: ${err.message} — trying next model`);
    }
  }

  throw lastError || new Error("All OpenRouter models failed");
}

// ── Availability check ───────────────────────────────────────────────────────

function isCloudVisionAvailable() {
  const hasGemini     = Boolean(process.env.GEMINI_API_KEY     && process.env.GEMINI_API_KEY.trim().length     > 5);
  const hasOpenRouter = Boolean(process.env.OPENROUTER_API_KEY && process.env.OPENROUTER_API_KEY.trim().length > 5);
  return hasGemini || hasOpenRouter;
}

// ── Main entry ───────────────────────────────────────────────────────────────

async function extractFieldsWithCloudVision(imagePath, documentId) {
  if (!fs.existsSync(imagePath)) throw new Error("Image not found: " + imagePath);

  const imageBytes  = fs.readFileSync(imagePath);
  const base64Image = imageBytes.toString("base64");
  const mimeType    = getMimeType(imagePath);

  let fields = null;

  // 1. Gemini direct (primary)
  if (process.env.GEMINI_API_KEY && process.env.GEMINI_API_KEY.trim().length > 5) {
    try {
      fields = await extractWithGemini(base64Image, mimeType);
    } catch (err) {
      console.warn(`[CloudVision] Gemini direct failed: ${err.message}. Trying OpenRouter...`);
    }
  }

  // 2. OpenRouter (fallback)
  if (!fields && process.env.OPENROUTER_API_KEY && process.env.OPENROUTER_API_KEY.trim().length > 5) {
    try {
      fields = await extractWithOpenRouter(base64Image, mimeType);
    } catch (err) {
      console.warn(`[CloudVision] OpenRouter failed: ${err.message}`);
    }
  }

  // Persist for audit — fire-and-forget so it never blocks the response
  if (fields && documentId) {
    fs.mkdirSync("processed", { recursive: true });
    const outPath = path.join("processed", `${documentId}_cloud_vision.json`);
    fs.promises.writeFile(outPath, JSON.stringify(fields, null, 2)).catch(() => {});
  }

  return fields;
}

module.exports = { isCloudVisionAvailable, extractFieldsWithCloudVision };
