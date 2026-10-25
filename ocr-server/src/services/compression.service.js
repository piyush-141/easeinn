// src/services/compression.service.js
// Single-pass compression: estimate quality from size ratio, write once.
// Replaces the iterative 9-pass loop that did up to 9 disk writes.
const sharp = require("sharp");
const path  = require("path");
const fs    = require("fs");
const { formatBytes } = require("../utils/helpers");

const MAX_SIZE = (parseInt(process.env.COMPRESSED_MAX_SIZE_MB) || 1) * 1024 * 1024;

/**
 * Compress image to under MAX_SIZE in a single pass.
 *
 * Strategy:
 *  1. Compute ratio = inputBytes / MAX_SIZE
 *  2. Map ratio to (quality, maxWidth) in one step
 *  3. Encode to buffer — no temp files
 *  4. If the estimate overshoots (very rare), one hard fallback at 900px/q50
 *
 * NEVER go below 900px width or quality 50 — text becomes unreadable for OCR.
 */
async function compressImage(inputPath) {
  if (!fs.existsSync(inputPath)) {
    throw new Error("Image file not found: " + inputPath);
  }

  fs.mkdirSync("processed", { recursive: true });

  const filename    = path.basename(inputPath, path.extname(inputPath));
  const outputPath  = path.join("processed", `${filename}_compressed.jpg`);
  const beforeBytes = fs.statSync(inputPath).size;
  const meta        = await sharp(inputPath).metadata();

  console.log(`[Compress] Input: ${formatBytes(beforeBytes)} (${meta.width}x${meta.height})`);

  // ── Quality / width selection based on compression ratio needed ──────────
  const ratio = beforeBytes / MAX_SIZE;

  let quality, maxWidth;

  if (ratio <= 1.0) {
    // Already under limit — light re-encode, no resize
    quality  = 90;
    maxWidth = undefined;
  } else if (ratio <= 2.0) {
    quality  = 80;
    maxWidth = 1800;
  } else if (ratio <= 4.0) {
    quality  = 70;
    maxWidth = 1600;
  } else if (ratio <= 8.0) {
    quality  = 60;
    maxWidth = 1400;
  } else {
    quality  = 52;
    maxWidth = 1100;
  }

  // ── Single pass — encode to buffer, no temp files ────────────────────────
  let pipeline = sharp(inputPath).rotate();
  if (maxWidth) pipeline = pipeline.resize({ width: maxWidth, withoutEnlargement: true });
  pipeline = pipeline.jpeg({ quality, progressive: true });

  const buffer = await pipeline.toBuffer();

  // ── Safety fallback (rare: very high-resolution images) ─────────────────
  if (buffer.length > MAX_SIZE) {
    console.warn(`[Compress] Estimate missed (${formatBytes(buffer.length)}), using hard fallback`);
    const fallback = await sharp(inputPath)
      .rotate()
      .resize({ width: 900, withoutEnlargement: true })
      .jpeg({ quality: 50, progressive: true })
      .toBuffer();

    await fs.promises.writeFile(outputPath, fallback);
    console.log(`[Compress] Fallback: ${formatBytes(beforeBytes)} → ${formatBytes(fallback.length)}`);
    return outputPath;
  }

  await fs.promises.writeFile(outputPath, buffer);
  console.log(
    `[Compress] ${formatBytes(beforeBytes)} → ${formatBytes(buffer.length)}` +
    ` (q=${quality}${maxWidth ? `, w≤${maxWidth}` : ""})`
  );
  return outputPath;
}

module.exports = { compressImage };