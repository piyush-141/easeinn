// src/services/ocr.service.js
const Tesseract = require("tesseract.js");
const fs = require("fs");
const path = require("path");

/**
 * PSM modes and when each works best for Indian ID cards:
 * 
 *  PSM 3  = Auto → works for well-structured full-page scans
 *  PSM 4  = Single column → works for vertical text layouts
 *  PSM 6  = Single block → works for cropped regions
 *  PSM 7  = Single line → works for isolated number regions
 *  PSM 11 = Sparse text → BEST for ID cards (scattered fields)
 *  PSM 13 = Raw line → good for number-only regions
 */

const FULL_CARD_CONFIGS = [
  { name: "sparse",  psm: "11" },   // best for scattered ID card layout
  { name: "block",   psm: "6"  },   // single block of text
  { name: "auto",    psm: "3"  },   // fully automatic
  { name: "column",  psm: "4"  },   // single column
];

const REGION_CONFIGS = [
  { name: "block",   psm: "6"  },   // best for cropped regions
  { name: "sparse",  psm: "11" },
  { name: "line",    psm: "7"  },   // for single-line crops (number regions)
];

/**
 * Run single OCR pass
 */
async function runOcrPass(imagePath, config) {
  const worker = await Tesseract.createWorker("eng");

  await worker.setParameters({
    tessedit_pageseg_mode: config.psm,
    preserve_interword_spaces: "1",
    tessedit_char_blacklist: "©®™",  // block common noise chars
  });

  const { data } = await worker.recognize(imagePath);
  await worker.terminate();

  return {
    text: data.text,
    confidence: data.confidence,
    config: config.name,
    psm: config.psm,
  };
}

/**
 * Score OCR output quality — TUNED for Indian identity documents
 */
function scoreOcrOutput(text, variantName) {
  let score = 0;
  const normalized = text.replace(/\n/g, " ").replace(/\s+/g, " ").trim();

  // ── AADHAAR-SPECIFIC SCORING ──

  // Aadhaar number (12 digits in any grouping)
  if (/\d{4}\s\d{4}\s\d{4}/.test(normalized)) score += 35;
  else if (/\d{4}\s?\d{4}\s?\d{4}/.test(normalized)) score += 25;

  // "Aadhaar" or "UIDAI" keyword
  if (/aadhaar|aadhar|uidai|आधार/i.test(normalized)) score += 10;

  // VID number
  if (/VID\s*:\s*\d{4}\s\d{4}\s\d{4}\s\d{4}/i.test(normalized)) score += 5;

  // ── PAN-SPECIFIC SCORING ──

  // PAN number format
  if (/[A-Z]{5}[0-9]{4}[A-Z]/.test(normalized)) score += 35;

  // "Permanent Account Number" or "Income Tax"
  if (/permanent account|income tax/i.test(normalized)) score += 10;

  // ── COMMON FIELD SCORING ──

  // Date pattern (DD/MM/YYYY or DD-MM-YYYY)
  if (/\d{2}[\/\-]\d{2}[\/\-]\d{4}/.test(normalized)) score += 20;

  // DOB keyword near a date
  if (/(?:DOB|Date of Birth|Birth|जन्म)[^a-zA-Z]{0,10}\d{2}[\/\-]\d{2}[\/\-]\d{4}/i.test(normalized)) {
    score += 15;  // extra bonus: keyword + date together
  }

  // Name-related keywords
  if (/\bName\b|नाम/i.test(normalized)) score += 10;

  // Gender
  if (/\b(MALE|FEMALE)\b/i.test(normalized)) score += 15;
  if (/पुरुष|महिला/.test(normalized)) score += 10;

  // Relation indicators (S/O, D/O etc.)
  if (/[SDWC]\/O\b/i.test(normalized)) score += 10;

  // Address keywords
  if (/Address|पता/i.test(normalized)) score += 8;

  // Pincode
  if (/\b[1-9]\d{5}\b/.test(normalized)) score += 10;

  // ── CAPITALIZED ENGLISH WORDS (likely names) ──
  const capsWords = normalized.match(/\b[A-Z][a-z]{2,}\b/g);
  if (capsWords && capsWords.length >= 2) score += 12;

  // Full uppercase words (RAHUL SHARMA style)
  const allCapsWords = normalized.match(/\b[A-Z]{3,}\b/g);
  if (allCapsWords) {
    // Filter out common non-name uppercase words
    const nonNames = ["GOVERNMENT", "INDIA", "AADHAAR", "MALE", "FEMALE", "DOB",
      "ADDRESS", "INCOME", "TAX", "DEPARTMENT", "PERMANENT", "ACCOUNT", "NUMBER",
      "UIDAI", "ENROLMENT", "UNIQUE", "IDENTIFICATION", "AUTHORITY", "VID"];
    const namelike = allCapsWords.filter((w) => !nonNames.includes(w));
    if (namelike.length >= 1) score += 10;
  }

  // ── QUALITY PENALTIES ──

  // Very short output → probably failed
  if (normalized.length < 15) score -= 40;

  // Garbage ratio: if less than 35% alphanumeric → noise
  const alphaNum = normalized.replace(/[^a-zA-Z0-9]/g, "").length;
  const ratio = alphaNum / Math.max(normalized.length, 1);
  if (ratio < 0.3) score -= 25;
  if (ratio < 0.2) score -= 25;

  // Too much Hindi without useful Hindi keywords → noise for English OCR
  const devanagari = (normalized.match(/[\u0900-\u097F]/g) || []).length;
  const devRatio = devanagari / Math.max(normalized.length, 1);
  if (devRatio > 0.5) score -= 15;  // mostly Hindi, our extraction is English-focused

  // ── VARIANT BONUS ──
  // Region-specific variants should score higher if they contain expected content
  if (variantName && variantName.includes("number") && /\d{4}\s?\d{4}\s?\d{4}/.test(normalized)) {
    score += 15;  // number region that actually found a number
  }
  if (variantName && variantName.includes("middle") && capsWords && capsWords.length >= 1) {
    score += 10;  // middle section that found name-like content
  }

  return score;
}

