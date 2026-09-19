type JsonObject = Record<string, unknown>;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};
const configuredOrigins = (Deno.env.get("DELETE_ACCOUNT_ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((origin) => origin.trim())
  .filter((origin) => origin.length > 0);
const allowedOrigins = new Set(
  configuredOrigins
    .map(normalizeOrigin)
    .filter((origin): origin is string => origin !== null),
);
const originsConfigurationValid = configuredOrigins.length > 0 &&
  configuredOrigins.every((origin) => normalizeOrigin(origin) !== null);
const requireOriginAllowlist = envFlag("DELETE_ACCOUNT_REQUIRE_ORIGIN_ALLOWLIST");
const userIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

class FunctionError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
  }
}

Deno.serve(async (request) => {
  if (!originAllowed(request)) {
    return json(request, {code: "ORIGIN_NOT_ALLOWED", message: "Origin không được phép."}, 403);
  }
  if (request.method === "OPTIONS") return new Response("ok", {headers: headersFor(request)});
  if (request.method !== "POST") return json(request, {code: "METHOD_NOT_ALLOWED", message: "Chỉ hỗ trợ POST."}, 405);

  try {
    const accessToken = bearerToken(request.headers.get("Authorization"));
    if (!accessToken) throw new FunctionError(401, "UNAUTHENTICATED", "Phiên đăng nhập không hợp lệ.");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
    if (!supabaseUrl || !serviceRoleKey) {
      throw new FunctionError(503, "DELETE_NOT_CONFIGURED", "Dịch vụ xóa tài khoản chưa được cấu hình.");
    }

    const userId = await authenticatedUserId(supabaseUrl, serviceRoleKey, accessToken);
    for (const bucket of ["receipt-images", "invoice-backups", "ai-inputs"]) {
      await removeUserObjects(supabaseUrl, serviceRoleKey, bucket, userId);
    }
    await deleteAuthUser(supabaseUrl, serviceRoleKey, userId);
    return json(request, {deleted: true});
  } catch (error) {
    if (error instanceof FunctionError) return json(request, {code: error.code, message: error.message}, error.status);
    console.error("delete_account_failed", error instanceof Error ? error.name : "unknown");
    return json(request, {code: "INTERNAL", message: "Không thể xóa tài khoản lúc này."}, 500);
  }
});

function originAllowed(request: Request): boolean {
  const origin = request.headers.get("Origin")?.trim();
  if (origin == null || origin.length === 0) return true;
  const normalizedOrigin = normalizeOrigin(origin);
  if (normalizedOrigin === null) return false;
  if (requireOriginAllowlist && !originsConfigurationValid) return false;
  if (allowedOrigins.size === 0) return !requireOriginAllowlist;
  return allowedOrigins.has(normalizedOrigin);
}

