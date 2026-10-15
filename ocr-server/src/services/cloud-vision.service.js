// src/services/cloud-vision.service.js
const fs = require("fs");
const path = require("path");
require("dotenv").config();

/**
 * Determine mime type from file path
 */
function getMimeType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === ".png") return "image/png";
  if (ext === ".webp") return "image/webp";
  return "image/jpeg";
}

/**
 * Strip markdown code fences
 */
function stripCodeFences(text) {
  return text
    .replace(/```json/gi, "")
    .replace(/```/g, "")
    .trim();
}

/**
 * Parse first JSON object from response text
 */
function parseFirstJsonObject(text) {
  const cleaned = stripCodeFences(text);
  try {
    return JSON.parse(cleaned);
  } catch (_err) {
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (!match) {
      throw new Error("No JSON object found in vision response");
    }
    return JSON.parse(match[0]);
  }
}

/**
 * Normalize null strings
 */
function normalizeNullStrings(value) {
  if (Array.isArray(value)) {
    return value.map(normalizeNullStrings);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, normalizeNullStrings(v)])
    );
  }
  if (typeof value === "string" && value.trim().toLowerCase() === "null") {
    return null;
  }
  return value;
}

const DOCUMENT_EXTRACTION_PROMPT = `You are an expert OCR and identity document verification system specialized in Indian government identity documents.

Analyze this document image carefully and extract all visible fields.
Documents supported: Aadhaar card (front and back), PAN card, Passport, Voter ID (EPIC), Driving Licence.

Tasks:
1. Identify the exact document type ('aadhaar', 'pan', 'passport', 'voter_id', 'driving_license', or 'unknown').
2. Fix any image artifacts, blur, reflection, tilt, or low lighting.
3. Distinguish between Hindi and English text; extract names and addresses in English.
4. Extract the primary identification number accurately:
   - Aadhaar: 12 digits formatted as 'XXXX XXXX XXXX'
   - PAN: 10 alphanumeric characters formatted as 'ABCDE1234F'
   - Passport: 1 letter followed by 7 digits
   - Voter ID / EPIC: 3 uppercase letters followed by 7 digits (e.g., 'ABC1234567')
   - Driving Licence: State code + numbers

Return ONLY a valid JSON object with this exact structure (no explanation, no markdown fences):
{
  "document_type": "aadhaar",
  "name": "Full Name in English or null",
  "dob": "DD/MM/YYYY or null",
  "gender": "MALE or FEMALE or null",
  "id_number": "Main document ID number or null",
  "aadhaar_number": "1234 5678 9012 or null",
  "pan_number": "ABCDE1234F or null",
  "address": "Full address in English or null",
  "pincode": "6 digit pincode or null",
  "district": "District name or null",
  "state": "State name or null",
  "father_name": "Father or husband name if present or null"
}`;

/**
 * Call Google Gemini Vision API using native fetch
 */
async function extractWithGemini(base64Image, mimeType) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return null;

  // Prioritize Gemini 2.5 Flash, with instant fallback to 2.5 Flash-Lite (low load, resists 503s)
  const models = [
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-3-flash-preview",
  ];

  let lastError = null;

  for (const model of models) {
    try {
      console.log(`[CloudVision] Calling Gemini model "${model}"...`);
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              role: "user",
              parts: [
                {
                  inline_data: {
                    mime_type: mimeType,
                    data: base64Image,
                  },
                },
                {
                  text: DOCUMENT_EXTRACTION_PROMPT,
                },
              ],
            },
          ],
          generationConfig: {
            temperature: 0.1,
            responseMimeType: "application/json",
          },
        }),
      });

      if (!response.ok) {
        const errText = await response.text();
        console.warn(`[CloudVision] Gemini model "${model}" returned HTTP ${response.status}. Trying next fallback model...`);
        lastError = new Error(`Gemini API error ${response.status}: ${errText}`);
        continue;
      }

      const data = await response.json();
      const candidateText = data.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!candidateText) {
        console.warn(`[CloudVision] Empty response from Gemini Vision (${model}). Trying next model...`);
        continue;
      }

      const parsed = normalizeNullStrings(parseFirstJsonObject(candidateText));
      console.log(`[CloudVision] ✓ Successfully extracted via Gemini (${model})!`);
      return parsed;
    } catch (err) {
      lastError = err;
      console.warn(`[CloudVision] Gemini model "${model}" failed: ${err.message}. Trying next fallback...`);
    }
  }

  throw lastError || new Error("All Gemini models failed");
}

