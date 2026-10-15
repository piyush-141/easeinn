// src/routes/api.routes.js
const express = require("express");
const router = express.Router();
const upload = require("../config/multer.config");

const { uploadDocument }        = require("../controllers/upload.controller");
const { processDocument }       = require("../controllers/process.controller");
const { extractFields }         = require("../controllers/extract.controller");
const { verifyDocumentHandler } = require("../controllers/verify.controller");
const { scanDocumentHandler }   = require("../controllers/checkin-scan.controller");

/**
 * CHECK-IN SCANNING ENDPOINTS:
 * Single & Multi-side (Aadhaar front + back) document OCR with automatic field extraction
 */
const checkinUpload = upload.fields([
  { name: "document", maxCount: 1 },
  { name: "document_front", maxCount: 1 },
  { name: "document_back", maxCount: 1 },
  { name: "front", maxCount: 1 },
  { name: "back", maxCount: 1 },
]);

router.post("/scan-document", checkinUpload, scanDocumentHandler);
router.post("/pipeline", checkinUpload, scanDocumentHandler);

/**
 * MULTI-STEP PIPELINE (Original iitr-reference preserved as-is):
 *
 *  1. POST /api/upload   — upload file → get document_id
 *  2. POST /api/process  — { document_id } → preprocess + OCR
 *  3. POST /api/extract  — { document_id } → structured fields
 *  4. POST /api/verify   — { document_id, name, dob, ... } → verification report
 */
router.post("/upload", upload.single("document"), uploadDocument);
router.post("/process", processDocument);
router.post("/extract", extractFields);
router.post("/verify",  verifyDocumentHandler);

/**
 * GET /api/status/:document_id
 * Retrieve any saved artefacts for a document
 */
router.get("/status/:document_id", (req, res) => {
  const fs   = require("fs");
  const path = require("path");
  const docId = req.params.document_id;

  const files = {
    meta:         path.join("processed", `${docId}_meta.json`),
    form_data:    path.join("processed", `${docId}_formdata.json`),
    ocr:          path.join("processed", `${docId}_ocr.json`),
    variants:     path.join("processed", `${docId}_variants.json`),
    extracted:    path.join("processed", `${docId}_extracted.json`),
    report:       path.join("processed", `${docId}_report.json`),
  };

  const result = { document_id: docId };

  for (const [key, filePath] of Object.entries(files)) {
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, "utf-8");
      try { result[key] = JSON.parse(content); }
      catch { result[key] = content; }
    }
  }

  if (Object.keys(result).length === 1) {
    return res.status(404).json({
      success: false,
      error: `No data found for document_id: ${docId}`,
    });
  }

  return res.json({ success: true, ...result });
});

module.exports = router;