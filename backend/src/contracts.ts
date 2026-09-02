export type ExtractionRequest = Readonly<{
  requestId: string;
  locale: "vi-VN";
  text: string;
}>;

export type ClassificationRequest = Readonly<{
  requestId: string;
  locale: "vi-VN";
  merchant: string;
}>;

export type ChatFact = Readonly<{
  key: string;
  value: string;
}>;

export type ChatHistoryMessage = Readonly<{
  role: "user" | "assistant";
  text: string;
}>;

export type ChatRequest = Readonly<{
  requestId: string;
  locale: "vi-VN";
  question: string;
  facts: ChatFact[];
  history: ChatHistoryMessage[];
}>;

export type InvoiceItem = Readonly<{
  description: string;
  quantity: number | null;
  unitPriceMinor: number | null;
  taxRate: number | null;
  totalMinor: number;
}>;

export type ExtractedInvoice = Readonly<{
  sellerName: string;
  sellerTaxCode: string | null;
  invoiceNumber: string | null;
  invoiceSymbol: string | null;
  invoiceDate: string | null;
  currencyCode: string;
  subtotalMinor: number;
  taxMinor: number;
  totalMinor: number;
  categoryId: string;
  items: InvoiceItem[];
}>;

export type Evidence = Readonly<{
  field: string;
  rawValue: string | null;
  value: string;
  confidence: number;
}>;

export type ExtractionResponse = Readonly<{
  requestId: string;
  invoice: ExtractedInvoice;
  evidence: Evidence[];
  modelVersion: string;
}>;

const MAX_TEXT_LENGTH = 50_000;

export function parseExtractionRequest(value: unknown): ExtractionRequest {
  if (!isObject(value)) throw new ClientError(400, "INVALID_BODY", "Body phải là JSON object.");
  const requestId = value.requestId;
  const locale = value.locale;
  const text = value.text;
  if (typeof requestId !== "string" || requestId.length < 8 || requestId.length > 128) {
    throw new ClientError(400, "INVALID_REQUEST_ID", "requestId không hợp lệ.");
  }
  if (locale !== "vi-VN") {
    throw new ClientError(400, "UNSUPPORTED_LOCALE", "Chỉ hỗ trợ locale vi-VN.");
  }
  if (typeof text !== "string" || text.trim().length === 0) {
    throw new ClientError(400, "EMPTY_TEXT", "OCR text không được rỗng.");
  }
  if (text.length > MAX_TEXT_LENGTH) {
    throw new ClientError(413, "TEXT_TOO_LARGE", "OCR text vượt quá giới hạn.");
  }
  return {requestId, locale, text};
}

export function parseClassificationRequest(value: unknown): ClassificationRequest {
  if (!isObject(value)) throw new ClientError(400, "INVALID_BODY", "Body phải là JSON object.");
  const requestId = value.requestId;
  const locale = value.locale;
  const merchant = value.merchant;
  if (typeof requestId !== "string" || requestId.length < 8 || requestId.length > 128) {
    throw new ClientError(400, "INVALID_REQUEST_ID", "requestId không hợp lệ.");
  }
  if (locale !== "vi-VN") {
    throw new ClientError(400, "UNSUPPORTED_LOCALE", "Chỉ hỗ trợ locale vi-VN.");
  }
  if (typeof merchant !== "string" || merchant.trim().length < 2 || merchant.length > 300) {
    throw new ClientError(400, "INVALID_MERCHANT", "Tên merchant không hợp lệ.");
  }
  return {requestId, locale, merchant: merchant.trim()};
}

export function parseChatRequest(value: unknown): ChatRequest {
  if (!isObject(value)) throw new ClientError(400, "INVALID_BODY", "Body phải là JSON object.");
  const requestId = value.requestId;
  const locale = value.locale;
  const question = value.question;
  if (typeof requestId !== "string" || requestId.length < 8 || requestId.length > 128) {
    throw new ClientError(400, "INVALID_REQUEST_ID", "requestId không hợp lệ.");
  }
  if (locale !== "vi-VN") {
    throw new ClientError(400, "UNSUPPORTED_LOCALE", "Chỉ hỗ trợ locale vi-VN.");
  }
  if (typeof question !== "string" || question.trim().length < 2) {
    throw new ClientError(400, "EMPTY_QUESTION", "Câu hỏi không được rỗng.");
  }
  if (question.length > 2_000) {
    throw new ClientError(413, "QUESTION_TOO_LARGE", "Câu hỏi vượt quá giới hạn.");
  }
  const facts = parseChatFacts(value.facts);
  const history = parseChatHistory(value.history);
  return {requestId, locale, question: question.trim(), facts, history};
}

function parseChatFacts(value: unknown): ChatFact[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 40) {
    throw new ClientError(400, "INVALID_FACTS", "facts không hợp lệ.");
  }
  return value.map((item) => {
    if (!isObject(item) || typeof item.key !== "string" || typeof item.value !== "string") {
      throw new ClientError(400, "INVALID_FACT", "Một fact của chatbot không hợp lệ.");
    }
    if (item.key.length > 100 || item.value.length > 2_000) {
      throw new ClientError(413, "FACT_TOO_LARGE", "Fact chatbot vượt quá giới hạn.");
    }
    return {key: item.key, value: item.value};
  });
}

function parseChatHistory(value: unknown): ChatHistoryMessage[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 12) {
    throw new ClientError(400, "INVALID_HISTORY", "history không hợp lệ.");
  }
  return value.map((item) => {
    if (!isObject(item) || (item.role !== "user" && item.role !== "assistant") || typeof item.text !== "string") {
      throw new ClientError(400, "INVALID_HISTORY_MESSAGE", "Một tin nhắn chatbot không hợp lệ.");
    }
    if (item.text.trim().length === 0 || item.text.length > 4_000) {
      throw new ClientError(413, "HISTORY_MESSAGE_TOO_LARGE", "Tin nhắn chatbot vượt quá giới hạn.");
    }
    return {role: item.role, text: item.text.trim()};
  });
}

export class ClientError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