/**
 * Call OpenRouter Vision API using standard OpenAI format with fallback models
 */
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
      console.log(`[CloudVision] Calling OpenRouter with model: "${model}"...`);
      const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": process.env.OPENROUTER_SITE_URL || "http://localhost:3001",
          "X-Title": "EaseInn DigiPramaan OCR",
        },
        body: JSON.stringify({
          model: model,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "image_url",
                  image_url: {
                    url: `data:${mimeType};base64,${base64Image}`,
                  },
                },
                {
                  text: DOCUMENT_EXTRACTION_PROMPT,
                },
              ],
            },
          ],
          max_tokens: 1000,
          temperature: 0.1,
        }),
      });

      if (!response.ok) {
        const errText = await response.text();
        console.warn(`[CloudVision] OpenRouter model "${model}" returned HTTP ${response.status}. Trying next OpenRouter fallback...`);
        lastError = new Error(`OpenRouter API error ${response.status}: ${errText}`);
        continue;
      }

      const data = await response.json();
      const rawText = data.choices?.[0]?.message?.content;
      if (!rawText) {
        console.warn(`[CloudVision] Empty response from OpenRouter (${model}). Trying next model...`);
        continue;
      }

      const parsed = normalizeNullStrings(parseFirstJsonObject(rawText));
      console.log(`[CloudVision] ✓ Successfully extracted via OpenRouter (${model})!`);
      return parsed;
    } catch (err) {
      lastError = err;
      console.warn(`[CloudVision] OpenRouter model "${model}" failed: ${err.message}. Trying next fallback...`);
    }
  }

  throw lastError || new Error("All OpenRouter models failed");
}

/**
 * Check if cloud vision is available (Gemini or OpenRouter key present)
 */
function isCloudVisionAvailable() {
  const hasGemini = Boolean(process.env.GEMINI_API_KEY && process.env.GEMINI_API_KEY.trim().length > 5);
  const hasOpenRouter = Boolean(process.env.OPENROUTER_API_KEY && process.env.OPENROUTER_API_KEY.trim().length > 5);
  return hasGemini || hasOpenRouter;
}

/**
 * Extract identity document fields using Cloud Vision (Gemini prioritized, OpenRouter fallback)
 */
async function extractFieldsWithCloudVision(imagePath, documentId) {
  if (!fs.existsSync(imagePath)) {
    throw new Error("Image file not found: " + imagePath);
  }

  const imageBytes = fs.readFileSync(imagePath);
  const base64Image = imageBytes.toString("base64");
  const mimeType = getMimeType(imagePath);

  let fields = null;

  // 1. Try Gemini if configured
  if (process.env.GEMINI_API_KEY && process.env.GEMINI_API_KEY.trim().length > 5) {
    try {
      fields = await extractWithGemini(base64Image, mimeType);
    } catch (err) {
      console.warn(`[CloudVision] Gemini direct failed: ${err.message}. Trying OpenRouter if available...`);
    }
  }

  // 2. Try OpenRouter if Gemini didn't run or failed
  if (!fields && process.env.OPENROUTER_API_KEY && process.env.OPENROUTER_API_KEY.trim().length > 5) {
    try {
      fields = await extractWithOpenRouter(base64Image, mimeType);
    } catch (err) {
      console.warn(`[CloudVision] OpenRouter failed: ${err.message}`);
    }
  }

  if (fields && documentId) {
    fs.mkdirSync("processed", { recursive: true });
    const outPath = path.join("processed", `${documentId}_cloud_vision.json`);
    fs.writeFileSync(outPath, JSON.stringify(fields, null, 2));
    console.log("[CloudVision] Fields saved →", outPath);
  }

  return fields;
}

module.exports = {
  isCloudVisionAvailable,
  extractFieldsWithCloudVision,
};
