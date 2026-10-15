// // src/controllers/extract.controller.js
// const fs = require("fs");
// const path = require("path");
// const { compressImage } = require("../services/compression.service");
// const { preprocessImage } = require("../services/preprocessing.service");
// const { extractText } = require("../services/ocr.service");
// const { extractFieldsFromText } = require("../services/extraction.service");
// const {
//   extractFieldsWithVision,
//   isOllamaAvailable,
// } = require("../services/ollama-vision.service");
// const { generateDocumentId } = require("../utils/helpers");

// async function extractFields(req, res, next) {
//   try {
//     if (!req.file) {
//       return res.status(400).json({
//         success: false,
//         error: "No file uploaded. Send a file with field name 'document'.",
//       });
//     }

//     const documentId = req.body.document_id || generateDocumentId();
//     const method = req.body.extraction_method || req.query.method || "auto";
//     const uploadedPath = req.file.path;

//     console.log(`\n[Extract] ═══ Start (${documentId}, method=${method}) ═══`);

//     // Step 1: Compress
//     const compressedPath = await compressImage(uploadedPath);

//     // Step 2: Generate document-specific preprocessed variants
//     const variants = await preprocessImage(compressedPath);

//     // Also add the original and compressed as variants
//     variants.original = uploadedPath;
//     variants.compressed = compressedPath;

//     let ocrFields = null;
//     let visionFields = null;
//     let ocrResult = null;
//     let usedMethod = "none";

//     // ── OCR EXTRACTION (multi-variant × multi-config) ──
//     if (method === "ocr" || method === "auto") {
//       try {
//         console.log("[Extract] Running enhanced multi-pass OCR...");
//         ocrResult = await extractText(variants, documentId);
//         ocrFields = extractFieldsFromText(ocrResult, `${documentId}_ocr`);
//         console.log("[Extract] OCR result:", ocrFields);
//       } catch (ocrErr) {
//         console.warn("[Extract] OCR failed:", ocrErr.message);
//       }
//     }

//     // ── VISION MODEL EXTRACTION ──
//     if (method === "vision" || method === "auto") {
//       const ollamaReady = await isOllamaAvailable();
//       if (ollamaReady) {
//         try {
//           console.log("[Extract] Running vision model...");
//           const imagesToTry = [...new Set([compressedPath, uploadedPath])];
//           let best = null;
//           let bestScore = -1;

//           for (const img of imagesToTry) {
//             try {
//               const result = await extractFieldsWithVision(img, `${documentId}_vision`);
//               const score = countNonNull(result);
//               if (score > bestScore) { best = result; bestScore = score; }
//             } catch (_e) { /* skip */ }
//           }

//           if (best) {
//             visionFields = best;
//             console.log("[Extract] Vision result:", visionFields);
//           }
//         } catch (visionErr) {
//           console.warn("[Extract] Vision failed:", visionErr.message);
//         }
//       } else {
//         console.warn("[Extract] Ollama not available — skipping vision");
//       }
//     }

//     // ── MERGE RESULTS ──
//     let finalFields = null;

//     if (ocrFields && visionFields) {
//       finalFields = smartMerge(visionFields, ocrFields);
//       usedMethod = "merged";
//       console.log("[Extract] Merged OCR + Vision");
//     } else if (visionFields) {
//       finalFields = visionFields;
//       usedMethod = "vision";
//     } else if (ocrFields) {
//       finalFields = ocrFields;
//       usedMethod = "ocr";
//     }

//     if (!finalFields) {
//       return res.status(422).json({
//         success: false,
//         error: "Could not extract any fields. Ensure the image is clear.",
//       });
//     }

//     // Save final
//     fs.mkdirSync("processed", { recursive: true });
//     fs.writeFileSync(
//       path.join("processed", `${documentId}_final.json`),
//       JSON.stringify(finalFields, null, 2)
//     );

//     const fieldCount = countNonNull(finalFields);
//     console.log(`[Extract] Final: ${fieldCount} fields extracted via ${usedMethod}`);
//     console.log(`[Extract] ═══ Complete ═══\n`);

