import {
  CircuitBreaker,
  evaluateAiFlags,
  flagSetLabel,
  geminiUsage,
  openAiUsage,
  parseAllowedHosts,
  parseFlagOverrides,
  parseInjectedFault,
  rolloutBucket,
  sanitizeSchemaForGemini,
  shouldRefundQuota,
  validateNinerRouterBaseUrl,
} from "./ai_platform.ts";

function assertEquals(actual: unknown, expected: unknown, message = "") {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message} expected ${e}, got ${a}`);
}

function assertThrows(fn: () => unknown, message = "") {
  try {
    fn();
  } catch {
    return;
  }
  throw new Error(`${message} expected function to throw`);
}

Deno.test("geminiUsage reads thinking tokens from usageMetadata", () => {
  assertEquals(geminiUsage({
    usageMetadata: {promptTokenCount: 1200, candidatesTokenCount: 300, thoughtsTokenCount: 900, totalTokenCount: 2400},
  }), {inputTokens: 1200, outputTokens: 300, thinkingTokens: 900, cachedTokens: 0, totalTokens: 2400});
  assertEquals(geminiUsage({candidates: []}), null);
});

Deno.test("openAiUsage splits reasoning tokens out of completion tokens", () => {
  assertEquals(openAiUsage({
    usage: {
      prompt_tokens: 800,
      completion_tokens: 150,
      total_tokens: 950,
      completion_tokens_details: {reasoning_tokens: 100},
      prompt_tokens_details: {cached_tokens: 512},
    },
  }), {inputTokens: 800, outputTokens: 50, thinkingTokens: 100, cachedTokens: 512, totalTokens: 950});
  assertEquals(openAiUsage({choices: []}), null);
});

Deno.test("circuit breaker opens, half-opens with one probe and closes", () => {
  let now = 0;
  const breaker = new CircuitBreaker(2, 1_000, () => now);
  breaker.recordFailure();
  assertEquals(breaker.allowRequest(), true, "still closed after 1 failure");
  breaker.recordFailure();
  assertEquals(breaker.state, "open");
  assertEquals(breaker.allowRequest(), false);
  now = 1_000;
  assertEquals(breaker.state, "half_open");
  assertEquals(breaker.allowRequest(), true, "first probe allowed");
  assertEquals(breaker.allowRequest(), false, "second concurrent probe blocked");
  breaker.recordFailure();
  assertEquals(breaker.state, "open", "failed probe re-opens");
  now = 2_000;
  assertEquals(breaker.allowRequest(), true);
  breaker.recordSuccess();
  assertEquals(breaker.state, "closed");
});

Deno.test("9Router base URL requires https and an allow-listed host", () => {
  const hosts = parseAllowedHosts(undefined, "finmi.ddns.net");
  assertEquals(validateNinerRouterBaseUrl("https://finmi.ddns.net/v1/", hosts), "https://finmi.ddns.net/v1");
  assertThrows(() => validateNinerRouterBaseUrl("http://finmi.ddns.net/v1", hosts), "http");
  assertThrows(() => validateNinerRouterBaseUrl("http://103.199.18.103:20128/v1", hosts), "old ip");
  assertThrows(() => validateNinerRouterBaseUrl("https://evil.example/v1", hosts), "host");
  assertThrows(() => validateNinerRouterBaseUrl("https://user:pw@finmi.ddns.net/v1", hosts), "credentials");
  assertThrows(() => validateNinerRouterBaseUrl("https://finmi.ddns.net/admin", hosts), "path");
  assertEquals(parseAllowedHosts(" A.example , b.example ", "x"), ["a.example", "b.example"]);
});

Deno.test("flag overrides only accept known AI flags", () => {
  const overrides = parseFlagOverrides("ai.router.failover=1, ai.chat.prompt_v2=off, online_ai=1, bogus=1");
  assertEquals([...overrides.entries()], [["ai.router.failover", true], ["ai.chat.prompt_v2", false]]);
});

Deno.test("evaluateAiFlags honours enabled, rollout and overrides", async () => {
  const flags = await evaluateAiFlags([
    {key: "ai.router.failover", enabled: true, rollout_percentage: 100},
    {key: "ai.chat.prompt_v2", enabled: true, rollout_percentage: 0},
    {key: "ai.extract.thinking_low", enabled: false, rollout_percentage: 100},
    {key: "online_ai", enabled: true, rollout_percentage: 100},
  ], "00000000-0000-4000-8000-000000000001", new Map([["ai.extract.validator", true]]));
  assertEquals(flagSetLabel(flags), "ai.extract.validator,ai.router.failover");
  assertEquals(flagSetLabel(await evaluateAiFlags([], null)), "none");
});

Deno.test("rollout bucket matches the Dart client algorithm", async () => {
  // sha256("user-1:ai.router.failover") first 4 bytes, big-endian, mod 100.
  // Reference value computed with Python hashlib (same as Dart `(b << 8) | byte`).
  assertEquals(await rolloutBucket("user-1", "ai.router.failover"), 10);
  assertEquals(await rolloutBucket(" user-1 ", "ai.router.failover"), 10, "trims user id");
});

Deno.test("quota refund policy and fault parsing", () => {
  assertEquals(shouldRefundQuota(503, "AI_DEGRADED"), true);
  assertEquals(shouldRefundQuota(429, "MODEL_RATE_LIMITED"), true);
  assertEquals(shouldRefundQuota(429, "RATE_LIMITED"), false, "user rate limit is not refunded");
  assertEquals(shouldRefundQuota(400, "INVALID_BODY"), false);
  assertEquals(parseInjectedFault(" 429 "), "429");
  assertEquals(parseInjectedFault("boom"), null);
});

Deno.test("sanitizeSchemaForGemini drops meta keywords recursively", () => {
  assertEquals(sanitizeSchemaForGemini({
    $schema: "x",
    title: "t",
    type: "object",
    properties: {a: {type: "string", title: "inner"}, title: {type: "string"}},
  }), {type: "object", properties: {a: {type: "string"}, title: {type: "string"}}});
});
