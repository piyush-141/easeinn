// // src/controllers/process.controller.js
// const fs = require("fs");
// const path = require("path");
// const { preprocessImage } = require("../services/preprocessing.service");
// const { extractText } = require("../services/ocr.service");
// const { generateDocumentId, formatBytes } = require("../utils/helpers");

// /**
//  * POST /api/process
//  *
//  * Enhances the uploaded image and extracts raw text using OCR.
//  *
//  * Postman setup:
//  *   - Body → form-data
//  *   - Key: "document" (type: File) → select your image
//  *   - Key: "document_id" (type: Text) → optional, for tracking
//  */
// async function processDocument(req, res, next) {
//   try {
//     if (!req.file) {
//       return res.status(400).json({
//         success: false,
//         error: "No file uploaded. Send a file with field name 'document'.",
//       });
//     }

//     const documentId = req.body.document_id || generateDocumentId();
//     const uploadedPath = req.file.path;

//     console.log(`\n[Process] Processing: ${req.file.originalname}`);

//     // Step 1: Enhance image
//     console.log("[Process] Step 1: Image enhancement...");
//     const enhancedPath = await preprocessImage(uploadedPath);

//     // Step 2: OCR
//     console.log("[Process] Step 2: OCR extraction...");
//     const { text: rawText, confidence } = await extractText(
//       enhancedPath,
//       documentId
//     );

//     return res.status(200).json({
//       success: true,
//       document_id: documentId,
//       message: "Document processed successfully",
//       processing: {
//         enhanced_image: enhancedPath,
//         original_file: req.file.originalname,
//       },
//       ocr: {
//         raw_text: rawText,
//         confidence: `${confidence}%`,
//         character_count: rawText.length,
//         line_count: rawText.split("\n").filter((l) => l.trim()).length,
//       },
//     });
//   } catch (err) {
//     next(err);
//   }
// }

// module.exports = { processDocument };

//======================

// src/controllers/process.controller.js
const fs = require("fs");
const path = require("path");
const { preprocessImage } = require("../services/preprocessing.service");
const { extractText } = require("../services/ocr.service");
const { generateDocumentId } = require("../utils/helpers");

/**
 * POST /api/process
 *
 * Step 2 of the pipeline.
 * Takes the document_id from /upload, preprocesses the image
 * and runs raw OCR. Saves results for use by /extract.
 *
 * Postman:
 *   Body → raw JSON
 *   { "document_id": "abc123" }
 */
async function processDocument(req, res, next) {
  try {
    const documentId = req.body.document_id;

    if (!documentId) {
      return res.status(400).json({
        success: false,
        error: "Missing 'document_id'. Run /api/upload first and pass its document_id here.",
      });
    }

    // Load metadata saved by /upload
    const metaPath = path.join("processed", `${documentId}_meta.json`);
    if (!fs.existsSync(metaPath)) {
      return res.status(404).json({
        success: false,
        error: `No uploaded document found for document_id: ${documentId}. Run /api/upload first.`,
      });
    }

    const meta = JSON.parse(fs.readFileSync(metaPath, "utf-8"));
    const { compressed_path: compressedPath, original_path: uploadedPath } = meta;

    console.log(`\n[Process] ═══ Start (${documentId}) ═══`);

    // Step 1: Preprocess / enhance
    console.log("[Process] Step 1: Preprocessing image variants...");
    const variants = await preprocessImage(compressedPath);
    variants.original  = uploadedPath;
    variants.compressed = compressedPath;

    // Step 2: OCR across all variants
    console.log("[Process] Step 2: Running OCR...");
    const ocrResult = await extractText(variants, documentId);

    // Save OCR output for /extract to use
    fs.writeFileSync(
      path.join("processed", `${documentId}_ocr.json`),
      JSON.stringify(ocrResult, null, 2)
    );

    // Save variants map so /extract can reuse them
    fs.writeFileSync(
      path.join("processed", `${documentId}_variants.json`),
      JSON.stringify(variants, null, 2)
    );

    console.log(`[Process] OCR confidence: ${ocrResult.confidence.toFixed(1)}%`);
    console.log(`[Process] ═══ Complete ═══\n`);

    return res.status(200).json({
      success:     true,
      document_id: documentId,
      message:     "Image processed. Use document_id in next step.",
      ocr: {
        confidence:      `${ocrResult.confidence.toFixed(1)}%`,
        quality_score:   ocrResult.qualityScore,
        best_variant:    ocrResult.bestVariant,
        best_config:     ocrResult.bestConfig,
        total_attempts:  ocrResult.totalAttempts,
        character_count: ocrResult.text?.length || 0,
        line_count:      ocrResult.text?.split("\n").filter((l) => l.trim()).length || 0,
        raw_text:        ocrResult.text,
      },
      next_step: "POST /api/extract  →  { document_id }",
    });
  } catch (err) {
    next(err);
  }
}

module.exports = { processDocument };