//     const response = {
//       success: true,
//       document_id: documentId,
//       extraction_method: usedMethod,
//       document_type: finalFields.document_type || "unknown",
//       extracted_data: finalFields,
//       quality: {
//         fields_extracted: fieldCount,
//         fields_total: 7,
//         extraction_rate: `${Math.round((fieldCount / 7) * 100)}%`,
//       },
//     };

//     if (ocrResult) {
//       response.ocr_details = {
//         confidence: `${ocrResult.confidence.toFixed(1)}%`,
//         quality_score: ocrResult.qualityScore,
//         best_variant: ocrResult.bestVariant,
//         best_config: ocrResult.bestConfig,
//         total_attempts: ocrResult.totalAttempts,
//         top_results: ocrResult.topResults,
//       };
//     }

//     if (ocrFields && visionFields) {
//       response.comparison = {
//         ocr: { fields: countNonNull(ocrFields), data: ocrFields },
//         vision: { fields: countNonNull(visionFields), data: visionFields },
//         merged: { fields: countNonNull(finalFields), data: finalFields },
//       };
//     }

//     return res.status(200).json(response);
//   } catch (err) {
//     next(err);
//   }
// }

// /**
//  * Smart merge: prefer vision model, fill gaps with OCR,
//  * but if OCR has a more specific value, prefer it
//  */
// function smartMerge(vision, ocr) {
//   const keys = [
//     "document_type", "name", "dob", "gender",
//     "id_number", "address", "pincode", "father_name",
//   ];

//   const merged = {};

//   for (const key of keys) {
//     const v = vision[key];
//     const o = ocr[key];

//     const vExists = v !== null && v !== undefined && v !== "";
//     const oExists = o !== null && o !== undefined && o !== "";

//     if (vExists && oExists) {
//       // Both have a value — prefer the more specific/longer one
//       // Exception: for id_number, prefer the formatted version
//       if (key === "id_number") {
//         // Prefer the one with proper formatting (spaces/dashes)
//         merged[key] = v.includes(" ") ? v : (o.includes(" ") ? o : v);
//       } else if (key === "address") {
//         // Prefer longer address
//         merged[key] = v.length >= o.length ? v : o;
//       } else {
//         // Default: prefer vision
//         merged[key] = v;
//       }
//     } else if (vExists) {
//       merged[key] = v;
//     } else if (oExists) {
//       merged[key] = o;
//     } else {
//       merged[key] = null;
//     }
//   }

//   return merged;
// }

// function countNonNull(fields) {
//   if (!fields) return 0;
//   const keys = ["name", "dob", "gender", "id_number", "address", "pincode"];
//   return keys.reduce((c, k) => {
//     const v = fields[k];
//     return v !== null && v !== undefined && v !== "" ? c + 1 : c;
//   }, 0);
// }

// module.exports = { extractFields };

//=============================

// src/controllers/extract.controller.js
const fs = require("fs");
const path = require("path");
const { extractFieldsFromText } = require("../services/extraction.service");
const {
  extractFieldsWithVision,
  isOllamaAvailable,
} = require("../services/ollama-vision.service");
const { generateDocumentId } = require("../utils/helpers");

/**
 * POST /api/extract
 *
 * Step 3 of the pipeline.
 * Takes document_id from /process, reads saved OCR output and image variants,
 * runs field extraction (OCR-based + vision), and saves structured fields.
 *
 * Postman:
 *   Body → raw JSON
 *   { "document_id": "abc123", "extraction_method": "auto" }   ← method optional
 */
