# Skills

`roblox-studio` connects Claude Code, Codex, Cursor, Gemini CLI, and other coding agents to the place open in Roblox Studio.

The agent can inspect the hierarchy, draft a SceneSpec, create terrain and geometry, write scoped Luau, patch generated instances, mirror code to Rojo, validate the map, and coordinate playtests. Studio changes use Undo recording and new builds stay under `Workspace/MapDrafts`.

```text
Prompt -> inspect -> SceneSpec -> dry run -> apply -> validate -> playtest
```

![Roblox Studio cabin generated through the bridge](assets/evolution/v4-exterior-pass.png)

## Install

### Claude Code

The marketplace plugin includes the skill and starts the local MCP server:

```text
/plugin marketplace add ShiroKSH/skills
/plugin install roblox-studio@skills
```

### Codex

```sh
npx skills add ShiroKSH/skills -g
codex mcp add roblox-studio -- npx -y github:ShiroKSH/skills
```

Restart Codex after adding the MCP server.

### Cursor, Copilot, Gemini CLI, and other hosts

Install the skill:

```sh
npx skills add ShiroKSH/skills -g
```

Add the bridge as a stdio MCP server:

```json
{
  "mcpServers": {
    "roblox-studio": {
      "command": "npx",
      "args": ["-y", "github:ShiroKSH/skills"]
    }
  }
}
```

Requirements: Node.js 20 or newer and Roblox Studio.

## Install the Studio plugin

