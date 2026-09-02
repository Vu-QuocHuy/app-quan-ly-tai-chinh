import type {ChatFact} from "./contracts.js";

const providerBase = "https://open.er-api.com/v6/latest";
const cacheTtlMs = 15 * 60 * 1_000;
const cache = new Map<string, {expiresAt: number; context: ExternalContext}>();
const supportedCurrencies = new Set([
  "AUD", "CAD", "CHF", "CNY", "EUR", "GBP", "HKD", "IDR", "INR",
  "JPY", "KRW", "MYR", "PHP", "SGD", "THB", "USD", "VND",
]);

export type ExternalContext = Readonly<{
  facts: ChatFact[];
  citations: ReadonlyArray<Readonly<{
    label: string;
    sourceType: "external";
    sourceId: string;
    url: string;
    capturedAt: string;
  }>>;
  usedExternalData: boolean;
}>;

export async function loadExternalContext(question: string): Promise<ExternalContext> {
  if (process.env.ENABLE_EXTERNAL_EXCHANGE_RATES === "false") {
    return {facts: [], citations: [], usedExternalData: false};
  }
  const pair = currencyPair(question);
  if (pair === undefined) return {facts: [], citations: [], usedExternalData: false};

  const url = `${providerBase}/${pair.base}`;
  const cached = cache.get(url);
  if (cached !== undefined && cached.expiresAt > Date.now()) return cached.context;
  try {
    const response = await fetch(url, {signal: AbortSignal.timeout(5_000)});
    if (!response.ok) return remember(url, unavailable(pair, url));
    const payload: unknown = await response.json();
    if (!isObject(payload) || payload.result !== "success" || !isObject(payload.rates)) {
      return remember(url, unavailable(pair, url));
    }
    const rate = payload.rates[pair.target];
    if (typeof rate !== "number" || !Number.isFinite(rate) || rate <= 0) {
      return remember(url, unavailable(pair, url));
    }
    const updated = typeof payload.time_last_update_utc === "string"
      ? payload.time_last_update_utc
      : "không rõ";
    return remember(url, {
      facts: [
        {key: "external_exchange_rate", value: `1 ${pair.base} = ${rate} ${pair.target}`},
        {key: "external_exchange_updated_at", value: updated},
      ],
      citations: [{
        label: "ExchangeRate-API",
        sourceType: "external",
        sourceId: `${pair.base}/${pair.target}`,
        url,
        capturedAt: new Date().toISOString(),
      }],
      usedExternalData: true,
    });
  } catch {
    return remember(url, unavailable(pair, url));
  }
}

function remember(url: string, context: ExternalContext): ExternalContext {
  cache.set(url, {expiresAt: Date.now() + cacheTtlMs, context});
  return context;
}

function unavailable(pair: CurrencyPair, url: string): ExternalContext {
  return {
    facts: [{key: "external_exchange_rate", value: `Không lấy được tỷ giá ${pair.base}/${pair.target}`}],
    citations: [{
      label: "ExchangeRate-API (không khả dụng)",
      sourceType: "external",
      sourceId: `${pair.base}/${pair.target}`,
      url,
      capturedAt: new Date().toISOString(),
    }],
    usedExternalData: false,
  };
}

type CurrencyPair = Readonly<{base: string; target: string}>;

function currencyPair(question: string): CurrencyPair | undefined {
  const upper = question.toUpperCase();
  const codes = [...upper.matchAll(/\b[A-Z]{3}\b/g)]
    .map((match) => match[0])
    .filter((code): code is string => code !== undefined && supportedCurrencies.has(code));
  const unique = [...new Set(codes)];
  const mentionsRate = /tỷ giá|ty gia|đổi tiền|doi tien|exchange|ngoại tệ|ngoai te/i.test(question);
  if (!mentionsRate && unique.length === 0) return undefined;
  const base = unique[0] ?? "USD";
  const target = unique[1] ?? "VND";
  if (base === target) return undefined;
  return {base, target};
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
