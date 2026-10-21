# Troubleshooting

## `studio_ping` says offline

- Start Roblox Studio.
- Enable HTTP requests in Studio game settings.
- Build/install the plugin and click `Connect`.
- Paste the exact token printed by the MCP server or set `ROBLOX_STUDIO_BRIDGE_TOKEN` before starting both sides.
- Confirm port `3765` is free.

## Plugin says register failed

- Check that the MCP server is running.
- Check host `127.0.0.1` and port.
- Check token length and copy/paste whitespace.

## Connection rejected or authentication failed

- Update both the MCP server and Studio plugin to 0.2.0, then restart them.
- Disconnect another Studio session using the same bridge. After a closed session stops polling, ownership expires in 35 seconds.
- If the server restarted with a new token, paste that token and connect again. A stable `ROBLOX_STUDIO_BRIDGE_TOKEN` allows automatic reconnection.

## A command timed out

- Inspect Studio before retrying an edit. A running edit may have completed even if its result was lost.
- Queued commands expire and are not replayed after reconnection.
- The plugin retries result delivery, not the scene edit itself.

## Studio reports an expired channel build

Install the current production Roblox Studio from [Roblox Create](https://create.roblox.com/). This is a Studio installation error, not a bridge token error. The MCP bridge cannot update or bypass an expired Studio build.

## Apply fails after dry-run

- Read `risks` from the dry-run response.
- Keep `rootPath` as `Workspace/MapDrafts` for new work.
- Use `Workspace/AI_Generated` only when migrating an older map.
- Lower object count or terrain size if a configured limit blocks apply.

## Rojo is missing

Install Rojo from https://rojo.space or use any existing local Rojo install, then run:

```sh
rojo build plugin/plugin.project.json -o dist/RobloxStudioBridge.rbxm
```

Manual fallback: create a local Studio plugin script from `plugin/src/init.lua` and include the `Bridge` ModuleScripts as children.
