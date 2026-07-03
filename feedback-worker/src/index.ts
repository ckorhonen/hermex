export interface Env {
  DB: D1Database;
  ADMIN_TOKEN: string;
}

type JsonRecord = Record<string, unknown>;

export interface FeedbackPayload {
  text: string;
  app: {
    id: string;
    name?: string;
    version?: string;
    build?: string;
    bundleId?: string;
    platform?: string;
  };
  device?: JsonRecord;
  screen?: {
    name?: string;
  };
  screenshot?: JsonRecord | null;
  annotation?: JsonRecord | null;
}

const maxFeedbackBodyBytes = 5 * 1024 * 1024;
const maxTextLength = 4_000;
const maxJsonTextLength = 3_000_000;
const feedbackRateLimit = 12;
const feedbackRateLimitWindowMs = 15 * 60 * 1000;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof HttpError) {
        return json({ ok: false, error: error.message }, { status: error.status });
      }
      console.error(error);
      return json({ ok: false, error: "Internal error" }, { status: 500 });
    }
  }
};

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }

  if (request.method === "GET" && url.pathname === "/health") {
    return json({ ok: true, service: "zora-feedback-inbox" });
  }

  if (url.pathname === "/api/feedback" && request.method === "POST") {
    await enforceFeedbackRateLimit(request, env);
    const payload = validateFeedbackPayload(await readBoundedJson(request, maxFeedbackBodyBytes));
    const row = await insertFeedback(env, payload);
    return json({ ok: true, feedback: row }, { status: 201 });
  }

  if (url.pathname === "/api/admin/feedback") {
    await requireAdmin(request, env);
    if (request.method === "GET") {
      return json({ ok: true, feedback: await listFeedback(env, url) });
    }
    if (request.method === "PATCH") {
      const payload = await readBoundedJson(request, 64 * 1024);
      return json({ ok: true, updated: await updateFeedback(env, payload) });
    }
  }

  throw new HttpError(404, "Not found");
}

export function validateFeedbackPayload(raw: unknown): FeedbackPayload {
  const data = asRecord(raw, "Feedback payload must be an object.");
  const text = requiredString(data.text, "text").trim();
  if (!text) {
    throw new HttpError(400, "Feedback text is required.");
  }
  if (text.length > maxTextLength) {
    throw new HttpError(413, "Feedback text is too long.");
  }

  const app = asRecord(data.app, "app is required.");
  const appId = requiredString(app.id, "app.id").trim();
  if (!appId || appId.length > 80) {
    throw new HttpError(400, "app.id is invalid.");
  }

  const screen = data.screen == null ? {} : asRecord(data.screen, "screen must be an object.");
  const device = data.device == null ? {} : asRecord(data.device, "device must be an object.");
  const screenshot = data.screenshot == null ? null : asRecord(data.screenshot, "screenshot must be an object.");
  const annotation = data.annotation == null ? null : asRecord(data.annotation, "annotation must be an object.");

  const screenshotText = screenshot ? JSON.stringify(screenshot) : "";
  if (screenshotText.length > maxJsonTextLength) {
    throw new HttpError(413, "Screenshot payload is too large.");
  }

  return {
    text,
    app: {
      id: appId,
      name: optionalString(app.name, 120),
      version: optionalString(app.version, 80),
      build: optionalString(app.build, 80),
      bundleId: optionalString(app.bundleId, 160),
      platform: optionalString(app.platform, 40)
    },
    device,
    screen: {
      name: optionalString(screen.name, 160)
    },
    screenshot,
    annotation
  };
}

async function insertFeedback(env: Env, payload: FeedbackPayload) {
  const id = crypto.randomUUID();
  const now = new Date().toISOString();

  await env.DB.prepare(
    `INSERT INTO feedback (
      id, app_id, app_name, app_version, app_build, bundle_id, platform,
      screen_name, text, device_json, screenshot_json, annotation_json,
      status, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'new', ?, ?)`
  )
    .bind(
      id,
      payload.app.id,
      payload.app.name ?? null,
      payload.app.version ?? null,
      payload.app.build ?? null,
      payload.app.bundleId ?? null,
      payload.app.platform ?? null,
      payload.screen?.name ?? null,
      payload.text,
      JSON.stringify(payload.device ?? {}),
      payload.screenshot ? JSON.stringify(payload.screenshot) : null,
      payload.annotation ? JSON.stringify(payload.annotation) : null,
      now,
      now
    )
    .run();

  return { id, status: "new", createdAt: now };
}

async function listFeedback(env: Env, url: URL) {
  const status = url.searchParams.get("status") ?? "new";
  const app = url.searchParams.get("app");
  const limit = clampInteger(Number(url.searchParams.get("limit") ?? "50"), 1, 100);

  let query =
    `SELECT id, app_id, app_name, app_version, app_build, bundle_id, platform,
            screen_name, text, device_json, screenshot_json, annotation_json,
            status, notes, created_at, updated_at
       FROM feedback
      WHERE status = ?`;
  const binds: Array<string | number | null> = [status];

  if (app) {
    query += " AND app_id = ?";
    binds.push(app);
  }

  query += " ORDER BY created_at ASC LIMIT ?";
  binds.push(limit);

  const result = await env.DB.prepare(query).bind(...binds).all();
  return (result.results ?? []).map(rowFromD1);
}

