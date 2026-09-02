import type {ClassificationRequest} from "./contracts.js";

type ClassificationResponse = Readonly<{
  requestId: string;
  categoryId: string;
  confidence: number;
  classifierVersion: string;
}>;

const rules: ReadonlyArray<Readonly<{categoryId: string; keywords: readonly string[]}>> = [
  {categoryId: "food", keywords: ["restaurant", "cafe", "coffee", "food", "mart", "quan an", "nha hang"]},
  {categoryId: "transport", keywords: ["grab", "taxi", "transport", "xang", "petrol", "parking"]},
  {categoryId: "utilities", keywords: ["electric", "water", "internet", "telecom", "dien luc", "cap nuoc"]},
  {categoryId: "health", keywords: ["hospital", "clinic", "pharmacy", "benh vien", "nha thuoc"]},
  {categoryId: "education", keywords: ["school", "academy", "education", "truong", "giao duc"]},
  {categoryId: "entertainment", keywords: ["cinema", "movie", "game", "theater", "rap phim"]},
  {categoryId: "shopping", keywords: ["shop", "store", "mall", "retail", "shopping"]},
];

export function classifyMerchant(request: ClassificationRequest): ClassificationResponse {
  const merchant = normalize(request.merchant);
  const match = rules.find((rule) => rule.keywords.some((keyword) => merchant.includes(keyword)));
  return {
    requestId: request.requestId,
    categoryId: match?.categoryId ?? "other",
    confidence: match ? 0.8 : 0.35,
    classifierVersion: "merchant-rules-v1",
  };
}

function normalize(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}
