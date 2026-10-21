import { mkdtemp, readFile, unlink, rmdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it } from "vitest";
import { CommandLogger } from "../src/logs/commandLogger.js";

it("redacts binary model and screenshot data alongside source and credentials", async () => {
  const directory = await mkdtemp(join(tmpdir(), "bridge-log-"));
  const path = join(directory, "commands.jsonl");
  try {
    await new CommandLogger(directory).log("command_result", {
      token: "private-token", result: { data: "private-binary", Source: "private-code", byteLength: 42 }
    });
    const entry = JSON.parse(await readFile(path, "utf8"));
    expect(entry.token).toBe("[redacted]");
    expect(entry.result).toEqual({ data: "[redacted]", Source: "[redacted]", byteLength: 42 });
  } finally {
    await unlink(path).catch(() => {});
    await rmdir(directory);
  }
});
