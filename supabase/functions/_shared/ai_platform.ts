// Shared AI platform helpers (TV3): token usage parsing, circuit breaker,
// provider URL validation and server-side feature flag evaluation.
// Kept free of network I/O so it can be unit tested with `deno test`.

type JsonObject = Record<string, unknown>;

export type AiProvider = "gemini" | "9router" | "groq" | "local" | "none";

export type AiUsage = {
  inputTokens: number;
  outputTokens: number;
  thinkingTokens: number;
  cachedTokens: number;
  totalTokens: number;
};

/** AI optimization flags stored in `public.app_feature_flags`. */
export const aiFlagKeys = [
  "ai.extract.thinking_low",
  "ai.extract.image_1600",
  "ai.extract.precheck_dedup",
  "ai.extract.validator",
  "ai.chat.local_router",
  "ai.chat.merge_calls",
  "ai.chat.prompt_v2",
  "ai.classify.local",
  "ai.router.failover",
  "ai.telemetry.upload",
] as const;

export type AiFlagKey = typeof aiFlagKeys[number];

const aiFlagKeySet: ReadonlySet<string> = new Set(aiFlagKeys);

export function isAiFlagKey(value: string): value is AiFlagKey {
  return aiFlagKeySet.has(value);
}

export function emptyUsage(): AiUsage {
  return {inputTokens: 0, outputTokens: 0, thinkingTokens: 0, cachedTokens: 0, totalTokens: 0};
}

export function addUsage(target: AiUsage, value: AiUsage): void {
  target.inputTokens += value.inputTokens;
  target.outputTokens += value.outputTokens;
  target.thinkingTokens += value.thinkingTokens;
  target.cachedTokens += value.cachedTokens;
  target.totalTokens += value.totalTokens;
}

