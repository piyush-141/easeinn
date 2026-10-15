// src/middleware/error.middleware.js
const multer = require("multer");

function errorHandler(err, req, res, next) {
  console.error("[Error]", err.message);

  // Multer-specific errors
  if (err instanceof multer.MulterError) {
    if (err.code === "LIMIT_FILE_SIZE") {
      return res.status(413).json({
        success: false,
        error: "File too large. Maximum allowed size is 15MB.",
      });
    }
    return res.status(400).json({
      success: false,
      error: `Upload error: ${err.message}`,
    });
  }

  // Custom file filter error
  if (err.message === "Only JPG, PNG and PDF allowed") {
    return res.status(415).json({
      success: false,
      error: err.message,
    });
  }

  // Generic server error
  return res.status(err.status || 500).json({
    success: false,
    error: err.message || "Internal Server Error",
  });
}

module.exports = { errorHandler };