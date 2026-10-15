// src/services/preprocessing.service.js
const sharp = require("sharp");
const path = require("path");
const fs = require("fs");

/**
 * MASTER PREPROCESSING FUNCTION
 * Generates document-type-specific variants optimized for Indian ID cards.
 * 
 * Strategy:
 *  1. First do a quick analysis of the image (dimensions, colors)
 *  2. Generate GENERIC variants that work for any document
 *  3. Generate AADHAAR-SPECIFIC variants (crop photo area, handle orange header)
 *  4. Generate PAN-SPECIFIC variants (handle dark background, signature area)
 *  5. Return all variants for multi-pass OCR
 */
async function preprocessImage(inputPath) {
  if (!fs.existsSync(inputPath)) {
    throw new Error("Image file not found: " + inputPath);
  }

  fs.mkdirSync("processed", { recursive: true });

  const filename = path.basename(inputPath, path.extname(inputPath));
  const basePath = path.join("processed", filename);

  // Get image metadata for smart processing
  const metadata = await sharp(inputPath).metadata();
  const { width, height } = metadata;

  console.log(`[Preprocess] Input: ${width}x${height}, ${metadata.format}`);

  // Detect if landscape (typical for ID cards) or portrait
  const isLandscape = width > height;
  console.log(`[Preprocess] Orientation: ${isLandscape ? "landscape" : "portrait"}`);

  const variants = {};

  // ════════════════════════════════════════════
  //  STEP 1: SMART CROP — Remove photo region
  //  On most Indian IDs, the photo is on the LEFT
  //  Cropping it out prevents OCR noise from face area
  // ════════════════════════════════════════════

  try {
    const out = `${basePath}_cropped_right.png`;

    // On landscape ID cards, photo is roughly left 30-35%
    // On portrait cards, photo might be top 30%
    let cropRegion;

    if (isLandscape) {
      // Crop out left 35% (photo region) — keep right 65% (text region)
      const cropLeft = Math.floor(width * 0.32);
      cropRegion = {
        left: cropLeft,
        top: 0,
        width: width - cropLeft,
        height: height,
      };
    } else {
      // Portrait: crop out top 25% or left 35%
      const cropLeft = Math.floor(width * 0.30);
      cropRegion = {
        left: cropLeft,
        top: 0,
        width: width - cropLeft,
        height: height,
      };
    }

    await sharp(inputPath)
      .rotate()
      .extract(cropRegion)
      .grayscale()
      .normalize()
      .sharpen({ sigma: 1.5 })
      .png()
      .toFile(out);

    variants.cropped_text_region = out;
    console.log("[Preprocess] ✓ Cropped text region (photo removed)");
  } catch (e) {
    console.warn("[Preprocess] ✗ Crop failed:", e.message);
  }

  // ════════════════════════════════════════════
  //  STEP 2: AADHAAR-OPTIMIZED VARIANTS
  // ════════════════════════════════════════════

  // Variant A: Remove orange/saffron tones (Aadhaar header)
  // Orange in RGB has high R, medium G, low B
  // Converting to grayscale with channel manipulation helps
  try {
    const out = `${basePath}_aadhaar_decolor.png`;

    await sharp(inputPath)
      .rotate()
      // Extract only the blue channel — orange becomes dark, black text stays visible
      // This kills the orange header while preserving dark text
      .extractChannel("blue")
      .normalize()
      .negate()           // invert so text is black on white
      .normalize()        // re-normalize after invert
      .sharpen({ sigma: 2.0 })
      .png()
      .toFile(out);

    variants.aadhaar_blue_channel = out;
    console.log("[Preprocess] ✓ Aadhaar blue channel extraction");
  } catch (e) {
    console.warn("[Preprocess] ✗ Blue channel failed:", e.message);
  }

  // Variant B: Green channel — sometimes better for colored backgrounds
  try {
    const out = `${basePath}_green_channel.png`;

    await sharp(inputPath)
      .rotate()
      .extractChannel("green")
      .normalize()
      .sharpen({ sigma: 1.5 })
      .png()
      .toFile(out);

    variants.green_channel = out;
    console.log("[Preprocess] ✓ Green channel extraction");
  } catch (e) {
    console.warn("[Preprocess] ✗ Green channel failed:", e.message);
  }

  // Variant C: Aggressive threshold on cropped region
  // Best for extracting the Aadhaar number at the bottom
  try {
    const out = `${basePath}_aadhaar_thresh.png`;

    // Focus on bottom 40% where Aadhaar number usually is
    const bottomCrop = {
      left: 0,
      top: Math.floor(height * 0.55),
      width: width,
      height: Math.floor(height * 0.45),
    };

    await sharp(inputPath)
      .rotate()
      .extract(bottomCrop)
      .grayscale()
      .normalize()
      .linear(2.0, -80)     // very aggressive contrast
      .threshold(128)
      .sharpen({ sigma: 2.0 })
      .png()
      .toFile(out);

    variants.aadhaar_number_region = out;
    console.log("[Preprocess] ✓ Aadhaar number region (bottom crop)");
  } catch (e) {
    console.warn("[Preprocess] ✗ Aadhaar number region failed:", e.message);
  }

  // Variant D: Middle section — where name, DOB, gender appear
  try {
    const out = `${basePath}_middle_section.png`;

    const middleCrop = {
      left: isLandscape ? Math.floor(width * 0.30) : 0,
      top: Math.floor(height * 0.15),
      width: isLandscape ? Math.floor(width * 0.65) : width,
      height: Math.floor(height * 0.50),
    };

    await sharp(inputPath)
      .rotate()
      .extract(middleCrop)
      .grayscale()
      .normalize()
      .sharpen({ sigma: 1.8 })
      .linear(1.5, -40)
      .png()
      .toFile(out);

    variants.middle_section = out;
    console.log("[Preprocess] ✓ Middle section (name/DOB region)");
  } catch (e) {
    console.warn("[Preprocess] ✗ Middle section failed:", e.message);
  }

  // ════════════════════════════════════════════
  //  STEP 3: PAN-OPTIMIZED VARIANTS
  // ════════════════════════════════════════════

  // Variant E: Invert dark regions (PAN has dark blue background in header)
  try {
    const out = `${basePath}_pan_invert.png`;

    await sharp(inputPath)
      .rotate()
      .grayscale()
      .normalize()
      .threshold(100)     // lower threshold to catch white-on-dark text
      .negate()           // invert: white text on dark bg → black text on white bg
      .normalize()
      .sharpen({ sigma: 1.5 })
      .png()
      .toFile(out);

    variants.pan_inverted = out;
    console.log("[Preprocess] ✓ PAN inverted (for dark backgrounds)");
  } catch (e) {
    console.warn("[Preprocess] ✗ PAN invert failed:", e.message);
  }

  // Variant F: PAN number region — typically upper-middle area
  try {
    const out = `${basePath}_pan_number.png`;

    const panNumberCrop = {
      left: Math.floor(width * 0.15),
      top: Math.floor(height * 0.35),
      width: Math.floor(width * 0.70),
      height: Math.floor(height * 0.20),
    };

    await sharp(inputPath)
      .rotate()
      .extract(panNumberCrop)
      .grayscale()
      .normalize()
      .linear(2.0, -60)
      .threshold(140)
      .sharpen({ sigma: 2.5 })
      // Upscale small crops for better OCR
      .resize({ width: Math.floor(panNumberCrop.width * 2.5), kernel: "lanczos3" })
      .png()
      .toFile(out);

    variants.pan_number_region = out;
    console.log("[Preprocess] ✓ PAN number region");
  } catch (e) {
    console.warn("[Preprocess] ✗ PAN number region failed:", e.message);
  }

  // ════════════════════════════════════════════
  //  STEP 4: UNIVERSAL HIGH-QUALITY VARIANTS
  // ════════════════════════════════════════════

  // Variant G: Standard grayscale + normalize (baseline)
  try {
    const out = `${basePath}_standard.png`;
    await sharp(inputPath)
      .rotate()
      .grayscale()
      .normalize()
      .sharpen({ sigma: 1.5 })
      .png()
      .toFile(out);
    variants.standard = out;
    console.log("[Preprocess] ✓ Standard grayscale");
  } catch (e) {
    console.warn("[Preprocess] ✗ Standard failed:", e.message);
  }

  // Variant H: High contrast
  try {
    const out = `${basePath}_highcontrast.png`;
    await sharp(inputPath)
      .rotate()
      .grayscale()
      .normalize()
      .linear(1.8, -60)
      .sharpen({ sigma: 2.0 })
      .png()
      .toFile(out);
    variants.high_contrast = out;
    console.log("[Preprocess] ✓ High contrast");
  } catch (e) {
    console.warn("[Preprocess] ✗ High contrast failed:", e.message);
  }

  // Variant I: Binary threshold
  try {
    const out = `${basePath}_binary.png`;
    await sharp(inputPath)
      .rotate()
      .grayscale()
      .normalize()
      .threshold(140)
      .png()
      .toFile(out);
    variants.binary = out;
    console.log("[Preprocess] ✓ Binary threshold");
  } catch (e) {
    console.warn("[Preprocess] ✗ Binary failed:", e.message);
  }

  // Variant J: Upscaled (if image is small)
  try {
    if (width < 1200 || height < 800) {
      const out = `${basePath}_upscaled.png`;
      const scale = Math.min(3, Math.ceil(1800 / width));
      await sharp(inputPath)
        .rotate()
        .resize({ width: width * scale, kernel: "lanczos3" })
        .grayscale()
        .normalize()
        .sharpen({ sigma: 1.2 })
        .png()
        .toFile(out);
      variants.upscaled = out;
      console.log(`[Preprocess] ✓ Upscaled ${scale}x`);
    }
  } catch (e) {
    console.warn("[Preprocess] ✗ Upscale failed:", e.message);
  }

  // Variant K: Adaptive — mild processing for clean scans
  try {
    const out = `${basePath}_mild.png`;
    await sharp(inputPath)
      .rotate()
      .grayscale()
      .sharpen({ sigma: 0.8 })
      .png()
      .toFile(out);
    variants.mild = out;
    console.log("[Preprocess] ✓ Mild (for clean scans)");
  } catch (e) {
    console.warn("[Preprocess] ✗ Mild failed:", e.message);
  }

  // Variant L: Color preserved but enhanced — catches colored text
  try {
    const out = `${basePath}_color_enhanced.png`;
    await sharp(inputPath)
      .rotate()
      .normalize()
      .sharpen({ sigma: 2.0 })
      .modulate({ brightness: 1.15, saturation: 0.2 })
      .png()
      .toFile(out);
    variants.color_enhanced = out;
    console.log("[Preprocess] ✓ Color enhanced");
  } catch (e) {
    console.warn("[Preprocess] ✗ Color enhanced failed:", e.message);
  }

  console.log(`[Preprocess] Total variants: ${Object.keys(variants).length}`);
  return variants;
}

module.exports = { preprocessImage };