Download [RobloxStudioBridge.rbxm from the latest release](https://github.com/ShiroKSH/skills/releases/latest/download/RobloxStudioBridge.rbxm) and put it in `%LOCALAPPDATA%\Roblox\Plugins` on Windows or `~/Documents/Roblox/Plugins` on macOS. Restart Studio after installing or updating it.

To build from source, install [Rokit](https://github.com/rojo-rbx/rokit), then run:

```sh
git clone https://github.com/ShiroKSH/skills.git
cd skills
rokit install
npm install
npm run install:plugin
```

The command builds `dist/RobloxStudioBridge.rbxm` with Rojo and copies it into the local Roblox plugins directory on Windows or macOS. The project pins Rojo and Lune in `rokit.toml`.

Manual fallback: run `npm run build:plugin`, then copy the `.rbxm` file into `%LOCALAPPDATA%\Roblox\Plugins` on Windows or `~/Documents/Roblox/Plugins` on macOS.

## Connect Studio

1. Enable HTTP requests for the place.
2. Open the `Roblox Studio Bridge` plugin panel.
3. Keep host `127.0.0.1` and port `3765`.
4. Paste the token printed by the MCP server and select `Connect`.
5. Run `studio_ping` from the agent.

The token is generated locally, is never a Roblox credential, is not persisted by the plugin, and is cleared from the panel after connection. Set `ROBLOX_STUDIO_BRIDGE_TOKEN` only when a stable local token is needed.

The panel reconnects after a server restart while the token stays the same. If the server generates a new token, select `Connect` with that token. Only one Studio session can own a bridge connection. Update the server and the plugin together.

## What the bridge exposes

- Bounded hierarchy and property inspection.
- SceneSpec map builds and graybox passes.
- Terrain generation through Studio APIs.
- Batched create, set, ensure, and delete operations inside managed roots.
- Camera control and viewport raycast probes for visual checks.
- Doors, buttons, elevators, teleporters, checkpoints, and scoped runtime scripts.
- Geometry validation, map-readiness contracts, trusted ModuleScript tests in actual Run or Play mode, and Studio output.
- Private binary model backups and native viewport-only PNG captures.
- Rojo projects under `generated/rojo/<mapName>` when `codegen.target` is `rojo` or `both`.

The full MCP tool list and protocol are documented in [docs/protocol.md](docs/protocol.md). SceneSpec fields are defined in [docs/scene-spec.schema.json](docs/scene-spec.schema.json).

## Map workflow

1. Run `studio_ping` and inspect the relevant place hierarchy.
2. Build a SceneSpec rooted at `Workspace/MapDrafts`.
3. Run `map_apply_scene_spec` with `dryRun=true`.
4. Review the target root, object count, touched services, scripts, filesystem writes, terrain, and risks.
5. Apply with `dryRun=false`.
6. Run `map_validate` on the returned map root with strict geometry enabled.
7. Run `map_readiness_check` for playable builds.
8. Inspect several camera angles, playtest interactions, read Studio output, and patch concrete failures.

Start with [examples/simple-obby.scene.json](examples/simple-obby.scene.json) for a minimal spec or [examples/vertical-bazaar.scene.json](examples/vertical-bazaar.scene.json) for a layered map. Every apply writes a filesystem manifest under `logs/manifests/` and a `SceneManifest` value under the generated map root.

## Gameplay Example

[Cash Cleaner](examples/cash-cleaner/README.md) contains the server runtime, production-state logic, and executable tests from a real tycoon map. The example fixes abandoned ownership, lost in-process inventory, and duplicate completion payouts, then adds live station countdowns and next-step feedback. Eight gameplay checks passed in Studio through MCP with 13 active prompts and four station displays.

Use `studio_export_model` to save a managed build root under `generated/exports` before a repair. Use `studio_run_test` with a reviewed test ModuleScript and `confirmToken="RUN_STUDIO_TEST"` to exercise behavior. Tests execute project code, not sandboxed code.

For images, select `Allow viewport capture` in the plugin panel once, then call `studio_capture_viewport`. Images stay under `generated/captures`. The tool never opens permission dialogs or captures desktop panels. Check in-world text before publishing a frame.

## Build evolution

These are cropped Roblox viewport frames from real iterations. Desktop chrome, chats, usernames, paths, tokens, and unrelated files are excluded.

| V1 first pass | V4 exterior pass |
| --- | --- |
| ![V1 night cabin](assets/evolution/v1-night-pass.png) | ![V4 cabin exterior](assets/evolution/v4-exterior-pass.png) |

| V4 balcony | V4 window and chimney |
| --- | --- |
| ![V4 balcony detail](assets/evolution/v4-balcony-detail.png) | ![V4 window detail](assets/evolution/v4-window-detail.png) |

## Safety

- The HTTP bridge binds to loopback only; the Studio plugin rejects non-loopback hosts.
- Every plugin endpoint except minimal health status requires the shared token.
- Poll credentials are sent in a POST body, not a URL.
- Dangerous Luau execution is disabled by default and filtered again in Studio.
- Deletes require `DELETE_MAP_DRAFTS` and remain limited to managed build roots.
- External asset IDs require an explicit allowlist.
- Command logs redact tokens, source, code, cookies, passwords, and confirmation values.
- Studio changes use `ChangeHistoryService` recording with a waypoint fallback.

See [docs/safety.md](docs/safety.md) for the full boundary.

## Final result

The same workflow can move from an early blockout to a connected, interactive Roblox place, then keep repairing it from validation and playtest feedback:

| Latest playtest | Latest station detail |
| --- | --- |
| ![Latest generated Roblox playtest](assets/evolution/latest-playtest.png) | ![Latest generated station detail](assets/evolution/latest-station-detail.png) |

## Development

```sh
npm install
rokit install
npm run check
npm run validate:skill
npm run test:plugin
npm run test:example
```

`check` runs the TypeScript build and HTTP/tool tests. `test:plugin` builds the `.rbxm`, compiles its Luau modules, and runs scene and transport regressions in Lune. It does not replace an in-Studio visual or playtest check.

Pull requests receive automatic reviews from CodeRabbit, Qodo, and Sourcery. GitHub
CodeQL scans JavaScript and TypeScript changes, while Dependabot opens grouped weekly
dependency updates and immediate security-fix PRs. Automated suggestions still need
to be verified against the tests and the Roblox Studio safety boundaries.

More detail: [Contributing](CONTRIBUTING.md), [Protocol](docs/protocol.md), [Safety](docs/safety.md), [Troubleshooting](docs/troubleshooting.md), and [Changelog](CHANGELOG.md).
