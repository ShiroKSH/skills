import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { StudioBridge } from "../src/protocol.js";
import { loadConfig } from "../src/security/config.js";
import { CommandLogger } from "../src/logs/commandLogger.js";

describe("Studio HTTP bridge", () => {
  const token = "test-only-bridge-token-not-a-credential";
  let bridge: StudioBridge;
  let logger: CommandLogger;
  let baseUrl: string;

  async function post(path: string, fields: Record<string, unknown> = {}) {
    return fetch(`${baseUrl}/plugin/${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token, clientId: "studio-a", ...fields })
    });
  }

  beforeEach(async () => {
    logger = new CommandLogger("logs/test");
    vi.spyOn(logger, "log").mockResolvedValue();
    bridge = new StudioBridge({ ...loadConfig({ ROBLOX_STUDIO_BRIDGE_TOKEN: token }), port: 0 }, logger);
    await bridge.start();
    baseUrl = `http://127.0.0.1:${bridge.getStatus().server.port}`;
  });

  afterEach(async () => {
    await bridge.stop();
    vi.restoreAllMocks();
  });

  it("authenticates before registration and keeps health metadata private", async () => {
    expect((await post("register", { token: "wrong" })).status).toBe(401);
    expect((await post("poll")).status).toBe(409);
    await post("register", { placeName: "Private place" });
    const health = await (await fetch(`${baseUrl}/health`)).json();
    expect(health).toEqual({ ok: true, status: "running", connected: true });
  });

  it("reports malformed JSON and non-object payloads as client errors", async () => {
    for (const body of ["{", "null", "[]", '"text"']) {
      const response = await fetch(`${baseUrl}/plugin/register`, { method: "POST", body });
      expect(response.status).toBe(400);
    }
  });

  it("stays connected throughout a 25 second idle poll", async () => {
    await post("register");
    const now = Date.now();
    vi.spyOn(Date, "now").mockReturnValue(now + 26_000);
    expect(bridge.getStatus().connected).toBe(true);
    vi.mocked(Date.now).mockReturnValue(now + 36_000);
    expect(bridge.getStatus().connected).toBe(false);
  });

  it("delivers a command once and resolves its Studio result", async () => {
    await post("register");
    const result = bridge.sendCommand("studio_ping", {});
    const { command } = await (await post("poll")).json();
    expect(command.name).toBe("studio_ping");
    expect(Date.parse(command.expiresAt)).toBeGreaterThan(Date.parse(command.createdAt));
    expect((await post("result", { commandId: command.id, ok: true, result: { status: "Connected" } })).status).toBe(200);
    await expect(result).resolves.toEqual({ status: "Connected" });
    expect((await post("result", { commandId: command.id, ok: true })).status).toBe(200);
  });

  it("removes timed-out edits instead of executing them on a later poll", async () => {
    await post("register");
    await expect(bridge.sendCommand("studio_create_instance", { name: "Expired" }, 20)).rejects.toThrow("Timed out");
    const current = bridge.sendCommand("studio_ping", {});
    const { command } = await (await post("poll")).json();
    expect(command.name).toBe("studio_ping");
    await post("result", { commandId: command.id, ok: true, result: "alive" });
    await expect(current).resolves.toBe("alive");
  });

  it("does not let another Studio steal an active session or its queue", async () => {
    await post("register");
    expect((await post("register", { clientId: "studio-b" })).status).toBe(409);
    expect((await post("poll", { clientId: "studio-b" })).status).toBe(409);
    expect(bridge.getStatus().plugin?.clientId).toBe("studio-a");
  });

  it("rejects missing client IDs without consuming commands or accepting results", async () => {
    expect((await post("register", { clientId: undefined })).status).toBe(400);
    await post("register");
    const result = bridge.sendCommand("studio_ping", {});
    expect((await post("poll", { clientId: undefined })).status).toBe(409);
    const { command } = await (await post("poll")).json();
    expect((await post("result", { clientId: undefined, commandId: command.id, ok: true })).status).toBe(409);
    await post("result", { commandId: command.id, ok: true, result: "correct session" });
    await expect(result).resolves.toBe("correct session");
  });

  it("rejects pending work promptly on shutdown", async () => {
    await post("register");
    const result = bridge.sendCommand("studio_ping", {});
    const rejection = expect(result).rejects.toThrow("bridge stopped");
    await (await post("poll")).json();
    await bridge.stop();
    await rejection;
    expect(bridge.getStatus().connected).toBe(false);
  });

  it("rejects old work when a stale Studio owner is replaced", async () => {
    await post("register");
    const result = bridge.sendCommand("studio_create_instance", {});
    const rejection = expect(result).rejects.toThrow("Studio session changed");
    await vi.waitFor(() => expect(logger.log).toHaveBeenCalledWith("command_queued", expect.anything()));
    const now = Date.now();
    vi.spyOn(Date, "now").mockReturnValue(now + 36_000);
    expect((await post("register", { clientId: "studio-b" })).status).toBe(200);
    await rejection;
    expect((await post("result", { commandId: "old", ok: true })).status).toBe(409);
    const fresh = bridge.sendCommand("studio_ping", {});
    const { command } = await (await post("poll", { clientId: "studio-b" })).json();
    expect(command.name).toBe("studio_ping");
    await post("result", { clientId: "studio-b", commandId: command.id, ok: true, result: "new place" });
    await expect(fresh).resolves.toBe("new place");
  });

  it("settles a completed command even when result logging fails", async () => {
    await post("register");
    const result = bridge.sendCommand("studio_ping", {});
    const { command } = await (await post("poll")).json();
    vi.mocked(logger.log).mockRejectedValueOnce(new Error("Disk full"));
    expect((await post("result", { commandId: command.id, ok: true, result: "done" })).status).toBe(500);
    await expect(result).resolves.toBe("done");
  });
});
