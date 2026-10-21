# Cash Cleaner

An executable gameplay example from a real bridge-built tycoon map. The loop is collect, inspect, wash, dry, count, bundle, ship, then upgrade.

## What Changed

- Leaving releases the business and refunds unfinished batches to that player's inventory.
- Processing bills still occupy capacity. A pickup cannot bypass the inventory limit.
- Unique job IDs prevent stale completion callbacks from crediting another owner or paying twice.
- Four station displays show batch size and remaining time. The HUD keeps the next step visible after notifications expire.
- Prompt handlers check ownership, distance, character health, and cooldown on the server.

Progress stays in memory for the current server session. This example does not add DataStore persistence or publish a place.

## Files

Place these sources in the existing generated map's `Gameplay` folder. `CleanerState` and both test files are ModuleScripts. `Runtime.server.luau` is a server Script. Remove the old runtime from the working copy before enabling its replacement.

The runtime expects the existing `GameplayV5/InteractionPads` layout. Pad names are listed in the runtime. The map model itself is not included in this public example.

```text
Workspace/MapDrafts/<map>/Gameplay
  CleanerState
  CleanerStateTests
  IntegrationTest
  Runtime
```

Run the logic checks locally with Lune.

```sh
npm run test:example
```

Run the integration test against a reviewed working copy through MCP.

```json
{
  "modulePath": "Workspace/MapDrafts/<map>/Gameplay/IntegrationTest",
  "confirmToken": "RUN_STUDIO_TEST",
  "mode": "run",
  "timeoutSeconds": 20
}
```

Verified in Roblox Studio 0.743 through the MCP bridge. Eight gameplay checks passed with 13 active prompts and four station countdowns. A native Play-mode test also verified the player spawn and three populated HUD labels. The checks cover owner release, cancellation at every station, inventory conservation, stale jobs, the complete sale loop, foreign-player access, and upgrade charging. The sanitized results are in [verification.json](verification.json).

For a private backup, call `studio_export_model` on the map root. For a viewport image, grant screenshot permission from the plugin panel, then call `studio_capture_viewport`. Both transfer their result to the local MCP server and save a local file. Neither uploads to a cloud service. Inspect every image before sharing it because in-world text can still contain personal information.
