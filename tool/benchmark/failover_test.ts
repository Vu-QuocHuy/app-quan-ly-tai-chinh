import {
  type FailoverRow,
  evaluateFailoverRuns,
  failoverCsv,
  parseChatResponse,
} from "./failover.ts";

function assert(ok: boolean, message = "Assertion failed") {
  if (!ok) throw new Error(message);
}

const okOn = (idx: number): FailoverRow => ({
  idx, scenario: "on", status: 200, code: "", provider: "gemini",
  failover: true, quotaRefunded: false, durationMs: idx <= 3 ? 4000 : 900,
});
const failOff = (idx: number): FailoverRow => ({
  idx, scenario: "off", status: 429, code: "MODEL_RATE_LIMITED", provider: "",
  failover: false, quotaRefunded: true, durationMs: 500,
});

Deno.test("flag ON: 10/10 answered by Gemini after failover passes", () => {
  const rows = [...Array(10)].map((_, i) => okOn(i + 1));
  const result = evaluateFailoverRuns(rows);
  assert(result.failures.length === 0, result.failures.join("; "));
});

Deno.test("flag ON: a non-200 answer fails the run", () => {
  const rows = [...Array(10)].map((_, i) => okOn(i + 1));
  rows[4] = {...rows[4], status: 429, code: "MODEL_RATE_LIMITED", provider: "", failover: false};
  const result = evaluateFailoverRuns(rows);
  assert(result.failures.some((f) => f.includes("on") && f.includes("200")), result.failures.join("; "));
});

Deno.test("flag ON: answered by 9Router instead of Gemini fails the run", () => {
  const rows = [...Array(10)].map((_, i) => okOn(i + 1));
  rows[0] = {...rows[0], provider: "9router", failover: false};
  const result = evaluateFailoverRuns(rows);
  assert(result.failures.some((f) => f.includes("gemini")), result.failures.join("; "));
});

Deno.test("flag OFF (B0): 429 MODEL_RATE_LIMITED is the expected outcome", () => {
  const rows = [...Array(10)].map((_, i) => failOff(i + 1));
  assert(evaluateFailoverRuns(rows).failures.length === 0);
});

Deno.test("flag OFF: a 200 means the fault was not injected", () => {
  const rows = [...Array(10)].map((_, i) => failOff(i + 1));
  rows[2] = {...rows[2], status: 200, code: "", provider: "9router"};
  const result = evaluateFailoverRuns(rows);
  assert(result.failures.some((f) => f.includes("off") && f.includes("429")), result.failures.join("; "));
});

Deno.test("the circuit opening is reported from the 4th ON request", () => {
  const rows = [...Array(10)].map((_, i) => okOn(i + 1));
  const result = evaluateFailoverRuns(rows);
  assert(result.circuitFasterAfter3 === true, "later requests should be faster than the first three");
  const slow = rows.map((row) => ({...row, durationMs: 4000}));
  assert(evaluateFailoverRuns(slow).circuitFasterAfter3 === false);
});

Deno.test("an empty run is a failure, not a pass", () => {
  assert(evaluateFailoverRuns([]).failures.length > 0);
});

Deno.test("parseChatResponse reads status, code and the _meta fields", () => {
  const row = parseChatResponse(3, "on", 200, {
    answer: "x",
    _meta: {provider: "gemini", failover: true, quotaRefunded: false},
  }, 1200);
  assert(row.provider === "gemini" && row.failover === true && row.status === 200);

  const err = parseChatResponse(4, "off", 429, {code: "MODEL_RATE_LIMITED", _meta: {quotaRefunded: true}}, 80);
  assert(err.code === "MODEL_RATE_LIMITED" && err.quotaRefunded === true && err.provider === "");
});

Deno.test("parseChatResponse tolerates a non-JSON body and odd types", () => {
  const row = parseChatResponse(1, "on", 502, null, 10);
  assert(row.code === "" && row.provider === "" && row.failover === false);
  const odd = parseChatResponse(2, "on", 200, {_meta: {provider: 42, failover: "yes"}}, 10);
  assert(odd.provider === "" && odd.failover === false);
});

Deno.test("CSV has a header and one line per row", () => {
  const csv = failoverCsv([okOn(1), failOff(2)]);
  const lines = csv.trim().split("\n");
  assert(lines.length === 3);
  assert(lines[0] === "idx,scenario,status,code,provider,failover,quota_refunded,duration_ms");
  assert(lines[1].startsWith("1,on,200,"));
});