/**
 * MAIN: Run multi-variant, multi-config OCR with smart result selection
 */
async function extractText(imageVariants, documentId) {
  if (typeof imageVariants === "string") {
    imageVariants = { single: imageVariants };
  }

  const variantCount = Object.keys(imageVariants).length;
  console.log(`[OCR] Starting multi-pass OCR across ${variantCount} variant(s)...`);

  const allResults = [];
  let completedPasses = 0;

  // Determine which configs to use per variant
  const regionVariants = [
    "aadhaar_number_region", "pan_number_region",
    "middle_section", "cropped_text_region"
  ];

  for (const [variantName, imagePath] of Object.entries(imageVariants)) {
    if (!fs.existsSync(imagePath)) {
      console.warn(`[OCR] Missing: ${variantName}`);
      continue;
    }

    // Use region configs for cropped variants, full configs for full images
    const isRegion = regionVariants.some((r) => variantName.includes(r));
    const configs = isRegion ? REGION_CONFIGS : FULL_CARD_CONFIGS;

    for (const config of configs) {
      try {
        const result = await runOcrPass(imagePath, config);
        const qualityScore = scoreOcrOutput(result.text, variantName);
        completedPasses++;

        allResults.push({
          variant: variantName,
          config: config.name,
          psm: config.psm,
          text: result.text,
          confidence: result.confidence,
          qualityScore,
        });

        if (qualityScore >= 60) {
          console.log(
            `[OCR] ★ ${variantName}/${config.name}(PSM${config.psm}) ` +
            `quality=${qualityScore} conf=${result.confidence.toFixed(0)}%`
          );
        }

        // Early exit if we get an excellent result from a full-card variant
        if (!isRegion && qualityScore >= 100 && result.confidence >= 75) {
          console.log(`[OCR] ★★ Excellent full-card result — continuing but this is likely best`);
        }
      } catch (err) {
        // silently skip
      }
    }
  }

  console.log(`[OCR] Completed ${completedPasses} passes, ${allResults.length} results`);

  if (allResults.length === 0) {
    throw new Error("OCR failed on all variants and configurations");
  }

  // Sort by quality then confidence
  allResults.sort((a, b) => {
    if (b.qualityScore !== a.qualityScore) return b.qualityScore - a.qualityScore;
    return b.confidence - a.confidence;
  });

  const best = allResults[0];
  console.log(
    `[OCR] BEST: variant="${best.variant}" config="${best.config}" ` +
    `PSM=${best.psm} quality=${best.qualityScore} conf=${best.confidence.toFixed(1)}%`
  );

  // Merge top results for maximum field coverage
  const mergedText = mergeOcrResults(allResults.slice(0, 8));

  // Build a FIELD-SPECIFIC merged text that combines the best source for each field type
  const fieldMergedText = buildFieldMergedText(allResults);

  // Save everything
  if (documentId) {
    fs.mkdirSync("processed", { recursive: true });

    fs.writeFileSync(
      path.join("processed", `${documentId}_ocr_best.txt`),
      `Variant: ${best.variant}\nConfig: ${best.config} (PSM ${best.psm})\n` +
      `Quality: ${best.qualityScore}\nConfidence: ${best.confidence.toFixed(1)}%\n` +
      `---\n\n${best.text}`
    );

    fs.writeFileSync(
      path.join("processed", `${documentId}_ocr_merged.txt`),
      mergedText
    );

    fs.writeFileSync(
      path.join("processed", `${documentId}_ocr_field_merged.txt`),
      fieldMergedText
    );

    const summary = allResults.slice(0, 15).map((r) => ({
      variant: r.variant,
      config: r.config,
      psm: r.psm,
      quality: r.qualityScore,
      confidence: r.confidence.toFixed(1),
      length: r.text.length,
      preview: r.text.substring(0, 80).replace(/\n/g, "⏎"),
    }));

    fs.writeFileSync(
      path.join("processed", `${documentId}_ocr_all.json`),
      JSON.stringify(summary, null, 2)
    );
  }

  return {
    text: best.text,
    mergedText,
    fieldMergedText,
    confidence: best.confidence,
    bestVariant: best.variant,
    bestConfig: best.config,
    qualityScore: best.qualityScore,
    totalAttempts: completedPasses,
    topResults: allResults.slice(0, 5).map((r) => ({
      variant: r.variant,
      config: r.config,
      quality: r.qualityScore,
    })),
  };
}

