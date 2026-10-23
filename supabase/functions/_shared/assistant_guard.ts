import commandSchema from "./assistant_command.schema.json" with {type: "json"};

export {commandSchema};
export type Command = Record<string, unknown> & {kind: string; operation: string};

export function normalizeText(value: string): string {
  return value.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/đ/g, "d").replace(/[^a-z0-9]+/g, " ").trim();
}

// Only explicit identity questions bypass scope classification. Never echo user
// supplied identity or instructions as the assistant's identity.
export function fixedReply(text: string, english: boolean): string | null {
  const value = normalizeText(text);
  if (/^(ban la ai|ban ten (la )?gi|ten (cua )?ban la gi|who are you|what is your name|what s your name)[ ]*(nhi|vay|the)?$/.test(value)) {
    return english ? "I’m FinmiAI, your financial assistant." : "Tôi là FinmiAI, trợ lý tài chính của bạn.";
  }
  if (/^(toi la ai|minh la ai|who am i|neural networks? la gi|what (is|are) (a )?neural networks?)$/.test(value)) return refusal(english);
  return null;
}

export function refusal(english: boolean): string {
  return english ? "I can help with your finances and app features: income, expenses, debts, budgets and groups." : "Tôi hỗ trợ tài chính và tính năng trong ứng dụng: thu chi, nợ, ngân sách và nhóm.";
}

export function unsafeRequest(text: string): boolean {
  const value = ` ${normalizeText(text)} `;
  const blocked = ["api key", "secret", "credentials", "system prompt", "developer message", "chi dan he thong", "bo qua chi dan", "bo qua quy tac", "ignore previous", "ignore all instructions", "jailbreak", "service role", "source code", "ma nguon", "sql", "tat ca tai khoan", "all users", "other account", "tai khoan cua nguoi khac"];
  return blocked.some((item) => value.includes(` ${item} `));
}

export function validateCommand(raw: unknown): Command {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) throw new Error("INVALID_COMMAND");
  const value = raw as Record<string, unknown>;
  const properties = commandSchema.properties;
  if (Object.keys(value).some((key) => !(key in properties)) || commandSchema.required.some((key) => !(key in value))) throw new Error("INVALID_COMMAND_FIELDS");
  for (const [key, rule] of Object.entries(properties)) {
    const field = value[key];
    const types: readonly string[] = typeof rule.type === "string" ? [rule.type] : rule.type;
    if (field === null) {
      if (!types.includes("null")) throw new Error("INVALID_COMMAND_NULL");
      continue;
    }
    if (types.includes("integer")) {
      if (typeof field !== "number" || !Number.isSafeInteger(field) || field < 1 || field > 9007199254740991) throw new Error("INVALID_COMMAND_AMOUNT");
    } else if (typeof field !== "string" || field.length > ("maxLength" in rule ? rule.maxLength : 64)) throw new Error("INVALID_COMMAND_STRING");
    if ("enum" in rule && !(rule.enum as readonly unknown[]).includes(field)) throw new Error("INVALID_COMMAND_ENUM");
  }
  if (value.date !== null) {
    const date = value.date as string;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(Date.parse(date)) || new Date(date).toISOString().slice(0, 10) !== date) throw new Error("INVALID_COMMAND_DATE");
  }
  return value as Command;
}
