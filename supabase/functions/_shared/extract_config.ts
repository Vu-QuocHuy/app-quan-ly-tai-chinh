// Gemini `generationConfig` additions for invoice extraction (OCR).
//
// B0 (all flags off) adds nothing, so the request is identical to `main`.
// TV1 – O1: `ai.extract.thinking_low` sets `thinkingLevel: "low"` — exactly the
// configuration TV1 measured (-30.8% tokens), with no output cap.
// TV1 – O3: `AI_EXTRACT_MAX_OUTPUT_TOKENS` is an opt-in cap (use it only after
// checking long receipts); `MAX_TOKENS` answers are rejected by the caller.

export type MediaResolution = "low" | "medium" | "high";

export type ExtractConfigOptions = {
  thinkingLow: boolean;
  /** `AI_EXTRACT_MAX_OUTPUT_TOKENS`; `undefined` or `0` means unset. */
  maxOutputTokensEnv?: number;
  /**
   * `AI_EXTRACT_MEDIA_RESOLUTION` (T3.6): how many tokens each image costs.
   * `undefined` keeps the model default, so the request equals `main`.
   */
  mediaResolution?: MediaResolution;
};

/** `low` | `medium` | `high` in any case; anything else is ignored. */
export function parseMediaResolution(value: string | undefined): MediaResolution | undefined {
  const normalized = value?.trim().toLowerCase();
  return normalized === "low" || normalized === "medium" || normalized === "high" ? normalized : undefined;
}

export function buildExtractGenerationConfig(options: ExtractConfigOptions): Record<string, unknown> {
  const envCap = options.maxOutputTokensEnv && options.maxOutputTokensEnv > 0
    ? options.maxOutputTokensEnv
    : undefined;
  const config: Record<string, unknown> = {};
  if (options.thinkingLow) config.thinkingConfig = {thinkingLevel: "low"};
  if (envCap !== undefined) config.maxOutputTokens = envCap;
  if (options.mediaResolution !== undefined) {
    config.mediaResolution = `MEDIA_RESOLUTION_${options.mediaResolution.toUpperCase()}`;
  }
  return config;
}
