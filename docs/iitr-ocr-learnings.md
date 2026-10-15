# IITR DigiPramaan — OCR & Document Verification Learnings

> **Source:** [github.com/Abhist17/iitr](https://github.com/Abhist17/iitr)
> **Purpose:** Understand exactly *how* this project achieves accurate OCR on Indian identity documents (Aadhaar, PAN, etc.) so we can reuse the best techniques in EaseInn's OCR pipeline.

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [The 4-Step Pipeline](#2-the-4-step-pipeline)
3. [Image Preprocessing — The Real Secret Sauce](#3-image-preprocessing--the-real-secret-sauce)
4. [Multi-Pass OCR Strategy](#4-multi-pass-ocr-strategy)
5. [Quality Scoring System](#5-quality-scoring-system)
6. [OCR Result Merging](#6-ocr-result-merging)
7. [Regex-Based Field Extraction](#7-regex-based-field-extraction)
8. [Vision Model (Ollama) as a Second Brain](#8-vision-model-ollama-as-a-second-brain)
9. [Smart Merge — OCR + Vision](#9-smart-merge--ocr--vision)
10. [Verification & Fuzzy Matching](#10-verification--fuzzy-matching)
11. [Compression Strategy](#11-compression-strategy)
12. [Key Takeaways for EaseInn](#12-key-takeaways-for-easeinn)
13. [Tech Stack Summary](#13-tech-stack-summary)

---

## 1. High-Level Architecture

The project is a **Node.js + Express REST API** that takes in Indian government ID documents (images or PDFs) and returns:

- Optimized/compressed images
- Structured extracted data (name, DOB, ID number, address, etc.)
- Verification report with confidence scores

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  /api/upload │ ──▶ │ /api/process │ ──▶ │ /api/extract  │ ──▶ │  /api/verify  │
│  (file + form│     │ (preprocess  │     │ (OCR fields + │     │ (compare vs   │
│   data)      │     │  + OCR)      │     │  vision merge)│     │  form data)   │
└─────────────┘     └─────────────┘     └──────────────┘     └──────────────┘
```

Each step saves intermediate artifacts to disk (`processed/` folder) so steps can be run independently.

---

## 2. The 4-Step Pipeline

| Step | Endpoint | What it does |
|------|----------|-------------|
| **1. Upload** | `POST /api/upload` | Accepts image via multer, compresses it via Sharp, saves metadata + form data to disk |
| **2. Process** | `POST /api/process` | Generates **12 preprocessed image variants**, runs **multi-pass OCR** (Tesseract) across all variants with multiple PSM modes |
| **3. Extract** | `POST /api/extract` | Runs regex-based field extraction on OCR text + optionally calls a vision model (Ollama/LLaVA). Merges both results intelligently |
| **4. Verify** | `POST /api/verify` | Compares extracted fields against user-submitted form data using fuzzy matching (Levenshtein distance) |

> **Key insight:** Steps are decoupled. Each saves its output as JSON to disk. The next step reads it. This makes debugging easy — you can inspect every intermediate result.

---

## 3. Image Preprocessing — The Real Secret Sauce

> **File:** `src/services/preprocessing.service.js`

This is where most of the OCR accuracy comes from. Instead of sending one image to Tesseract, the system generates **up to 12 different image variants**, each optimized for different document types and conditions.

### 3.1 Smart Cropping (Step 1)

```
On most Indian ID cards, the PHOTO is on the LEFT side.
This photo region generates OCR noise (face features misread as text).

Solution: Crop out the left 32% of landscape cards to remove the photo.
```

- **Landscape cards:** Remove left 32% (photo region), keep right 68% (text region)
- **Portrait cards:** Remove left 30%
- Applied transforms: `grayscale → normalize → sharpen(sigma=1.5)`

### 3.2 Aadhaar-Specific Variants (Step 2)

| Variant | Technique | Why it works |
|---------|-----------|-------------|
| **Blue channel extraction** | `extractChannel("blue")` → `negate()` → `normalize()` | Aadhaar has an **orange/saffron header**. Orange = high R, medium G, low B. Extracting the blue channel makes the orange disappear while keeping black text visible |
| **Green channel** | `extractChannel("green")` → `normalize()` | Sometimes better than blue for colored backgrounds |
| **Number region crop** | Crop bottom 45% → aggressive contrast (`linear(2.0, -80)`) → `threshold(128)` | Aadhaar number is typically at the bottom of the card. Isolating it + high contrast = near-perfect number OCR |
| **Middle section crop** | Crop middle 50% (offset by 15% from top, excluding left 30% on landscape) | Name, DOB, and gender are in the middle section of the card |

### 3.3 PAN-Specific Variants (Step 3)

| Variant | Technique | Why |
|---------|-----------|-----|
| **Inverted** | `grayscale → threshold(100) → negate()` | PAN has dark blue background in header. White text on dark bg needs inversion |
| **Number region** | Crop upper-middle area (35% from top, 20% height) → high contrast → threshold → **2.5x upscale** | PAN number (ABCDE1234F) is small — upscaling the crop dramatically improves OCR |

### 3.4 Universal Variants (Step 4)

| Variant | Settings | Best for |
|---------|----------|----------|
| **Standard grayscale** | `grayscale → normalize → sharpen(1.5)` | Baseline for clean scans |
| **High contrast** | `linear(1.8, -60) → sharpen(2.0)` | Faded/old documents |
| **Binary threshold** | `threshold(140)` | Documents with uniform backgrounds |
| **Upscaled** | `resize(width × scale, lanczos3)` — only if image < 1200px | Cheap phone photos |
| **Mild** | Just `grayscale → sharpen(0.8)` | High-quality scans that don't need aggressive processing |
| **Color enhanced** | `normalize → sharpen(2.0) → modulate(brightness: 1.15, saturation: 0.2)` | Colored text that gets lost in grayscale |

> **Key pattern: Every variant uses `.rotate()` first.** This applies EXIF rotation — critical for phone photos that store orientation as metadata rather than actually rotating pixels.

---

## 4. Multi-Pass OCR Strategy

> **File:** `src/services/ocr.service.js`

### 4.1 PSM Modes

Tesseract has different **Page Segmentation Modes (PSM)** that dramatically affect accuracy:

| PSM | Mode | Best for |
|-----|------|----------|
| **3** | Fully automatic | Well-structured scans |
| **4** | Single column | Vertical text layouts |
| **6** | Single text block | Cropped regions |
| **7** | Single line | Isolated number regions |
| **11** | Sparse text | **Best for ID cards** — scattered fields, non-linear layout |
| **13** | Raw line | Number-only regions |

### 4.2 Two Config Sets

```javascript
// For full card images — try all 4 modes
FULL_CARD_CONFIGS = [PSM 11, PSM 6, PSM 3, PSM 4]

// For cropped regions — only 3 relevant modes
REGION_CONFIGS = [PSM 6, PSM 11, PSM 7]
```

### 4.3 The Loop

For each of the ~12 image variants × each PSM config = **potentially 40-50 OCR passes**.

```
For each variant (12 variants):
    Determine if it's a "region" crop or full card
    For each PSM config (3-4 configs):
        Run Tesseract OCR
        Score the output quality
        Store the result
```

### 4.4 Tesseract Parameters

```javascript
{
  tessedit_pageseg_mode: config.psm,
  preserve_interword_spaces: "1",        // Keep spaces between words
  tessedit_char_blacklist: "©®™",        // Block common noise characters
}
```

- Language: `eng` (English)
- The repo also mentions `eng+hin` for Hindi/Devanagari support

---

## 5. Quality Scoring System

> **This is the core innovation** — instead of blindly trusting Tesseract's confidence %, the system scores OCR output based on whether it contains **expected patterns** for Indian identity documents.

### Scoring Rules (points system):

#### Aadhaar-Specific
| Pattern | Points |
|---------|--------|
| Aadhaar number `XXXX XXXX XXXX` (proper spacing) | **+35** |
| Aadhaar number (no spacing) | +25 |
| Keywords: "aadhaar", "aadhar", "uidai", "आधार" | +10 |
| VID number | +5 |

#### PAN-Specific
| Pattern | Points |
|---------|--------|
| PAN format `ABCDE1234F` | **+35** |
| Keywords: "permanent account", "income tax" | +10 |

#### Common Fields
| Pattern | Points |
|---------|--------|
| Date `DD/MM/YYYY` | +20 |
| DOB keyword near a date | +15 (bonus) |
| "Name" keyword | +10 |
| Gender `MALE`/`FEMALE` | +15 |
| Hindi gender पुरुष/महिला | +10 |
| Relation indicator `S/O`, `D/O`, etc. | +10 |
| "Address" keyword | +8 |
| Pincode (6-digit) | +10 |
| Capitalized name-like words (≥2) | +12 |
| ALL CAPS name-like words | +10 |

#### Quality Penalties
| Condition | Penalty |
|-----------|---------|
| Output < 15 characters | **-40** |
| Alphanumeric ratio < 30% (garbage) | -25 |
| Alphanumeric ratio < 20% | -25 more |
| Too much Devanagari (>50%) | -15 |

#### Region-Specific Bonuses
| Condition | Bonus |
|-----------|-------|
| Number-region variant that found a 12-digit number | +15 |
| Middle-section variant that found capitalized words | +10 |

### Result Selection

```javascript
// Sort by quality score first, then Tesseract confidence
allResults.sort((a, b) => {
    if (b.qualityScore !== a.qualityScore) return b.qualityScore - a.qualityScore;
    return b.confidence - a.confidence;
});
```

---

## 6. OCR Result Merging

The system doesn't just pick the single best result — it **merges the top 8 results** to maximize field coverage.

### 6.1 Line-Level Merge

Starting with the best result's text, it scans lower-ranked results for **new useful lines** that weren't already captured:

A line is considered "useful" if it matches any of:
- Aadhaar number pattern
- PAN number pattern
- Date pattern
- Keywords (DOB, Name, Address, MALE, FEMALE)
- Relation indicators (S/O, etc.)
- Pincode
- Multi-word capitalized names

### 6.2 Field-Specific Merge

For each field type (aadhaar_number, pan_number, date, name, gender, address, relation), the system:
1. Searches **all** OCR results (already sorted by quality)
2. Finds the lines that match the field's regex pattern
3. Adds unique matching lines to a field-specific merged text

This produces **three text outputs**:
- `bestText` — single best OCR result
- `mergedText` — line-level merge of top 8
- `fieldMergedText` — field-specific merge from all results

Field extraction runs on **all three** and takes the first successful extraction.

---

## 7. Regex-Based Field Extraction

> **File:** `src/services/extraction.service.js`

### 7.1 Document Type Detection (Scoring-Based)

```javascript
// Not just keyword matching — uses a SCORING system
let aadhaarScore = 0, panScore = 0;

// Each keyword/pattern adds to the score
if (/aadhaar|aadhar|आधार/.test(t)) aadhaarScore += 3;
if (/\d{4}\s\d{4}\s\d{4}/.test(text)) aadhaarScore += 4;
if (/[A-Z]{5}[0-9]{4}[A-Z]/.test(text)) panScore += 4;

// Highest score wins (with minimum threshold of 3)
```

### 7.2 Name Extraction — 6 Strategies

This is the hardest part. The system tries **6 different strategies** in order:

1. **Explicit label:** `Name: Rahul Kumar` or `नाम: ...`
2. **Relation line:** `Rahul Kumar S/O Suresh Kumar`
3. **Contextual position:** Find DOB or gender line → look 1-4 lines above
4. **Capitalized lines:** Find lines matching `Title Case` or `ALL CAPS` patterns
5. **All-caps filtering:** Filter out known non-name words (GOVERNMENT, INDIA, etc.)
6. **Loose patterns:** Look for names after Hindi text or document headers

#### Garbled Text Detection

```javascript
function isGarbled(line) {
    const letters = (line.match(/[A-Za-z]/g) || []).length;
    const noise = (line.match(/[@=\-_|\\/*+~`"'<>]/g) || []).length;
    if (noise / letters > 0.3) return true;    // >30% noise = garbled
    
    // Words > 15 chars are suspicious ("Govemmentiofiidiammess")
    for (const w of words) {
        if (w.length > 15) return true;
    }
}
```

#### Name Blacklist
Common false positives filtered out: GOVERNMENT, INDIA, AADHAAR, UIDAI, MALE, FEMALE, DOB, ADDRESS, INCOME, TAX, etc.

### 7.3 DOB Extraction

Multiple patterns tried:
```
DOB: 14/02/1998
D.O.B: 14-02-1998
Date of Birth: 14.02.1998
जन्म तिथि: 14/02/1998
Year of Birth: 1998 → converted to 01/01/1998
```

All dates normalized to `DD/MM/YYYY`. Validation: day 1-31, month 1-12, year 1920-2024.

### 7.4 ID Number Extraction

**Aadhaar:** Looks for 12 digits in any grouping, validates first digit is not 0 or 1, reformats to `XXXX XXXX XXXX`.

**PAN:** Strict format `[A-Z]{5}[0-9]{4}[A-Z]`.

**Voter ID:** `[A-Z]{3}[0-9]{7}`.

### 7.5 Pincode Extraction

Finds 6-digit numbers starting with 1-9, but **excludes digits that are part of an Aadhaar number** to avoid false positives.

### 7.6 Triple-Source Extraction

Every field is extracted from **all three text sources** (best, merged, field-merged):

```javascript
const name =
    extractName(bestText, ...) ||
    extractName(mergedText, ...) ||
    extractName(fieldMergedText, ...);
```

---

## 8. Vision Model (Ollama) as a Second Brain

> **File:** `src/services/ollama-vision.service.js`

When available, the system sends the image directly to a **vision LLM** (LLaVA or Qwen via Ollama) with a structured prompt:

```
You are a document data extraction system. Analyze this identity document image carefully.
Return ONLY a valid JSON object with these keys:
{
  "document_type": "aadhaar or pan or ...",
  "name": "full name in English or null",
  "dob": "DD/MM/YYYY format or null",
  ...
}
```

Key settings:
- `temperature: 0.1` (near-deterministic output)
- Image sent as base64
- Response parsed with fallback JSON extraction (`/\{[\s\S]*\}/`)
- String `"null"` values converted to actual `null`

**Both compressed and original images are tried** — the result with more non-null fields wins.

---

## 9. Smart Merge — OCR + Vision

When both OCR and vision results are available, they're merged with field-specific logic:

| Field | Merge Rule |
|-------|-----------|
| `id_number` | Prefer the version with proper formatting (spaces/dashes) |
| `address` | Prefer the longer version |
| Everything else | **Prefer vision model**, fall back to OCR |

```javascript
if (vExists && oExists) {
    if (key === "id_number") {
        merged[key] = v.includes(" ") ? v : (o.includes(" ") ? o : v);
    } else if (key === "address") {
        merged[key] = v.length >= o.length ? v : o;
    } else {
        merged[key] = v; // prefer vision
    }
} else if (vExists) { merged[key] = v; }
  else if (oExists) { merged[key] = o; }
  else { merged[key] = null; }
```

---

## 10. Verification & Fuzzy Matching

> **File:** `src/services/verification.service.js` and `src/utils/helpers.js`

### Field Comparison

| Field | Method | Match Threshold |
|-------|--------|----------------|
| `name` | Levenshtein similarity | >= 0.75 (75%) |
| `dob` | Exact normalized date match | 1.0 (100%) |
| `id_number` | Normalized digits comparison | >= 0.95 (95%) |
| `address` | Levenshtein similarity | >= 0.50 (50%) |
| `gender` | Exact normalized string match | 1.0 (100%) |

### Weighted Confidence Score

```javascript
const fieldWeights = {
    name: 3,        // high importance
    dob: 2,
    id_number: 4,   // highest importance
    address: 1,     // lowest — addresses are messy
    gender: 1,
};
```

### Fuzzy Matching (Levenshtein Distance)

```javascript
function similarityScore(str1, str2) {
    // Normalize: lowercase, trim, remove spaces/punctuation
    // Check containment (one contains other -> 0.9)
    // Otherwise: 1 - (levenshtein_distance / max_length)
}
```

---

## 11. Compression Strategy

> **File:** `src/services/compression.service.js`

### Iterative Compression

If the image is over the size limit (default 1MB), try progressively aggressive settings:

| Attempt | Width | Quality | Notes |
|---------|-------|---------|-------|
| 1 | 2000px | 85% | |
| 2 | 1800px | 80% | |
| 3 | 1600px | 75% | |
| 4 | 1500px | 70% | |
| 5 | 1400px | 65% | |
| 6 | 1200px | 60% | |
| 7 | 1100px | 55% | |
| 8 | 1000px | 50% | **Minimum for OCR** |
| Last resort | 900px | 45% | Aggressive |

### Hard Rules
- **Never below 1000px width** — text becomes unreadable for OCR
- **Never below quality 50** — JPEG artifacts destroy OCR accuracy
- Always use `progressive: true` for smaller file size
- Always call `.rotate()` to fix EXIF orientation

---

## 12. Key Takeaways for EaseInn

### What Makes This Accurate

1. **Multi-variant preprocessing** — Don't send one image to OCR. Generate 10-12 differently processed versions. Channel extraction (blue/green) kills colored backgrounds.

2. **Multi-pass OCR with different PSM modes** — PSM 11 (sparse text) is best for ID cards. Running 3-4 PSM modes per variant catches different text layouts.

3. **Quality scoring over confidence** — Tesseract's built-in confidence % is unreliable. Scoring based on **expected patterns** (Aadhaar number regex, PAN format, date patterns) is far more accurate.

4. **Result merging** — No single OCR pass gets everything. Merging the best lines from multiple passes gives near-complete coverage.

5. **Region-specific crops** — Cropping the photo region out, isolating the number area, focusing on the middle section — each helps OCR focus on what matters.

6. **Vision model as backup** — When regex-based extraction fails, a vision LLM can read the document directly. Merging both gives the best results.

### What We Should Reuse in EaseInn

| Technique | Relevance | Priority |
|-----------|-----------|----------|
| Multi-variant preprocessing (Sharp) | **High** — works for any document type | Must have |
| Photo region cropping | **High** — hotel documents may have logos/stamps | Must have |
| PSM 11 for scattered text | **High** — most documents aren't clean paragraphs | Must have |
| Quality scoring with domain-specific patterns | **High** — we need our own patterns for hotel documents | Must have |
| Result merging (line-level + field-level) | **High** — dramatically improves coverage | Should have |
| Blue/green channel extraction | **Medium** — useful if documents have colored backgrounds | Should have |
| Binary thresholding variants | **Medium** — helps with poor lighting | Should have |
| Vision model merge | **Medium** — great accuracy boost but adds latency | Nice to have |
| Iterative compression with min bounds | **High** — prevents quality loss | Must have |
| Levenshtein fuzzy matching for verification | **Medium** — depends on our verification needs | Should have |

### Patterns to Adapt for Hotel Documents

For EaseInn, we'd need to create our own:
- **Quality scoring patterns:** Look for check-in dates, room numbers, guest names, hotel names, booking IDs
- **Preprocessing variants:** May need different crops based on hotel document layouts
- **Field extraction regexes:** Hotel-specific formats for dates, prices, room numbers

---

## 13. Tech Stack Summary

| Component | Technology | Role |
|-----------|-----------|------|
| Server | Express.js | HTTP API |
| Image Processing | **Sharp** (libvips) | Compression, preprocessing, channel extraction |
| OCR | **Tesseract.js** | Text recognition (eng + hin) |
| Vision AI | **Ollama** (LLaVA/Qwen) | Secondary extraction via vision model |
| File Upload | Multer | Multipart handling |
| Fuzzy Matching | Custom Levenshtein | Field verification |

### Dependencies

```
express, sharp, tesseract.js, multer, node-fetch, dotenv, cors, uuid
Optional: Ollama (local) for vision model
```

---

> **Bottom line:** The accuracy comes from a **quantity-over-quality approach** at the OCR level — generate many variants, run many passes, score them intelligently, merge the best — combined with **domain-specific pattern matching** that knows exactly what Indian ID documents look like.
