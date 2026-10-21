# Changelog

## 0.2.3 - 2026-10-21

- Export managed map roots as private native Roblox models with size limits, unique filenames, and binary log redaction.
- Run reviewed ModuleScript tests in native Studio Run or Play mode with explicit confirmation, timeout cleanup, and an edit-side stop watchdog.
- Capture viewport-only PNGs after user-granted native permission without automatic prompts or desktop capture.
- Add the Cash Cleaner gameplay example with ownership release, cancelled-job refunds, capacity conservation, station countdowns, and eight executable regression checks.
- Require a specific export subtree instead of a managed container, keep the closed example door collidable, and synchronize both agent plugin manifests.
- Restrict artifact permissions on POSIX, clean up failed writes, propagate test failures as MCP errors, recover from unserializable results, and preserve viewport proportions when dimensions are omitted.
- Drain oversized HTTP requests and close their connection explicitly so later commands use a clean connection.

## 0.2.2 - 2026-10-21

- Rotate the Studio client identity after a place change so reconnecting cannot consume the previous place's queued edits.
- Clean up draft roots when grounding or zone creation fails, and preserve original error locations.
- Make the long-command ownership regression independent of a short wall-clock timeout and verify queues remain with the original client.

## 0.2.1 - 2026-10-21

- Keep session ownership while a command is pending and use its original deadline when logging delays dispatch.
- Stop before executing a polled command when the Studio place changes.
- Retry completed result delivery until acknowledgement, rejection, disconnect, or the command deadline without replaying edits.
- Give CFrame precedence over Position consistently during SceneSpec grounding and creation.
- Remove newly created draft instances when nested parent resolution fails, including without an Undo recording.
- Distinguish command requests and unmatched result acknowledgements in logs instead of reporting unqueued edits or false orphan results.

## 0.2.0 - 2026-10-21

- Reconnect after bridge restarts, cancel disconnected polls, retry result delivery without replaying edits, and reject expired commands.
- Bind queued work to one Studio client, clear timed-out commands, and settle pending commands when the bridge stops or logging fails.
- Resolve nested SceneSpec parents regardless of declaration order and report missing or cyclic parent paths.
- Preserve CFrame rotation and account for rotated part bounds when grounding generated maps.
- Refresh the plugin panel with Studio theme colors, responsive connection fields, a Connect/Disconnect toggle, and scrollable activity logs.
- Add HTTP integration coverage and executable Luau regression tests against the built plugin model.
- Update the MCP SDK, test runner, and transitive dependencies to resolve the reported npm advisories.

- Add automatic CodeRabbit, Qodo, Sourcery, CodeQL, Dependabot, and secret-scanning review layers for pull requests.
- Rename the repository to `skills` and the bundled integration to `roblox-studio`.
- Add Claude Code and Codex marketplace metadata plus a bundled stdio MCP configuration.
- Expand the Roblox Studio skill with setup, SceneSpec, repair, validation, visual inspection, and playtest workflows.
- Add one-command Studio plugin installation for Windows and macOS.
- Keep bridge traffic on loopback, move polling credentials out of URLs, and stop persisting the local token in Studio settings.
