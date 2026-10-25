// src/utils/cleanup.js
// Deletes uploads/ and processed/ files older than MAX_AGE_MS.
// Runs every INTERVAL_MS in the background. Aadhaar data must not persist
// beyond the check-in session — 2-hour TTL is the policy.

const fs   = require("fs");
const path = require("path");

const MAX_AGE_MS  = 2 * 60 * 60 * 1000; // 2 hours
const INTERVAL_MS = 30 * 60 * 1000;     // run every 30 min

const DIRS = ["uploads", "processed"];

async function cleanDir(dir) {
  if (!fs.existsSync(dir)) return;
  let deleted = 0;
  try {
    const entries = await fs.promises.readdir(dir);
    const now = Date.now();
    await Promise.all(
      entries.map(async (entry) => {
        const filePath = path.join(dir, entry);
        try {
          const stat = await fs.promises.stat(filePath);
          if (stat.isFile() && now - stat.mtimeMs > MAX_AGE_MS) {
            await fs.promises.unlink(filePath);
            deleted++;
          }
        } catch (_) {
          // ignore individual file errors (race conditions, etc.)
        }
      })
    );
    if (deleted > 0) {
      console.log(`[Cleanup] Removed ${deleted} stale file(s) from ${dir}/`);
    }
  } catch (err) {
    console.warn(`[Cleanup] Failed to scan ${dir}:`, err.message);
  }
}

async function runCleanup() {
  await Promise.all(DIRS.map(cleanDir));
}

/**
 * Start the recurring cleanup timer.
 * Call once at server startup.
 */
function startCleanup() {
  // Run once immediately (clears any files left from a previous process)
  runCleanup().catch(() => {});

  const handle = setInterval(() => {
    runCleanup().catch(() => {});
  }, INTERVAL_MS);

  // Don't let the interval keep the process alive if nothing else is running
  if (handle.unref) handle.unref();

  console.log(
    `[Cleanup] File TTL: ${MAX_AGE_MS / 3600000}h | Interval: ${INTERVAL_MS / 60000}min`
  );
}

module.exports = { startCleanup };
