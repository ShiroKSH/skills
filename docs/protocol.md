# Protocol

The MCP server is a stdio MCP process for AI coding agents and a localhost HTTP queue for Roblox Studio.

Studio plugins cannot reliably accept inbound sockets, so the plugin polls the Node server:

1. Plugin posts `/plugin/register` with the shared token, a non-empty `clientId`, and place metadata.
2. Plugin long-polls `POST /plugin/poll` with the shared token and registered `clientId` in the JSON body.
3. MCP tool calls enqueue commands.
4. Plugin executes a command in Studio and posts `/plugin/result`.
5. Optional plugin logs go to `/plugin/output`.

Default bind is `127.0.0.1:3765`. Non-loopback binds are refused.

The pre-release GET polling route was removed so credentials never appear in request URLs. Plugin and server must be updated together.

Version 0.2.0 and later require the registered `clientId` on every plugin request. Older plugins must be updated with the server. A different Studio session receives HTTP 409 while the current owner is active. An idle owner becomes stale after 35 seconds without a poll or result. Pending commands retain ownership until completion or their deadline, preventing a long edit from being transferred to another place.

The plugin re-registers after connection failures, with a capped backoff. Authentication failures stop reconnecting until the user supplies the correct token. Disconnecting invalidates in-flight poll responses. Result delivery retries never execute the command again.

Result delivery retries continue until acknowledgement, a permanent rejection, disconnect, or the command deadline. A detected place change stops the connection before the next command can execute. Inspect the place and connect again. Request logs use `command_requested`, while results without a pending command use `command_result_unmatched`, including duplicate acknowledgements.

Version 0.2.2 rotates the client identity after a place change. Reconnecting uses a new owner rather than consuming the old queue. A pending old command may temporarily block the new registration until its deadline. Use plugin 0.2.2 or later for this protection.

## Command envelope

```json
{
  "id": "uuid",
  "name": "map_apply_scene_spec",
  "args": {},
  "createdAt": "2026-10-21T00:00:00.000Z",
  "expiresAt": "2026-10-21T00:00:30.000Z"
}
```

Expired commands are removed from the server queue and rejected by the plugin before execution. A timeout does not cancel an edit that is already running. Inspect Studio before retrying an edit whose result was lost.

## Result envelope

```json
{
  "token": "shared token",
  "clientId": "registered Studio client ID",
  "commandId": "uuid",
  "ok": true,
  "result": {}
}
```

## MCP tools

- `studio_ping`
- `studio_get_tree`
- `studio_find_instances`
- `studio_get_properties`
- `studio_create_instance`
- `studio_set_properties`
- `studio_delete_instances`
- `studio_patch_instances`
- `studio_execute_luau`
- `studio_get_camera`
- `studio_set_camera`
- `studio_focus_instance`
- `studio_visual_probe`
- `studio_export_model`
- `studio_capture_viewport`
- `studio_run_test`
- `map_apply_scene_spec`
- `terrain_generate`
- `map_create_blockout`
- `map_refine_visuals`
- `map_validate`
- `map_readiness_check`
- `studio_read_output`
- `studio_start_playtest`
- `studio_stop_playtest`

## Backups And Captures

`studio_export_model` takes a managed `rootPath` and saves a native `.rbxm` under `generated/exports`. Select a specific map or subtree, not the managed container itself. Limits are 10,000 instances and 8 MiB of binary data. The result contains the local artifact path and counts, not the encoded model. It does not modify the selected root or upload it.

`studio_capture_viewport` accepts optional integer `width` and `height` from 1 to 4096 and saves a viewport-only PNG under `generated/captures`. It requires native Studio screenshot permission and an active rendered place. Grant permission with the plugin's `Allow viewport capture` button. Tool calls never prompt. An unavailable capture returns an error without falling back to desktop screenshots.

