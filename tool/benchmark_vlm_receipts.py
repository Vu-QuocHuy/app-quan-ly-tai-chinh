#!/usr/bin/env python3
"""Evaluate invoice extraction against unambiguous MC-OCR labels.

Images are sent to the configured Supabase ai-api function. Credentials are read
from the local Supabase config and hidden prompts; they are never printed.
The benchmark always signs in with a Supabase test account before sending images.
"""

from __future__ import annotations

import argparse
import base64
import csv
from datetime import date, datetime
import getpass
import json
import mimetypes
import os
from pathlib import Path
import random
import re
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.request
import uuid


PRIMARY_LABELS = ("SELLER", "TIMESTAMP", "TOTAL_COST")


def _annotation_parts(value: str) -> list[str]:
    return value.split("|||") if value else []


def _date_key(value: str) -> str | None:
    normalized = unicodedata.normalize("NFKC", value).strip()
    vietnamese = re.search(
        r"ngày\s*(\d{1,2}).*?tháng\s*(\d{1,2}).*?năm\s*(\d{4})",
        normalized,
        re.IGNORECASE,
    )
    if vietnamese:
        day, month, year = map(int, vietnamese.groups())
        try:
            return date(year, month, day).isoformat()
        except ValueError:
            return None

    patterns = (
        (r"\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b", (0, 1, 2)),
        (r"\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})\b", (2, 1, 0)),
    )
    for pattern, order in patterns:
        match = re.search(pattern, normalized)
        if not match:
            continue
        parts = [int(match.group(index + 1)) for index in range(3)]
        year, month, day = (parts[index] for index in order)
        try:
            return date(year, month, day).isoformat()
        except ValueError:
            return None
    try:
        return datetime.fromisoformat(normalized.replace("Z", "+00:00")).date().isoformat()
    except ValueError:
        return None


def _amount_keys(value: str) -> set[str]:
    normalized = unicodedata.normalize("NFKC", value)
    tokens = re.findall(r"\d+(?:[.,]\d+)*", normalized)
    return {
        digits
        for token in tokens
        if (digits := re.sub(r"\D", "", token))
    }


