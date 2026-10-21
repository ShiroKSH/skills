import { z } from "zod";

const numberTriple = z.tuple([z.number(), z.number(), z.number()]);
const shortName = z.string().min(1).max(128);
const notes = z.string().max(2000);

export const DEFAULT_SCENE_ROOT = "Workspace/MapDrafts";
export const LEGACY_BUILD_SCENE_ROOT = "Workspace/Builds";
export const LEGACY_AI_GENERATED_SCENE_ROOT = "Workspace/AI_Generated";
export const SAFE_SCENE_ROOTS = [
  DEFAULT_SCENE_ROOT,
  LEGACY_BUILD_SCENE_ROOT,
  LEGACY_AI_GENERATED_SCENE_ROOT
] as const;

export const serializedValueSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("Vector3"), value: numberTriple }),
  z.object({ type: z.literal("Color3"), value: numberTriple }),
  z.object({ type: z.literal("CFrame"), value: z.array(z.number()).refine(
    (components) => components.length === 3 || components.length === 12,
    "CFrame requires exactly 3 position or 12 transform components"
  ) }),
  z.object({ type: z.literal("Enum"), value: z.string().min(1) }),
  z.object({ type: z.literal("UDim2"), value: z.tuple([z.number(), z.number(), z.number(), z.number()]) }),
  z.object({ type: z.literal("BrickColor"), value: z.union([z.string(), z.number()]) }),
  z.object({ type: z.literal("NumberRange"), value: z.union([z.number(), z.tuple([z.number(), z.number()])]) }),
  z.object({
    type: z.literal("ColorSequence"),
    value: z.array(
      z.object({
        time: z.number().min(0).max(1),
        color: numberTriple
      })
    ).min(1)
  })
]);

export const primitivePropertySchema = z.union([z.string(), z.number(), z.boolean(), z.null()]);
export const propertyValueSchema = z.union([primitivePropertySchema, serializedValueSchema]);
const vectorRefSchema = z.union([shortName, numberTriple, serializedValueSchema]);

export const sceneInstanceSchema = z.object({
  className: z.string().min(1),
  name: shortName,
  parentPath: z.string().min(1).default("$MAP_ROOT"),
  properties: z.record(propertyValueSchema).default({})
});

export const sceneScriptSchema = z.object({
  path: z.string().min(1),
  source: z.string().max(200_000)
});

export const sceneCodegenSchema = z
  .object({
    target: z.enum(["studio", "rojo", "both"]).default("studio"),
    rojoRoot: z.string().min(1).max(260).default("generated/rojo"),
    projectName: z.string().min(1).max(80).optional()
  })
  .default({ target: "studio", rojoRoot: "generated/rojo" });

export const sceneZoneSchema = z.object({
  name: shortName,
  kind: z.enum(["spawn", "combat", "shop", "obstacle", "road", "decoration", "boundary"]),
  position: serializedValueSchema,
  size: serializedValueSchema,
  notes: z.string().optional()
});

export const sceneLayoutSchema = z.object({
  kind: z.enum(["open-world", "linear", "hub", "arena", "city", "dungeon", "obby", "custom"]).default("custom"),
  origin: numberTriple.optional(),
  size: numberTriple.optional(),
  primaryAxis: z.enum(["x", "y", "z"]).optional(),
  gridSize: z.number().positive().max(10_000).optional(),
  grounding: z
    .object({
      mode: z.enum(["raycast", "manual", "none"]).default("raycast"),
      groundY: z.number().optional(),
      clearance: z.number().min(0).max(100).default(0.05),
      support: z.enum(["none", "skirt", "piers"]).default("skirt")
    })
    .optional(),
  notes: notes.optional()
});

export const sceneBuildingSchema = z.object({
  name: shortName,
  kind: z
    .enum([
      "residential",
      "commercial",
      "industrial",
      "civic",
      "landmark",
      "arena",
      "utility",
      "tower",
      "market",
      "monastery",
      "factory",
      "outpost",
      "custom"
    ])
    .default("custom"),
  position: numberTriple.optional(),
  size: numberTriple.optional(),
  footprint: numberTriple.optional(),
  levels: z.number().int().positive().max(16).optional(),
  floorCount: z.number().int().positive().max(200).optional(),
  floorHeight: z.number().positive().max(80).optional(),
  balconyEvery: z.number().int().positive().max(16).optional(),
  roof: z.enum(["flat", "pitched", "dome", "antenna", "custom"]).optional(),
  material: z.string().max(128).optional(),
  style: z.string().max(128).optional(),
  entrances: z.array(shortName).default([]),
  notes: notes.optional()
});

export const sceneLevelSchema = z.object({
  name: shortName,
  order: z.number().int().min(0).optional(),
  kind: z.enum(["surface", "interior", "underground", "sky", "dungeon", "arena", "custom"]).default("custom"),
  bounds: numberTriple.optional(),
  altitude: z.number().optional(),
  connectsTo: z.array(shortName).default([]),
  notes: notes.optional()
});

export const scenePoiSchema = z.object({
  name: shortName,
  kind: z
    .enum([
      "spawn",
      "objective",
      "quest",
      "shop",
      "market",
      "combat",
      "puzzle",
      "resource",
      "landmark",
      "vista",
      "transit",
      "custom"
    ])
    .default("custom"),
  position: numberTriple,
  size: numberTriple.optional(),
  color: serializedValueSchema.optional(),
  transparency: z.number().min(0).max(1).optional(),
  radius: z.number().positive().optional(),
  priority: z.enum(["low", "medium", "high", "critical"]).default("medium"),
  notes: notes.optional()
});