Files use unique names and are never overwritten. Failed writes remove only the newly created artifact. POSIX artifact directories are restricted to mode `0700` and files to `0600`; Windows uses the enclosing directory's ACL. Binary results are capped at 8 MiB, decoded and signature-checked before saving. Only `/plugin/result` permits a 16 MiB JSON envelope for base64 transport. Other request bodies retain their 1 MiB limit. Encoded data is redacted from logs. Captures preserve viewport proportions when either output dimension is omitted.

Symbolic artifact directories are rejected before permission changes or file creation. If cleanup fails after a partial write, the error identifies the owned path and includes both failures. Inferred capture dimensions must also fit 1-4096 pixels. Unsupported combinations fail rather than silently stretching or changing a requested dimension.

## Automated Tests

`studio_run_test` takes `modulePath`, `confirmToken="RUN_STUDIO_TEST"`, `mode="run"` or `"play"`, optional JSON `args`, and `timeoutSeconds` from 1 to 120. The ModuleScript must be inside a managed root and return a function accepting `args`. Its return value must be JSON-serializable.

The bridge creates a temporary server runner, starts the native Studio test, returns `{ok,result}` or `{ok:false,error}`, and removes the runner from edit mode afterward. Failed tests also set the MCP `isError` flag. A test-server deadline and an edit-side Stop watchdog handle timeouts. These are not an operating-system hard kill. A frozen Studio process can still require a restart.

Run reviewed project code only. Tests and the place's existing scripts execute with ordinary game-script access, including any enabled persistent or external services. The managed-root check restricts test selection, not runtime behavior. Simulation changes are discarded when the test ends, but DataStore and external writes are not rolled back. Legacy `studio_start_playtest` and `studio_stop_playtest` keep their manual-action response for compatibility.

## SceneSpec build flow

1. Convert the prompt into a SceneSpec with `mapName`, `rootPath`, terrain, zones, instances, `functionalObjects`, and optional scripts.
2. Use `Workspace/MapDrafts` for new maps.
3. Set `layout.grounding` for placed maps. Default `mode=raycast` samples the current Workspace surface; `mode=manual` uses `groundY`; `mode=none` is only for intentional sky/void maps.
4. Organize multilevel maps with named folders/models and unique instance names.
5. Include a readable player route: spawn, path, entry platform, and a functional door/opening.
6. Put doors, buttons, lifts, teleporters, and checkpoints in `functionalObjects`; the plugin adds ProximityPrompts and a scoped `MapInteractions` runtime script. Doors should set `autoCloseSeconds` unless they are intentionally persistent. When a visible door panel already exists in `instances`, set `target` to that part instead of creating a second functional door.
7. Set `codegen.target` to `studio`, `rojo`, or `both`. `both` writes runtime/scripts into Studio and mirrors Luau plus `default.project.json` under `generated/rojo/<mapName>`.
8. Call `map_apply_scene_spec` with `dryRun=true`; review target root, counts, services, and risks.
9. Call `map_apply_scene_spec` with `dryRun=false`; run `map_validate` with `strictGeometry=true`; then run `map_readiness_check` with the correct profile.

`map_validate` checks the safe root, spawn count, anchoring, terrain penetration on player surfaces, stair landing/headroom, and likely solid overlaps. It is not final visual readiness. `map_readiness_check` is the final contract gate for visible assemblies such as house doors, balconies, roofs, and stair headroom. Warnings are not fatal, but a generator should treat terrain intersections, unreachable stairs, ceiling-blocked stairs, blocked doorways, and broken facade contracts as rebuild triggers.

For iterative visual repair, use `studio_patch_instances` for batched create/set/delete edits inside generated roots. Use `studio_focus_instance` or `studio_set_camera` to move the Studio viewport, then `studio_visual_probe` to raycast a viewport grid and report visible hit parts before calling a build ready.

`Workspace/AI_Generated` is accepted only for migrating older maps.

When an instance provides both `CFrame` and `Position`, `CFrame` takes precedence for placement and grounding.
