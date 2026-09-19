type JsonObject = Record<string, unknown>;

type ExtractionJob = {
  id: string;
  request_id: string;
  input_path: string;
  input_kind: "text" | "image";
  input_mime_type: string | null;
  attempt_count: number;
  max_attempts: number;
};

type ExpiredInput = {
  id: string;
  input_path: string;
};

class WorkerError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
  }
}

const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
const apiRoot = "https://generativelanguage.googleapis.com/v1beta";
const maxTextLength = 50_000;
const maxImageBytes = 15_000_000;
const batchSize = configuredInteger("AI_WORKER_BATCH_SIZE", 3, 1, 10);
const supportedCurrencies = new Set(["VND", "USD", "EUR", "JPY", "CNY"]);
const supportedCategories = new Set([
  "food", "transport", "shopping", "utilities", "health", "education",
  "entertainment", "other",
]);
const supportedImageMimeTypes = new Set(["image/jpeg", "image/png", "image/webp"]);

const invoiceSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "sellerName", "sellerTaxCode", "invoiceNumber", "invoiceSymbol",
    "invoiceDate", "currencyCode", "subtotalMinor", "taxMinor",
    "totalMinor", "categoryId", "items",
  ],
  properties: {
    sellerName: {type: "string"},
    sellerTaxCode: {type: ["string", "null"]},
    invoiceNumber: {type: ["string", "null"]},
    invoiceSymbol: {type: ["string", "null"]},
    invoiceDate: {type: ["string", "null"]},
    currencyCode: {type: "string", enum: ["VND", "USD", "EUR", "JPY", "CNY"]},
    subtotalMinor: {type: "integer", minimum: 0},
    taxMinor: {type: "integer", minimum: 0},
    totalMinor: {type: "integer", minimum: 0},
    categoryId: {
      type: "string",
      enum: ["food", "transport", "shopping", "utilities", "health", "education", "entertainment", "other"],
    },
    items: {
      type: "array",
      maxItems: 200,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["description", "quantity", "unitPriceMinor", "taxRate", "totalMinor", "categoryId"],
        properties: {
          description: {type: "string"},
          quantity: {type: ["number", "null"], minimum: 0},
          unitPriceMinor: {type: ["integer", "null"], minimum: 0},
          taxRate: {type: ["number", "null"], minimum: 0, maximum: 100},
          totalMinor: {type: "integer", minimum: 0},
          categoryId: {
            type: "string",
            enum: ["food", "transport", "shopping", "utilities", "health", "education", "entertainment", "other"],
          },
        },
      },
    },
  },
} as const;

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({code: "METHOD_NOT_ALLOWED"}, 405);
  }
  if (!workerAuthorized(request)) {
    return json({code: "WORKER_UNAUTHORIZED"}, 401);
  }
  const startedAt = Date.now();
  try {
    await cleanupExpiredInputs();
    await cleanupMetrics();
    await cleanupSyncMetrics();
    await cleanupCostUsage();
    await cleanupJobs();
    await cleanupClientErrors();
    const jobs = await claimJobs();
    let succeeded = 0;
    let failed = 0;
    for (const job of jobs) {
      try {
        const result = await processJob(job);
        await finishJob(job.id, true, result);
        await deleteInput(job.input_path);
        succeeded += 1;
      } catch (error) {
        const code = error instanceof WorkerError ? error.code : "WORKER_FAILED";
        try {
          await finishJob(job.id, false, null, code);
        } catch {
        }
        console.warn("ai_job_failed", JSON.stringify({code}));
        failed += 1;
      }
    }
    console.log("ai_worker_completed", JSON.stringify({
      claimed: jobs.length,
      succeeded,
      failed,
      durationMs: Date.now() - startedAt,
    }));
    return json({claimed: jobs.length, succeeded, failed});
  } catch (error) {
    const code = error instanceof WorkerError ? error.code : "WORKER_FAILED";
    console.error("ai_worker_failed", JSON.stringify({code, durationMs: Date.now() - startedAt}));
    return json({code: "WORKER_FAILED"}, 503);
  }
});

async function claimJobs(): Promise<ExtractionJob[]> {
  const rows = await adminJson("/rest/v1/rpc/claim_ai_extraction_jobs", {
    method: "POST",
    body: JSON.stringify({p_limit: batchSize}),
  });
  if (!Array.isArray(rows)) throw new WorkerError("CLAIM_FAILED", "Không nhận được job.");
  return rows.filter(isExtractionJob);
}

