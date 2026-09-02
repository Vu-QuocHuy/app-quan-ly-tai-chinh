import {getApps, initializeApp} from "firebase-admin/app";
import {getAppCheck} from "firebase-admin/app-check";
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions";
import {onRequest} from "firebase-functions/v2/https";

import {classifyMerchant} from "./classification.js";
import {answerChat} from "./chat.js";
import {
  ClientError,
  parseChatRequest,
  parseClassificationRequest,
  parseExtractionRequest,
} from "./contracts.js";
import {extractInvoice} from "./gemini.js";
import {enforceRateLimit} from "./rate_limiter.js";

const geminiApiKey = defineSecret("GEMINI_API_KEY");

if (getApps().length === 0) initializeApp();

export const api = onRequest(
  {
    region: "asia-southeast1",
    cors: true,
    timeoutSeconds: 30,
    memory: "256MiB",
    maxInstances: 10,
    secrets: [geminiApiKey],
  },
  async (request, response) => {
    response.set("Cache-Control", "no-store");
    try {
      if (request.method === "GET" && request.path === "/health") {
        response.status(200).json({status: "ok"});
        return;
      }
      if (request.method === "POST" && request.path === "/v1/extractions/ocr-text") {
        await requireAppCheck(request.header("X-Firebase-AppCheck"));
        enforceRateLimit(request.ip || "unknown");
        const input = parseExtractionRequest(request.body);
        const result = await extractInvoice(input, geminiApiKey.value());
        logger.info("invoice_extraction_completed", {requestId: input.requestId});
        response.status(200).json(result);
        return;
      }
      if (request.method === "POST" && request.path === "/v1/classifications") {
        await requireAppCheck(request.header("X-Firebase-AppCheck"));
        enforceRateLimit(request.ip || "unknown");
        const input = parseClassificationRequest(request.body);
        response.status(200).json(classifyMerchant(input));
        return;
      }
      if (request.method === "POST" && request.path === "/v1/chat") {
        await requireAppCheck(request.header("X-Firebase-AppCheck"));
        enforceRateLimit(request.ip || "unknown");
        const input = parseChatRequest(request.body);
        const result = await answerChat(input, geminiApiKey.value());
        logger.info("chat_completed", {requestId: input.requestId});
        response.status(200).json(result);
        return;
      }
      if (request.path === "/v1/qr/resolve") {
        response.status(501).json({
          code: "QR_EXPERIMENTAL_DISABLED",
          message: "QR provider adapter chưa được bật.",
        });
        return;
      }
      response.status(404).json({code: "NOT_FOUND", message: "Endpoint không tồn tại."});
    } catch (error: unknown) {
      if (error instanceof ClientError) {
        response.status(error.status).json({code: error.code, message: error.message});
        return;
      }
      logger.error("request_failed", {errorType: error instanceof Error ? error.name : "unknown"});
      response.status(500).json({code: "INTERNAL", message: "Không thể xử lý yêu cầu."});
    }
  },
);

async function requireAppCheck(token: string | undefined): Promise<void> {
  const emulatorBypass =
    process.env.FUNCTIONS_EMULATOR === "true" &&
    process.env.ALLOW_UNVERIFIED_APP_CHECK === "true";
  if (emulatorBypass) return;
  if (!token) {
    throw new ClientError(401, "APP_CHECK_REQUIRED", "Thiếu App Check token.");
  }
  try {
    await getAppCheck().verifyToken(token);
  } catch {
    throw new ClientError(401, "APP_CHECK_INVALID", "App Check token không hợp lệ.");
  }
}
