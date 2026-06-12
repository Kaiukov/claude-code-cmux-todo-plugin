/**
 * coms-net.ts — Pi extension: structured completion event emitter + tools
 *
 * Ported from disler/pi-vs-claude-code (MIT).
 * https://github.com/disler/pi-vs-claude-code
 *
 * On agent_end, emits a structured `done` event to the coms-net hub so the
 * orchestrator can receive worker completion via an event bus instead of
 * screen-scraping or git-polling.
 *
 * Also exposes tools: coms_net_send, coms_net_get, coms_net_await, coms_net_list.
 *
 * Env:
 *   COMS_NET_HUB_URL  — hub base URL (default http://127.0.0.1:9876)
 *   COMS_NET_TOKEN    — shared auth token
 *   COMS_NET_CHANNEL  — explicit channel; falls back to ctx.cwd
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { StringEnum } from "@earendil-works/pi-ai";

function hubUrl(): string {
  return process.env.COMS_NET_HUB_URL || "http://127.0.0.1:9876";
}

function authToken(): string {
  return process.env.COMS_NET_TOKEN || "";
}

function channelKey(ctxCwd: string): string {
  return process.env.COMS_NET_CHANNEL || ctxCwd;
}

async function postEvent(
  channel: string,
  type: string,
  extra: Record<string, unknown> = {},
): Promise<{ ok: boolean; error?: string }> {
  const token = authToken();
  if (!token) return { ok: false, error: "COMS_NET_TOKEN not set" };

  try {
    const resp = await fetch(`${hubUrl()}/send?channel=${encodeURIComponent(channel)}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ type, channel, ...extra }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!resp.ok) {
      const body = await resp.text();
      return { ok: false, error: `hub returned ${resp.status}: ${body}` };
    }
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}

async function awaitEvent(
  channel: string,
  type: string,
  timeoutMs: number,
): Promise<{ ok: boolean; event?: Record<string, unknown>; error?: string }> {
  const token = authToken();
  if (!token) return { ok: false, error: "COMS_NET_TOKEN not set" };

  try {
    const url = `${hubUrl()}/await?channel=${encodeURIComponent(channel)}&type=${encodeURIComponent(type)}&timeout=${timeoutMs}&poll=1`;
    const resp = await fetch(url, {
      headers: { authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(timeoutMs + 5_000),
    });
    if (resp.status === 408) {
      return { ok: false, error: "timeout" };
    }
    if (!resp.ok) {
      const body = await resp.text();
      return { ok: false, error: `hub returned ${resp.status}: ${body}` };
    }
    const ev = await resp.json();
    return { ok: true, event: ev };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}

async function getEvent(
  channel: string,
  type?: string,
): Promise<{ ok: boolean; event?: Record<string, unknown> | null; error?: string }> {
  const token = authToken();
  if (!token) return { ok: false, error: "COMS_NET_TOKEN not set" };

  try {
    let url = `${hubUrl()}/get?channel=${encodeURIComponent(channel)}`;
    if (type) url += `&type=${encodeURIComponent(type)}`;
    const resp = await fetch(url, {
      headers: { authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(10_000),
    });
    if (!resp.ok) {
      const body = await resp.text();
      return { ok: false, error: `hub returned ${resp.status}: ${body}` };
    }
    const ev = await resp.json();
    return { ok: true, event: ev };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}

async function listEvents(
  channel: string,
): Promise<{ ok: boolean; events?: Record<string, unknown>[]; error?: string }> {
  const token = authToken();
  if (!token) return { ok: false, error: "COMS_NET_TOKEN not set" };

  try {
    const url = `${hubUrl()}/list?channel=${encodeURIComponent(channel)}`;
    const resp = await fetch(url, {
      headers: { authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(10_000),
    });
    if (!resp.ok) {
      const body = await resp.text();
      return { ok: false, error: `hub returned ${resp.status}: ${body}` };
    }
    const list = await resp.json();
    return { ok: true, events: list };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}

export default function (pi: ExtensionAPI) {
  // ── Emit done event on agent_end ──────────────────────────────────────
  pi.on("agent_end", async (_event, ctx) => {
    const ch = channelKey(ctx.cwd);
    const branch = process.env.COMS_NET_BRANCH || "";
    const status = "success"; // agent_end means natural completion

    const payload = {
      type: "done",
      channel: ch,
      branch,
      status,
      ts: Date.now(),
    };

    const result = await postEvent(ch, "done", payload);
    if (!result.ok) {
      ctx.ui.notify(`coms-net: failed to emit done event: ${result.error}`);
    }
  });

  // ── Register tools ────────────────────────────────────────────────────

  pi.registerTool({
    name: "coms_net_send",
    label: "ComsNet Send",
    description: "Send an event to the coms-net event bus hub",
    promptSnippet: "Send an event to coms-net hub",
    parameters: Type.Object({
      type: Type.String({ description: "Event type (e.g., 'done', 'progress', 'log')" }),
      channel: Type.Optional(Type.String({ description: "Channel key; defaults to worker cwd" })),
      payload: Type.Optional(Type.Record(Type.String(), Type.Unknown(), { description: "Additional event data" })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const channel = params.channel || channelKey(ctx.cwd);
      const result = await postEvent(channel, params.type, params.payload || {});
      if (!result.ok) {
        return {
          isError: true,
          content: [{ type: "text", text: `coms_net_send failed: ${result.error}` }],
        };
      }
      return {
        content: [{ type: "text", text: `Event sent to channel "${channel}"` }],
      };
    },
  });

  pi.registerTool({
    name: "coms_net_await",
    label: "ComsNet Await",
    description: "Block until a matching event arrives on a channel or timeout",
    promptSnippet: "Await an event on coms-net hub",
    parameters: Type.Object({
      type: Type.Optional(Type.String({ description: "Event type to wait for (default: 'done')" })),
      channel: Type.Optional(Type.String({ description: "Channel key; defaults to worker cwd" })),
      timeout: Type.Optional(Type.Number({ description: "Timeout in milliseconds (default: 120000)" })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const channel = params.channel || channelKey(ctx.cwd);
      const type = params.type || "done";
      const timeout = params.timeout || 120_000;
      const result = await awaitEvent(channel, type, timeout);
      if (!result.ok) {
        return {
          isError: true,
          content: [{ type: "text", text: `coms_net_await failed: ${result.error}` }],
        };
      }
      return {
        content: [{ type: "text", text: JSON.stringify(result.event, null, 2) }],
      };
    },
  });

  pi.registerTool({
    name: "coms_net_get",
    label: "ComsNet Get",
    description: "Get the next matching event from a channel without blocking",
    promptSnippet: "Get the next event on coms-net hub",
    parameters: Type.Object({
      type: Type.Optional(Type.String({ description: "Event type filter" })),
      channel: Type.Optional(Type.String({ description: "Channel key; defaults to worker cwd" })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const channel = params.channel || channelKey(ctx.cwd);
      const result = await getEvent(channel, params.type);
      if (!result.ok) {
        return {
          isError: true,
          content: [{ type: "text", text: `coms_net_get failed: ${result.error}` }],
        };
      }
      return {
        content: [{ type: "text", text: result.event ? JSON.stringify(result.event, null, 2) : "null (no events)" }],
      };
    },
  });

  pi.registerTool({
    name: "coms_net_list",
    label: "ComsNet List",
    description: "List all active events on a channel",
    promptSnippet: "List events on coms-net hub channel",
    parameters: Type.Object({
      channel: Type.Optional(Type.String({ description: "Channel key; defaults to worker cwd" })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const channel = params.channel || channelKey(ctx.cwd);
      const result = await listEvents(channel);
      if (!result.ok) {
        return {
          isError: true,
          content: [{ type: "text", text: `coms_net_list failed: ${result.error}` }],
        };
      }
      return {
        content: [{ type: "text", text: JSON.stringify(result.events, null, 2) }],
      };
    },
  });
}
