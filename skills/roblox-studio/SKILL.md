---
name: roblox-studio
description: "Build, inspect, repair, validate, and playtest Roblox Studio maps and Luau through the local bridge. Use for SceneSpecs, terrain, Studio edits, gameplay objects, visual checks, and Rojo output."
---

# Roblox Studio

Use the `roblox-studio` MCP tools to work against the place currently open in Studio. Keep new work under `Workspace/MapDrafts`.

## Preflight

1. Confirm the MCP tools are available. If they are missing or `studio_ping` reports offline, read [setup.md](references/setup.md).
2. Run `studio_ping` before every work session.
3. Inspect the relevant hierarchy with `studio_get_tree`; use `studio_find_instances` and `studio_get_properties` for targeted reads.
4. State the place and target root before changing anything. Never imply that Studio changed when the bridge is offline.

## Choose a Workflow

- New map or major rebuild: read [scene-spec.md](references/scene-spec.md), draft one SceneSpec, then use `map_apply_scene_spec`.
- Fast graybox: use `map_create_blockout`, then validate the route before visual refinement.
- Existing generated map repair: inspect first and batch related edits with `studio_patch_instances`.
- Before a substantial repair, use `studio_export_model` to keep a private local model backup.
- Focused property edit: use `studio_set_properties`; use `studio_create_instance` only inside a managed root.
- Terrain-only task: use `terrain_generate` with an explicit bounded size.
- Luau plus Rojo output: set `codegen.target` to `both` and review every script before apply.
- Tool choice or argument uncertainty: read [tools.md](references/tools.md).

## Build Loop

1. Translate the request into named areas, player route, scale, style, interactions, and acceptance checks.
2. Preserve existing content unless the user explicitly asked to replace or edit it.
3. For a SceneSpec, run `map_apply_scene_spec` with `dryRun=true`.
4. Review target root, object count, services touched, filesystem writes, scripts, terrain, and reported risks.
5. Apply with `dryRun=false` when the user requested the build or explicitly approved the dry run.
6. Run `map_validate` on the exact returned map root with `strictGeometry=true`.
7. Run `map_readiness_check` for playable maps; use `profile="house"` only for its named house contract.
8. Inspect from useful angles with `studio_focus_instance`, `studio_set_camera`, and `studio_visual_probe`.
9. When behavior matters, review a managed test ModuleScript returning `function(args)`. Raise an error on failure and return a JSON-serializable value on success. Call `studio_run_test` with `confirmToken="RUN_STUDIO_TEST"`, optional `mode` (`run` or `play`), and `timeoutSeconds` (integer 1-120, default 30). Tests execute ordinary project code, not a sandbox. Use a working copy and disable or mock persistent/external writes.
10. Repair concrete failures and repeat validation. Prefer a scoped patch over rebuilding a sound map.

## Quality Bar

- Include a SpawnLocation, readable route, safe landings, and an obvious destination for playable maps.
- Use unique, semantic names and models/folders for levels, buildings, routes, and systems.
- Ground normal maps with `layout.grounding.mode="raycast"`; use `manual` for a known elevation and `none` only for intentional sky or void maps.
- Put doors, buttons, elevators, teleporters, and checkpoints in `functionalObjects`. Bind a behavior to existing visible geometry with `target` when possible.
- Treat validation warnings about terrain intersections, blocked doors, stair headroom, unreachable landings, or solid overlaps as repair work.
- Do not call a map visually ready from object counts or `map_validate` alone.
- Use `studio_capture_viewport` for real viewport evidence after native permission is granted. Never substitute a desktop capture, invent a frame, or trigger permission dialogs during a background-only task. Review in-world text before sharing an image.

## Guardrails

- Never request Roblox credentials, cookies, or `.ROBLOSECURITY`.
- Never send the bridge token anywhere except the local Studio plugin.
- Never use external asset IDs without a user-supplied allowlist.
- Keep direct edits and deletes inside managed roots. Deletes require the configured confirm token and explicit user intent.
- Do not enable `studio_execute_luau` to bypass declarative tools. If it is genuinely required, explain the exact code and risk first.
- Avoid remote code, HTTP, `require(assetId)`, `loadstring`, and hidden loaders in generated Luau.

## Handoff

Report the exact map root, manifest path, Rojo files, validation/readiness result, playtest result, warnings left, and the next manual Studio check. Separate verified results from visual judgment.
