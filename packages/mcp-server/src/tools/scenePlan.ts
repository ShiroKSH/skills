import type { BridgeConfig } from "../security/config.js";
import { isSafeSceneRoot, type SceneSpec } from "../schema/sceneSpec.js";

export type ScenePlan = {
  mapName: string;
  targetRoot: string;
  objectCount: number;
  batchOperations: number;
  servicesTouched: string[];
  risks: string[];
  allowedToApply: boolean;
};

function serviceFromPath(path: string): string {
  return path.split(/[/.]/, 1)[0] || "Workspace";
}

function riskBlocksApply(risk: string): boolean {
  return (
    risk.includes("exceeds") ||
    risk.includes("requires allowExistingEdit") ||
    risk.includes("require allowedAssetIds")
  );
}

export function planSceneSpec(sceneSpec: SceneSpec, config?: BridgeConfig): ScenePlan {
  const services = new Set<string>(["Workspace"]);
  const risks: string[] = [];
  const terrainEnabled = sceneSpec.terrain?.enabled === true;
  const buildings = sceneSpec.buildings ?? [];
  const levels = sceneSpec.levels ?? [];
  const pois = sceneSpec.pois ?? [];
  const connectors = sceneSpec.connectors ?? [];
  const functionalObjects = sceneSpec.functionalObjects ?? [];
  const highLevelObjectCount =
    (sceneSpec.layout ? 1 : 0) +
    buildings.length +
    levels.length +
    pois.length +
    connectors.length +
    functionalObjects.length +
    (sceneSpec.theme ? 1 : 0) +
    (sceneSpec.assetPolicy ? 1 : 0) +
    (sceneSpec.visibility ? 1 : 0);
  const generatedObjectCount =
    2 +
    sceneSpec.zones.length +
    sceneSpec.instances.length +
    sceneSpec.scripts.length +
    highLevelObjectCount +
    (terrainEnabled ? 1 : 0);

  if (sceneSpec.lighting || sceneSpec.visibility) {
    services.add("Lighting");
  }
  if (functionalObjects.length > 0) {
    services.add("ServerScriptService");
    risks.push("Functional objects create ProximityPrompts and a scoped MapInteractions runtime script.");
  }
  if (sceneSpec.codegen?.target === "rojo" || sceneSpec.codegen?.target === "both") {
    risks.push(`Rojo codegen writes local Luau/project files under ${sceneSpec.codegen.rojoRoot}.`);
  }
  if (sceneSpec.layout?.grounding?.mode && sceneSpec.layout.grounding.mode !== "none") {
    risks.push("Grounding uses Studio raycasts/manual groundY to place the map on the current Workspace surface.");
  }
  if (terrainEnabled) {
    services.add("Workspace.Terrain");
    risks.push("Terrain API changes shared Workspace.Terrain; undo via Studio history if needed.");
  }

  for (const instance of sceneSpec.instances) {
    if (instance.parentPath !== "$MAP_ROOT" && !instance.parentPath.startsWith("$MAP_ROOT/")) {
      services.add(serviceFromPath(instance.parentPath));
    }
  }
  for (const script of sceneSpec.scripts) {
    services.add(serviceFromPath(script.path));
    risks.push(`Script source will be written to ${script.path}. Review before apply.`);
  }

  if (sceneSpec.assetPolicy?.allowExternalAssets === true) {
    if (sceneSpec.assetPolicy.allowedAssetIds.length === 0) {
      risks.push("External assets require allowedAssetIds before apply.");
    } else {
      risks.push("External asset allowlist declared; verify asset ownership before apply.");
    }
  }

  if (!isSafeSceneRoot(sceneSpec.rootPath) && !sceneSpec.allowExistingEdit) {
    risks.push("Non-safe rootPath requires allowExistingEdit=true before apply.");
  }

  if (config) {
    if (generatedObjectCount > config.limits.maxObjectCount) {
      risks.push(`Object count ${generatedObjectCount} exceeds maxObjectCount ${config.limits.maxObjectCount}.`);
    }
    if (generatedObjectCount > config.limits.maxBatchOperations) {
      risks.push(
        `Batch operations ${generatedObjectCount} exceeds maxBatchOperations ${config.limits.maxBatchOperations}.`
      );
    }
    const terrainSize = sceneSpec.terrain?.size;
    if (terrainSize && Math.max(...terrainSize) > config.limits.maxTerrainSize) {
      risks.push(`Terrain size ${terrainSize.join("x")} exceeds maxTerrainSize ${config.limits.maxTerrainSize}.`);
    }
  }

  return {
    mapName: sceneSpec.mapName,
    targetRoot: `${sceneSpec.rootPath}/${sceneSpec.mapName}_<timestamp>`,
    objectCount: generatedObjectCount,
    batchOperations: generatedObjectCount,
    servicesTouched: Array.from(services).sort(),
    risks,
    allowedToApply:
      risks.every((risk) => !riskBlocksApply(risk)) &&
      (isSafeSceneRoot(sceneSpec.rootPath) || sceneSpec.allowExistingEdit)
  };
}