async function processJob(job: ExtractionJob): Promise<JsonObject> {
  if (!isSafeInputPath(job.input_path)) {
    throw new WorkerError("INPUT_PATH_INVALID", "Đường dẫn input không hợp lệ.");
  }
  const bytes = await downloadInput(job.input_path);
  if (job.input_kind === "text") {
    const text = new TextDecoder().decode(bytes).trim();
    if (!text || text.length > maxTextLength) throw new WorkerError("TEXT_INVALID", "OCR text không hợp lệ.");
    const invoice = await generateInvoice(text);
    return extractionResult(job.request_id, invoice);
  }
  if (bytes.length > maxImageBytes || !job.input_mime_type ||
      !supportedImageMimeTypes.has(job.input_mime_type)) {
    throw new WorkerError("IMAGE_INVALID", "Ảnh input không hợp lệ.");
  }
  const invoice = await generateInvoice(undefined, {
    mimeType: job.input_mime_type,
    data: encodeBase64(bytes),
  });
  return extractionResult(job.request_id, invoice);
}

function extractionResult(requestId: string, invoice: JsonObject): JsonObject {
  validateInvoice(invoice);
  return {
    requestId,
    invoice,
    evidence: [
      {field: "sellerName", rawValue: invoice.sellerName, value: invoice.sellerName, confidence: 0.75},
      {field: "totalMinor", rawValue: String(invoice.totalMinor), value: String(invoice.totalMinor), confidence: 0.75},
    ],
    modelVersion: model,
  };
}