function headersFor(request: Request): Record<string, string> {
  const origin = request.headers.get("Origin")?.trim();
  if (origin == null || origin.length === 0) {
    return corsHeaders;
  }
  if (allowedOrigins.size === 0 && !requireOriginAllowlist) {
    return corsHeaders;
  }
  const normalizedOrigin = normalizeOrigin(origin);
  if (normalizedOrigin === null ||
      (requireOriginAllowlist && !originsConfigurationValid) ||
      !allowedOrigins.has(normalizedOrigin)) {
    return {
      ...corsHeaders,
      "Access-Control-Allow-Origin": "null",
      "Vary": "Origin",
    };
  }
  return {
    ...corsHeaders,
    "Access-Control-Allow-Origin": normalizedOrigin,
    "Vary": "Origin",
  };
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

function bearerToken(value: string | null): string | null {
  if (!value) return null;
  const match = /^Bearer\s+(.+)$/i.exec(value.trim());
  return match?.[1]?.trim() || null;
}

async function authenticatedUserId(
  supabaseUrl: string,
  serviceRoleKey: string,
  accessToken: string,
): Promise<string> {
  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${accessToken}`,
    },
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new FunctionError(401, "UNAUTHENTICATED", "Phiên đăng nhập không hợp lệ.");
  const value: unknown = await response.json();
  if (!isObject(value) || typeof value.id !== "string" || !userIdPattern.test(value.id.trim())) {
    throw new FunctionError(401, "UNAUTHENTICATED", "Không xác định được tài khoản.");
  }
  return value.id;
}

async function removeUserObjects(
  supabaseUrl: string,
  serviceRoleKey: string,
  bucket: string,
  userId: string,
): Promise<void> {
  const paths = await listUserObjects(supabaseUrl, serviceRoleKey, bucket, userId);
  for (let index = 0; index < paths.length; index += 100) {
    const chunk = paths.slice(index, index + 100);
    const response = await fetch(`${supabaseUrl}/storage/v1/object/${bucket}`, {
      method: "DELETE",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({prefixes: chunk}),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new FunctionError(502, "STORAGE_DELETE_FAILED", "Không thể dọn tệp tài khoản.");
  }
}

async function listUserObjects(
  supabaseUrl: string,
  serviceRoleKey: string,
  bucket: string,
  userId: string,
): Promise<string[]> {
  const paths: string[] = [];
  await listStoragePrefix(
    supabaseUrl,
    serviceRoleKey,
    bucket,
    userId,
    `${userId}/`,
    paths,
    new Set<string>(),
  );
  return paths;
}

async function listStoragePrefix(
  supabaseUrl: string,
  serviceRoleKey: string,
  bucket: string,
  userId: string,
  prefix: string,
  paths: string[],
  visitedPrefixes: Set<string>,
): Promise<void> {
  if (!prefix.startsWith(`${userId}/`) || !visitedPrefixes.add(prefix)) return;
  let offset = 0;
  while (true) {
    const response = await fetch(`${supabaseUrl}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        prefix,
        limit: 1_000,
        offset,
        sortBy: {column: "name", order: "asc"},
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (response.status === 404) return;
    if (!response.ok) throw new FunctionError(502, "STORAGE_LIST_FAILED", "Không thể kiểm tra tệp tài khoản.");
    const value: unknown = await response.json();
    if (!Array.isArray(value)) throw new FunctionError(502, "STORAGE_LIST_FAILED", "Danh sách tệp không hợp lệ.");
    for (const item of value) {
      if (!isObject(item) || typeof item.name !== "string" || item.name.trim().length === 0) continue;
      const listedName = item.name.trim();
      const prefixRelative = prefix.slice(userId.length + 1);
      const relativeName = listedName.startsWith(`${userId}/`)
        ? listedName.slice(userId.length + 1)
        : listedName.startsWith(prefixRelative)
        ? listedName
        : `${prefixRelative}${listedName}`;
      if ((item.id != null || item.metadata != null) && isSafeObjectName(relativeName)) {
        paths.push(`${userId}/${relativeName}`);
      } else if (isSafeObjectName(relativeName)) {
        await listStoragePrefix(
          supabaseUrl,
          serviceRoleKey,
          bucket,
          userId,
          `${userId}/${relativeName}/`,
          paths,
          visitedPrefixes,
        );
      }
    }
    if (value.length < 1_000) break;
    offset += value.length;
  }
}

function isSafeObjectName(value: string): boolean {
  const name = value.trim();
  if (name.length === 0 || name.length > 1_024 || /[\u0000-\u001F]/.test(name) || name.startsWith("/") || name.includes("\\")) return false;
  return name.split("/").every((part) => part.length > 0 && part !== "." && part !== "..");
}

async function deleteAuthUser(
  supabaseUrl: string,
  serviceRoleKey: string,
  userId: string,
): Promise<void> {
  const response = await fetch(`${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
    method: "DELETE",
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
    },
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new FunctionError(502, "ACCOUNT_DELETE_FAILED", "Không thể xóa tài khoản trên máy chủ.");
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function json(request: Request, body: JsonObject, status = 200): Response {
  return new Response(JSON.stringify(body), {status, headers: headersFor(request)});
}
