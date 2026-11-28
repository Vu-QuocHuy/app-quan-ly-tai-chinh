import {
  buildExtractGenerationConfig,
  DEFAULT_THINKING_LOW_MAX_OUTPUT_TOKENS,
} from "./extract_config.ts";

function assertEquals(actual: unknown, expected: unknown, message = "") {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message} expected ${e} but got ${a}`);
}

Deno.test("all optimisations off: no generationConfig additions (B0 = main)", () => {
  assertEquals(buildExtractGenerationConfig({thinkingLow: false}), {});
});

Deno.test("thinkingLow: thinkingLevel low with the default output cap", () => {
  assertEquals(buildExtractGenerationConfig({thinkingLow: true}), {
    thinkingConfig: {thinkingLevel: "low"},
    maxOutputTokens: 4096,
  });
  assertEquals(DEFAULT_THINKING_LOW_MAX_OUTPUT_TOKENS, 4096);
});

Deno.test("env cap overrides the default cap when thinkingLow is on", () => {
  assertEquals(buildExtractGenerationConfig({thinkingLow: true, maxOutputTokensEnv: 2048}), {
    thinkingConfig: {thinkingLevel: "low"},
    maxOutputTokens: 2048,
  });
});

Deno.test("env cap alone sets only maxOutputTokens (no thinkingConfig)", () => {
  assertEquals(buildExtractGenerationConfig({thinkingLow: false, maxOutputTokensEnv: 8192}), {
    maxOutputTokens: 8192,
  });
});

Deno.test("an unset or zero env cap is ignored", () => {
  assertEquals(buildExtractGenerationConfig({thinkingLow: false, maxOutputTokensEnv: 0}), {});
  assertEquals(buildExtractGenerationConfig({thinkingLow: false, maxOutputTokensEnv: undefined}), {});
});
