import type {ExtractedInvoice, ExtractionRequest, ExtractionResponse} from "./contracts.js";
import {ClientError, isObject} from "./contracts.js";

const MODEL = process.env.GEMINI_MODEL ?? "gemini-2.5-flash";
const API_ROOT = "https://generativelanguage.googleapis.com/v1beta";

const responseSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "sellerName",
    "sellerTaxCode",
    "invoiceNumber",
    "invoiceSymbol",
    "invoiceDate",
    "currencyCode",
    "subtotalMinor",
    "taxMinor",
    "totalMinor",
    "categoryId",
    "items",
  ],
  properties: {
    sellerName: {type: "string"},
    sellerTaxCode: {type: ["string", "null"]},
    invoiceNumber: {type: ["string", "null"]},
    invoiceSymbol: {type: ["string", "null"]},
    invoiceDate: {type: ["string", "null"], description: "ISO-8601 date YYYY-MM-DD"},
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
        required: ["description", "quantity", "unitPriceMinor", "taxRate", "totalMinor"],
        properties: {
          description: {type: "string"},
          quantity: {type: ["number", "null"], minimum: 0},
          unitPriceMinor: {type: ["integer", "null"], minimum: 0},
          taxRate: {type: ["number", "null"], minimum: 0, maximum: 100},
          totalMinor: {type: "integer", minimum: 0},
        },
      },
    },
  },
} as const;

export async function extractInvoice(
  request: ExtractionRequest,
  apiKey: string,
): Promise<ExtractionResponse> {
  const prompt = [
    "Trích xuất hóa đơn/biên lai Việt Nam từ OCR text.",
    "Không suy đoán trường không nhìn thấy; dùng null hoặc 0.",
    "Tiền dùng số nguyên theo đơn vị nhỏ nhất; với VND giữ nguyên số đồng.",
    "Đối chiếu tổng tiền nhưng không tự sửa số liệu để ép khớp.",
    "OCR text:",
    request.text,
  ].join("\n");
  const requestBody = JSON.stringify({
    contents: [{role: "user", parts: [{text: prompt}]}],
    generationConfig: {
      temperature: 0.1,
      responseMimeType: "application/json",
      responseJsonSchema: responseSchema,
    },
  });
  let response: Response | undefined;
  try {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      response = await fetch(`${API_ROOT}/models/${MODEL}:generateContent`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: requestBody,
        signal: AbortSignal.timeout(15_000),
      });
      if (response.ok) break;
      const retryable = response.status === 429 || response.status >= 500;
      if (!retryable || attempt === 1) {
        throw new ClientError(502, "MODEL_ERROR", `Gemini trả lỗi ${response.status}.`);
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  } catch (error: unknown) {
    if (error instanceof ClientError) throw error;
    throw new ClientError(504, "MODEL_TIMEOUT", "Gemini không phản hồi đúng hạn.");
  }
  if (!response?.ok) {
    throw new ClientError(502, "MODEL_ERROR", "Gemini không thể xử lý yêu cầu.");
  }
  const payload: unknown = await response.json();
  const text = modelText(payload);
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new ClientError(502, "INVALID_MODEL_JSON", "Model không trả JSON hợp lệ.");
  }
  const invoice = validateInvoice(parsed);
  return {
    requestId: request.requestId,
    invoice,
    evidence: coreEvidence(invoice),
    modelVersion: MODEL,
  };
}

function modelText(payload: unknown): string {
  if (!isObject(payload)) throw new ClientError(502, "INVALID_MODEL_RESPONSE", "Model response không hợp lệ.");
  const candidates = payload.candidates;
  if (!Array.isArray(candidates) || !isObject(candidates[0])) {
    throw new ClientError(502, "EMPTY_MODEL_RESPONSE", "Model không trả dữ liệu.");
  }
  const content = candidates[0].content;
  if (!isObject(content) || !Array.isArray(content.parts) || !isObject(content.parts[0])) {
    throw new ClientError(502, "EMPTY_MODEL_RESPONSE", "Model không trả nội dung.");
  }
  const text = content.parts[0].text;
  if (typeof text !== "string") throw new ClientError(502, "EMPTY_MODEL_RESPONSE", "Model không trả JSON.");
  return text;
}

function validateInvoice(value: unknown): ExtractedInvoice {
  if (!isObject(value) || typeof value.sellerName !== "string") {
    throw new ClientError(502, "INVALID_MODEL_RESPONSE", "Dữ liệu model sai schema.");
  }
  const amountKeys = ["subtotalMinor", "taxMinor", "totalMinor"] as const;
  for (const key of amountKeys) {
    if (!Number.isSafeInteger(value[key]) || (value[key] as number) < 0) {
      throw new ClientError(502, "INVALID_AMOUNT", `Trường ${key} không hợp lệ.`);
    }
  }
  return value as unknown as ExtractedInvoice;
}

function coreEvidence(invoice: ExtractedInvoice) {
  return [
    {field: "sellerName", rawValue: invoice.sellerName, value: invoice.sellerName, confidence: 0.75},
    {field: "totalMinor", rawValue: String(invoice.totalMinor), value: String(invoice.totalMinor), confidence: 0.75},
  ];
}
