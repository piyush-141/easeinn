// src/config/multer.config.js
const multer = require("multer");
const path = require("path");
const fs = require("fs");

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = "uploads/";
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    // application_id prefix if provided, otherwise timestamp
    const prefix = req.body.application_id || Date.now().toString();
    const unique = `${prefix}_${Date.now()}`;
    let ext = path.extname(file.originalname || "").toLowerCase();
    if (!ext || ext === "." || ext === ".octet-stream") {
      ext = ".jpg";
    }
    cb(null, `${unique}${ext}`);
  },
});

const fileFilter = (req, file, cb) => {
  const allowedExtensions = [
    ".jpg", ".jpeg", ".png", ".webp", ".pdf", ".jfif", ".bmp", ".tiff", ""
  ];
  const ext = path.extname(file.originalname || "").toLowerCase();
  const mime = (file.mimetype || "").toLowerCase();

  // Allow any image mime type, pdf, or octet-stream with image/empty extension
  if (
    mime.startsWith("image/") ||
    mime === "application/pdf" ||
    mime === "application/octet-stream" ||
    mime === "binary/octet-stream" ||
    allowedExtensions.includes(ext)
  ) {
    cb(null, true);
  } else {
    cb(new Error("Only JPG, PNG, WEBP and PDF allowed"));
  }
};

const maxSize = (parseInt(process.env.MAX_FILE_SIZE_MB) || 15) * 1024 * 1024;

const upload = multer({
  storage,
  fileFilter,
  limits: { fileSize: maxSize },
});

module.exports = upload;