async function extractFields(req, res, next) {
  try {
    const documentId = req.body.document_id;
    const method = req.body.extraction_method || req.query.method || "auto";

    if (!documentId) {
      return res.status(400).json({
        success: false,
        error: "Missing 'document_id'. Run /api/process first and pass its document_id here.",
      });
    }

    // Load OCR result saved by /process
    const ocrPath      = path.join("processed", `${documentId}_ocr.json`);
    const variantsPath = path.join("processed", `${documentId}_variants.json`);
    const metaPath     = path.join("processed", `${documentId}_meta.json`);

    if (!fs.existsSync(ocrPath)) {
      return res.status(404).json({
        success: false,
        error: `No processed data found for document_id: ${documentId}. Run /api/process first.`,
      });
    }

    const ocrResult = JSON.parse(fs.readFileSync(ocrPath,      "utf-8"));
    const variants  = JSON.parse(fs.readFileSync(variantsPath, "utf-8"));
    const meta      = JSON.parse(fs.readFileSync(metaPath,     "utf-8"));

    console.log(`\n[Extract] ═══ Start (${documentId}, method=${method}) ═══`);

    let ocrFields    = null;
    let visionFields = null;
    let usedMethod   = "none";

    // ── OCR FIELD EXTRACTION ──
    if (method === "ocr" || method === "auto") {
      try {
        console.log("[Extract] Extracting fields from OCR text...");
        ocrFields = extractFieldsFromText(ocrResult, `${documentId}_ocr`);
        console.log("[Extract] OCR fields:", ocrFields);
      } catch (ocrErr) {
        console.warn("[Extract] OCR field extraction failed:", ocrErr.message);
      }
    }

    // ── VISION MODEL EXTRACTION ──
    if (method === "vision" || method === "auto") {
      const ollamaReady = await isOllamaAvailable();
      if (ollamaReady) {
        try {
          console.log("[Extract] Running vision model...");
          const imagesToTry = [...new Set([
            meta.compressed_path,
            meta.original_path,
          ])].filter(Boolean);

          let best      = null;
          let bestScore = -1;

          for (const img of imagesToTry) {
            try {
              const result = await extractFieldsWithVision(img, `${documentId}_vision`);
              const score  = countNonNull(result);
              if (score > bestScore) { best = result; bestScore = score; }
            } catch (_e) { /* skip */ }
          }

          if (best) {
            visionFields = best;
            console.log("[Extract] Vision fields:", visionFields);
          }
        } catch (visionErr) {
          console.warn("[Extract] Vision failed:", visionErr.message);
        }
      } else {
        console.warn("[Extract] Ollama not available — skipping vision");
      }
    }

    // ── MERGE ──
    let finalFields = null;

    if (ocrFields && visionFields) {
      finalFields = smartMerge(visionFields, ocrFields);
      usedMethod  = "merged";
    } else if (visionFields) {
      finalFields = visionFields;
      usedMethod  = "vision";
    } else if (ocrFields) {
      finalFields = ocrFields;
      usedMethod  = "ocr";
    }

    if (!finalFields) {
      return res.status(422).json({
        success: false,
        error: "Could not extract any fields. Ensure the image is clear.",
      });
    }

    // Save extracted fields for /verify to use
    fs.writeFileSync(
      path.join("processed", `${documentId}_extracted.json`),
      JSON.stringify(finalFields, null, 2)
    );

    const fieldCount = countNonNull(finalFields);
    console.log(`[Extract] ${fieldCount} fields extracted via ${usedMethod}`);
    console.log(`[Extract] ═══ Complete ═══\n`);

    const response = {
      success:           true,
      document_id:       documentId,
      extraction_method: usedMethod,
      document_type:     finalFields.document_type || "unknown",
      extracted_data:    finalFields,
      quality: {
        fields_extracted: fieldCount,
        fields_total:     6,
        extraction_rate:  `${Math.round((fieldCount / 6) * 100)}%`,
      },
      next_step: "POST /api/verify  →  { document_id, name, dob, id_number, address, gender }",
    };

    if (ocrFields && visionFields) {
      response.comparison = {
        ocr:    { fields: countNonNull(ocrFields),    data: ocrFields    },
        vision: { fields: countNonNull(visionFields), data: visionFields },
        merged: { fields: countNonNull(finalFields),  data: finalFields  },
      };
    }

    return res.status(200).json(response);
  } catch (err) {
    next(err);
  }
}

function smartMerge(vision, ocr) {
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
        merged[key] = v.includes(" ") ? v : (o.includes(" ") ? o : v);
      } else if (key === "address") {
        merged[key] = v.length >= o.length ? v : o;
      } else {
        merged[key] = v; // prefer vision
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

function countNonNull(fields) {
  if (!fields) return 0;
  const keys = ["name", "dob", "gender", "id_number", "address", "pincode"];
  return keys.reduce((c, k) => {
    const v = fields[k];
    return v !== null && v !== undefined && v !== "" ? c + 1 : c;
  }, 0);
}

module.exports = { extractFields };