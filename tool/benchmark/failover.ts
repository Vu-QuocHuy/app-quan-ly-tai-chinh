// T3.4 — failover 429 check for the AI platform (TV3's circuit breaker).
//
// Sends 10 chat questions with an injected 9Router fault, once with
// `ai.router.failover` OFF (B0) and once ON, and checks the outcome described
// in docs/ai-optimization/tv3-nen-tang-ai.md §6.
//
//   FINMI_AI_URL=<ai-api endpoint> FINMI_AI_ACCESS_TOKEN=<user jwt> \
//   FINMI_AI_PUBLISHABLE_KEY=<anon key> \
//   deno run --allow-env --allow-net --allow-read --allow-write \
//     tool/benchmark/failover.ts [--out docs/ai-optimization/data/failover.csv]
//
// The target project must have AI_ALLOW_DEBUG_HEADERS=true and
// AI_EXPOSE_USAGE_META=true (dev/benchmark projects only). Never commit the
// URL, the token or the key.

export type FailoverRow = {
  idx: number;
  scenario: "off" | "on";
  status: number;
  code: string;
  provider: string;
  failover: boolean;
  quotaRefunded: boolean;
  durationMs: number;
};

export type FailoverResult = {
  failures: string[];
  /** Median duration of requests 4..10 below that of requests 1..3 (ON). */
  circuitFasterAfter3: boolean | null;
};

const REQUESTS_PER_SCENARIO = 10;

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function parseChatResponse(
  idx: number,
  scenario: "off" | "on",
  status: number,
  body: unknown,
  durationMs: number,
): FailoverRow {
  const json = isObject(body) ? body : {};
  const meta = isObject(json._meta) ? json._meta : {};
  return {
    idx,
    scenario,
    status,
    code: typeof json.code === "string" ? json.code : "",
    provider: typeof meta.provider === "string" ? meta.provider : "",
    failover: meta.failover === true,
    quotaRefunded: meta.quotaRefunded === true,
    durationMs,
  };
}

function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

export function evaluateFailoverRuns(rows: FailoverRow[]): FailoverResult {
  const failures: string[] = [];
  const on = rows.filter((row) => row.scenario === "on");
  const off = rows.filter((row) => row.scenario === "off");
  if (rows.length === 0) failures.push("no requests were sent");

  for (const row of on) {
    if (row.status !== 200) {
      failures.push(`on #${row.idx}: expected status 200 after failover, got ${row.status} ${row.code}`);
    } else if (row.provider !== "gemini" || !row.failover) {
      failures.push(`on #${row.idx}: expected provider gemini with failover=true, got ${row.provider || "-"} failover=${row.failover}`);
    }
  }
  for (const row of off) {
    if (row.status !== 429 || row.code !== "MODEL_RATE_LIMITED") {
      failures.push(`off #${row.idx}: expected 429 MODEL_RATE_LIMITED (baseline), got ${row.status} ${row.code}`);
    }
  }

  let circuitFasterAfter3: boolean | null = null;
  if (on.length >= 4) {
    const ordered = [...on].sort((a, b) => a.idx - b.idx);
    const first = ordered.slice(0, 3).map((row) => row.durationMs);
    const later = ordered.slice(3).map((row) => row.durationMs);
    circuitFasterAfter3 = median(later) < median(first);
  }
  return {failures, circuitFasterAfter3};
}

export function failoverCsv(rows: FailoverRow[]): string {
  const header = "idx,scenario,status,code,provider,failover,quota_refunded,duration_ms";
  const lines = rows.map((row) =>
    [row.idx, row.scenario, row.status, row.code, row.provider, row.failover, row.quotaRefunded, row.durationMs].join(",")
  );
  return [header, ...lines].join("\n") + "\n";
}

// ---------------------------------------------------------------------------

async function loadQuestions(): Promise<string[]> {
  const path = new URL("./chat_questions_40.json", import.meta.url);
  const data = JSON.parse(await Deno.readTextFile(path));
  // Questions that really reach the model (not answered locally, not refused
  // by the privacy policy before the network).
  const ids = ["Q13", "Q14", "Q15", "Q16", "Q17", "Q18", "Q19", "Q20", "Q29", "Q34"];
  const byId = new Map<string, string>(data.questions.map((q: {id: string; text: string}) => [q.id, q.text]));
  return ids.map((id) => {
    const text = byId.get(id);
    if (!text) throw new Error(`question ${id} missing from chat_questions_40.json`);
    return text;
  });
}

async function runScenario(
  scenario: "off" | "on",
  questions: string[],
  config: {url: string; token: string; key: string},
): Promise<FailoverRow[]> {
  const rows: FailoverRow[] = [];
  for (const [i, question] of questions.slice(0, REQUESTS_PER_SCENARIO).entries()) {
    const started = performance.now();
    const response = await fetch(config.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${config.token}`,
        apikey: config.key,
        "x-finmi-flags": `ai.router.failover=${scenario === "on" ? 1 : 0}`,
        "x-finmi-fault": "429",
      },
      body: JSON.stringify({
        action: "chat",
        requestId: crypto.randomUUID(),
        locale: "vi-VN",
        question,
        facts: [],
        allowToolCalls: false,
      }),
    });
    let body: unknown = null;
    try {
      body = await response.json();
    } catch {
      body = null;
    }
    rows.push(parseChatResponse(i + 1, scenario, response.status, body, Math.round(performance.now() - started)));
  }
  return rows;
}

if (import.meta.main) {
  const url = Deno.env.get("FINMI_AI_URL");
  const token = Deno.env.get("FINMI_AI_ACCESS_TOKEN");
  const key = Deno.env.get("FINMI_AI_PUBLISHABLE_KEY");
  if (!url || !token || !key) {
    console.error("Set FINMI_AI_URL (ai-api endpoint), FINMI_AI_ACCESS_TOKEN and FINMI_AI_PUBLISHABLE_KEY. Do not commit them.");
    Deno.exit(2);
  }
  const outIndex = Deno.args.indexOf("--out");
  const outPath = outIndex >= 0 ? Deno.args[outIndex + 1] : null;

  const questions = await loadQuestions();
  // OFF first: the circuit breaker is per isolate, so run the baseline before
  // the failover scenario can leave it open.
  const rows = [
    ...await runScenario("off", questions, {url, token, key}),
    ...await runScenario("on", questions, {url, token, key}),
  ];
  const csv = failoverCsv(rows);
  if (outPath) await Deno.writeTextFile(outPath, csv);
  else console.log(csv);

  const result = evaluateFailoverRuns(rows);
  console.log(`circuit faster after request 3 (ON): ${result.circuitFasterAfter3}`);
  if (result.failures.length > 0) {
    for (const failure of result.failures) console.error(`FAIL ${failure}`);
    Deno.exit(1);
  }
  console.log("failover check passed");
}
