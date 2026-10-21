# Safety

## Trust model

- Trusted: the user, the selected coding agent, this local MCP process, and the installed Studio plugin.
- Untrusted by default: generated Luau, external asset IDs, arbitrary network hosts, unrelated local processes, and existing place content outside managed roots.
- Protected assets: the open Roblox place, local bridge token, project files, command logs, and generated Rojo output.
- Boundaries: agent to MCP over stdio, MCP to Studio over authenticated loopback HTTP, and plugin commands to Studio APIs under Undo recording.

## Controls

- Local-first only. Server binds to `127.0.0.1` by default and rejects non-loopback hosts.
- Shared token required for every plugin endpoint except `/health`.
- The health endpoint returns only process and connection state; place metadata requires the shared token.
- Polling sends the token in a POST body, never in a URL. The Studio plugin accepts loopback hosts only.
- The Studio plugin keeps the token in memory for the current connection and clears the input after use.
- No Roblox credentials, `.ROBLOSECURITY`, or external asset IDs are needed.
- `studio_execute_luau` is disabled unless `ROBLOX_STUDIO_BRIDGE_ALLOW_DANGEROUS_LUAU=1` and the plugin setting is also enabled.
- Dangerous Luau blocks `require(assetId)`, `HttpService`, `loadstring`, `InsertService`, `.ROBLOSECURITY`, and `PluginSecurity`.
- New SceneSpecs target `Workspace/MapDrafts`.
- `Workspace/AI_Generated` remains accepted only for migrating older maps.
- `studio_delete_instances` requires `confirmToken`; use it only for generated build roots.
- All commands are logged to `logs/commands.jsonl` with tokens, source, code, and binary data redacted.
- `map_apply_scene_spec dryRun=true` runs locally in the MCP server and returns object count, touched services, and risks.
- Apply writes a filesystem manifest under `logs/manifests/.../map_manifest.json`; the plugin also creates `SceneManifest` under the map root.
- Studio changes are wrapped in `ChangeHistoryService` recording when available, with `SetWaypoint` fallback.
- Model backups and viewport captures stay in ignored local `generated` directories. They are not automatically shared or uploaded.
- Viewport capture requires native permission granted by a user-clicked button. Agents cannot trigger the permission dialog through the capture tool. Desktop and Studio panels are excluded, but in-world text still needs a privacy review before sharing.
- `studio_run_test` requires `RUN_STUDIO_TEST` confirmation and a reviewed managed ModuleScript. This explicitly executes trusted project code and is not a sandbox. Test only a working copy with persistent/external writes disabled or mocked. A timeout stops the simulation when Studio remains responsive, not a frozen operating-system process.
