#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { loadConfig } from "./security/config.js";
import { CommandLogger } from "./logs/commandLogger.js";
import { StudioBridge } from "./protocol.js";
import { registerBridgeTools } from "./tools/registry.js";

const config = loadConfig();

if (config.tokenWasGenerated) {
  console.error(
    `[roblox-studio] Generated one-time plugin token: ${config.token}\n` +
      "[roblox-studio] Paste it into the Studio plugin, or set ROBLOX_STUDIO_BRIDGE_TOKEN."
  );
}

const logger = new CommandLogger(config.logsDir);
const bridge = new StudioBridge(config, logger);
await bridge.start();

const server = new McpServer({
  name: "roblox-studio",
  version: "0.2.1"
});

registerBridgeTools(server, bridge, config);

const transport = new StdioServerTransport();
await server.connect(transport);

const shutdown = async () => {
  await bridge.stop();
  process.exit(0);
};

process.once("SIGINT", () => {
  void shutdown();
});
process.once("SIGTERM", () => {
  void shutdown();
});