async function generateInvoice(text?: string, image?: {mimeType: string; data: string}): Promise<JsonObject> {
  const apiKey = Deno.env.get("GEMINI_API_KEY")?.trim();
  if (!apiKey) throw new WorkerError("AI_NOT_CONFIGURED", "Gemini chưa được cấu hình.");
  const prompt = [
    "Trích xuất hóa đơn/biên lai Việt Nam từ OCR text.",
    "Không suy đoán trường không nhìn thấy; dùng null hoặc 0.",
    "Tiền dùng số nguyên theo đơn vị nhỏ nhất; với VND giữ nguyên số đồng.",
    "Đối chiếu tổng tiền nhưng không tự sửa số liệu để ép khớp.",
    "Phân loại từng mặt hàng vào đúng categoryId dựa trên mô tả; nếu không chắc dùng other.",
    text ? "OCR text:" : "Phân tích trực tiếp ảnh hóa đơn đính kèm:",
    ...(text ? [text] : []),
  ].join("\n");
  const response = await fetch(apiRoot + "/models/" + model + ":generateContent", {
    method: "POST",
    headers: {"Content-Type": "application/json", "x-goog-api-key": apiKey},
    body: JSON.stringify({
      contents: [{
        role: "user",
        parts: [
          {text: prompt},
          ...(image ? [{inlineData: {mimeType: image.mimeType, data: image.data}}] : []),
        ],
      }],
      generationConfig: {
        temperature: 0.1,
        responseMimeType: "application/json",
        responseJsonSchema: invoiceSchema,
      },
    }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new WorkerError(response.status === 429 ? "MODEL_RATE_LIMITED" : "MODEL_ERROR", "Model không xử lý được job.");
  const payload: unknown = await response.json();
  if (!isObject(payload) || !Array.isArray(payload.candidates) || !isObject(payload.candidates[0])) {
    throw new WorkerError("EMPTY_MODEL_RESPONSE", "Model không trả dữ liệu.");
  }
  const content = payload.candidates[0].content;
  if (!isObject(content) || !Array.isArray(content.parts) || !isObject(content.parts[0]) || typeof content.parts[0].text !== "string") {
    throw new WorkerError("EMPTY_MODEL_RESPONSE", "Model không trả nội dung.");
  }
  try {
    const value: unknown = JSON.parse(content.parts[0].text);
    if (!isObject(value)) throw new Error("not-object");
    return value;
  } catch {
    throw new WorkerError("INVALID_MODEL_JSON", "Model không trả JSON hợp lệ.");
  }
}

function validateInvoice(value: JsonObject): void {
  if (typeof value.sellerName !== "string" || value.sellerName.trim().length === 0 || value.sellerName.length > 500) {
    throw new WorkerError("INVALID_MODEL_RESPONSE", "Tên bên bán không hợp lệ.");
  }
  for (const key of ["sellerTaxCode", "invoiceNumber", "invoiceSymbol"]) {
    const field = value[key];
    if (field !== null && field !== undefined && (typeof field !== "string" || field.length > 300)) {
      throw new WorkerError("INVALID_MODEL_RESPONSE", "Trường hóa đơn không hợp lệ.");
    }
  }
  if (value.invoiceDate !== null && value.invoiceDate !== undefined &&
      (typeof value.invoiceDate !== "string" || Date.parse(value.invoiceDate) !== Date.parse(value.invoiceDate))) {
    throw new WorkerError("INVALID_MODEL_RESPONSE", "Ngày hóa đơn không hợp lệ.");
  }
  if (typeof value.currencyCode !== "string" || !supportedCurrencies.has(value.currencyCode)) {
    throw new WorkerError("INVALID_MODEL_RESPONSE", "Loại tiền không hợp lệ.");
  }
  if (typeof value.categoryId !== "string" || !supportedCategories.has(value.categoryId)) {
    throw new WorkerError("INVALID_MODEL_RESPONSE", "Danh mục hóa đơn không hợp lệ.");
  }
  for (const key of ["subtotalMinor", "taxMinor", "totalMinor"]) {
    const amount = value[key];
    if (typeof amount !== "number" || !Number.isSafeInteger(amount) || amount < 0) {
      throw new WorkerError("INVALID_AMOUNT", "Model trả số tiền không hợp lệ.");
    }
  }
  if (!Array.isArray(value.items) || value.items.length > 200) {
    throw new WorkerError("INVALID_MODEL_RESPONSE", "Danh sách hàng hóa không hợp lệ.");
  }
  for (const item of value.items) {
    if (!isObject(item) || typeof item.description !== "string" ||
        item.description.trim().length === 0 || item.description.length > 500 ||
        typeof item.categoryId !== "string" || !supportedCategories.has(item.categoryId)) {
      throw new WorkerError("INVALID_MODEL_RESPONSE", "Dòng hàng hóa không hợp lệ.");
    }
    const quantity = item.quantity;
    if (quantity !== null && quantity !== undefined &&
        (typeof quantity !== "number" || !Number.isFinite(quantity) || quantity < 0)) {
      throw new WorkerError("INVALID_MODEL_RESPONSE", "Số lượng hàng hóa không hợp lệ.");
    }
    const unitPrice = item.unitPriceMinor;
    if (unitPrice !== null && unitPrice !== undefined &&
        (typeof unitPrice !== "number" || !Number.isSafeInteger(unitPrice) || unitPrice < 0)) {
      throw new WorkerError("INVALID_AMOUNT", "Đơn giá hàng hóa không hợp lệ.");
    }
    if (item.taxRate !== null && item.taxRate !== undefined &&
        (typeof item.taxRate !== "number" || !Number.isFinite(item.taxRate) || item.taxRate < 0 || item.taxRate > 100)) {
      throw new WorkerError("INVALID_MODEL_RESPONSE", "Thuế suất hàng hóa không hợp lệ.");
    }
    if (typeof item.totalMinor !== "number" || !Number.isSafeInteger(item.totalMinor) || item.totalMinor < 0) {
      throw new WorkerError("INVALID_AMOUNT", "Thành tiền hàng hóa không hợp lệ.");
    }
  }
}

async function downloadInput(path: string): Promise<Uint8Array> {
  const response = await adminFetch("/storage/v1/object/ai-inputs/" + storageObjectPath(path), {
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new WorkerError("INPUT_NOT_FOUND", "Không đọc được input.");
  return new Uint8Array(await response.arrayBuffer());
}

async function deleteInput(path: string): Promise<boolean> {
  try {
    const response = await adminFetch("/storage/v1/object/ai-inputs/" + storageObjectPath(path), {
      method: "DELETE",
      signal: AbortSignal.timeout(5_000),
    });
    return response.ok || response.status === 404;
  } catch {
    return false;
  }
}

async function finishJob(id: string, succeeded: boolean, result: JsonObject | null, errorCode?: string): Promise<void> {
  await adminJson("/rest/v1/rpc/finish_ai_extraction_job", {
    method: "POST",
    body: JSON.stringify({
      p_job_id: id,
      p_succeeded: succeeded,
      p_result: result,
      p_error_code: errorCode ?? null,
    }),
  });
}

async function cleanupExpiredInputs(): Promise<void> {
  let rows: unknown;
  try {
    rows = await adminJson("/rest/v1/rpc/cleanup_ai_extraction_inputs", {method: "POST"});
  } catch {
    return;
  }
  if (!Array.isArray(rows)) return;
  for (const row of rows) {
    if (!isExpiredInput(row) || !isSafeInputPath(row.input_path)) continue;
    if (await deleteInput(row.input_path)) {
      try {
        await adminJson("/rest/v1/rpc/mark_ai_extraction_input_deleted", {
          method: "POST",
          body: JSON.stringify({
            p_job_id: row.id,
            p_input_path: row.input_path,
          }),
        });
      } catch {
      }
    }
  }
}

async function cleanupMetrics(): Promise<void> {
  try {
    await adminJson("/rest/v1/rpc/cleanup_ai_request_metrics", {
      method: "POST",
      body: JSON.stringify({p_retention_days: 30}),
    });
  } catch {
  }
}

async function cleanupSyncMetrics(): Promise<void> {
  try {
    await adminJson("/rest/v1/rpc/cleanup_sync_request_metrics", {
      method: "POST",
      body: JSON.stringify({p_retention_days: 30}),
    });
  } catch {
  }
}

async function cleanupCostUsage(): Promise<void> {
  try {
    await adminJson("/rest/v1/rpc/cleanup_ai_cost_usage", {
      method: "POST",
      body: JSON.stringify({p_retention_days: 400}),
    });
  } catch {
  }
}

async function cleanupJobs(): Promise<void> {
  try {
    await adminJson("/rest/v1/rpc/cleanup_ai_extraction_jobs", {
      method: "POST",
      body: JSON.stringify({p_retention_days: 30}),
    });
  } catch {
  }
}

async function cleanupClientErrors(): Promise<void> {
  try {
    await adminJson("/rest/v1/rpc/cleanup_client_error_events", {
      method: "POST",
      body: JSON.stringify({p_retention_days: 30}),
    });
  } catch {
  }
}

function isExpiredInput(value: unknown): value is ExpiredInput {
  return isObject(value) &&
    typeof value.id === "string" &&
    typeof value.input_path === "string";
}

async function adminJson(path: string, init: RequestInit = {}): Promise<unknown> {
  const response = await adminFetch(path, init);
  if (!response.ok) throw new WorkerError("BACKEND_UNAVAILABLE", "Không truy cập được backend.");
  const body = await response.text();
  if (!body) return null;
  try {
    return JSON.parse(body);
  } catch {
    throw new WorkerError("INVALID_BACKEND_RESPONSE", "Backend trả dữ liệu không hợp lệ.");
  }
}

function storageObjectPath(path: string): string {
  return path.split("/").map((segment) => encodeURIComponent(segment)).join("/");
}

async function adminFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const url = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!url || !serviceKey) throw new WorkerError("BACKEND_NOT_CONFIGURED", "Worker chưa được cấu hình.");
  const headers = new Headers(init.headers);
  headers.set("apikey", serviceKey);
  headers.set("Authorization", "Bearer " + serviceKey);
  if (init.body != null) headers.set("Content-Type", "application/json");
  return fetch(url + path, {
    ...init,
    headers,
    signal: init.signal ?? AbortSignal.timeout(5_000),
  });
}

function workerAuthorized(request: Request): boolean {
  const expected = Deno.env.get("AI_WORKER_SECRET")?.trim();
  const actual = request.headers.get("X-Worker-Secret")?.trim();
  return expected != null && expected.length >= 32 && actual === expected;
}

function isSafeInputPath(path: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.input$/i.test(path);
}

function isExtractionJob(value: unknown): value is ExtractionJob {
  return isObject(value) &&
    typeof value.id === "string" &&
    typeof value.request_id === "string" &&
    typeof value.input_path === "string" &&
    (value.input_kind === "text" || value.input_kind === "image") &&
    (value.input_mime_type == null || typeof value.input_mime_type === "string") &&
    typeof value.attempt_count === "number" &&
    typeof value.max_attempts === "number";
}

function encodeBase64(bytes: Uint8Array): string {
  let value = "";
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value);
}

function configuredInteger(name: string, fallback: number, minimum: number, maximum: number): number {
  const value = Number.parseInt(Deno.env.get(name) ?? "", 10);
  return Number.isInteger(value) && value >= minimum && value <= maximum ? value : fallback;
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function json(body: JsonObject, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {"Content-Type": "application/json; charset=utf-8"},
  });
}
