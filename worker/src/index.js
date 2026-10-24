const UPSTREAM = "https://api.spicylyrics.org/v1/lyrics/";

function json(status, body, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...extra },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/v1\/lyrics\/([A-Za-z0-9]{22})$/);
    if (request.method !== "GET" || !match) return json(404, { Body: { error: "not_found" } });
    if (!env.SPICY_API_KEY) return json(500, { Body: { error: "no_key" } });

    const id = match[1];
    const cache = caches.default;
    const cacheKey = new Request(`https://lyrics-cache.internal/${id}`);
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    if (env.LIMITER) {
      const ip = request.headers.get("CF-Connecting-IP") || "unknown";
      const { success } = await env.LIMITER.limit({ key: ip });
      if (!success) return json(429, { Body: { error: "rate_limited" } }, { "Retry-After": "60" });
    }

    const upstream = await fetch(UPSTREAM + id, {
      headers: {
        Authorization: `Bearer ${env.SPICY_API_KEY}`,
        Accept: "application/json",
        "User-Agent": "SpicyLyricsiOS-Proxy/1.0 (https://github.com/mapix3/SpicyLyrics-iOS-v2)",
      },
    });

    const ttl = upstream.status === 200 ? 86400 : upstream.status === 404 ? 3600 : 0;
    const response = new Response(await upstream.arrayBuffer(), {
      status: upstream.status,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": ttl ? `public, max-age=${ttl}` : "no-store",
      },
    });
    if (ttl) ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};
