import {createHash} from "node:crypto";

import {ClientError} from "./contracts.js";

type Bucket = {readonly startedAt: number; count: number};

const WINDOW_MS = 60_000;
const MAX_REQUESTS_PER_WINDOW = 30;
const buckets = new Map<string, Bucket>();

export function enforceRateLimit(identifier: string): void {
  const now = Date.now();
  const key = createHash("sha256").update(identifier).digest("hex");
  const current = buckets.get(key);
  if (!current || now - current.startedAt >= WINDOW_MS) {
    buckets.set(key, {startedAt: now, count: 1});
    pruneExpired(now);
    return;
  }
  current.count += 1;
  if (current.count > MAX_REQUESTS_PER_WINDOW) {
    throw new ClientError(
      429,
      "RATE_LIMITED",
      "Quá nhiều yêu cầu. Vui lòng thử lại sau một phút.",
    );
  }
}

function pruneExpired(now: number): void {
  if (buckets.size < 1_000) return;
  for (const [key, bucket] of buckets) {
    if (now - bucket.startedAt >= WINDOW_MS) buckets.delete(key);
  }
}
