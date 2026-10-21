import { chmod, lstat, mkdir, open, unlink } from "node:fs/promises";
import { join } from "node:path";

export async function writePrivateArtifact(directory: string, filename: string, data: Uint8Array): Promise<string> {
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const directoryInfo = await lstat(directory);
  if (directoryInfo.isSymbolicLink() || !directoryInfo.isDirectory()) {
    throw new Error("Artifact directory must be a real directory, not a symbolic link");
  }
  if (process.platform !== "win32") await chmod(directory, 0o700);
  const path = join(directory, filename);
  const file = await open(path, "wx", 0o600);
  try {
    await file.writeFile(data);
    await file.close();
  } catch (error) {
    await file.close().catch(() => {});
    try {
      await unlink(path);
    } catch (cleanupError) {
      throw new AggregateError([error, cleanupError], `Artifact write and cleanup failed for ${path}`, { cause: error });
    }
    throw error;
  }
  return path;
}