export const sceneConnectorSchema = z.object({
  name: shortName,
  kind: z.enum(["road", "path", "bridge", "tunnel", "stairs", "elevator", "teleporter", "door", "zipline", "custom"]),
  from: vectorRefSchema,
  to: vectorRefSchema,
  width: z.number().positive().optional(),
  bidirectional: z.boolean().default(true),
  notes: notes.optional()
});

export const sceneFunctionalObjectSchema = z.object({
  name: shortName,
  kind: z.enum(["door", "button", "lever", "elevator", "teleporter", "checkpoint", "custom"]),
  action: z.enum(["toggle", "open", "move", "teleport", "checkpoint", "message", "custom"]).default("toggle"),
  position: numberTriple.optional(),
  size: numberTriple.optional(),
  target: z.string().min(1).max(256).optional(),
  targetPosition: numberTriple.optional(),
  openOffset: numberTriple.optional(),
  promptText: z.string().min(1).max(80).optional(),
  startsOpen: z.boolean().default(false),
  locked: z.boolean().default(false),
  autoCloseSeconds: z.number().min(0).max(120).default(5),
  notes: notes.optional()
});

export const scenePaletteSchema = z.union([
  z
    .object({
      wall: serializedValueSchema.optional(),
      accent: serializedValueSchema.optional(),
      roof: serializedValueSchema.optional(),
      floor: serializedValueSchema.optional(),
      trim: serializedValueSchema.optional()
    })
    .partial(),
  z.array(
    z.object({
      name: shortName,
      color: serializedValueSchema
    })
  )
]);

export const sceneThemeSchema = z.object({
  mood: z.string().max(128).optional(),
  genre: z.string().max(128).optional(),
  timePeriod: z.string().max(128).optional(),
  palette: scenePaletteSchema.optional(),
  materials: z.array(z.string().min(1).max(128)).default([]),
  notes: notes.optional()
});

export const sceneAssetPolicySchema = z.object({
  allowExternalAssets: z.boolean().default(false),
  allowedAssetIds: z.array(z.union([z.number().int().positive(), z.string().regex(/^\d+$/)])).default([]),
  allowedSources: z.array(z.enum(["built-in", "creator-store", "team-owned", "local", "custom"])).default(["built-in"]),
  notes: notes.optional()
});

export const sceneVisibilitySchema = z.object({
  maxViewDistance: z.number().positive().optional(),
  fogStart: z.number().min(0).optional(),
  fogEnd: z.number().min(0).optional(),
  occlusion: z.enum(["none", "manual", "streaming", "custom"]).default("streaming"),
  levelOfDetail: z.enum(["low", "medium", "high", "adaptive"]).default("adaptive"),
  notes: notes.optional()
});

export const sceneSpecSchema = z.object({
  mapName: z.string().min(1).max(80).regex(/^[A-Za-z0-9 _-]+$/),
  description: z.string().max(4000).default(""),
  style: z.enum(["realistic", "lowpoly", "cartoon", "sci-fi", "medieval", "modern", "horror", "obby"]),
  scale: z.number().positive().max(100).default(1),
  rootPath: z.string().default(DEFAULT_SCENE_ROOT),
  lighting: z
    .object({
      timeOfDay: z.string().optional(),
      ambient: serializedValueSchema.optional(),
      brightness: z.number().min(0).max(20).optional()
    })
    .optional(),
  terrain: z
    .object({
      enabled: z.boolean().default(false),
      biome: z.enum(["forest", "desert", "snow", "island", "city", "arena", "custom"]).default("custom"),
      size: numberTriple.default([256, 64, 256]),
      seed: z.number().int().optional(),
      heightNoise: z.number().min(0).max(1).optional(),
      water: z.boolean().optional(),
      caves: z.boolean().optional(),
      paths: z.boolean().optional()
    })
    .optional(),
  zones: z.array(sceneZoneSchema).default([]),
  layout: sceneLayoutSchema.optional(),
  buildings: z.array(sceneBuildingSchema).optional(),
  levels: z.array(sceneLevelSchema).optional(),
  pois: z.array(scenePoiSchema).optional(),
  connectors: z.array(sceneConnectorSchema).optional(),
  functionalObjects: z.array(sceneFunctionalObjectSchema).default([]),
  theme: sceneThemeSchema.optional(),
  assetPolicy: sceneAssetPolicySchema.optional(),
  visibility: sceneVisibilitySchema.optional(),
  instances: z.array(sceneInstanceSchema).default([]),
  scripts: z.array(sceneScriptSchema).default([]),
  codegen: sceneCodegenSchema.optional(),
  allowExistingEdit: z.boolean().default(false)
});

export type SerializedValue = z.infer<typeof serializedValueSchema>;
export type SceneSpec = z.infer<typeof sceneSpecSchema>;
export type SceneInstance = z.infer<typeof sceneInstanceSchema>;

export function parseSceneSpec(input: unknown): SceneSpec {
  return sceneSpecSchema.parse(input);
}

export function isSafeSceneRoot(rootPath: string): boolean {
  return (SAFE_SCENE_ROOTS as readonly string[]).includes(rootPath);
}
