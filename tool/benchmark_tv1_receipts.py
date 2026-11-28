#!/usr/bin/env python3
"""Paired OCR benchmark. Run `prepare`, export Flutter payloads, then `run` per variant."""

import argparse
import base64
import hashlib
import json
import mimetypes
import os
from pathlib import Path
import random
import statistics
import time
import uuid

from benchmark_vlm_receipts import _date_key, _sign_in, _request_json, load_gold_rows


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
    temporary.replace(path)


def percentile(values, fraction):
    values = sorted(values)
    if not values:
        return None
    position = (len(values) - 1) * fraction
    lower = int(position)
    return values[lower] + (values[min(lower + 1, len(values) - 1)] - values[lower]) * (position - lower)


def summary(rows):
    count = len(rows)
    successful = [row for row in rows if row.get("invoice")]
    durations = [row["latency_ms"] for row in successful if row.get("latency_ms") is not None]
    tokens = [row["tokens"] for row in rows if row.get("tokens") is not None]
    wrong_totals = [row for row in successful if not row["total_correct"]]
    correct_totals = [row for row in successful if row["total_correct"]]
    return {
        "samples": count,
        "successful": len(successful),
        "failed": count - len(successful),
        "total_correct": sum(row.get("total_correct") is True for row in rows),
        "date_correct": sum(row.get("date_correct") is True for row in rows),
        "payload_kb_mean": round(statistics.mean(row["payload_bytes"] for row in rows) / 1024, 2) if count else None,
        "success_latency_ms_p50": round(percentile(durations, .5), 1) if durations else None,
        "success_latency_ms_p95": round(percentile(durations, .95), 1) if durations else None,
        "tokens_mean": round(statistics.mean(tokens), 1) if tokens else None,
        "token_coverage": f"{len(tokens)}/{count}",
        "total_warning_recall": round(sum(row.get("total_warned") is True for row in wrong_totals) / len(wrong_totals), 3) if wrong_totals else None,
        "total_warning_false_positive_rate": round(sum(row.get("total_warned") is True for row in correct_totals) / len(correct_totals), 3) if correct_totals else None,
        "wrong_total_count": len(wrong_totals),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser("prepare")
    prepare.add_argument("--images", type=Path, default=Path("train_images"))
    prepare.add_argument("--annotations", type=Path, default=Path("mcocr_train_df.csv"))
    prepare.add_argument("--limit", type=int, default=30)
    prepare.add_argument("--seed", type=int, default=20261004)
    prepare.add_argument("--sample", type=Path, required=True)
    run = commands.add_parser("run")
    run.add_argument("--sample", type=Path, required=True)
    run.add_argument("--payload-manifest", type=Path)
    run.add_argument("--variant", required=True)
    run.add_argument("--output", type=Path, required=True)
    run.add_argument("--config", type=Path, default=Path("config/supabase.groq.local.json"))
    run.add_argument("--pause-seconds", type=float, default=2.1)
    run.add_argument("--compare-to", type=Path)
    args = parser.parse_args()

    if args.command == "prepare":
        if args.limit < 1:
            parser.error("--limit must be positive")
        gold = load_gold_rows(args.annotations, args.images)
        if not gold:
            parser.error("No eligible labeled receipts")
        sample = sorted(random.Random(args.seed).sample(gold, min(args.limit, len(gold))), key=lambda row: row["image_id"])
        for row in sample:
            row["source_sha256"] = hashlib.sha256(Path(row["image_path"]).read_bytes()).hexdigest()
        write_jsonl(args.sample, sample)
        print(f"Prepared {len(sample)} receipts: {args.sample}")
        return

    sample = read_jsonl(args.sample)
    if not sample or len({row["image_id"] for row in sample}) != len(sample):
        parser.error("Sample must contain unique image_id values")
    payloads = {}
    if args.payload_manifest:
        payloads = {row["image_id"]: row for row in read_jsonl(args.payload_manifest)}
        if set(payloads) != {row["image_id"] for row in sample}:
            parser.error("Payload manifest must match the sample exactly")
    if args.pause_seconds < 0:
        parser.error("--pause-seconds must not be negative")
    if args.output.exists():
        parser.error("Output exists; use a new file for every independent run")
    baseline = read_jsonl(args.compare_to) if args.compare_to else None
    if baseline is not None and (len(baseline) != len(sample) or {row["image_id"] for row in baseline} != {row["image_id"] for row in sample}):
        parser.error("Baseline and current run must contain the same image IDs")
    config = json.loads(args.config.read_text(encoding="utf-8"))
    base_url, api_key = config.get("SUPABASE_URL"), config.get("SUPABASE_PUBLISHABLE_KEY")
    if not base_url or not api_key:
        parser.error("Supabase URL and publishable key are required")
    email = os.environ.get("SUPABASE_TEST_EMAIL") or input("Supabase test email: ")
    password = os.environ.get("SUPABASE_TEST_PASSWORD")
    if not password:
        import getpass
        password = getpass.getpass("Supabase test password: ")
    token = _sign_in(base_url, api_key, email, password)
    headers = {"apikey": api_key, "Authorization": f"Bearer {token}"}
    url = f"{base_url.rstrip('/')}/functions/v1/ai-api"
    results = []
    for index, gold in enumerate(sample):
        payload = payloads.get(gold["image_id"])
        if hashlib.sha256(Path(gold["image_path"]).read_bytes()).hexdigest() != gold["source_sha256"]:
            parser.error(f"Source image changed since prepare: {gold['image_id']}")
        image_path = Path(payload["payload_path"] if payload else gold["image_path"])
        mime_type = payload["mime_type"] if payload else mimetypes.guess_type(image_path.name)[0]
        if mime_type not in {"image/jpeg", "image/png", "image/webp"}:
            parser.error(f"Unsupported image type: {image_path}")
        image_bytes = image_path.read_bytes()
        record = {
            "variant": args.variant, "image_id": gold["image_id"],
            "request_id": str(uuid.uuid4()), "original_bytes": Path(gold["image_path"]).stat().st_size,
            "payload_bytes": len(image_bytes), "mime_type": mime_type,
        }
        started = time.monotonic()
        try:
            response = _request_json(url, {
                "action": "extract", "requestId": record["request_id"], "locale": "vi-VN",
                "imageBase64": base64.b64encode(image_bytes).decode("ascii"), "mimeType": mime_type,
            }, headers)
            invoice = response.get("invoice")
            if not isinstance(invoice, dict):
                raise RuntimeError("Missing invoice in response")
            usage = response.get("usageMetadata")
            evidence = response.get("evidence")
            total_evidence = next((item for item in evidence if isinstance(item, dict) and item.get("field") == "totalMinor"), None) if isinstance(evidence, list) else None
            record.update({
                "invoice": invoice,
                "total_correct": str(invoice.get("totalMinor")) == gold["total_key"],
                "date_correct": _date_key(invoice.get("invoiceDate") or "") == gold["date_key"],
                "tokens": usage.get("totalTokenCount") if isinstance(usage, dict) else None,
                "input_tokens": usage.get("promptTokenCount") if isinstance(usage, dict) else None,
                "thinking_tokens": usage.get("thoughtsTokenCount") if isinstance(usage, dict) else None,
                "output_tokens": usage.get("candidatesTokenCount") if isinstance(usage, dict) else None,
                "model_version": response.get("modelVersion"),
                "total_warned": isinstance(total_evidence.get("confidence"), (int, float)) and total_evidence["confidence"] < .6 if total_evidence else False,
            })
        except RuntimeError as error:
            record["error"] = str(error)
            record["total_correct"] = False
            record["date_correct"] = False
        record["latency_ms"] = round((time.monotonic() - started) * 1000)
        results.append(record)
        write_jsonl(args.output, results)
        print(f"{index + 1}/{len(sample)} {gold['image_id']}: {'OK' if 'invoice' in record else record['error']}", flush=True)
        if index + 1 < len(sample):
            time.sleep(max(0, args.pause_seconds - record["latency_ms"] / 1000))
    print(json.dumps(summary(results), ensure_ascii=False, indent=2))
    if baseline is not None:
        before, after = summary(baseline), summary(results)
        print("baseline:", json.dumps(before, ensure_ascii=False, indent=2))
        for key in ("payload_kb_mean", "success_latency_ms_p50", "success_latency_ms_p95", "tokens_mean"):
            if before[key] and after[key] is not None:
                print(f"{key}: {(after[key] / before[key] - 1) * 100:+.1f}%")
        print(f"total correct: {before['total_correct']}/{before['samples']} -> {after['total_correct']}/{after['samples']}")
        print(f"date correct: {before['date_correct']}/{before['samples']} -> {after['date_correct']}/{after['samples']}")


if __name__ == "__main__":
    main()
