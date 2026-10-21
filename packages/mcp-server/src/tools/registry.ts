import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { BridgeConfig } from "../security/config.js";
import type { StudioBridge } from "../protocol.js";
import { parseSceneSpec } from "../schema/sceneSpec.js";
import { planSceneSpec } from "./scenePlan.js";
import { validateLuauForDangerousExecution } from "../security/luauSafety.js";
import { writeRojoArtifacts } from "./rojoArtifacts.js";
import { registerModelExportTool } from "./modelExport.js";
import { registerViewportCaptureTool } from "./viewportCapture.js";

function jsonResult(data: unknown) {
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(data, null, 2)
      }
    ]
  };
}

async function dispatch(bridge: StudioBridge, name: string, args: unknown, timeoutMs?: number) {
  const result = await bridge.sendCommand(name, args, timeoutMs);
  return jsonResult(result);
}

async function writeManifest(config: BridgeConfig, sceneSpec: unknown, applyResult: unknown): Promise<string> {
  const safeMapName =
    typeof sceneSpec === "object" && sceneSpec && "mapName" in sceneSpec
      ? String((sceneSpec as { mapName?: unknown }).mapName).replace(/[^A-Za-z0-9_-]/g, "_")
      : "map";
  const manifestDir = join(config.logsDir, "manifests", `${safeMapName}_${Date.now()}`);
  await mkdir(manifestDir, { recursive: true });
  const manifestPath = join(manifestDir, "map_manifest.json");
  await writeFile(
    manifestPath,
    JSON.stringify(
      {
        createdAt: new Date().toISOString(),
        sceneSpec,
        result: applyResult
      },
      null,
      2
    ),
    "utf8"
  );
  return manifestPath;
}

function requireDeleteToken(input: { confirmToken?: string; requireConfirmToken?: string }, config: BridgeConfig): void {
  const supplied = input.confirmToken ?? input.requireConfirmToken;
  if (supplied !== config.deleteConfirmToken) {
    throw new Error("studio_delete_instances requires a valid confirmToken.");
  }
}

