function createWhatsAppAuthMiddleware({
  authUrl = process.env.SUPABASE_URL || "",
  anonKey = process.env.SUPABASE_ANON_KEY || "",
  fetcher = fetch,
} = {}) {
  const baseUrl = authUrl.replace(/\/$/, "");
  return async function requireWhatsAppUser(req, res, next) {
  if (!baseUrl || !anonKey) {
    return res.status(503).json({ success: false, code: "AUTH_NOT_CONFIGURED", error: "WhatsApp access is unavailable until server authentication is configured." });
  }

  const authorization = req.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return res.status(401).json({ success: false, code: "AUTH_REQUIRED", error: "Sign in to access WhatsApp." });
  }

  try {
    const response = await fetcher(`${baseUrl}/auth/v1/user`, {
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${match[1]}`,
      },
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) {
      return res.status(401).json({ success: false, code: "AUTH_INVALID", error: "Your sign-in expired. Please sign in again." });
    }
    req.user = await response.json();
    return next();
  } catch (err) {
    console.error("[WhatsApp Auth] Supabase verification failed:", err.message);
    return res.status(503).json({ success: false, code: "AUTH_UNAVAILABLE", error: "Could not verify your sign-in. Try again shortly." });
  }
  };
}

module.exports = createWhatsAppAuthMiddleware();
module.exports.createWhatsAppAuthMiddleware = createWhatsAppAuthMiddleware;
