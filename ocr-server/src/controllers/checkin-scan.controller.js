// src/controllers/checkin-scan.controller.js
const fs = require("fs");
const path = require("path");
const { compressImage } = require("../services/compression.service");
const { preprocessImage } = require("../services/preprocessing.service");
const { extractText } = require("../services/ocr.service");
const { extractFieldsFromText, detectDocumentType } = require("../services/extraction.service");
const { extractFieldsWithVision, isOllamaAvailable } = require("../services/ollama-vision.service");
const { extractFieldsWithCloudVision, isCloudVisionAvailable } = require("../services/cloud-vision.service");
const { generateDocumentId, formatBytes, formatAadhaarNumber } = require("../utils/helpers");

/**
 * Smart merge function combining vision output and OCR output
 */
function smartMerge(vision, ocr) {
  if (!vision) return ocr;
  if (!ocr) return vision;

  const keys = [
    "document_type", "name", "dob", "gender",
    "id_number", "address", "pincode", "father_name",
  ];
  const merged = {};
  for (const key of keys) {
    const v = vision[key];
    const o = ocr[key];
    const vExists = v !== null && v !== undefined && v !== "";
    const oExists = o !== null && o !== undefined && o !== "";

    if (vExists && oExists) {
      if (key === "id_number") {
        merged[key] = formatAadhaarNumber(v || o);
      } else if (key === "address") {
        merged[key] = v.length >= o.length ? v : o;
      } else {
        merged[key] = v; // prefer vision for text quality
      }
    } else if (vExists) {
      merged[key] = v;
    } else if (oExists) {
      merged[key] = o;
    } else {
      merged[key] = null;
    }
  }
  return merged;
}

/**
 * Merge front and back document sides (especially for Aadhaar)
 * Front side is authoritative for: name, dob, gender, id_number
 * Back side is authoritative for: address, pincode, father_name (C/O)
 */
function mergeFrontAndBack(frontFields, backFields, expectedDocType) {
  const merged = {
    document_type: expectedDocType || frontFields.document_type || backFields.document_type || "aadhaar",
    // Name: prefer front side
    name: frontFields.name || backFields.name || null,
    // DOB: prefer front side
    dob: frontFields.dob || backFields.dob || null,
    // Gender: prefer front side
    gender: frontFields.gender || backFields.gender || null,
    // ID Number: prefer front side (Aadhaar number is on front)
    id_number: frontFields.id_number || backFields.id_number || null,
    // Address: prefer back side (Address is on back of Aadhaar)
    address: backFields.address || frontFields.address || null,
    // Pincode: prefer back side
    pincode: backFields.pincode || frontFields.pincode || null,
    // Father/Husband (Care of): back side usually has C/O: Father/Husband name
    father_name: backFields.father_name || frontFields.father_name || null,
  };

  return merged;
}

/**
 * Run complete OCR pipeline on a single image file
 */
async function processSingleImage(filePath, originalName, docId) {
  console.log(`[Scan] Processing image: ${originalName} (ID: ${docId})`);
  const t0 = Date.now();

  // Step 1: Compress
  const compressedPath = await compressImage(filePath);
  const compressMs = Date.now() - t0;

  let fields = null;
  let ocrResult = null;
  const tVision = Date.now();

  // Step 2: Cloud Vision (Gemini → OpenRouter)
  if (isCloudVisionAvailable()) {
    try {
      console.log(`[Scan] Cloud Vision — extracting fields from ${docId}...`);
      const cloudVisionResult = await extractFieldsWithCloudVision(compressedPath, `${docId}_cloud_vision`);
      if (cloudVisionResult && (cloudVisionResult.name || cloudVisionResult.id_number || cloudVisionResult.dob)) {
        fields = cloudVisionResult;
        console.log(`[Scan] ✓ Cloud Vision extracted fields for ${docId}`);
      }
    } catch (err) {
      console.warn(`[Scan] Cloud Vision error: ${err.message}. Falling back to local pipeline.`);
    }
  }

  // Step 3: Local OCR fallback if cloud vision yielded nothing
  if (!fields) {
    console.log(`[Scan] Running local OCR on ${docId}...`);
    const variants = await preprocessImage(compressedPath);
    variants.original = filePath;
    variants.compressed = compressedPath;

    ocrResult = await extractText(variants, docId);
    fields = extractFieldsFromText(ocrResult, `${docId}_ocr`);

    try {
      const ollamaReady = await isOllamaAvailable();
      if (ollamaReady) {
        const visionResult = await extractFieldsWithVision(compressedPath, `${docId}_vision`);
        if (visionResult) fields = smartMerge(visionResult, fields);
      }
    } catch (err) {
      console.warn(`[Scan] Local vision skipped: ${err.message}`);
    }
  } else {
    ocrResult = {
      confidence: 98,
      qualityScore: 95,
      bestVariant: "cloud_vision",
      rawText: Object.entries(fields).filter(([_, v]) => v).map(([k, v]) => `${k}: ${v}`).join("\n"),
    };
  }

  const visionMs = Date.now() - tVision;

  return {
    docId,
    filePath,
    compressedPath,
    ocrResult: {
      confidence: ocrResult.confidence,
      qualityScore: ocrResult.qualityScore,
      bestVariant: ocrResult.bestVariant,
      rawText: ocrResult.text || ocrResult.rawText,
    },
    fields,
    timing: { compress_ms: compressMs, vision_ms: visionMs, total_ms: Date.now() - t0 },
  };
}

