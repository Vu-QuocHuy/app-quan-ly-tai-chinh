// Gemini `generationConfig` additions for invoice extraction (OCR).
//
// B0 (all flags off) adds nothing, so the request is identical to `main`.
// TV1 – O1/O3: `ai.extract.thinking_low` sets `thinkingLevel: "low"` and a
// bounded output cap. `AI_EXTRACT_MAX_OUTPUT_TOKENS` overrides the cap and
// may also be used on its own.

/** Output cap used with thinking-low when no env override is configured. */
export const DEFAULT_THINKING_LOW_MAX_OUTPUT_TOKENS = 4096;

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
  const cap = envCap ?? (options.thinkingLow ? DEFAULT_THINKING_LOW_MAX_OUTPUT_TOKENS : undefined);
  if (cap !== undefined) config.maxOutputTokens = cap;
  if (options.mediaResolution !== undefined) {
    config.mediaResolution = `MEDIA_RESOLUTION_${options.mediaResolution.toUpperCase()}`;
  }
  return config;
}
