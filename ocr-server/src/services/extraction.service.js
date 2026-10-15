// src/services/extraction.service.js
const fs = require("fs");
const path = require("path");

function detectDocumentType(text) {
  const t = text.toLowerCase();

  let aadhaarScore = 0;
  let panScore = 0;

  if (/aadhaar|aadhar|आधार/.test(t)) aadhaarScore += 3;
  if (/uidai/.test(t)) aadhaarScore += 3;
  if (/unique identification/.test(t)) aadhaarScore += 2;
  if (/enrol/.test(t)) aadhaarScore += 1;
  if (/\d{4}\s\d{4}\s\d{4}/.test(text)) aadhaarScore += 4;
  if (/VID/.test(text)) aadhaarScore += 2;

  if (/income tax/.test(t)) panScore += 3;
  if (/permanent account/.test(t)) panScore += 3;
  if (/[A-Z]{5}[0-9]{4}[A-Z]/.test(text)) panScore += 4;
  if (/dept|department/.test(t)) panScore += 1;
  if (/father/.test(t)) panScore += 1;

  if (aadhaarScore > panScore && aadhaarScore >= 3) return "aadhaar";
  if (panScore > aadhaarScore && panScore >= 3) return "pan";
  if (/voter|election/i.test(t)) return "voter_id";
  if (/passport|republic of india/i.test(t)) return "passport";

  return "unknown";
}

// ═══════════════════════════════════════════════
//  NAME EXTRACTION — Multi-Strategy
// ═══════════════════════════════════════════════

function extractName(raw, text, docType) {
  const strategies = [
    () => extractNameFromExplicitLabel(raw, text),
    () => extractNameFromRelationLine(raw, text),
    () => extractNameFromContextualPosition(raw),
    () => extractNameFromCapitalizedLines(raw, docType),
    () => extractNameFromAllCapsLines(raw, docType),
    () => extractNameFromLoosePatterns(raw, text),
  ];

  for (const strategy of strategies) {
    try {
      const name = strategy();
      if (name && isValidName(name, docType)) {
        const cleaned = cleanName(name);
        if (cleaned.length >= 2) {
          return cleaned;
        }
      }
    } catch (_e) {
      // skip failed strategy
    }
  }

  return null;
}

