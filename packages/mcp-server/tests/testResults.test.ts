import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { expect, it, vi } from "vitest";
import type { StudioBridge } from "../src/protocol.js";
import { loadConfig } from "../src/security/config.js";
import { registerBridgeTools } from "../src/tools/registry.js";

it.each([
  { ok: true, result: { passed: 1 } },
  { ok: false, error: "Assertion failed" },
  { ok: false, error: "Test deadline exceeded", timedOut: true }
])("propagates native test status through MCP $ok $error", async (result) => {
  const server = new McpServer({ name: "test-server", version: "1" });
  const client = new Client({ name: "test-client", version: "1" });
  const bridge = { sendCommand: vi.fn().mockResolvedValue(result) } as unknown as StudioBridge;
  registerBridgeTools(server, bridge, loadConfig({ ROBLOX_STUDIO_BRIDGE_TOKEN: "test-only-contract-token-not-a-credential" }));
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  try {
    const response = await client.callTool({ name: "studio_run_test", arguments: {
      modulePath: "Workspace/MapDrafts/Fixture/Test", confirmToken: "RUN_STUDIO_TEST"
    } });
    expect(response.isError).toBe(result.ok === false);
    const text = response.content.find(item => item.type === "text");
    expect(text && JSON.parse(text.text)).toEqual(result);
  } finally {
    await client.close();
    await server.close();
  }
});