/**
 * Merge unique lines from multiple OCR results
 */
function mergeOcrResults(results) {
  if (results.length === 0) return "";
  if (results.length === 1) return results[0].text;

  let merged = results[0].text;
  const existingLines = new Set(
    merged.split("\n").map((l) => l.trim().toLowerCase()).filter(Boolean)
  );

  for (let i = 1; i < results.length; i++) {
    for (const line of results[i].text.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      if (existingLines.has(trimmed.toLowerCase())) continue;

      const isUseful =
        /\d{4}\s?\d{4}\s?\d{4}/.test(trimmed) ||
        /[A-Z]{5}[0-9]{4}[A-Z]/.test(trimmed) ||
        /\d{2}[\/\-]\d{2}[\/\-]\d{4}/.test(trimmed) ||
        /DOB|Name|Address|MALE|FEMALE/i.test(trimmed) ||
        /[SDWC]\/O/i.test(trimmed) ||
        /\b[1-9]\d{5}\b/.test(trimmed) ||
        /\b[A-Z][a-z]{2,}(?:\s+[A-Z][a-z]{2,})+\b/.test(trimmed);

      if (isUseful) {
        merged += "\n" + trimmed;
        existingLines.add(trimmed.toLowerCase());
      }
    }
  }

  return merged;
}

/**
 * Build field-specific merged text.
 * For each field type, find the OCR result that best contains that field.
 */
function buildFieldMergedText(allResults) {
  const fieldPatterns = {
    aadhaar_number: /\d{4}\s?\d{4}\s?\d{4}/,
    pan_number: /[A-Z]{5}[0-9]{4}[A-Z]/,
    date: /\d{2}[\/\-]\d{2}[\/\-]\d{4}/,
    name_indicator: /\b[A-Z][a-z]{2,}(?:\s+[A-Z][a-z]{2,})+\b/,
    gender: /\b(MALE|FEMALE)\b/i,
    address: /Address|पता/i,
    relation: /[SDWC]\/O/i,
  };

  let merged = "";
  const addedLines = new Set();

  for (const [fieldName, pattern] of Object.entries(fieldPatterns)) {
    // Find the result with the highest quality that contains this field
    for (const result of allResults) {
      const lines = result.text.split("\n");
      for (const line of lines) {
        if (pattern.test(line) && !addedLines.has(line.trim().toLowerCase())) {
          merged += line.trim() + "\n";
          addedLines.add(line.trim().toLowerCase());
        }
      }
    }
  }

  return merged;
}

module.exports = { extractText, scoreOcrOutput };