export function registerBridgeTools(server: McpServer, bridge: StudioBridge, config: BridgeConfig): void {
  registerModelExportTool(server, bridge);
  registerViewportCaptureTool(server, bridge);
  server.registerTool("studio_run_test", {
    description: "Execute trusted project test code in Studio Run or Play mode with timeout cleanup. Requires RUN_STUDIO_TEST confirmation. Not a sandbox. The managed ModuleScript must return a function.",
    inputSchema: {
      modulePath: z.string().min(1),
      confirmToken: z.literal("RUN_STUDIO_TEST"),
      mode: z.enum(["run", "play"]).default("run"),
      args: z.record(z.unknown()).default({}),
      timeoutSeconds: z.number().int().min(1).max(120).default(30)
    }
  }, async (args) => dispatch(bridge, "studio_run_test", args, (args.timeoutSeconds + 20) * 1000));
  server.registerTool(
    "studio_ping",
    {
      description: "Check local Roblox Studio plugin status and return version, place, and connection state.",
      inputSchema: {}
    },
    async () => {
      const status = bridge.getStatus();
      if (!status.connected) {
        return jsonResult({ ok: false, status: "offline", bridge: status });
      }
      const plugin = await bridge.sendCommand("studio_ping", {}, 10_000);
      return jsonResult({ ok: true, bridge: bridge.getStatus(), plugin });
    }
  );

  server.registerTool(
    "studio_get_tree",
    {
      description: "Read a bounded Instance tree from Roblox Studio.",
      inputSchema: {
        rootPath: z.string().default("game"),
        depth: z.number().int().min(0).max(20).default(3),
        includeProperties: z.boolean().default(false)
      }
    },
    async (args) => dispatch(bridge, "studio_get_tree", args)
  );

  server.registerTool(
    "studio_find_instances",
    {
      description: "Find Instances by name, className, tag, or path prefix.",
      inputSchema: {
        name: z.string().optional(),
        className: z.string().optional(),
        tags: z.array(z.string()).optional(),
        pathPrefix: z.string().optional(),
        properties: z.array(z.string()).optional(),
        limit: z.number().int().min(1).max(500).default(100)
      }
    },
    async (args) => dispatch(bridge, "studio_find_instances", args)
  );

  server.registerTool(
    "studio_get_properties",
    {
      description: "Read serialized properties for a single Instance.",
      inputSchema: {
        instancePath: z.string(),
        propertyNames: z.array(z.string()).min(1).max(100)
      }
    },
    async (args) => dispatch(bridge, "studio_get_properties", args)
  );

  server.registerTool(
    "studio_create_instance",
    {
      description: "Create an allowed Instance class under a requested parent path.",
      inputSchema: {
        parentPath: z.string(),
        className: z.string(),
        name: z.string(),
        properties: z.record(z.unknown()).default({})
      }
    },
    async (args) => dispatch(bridge, "studio_create_instance", args)
  );

  server.registerTool(
    "studio_set_properties",
    {
      description: "Set validated serialized properties on one Instance.",
      inputSchema: {
        instancePath: z.string(),
        properties: z.record(z.unknown())
      }
    },
    async (args) => dispatch(bridge, "studio_set_properties", args)
  );

  server.registerTool(
    "studio_delete_instances",
    {
      description: "Delete Instances. Requires confirmToken; intended for generated content.",
      inputSchema: {
        paths: z.array(z.string()).min(1).max(200),
        confirmToken: z.string().optional(),
        requireConfirmToken: z.string().optional()
      }
    },
    async (args) => {
      requireDeleteToken(args, config);
      return dispatch(bridge, "studio_delete_instances", args);
    }
  );

  server.registerTool(
    "studio_patch_instances",
    {
      description: "Apply a batch of create, set, ensure, and delete operations inside managed generated roots.",
      inputSchema: {
        operations: z
          .array(
            z.object({
              action: z.enum(["create", "set", "ensure", "delete"]).default("set"),
              parentPath: z.string().optional(),
              instancePath: z.string().optional(),
              path: z.string().optional(),
              className: z.string().optional(),
              name: z.string().optional(),
              properties: z.record(z.unknown()).default({})
            })
          )
          .min(1)
          .max(500),
        confirmToken: z.string().optional(),
        requireConfirmToken: z.string().optional()
      }
    },
    async (args) => dispatch(bridge, "studio_patch_instances", args, Math.max(30_000, args.operations.length * 1_000))
  );

  server.registerTool(
    "studio_execute_luau",
    {
      description: "Execute Luau in Studio only when explicitly enabled by config.",
      inputSchema: {
        code: z.string().min(1).max(100_000),
        timeoutMs: z.number().int().min(100).max(30_000).default(5_000),
        reason: z.string().min(1)
      }
    },
    async (args) => {
      if (!config.allowDangerousLuauExecution) {
        throw new Error("studio_execute_luau is disabled. Set ROBLOX_STUDIO_BRIDGE_ALLOW_DANGEROUS_LUAU=1 to enable.");
      }
      const blocked = validateLuauForDangerousExecution(args.code);
      if (blocked.length > 0) {
        throw new Error(`Blocked dangerous Luau: ${blocked.join("; ")}`);
      }
      return dispatch(bridge, "studio_execute_luau", args, args.timeoutMs + 5_000);
    }
  );

  server.registerTool(
    "studio_get_camera",
    {
      description: "Read the current Roblox Studio viewport camera state.",
      inputSchema: {}
    },
    async () => dispatch(bridge, "studio_get_camera", {}, 10_000)
  );

  server.registerTool(
    "studio_set_camera",
    {
      description: "Move the Roblox Studio viewport camera to inspect generated content.",
      inputSchema: {
        position: z.tuple([z.number(), z.number(), z.number()]).optional(),
        lookAt: z.tuple([z.number(), z.number(), z.number()]).optional(),
        cframe: z.record(z.unknown()).optional(),
        focus: z.record(z.unknown()).optional(),
        fieldOfView: z.number().min(20).max(100).optional()
      }
    },
    async (args) => dispatch(bridge, "studio_set_camera", args, 10_000)
  );

  server.registerTool(
    "studio_focus_instance",
    {
      description: "Focus the Studio viewport camera on an Instance from a named direction.",
      inputSchema: {
        instancePath: z.string(),
        view: z.enum(["iso", "front", "back", "left", "right", "top"]).default("iso"),
        distance: z.number().positive().optional(),
        fieldOfView: z.number().min(20).max(100).optional()
      }
    },
    async (args) => dispatch(bridge, "studio_focus_instance", args, 10_000)
  );

  server.registerTool(
    "studio_visual_probe",
    {
      description: "Set the Studio camera and raycast a viewport grid to report visible hit parts.",
      inputSchema: {
        position: z.tuple([z.number(), z.number(), z.number()]).optional(),
        lookAt: z.tuple([z.number(), z.number(), z.number()]).optional(),
        cframe: z.record(z.unknown()).optional(),
        fieldOfView: z.number().min(20).max(100).optional(),
        rows: z.number().int().min(1).max(15).default(5),
        columns: z.number().int().min(1).max(21).default(7),
        maxDistance: z.number().positive().max(5000).default(500),
        aspect: z.number().positive().default(16 / 9)
      }
    },
    async (args) => dispatch(bridge, "studio_visual_probe", args, 15_000)
  );

  server.registerTool(
    "map_apply_scene_spec",
    {
      description: "Dry-run or apply a SceneSpec map into Workspace/MapDrafts.",
      inputSchema: {
        sceneSpec: z.record(z.unknown()),
        dryRun: z.boolean().default(true)
      }
    },
    async (args) => {
      const sceneSpec = parseSceneSpec(args.sceneSpec);
      const plan = planSceneSpec(sceneSpec, config);
      if (args.dryRun !== false) {
        return jsonResult({ dryRun: true, plan });
      }
      if (!plan.allowedToApply) {
        throw new Error(`SceneSpec is not safe to apply: ${plan.risks.join("; ")}`);
      }
      const applyResult = await bridge.sendCommand("map_apply_scene_spec", { sceneSpec, dryRun: false });
      const rojoArtifacts = await writeRojoArtifacts(config, sceneSpec, applyResult as { mapRootPath?: string });
      const manifestPath = await writeManifest(config, sceneSpec, applyResult);
      return jsonResult({ dryRun: false, manifestPath, rojoArtifacts, result: applyResult });
    }
  );

  server.registerTool(
    "terrain_generate",
    {
      description: "Generate terrain through Roblox Terrain API via the Studio plugin.",
      inputSchema: {
        parentFolder: z.string().default("Workspace/MapDrafts"),
        size: z.tuple([z.number(), z.number(), z.number()]),
        seed: z.number().int().optional(),
        biome: z.enum(["forest", "desert", "snow", "island", "city", "arena", "obby", "custom"]).default("custom"),
        heightNoise: z.number().min(0).max(1).default(0.4),
        water: z.boolean().default(false),
        caves: z.boolean().default(false),
        paths: z.boolean().default(false)
      }
    },
    async (args) => {
      if (Math.max(...args.size) > config.limits.maxTerrainSize) {
        throw new Error(`Terrain size exceeds maxTerrainSize ${config.limits.maxTerrainSize}.`);
      }
      return dispatch(bridge, "terrain_generate", args);
    }
  );

  server.registerTool(
    "map_create_blockout",
    {
      description: "Create or dry-run a greybox blockout from a SceneSpec.",
      inputSchema: {
        sceneSpec: z.record(z.unknown()),
        dryRun: z.boolean().default(true)
      }
    },
    async (args) => {
      const sceneSpec = parseSceneSpec(args.sceneSpec);
      const plan = planSceneSpec(sceneSpec, config);
      if (args.dryRun !== false) {
        return jsonResult({ dryRun: true, plan });
      }
      return dispatch(bridge, "map_create_blockout", { sceneSpec, dryRun: false });
    }
  );

  server.registerTool(
    "map_refine_visuals",
    {
      description: "Refine generated map visuals without changing gameplay layout.",
      inputSchema: {
        mapRootPath: z.string(),
        style: z.enum(["realistic", "lowpoly", "cartoon", "sci-fi", "medieval", "modern", "horror", "obby"]),
        dryRun: z.boolean().default(true),
        notes: z.string().optional()
      }
    },
    async (args) => dispatch(bridge, "map_refine_visuals", args)
  );

  server.registerTool(
    "map_validate",
    {
      description: "Validate generated map safety and geometry. This is not a final visual readiness check.",
      inputSchema: {
        rootPath: z.string().default("Workspace/MapDrafts"),
        maxObjects: z.number().int().min(1).max(20_000).default(config.limits.maxObjectCount),
        strictGeometry: z.boolean().default(true),
        terrainClearance: z.number().min(0).max(20).default(0.2),
        maxOverlapWarnings: z.number().int().min(1).max(500).default(40)
      }
    },
    async (args) => dispatch(bridge, "map_validate", args)
  );

  server.registerTool(
    "map_readiness_check",
    {
      description: "Run final visual-readiness contract checks for generated maps after map_validate.",
      inputSchema: {
        rootPath: z.string(),
        profile: z.enum(["generic", "house"]).default("generic"),
        expectedMapVersion: z.string().min(1).max(32).optional(),
        requireVisibleVersion: z.boolean().default(true)
      }
    },
    async (args) => dispatch(bridge, "map_readiness_check", args)
  );

  server.registerTool(
    "studio_read_output",
    {
      description: "Return recent output lines mirrored by the Studio plugin.",
      inputSchema: {
        lines: z.number().int().min(1).max(500).default(100)
      }
    },
    async (args) => jsonResult({ lines: bridge.readOutput(args.lines) })
  );

  server.registerTool(
    "studio_start_playtest",
    {
      description: "Ask Studio plugin to start playtest, or return a manual fallback.",
      inputSchema: {}
    },
    async () => dispatch(bridge, "studio_start_playtest", {}, 10_000)
  );

  server.registerTool(
    "studio_stop_playtest",
    {
      description: "Ask Studio plugin to stop playtest, or return a manual fallback.",
      inputSchema: {}
    },
    async () => dispatch(bridge, "studio_stop_playtest", {}, 10_000)
  );
}
