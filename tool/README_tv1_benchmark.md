# TV1 receipt OCR benchmark

The summary reports successful and failed requests separately. Latency percentiles use successful requests only, so fast HTTP 429 responses cannot make OCR look faster. Use `flutter test tool/replay_tv1_warnings_test.dart --no-pub` for the app's warning rule on the archived B1 data. The API evidence metrics in the Python runner describe the server response before the Flutter rule.

Run from the repository root. This benchmark calls the authenticated `ai-api` `extract` endpoint and consumes quota. Use a test account; credentials stay in environment variables or the hidden password prompt.

## Freeze one sample

```bash
python3 tool/benchmark_tv1_receipts.py prepare \
  --limit 30 --seed 20261004 --sample artifacts/tv1/sample.jsonl
```

The existing MC-OCR labels provide seller, date and total. Review the selected labels manually before treating them as ground truth. Keep `sample.jsonl` fixed for every variant.

## Export the bytes the app actually sends

Do this once on the baseline code, then again after changing `receipt_image_optimizer.dart`. The exporter calls `optimizeReceiptImageForOcr` directly.

```bash
FINMI_BENCH_SAMPLE=artifacts/tv1/sample.jsonl \
FINMI_BENCH_PAYLOAD_DIR=artifacts/tv1/payload_b0 \
flutter test tool/export_ocr_payloads_test.dart
```

Use another output directory such as `payload_b1` after the image change. A payload manifest records the MIME type even when the exported file has a `.payload` suffix.

## Run each server configuration

Set `SUPABASE_TEST_EMAIL` and `SUPABASE_TEST_PASSWORD`, or enter them at the prompts. The config file supplies `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.

```bash
python3 tool/benchmark_tv1_receipts.py run \
  --sample artifacts/tv1/sample.jsonl \
  --payload-manifest artifacts/tv1/payload_b0/payload_manifest.jsonl \
  --variant B0 --output artifacts/tv1/b0.jsonl

python3 tool/benchmark_tv1_receipts.py run \
  --sample artifacts/tv1/sample.jsonl \
  --payload-manifest artifacts/tv1/payload_b1/payload_manifest.jsonl \
  --variant B1 --output artifacts/tv1/b1.jsonl \
  --compare-to artifacts/tv1/b0.jsonl
```

Deploy the corresponding server setting before each run. `AI_EXTRACT_THINKING_LOW=true` enables low thinking; unset it for B0/I. Set `AI_EXTRACT_MAX_OUTPUT_TOKENS` only after checking long receipts, and leave it unset for the initial T run. For attribution, run `T` with the B0 image manifest and low thinking, then `I` with the B1 image manifest and baseline thinking. The script refuses to overwrite an output file, so each independent run has its own record. It writes one row after every request, including failures.

`latency_ms` is script-to-API wall time, not app UI time. `tokens` uses Gemini `usageMetadata.totalTokenCount` returned by `ai-api`; `token_coverage` exposes missing metadata. Counts of correct total and date use the full sample as denominator. `total_warning_recall` and false-positive rate score the API's `totalMinor` evidence against labeled total errors among successful responses; a small or zero `wrong_total_count` cannot support a strong M5 claim. p95 from 30 images is descriptive only. The script does not exercise the app's duplicate guard; evaluate M10 with five already-saved images in the app and verify no `extract` request was made.
