import { describe, expect, it } from "vitest";
import { parseSceneSpec } from "../src/schema/sceneSpec.js";
import { planSceneSpec } from "../src/tools/scenePlan.js";
import type { BridgeConfig } from "../src/security/config.js";

const config: BridgeConfig = {
  host: "127.0.0.1",
  port: 3765,
  token: "123456789012345678901234",
  tokenWasGenerated: false,
  deleteConfirmToken: "DELETE_MAP_DRAFTS",
  allowDangerousLuauExecution: false,
  commandTimeoutMs: 120_000,
  logsDir: "logs",
  limits: {
    maxObjectCount: 1000,
    maxTerrainSize: 512,
    maxBatchOperations: 2000
  }
};

describe("SceneSpec planning", () => {
  it("accepts a minimal obby spec and plans Workspace/MapDrafts output", () => {
    const spec = parseSceneSpec({
      mapName: "Simple Obby",
      description: "Small greybox obby",
      style: "obby",
      zones: [
        {
          name: "SpawnArea",
          kind: "spawn",
          position: { type: "Vector3", value: [0, 5, 0] },
          size: { type: "Vector3", value: [32, 4, 32] }
        }
      ],
      instances: [
        {
          className: "SpawnLocation",
          name: "Spawn",
          parentPath: "$MAP_ROOT",
          properties: {
            Anchored: true,
            Size: { type: "Vector3", value: [12, 1, 12] }
          }
        }
      ]
    });

    const plan = planSceneSpec(spec, config);

    expect(plan.allowedToApply).toBe(true);
    expect(plan.targetRoot).toBe("Workspace/MapDrafts/Simple Obby_<timestamp>");
    expect(plan.objectCount).toBe(4);
    expect(plan.servicesTouched).toContain("Workspace");
  });

  it("keeps legacy safe roots allowed", () => {
    const spec = parseSceneSpec({
      mapName: "Legacy Root",
      style: "modern",
      rootPath: "Workspace/Builds"
    });
    const aiSpec = parseSceneSpec({
      mapName: "Legacy AI Root",
      style: "modern",
      rootPath: "Workspace/AI_Generated"
    });

    const plan = planSceneSpec(spec, config);
    const aiPlan = planSceneSpec(aiSpec, config);

    expect(plan.allowedToApply).toBe(true);
    expect(plan.targetRoot).toBe("Workspace/Builds/Legacy Root_<timestamp>");
    expect(plan.risks.join("\n")).not.toContain("allowExistingEdit");
    expect(aiPlan.allowedToApply).toBe(true);
    expect(aiPlan.targetRoot).toBe("Workspace/AI_Generated/Legacy AI Root_<timestamp>");
    expect(aiPlan.risks.join("\n")).not.toContain("allowExistingEdit");
  });

  it("counts nested map parents as Workspace instead of a separate service", () => {
    const plan = planSceneSpec(parseSceneSpec({
      mapName: "Nested Cabin",
      style: "modern",
      instances: [{ className: "Part", name: "Wall", parentPath: "$MAP_ROOT/Buildings/Cabin" }]
    }), config);
    expect(plan.servicesTouched).toEqual(["Workspace"]);
  });

  it("accepts rich high-level map fields and includes them in planning", () => {
    const spec = parseSceneSpec({
      mapName: "Rich City",
      style: "modern",
      layout: {
        kind: "city",
        origin: [0, 0, 0],
        size: [512, 160, 512],
        primaryAxis: "x",
        gridSize: 32
      },
      buildings: [
        {
          name: "TransitHub",
          kind: "civic",
          position: [0, 0, 0],
          size: [80, 60, 80],
          floorCount: 3,
          entrances: ["NorthPlaza", "RailPlatform"]
        },
        {
          name: "MarketHall",
          kind: "commercial",
          position: [96, 0, 32],
          size: [72, 40, 64]
        }
      ],
      levels: [
        {
          name: "Street",
          order: 0,
          kind: "surface",
          bounds: [512, 40, 512],
          connectsTo: ["TransitHub"]
        }
      ],
      pois: [
        {
          name: "NorthPlaza",
          kind: "spawn",
          position: [-64, 0, 0],
          radius: 24,
          priority: "high"
        },
        {
          name: "RailPlatform",
          kind: "transit",
          position: [24, 0, -80],
          radius: 18
        }
      ],
      connectors: [
        {
          name: "MainWalkway",
          kind: "path",
          from: "NorthPlaza",
          to: "RailPlatform",
          width: 16
        }
      ],
      theme: {
        mood: "bright civic",
        genre: "near future",
        palette: [
          {
            name: "TransitBlue",
            color: { type: "Color3", value: [0.1, 0.35, 0.85] }
          }
        ],
        materials: ["Concrete", "Glass", "Metal"]
      },
      assetPolicy: {
        allowExternalAssets: false
      },
      visibility: {
        maxViewDistance: 768,
        fogStart: 512,
        fogEnd: 900,
        occlusion: "streaming",
        levelOfDetail: "adaptive"
      }
    });

    const plan = planSceneSpec(spec, config);

    expect(spec.rootPath).toBe("Workspace/MapDrafts");
    expect(spec.buildings).toHaveLength(2);
    expect(spec.pois).toHaveLength(2);
    expect(spec.assetPolicy?.allowedSources).toEqual(["built-in"]);
    expect(plan.allowedToApply).toBe(true);
    expect(plan.objectCount).toBe(12);
    expect(plan.targetRoot).toBe("Workspace/MapDrafts/Rich City_<timestamp>");
    expect(plan.servicesTouched).toContain("Lighting");
  });

  it("blocks non-default roots unless allowExistingEdit is set", () => {
    const spec = parseSceneSpec({
      mapName: "Unsafe Root",
      style: "modern",
      rootPath: "Workspace",
      instances: []
    });

    const plan = planSceneSpec(spec, config);

    expect(plan.allowedToApply).toBe(false);
    expect(plan.risks.join("\n")).toContain("allowExistingEdit");
  });

  it("blocks external assets without an explicit allowlist", () => {
    const spec = parseSceneSpec({
      mapName: "External Asset Map",
      style: "realistic",
      assetPolicy: {
        allowExternalAssets: true
      }
    });

    const plan = planSceneSpec(spec, config);

    expect(plan.allowedToApply).toBe(false);
    expect(plan.risks.join("\n")).toContain("allowedAssetIds");
  });

  it("reports terrain limit risk", () => {
    const spec = parseSceneSpec({
      mapName: "Huge Terrain",
      style: "realistic",
      terrain: {
        enabled: true,
        biome: "forest",
        size: [1024, 64, 1024]
      }
    });

    const plan = planSceneSpec(spec, config);

    expect(plan.allowedToApply).toBe(false);
    expect(plan.risks.join("\n")).toContain("maxTerrainSize");
    expect(plan.servicesTouched).toContain("Workspace.Terrain");
  });

  it("plans functional objects and optional Rojo codegen", () => {
    const spec = parseSceneSpec({
      mapName: "Interactive Cottage",
      style: "medieval",
      codegen: {
        target: "both",
        rojoRoot: "generated/rojo"
      },
      functionalObjects: [
        {
          name: "FrontDoor",
          kind: "door",
          position: [0, 5, 0],
          size: [5, 8, 1],
          promptText: "Open Door",
          openOffset: [6, 0, 0]
        }
      ]
    });

    const plan = planSceneSpec(spec, config);

    expect(plan.allowedToApply).toBe(true);
    expect(plan.servicesTouched).toContain("ServerScriptService");
    expect(plan.risks.join("\n")).toContain("Functional objects");
    expect(plan.risks.join("\n")).toContain("Rojo codegen");
    expect(spec.functionalObjects[0]?.promptText).toBe("Open Door");
  });
});
