import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { timingSafeEqual, randomUUID } from "node:crypto";
import { URL } from "node:url";
import type { BridgeConfig } from "./security/config.js";
import type { CommandLogger } from "./logs/commandLogger.js";

type PluginInfo = {
  clientId: string;
  pluginVersion: string;
  placeName: string;
  placeId: number | string;
  status: string;
};

type QueuedCommand = {
  id: string;
  name: string;
  args: unknown;
  createdAt: string;
  expiresAt: string;
};

type PendingCommand = {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
  clientId: string;
};

type PollWaiter = {
  response: ServerResponse;
  timer: NodeJS.Timeout;
};

export type BridgeStatus = {
  server: {
    host: string;
    port: number;
  };
  connected: boolean;
  lastSeenAt?: string;
  plugin?: PluginInfo;
};

export class StudioBridge {
  private server?: Server;
  private plugin?: PluginInfo;
  private lastSeenAt = 0;
  private readonly queue: QueuedCommand[] = [];
  private readonly pending = new Map<string, PendingCommand>();
  private readonly waiters: PollWaiter[] = [];
  private readonly outputLines: string[] = [];
  private stopping = false;

  constructor(
    private readonly config: BridgeConfig,
    private readonly logger: CommandLogger
  ) {}

  async start(): Promise<void> {
    if (this.server) {
      return;
    }

    this.stopping = false;
    const server = createServer((request, response) => {
      void this.handleRequest(request, response).catch((error: unknown) => {
        const statusCode = error instanceof RequestError ? error.statusCode : 500;
        this.sendJson(response, statusCode, { ok: false, error: error instanceof Error ? error.message : String(error) });
      });
    });

    await new Promise<void>((resolveStart, rejectStart) => {
      server.once("error", rejectStart);
      server.listen(this.config.port, this.config.host, () => {
        server.removeListener("error", rejectStart);
        resolveStart();
      });
    });
    this.server = server;
  }

