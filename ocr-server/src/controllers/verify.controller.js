// // src/controllers/verify.controller.js
// const fs = require("fs");
// const path = require("path");
// const { verifyDocument } = require("../services/verification.service");
// const { generateDocumentId } = require("../utils/helpers");

// /**
//  * POST /api/verify
//  *
//  * Accepts the output of /api/extract + form data to verify.
//  *
//  * Two usage modes:
//  *
//  * Mode A — Pass extracted_data as JSON body (no file upload needed):
//  *   Content-Type: application/json
//  *   {
//  *     "document_id": "abc123",          // optional, reuse extract's doc ID
//  *     "extracted_data": { ...fields },  // output from /api/extract
//  *     "name": "Rahul Sharma",
//  *     "dob": "14/02/1998",
//  *     "id_number": "1234 5678 9012",
//  *     "address": "123 Main Street, Mumbai",
//  *     "gender": "MALE"
//  *   }
//  *
//  * Mode B — Pass extracted_data as a form-data field (string JSON):
//  *   Body → form-data
//  *   Key: "extracted_data" (Text) → JSON string of extract output
//  *   Key: "name" (Text) → "Rahul Sharma"
//  *   ... other form fields
//  */
// async function verifyDocumentHandler(req, res, next) {
//   try {
//     const documentId = req.body.document_id || generateDocumentId();

//     // ── Parse extracted_data ──
//     // Accept either a parsed object (JSON body) or a JSON string (form-data)
//     let extractedData = req.body.extracted_data;

//     if (typeof extractedData === "string") {
//       try {
//         extractedData = JSON.parse(extractedData);
//       } catch {
//         return res.status(400).json({
//           success: false,
//           error: "Invalid JSON in 'extracted_data' field.",
//         });
//       }
//     }

//     // Support passing the full /api/extract response — unwrap if needed
//     if (extractedData && extractedData.extracted_data) {
//       extractedData = extractedData.extracted_data;
//     }

//     if (!extractedData || typeof extractedData !== "object") {
//       return res.status(400).json({
//         success: false,
//         error:
//           "Missing 'extracted_data'. Provide the output from /api/extract " +
//           "either as a JSON body field or a stringified form-data field.",
//       });
//     }

//     // ── Collect form data to verify against ──
//     const formData = {
//       name:      req.body.name      || null,
//       dob:       req.body.dob       || null,
//       id_number: req.body.id_number || null,
//       address:   req.body.address   || null,
//       gender:    req.body.gender    || null,
//     };

//     const hasFormData = Object.values(formData).some((v) => v !== null);
//     if (!hasFormData) {
//       return res.status(400).json({
//         success: false,
//         error:
//           "No form data provided. Submit at least one field " +
//           "(name, dob, id_number, address, gender) to verify against.",
//       });
//     }

//     console.log(`\n[Verify] === Start (${documentId}) ===`);
//     console.log("[Verify] Extracted data received:", extractedData);
//     console.log("[Verify] Form data to verify:", formData);

//     // ── Verify ──
//     const verification = verifyDocument(extractedData, formData);

//     // ── Save report ──
//     const report = {
//       document_id:        documentId,
//       document_type:      extractedData.document_type || "unknown",
//       extraction_method:  extractedData.extraction_method || "pre-extracted",
//       extracted_data:     extractedData,
//       form_data:          formData,
//       verification,
//       timestamp:          new Date().toISOString(),
//     };

//     fs.mkdirSync("processed", { recursive: true });
//     fs.writeFileSync(
//       path.join("processed", `${documentId}_report.json`),
//       JSON.stringify(report, null, 2)
//     );

//     console.log(`[Verify] Score: ${verification.confidence_score}`);
//     console.log(`[Verify] === Complete ===\n`);

//     return res.status(200).json({
//       success:            true,
//       document_id:        documentId,
//       document_type:      extractedData.document_type || "unknown",
//       extraction_method:  extractedData.extraction_method || "pre-extracted",
//       extracted_data: {
//         name:       extractedData.name       || null,
//         dob:        extractedData.dob        || null,
//         id_number:  extractedData.id_number  || null,
//         address:    extractedData.address    || null,
//         gender:     extractedData.gender     || null,
//         pincode:    extractedData.pincode    || null,
//       },
//       verification: {
//         is_verified:          verification.is_verified,
//         confidence_score:     verification.confidence_score,
//         matched_fields:       verification.matched_fields,
//         mismatched_fields:    verification.mismatched_fields,
//         unverifiable_fields:  verification.unverifiable_fields,
//         field_details:        verification.field_results,
//       },
//     });
//   } catch (err) {
//     next(err);
//   }
// }

