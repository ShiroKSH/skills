# Changelog

## 0.2.1 - Unreleased

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
