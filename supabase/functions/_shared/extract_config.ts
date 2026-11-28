// Gemini `generationConfig` additions for invoice extraction (OCR).
//
// B0 (all flags off) adds nothing, so the request is identical to `main`.
// TV1 – O1/O3: `ai.extract.thinking_low` sets `thinkingLevel: "low"` and a
// bounded output cap. `AI_EXTRACT_MAX_OUTPUT_TOKENS` overrides the cap and
// may also be used on its own.

/** Output cap used with thinking-low when no env override is configured. */
export const DEFAULT_THINKING_LOW_MAX_OUTPUT_TOKENS = 4096;

export type ExtractConfigOptions = {
  thinkingLow: boolean;
  /** `AI_EXTRACT_MAX_OUTPUT_TOKENS`; `undefined` or `0` means unset. */
  maxOutputTokensEnv?: number;
};

export function buildExtractGenerationConfig(options: ExtractConfigOptions): Record<string, unknown> {
  const envCap = options.maxOutputTokensEnv && options.maxOutputTokensEnv > 0
    ? options.maxOutputTokensEnv
    : undefined;
  const config: Record<string, unknown> = {};
  if (options.thinkingLow) config.thinkingConfig = {thinkingLevel: "low"};
  const cap = envCap ?? (options.thinkingLow ? DEFAULT_THINKING_LOW_MAX_OUTPUT_TOKENS : undefined);
  if (cap !== undefined) config.maxOutputTokens = cap;
  return config;
}
