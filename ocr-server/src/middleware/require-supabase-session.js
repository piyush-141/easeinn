const crypto = require("crypto");

const SUPABASE_URL = (process.env.WHATSAPP_SUPABASE_URL || "https://pvydmztbjyrqefaqdqhb.supabase.co").replace(/\/$/, "");
const SUPABASE_PUBLISHABLE_KEY =
  process.env.WHATSAPP_SUPABASE_PUBLISHABLE_KEY ||
  "sb_publishable__U1X_V5sTRpj3Yr2N1x_mw_ejQD0IUV";
const verifiedTokens = new Map();
const MAX_CACHE_ENTRIES = 2000;

function tokenCacheExpiry(token) {
  try {
    const payload = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString("utf8"));
    const expiresAt = Number(payload.exp) * 1000;
    return Math.min(Date.now() + 30_000, expiresAt);
  } catch (_) {
    return Date.now();
  }
}

async function isValidSupabaseAccessToken(token) {
  const tokenHash = crypto.createHash("sha256").update(token).digest("hex");
  const cached = verifiedTokens.get(tokenHash);
  if (cached && cached.expiresAt > Date.now()) return true;
  if (cached) verifiedTokens.delete(tokenHash);

  const response = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    method: "GET",
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      authorization: `Bearer ${token}`,
      accept: "application/json",
    },
    signal: AbortSignal.timeout(5000),
  });

  if (response.status === 401 || response.status === 403) return false;
  if (!response.ok) throw new Error(`Supabase Auth returned HTTP ${response.status}`);
  const user = await response.json();
  if (!user || typeof user.id !== "string" || !user.id) return false;

  const expiresAt = tokenCacheExpiry(token);
  if (expiresAt > Date.now()) {
    if (verifiedTokens.size >= MAX_CACHE_ENTRIES) {
      const firstKey = verifiedTokens.keys().next().value;
      if (firstKey) verifiedTokens.delete(firstKey);
    }
    verifiedTokens.set(tokenHash, { expiresAt });
  }
  return true;
}

async function requireSupabaseSession(req, res, next) {
  // Local emulator development uses the device's offline/demo account, which
  // has no Supabase access token. Keep that path available only when the local
  // launcher explicitly opts in; never honor the bypass in production.
  if (
    process.env.NODE_ENV !== "production" &&
    process.env.WHATSAPP_ALLOW_LOCAL_ACCESS === "true"
  ) {
    return next();
  }

  const authorization = req.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return res.status(401).json({
      success: false,
      code: "AUTH_REQUIRED",
      error: "WhatsApp requires an active EaseInn online session. Sign in to the app and try again.",
    });
  }

  try {
    if (!(await isValidSupabaseAccessToken(match[1].trim()))) {
      return res.status(401).json({
        success: false,
        code: "SESSION_EXPIRED",
        error: "Your EaseInn session expired. Sign in to the app again, then retry.",
      });
    }
    return next();
  } catch (err) {
    console.error("[WhatsApp Auth] Supabase verification unavailable:", err.message);
    return res.status(503).json({
      success: false,
      code: "AUTH_SERVICE_UNAVAILABLE",
      error: "Could not verify your EaseInn session right now. Retry when the backend is online.",
    });
  }
}

module.exports = { requireSupabaseSession, isValidSupabaseAccessToken };
