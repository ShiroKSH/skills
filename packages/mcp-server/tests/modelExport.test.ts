import { mkdtemp, readFile, readdir, rmdir, unlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { saveModelExport } from "../src/tools/modelExport.js";

describe("private model exports", () => {
  let directory: string;
  const data = Buffer.concat([Buffer.from("<roblox!"), Buffer.alloc(24)]);
  const result = { rootPath: "Workspace/MapDrafts/Cabin", byteLength: data.length, instanceCount: 3, data: data.toString("base64") };
  beforeEach(async () => { directory = await mkdtemp(join(tmpdir(), "studio-exports-")); });
  afterEach(async () => {
    for (const name of await readdir(directory)) await unlink(join(directory, name));
    await rmdir(directory);
  });

  it("writes unique binary artifacts without overwriting a previous export", async () => {
    const first = await saveModelExport(result, directory);
    const second = await saveModelExport(result, directory);
    expect(first.artifactPath).not.toBe(second.artifactPath);
    expect(await readFile(first.artifactPath)).toEqual(data);
  });

  it("does not interpret the root path as an output path", async () => {
    const saved = await saveModelExport({ ...result, rootPath: "../../private/../escape" }, directory);
    expect(dirname(saved.artifactPath)).toBe(directory);
  });

  it("rejects invalid signatures and inconsistent byte counts before writing", async () => {
    await expect(saveModelExport({ ...result, byteLength: 100 }, directory)).rejects.toThrow("invalid binary model");
    await expect(saveModelExport({ ...result, data: Buffer.alloc(32).toString("base64") }, directory)).rejects.toThrow("invalid binary model");
    expect(await readdir(directory)).toEqual([]);
  });
});
