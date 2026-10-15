// src/utils/helpers.js
const { v4: uuidv4 } = require("uuid");

/**
 * Generate a unique document ID if none provided
 */
function generateDocumentId() {
  return `DOC_${uuidv4().split("-")[0].toUpperCase()}`;
}

/**
 * Format file size in human-readable form
 */
function formatBytes(bytes) {
  if (bytes === 0) return "0 Bytes";
  const sizes = ["Bytes", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(2)} ${sizes[i]}`;
}

/**
 * Normalize a string for comparison (lowercase, trim, remove extra spaces)
 */
function normalizeString(str) {
  if (!str || typeof str !== "string") return "";
  return str
    .toLowerCase()
    .trim()
    .replace(/\s+/g, " ")
    .replace(/[.,\-]/g, "");
}

/**
 * Compare two strings with fuzzy matching
 * Returns a similarity score between 0 and 1
 */
function similarityScore(str1, str2) {
  const a = normalizeString(str1);
  const b = normalizeString(str2);

  if (!a || !b) return 0;
  if (a === b) return 1;

  // Check if one contains the other
  if (a.includes(b) || b.includes(a)) return 0.9;

  // Levenshtein distance based similarity
  const distance = levenshteinDistance(a, b);
  const maxLen = Math.max(a.length, b.length);
  return Math.max(0, 1 - distance / maxLen);
}

/**
 * Levenshtein distance between two strings
 */
function levenshteinDistance(s1, s2) {
  const m = s1.length;
  const n = s2.length;
  const dp = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));

  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;

  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      if (s1[i - 1] === s2[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
      } else {
        dp[i][j] = 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
      }
    }
  }

  return dp[m][n];
}

/**
 * Normalize date to DD/MM/YYYY for comparison
 */
function normalizeDate(dateStr) {
  if (!dateStr || typeof dateStr !== "string") return "";

  // Remove extra spaces
  const cleaned = dateStr.trim().replace(/\s+/g, "");

  // Try DD/MM/YYYY or DD-MM-YYYY
  const match = cleaned.match(/(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})/);
  if (match) {
    const day = match[1].padStart(2, "0");
    const month = match[2].padStart(2, "0");
    const year = match[3];
    return `${day}/${month}/${year}`;
  }

  return cleaned;
}

/**
 * Normalize Aadhaar number (remove spaces, keep only digits)
 */
function normalizeAadhaar(aadhaar) {
  if (!aadhaar || typeof aadhaar !== "string") return "";
  return aadhaar.replace(/\s+/g, "").replace(/[^0-9]/g, "");
}

module.exports = {
  generateDocumentId,
  formatBytes,
  normalizeString,
  similarityScore,
  normalizeDate,
  normalizeAadhaar,
};