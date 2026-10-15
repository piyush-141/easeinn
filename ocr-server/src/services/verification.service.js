// src/services/verification.service.js
const {
  normalizeString,
  similarityScore,
  normalizeDate,
  normalizeAadhaar,
} = require("../utils/helpers");

/**
 * Compare extracted document data against user-submitted form data.
 * Returns a detailed verification report with match status and confidence.
 */
function verifyDocument(extractedData, formData) {
  const results = {
    field_results: {},
    matched_fields: [],
    mismatched_fields: [],
    unverifiable_fields: [],
    confidence_score: 0,
  };

  // Define which fields to compare and how
  const fieldComparators = [
    {
      key: "name",
      extractedKey: "name",
      formKey: "name",
      comparator: (a, b) => similarityScore(a, b),
      threshold: 0.75,
    },
    {
      key: "dob",
      extractedKey: "dob",
      formKey: "dob",
      comparator: (a, b) => {
        const na = normalizeDate(a);
        const nb = normalizeDate(b);
        return na === nb ? 1 : 0;
      },
      threshold: 1.0,
    },
    {
      key: "id_number",
      extractedKey: "id_number",
      formKey: "id_number",
      comparator: (a, b) => {
        const na = normalizeAadhaar(a);
        const nb = normalizeAadhaar(b);
        if (!na || !nb) return 0;
        return na === nb ? 1 : similarityScore(na, nb);
      },
      threshold: 0.95,
    },
    {
      key: "address",
      extractedKey: "address",
      formKey: "address",
      comparator: (a, b) => similarityScore(a, b),
      threshold: 0.5,
    },
    {
      key: "gender",
      extractedKey: "gender",
      formKey: "gender",
      comparator: (a, b) => {
        return normalizeString(a) === normalizeString(b) ? 1 : 0;
      },
      threshold: 1.0,
    },
  ];

  let totalWeight = 0;
  let weightedScore = 0;

  // Weights for confidence calculation
  const fieldWeights = {
    name: 3,
    dob: 2,
    id_number: 4,
    address: 1,
    gender: 1,
  };

  for (const field of fieldComparators) {
    const extractedValue = extractedData[field.extractedKey];
    const formValue = formData[field.formKey];

    // If neither side has data, skip
    if (!extractedValue && !formValue) {
      continue;
    }

    // If form doesn't have this field, skip (can't verify)
    if (!formValue) {
      results.unverifiable_fields.push(field.key);
      results.field_results[field.key] = {
        extracted: extractedValue,
        submitted: null,
        status: "not_submitted",
        score: null,
      };
      continue;
    }

    // If extraction missed this field
    if (!extractedValue) {
      results.unverifiable_fields.push(field.key);
      results.field_results[field.key] = {
        extracted: null,
        submitted: formValue,
        status: "not_extracted",
        score: 0,
      };
      totalWeight += fieldWeights[field.key] || 1;
      continue;
    }

    // Compare
    const score = field.comparator(extractedValue, formValue);
    const isMatch = score >= field.threshold;
    const weight = fieldWeights[field.key] || 1;

    results.field_results[field.key] = {
      extracted: extractedValue,
      submitted: formValue,
      match: isMatch,
      similarity_score: Math.round(score * 100) / 100,
    };

    if (isMatch) {
      results.matched_fields.push(field.key);
    } else {
      results.mismatched_fields.push(field.key);
    }

    totalWeight += weight;
    weightedScore += score * weight;
  }

  // Calculate overall confidence
  results.confidence_score =
    totalWeight > 0
      ? Math.round((weightedScore / totalWeight) * 100) / 100
      : 0;

  results.is_verified =
    results.mismatched_fields.length === 0 &&
    results.matched_fields.length > 0;

  return results;
}

module.exports = { verifyDocument };