/**
 * POST /api/scan-document
 * Unified check-in scanning endpoint.
 * Supports:
 * - Single document upload (`document` or `document_front`)
 * - Dual document upload (`document_front` + `document_back` or `front` + `back`)
 * - Document type hint in `req.body.document_type` ('aadhaar', 'pan', 'passport', 'voter_id', 'driving_license', 'auto')
 */
async function scanDocumentHandler(req, res, next) {
  try {
    const docTypeHint = req.body.document_type || "auto";
    const baseId = generateDocumentId();

    // Resolve uploaded files
    let frontFile = null;
    let backFile = null;

    if (req.files) {
      frontFile = req.files.document_front?.[0] || req.files.front?.[0] || req.files.document?.[0];
      backFile = req.files.document_back?.[0] || req.files.back?.[0];
    } else if (req.file) {
      frontFile = req.file;
    }

    if (!frontFile && !backFile) {
      return res.status(400).json({
        success: false,
        error: "No document file uploaded. Provide 'document_front' (and optional 'document_back') or 'document'.",
      });
    }

    console.log(`\n======================================================`);
    console.log(`[CheckIn Scan] Starting document extraction: ID ${baseId}`);
    console.log(`[CheckIn Scan] Document type hint: ${docTypeHint}`);
    console.log(`[CheckIn Scan] Front side: ${frontFile ? frontFile.originalname : 'none'}`);
    console.log(`[CheckIn Scan] Back side: ${backFile ? backFile.originalname : 'none'}`);
    console.log(`======================================================\n`);

    let frontResult = null;
    let backResult  = null;
    const tTotal = Date.now();

    // Process front and back CONCURRENTLY — single biggest latency gain
    [frontResult, backResult] = await Promise.all([
      frontFile
        ? processSingleImage(frontFile.path, frontFile.originalname, `${baseId}_front`)
        : Promise.resolve(null),
      backFile
        ? processSingleImage(backFile.path, backFile.originalname, `${baseId}_back`)
        : Promise.resolve(null),
    ]);

    let finalExtractedData = {};
    let finalDocType = docTypeHint !== "auto" ? docTypeHint : null;

    if (frontResult && backResult) {
      // Both front and back provided (e.g. Aadhaar card)
      finalDocType = finalDocType || frontResult.fields.document_type || backResult.fields.document_type || "aadhaar";
      finalExtractedData = mergeFrontAndBack(frontResult.fields, backResult.fields, finalDocType);
    } else if (frontResult) {
      finalDocType = finalDocType || frontResult.fields.document_type || "unknown";
      finalExtractedData = frontResult.fields;
      if (finalDocType) finalExtractedData.document_type = finalDocType;
    } else if (backResult) {
      finalDocType = finalDocType || backResult.fields.document_type || "unknown";
      finalExtractedData = backResult.fields;
      if (finalDocType) finalExtractedData.document_type = finalDocType;
    }

    // Prepare clean response payload formatted specifically for guest check-in form auto-fill
    const responsePayload = {
      success: true,
      document_id: baseId,
      document_type: finalDocType,
      has_both_sides: Boolean(frontFile && backFile),
      // Clean guest profile fields ready to auto-populate check-in form
      guest_data: {
        full_name: finalExtractedData.name || "",
        id_type: finalDocType === "unknown" ? "aadhaar" : finalDocType,
        id_number: finalDocType === "aadhaar" || (!finalDocType && finalExtractedData.id_number)
          ? formatAadhaarNumber(finalExtractedData.id_number)
          : (finalExtractedData.id_number || ""),
        date_of_birth: finalExtractedData.dob || "",
        gender: finalExtractedData.gender ? finalExtractedData.gender.toLowerCase() : "",
        address: finalExtractedData.address || "",
        pincode: finalExtractedData.pincode || "",
        father_name: finalExtractedData.father_name || "",
      },
      // Detailed side breakdown for UI inspection / audit
      details: {
        front: frontResult ? {
          filename: frontFile.originalname,
          confidence: `${frontResult.ocrResult.confidence.toFixed(1)}%`,
          extracted: frontResult.fields,
        } : null,
        back: backResult ? {
          filename: backFile.originalname,
          confidence: `${backResult.ocrResult.confidence.toFixed(1)}%`,
          extracted: backResult.fields,
        } : null,
      },
    };

    // Attach timing breakdown (always included — useful for benchmarking)
    responsePayload._timing = {
      server_total_ms: Date.now() - tTotal,
      front_ms: frontResult?.timing?.total_ms ?? null,
      front_compress_ms: frontResult?.timing?.compress_ms ?? null,
      front_vision_ms:   frontResult?.timing?.vision_ms   ?? null,
      back_ms:  backResult?.timing?.total_ms  ?? null,
      back_compress_ms:  backResult?.timing?.compress_ms  ?? null,
      back_vision_ms:    backResult?.timing?.vision_ms    ?? null,
    };

    console.log(`[CheckIn Scan] Done ${baseId} in ${responsePayload._timing.server_total_ms}ms`);
    console.log(`[CheckIn Scan] Auto-fill fields:`, responsePayload.guest_data);

    return res.status(200).json(responsePayload);
  } catch (err) {
    console.error("[CheckIn Scan] Error occurred during scan:", err);
    next(err);
  }
}

module.exports = {
  scanDocumentHandler,
};
