/**
 * coms-net-server.ts — Bun HTTP/SSE event hub for Pi worker completion
 *
 * Ported from disler/pi-vs-claude-code (MIT).
 * https://github.com/disler/pi-vs-claude-code
 *
 * Endpoints:
 *   POST /send     — Enqueue an event (channel-isolated, TTL-gated)
 *   GET  /await    — SSE/poll: block until a matching event arrives or timeout
 *   GET  /get      — Retrieve the first matching event without blocking
 *   GET  /list     — List all active events for a channel
 *   GET  /health   — Liveness probe
 *
 * Auth: Every request must carry header `Authorization: Bearer <COMS_NET_TOKEN>`.
 * Channel isolation: events are namespaced by channel key.
 * TTL: Events expire after `COMS_NET_TTL_SEC` (default 300).
 * max-hops: max number of await clients per channel (default 100).
 */

interface EventRecord {
  id: string;
  type: string;
  channel: string;
  payload: Record<string, unknown>;
  createdAt: number;
}

// ── args / env ──────────────────────────────────────────────────────────
const port = parseInt(process.env.COMS_NET_PORT || "0", 10) || 0;
const host = process.env.COMS_NET_HOST || "127.0.0.1";
const token = process.env.COMS_NET_TOKEN || "";
const ttlSec = parseInt(process.env.COMS_NET_TTL_SEC || "300", 10);
const maxHops = parseInt(process.env.COMS_NET_MAX_HOPS || "100", 10);
const heartbeatSec = parseInt(process.env.COMS_NET_HEARTBEAT_SEC || "15", 10);

if (!token) {
  console.error("FATAL: COMS_NET_TOKEN not set");
  process.exit(1);
}

// ── in-memory store ─────────────────────────────────────────────────────
const events = new Map<string, EventRecord>();
let eventIdCounter = 0;

// Per-channel awaiters: channel → array of {resolve, signal}
type Awaiter = {
  resolve: (ev: EventRecord | null) => void;
  signal: AbortSignal;
};
const awaiters = new Map<string, Awaiter[]>();

// ── helpers ─────────────────────────────────────────────────────────────
function newId(): string {
  eventIdCounter += 1;
  return `ev_${Date.now()}_${eventIdCounter}`;
}

function checkAuth(req: Request): Response | null {
  const auth = req.headers.get("authorization") || "";
  if (auth !== `Bearer ${token}`) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }
  return null;
}

function parseChannel(url: URL): { channel: string; error?: string } {
  const ch = url.searchParams.get("channel");
  if (!ch) return { channel: "", error: "missing channel parameter" };
  return { channel: ch };
}

// ── TTL expiry sweep (every 30 s) ──────────────────────────────────────
function sweepExpired() {
  const now = Date.now();
  for (const [id, ev] of events) {
    if (now - ev.createdAt > ttlSec * 1_000) {
      events.delete(id);
    }
  }
}
setInterval(sweepExpired, 30_000);

// ── notify awaiters for a channel ───────────────────────────────────────
function notifyAwaiters(channel: string, ev: EventRecord) {
  const list = awaiters.get(channel);
  if (!list) return;
  const survivors: Awaiter[] = [];
  for (const a of list) {
    if (a.signal.aborted) continue;
    a.resolve(ev);
    // Each awaiter gets at most one event, then we break
    // But we need to signal only ONE per event. The first un-aborted gets it.
    // We collect the rest.
  }
  // Simple approach: resolve the first un-aborted, collect rest
  let resolved = false;
  for (const a of list) {
    if (resolved) {
      if (!a.signal.aborted) survivors.push(a);
      continue;
    }
    if (a.signal.aborted) continue;
    a.resolve(ev);
    resolved = true;
  }
  awaiters.set(channel, survivors);
}

// ── routes ──────────────────────────────────────────────────────────────

async function handleSend(req: Request, url: URL): Promise<Response> {
  const authErr = checkAuth(req);
  if (authErr) return authErr;

  const { channel, error } = parseChannel(url);
  if (error) return new Response(JSON.stringify({ error }), { status: 400, headers: { "content-type": "application/json" } });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid JSON body" }), { status: 400, headers: { "content-type": "application/json" } });
  }

  const ev: EventRecord = {
    id: newId(),
    type: (body.type as string) || "event",
    channel,
    payload: body,
    createdAt: Date.now(),
  };
  events.set(ev.id, ev);

  // notify awaiters
  notifyAwaiters(channel, ev);

  return new Response(JSON.stringify({ status: "ok", eventId: ev.id }), {
    status: 201,
    headers: { "content-type": "application/json" },
  });
}

async function handleGet(req: Request, url: URL): Promise<Response> {
  const authErr = checkAuth(req);
  if (authErr) return authErr;

  const { channel, error } = parseChannel(url);
  if (error) return new Response(JSON.stringify({ error }), { status: 400, headers: { "content-type": "application/json" } });

  const typeFilter = url.searchParams.get("type") || undefined;

  // Find first matching event
  for (const [, ev] of events) {
    if (ev.channel !== channel) continue;
    if (typeFilter && ev.type !== typeFilter) continue;
    events.delete(ev.id); // consume once
    return new Response(JSON.stringify(ev), { headers: { "content-type": "application/json" } });
  }

  return new Response(JSON.stringify(null), { headers: { "content-type": "application/json" } });
}

