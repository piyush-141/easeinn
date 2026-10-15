// // src/controllers/upload.controller.js
// const fs = require("fs");
// const path = require("path");
// const { compressImage } = require("../services/compression.service");
// const { generateDocumentId, formatBytes } = require("../utils/helpers");

// /**
//  * POST /api/upload
//  *
//  * Accepts an identity document file + form data.
//  * Compresses the file to under 1MB and stores it.
//  *
//  * Postman setup:
//  *   - Body → form-data
//  *   - Key: "document" (type: File) → select your image
//  *   - Key: "name" (type: Text) → "Rahul Sharma"
//  *   - Key: "dob" (type: Text) → "14/02/1998"
//  *   - Key: "id_number" (type: Text) → "1234 5678 9012"
//  *   - Key: "address" (type: Text) → "123 Main St, Mumbai"
//  */
// async function uploadDocument(req, res, next) {
//   try {
//     if (!req.file) {
//       return res.status(400).json({
//         success: false,
//         error: "No file uploaded. Send a file with field name 'document'.",
//       });
//     }

//     const documentId = req.body.application_id || generateDocumentId();
//     const uploadedPath = req.file.path;
//     const originalSize = req.file.size;

//     console.log(`\n[Upload] Received: ${req.file.originalname} (${formatBytes(originalSize)})`);

//     // Compress the image
//     const compressedPath = await compressImage(uploadedPath);
//     const compressedSize = fs.statSync(compressedPath).size;

//     // Collect form data
//     const formData = {
//       name: req.body.name || null,
//       dob: req.body.dob || null,
//       id_number: req.body.id_number || null,
//       address: req.body.address || null,
//       gender: req.body.gender || null,
//     };

//     // Save form data alongside document
//     fs.mkdirSync("processed", { recursive: true });
//     const formDataPath = path.join("processed", `${documentId}_formdata.json`);
//     fs.writeFileSync(formDataPath, JSON.stringify(formData, null, 2));

//     return res.status(200).json({
//       success: true,
//       document_id: documentId,
//       message: "Document uploaded and compressed successfully",
//       file: {
//         original_name: req.file.originalname,
//         original_size: formatBytes(originalSize),
//         compressed_size: formatBytes(compressedSize),
//         compression_ratio: `${Math.round((1 - compressedSize / originalSize) * 100)}%`,
//         stored_path: compressedPath,
//       },
//       form_data: formData,
//     });
//   } catch (err) {
//     next(err);
//   }
// }

// module.exports = { uploadDocument };

// ========================================================

// src/controllers/upload.controller.js
const fs = require("fs");
const path = require("path");
const { compressImage } = require("../services/compression.service");
const { generateDocumentId, formatBytes } = require("../utils/helpers");

/**
 * POST /api/upload
 *
 * Step 1 of the pipeline.
 * Upload an identity document image + optional form data.
 * Returns a document_id to be used in subsequent steps.
 *
 * Postman:
 *   Body → form-data
 *   Key: "document" (File)
 *   Key: "name", "dob", "id_number", "address", "gender" (Text) — optional here, required at /verify
 */
async function uploadDocument(req, res, next) {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: "No file uploaded. Send a file with field name 'document'.",
      });
    }

    const documentId = req.body.document_id || generateDocumentId();
    const uploadedPath = req.file.path;
    const originalSize = req.file.size;

    console.log(`\n[Upload] ═══ Start (${documentId}) ═══`);
    console.log(`[Upload] File: ${req.file.originalname} (${formatBytes(originalSize)})`);

    // Compress image
    const compressedPath = await compressImage(uploadedPath);
    const compressedSize = fs.statSync(compressedPath).size;

    // Save metadata so downstream steps can locate files
    fs.mkdirSync("processed", { recursive: true });

    const meta = {
      document_id:     documentId,
      original_path:   uploadedPath,
      compressed_path: compressedPath,
      original_name:   req.file.originalname,
      uploaded_at:     new Date().toISOString(),
    };
    fs.writeFileSync(
      path.join("processed", `${documentId}_meta.json`),
      JSON.stringify(meta, null, 2)
    );

    // Save form data if provided (can also be submitted at /verify)
    const formData = {
      name:      req.body.name      || null,
      dob:       req.body.dob       || null,
      id_number: req.body.id_number || null,
      address:   req.body.address   || null,
      gender:    req.body.gender    || null,
    };
    fs.writeFileSync(
      path.join("processed", `${documentId}_formdata.json`),
      JSON.stringify(formData, null, 2)
    );

    console.log(`[Upload] ═══ Complete ═══\n`);

    return res.status(200).json({
      success:     true,
      document_id: documentId,
      message:     "Document uploaded. Use document_id in next steps.",
      file: {
        original_name:     req.file.originalname,
        original_size:     formatBytes(originalSize),
        compressed_size:   formatBytes(compressedSize),
        compression_ratio: `${Math.round((1 - compressedSize / originalSize) * 100)}%`,
      },
      next_step: "POST /api/process  →  { document_id }",
    });
  } catch (err) {
    next(err);
  }
}

module.exports = { uploadDocument };