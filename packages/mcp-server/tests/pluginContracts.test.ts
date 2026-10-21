import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { parseSceneSpec } from "../src/schema/sceneSpec.js";

const sceneApplier = readFileSync("plugin/src/Bridge/SceneApplier.lua", "utf8");
const commandRouter = readFileSync("plugin/src/Bridge/CommandRouter.lua", "utf8");
const registry = readFileSync("packages/mcp-server/src/tools/registry.ts", "utf8");

describe("plugin visual-readiness contracts", () => {
  it("parses functional doors that bind to existing visible parts", () => {
    const spec = parseSceneSpec({
      mapName: "Door Binding",
      style: "modern",
      instances: [
        {
          className: "Part",
          name: "FrontDoorPanel",
          properties: {
            Anchored: true,
            Size: { type: "Vector3", value: [6, 7, 0.5] },
            Position: { type: "Vector3", value: [0, 5, 0] }
          }
        }
      ],
      functionalObjects: [
        {
          name: "FrontDoorBehavior",
          kind: "door",
          target: "FrontDoorPanel",
          openOffset: [7, 0, 0],
          autoCloseSeconds: 4
        }
      ]
    });

    expect(spec.functionalObjects[0].target).toBe("FrontDoorPanel");
    expect(spec.functionalObjects[0].autoCloseSeconds).toBe(4);
  });

  it("keeps functional doors attached to visible geometry in the source plugin", () => {
    expect(sceneApplier).toContain("resolveFunctionalTarget");
    expect(sceneApplier).toContain('markFunctionalPart(part, "SlidingDoor"');
    expect(sceneApplier).toContain('shiftVectorField(objectSpec, "position"');
    expect(sceneApplier).toContain('shiftVectorField(objectSpec, "targetPosition"');
  });

  it("exposes map_readiness_check through MCP and the plugin router", () => {
    expect(sceneApplier).toContain("function SceneApplier.readiness");
    expect(commandRouter).toContain('"map_readiness_check"');
    expect(registry).toContain('"map_readiness_check"');
    expect(registry).toContain("expectedMapVersion");
  });

  it("exposes persistent live patch and Studio vision commands", () => {
    expect(commandRouter).toContain('"studio_patch_instances"');
    expect(commandRouter).toContain('"studio_get_camera"');
    expect(commandRouter).toContain('"studio_set_camera"');
    expect(commandRouter).toContain('"studio_focus_instance"');
    expect(commandRouter).toContain('"studio_visual_probe"');
    for (const toolName of [
      "studio_patch_instances",
      "studio_get_camera",
      "studio_set_camera",
      "studio_focus_instance",
      "studio_visual_probe"
    ]) {
      expect(registry).toContain(`"${toolName}"`);
    }
  });

  it("checks the visual failures that slipped through map_validate", () => {
    expect(sceneApplier).toContain("blocksDoorOpening");
    expect(sceneApplier).toContain("Balcony deck is not outside");
    expect(sceneApplier).toContain("Unexpected roof cap slab");
    expect(sceneApplier).toContain("validateRoofClosureReadiness");
    expect(sceneApplier).toContain("visible sky gap");
    expect(sceneApplier).toContain("validateAllStairHeadroom");
    expect(sceneApplier).toContain("validateFloorSeparation");
    expect(sceneApplier).toContain("validatePathWithinLotBounds");
    expect(sceneApplier).toContain("validateVisibleMapVersion");
  });

  it("rejects incomplete CFrame rotations before reaching Studio", () => {
    for (const length of [4, 6, 9, 11]) {
      expect(() => parseSceneSpec({
        mapName: "Invalid Transform",
        style: "modern",
        instances: [{ className: "Part", name: "Wall", properties: {
          CFrame: { type: "CFrame", value: Array(length).fill(0) }
        } }]
      })).toThrow("CFrame requires exactly");
    }
  });
});