async function handleAwait(req: Request, url: URL): Promise<Response> {
  const authErr = checkAuth(req);
  if (authErr) return authErr;

  const { channel, error } = parseChannel(url);
  if (error) return new Response(JSON.stringify({ error }), { status: 400, headers: { "content-type": "application/json" } });

  const typeFilter = url.searchParams.get("type") || "done";
  const timeoutMs = parseInt(url.searchParams.get("timeout") || "120000", 10);
  const pollMode = url.searchParams.get("poll") === "1";

  // Check if a matching event already exists
  for (const [, ev] of events) {
    if (ev.channel !== channel) continue;
    if (typeFilter && ev.type !== typeFilter) continue;
    events.delete(ev.id);
    if (pollMode) {
      return new Response(JSON.stringify(ev), { headers: { "content-type": "application/json" } });
    }
    return new Response(JSON.stringify(ev), { headers: { "content-type": "application/json" } });
  }

  // SSE mode
  if (!pollMode) {
    const stream = new ReadableStream({
      async start(controller) {
        const encoder = new TextEncoder();

        // Send initial heartbeat
        controller.enqueue(encoder.encode(`event: heartbeat\ndata: {"ts":${Date.now()}}\n\n`));

        const heartbeatInterval = setInterval(() => {
          controller.enqueue(encoder.encode(`event: heartbeat\ndata: {"ts":${Date.now()}}\n\n`));
        }, heartbeatSec * 1_000);

        const abortController = new AbortController();
        const timeoutId = setTimeout(() => {
          controller.enqueue(encoder.encode(`event: timeout\ndata: {"error":"timeout","channel":"${channel}"}\n\n`));
          abortController.abort();
        }, timeoutMs);

        let resolved = false;
        const awaiter: Awaiter = {
          resolve: (ev: EventRecord | null) => {
            if (resolved) return;
            resolved = true;
            clearTimeout(timeoutId);
            clearInterval(heartbeatInterval);
            if (ev) {
              const data = JSON.stringify(ev);
              controller.enqueue(encoder.encode(`event: message\ndata: ${data}\n\n`));
            } else {
              controller.enqueue(encoder.encode(`event: timeout\ndata: {"error":"timeout","channel":"${channel}"}\n\n`));
            }
            controller.close();
          },
          signal: abortController.signal,
        };

        // Register awaiter (respect maxHops)
        const existing = awaiters.get(channel) || [];
        if (existing.length >= maxHops) {
          clearTimeout(timeoutId);
          clearInterval(heartbeatInterval);
          controller.enqueue(encoder.encode(`event: error\ndata: {"error":"max_hops","channel":"${channel}"}\n\n`));
          controller.close();
          return;
        }
        existing.push(awaiter);
        awaiters.set(channel, existing);

        // If the connection is closed early, clean up
        const cleanup = () => {
          clearTimeout(timeoutId);
          clearInterval(heartbeatInterval);
          if (!resolved) {
            resolved = true;
            const list = awaiters.get(channel) || [];
            awaiters.set(channel, list.filter(a => a !== awaiter));
          }
        };

        // Listen for abort from client disconnect via request signal
        req.signal.addEventListener("abort", cleanup);
      },
    });

    return new Response(stream, {
      headers: {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        connection: "keep-alive",
      },
    });
  }

  // Poll mode: block with retries
  const deadline = Date.now() + timeoutMs;
  const pollInterval = 1000;

  while (Date.now() < deadline) {
    // Check for events
    for (const [, ev] of events) {
      if (ev.channel !== channel) continue;
      if (typeFilter && ev.type !== typeFilter) continue;
      events.delete(ev.id);
      return new Response(JSON.stringify(ev), { headers: { "content-type": "application/json" } });
    }

    // Wait before next poll
    await new Promise(r => setTimeout(r, pollInterval));
  }

  return new Response(JSON.stringify({ error: "timeout", channel }), {
    status: 408,
    headers: { "content-type": "application/json" },
  });
}

async function handleList(req: Request, url: URL): Promise<Response> {
  const authErr = checkAuth(req);
  if (authErr) return authErr;

  const { channel, error } = parseChannel(url);
  if (error) return new Response(JSON.stringify({ error }), { status: 400, headers: { "content-type": "application/json" } });

  const result: EventRecord[] = [];
  for (const [, ev] of events) {
    if (ev.channel !== channel) continue;
    result.push(ev);
  }

  return new Response(JSON.stringify(result), { headers: { "content-type": "application/json" } });
}

async function handleHealth(_req: Request): Promise<Response> {
  return new Response(JSON.stringify({ status: "ok", ts: Date.now() }), {
    headers: { "content-type": "application/json" },
  });
}

// ── Router ──────────────────────────────────────────────────────────────
const server = Bun.serve({
  port,
  hostname: host,
  async fetch(req) {
    const url = new URL(req.url);
    const method = req.method.toUpperCase();
    const path = url.pathname;

    try {
      if (path === "/send" && method === "POST") {
        return await handleSend(req, url);
      }
      if (path === "/get" && method === "GET") {
        return await handleGet(req, url);
      }
      if (path === "/await" && method === "GET") {
        return await handleAwait(req, url);
      }
      if (path === "/list" && method === "GET") {
        return await handleList(req, url);
      }
      if (path === "/health" && method === "GET") {
        return await handleHealth(req);
      }

      return new Response(JSON.stringify({ error: "not found" }), {
        status: 404,
        headers: { "content-type": "application/json" },
      });
    } catch (err) {
      console.error("request error:", err);
      return new Response(JSON.stringify({ error: "internal error" }), {
        status: 500,
        headers: { "content-type": "application/json" },
      });
    }
  },
});

console.log(`coms-net-server listening on http://${host}:${server.port}`);
console.log(`  channel-isolation: per-channel namespacing`);
console.log(`  auth-token: ${token ? "configured" : "MISSING"}`);
console.log(`  TTL: ${ttlSec}s`);
console.log(`  max-hops: ${maxHops}`);
console.log(`  heartbeat: ${heartbeatSec}s`);
