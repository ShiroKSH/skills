import { mkdir, appendFile } from "node:fs/promises";
import { join } from "node:path";

type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue | undefined };

const REDACTED_KEYS = new Set([
  "authorization",
  "auth",
  "code",
  "confirmtoken",
  "cookie",
  "data",
  "password",
  "secret",
  "source",
  "token"
]);

function redact(value: unknown): JsonValue {
  if (value === null || typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    return value;
  }

  if (Array.isArray(value)) {
    return value.slice(0, 50).map((item) => redact(item));
  }

  if (typeof value === "object") {
    const output: Record<string, JsonValue> = {};
    for (const [key, inner] of Object.entries(value as Record<string, unknown>)) {
      output[key] = REDACTED_KEYS.has(key.toLowerCase()) ? "[redacted]" : redact(inner);
    }
    return output;
  }

  return String(value);
}

export class CommandLogger {
  private readonly filePath: string;

  constructor(private readonly logsDir: string) {
    this.filePath = join(logsDir, "commands.jsonl");
  }

  async log(event: string, payload: Record<string, unknown>): Promise<void> {
    await mkdir(this.logsDir, { recursive: true });
    const safePayload = redact(payload) as Record<string, JsonValue | undefined>;
    const line = JSON.stringify({
      at: new Date().toISOString(),
      event,
      ...safePayload
    });
    await appendFile(this.filePath, `${line}\n`, "utf8");
  }
}
