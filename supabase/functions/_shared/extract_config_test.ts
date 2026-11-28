import {buildExtractGenerationConfig, parseMediaResolution} from "./extract_config.ts";

function assertEquals(actual: unknown, expected: unknown, message = "") {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message} expected ${e} but got ${a}`);
}

Deno.test("all optimisations off: no generationConfig additions (B0 = main)", () => {
  assertEquals(buildExtractGenerationConfig({thinkingLow: false}), {});
});

Deno.test("thinkingLow adds only thinkingLevel low (the configuration TV1 measured)", () => {
  assertEquals(buildExtractGenerationConfig({thinkingLow: true}), {
    thinkingConfig: {thinkingLevel: "low"},
  });
});

Deno.test("env cap is added next to thinkingLow when configured", () => {
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

Deno.test("media resolution medium adds the Gemini enum, alone or with thinking low", () => {
  assertEquals(buildExtractGenerationConfig({thinkingLow: false, mediaResolution: "medium"}), {
    mediaResolution: "MEDIA_RESOLUTION_MEDIUM",
  });
  assertEquals(buildExtractGenerationConfig({thinkingLow: true, mediaResolution: "low"}), {
    thinkingConfig: {thinkingLevel: "low"},
    mediaResolution: "MEDIA_RESOLUTION_LOW",
  });
});

Deno.test("no media resolution leaves the request as in main", () => {
  assertEquals(buildExtractGenerationConfig({thinkingLow: false, mediaResolution: undefined}), {});
});

Deno.test("parseMediaResolution accepts low/medium/high in any case and ignores the rest", () => {
  assertEquals(parseMediaResolution("medium"), "medium");
  assertEquals(parseMediaResolution(" HIGH "), "high");
  assertEquals(parseMediaResolution("Low"), "low");
  assertEquals(parseMediaResolution("ultra"), undefined);
  assertEquals(parseMediaResolution(""), undefined);
  assertEquals(parseMediaResolution(undefined), undefined);
});