async function updateFeedback(env: Env, raw: unknown) {
  const payload = asRecord(raw, "Update payload must be an object.");
  const ids = normalizeIDs(payload);
  const status = requiredString(payload.status, "status").trim();
  if (!["new", "planned", "in_progress", "done", "ignored"].includes(status)) {
    throw new HttpError(400, "Unsupported status.");
  }
  const notes = optionalString(payload.notes, 4_000);
  const now = new Date().toISOString();

  for (const id of ids) {
    await env.DB.prepare("UPDATE feedback SET status = ?, notes = COALESCE(?, notes), updated_at = ? WHERE id = ?")
      .bind(status, notes ?? null, now, id)
      .run();
  }

  return { ids, status, updatedAt: now };
}

async function enforceFeedbackRateLimit(request: Request, env: Env): Promise<void> {
  const now = Date.now();
  const bucketStart = Math.floor(now / feedbackRateLimitWindowMs) * feedbackRateLimitWindowMs;
  const ip = request.headers.get("CF-Connecting-IP") ?? request.headers.get("x-forwarded-for") ?? "unknown";
  const bucketKey = `${await sha256(ip)}:${bucketStart}`;
  const updatedAt = new Date(now).toISOString();

  await env.DB.prepare(
    `INSERT INTO feedback_rate_limits (bucket_key, window_start, count, updated_at)
     VALUES (?, ?, 1, ?)
     ON CONFLICT(bucket_key) DO UPDATE SET
       count = feedback_rate_limits.count + 1,
       updated_at = excluded.updated_at`
  )
    .bind(bucketKey, bucketStart, updatedAt)
    .run();

  const result = await env.DB.prepare("SELECT count FROM feedback_rate_limits WHERE bucket_key = ?")
    .bind(bucketKey)
    .first<{ count: number }>();
  if ((result?.count ?? 0) > feedbackRateLimit) {
    throw new HttpError(429, "Too many feedback reports. Please try again later.");
  }

  await env.DB.prepare("DELETE FROM feedback_rate_limits WHERE window_start < ?")
    .bind(bucketStart - feedbackRateLimitWindowMs * 8)
    .run();
}

async function requireAdmin(request: Request, env: Env): Promise<void> {
  if (!env.ADMIN_TOKEN) {
    throw new HttpError(500, "Admin token is not configured.");
  }

  const auth = request.headers.get("authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice("Bearer ".length) : "";
  if (!token || token !== env.ADMIN_TOKEN) {
    throw new HttpError(401, "Unauthorized");
  }
}

async function readBoundedJson(request: Request, maxBytes: number): Promise<unknown> {
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) {
    throw new HttpError(413, "Request body is too large.");
  }

  try {
    return JSON.parse(text);
  } catch {
    throw new HttpError(400, "Request body must be valid JSON.");
  }
}

function rowFromD1(row: JsonRecord) {
  return {
    id: String(row.id),
    app: {
      id: String(row.app_id),
      name: nullableString(row.app_name),
      version: nullableString(row.app_version),
      build: nullableString(row.app_build),
      bundleId: nullableString(row.bundle_id),
      platform: nullableString(row.platform)
    },
    screen: { name: nullableString(row.screen_name) },
    text: String(row.text ?? ""),
    device: parseOptionalJson(row.device_json),
    screenshot: parseOptionalJson(row.screenshot_json),
    annotation: parseOptionalJson(row.annotation_json),
    status: String(row.status ?? "new"),
    notes: nullableString(row.notes),
    createdAt: String(row.created_at),
    updatedAt: String(row.updated_at)
  };
}

function parseOptionalJson(value: unknown): unknown {
  if (typeof value !== "string" || !value) return null;
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function normalizeIDs(payload: JsonRecord): string[] {
  if (typeof payload.id === "string") return [payload.id];
  if (Array.isArray(payload.ids) && payload.ids.every((id) => typeof id === "string")) {
    return payload.ids as string[];
  }
  throw new HttpError(400, "id or ids is required.");
}

function asRecord(value: unknown, message: string): JsonRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, message);
  }
  return value as JsonRecord;
}

function requiredString(value: unknown, key: string): string {
  if (typeof value !== "string") {
    throw new HttpError(400, `${key} must be a string.`);
  }
  return value;
}

function optionalString(value: unknown, maxLength: number): string | undefined {
  if (value == null) return undefined;
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.slice(0, maxLength) || undefined;
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function clampInteger(value: number, lower: number, upper: number): number {
  if (!Number.isFinite(value)) return lower;
  return Math.min(Math.max(Math.trunc(value), lower), upper);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function json(body: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  for (const [key, value] of Object.entries(corsHeaders())) {
    headers.set(key, value);
  }
  return new Response(JSON.stringify(body, null, 2), { ...init, headers });
}

function corsHeaders(): Record<string, string> {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,PATCH,OPTIONS",
    "access-control-allow-headers": "content-type,authorization"
  };
}

export class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}
