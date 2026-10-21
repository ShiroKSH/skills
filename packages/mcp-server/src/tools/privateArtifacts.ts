import { chmod, mkdir, open, unlink } from "node:fs/promises";
import { join } from "node:path";

export async function writePrivateArtifact(directory: string, filename: string, data: Uint8Array): Promise<string> {
  await mkdir(directory, { recursive: true, mode: 0o700 });
  if (process.platform !== "win32") await chmod(directory, 0o700);
  const path = join(directory, filename);
  const file = await open(path, "wx", 0o600);
  try {
    await file.writeFile(data);
    await file.close();
  } catch (error) {
    await file.close().catch(() => {});
    await unlink(path).catch(() => {});
    throw error;
  }
  return path;
}