function extractNameFromExplicitLabel(raw, text) {
  const patterns = [
    /(?:Name|नाम)\s*[:=\.]\s*([A-Za-z][A-Za-z .'\-]{2,40})/i,
    /(?:Name|नाम)\s*[:=\.]\s*\n?\s*([A-Za-z][A-Za-z .'\-]{2,40})/im,
    /To[,\s]+([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3})/,
  ];

  for (const p of patterns) {
    const match = text.match(p) || raw.match(p);
    if (match) return match[1].trim();
  }
  return null;
}

function extractNameFromRelationLine(raw, text) {
  const patterns = [
    /([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,3})\s*\n?\s*[SDWC]\/O/im,
    /([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,3})\s+(?:son|daughter|wife)\s+of/i,
    /([A-Z]{2,}(?:\s+[A-Z]{2,}){0,3})\s*\n?\s*[SDWC]\/O/m,
  ];

  for (const p of patterns) {
    const match = raw.match(p) || text.match(p);
    if (match) return toTitleCase(match[1].trim());
  }
  return null;
}

function extractNameFromContextualPosition(raw) {
  const lines = raw.split("\n").map((l) => l.trim()).filter(Boolean);

  let dobIdx = -1;
  let genderIdx = -1;

  for (let i = 0; i < lines.length; i++) {
    if (/DOB|Date of Birth|जन्म|Year of Birth/i.test(lines[i]) ||
      /\d{2}[\/\-]\d{2}[\/\-]\d{4}/.test(lines[i])) {
      if (dobIdx === -1) dobIdx = i;
    }
    if (/\b(MALE|FEMALE|पुरुष|महिला)\b/i.test(lines[i])) {
      if (genderIdx === -1) genderIdx = i;
    }
  }

  const anchorIdx = dobIdx >= 0 ? dobIdx : genderIdx;
  if (anchorIdx < 0) return null;

  for (let offset = 1; offset <= 4 && anchorIdx - offset >= 0; offset++) {
    const candidate = lines[anchorIdx - offset];
    if (looksLikeName(candidate)) {
      return toTitleCase(candidate.replace(/\s+[a-z]$/, "").trim());
    }
  }

  return null;
}

function extractNameFromCapitalizedLines(raw, docType) {
  const lines = raw.split("\n").map((l) => l.trim()).filter(Boolean);

  const skipPatterns = [
    /government/i,
    /india/i,
    /aadhaar/i,
    /aadhar/i,
    /uidai/i,
    /enrol/i,
    /unique/i,
    /identification/i,
    /authority/i,
    /\d{4}\s\d{4}\s\d{4}/,
    /DOB/i,
    /Date of Birth/i,
    /^Address/i,
    /^Male$/i,
    /^Female$/i,
    /VID/i,
    /download/i,
    /income tax/i,
    /permanent/i,
    /department/i,
    /^[0-9\s]+$/,
    /help/i,
    /www\./i,
    /http/i,
    /signature/i,
    /^issue/i,
    /^Govt/i,
    /^of$/i,
    /^the$/i,
    /^TEST$/i,                        // FIX: skip "TEST" header line
    /आधार|भारत|सरकार|प्राधिकरण|विशिष्ट/,
    /[A-Z]{5}[0-9]{4}[A-Z]/,
    /^\d{2}[\/\-]\d{2}/,
    // FIX: skip lines with high symbol/noise ratio
    /[@=\|\\]{2,}/,                   // lines with multiple symbols
    /[^\x00-\x7F]{3,}/,               // lines heavy with non-ASCII (Hindi headers)
    // FIX: skip lines that are clearly garbled (contain no real word >= 3 clean letters)
    /^[^A-Za-z]*$/,                   // no letters at all
  ];

  // FIX: helper to detect garbled text — too many non-alpha chars mixed in
  function isGarbled(line) {
    const letters = (line.match(/[A-Za-z]/g) || []).length;
    const noise   = (line.match(/[@=\-_\|\\\/\*\+~`"'<>]/g) || []).length;
    if (letters === 0) return true;
    if (noise / letters > 0.3) return true;   // >30% noise chars → garbled

    // FIX: if any single "word" is suspiciously long (>15 chars, no spaces)
    // it's likely a mashed-up header like "Govemmentiofiidiammess"
    const words = line.split(/\s+/);
    for (const w of words) {
      if (w.length > 15) return true;
    }
    return false;
  }

  const candidates = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (skipPatterns.some((p) => p.test(line))) continue;
    if (line.length < 2 || line.length > 45) continue;
    if (isGarbled(line)) continue;                         // FIX: skip garbled lines

    const digitRatio = (line.match(/\d/g) || []).length / line.length;
    if (digitRatio > 0.25) continue;

    // Title Case: "Rahul Sharma" or single word "Tahzeen"
    if (/^[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,3}$/.test(line)) {
      candidates.push({ name: line, score: 12, line: i });
    }
    // ALL CAPS with 2+ words: "RAHUL SHARMA"
    else if (/^[A-Z]{2,}(?:\s+[A-Z]{2,}){1,3}$/.test(line)) {
      candidates.push({ name: toTitleCase(line), score: 10, line: i });
    }
    // Mixed with minor noise char: "j Rahul Sharma" or "Rahul Sharma g"
    else if (/^[a-z]?\s*[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,3}\s*[a-z]?$/.test(line)) {
      const cleaned = line.replace(/^[a-z]\s*/, "").replace(/\s*[a-z]$/, "");
      candidates.push({ name: cleaned, score: 7, line: i });
    }
  }

  if (candidates.length === 0) return null;

  // Prefer candidates NOT on line 0 (line 0 is almost always a header)
  candidates.sort((a, b) => {
    const aPos = a.line === 0 ? 999 : a.line;   // FIX: push line-0 to end
    const bPos = b.line === 0 ? 999 : b.line;
    if (b.score !== a.score) return b.score - a.score;
    return aPos - bPos;
  });

  return candidates[0].name;
}

function extractNameFromAllCapsLines(raw, docType) {
  const lines = raw.split("\n").map((l) => l.trim()).filter(Boolean);

  const nonNameWords = new Set([
    "GOVERNMENT", "INDIA", "OF", "THE", "AADHAAR", "UIDAI",
    "MALE", "FEMALE", "DOB", "ADDRESS", "INCOME", "TAX",
    "DEPARTMENT", "PERMANENT", "ACCOUNT", "NUMBER", "CARD",
    "ENROLMENT", "ENROLLMENT", "UNIQUE", "IDENTIFICATION",
    "AUTHORITY", "VID", "REPUBLIC", "VOTER", "ELECTION",
    "COMMISSION", "PAN", "DOWNLOAD", "HELP", "ISSUE", "TEST",  // FIX: added TEST
  ]);

  for (const line of lines) {
    const words = line.split(/\s+/).filter((w) => /^[A-Z]{2,}$/.test(w));
    if (words.length < 2) continue;

    const nameWords = words.filter((w) => !nonNameWords.has(w));
    if (nameWords.length < 2) continue;

    if (/\d/.test(line)) continue;

    return toTitleCase(nameWords.join(" "));
  }

  return null;
}

function extractNameFromLoosePatterns(raw, text) {
  const patterns = [
    /(?:India|Aadhaar|UIDAI)[^\n]*\n[^\n]*\n\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3})/i,
    /[\u0900-\u097F]+\s*\n\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3})/,
    /\n\s*([A-Z][a-z]{2,}(?:\s+[A-Z][a-z]{2,}){0,2})\s*\n/,   // FIX: allow single-word name
  ];

  for (const p of patterns) {
    const match = raw.match(p);
    if (match && looksLikeName(match[1])) {
      return match[1].trim();
    }
  }

  return null;
}

// ═══════════════════════════════════════════════
//  NAME VALIDATION HELPERS
// ═══════════════════════════════════════════════

function looksLikeName(text) {
  if (!text || typeof text !== "string") return false;
  const cleaned = text.trim();
  if (cleaned.length < 2 || cleaned.length > 50) return false;
  if (!/[A-Za-z]/.test(cleaned)) return false;

  const digitRatio = (cleaned.match(/\d/g) || []).length / cleaned.length;
  if (digitRatio > 0.2) return false;

  const blacklist = [
    "government", "india", "aadhaar", "aadhar", "uidai",
    "male", "female", "address", "dob", "date", "birth",
    "income", "tax", "department", "permanent", "account",
    "enrolment", "enrollment", "unique", "identification",
    "authority", "download", "help", "issue", "card", "test",  // FIX: added test
  ];

  if (blacklist.includes(cleaned.toLowerCase())) return false;

  // FIX: reject if any single word is longer than 20 chars (garbled header)
  const words = cleaned.split(/\s+/);
  for (const w of words) {
    if (w.length > 20) return false;
  }

  const validWords = words.filter((w) => /[A-Za-z]{2,}/.test(w));
  return validWords.length >= 1;
}

function isValidName(name, docType) {
  return looksLikeName(name);
}

function cleanName(name) {
  return name
    .replace(/\s+/g, " ")
    .replace(/[^A-Za-z .'\-]/g, "")
    .replace(/^\s*[a-z]\s+/, "")
    .replace(/\s+[a-z]\s*$/, "")
    .replace(/\s+/g, " ")
    .trim();
}

function toTitleCase(str) {
  return str
    .toLowerCase()
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

// ═══════════════════════════════════════════════
//  DOB EXTRACTION
// ═══════════════════════════════════════════════

function extractDob(raw, text) {
  const patterns = [
    /(?:DOB|D\.O\.B|Date of Birth|जन्म\s*(?:तिथि|दिनांक)?|Birth\s*Date)\s*[:\-\/=.\s]+(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{4})/i,
    /(?:Year of Birth|YOB|जन्म\s*वर्ष)\s*[:\-\/=.\s]+(\d{4})/i,
    /DOB[^0-9]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{4})/i,
    /\b(\d{2}[\/\-]\d{2}[\/\-]\d{4})\b/,
  ];

  for (const p of patterns) {
    const match = text.match(p) || raw.replace(/\n/g, " ").match(p);
    if (match) {
      let dob = match[1].trim();

      if (/^\d{4}$/.test(dob)) {
        const year = parseInt(dob);
        if (year >= 1920 && year <= 2015) return `01/01/${dob}`;
        continue;
      }

      dob = dob.replace(/\./g, "/").replace(/-/g, "/");
      const parts = dob.split("/");
      if (parts.length === 3) {
        const day = parseInt(parts[0]);
        const month = parseInt(parts[1]);
        const year = parseInt(parts[2]);

        if (day >= 1 && day <= 31 && month >= 1 && month <= 12 && year >= 1920 && year <= 2024) {
          return `${parts[0].padStart(2, "0")}/${parts[1].padStart(2, "0")}/${parts[2]}`;
        }
      }
    }
  }

  return null;
}

// ═══════════════════════════════════════════════
//  ID NUMBER EXTRACTION
// ═══════════════════════════════════════════════

function extractIdNumber(raw, text, docType) {
  if (docType === "aadhaar" || docType === "unknown") {
    const aadhaarPatterns = [
      /\b(\d{4}\s\d{4}\s\d{4})\b/,
      /\b(\d{4}[\s.\-_]\d{4}[\s.\-_]\d{4})\b/,
      /\b(\d{12})\b/,
      /(?:Aadhaar|Aadhar|UID)[^0-9]*(\d{4}\s?\d{4}\s?\d{4})/i,
    ];

    for (const p of aadhaarPatterns) {
      const match = text.match(p) || raw.replace(/\n/g, " ").match(p);
      if (match) {
        const digits = match[1].replace(/[^0-9]/g, "");
        if (digits.length === 12 && digits[0] !== "0" && digits[0] !== "1") {
          return `${digits.slice(0, 4)} ${digits.slice(4, 8)} ${digits.slice(8, 12)}`;
        }
      }
    }
  }

  if (docType === "pan" || docType === "unknown") {
    const panPatterns = [
      /\b([A-Z]{5}[0-9]{4}[A-Z])\b/,
      /\b([A-Z]{4,6}[0-9]{3,5}[A-Z])\b/,
    ];

    for (const p of panPatterns) {
      const match = text.match(p);
      if (match && /^[A-Z]{5}[0-9]{4}[A-Z]$/.test(match[1])) {
        return match[1];
      }
    }
  }

  if (docType === "voter_id" || docType === "unknown") {
    const match = text.match(/\b([A-Z]{3}[0-9]{7})\b/);
    if (match) return match[1];
  }

  return null;
}

// ═══════════════════════════════════════════════
//  ADDRESS EXTRACTION
// ═══════════════════════════════════════════════

function extractAddress(raw, text) {
  const patterns = [
    /(?:Address|पता)\s*[:=\.]\s*([\s\S]{10,200}?)(?=\n\s*\n|\d{4}\s\d{4}\s\d{4}|$)/i,
    /(?:Address|पता)\s*[:=\.]\s*([A-Za-z0-9][A-Za-z0-9 ,.\-\/\n]{10,200})/i,
    /[SDWC]\/O\s*[:=]?\s*[A-Za-z ]+[,\n]\s*([A-Za-z0-9 ,.\-\/\n]{10,200})/i,
  ];

  for (const p of patterns) {
    const match = raw.match(p) || text.match(p);
    if (match) {
      let address = match[1]
        .replace(/\n/g, ", ")
        .replace(/\s+/g, " ")
        .replace(/,\s*,/g, ",")
        .replace(/,\s*$/, "")
        .trim();

      const cutoff = address.search(/\d{4}\s\d{4}\s\d{4}/);
      if (cutoff > 0) address = address.substring(0, cutoff).trim().replace(/,\s*$/, "");

      if (address.length >= 10) return address;
    }
  }

  return null;
}

// ═══════════════════════════════════════════════
//  GENDER & PINCODE
// ═══════════════════════════════════════════════

function extractGender(text) {
  if (/\bMALE\b/.test(text)) return "MALE";
  if (/\bFEMALE\b/.test(text)) return "FEMALE";
  if (/\bMale\b/.test(text)) return "MALE";
  if (/\bFemale\b/.test(text)) return "FEMALE";
  if (/पुरुष/.test(text)) return "MALE";
  if (/महिला|स्त्री/.test(text)) return "FEMALE";
  return null;
}

function extractPincode(text) {
  const matches = text.match(/\b([1-9]\d{5})\b/g);
  if (!matches) return null;

  const aadhaarDigits = (text.match(/\d{4}\s\d{4}\s\d{4}/g) || [])
    .join("").replace(/\s/g, "");

  for (const candidate of matches) {
    if (!aadhaarDigits.includes(candidate)) {
      const first = parseInt(candidate[0]);
      if (first >= 1 && first <= 9) return candidate;
    }
  }

  return matches[matches.length - 1];
}

// ═══════════════════════════════════════════════
//  PAN-SPECIFIC: FATHER'S NAME
// ═══════════════════════════════════════════════

function extractFatherName(raw, text) {
  const patterns = [
    /(?:Father|Father's?\s*Name)\s*[:=\.]\s*([A-Za-z][A-Za-z .'\-]{2,40})/i,
    /[SDWC]\/O\s*[:=]?\s*([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,3})/,
    /[SDWC]\/O\s*[:=]?\s*([A-Z]{2,}(?:\s+[A-Z]{2,}){0,3})/,
  ];

  for (const p of patterns) {
    const match = text.match(p) || raw.match(p);
    if (match) {
      const name = match[1].trim();
      if (looksLikeName(name)) return toTitleCase(cleanName(name));
    }
  }

  return null;
}

// ═══════════════════════════════════════════════
//  MAIN EXTRACTION
// ═══════════════════════════════════════════════

function extractFieldsFromText(ocrResult, documentId) {
  let bestText, mergedText, fieldMergedText;

  if (typeof ocrResult === "string") {
    bestText = ocrResult;
    mergedText = ocrResult;
    fieldMergedText = ocrResult;
  } else {
    bestText = ocrResult.text || "";
    mergedText = ocrResult.mergedText || bestText;
    fieldMergedText = ocrResult.fieldMergedText || mergedText;
  }

  const allText = [bestText, mergedText, fieldMergedText].join("\n---\n");

  const docType = detectDocumentType(allText);

  const normalizedBest   = bestText.replace(/\n/g, " ").replace(/\s+/g, " ").trim();
  const normalizedMerged = mergedText.replace(/\n/g, " ").replace(/\s+/g, " ").trim();
  const normalizedField  = fieldMergedText.replace(/\n/g, " ").replace(/\s+/g, " ").trim();

  const name =
    extractName(bestText, normalizedBest, docType) ||
    extractName(mergedText, normalizedMerged, docType) ||
    extractName(fieldMergedText, normalizedField, docType);

  const dob =
    extractDob(bestText, normalizedBest) ||
    extractDob(mergedText, normalizedMerged) ||
    extractDob(fieldMergedText, normalizedField);

  const gender =
    extractGender(normalizedBest) ||
    extractGender(normalizedMerged) ||
    extractGender(normalizedField);

  const idNumber =
    extractIdNumber(bestText, normalizedBest, docType) ||
    extractIdNumber(mergedText, normalizedMerged, docType) ||
    extractIdNumber(fieldMergedText, normalizedField, docType);

  const address =
    extractAddress(bestText, normalizedBest) ||
    extractAddress(mergedText, normalizedMerged) ||
    extractAddress(fieldMergedText, normalizedField);

  const pincode =
    extractPincode(normalizedBest) ||
    extractPincode(normalizedMerged) ||
    extractPincode(normalizedField);

  const fatherName =
    extractFatherName(bestText, normalizedBest) ||
    extractFatherName(mergedText, normalizedMerged) ||
    extractFatherName(fieldMergedText, normalizedField);

  const fields = {
    document_type: docType,
    name,
    dob,
    gender,
    id_number: idNumber,
    address,
    pincode,
  };

  if (fatherName) fields.father_name = fatherName;

  const extractedCount = Object.values(fields)
    .filter((v) => v !== null && v !== "unknown").length;

  console.log(
    `[Extract] Document: ${docType} | ` +
    `Fields: ${extractedCount}/${Object.keys(fields).length} | ` +
    `Name: ${name || "MISSING"} | DOB: ${dob || "MISSING"} | ` +
    `ID: ${idNumber || "MISSING"}`
  );

  if (documentId) {
    fs.mkdirSync("processed", { recursive: true });
    fs.writeFileSync(
      path.join("processed", `${documentId}_fields.json`),
      JSON.stringify(fields, null, 2)
    );
  }

  return fields;
}

module.exports = { extractFieldsFromText, detectDocumentType };