def _seller_key(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return " ".join(normalized.split())


def load_gold_rows(csv_path: Path, images_dir: Path) -> list[dict[str, str]]:
    image_by_name: dict[str, list[Path]] = {}
    for image in images_dir.rglob("*"):
        if image.is_file():
            image_by_name.setdefault(image.name.casefold(), []).append(image)

    gold_rows: list[dict[str, str]] = []
    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            image_id = (row.get("img_id") or "").strip()
            candidates = image_by_name.get(Path(image_id).name.casefold(), [])
            if not image_id or len(candidates) != 1:
                continue

            labels = _annotation_parts(row.get("anno_labels") or "")
            texts = _annotation_parts(row.get("anno_texts") or "")
            if len(labels) != len(texts):
                continue

            values = {label: [] for label in PRIMARY_LABELS}
            for label, text in zip(labels, texts):
                canonical_label = "TOTAL_COST" if label == "TOTAL_TOTAL_COST" else label
                if canonical_label in values and text.strip():
                    values[canonical_label].append(text.strip())

            # MC-OCR often gives the same semantic label to a caption and its
            # value. Pick the single distinct parseable value for date/amount,
            # and keep only records with one unambiguous seller annotation.
            sellers = {_seller_key(value): value for value in values["SELLER"]}
            dates = {
                key: value
                for value in values["TIMESTAMP"]
                if (key := _date_key(value)) is not None
            }
            amounts = {
                key: value
                for value in values["TOTAL_COST"]
                for key in _amount_keys(value)
            }
            if len(sellers) != 1 or len(dates) != 1 or len(amounts) != 1:
                continue

            seller_key = next(iter(sellers))
            date_key = next(iter(dates))
            amount_key = next(iter(amounts))
            if not seller_key:
                continue
            gold_rows.append(
                {
                    "image_id": image_id,
                    "image_path": str(candidates[0]),
                    "seller_key": seller_key,
                    "date_key": date_key,
                    "total_key": amount_key,
                }
            )
    return sorted(gold_rows, key=lambda row: row["image_id"])


def _request_json(url: str, body: dict, headers: dict[str, str]) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        headers={**headers, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        try:
            details = json.loads(error.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            details = {}
        code = details.get("code") if isinstance(details, dict) else None
        message = details.get("message") if isinstance(details, dict) else None
        validation_detail = ""
        if (
            code in {"INVALID_MODEL_RESPONSE", "INVALID_AMOUNT", "EMPTY_MODEL_RESPONSE", "INVALID_MODEL_JSON"}
            and isinstance(message, str)
        ):
            safe_message = " ".join(message.split())[:240]
            validation_detail = f": {safe_message}" if safe_message else ""
        upstream_match = (
            re.search(
                r"Gemini trả lỗi (\d+)(?:, Gemini ([A-Z][A-Z0-9_]{0,63}))?"
                r"(?:, chi tiết: (.+))?\.",
                message,
            )
            if code in {"MODEL_ERROR", "MODEL_RATE_LIMITED"} and isinstance(message, str)
            else None
        )
        upstream = ""
        if upstream_match:
            upstream_details = ": ".join(
                part for part in upstream_match.groups()[1:] if part
            )
            suffix = f" ({upstream_details})" if upstream_details else ""
            upstream = f", Gemini HTTP {upstream_match.group(1)}{suffix}"
        elif code in {"MODEL_ERROR", "MODEL_RATE_LIMITED"} and isinstance(message, str):
            groq_match = re.search(r"Groq trả lỗi (\d+)(?:: (.+))?\.", message)
            if groq_match:
                details = f" ({groq_match.group(2)})" if groq_match.group(2) else ""
                upstream = f", Groq HTTP {groq_match.group(1)}{details}"
        raise RuntimeError(
            f"HTTP {error.code} ({code or 'request_failed'}{upstream}){validation_detail}"
        ) from None
    except urllib.error.URLError as error:
        raise RuntimeError(f"Network error ({error.reason})") from None
    if not isinstance(payload, dict):
        raise RuntimeError("Backend returned an invalid response")
    return payload


def _sign_in(base_url: str, api_key: str, email: str, password: str) -> str:
    payload = _request_json(
        f"{base_url.rstrip('/')}/auth/v1/token?grant_type=password",
        {"email": email, "password": password},
        {"apikey": api_key},
    )
    token = payload.get("access_token")
    if not isinstance(token, str) or not token:
        raise RuntimeError("Supabase sign-in did not return an access token")
    return token


def _extract_one(
    *, base_url: str, api_key: str, access_token: str | None, image_path: Path
) -> dict:
    mime_type, _ = mimetypes.guess_type(image_path.name)
    if mime_type not in {"image/jpeg", "image/png", "image/webp"}:
        raise RuntimeError(f"Unsupported image type: {image_path.suffix or '(unknown)'}")
    request_id = str(uuid.uuid4())
    body = {
        "action": "extract",
        "requestId": request_id,
        "locale": "vi-VN",
        "imageBase64": base64.b64encode(image_path.read_bytes()).decode("ascii"),
        "mimeType": mime_type,
    }
    headers = {"apikey": api_key}
    if access_token:
        headers["Authorization"] = f"Bearer {access_token}"
    url = f"{base_url.rstrip('/')}/functions/v1/ai-api"
    for attempt in range(2):
        try:
            return _request_json(url, body, headers)
        except RuntimeError as error:
            if _is_groq_daily_token_limit(error):
                raise
            retry_after = _groq_retry_after_seconds(error)
            if retry_after is None or attempt > 0:
                raise
            delay = retry_after + 1
            print(f"Groq rate limit; retrying once in {delay:.1f}s", file=sys.stderr)
            time.sleep(delay)
    raise RuntimeError("Extraction retry did not complete")


def _is_groq_daily_token_limit(error: RuntimeError) -> bool:
    return (
        "Groq HTTP 429" in str(error)
        and "tokens per day (TPD)" in str(error)
    )


def _groq_retry_after_seconds(error: RuntimeError) -> float | None:
    if "MODEL_RATE_LIMITED" not in str(error) or "Groq HTTP 429" not in str(error):
        return None
    match = re.search(
        r"try again in\s+(?:(\d+)\s*m)?\s*([0-9]+(?:\.[0-9]+)?)\s*s",
        str(error),
        re.I,
    )
    if not match:
        return None
    minutes = int(match.group(1) or 0)
    seconds = float(match.group(2))
    return minutes * 60 + seconds


def _write_predictions(output_path: Path, predictions: dict[str, dict]) -> None:
    temporary_path = output_path.with_suffix(f"{output_path.suffix}.tmp")
    with temporary_path.open("w", encoding="utf-8") as handle:
        for image_id, prediction in sorted(predictions.items()):
            invoice = prediction.get("invoice") if isinstance(prediction, dict) else None
            record = {
                "image_id": image_id,
                "invoice": invoice if isinstance(invoice, dict) else None,
                "sellerName": invoice.get("sellerName") if isinstance(invoice, dict) else None,
                "invoiceDate": invoice.get("invoiceDate") if isinstance(invoice, dict) else None,
                "totalMinor": invoice.get("totalMinor") if isinstance(invoice, dict) else None,
                "categoryId": invoice.get("categoryId") if isinstance(invoice, dict) else None,
                "categoryNormalization": prediction.get("categoryNormalization") if isinstance(prediction, dict) else None,
                "error": prediction.get("error") if isinstance(prediction, dict) else "invalid_response",
            }
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    os.replace(temporary_path, output_path)


def _load_successful_predictions(
    source_path: Path, sample_ids: set[str]
) -> dict[str, dict]:
    predictions: dict[str, dict] = {}
    with source_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            record = json.loads(line)
            if not isinstance(record, dict):
                continue
            image_id = record.get("image_id")
            invoice = record.get("invoice")
            if (
                not isinstance(image_id, str)
                or image_id not in sample_ids
                or not isinstance(invoice, dict)
            ):
                continue
            predictions[image_id] = {
                "invoice": invoice,
                "categoryNormalization": record.get("categoryNormalization"),
            }
    return predictions


def _load_prediction_image_ids(source_path: Path) -> set[str]:
    image_ids: set[str] = set()
    with source_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            record = json.loads(line)
            if not isinstance(record, dict):
                continue
            image_id = record.get("image_id")
            if isinstance(image_id, str):
                image_ids.add(image_id)
    return image_ids


def _prediction_value(response: dict, name: str):
    invoice = response.get("invoice")
    return invoice.get(name) if isinstance(invoice, dict) else None


def _score(gold_rows: list[dict[str, str]], predictions: dict[str, dict]) -> dict:
    fields = {
        "seller": lambda value: _seller_key(value) if isinstance(value, str) else None,
        "date": lambda value: _date_key(value) if isinstance(value, str) else None,
        "total": lambda value: str(value) if isinstance(value, int) and value >= 0 else None,
    }
    gold_fields = {"seller": "seller_key", "date": "date_key", "total": "total_key"}
    matched = {field: 0 for field in fields}
    present = {field: 0 for field in fields}
    for row in gold_rows:
        prediction = predictions.get(row["image_id"])
        if not prediction:
            continue
        for field, normalize in fields.items():
            value = _prediction_value(prediction, {
                "seller": "sellerName",
                "date": "invoiceDate",
                "total": "totalMinor",
            }[field])
            normalized = normalize(value)
            if normalized is not None:
                present[field] += 1
                matched[field] += int(normalized == row[gold_fields[field]])
    attempted = len(gold_rows)
    return {
        field: {
            "matched": matched[field],
            "attempted": attempted,
            "present": present[field],
            "accuracy": matched[field] / attempted if attempted else None,
            "accuracy_when_present": matched[field] / present[field] if present[field] else None,
            "coverage": present[field] / attempted if attempted else None,
        }
        for field in fields
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--images", type=Path, default=Path("train_images"))
    parser.add_argument("--annotations", type=Path, default=Path("mcocr_train_df.csv"))
    parser.add_argument("--config", type=Path, default=Path("config/supabase.groq.local.json"))
    parser.add_argument("--limit", type=int, default=10, help="0 means all eligible images")
    parser.add_argument("--seed", type=int, default=20261004)
    parser.add_argument(
        "--resume-from",
        type=Path,
        help="reuse successful responses from a previous JSONL run with the same sample",
    )
    parser.add_argument(
        "--pause-seconds",
        type=float,
        help="minimum gap between authenticated requests; defaults to 65s",
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--no-auth",
        action="store_true",
        help="disabled: benchmark requests require an authenticated Supabase session",
    )
    parser.add_argument("--prepare-only", action="store_true", help="print eligibility counts without calling the API")
    args = parser.parse_args()
    if args.no_auth:
        parser.error("--no-auth đã bị tắt; benchmark cần đăng nhập Supabase.")

    gold_rows = load_gold_rows(args.annotations, args.images)
    if not gold_rows:
        print("No unambiguous images with seller, date and total labels found.", file=sys.stderr)
        return 2
    print(f"Eligible labeled images: {len(gold_rows)}", flush=True)
    if args.prepare_only:
        return 0

    if args.limit < 0:
        parser.error("--limit must be 0 or greater")
    if args.resume_from:
        resume_ids = _load_prediction_image_ids(args.resume_from)
        rows_by_id = {row["image_id"]: row for row in gold_rows}
        missing_ids = resume_ids.difference(rows_by_id)
        if not resume_ids or missing_ids:
            parser.error(
                "Resume file has no matching eligible image IDs; "
                "use the same annotations and image dataset."
            )
        sample = sorted((rows_by_id[image_id] for image_id in resume_ids), key=lambda row: row["image_id"])
        sample_count = len(sample)
    else:
        sample_count = len(gold_rows) if args.limit == 0 else min(args.limit, len(gold_rows))
        sample = sorted(
            random.Random(args.seed).sample(gold_rows, sample_count),
            key=lambda row: row["image_id"],
        )
    pause_seconds = args.pause_seconds
    if pause_seconds is None:
        pause_seconds = 2.1

    config = json.loads(args.config.read_text(encoding="utf-8"))
    base_url = config.get("SUPABASE_URL")
    api_key = config.get("SUPABASE_PUBLISHABLE_KEY")
    if not isinstance(base_url, str) or not isinstance(api_key, str):
        print("Supabase URL or publishable key is missing from config.", file=sys.stderr)
        return 2
    email = os.environ.get("SUPABASE_TEST_EMAIL") or input("Supabase test account email: ")
    password = os.environ.get("SUPABASE_TEST_PASSWORD") or getpass.getpass("Supabase test account password: ")
    try:
        access_token = _sign_in(base_url, api_key, email, password)
    except RuntimeError as error:
        print(f"Sign-in failed: {error}", file=sys.stderr)
        return 2

    sample_ids = {row["image_id"] for row in sample}
    cached_predictions = (
        _load_successful_predictions(args.resume_from, sample_ids)
        if args.resume_from
        else {}
    )
    predictions = {
        row["image_id"]: {"error": "not_attempted"}
        for row in sample
    }
    predictions.update(cached_predictions)
    output_path = args.output or args.resume_from or Path(tempfile.gettempdir()) / (
        f"vlm-receipt-predictions-{datetime.now().strftime('%Y%m%d-%H%M%S')}.jsonl"
    )
    pending_rows = [
        row for row in sample if row["image_id"] not in cached_predictions
    ]
    pending_count = len(pending_rows)
    print(
        f"Cached successful responses: {len(cached_predictions)}/{sample_count}; "
        f"requests remaining: {pending_count}",
        flush=True,
    )
    _write_predictions(output_path, predictions)
    for index, row in enumerate(pending_rows, start=1):
        started = time.monotonic()
        quota_exhausted = False
        try:
            predictions[row["image_id"]] = _extract_one(
                base_url=base_url,
                api_key=api_key,
                access_token=access_token,
                image_path=Path(row["image_path"]),
            )
            print(f"Processed {index}/{pending_count}", flush=True)
        except RuntimeError as error:
            predictions[row["image_id"]] = {"error": str(error)}
            print(f"Failed {index}/{pending_count}: {error}", file=sys.stderr)
            quota_exhausted = _is_groq_daily_token_limit(error)
        _write_predictions(output_path, predictions)
        if quota_exhausted:
            print(
                "Stopped early because the Groq token-per-day limit was reached.",
                file=sys.stderr,
            )
            break
        if index < pending_count:
            elapsed = time.monotonic() - started
            time.sleep(max(0, pause_seconds - elapsed))

    successful = {key: value for key, value in predictions.items() if "invoice" in value}
    scored_rows = [row for row in sample if row["image_id"] in successful]
    scored = _score(scored_rows, successful)
    print(f"Predictions saved locally: {output_path}")
    print(f"Successful responses: {len(successful)}/{sample_count}")
    for field, metric in scored.items():
        accuracy = metric["accuracy"]
        present_accuracy = metric["accuracy_when_present"]
        coverage = metric["coverage"]
        accuracy_label = "n/a" if accuracy is None else f"{accuracy:.1%}"
        present_label = "n/a" if present_accuracy is None else f"{present_accuracy:.1%}"
        coverage_label = "n/a" if coverage is None else f"{coverage:.1%}"
        print(
            f"{field}: {metric['matched']}/{metric['attempted']} exact "
            f"({accuracy_label}); present {metric['present']}/{metric['attempted']} "
            f"({coverage_label}); exact when present {present_label}"
        )
    item_checks: list[tuple[str, int, int, int, bool]] = []
    for image_id, prediction in successful.items():
        invoice = prediction.get("invoice")
        if not isinstance(invoice, dict):
            continue
        subtotal = invoice.get("subtotalMinor")
        total = invoice.get("totalMinor")
        tax = invoice.get("taxMinor")
        items = invoice.get("items")
        if (
            isinstance(subtotal, int)
            and subtotal > 0
            and isinstance(total, int)
            and isinstance(items, list)
            and items
            and all(
                isinstance(item, dict)
                and isinstance(item.get("totalMinor"), int)
                for item in items
            )
        ):
            item_sum = sum(item["totalMinor"] for item in items)
            comparable_amounts = {subtotal, total}
            if isinstance(tax, int):
                comparable_amounts.add(subtotal + tax)
            item_checks.append(
                (image_id, item_sum, subtotal, total, item_sum in comparable_amounts)
            )
    if item_checks:
        consistent = sum(is_compatible for *_, is_compatible in item_checks)
        print(
            "Item total sum compatible with subtotal, subtotal plus tax, or final "
            f"total (consistency check, not gold accuracy): {consistent}/{len(item_checks)}"
        )
        for image_id, item_sum, subtotal, total, is_compatible in item_checks:
            if not is_compatible:
                print(
                    f"Item total mismatch: {image_id} lines={item_sum} "
                    f"subtotal={subtotal} total={total}"
                )
    return 0 if len(successful) == sample_count else 1


if __name__ == "__main__":
    raise SystemExit(main())
