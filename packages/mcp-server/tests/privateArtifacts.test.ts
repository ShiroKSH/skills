import * as fs from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, it, vi } from "vitest";
import { writePrivateArtifact } from "../src/tools/privateArtifacts.js";

vi.mock("node:fs/promises", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs/promises")>();
  return { ...actual, open: vi.fn(actual.open) };
});

afterEach(() => vi.restoreAllMocks());

it("writes exact bytes and restricts existing artifact directories on POSIX", async () => {
  const directory = await fs.mkdtemp(join(tmpdir(), "bridge-private-"));
  const path = join(directory, "model.rbxm");
  try {
    if (process.platform !== "win32") await fs.chmod(directory, 0o755);
    await writePrivateArtifact(directory, "model.rbxm", Buffer.from("model"));
    expect(await fs.readFile(path, "utf8")).toBe("model");
    if (process.platform !== "win32") {
      expect((await fs.stat(directory)).mode & 0o777).toBe(0o700);
      expect((await fs.stat(path)).mode & 0o777).toBe(0o600);
    }
  } finally {
    await fs.unlink(path).catch(() => {});
    await fs.rmdir(directory);
  }
});

it("does not remove a pre-existing file when exclusive creation fails", async () => {
  const directory = await fs.mkdtemp(join(tmpdir(), "bridge-collision-"));
  const path = join(directory, "model.rbxm");
  try {
    await fs.writeFile(path, "original");
    await expect(writePrivateArtifact(directory, "model.rbxm", Buffer.from("new"))).rejects.toThrow();
    expect(await fs.readFile(path, "utf8")).toBe("original");
  } finally {
    await fs.unlink(path);
    await fs.rmdir(directory);
  }
});

it("removes an owned partial file after a write error", async () => {
  const directory = await fs.mkdtemp(join(tmpdir(), "bridge-partial-"));
  const path = join(directory, "model.rbxm");
  const { open: realOpen } = await vi.importActual<typeof import("node:fs/promises")>("node:fs/promises");
  try {
    vi.mocked(fs.open).mockImplementationOnce(async (...args) => {
      const handle = await realOpen(...args);
      const write = handle.writeFile.bind(handle);
      vi.spyOn(handle, "writeFile").mockImplementationOnce(async () => {
        await write(Buffer.from("partial"));
        throw new Error("Expected disk failure");
      });
      return handle;
    });
    await expect(writePrivateArtifact(directory, "model.rbxm", Buffer.from("complete"))).rejects.toThrow("Expected disk failure");
    expect(await fs.readdir(directory)).toEqual([]);
  } finally {
    vi.restoreAllMocks();
    await fs.unlink(path).catch(() => {});
    await fs.rmdir(directory);
  }
});