  async stop(): Promise<void> {
    this.stopping = true;
    this.plugin = undefined;
    this.lastSeenAt = 0;
    this.queue.length = 0;
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Error("Studio bridge stopped before the command completed"));
    }
    this.pending.clear();
    for (const waiter of this.waiters.splice(0)) {
      clearTimeout(waiter.timer);
      this.sendJson(waiter.response, 200, { ok: true, command: null });
    }

    await new Promise<void>((resolveStop) => {
      if (!this.server) {
        resolveStop();
        return;
      }
      this.server.close(() => resolveStop());
      this.server.closeAllConnections();
      this.server = undefined;
    });
  }

  getStatus(): BridgeStatus {
    const connected = !this.stopping && !!this.plugin
      && (Date.now() - this.lastSeenAt < 35_000 || this.pending.size > 0);
    const address = this.server?.address();
    return {
      server: {
        host: this.config.host,
        port: address && typeof address !== "string" ? address.port : this.config.port
      },
      connected,
      lastSeenAt: this.lastSeenAt > 0 ? new Date(this.lastSeenAt).toISOString() : undefined,
      plugin: this.plugin
    };
  }

  readOutput(lineCount: number): string[] {
    return this.outputLines.slice(-lineCount);
  }

  async sendCommand(name: string, args: unknown, timeoutMs = this.config.commandTimeoutMs): Promise<unknown> {
    if (!this.getStatus().connected) {
      throw new Error("Roblox Studio plugin is not connected. Open Studio, install plugin, set token, then Connect.");
    }

    const command: QueuedCommand = {
      id: randomUUID(),
      name,
      args,
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + timeoutMs).toISOString()
    };
    const clientId = this.plugin!.clientId;

    await this.logger.log("command_requested", { commandId: command.id, name, args });
    if (!this.getStatus().connected || this.plugin?.clientId !== clientId) {
      throw new Error("Studio connection changed before the command was queued");
    }
    const remainingMs = Date.parse(command.expiresAt) - Date.now();
    if (remainingMs <= 0) {
      throw new Error(`Timed out before queuing Studio command ${name}`);
    }

    const resultPromise = new Promise<unknown>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(command.id);
        const index = this.queue.findIndex((queued) => queued.id === command.id);
        if (index >= 0) this.queue.splice(index, 1);
        reject(new Error(`Timed out waiting for Studio result for ${name}`));
      }, remainingMs);
      this.pending.set(command.id, { resolve, reject, timer, clientId });
    });

    this.queue.push(command);
    this.flushPollWaiter();
    return resultPromise;
  }

  private async handleRequest(request: IncomingMessage, response: ServerResponse): Promise<void> {
    const url = new URL(request.url ?? "/", "http://localhost");

    if (request.method === "GET" && url.pathname === "/health") {
      this.sendJson(response, 200, {
        ok: true,
        status: "running",
        connected: this.getStatus().connected
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/plugin/register") {
      const body = await this.readJson(request);
      this.requireBodyToken(body);
      const clientId = body.clientId;
      if (typeof clientId !== "string" || !clientId.trim()) {
        throw new RequestError(400, "A non-empty Studio clientId is required");
      }
      if (this.getStatus().connected && this.plugin?.clientId !== clientId) {
        throw new RequestError(409, "Another Studio session is connected");
      }
      if (this.plugin && this.plugin.clientId !== clientId) {
        for (const pending of this.pending.values()) {
          clearTimeout(pending.timer);
          pending.reject(new Error("Studio session changed before the command completed"));
        }
        this.pending.clear();
        this.queue.length = 0;
        for (const waiter of this.waiters.splice(0)) {
          clearTimeout(waiter.timer);
          this.sendJson(waiter.response, 409, { ok: false, error: "Studio session changed" });
        }
      }
      this.lastSeenAt = Date.now();
      this.plugin = {
        clientId,
        pluginVersion: String(body.pluginVersion ?? "unknown"),
        placeName: String(body.placeName ?? "unknown"),
        placeId: String(body.placeId ?? "unknown"),
        status: String(body.status ?? "Connected")
      };
      await this.logger.log("plugin_registered", { plugin: this.plugin });
      this.sendJson(response, 200, { ok: true, serverVersion: "0.2.3" });
      return;
    }

    if (request.method === "POST" && url.pathname === "/plugin/poll") {
      const body = await this.readJson(request);
      this.requireBodyToken(body);
      this.requireClient(body);
      this.lastSeenAt = Date.now();
      this.holdOrSendCommand(response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/plugin/result") {
      const body = await this.readJson(request, 16 * 1024 * 1024);
      this.requireBodyToken(body);
      this.requireClient(body);
      this.lastSeenAt = Date.now();
      await this.receiveResult(body);
      this.sendJson(response, 200, { ok: true });
      return;
    }

    if (request.method === "POST" && url.pathname === "/plugin/output") {
      const body = await this.readJson(request);
      this.requireBodyToken(body);
      this.requireClient(body);
      const lines = Array.isArray(body.lines) ? body.lines.map(String) : [String(body.line ?? "")];
      this.outputLines.push(...lines.filter((line) => line.length > 0));
      while (this.outputLines.length > 500) {
        this.outputLines.shift();
      }
      this.sendJson(response, 200, { ok: true });
      return;
    }

    this.sendJson(response, 404, { ok: false, error: "Not found" });
  }

  private holdOrSendCommand(response: ServerResponse): void {
    if (response.destroyed) return;
    const command = this.queue.shift();
    if (command) {
      this.sendJson(response, 200, { ok: true, command });
      return;
    }

    const waiter: PollWaiter = {
      response,
      timer: setTimeout(() => {
        const index = this.waiters.indexOf(waiter);
        if (index >= 0) {
          this.waiters.splice(index, 1);
        }
        this.sendJson(response, 200, { ok: true, command: null });
      }, 25_000)
    };
    this.waiters.push(waiter);
    response.once("close", () => {
      clearTimeout(waiter.timer);
      const index = this.waiters.indexOf(waiter);
      if (index >= 0) this.waiters.splice(index, 1);
    });
  }

  private flushPollWaiter(): void {
    while (this.waiters.length && this.queue.length) {
      const waiter = this.waiters.shift()!;
      if (waiter.response.destroyed || waiter.response.writableEnded) {
        clearTimeout(waiter.timer);
        continue;
      }
      const command = this.queue.shift()!;
      clearTimeout(waiter.timer);
      this.sendJson(waiter.response, 200, { ok: true, command });
      return;
    }
  }

  private async receiveResult(body: Record<string, unknown>): Promise<void> {
    const commandId = String(body.commandId ?? "");
    const pending = this.pending.get(commandId);
    if (!pending) {
      await this.logger.log("command_result_unmatched", { commandId });
      return;
    }
    if (pending.clientId !== this.plugin?.clientId) {
      throw new RequestError(409, "Command belongs to another Studio session");
    }

    this.pending.delete(commandId);
    clearTimeout(pending.timer);
    try {
      await this.logger.log("command_result", { commandId, ok: body.ok === true });
    } finally {
      if (body.ok === true) {
        pending.resolve(body.result);
      } else {
        pending.reject(new Error(String(body.error ?? "Studio command failed")));
      }
    }
  }

  private async readJson(request: IncomingMessage, maximumBytes = 1_000_000): Promise<Record<string, unknown>> {
    const chunks: Buffer[] = [];
    let total = 0;

    for await (const chunk of request.iterator({ destroyOnReturn: false })) {
      const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      total += buffer.length;
      if (total > maximumBytes) {
        request.resume();
        throw new RequestError(413, "Request body too large");
      }
      chunks.push(buffer);
    }

    const text = Buffer.concat(chunks).toString("utf8");
    if (!text) {
      return {};
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new RequestError(400, "Request body must be valid JSON");
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new RequestError(400, "Request body must be a JSON object");
    }
    return parsed as Record<string, unknown>;
  }

  private requireClient(body: Record<string, unknown>): void {
    if (!this.plugin || body.clientId !== this.plugin.clientId) {
      throw new RequestError(409, "Register this Studio session before polling or sending results");
    }
  }

  private requireBodyToken(body: Record<string, unknown>): void {
    this.requireToken(String(body.token ?? ""));
  }

  private requireToken(candidate: string): void {
    const expected = Buffer.from(this.config.token);
    const actual = Buffer.from(candidate);
    if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
      throw new RequestError(401, "Invalid bridge token");
    }
  }

  private sendJson(response: ServerResponse, statusCode: number, body: unknown): void {
    if (response.writableEnded || response.destroyed) {
      return;
    }
    response.writeHead(statusCode, {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...(statusCode === 413 ? { connection: "close" } : {})
    });
    response.end(JSON.stringify(body));
  }
}

class RequestError extends Error {
  constructor(readonly statusCode: number, message: string) {
    super(message);
  }
}