function count(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0;
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Gemini `generateContent` → `usageMetadata`. */
export function geminiUsage(payload: unknown): AiUsage | null {
  if (!isObject(payload) || !isObject(payload.usageMetadata)) return null;
  const usage = payload.usageMetadata;
  const inputTokens = count(usage.promptTokenCount);
  const outputTokens = count(usage.candidatesTokenCount);
  const thinkingTokens = count(usage.thoughtsTokenCount);
  const cachedTokens = count(usage.cachedContentTokenCount);
  const reportedTotal = count(usage.totalTokenCount);
  return {
    inputTokens,
    outputTokens,
    thinkingTokens,
    cachedTokens,
    totalTokens: reportedTotal > 0 ? reportedTotal : inputTokens + outputTokens + thinkingTokens,
  };
}

/** OpenAI-compatible (9Router) `usage` block. */
export function openAiUsage(payload: unknown): AiUsage | null {
  if (!isObject(payload) || !isObject(payload.usage)) return null;
  const usage = payload.usage;
  const inputTokens = count(usage.prompt_tokens);
  const completionTokens = count(usage.completion_tokens);
  const details = isObject(usage.completion_tokens_details) ? usage.completion_tokens_details : {};
  const promptDetails = isObject(usage.prompt_tokens_details) ? usage.prompt_tokens_details : {};
  const thinkingTokens = Math.min(count(details.reasoning_tokens), completionTokens);
  const reportedTotal = count(usage.total_tokens);
  return {
    inputTokens,
    // Keep output and thinking disjoint so input + output + thinking = total.
    outputTokens: completionTokens - thinkingTokens,
    thinkingTokens,
    cachedTokens: count(promptDetails.cached_tokens),
    totalTokens: reportedTotal > 0 ? reportedTotal : inputTokens + completionTokens,
  };
}

export type BreakerState = "closed" | "open" | "half_open";

/**
 * Per-isolate circuit breaker. Edge Function isolates are reused while warm,
 * so the state protects bursts of traffic but is not shared across isolates.
 */
export class CircuitBreaker {
  private failures = 0;
  private openedAt = 0;
  private probeInFlight = false;

  constructor(
    readonly failureThreshold: number,
    readonly cooldownMs: number,
    private readonly now: () => number = Date.now,
  ) {}

  get state(): BreakerState {
    if (this.failures < this.failureThreshold) return "closed";
    return this.now() - this.openedAt >= this.cooldownMs ? "half_open" : "open";
  }

  /** Whether the primary provider may be called now. */
  allowRequest(): boolean {
    const state = this.state;
    if (state === "closed") return true;
    if (state === "open") return false;
    if (this.probeInFlight) return false;
    this.probeInFlight = true;
    return true;
  }

  recordSuccess(): void {
    this.failures = 0;
    this.openedAt = 0;
    this.probeInFlight = false;
  }

  recordFailure(): void {
    this.probeInFlight = false;
    const failedProbe = this.state === "half_open";
    this.failures += 1;
    if (failedProbe || this.failures >= this.failureThreshold) {
      // A failed half-open probe re-opens the circuit for a full cooldown.
      this.failures = Math.max(this.failures, this.failureThreshold);
      this.openedAt = this.now();
    }
  }
}

/**
 * 9Router must be reached over HTTPS on an allow-listed host, with an
 * OpenAI-compatible `/v1` base path. Returns the normalized base URL.
 */
export function validateNinerRouterBaseUrl(value: string, allowedHosts: readonly string[]): string {
  const url = new URL(value.trim());
  const hosts = allowedHosts.map((host) => host.trim().toLowerCase()).filter((host) => host.length > 0);
  if (url.protocol !== "https:") throw new Error("insecure-protocol");
  if (hosts.length === 0 || !hosts.includes(url.hostname.toLowerCase())) throw new Error("host-not-allowed");
  if (url.username || url.password || url.search || url.hash) throw new Error("invalid-url");
  if (url.pathname.replace(/\/+$/, "") !== "/v1") throw new Error("invalid-path");
  return url.toString().replace(/\/+$/, "");
}

export function parseAllowedHosts(value: string | undefined, fallback: string): string[] {
  return (value?.trim() ? value : fallback)
    .split(",")
    .map((host) => host.trim().toLowerCase())
    .filter((host) => host.length > 0);
}

/** `x-finmi-flags: ai.router.failover=1,ai.chat.prompt_v2=0` (debug only). */
export function parseFlagOverrides(header: string | null): Map<AiFlagKey, boolean> {
  const overrides = new Map<AiFlagKey, boolean>();
  if (!header) return overrides;
  for (const part of header.split(",").slice(0, aiFlagKeys.length * 2)) {
    const [rawKey, rawValue] = part.split("=", 2).map((item) => item?.trim() ?? "");
    if (!rawKey || !isAiFlagKey(rawKey)) continue;
    const value = (rawValue ?? "").toLowerCase();
    if (["1", "true", "on"].includes(value)) overrides.set(rawKey, true);
    if (["0", "false", "off"].includes(value)) overrides.set(rawKey, false);
  }
  return overrides;
}

export type FlagRow = {key: string; enabled: boolean; rollout_percentage?: number | null};

/** Same bucketing as the Flutter client (`RemoteConfigService._isInRollout`). */
export async function rolloutBucket(userId: string, key: string): Promise<number> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${userId.trim()}:${key}`)),
  );
  let bucket = 0;
  for (const byte of digest.subarray(0, 4)) bucket = bucket * 256 + byte;
  return bucket % 100;
}

export async function evaluateAiFlags(
  rows: readonly FlagRow[],
  userId: string | null,
  overrides: ReadonlyMap<AiFlagKey, boolean> = new Map(),
): Promise<Set<AiFlagKey>> {
  const enabled = new Set<AiFlagKey>();
  for (const row of rows) {
    if (!isAiFlagKey(row.key) || row.enabled !== true) continue;
    const rollout = typeof row.rollout_percentage === "number"
      ? Math.min(Math.max(Math.trunc(row.rollout_percentage), 0), 100)
      : 100;
    if (rollout <= 0 || !userId?.trim()) continue;
    if (rollout >= 100 || await rolloutBucket(userId, row.key) < rollout) enabled.add(row.key);
  }
  for (const [key, value] of overrides) {
    if (value) enabled.add(key);
    else enabled.delete(key);
  }
  return enabled;
}

/** Stable label stored in `ai_request_metrics.flag_set` (`none` = baseline B0). */
export function flagSetLabel(flags: ReadonlySet<string>): string {
  const keys = [...flags].filter(isAiFlagKey).sort();
  return keys.length === 0 ? "none" : keys.join(",");
}

/** Error codes caused by the AI provider rather than by the user's input. */
const providerFailureCodes = new Set([
  "MODEL_RATE_LIMITED",
  "MODEL_ERROR",
  "MODEL_TIMEOUT",
  "EMPTY_MODEL_RESPONSE",
  "INVALID_MODEL_JSON",
  "AI_NOT_CONFIGURED",
]);

export function isProviderFailureCode(code: string): boolean {
  return providerFailureCodes.has(code);
}

/** Quota is refunded for provider-side failures (5xx and upstream 429). */
export function shouldRefundQuota(status: number, code: string): boolean {
  return status >= 500 || code === "MODEL_RATE_LIMITED";
}

/** Gemini `responseJsonSchema` rejects some JSON Schema meta keywords. */
export function sanitizeSchemaForGemini(schema: unknown, isPropertyMap = false): unknown {
  if (Array.isArray(schema)) return schema.map((item) => sanitizeSchemaForGemini(item));
  if (!isObject(schema)) return schema;
  const result: JsonObject = {};
  for (const [key, value] of Object.entries(schema)) {
    // Keys of a `properties` map are field names (a field may be called "title").
    if (!isPropertyMap && (key === "$schema" || key === "$id" || key === "title" || key === "$comment")) continue;
    result[key] = sanitizeSchemaForGemini(value, !isPropertyMap && key === "properties");
  }
  return result;
}

export type InjectedFault = "429" | "500" | "timeout";

export function parseInjectedFault(value: string | null | undefined): InjectedFault | null {
  const normalized = value?.trim().toLowerCase();
  return normalized === "429" || normalized === "500" || normalized === "timeout" ? normalized : null;
}
