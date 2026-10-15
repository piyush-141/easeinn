// src/services/ollama-vision.service.js
const fs = require("fs");
const path = require("path");
const fetch = require("node-fetch");
require("dotenv").config();

const OLLAMA_BASE_URL = (
  process.env.OLLAMA_API_BASE_URL || "http://localhost:11434"
).replace(/\/+$/, "");

const OLLAMA_MODEL = process.env.OLLAMA_MODEL || "llava:latest";

/**
 * Strip markdown code fences from LLM response
 */
function stripCodeFences(text) {
  return text
    .replace(/```json/gi, "")
    .replace(/```/g, "")
    .trim();
}

/**
 * Parse the first JSON object found in text
 */
function parseFirstJsonObject(text) {
  const cleaned = stripCodeFences(text);

  try {
    return JSON.parse(cleaned);
  } catch (_err) {
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (!match) {
      throw new Error("No JSON object found in LLM response");
    }
    return JSON.parse(match[0]);
  }
}

/**
 * Convert string "null" values to actual null
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

/**
 * Extract identity fields from a document image using Ollama vision model.
 * Sends the image directly to LLaVA/Qwen for structured extraction.
 */
async function extractFieldsWithVision(imagePath, documentId) {
  console.log(`[Vision] Sending image to "${OLLAMA_MODEL}"...`);

  if (!fs.existsSync(imagePath)) {
    throw new Error("Image file not found: " + imagePath);
  }

  const imageBytes = fs.readFileSync(imagePath);
  const base64Image = imageBytes.toString("base64");

  const prompt = `You are a document data extraction system. Analyze this identity document image carefully.

Determine the document type and extract all visible fields.

Return ONLY a valid JSON object with these keys:
{
  "document_type": "aadhaar or pan or voter_id or passport or unknown",
  "name": "full name in English or null",
  "dob": "DD/MM/YYYY format or null",
  "gender": "MALE or FEMALE or null",
  "id_number": "the main ID number (Aadhaar: 1234 5678 9012, PAN: ABCDE1234F) or null",
  "address": "full address if visible or null",
  "pincode": "6-digit pincode or null",
  "father_name": "father's name if visible or null"
}

Rules:
- Use English text only, not Hindi/regional scripts
- DOB must be DD/MM/YYYY
- Aadhaar must be 12 digits in groups of 4 separated by spaces
- PAN must be 5 letters + 4 digits + 1 letter
- Return ONLY valid JSON, no explanation, no markdown fences`;

  const response = await fetch(`${OLLAMA_BASE_URL}/api/generate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: OLLAMA_MODEL,
      prompt: prompt,
      images: [base64Image],
      stream: false,
      options: { temperature: 0.1 },
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Ollama API error ${response.status}: ${errText}`);
  }

  const data = await response.json();
  const responseText = data.response.trim();

  console.log("[Vision] Raw response:", responseText.substring(0, 200) + "...");

  let fields;
  try {
    fields = normalizeNullStrings(parseFirstJsonObject(responseText));
  } catch (err) {
    throw new Error("Failed to parse vision model response: " + err.message);
  }

  // Save fields to file
  if (documentId) {
    fs.mkdirSync("processed", { recursive: true });
    const outPath = path.join("processed", `${documentId}_vision_fields.json`);
    fs.writeFileSync(outPath, JSON.stringify(fields, null, 2));
    console.log("[Vision] Fields saved →", outPath);
  }

  return fields;
}

/**
 * Check if Ollama service is available
 */
async function isOllamaAvailable() {
  try {
    const response = await fetch(`${OLLAMA_BASE_URL}/api/tags`, {
      method: "GET",
      signal: AbortSignal.timeout(3000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

module.exports = { extractFieldsWithVision, isOllamaAvailable };