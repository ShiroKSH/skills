import { randomUUID } from "node:crypto";
import { resolve } from "node:path";
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { StudioBridge } from "../protocol.js";
import { writePrivateArtifact } from "./privateArtifacts.js";

export async function saveViewportCapture(result: unknown, directory = resolve("generated", "captures")) {
  const parsed = z.object({
    ok: z.literal(true),
    width: z.number().int().min(1).max(4096),
    height: z.number().int().min(1).max(4096),
    byteLength: z.number().int().min(33).max(8 * 1024 * 1024),
    data: z.string().max(12 * 1024 * 1024).regex(/^[A-Za-z0-9+/]+={0,2}$/)
  }).parse(result);
  const data = Buffer.from(parsed.data, "base64");
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (data.length !== parsed.byteLength || !data.subarray(0, 8).equals(signature)
    || data.subarray(12, 16).toString("ascii") !== "IHDR"
    || data.readUInt32BE(16) !== parsed.width || data.readUInt32BE(20) !== parsed.height) {
    throw new Error("Studio returned an invalid PNG viewport capture");
  }
  const artifactPath = await writePrivateArtifact(directory, `viewport_${randomUUID()}.png`, data);
  return { artifactPath, width: parsed.width, height: parsed.height, byteLength: data.length };
}

export function registerViewportCaptureTool(server: McpServer, bridge: StudioBridge) {
  server.registerTool("studio_capture_viewport", {
    description: "Capture only the Roblox 3D viewport as a private local PNG without desktop or Studio panels. Never opens a permission prompt.",
    inputSchema: {
      width: z.number().int().min(1).max(4096).optional(),
      height: z.number().int().min(1).max(4096).optional()
    }
  }, async (args) => {
    const result = await bridge.sendCommand("studio_capture_viewport", args, 25_000);
    if (typeof result === "object" && result && "ok" in result && result.ok === false) {
      return { content: [{ type: "text" as const, text: JSON.stringify(result) }], isError: true };
    }
    const artifact = await saveViewportCapture(result);
    return { content: [{ type: "text" as const, text: JSON.stringify(artifact) }] };
  });
}
