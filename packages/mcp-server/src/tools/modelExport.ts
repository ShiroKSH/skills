import { randomUUID } from "node:crypto";
import { resolve } from "node:path";
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { StudioBridge } from "../protocol.js";
import { writePrivateArtifact } from "./privateArtifacts.js";

export async function saveModelExport(result: unknown, directory = resolve("generated", "exports")) {
  const parsed = z.object({
    rootPath: z.string(),
    instanceCount: z.number().int().min(1).max(10000),
    byteLength: z.number().int().min(8).max(8 * 1024 * 1024),
    data: z.string().max(12 * 1024 * 1024).regex(/^[A-Za-z0-9+/]+={0,2}$/)
  }).parse(result);
  const data = Buffer.from(parsed.data, "base64");
  if (data.length !== parsed.byteLength || data.subarray(0, 8).toString("ascii") !== "<roblox!") {
    throw new Error("Studio returned an invalid binary model export");
  }
  const name = parsed.rootPath.split("/").at(-1)!.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 80) || "map";
  const artifactPath = await writePrivateArtifact(directory, `${name}_${randomUUID()}.rbxm`, data);
  return { artifactPath, rootPath: parsed.rootPath, byteLength: data.length, instanceCount: parsed.instanceCount };
}

export function registerModelExportTool(server: McpServer, bridge: StudioBridge) {
  server.registerTool("studio_export_model", {
    description: "Save a managed build root as a private local binary Roblox model under generated/exports.",
    inputSchema: { rootPath: z.string().min(1) }
  }, async (args) => {
    const result = await bridge.sendCommand("studio_export_model", args, 60_000);
    const artifact = await saveModelExport(result);
    return { content: [{ type: "text" as const, text: JSON.stringify(artifact) }] };
  });
}
