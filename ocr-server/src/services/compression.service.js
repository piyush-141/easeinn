// src/services/compression.service.js
const sharp = require("sharp");
const path = require("path");
const fs = require("fs");
const { formatBytes } = require("../utils/helpers");

const MAX_SIZE = (parseInt(process.env.COMPRESSED_MAX_SIZE_MB) || 1) * 1024 * 1024;

/**
 * Compress image to under MAX_SIZE while maintaining OCR readability.
 *
 * Strategy:
 *  - If image already under limit → keep JPEG with high quality
 *  - If image over limit → progressive resize + quality reduction
 *  - NEVER go below width 1000px (text becomes unreadable)
 *  - NEVER go below quality 50 (artifacts kill OCR)
 */

async function compressImage(inputPath) {
  if (!fs.existsSync(inputPath)) {
    throw new Error("Image file not found: " + inputPath);
  }

  fs.mkdirSync("processed", { recursive: true });

  const filename = path.basename(inputPath, path.extname(inputPath));
  const beforeBytes = fs.statSync(inputPath).size;
  const metadata = await sharp(inputPath).metadata();

  console.log(
    `[Compress] Input: ${formatBytes(beforeBytes)} (${metadata.width}x${metadata.height})`
  );

  // If already under limit → normalize but KEEP JPEG
  if (beforeBytes <= MAX_SIZE) {
    const outputPath = path.join("processed", `${filename}_compressed.jpg`);

    await sharp(inputPath)
      .rotate() // apply EXIF rotation
      .jpeg({ quality: 90, progressive: true })
      .toFile(outputPath);

    console.log(
      `[Compress] Already under ${formatBytes(MAX_SIZE)}, saved as optimized JPEG`
    );

    return outputPath;
  }

  // Iterative compression
  const outputPath = path.join("processed", `${filename}_compressed.jpg`);

  const attempts = [
    { width: 2000, quality: 85 },
    { width: 1800, quality: 80 },
    { width: 1600, quality: 75 },
    { width: 1500, quality: 70 },
    { width: 1400, quality: 65 },
    { width: 1200, quality: 60 },
    { width: 1100, quality: 55 },
    { width: 1000, quality: 50 }, // minimum acceptable for OCR
  ];

  for (const attempt of attempts) {
    const tempPath = outputPath + ".tmp";

    await sharp(inputPath)
      .rotate()
      .resize({ width: attempt.width, withoutEnlargement: true })
      .jpeg({ quality: attempt.quality, progressive: true })
      .toFile(tempPath);

    const afterBytes = fs.statSync(tempPath).size;

    if (afterBytes <= MAX_SIZE) {
      fs.renameSync(tempPath, outputPath);

      console.log(
        `[Compress] ${formatBytes(beforeBytes)} → ${formatBytes(afterBytes)} ` +
          `(width=${attempt.width}, q=${attempt.quality})`
      );

      return outputPath;
    }

    fs.unlinkSync(tempPath);
  }

  // Last resort
  await sharp(inputPath)
    .rotate()
    .resize({ width: 900, withoutEnlargement: true })
    .jpeg({ quality: 45, progressive: true })
    .toFile(outputPath);

  const afterBytes = fs.statSync(outputPath).size;

  console.log(
    `[Compress] Aggressive: ${formatBytes(beforeBytes)} → ${formatBytes(afterBytes)}`
  );

  return outputPath;
}

module.exports = { compressImage };