// module.exports = { verifyDocumentHandler };


//================================

// src/controllers/verify.controller.js
const fs = require("fs");
const path = require("path");
const { verifyDocument } = require("../services/verification.service");
const { generateDocumentId } = require("../utils/helpers");

/**
 * POST /api/verify
 *
 * Step 4 (final) of the pipeline.
 * Reads extracted fields saved by /extract, compares with submitted form data.
 *
 * Postman:
 *   Body → raw JSON
 *   {
 *     "document_id": "abc123",
 *     "name":        "Rahul Sharma",
 *     "dob":         "14/02/1998",
 *     "id_number":   "1234 5678 9012",
 *     "address":     "123 Main Street, Mumbai",
 *     "gender":      "MALE"
 *   }
 */
async function verifyDocumentHandler(req, res, next) {
  try {
    const documentId = req.body.document_id;

    if (!documentId) {
      return res.status(400).json({
        success: false,
        error: "Missing 'document_id'. Run /api/extract first and pass its document_id here.",
      });
    }

    // Load extracted fields saved by /extract
    const extractedPath = path.join("processed", `${documentId}_extracted.json`);
    if (!fs.existsSync(extractedPath)) {
      return res.status(404).json({
        success: false,
        error: `No extracted data found for document_id: ${documentId}. Run /api/extract first.`,
      });
    }

    const extractedData = JSON.parse(fs.readFileSync(extractedPath, "utf-8"));

    // Collect form data from request body
    // Also fall back to form data saved during /upload if not provided here
    let formData = {
      name:      req.body.name      || null,
      dob:       req.body.dob       || null,
      id_number: req.body.id_number || null,
      address:   req.body.address   || null,
      gender:    req.body.gender    || null,
    };

    // If nothing provided in body, try loading from /upload saved form data
    const hasBodyFormData = Object.values(formData).some((v) => v !== null);
    if (!hasBodyFormData) {
      const savedFormPath = path.join("processed", `${documentId}_formdata.json`);
      if (fs.existsSync(savedFormPath)) {
        const saved = JSON.parse(fs.readFileSync(savedFormPath, "utf-8"));
        const hasSavedData = Object.values(saved).some((v) => v !== null);
        if (hasSavedData) {
          formData = saved;
          console.log("[Verify] Using form data saved from /upload");
        }
      }
    }

    const hasFormData = Object.values(formData).some((v) => v !== null);
    if (!hasFormData) {
      return res.status(400).json({
        success: false,
        error:
          "No form data provided. Submit at least one field " +
          "(name, dob, id_number, address, gender) to verify against, " +
          "or include them when calling /api/upload.",
      });
    }

    console.log(`\n[Verify] ═══ Start (${documentId}) ═══`);
    console.log("[Verify] Extracted data:", extractedData);
    console.log("[Verify] Form data:", formData);

    // Verify
    const verification = verifyDocument(extractedData, formData);

    // Save full report
    const report = {
      document_id:       documentId,
      document_type:     extractedData.document_type || "unknown",
      extracted_data:    extractedData,
      form_data:         formData,
      verification,
      timestamp:         new Date().toISOString(),
    };

    fs.mkdirSync("processed", { recursive: true });
    fs.writeFileSync(
      path.join("processed", `${documentId}_report.json`),
      JSON.stringify(report, null, 2)
    );

    console.log(`[Verify] Score: ${verification.confidence_score}`);
    console.log(`[Verify] ═══ Complete ═══\n`);

    return res.status(200).json({
      success:      true,
      document_id:  documentId,
      document_type: extractedData.document_type || "unknown",
      extracted_data: {
        name:      extractedData.name      || null,
        dob:       extractedData.dob       || null,
        id_number: extractedData.id_number || null,
        address:   extractedData.address   || null,
        gender:    extractedData.gender    || null,
        pincode:   extractedData.pincode   || null,
      },
      verification: {
        is_verified:         verification.is_verified,
        confidence_score:    verification.confidence_score,
        matched_fields:      verification.matched_fields,
        mismatched_fields:   verification.mismatched_fields,
        unverifiable_fields: verification.unverifiable_fields,
        field_details:       verification.field_results,
      },
    });
  } catch (err) {
    next(err);
  }
}

module.exports = { verifyDocumentHandler };