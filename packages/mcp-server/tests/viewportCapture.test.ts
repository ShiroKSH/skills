import { mkdtemp, readFile, readdir, unlink, rmdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { saveViewportCapture } from "../src/tools/viewportCapture.js";

const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64");
const result = { ok: true, width: 1, height: 1, byteLength: png.length, data: png.toString("base64") };

describe("private viewport captures", () => {
  it("saves exact PNG bytes with unique local filenames", async () => {
    const directory = await mkdtemp(join(tmpdir(), "studio-viewport-"));
    try {
      const first = await saveViewportCapture(result, directory);
      const second = await saveViewportCapture(result, directory);
      expect(first.artifactPath).not.toBe(second.artifactPath);
      expect(await readFile(first.artifactPath)).toEqual(png);
    } finally {
      for (const name of await readdir(directory)) await unlink(join(directory, name));
      await rmdir(directory);
    }
  });

  it("rejects wrong signatures, sizes, dimensions, and denied captures before writing", async () => {
    const directory = await mkdtemp(join(tmpdir(), "studio-invalid-viewport-"));
    try {
      for (const invalid of [
      { ...result, data: Buffer.alloc(png.length).toString("base64") },
      { ...result, byteLength: png.length + 1 },
      { ...result, width: 2 },
      { ...result, height: 2 },
      { ok: false, permissionRequired: true }
      ]) {
        await expect(saveViewportCapture(invalid, directory)).rejects.toThrow();
      }
      expect(await readdir(directory)).toEqual([]);
    } finally {
      for (const name of await readdir(directory)) await unlink(join(directory, name));
      await rmdir(directory);
    }
  });
});
