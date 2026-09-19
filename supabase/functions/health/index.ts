const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, {headers});
  if (request.method !== "GET" && request.method !== "HEAD") {
    return json({ok: false, code: "METHOD_NOT_ALLOWED"}, 405);
  }
  const url = new URL(request.url);
  if (url.searchParams.get("check") === "readiness") {
    return readiness(request);
  }
  return json({ok: true, service: "finance-backend"});
});

async function readiness(request: Request): Promise<Response> {
  const expected = Deno.env.get("HEALTHCHECK_SECRET")?.trim();
  const actual = request.headers.get("X-Health-Secret")?.trim();
  if (!expected || expected.length < 32) {
    return json({ok: false, code: "READINESS_NOT_CONFIGURED"}, 503);
  }
  if (actual !== expected) {
    return json({ok: false, code: "HEALTHCHECK_UNAUTHORIZED"}, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  const checks = {
    supabaseConfig: Boolean(supabaseUrl && serviceRoleKey),
    supabaseAnonKey: Boolean(Deno.env.get("SUPABASE_ANON_KEY")?.trim()),
    database: false,
    aiKey: Boolean(Deno.env.get("GEMINI_API_KEY")?.trim()),
    workerSecret: (Deno.env.get("AI_WORKER_SECRET")?.trim().length ?? 0) >= 32,
    aiOriginAllowlist: originAllowlistEnforced("AI_REQUIRE_ORIGIN_ALLOWLIST", "AI_ALLOWED_ORIGINS"),
    deleteAccountOriginAllowlist: originAllowlistEnforced("DELETE_ACCOUNT_REQUIRE_ORIGIN_ALLOWLIST", "DELETE_ACCOUNT_ALLOWED_ORIGINS"),
    aiExtractionJobs: false,
    aiInputBucket: false,
    receiptImageBucket: false,
    invoiceBackupBucket: false,
    aiCostBudget: false,
    aiCostUsage: false,
    aiCostUsageSummary: false,
    syncMetrics: false,
    featureFlags: false,
    clientErrorMonitoring: false,
  };

  if (supabaseUrl && serviceRoleKey) {
    checks.database = await probe(
      `${supabaseUrl}/rest/v1/ai_request_metrics?select=id&limit=1`,
      serviceRoleKey,
    );
    checks.aiInputBucket = await probe(
      `${supabaseUrl}/storage/v1/bucket/ai-inputs`,
      serviceRoleKey,
    );
    checks.receiptImageBucket = await probe(
      `${supabaseUrl}/storage/v1/bucket/receipt-images`,
      serviceRoleKey,
    );
    checks.invoiceBackupBucket = await probe(
      `${supabaseUrl}/storage/v1/bucket/invoice-backups`,
      serviceRoleKey,
    );
    checks.aiExtractionJobs = await probe(
      `${supabaseUrl}/rest/v1/ai_extraction_jobs?select=id&limit=1`,
      serviceRoleKey,
    );
    checks.aiCostBudget = await probe(
      `${supabaseUrl}/rest/v1/ai_cost_budgets?select=user_id&limit=1`,
      serviceRoleKey,
    );
    checks.aiCostUsage = await probe(
      `${supabaseUrl}/rest/v1/ai_cost_usage?select=user_id&limit=1`,
      serviceRoleKey,
    );
    checks.aiCostUsageSummary = await probe(
      `${supabaseUrl}/rest/v1/ai_cost_usage_summary?select=period_type&limit=1`,
      serviceRoleKey,
    );
    checks.syncMetrics = await probe(
      `${supabaseUrl}/rest/v1/sync_request_metrics?select=id&limit=1`,
      serviceRoleKey,
    );
    checks.featureFlags = await probe(
      `${supabaseUrl}/rest/v1/app_feature_flags?select=key&limit=1`,
      serviceRoleKey,
    );
    checks.clientErrorMonitoring = await probe(
      `${supabaseUrl}/rest/v1/client_error_events?select=id&limit=1`,
      serviceRoleKey,
    );
  }
  const ok = Object.values(checks).every(Boolean);
  return json({ok, service: "finance-backend", checks}, ok ? 200 : 503);
}

function originAllowlistEnforced(requiredName: string, originsName: string): boolean {
  if (!envFlag(requiredName)) return false;
  const origins = (Deno.env.get(originsName) ?? "")
    .split(",")
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
  return origins.length > 0 && origins.every((origin) => normalizeOrigin(origin) !== null);
}

function normalizeOrigin(value: string): string | null {
  try {
    const parsed = new URL(value);
    const isLocalHttp = parsed.protocol === "http:" &&
      (parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1" || parsed.hostname === "[::1]");
    const isSecure = parsed.protocol === "https:";
    if ((!isSecure && !isLocalHttp) || parsed.username || parsed.password || parsed.pathname !== "/" || parsed.search || parsed.hash) {
      return null;
    }
    return parsed.origin;
  } catch {
    return null;
  }
}

function envFlag(name: string): boolean {
  return (Deno.env.get(name) ?? "").trim().toLowerCase() === "true";
}

async function probe(url: string, serviceRoleKey: string): Promise<boolean> {
  try {
    const response = await fetch(url, {
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
      },
      signal: AbortSignal.timeout(5_000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {status, headers});
}
