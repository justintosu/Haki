// Haki — "delete-account" edge function.
//
// POST {} with the caller's Supabase session (`Authorization: Bearer <jwt>`)
//   → {"deleted": true}
//
// Permanently deletes the caller's account and all of their data:
//   1. Revokes every Plaid item at Plaid (best effort; skipped when Plaid
//      isn't configured) and deletes the stored items, which cascades to
//      brokerage connections, accounts, holdings and transactions.
//   2. Deletes every storage object under "<user id>/" in the "avatars" and
//      "post-images" buckets.
//   3. Deletes the auth user; the profile, posts, likes, comments, follows
//      and snapshots cascade from it.
// If step 2 or 3 fails the request fails and the account still exists, so
// the user can simply try again.
//
// Errors: non-2xx with {"error": {"code": string, "message": string}}.
// Codes: unauthorized, bad_request, server_error.
//
// Self-contained on purpose (no relative imports) so it deploys as one file.

import { createClient } from "npm:@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Public buckets where users write to "<user id>/<file>". */
const STORAGE_BUCKETS = ["avatars", "post-images"] as const;
const STORAGE_LIST_PAGE_SIZE = 1000;
const STORAGE_REMOVE_CHUNK_SIZE = 100;
/** Safety cap on storage list calls per bucket. */
const STORAGE_MAX_LIST_CALLS = 5000;
const DB_PAGE_SIZE = 1000;
const PLAID_API_VERSION = "2020-09-14";
const PLAID_TIMEOUT_MS = 20_000;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

// ---------------------------------------------------------------------------
// Errors and responses
// ---------------------------------------------------------------------------

type ErrorCode = "unauthorized" | "bad_request" | "server_error";

class HttpError extends Error {
  readonly status: number;
  readonly code: ErrorCode;

  constructor(status: number, code: ErrorCode, message: string) {
    super(message);
    this.name = "HttpError";
    this.status = status;
    this.code = code;
  }
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function toErrorResponse(error: unknown): Response {
  const httpError = error instanceof HttpError ? error : new HttpError(
    500,
    "server_error",
    "Something went wrong on the server. Try again.",
  );
  if (!(error instanceof HttpError)) {
    console.error("[delete-account] unexpected error:", describeUnknown(error));
  } else if (error.status >= 500) {
    console.error(`[delete-account] ${error.code}: ${error.message}`);
  }
  return jsonResponse(httpError.status, {
    error: { code: httpError.code, message: httpError.message },
  });
}

function describeUnknown(error: unknown): string {
  if (error instanceof Error) return `${error.name}: ${error.message}`;
  try {
    return JSON.stringify(error);
  } catch {
    return String(error);
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** A trimmed, non-empty string, else null. */
function str(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function chunk<T>(items: readonly T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

function env(name: string): string | null {
  return str(Deno.env.get(name));
}

interface SupabaseEnv {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
}

function readSupabaseEnv(): SupabaseEnv {
  const url = env("SUPABASE_URL");
  const anonKey = env("SUPABASE_ANON_KEY");
  const serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceRoleKey) {
    console.error(
      "[delete-account] SUPABASE_URL, SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY is missing",
    );
    throw new HttpError(
      500,
      "server_error",
      "The server is missing its Supabase configuration.",
    );
  }
  return { url, anonKey, serviceRoleKey };
}

interface PlaidConfig {
  clientId: string;
  secret: string;
  baseUrl: string;
}

/** Plaid credentials, or null when Plaid isn't (correctly) configured. */
function readPlaidConfig(): PlaidConfig | null {
  const clientId = env("PLAID_CLIENT_ID");
  const secret = env("PLAID_SECRET");
  const environment = (env("PLAID_ENV") ?? "sandbox").toLowerCase();
  if (!clientId || !secret) return null;
  if (environment !== "sandbox" && environment !== "production") return null;
  return {
    clientId,
    secret,
    baseUrl: environment === "production"
      ? "https://production.plaid.com"
      : "https://sandbox.plaid.com",
  };
}

// ---------------------------------------------------------------------------
// Supabase clients and authentication
// ---------------------------------------------------------------------------

function createAdminClient(config: SupabaseEnv) {
  return createClient(config.url, config.serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

type AdminClient = ReturnType<typeof createAdminClient>;

/** Returns the caller's user id (lowercase UUID) or throws 401. */
async function authenticate(
  req: Request,
  config: SupabaseEnv,
): Promise<string> {
  const header = req.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(\S+)\s*$/i.exec(header);
  if (!match) {
    throw new HttpError(401, "unauthorized", "Sign in to continue.");
  }
  const jwt = match[1];
  const userClient = createClient(config.url, config.anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  const { data, error } = await userClient.auth.getUser(jwt);
  if (error) {
    const status = error.status ?? 0;
    if (status === 0 || status >= 500) {
      console.error(
        `[delete-account] auth.getUser failed (${status}): ${error.message}`,
      );
      throw new HttpError(
        503,
        "server_error",
        "Couldn't verify your session right now. Try again.",
      );
    }
    throw new HttpError(
      401,
      "unauthorized",
      "Your session has expired. Sign in again.",
    );
  }
  const id = str(data.user?.id);
  if (!id || !UUID_PATTERN.test(id)) {
    throw new HttpError(
      401,
      "unauthorized",
      "Your session has expired. Sign in again.",
    );
  }
  return id.toLowerCase();
}

// ---------------------------------------------------------------------------
// Step 1: Plaid items
// ---------------------------------------------------------------------------

/** Best-effort Plaid /item/remove. Never logs the request body (secrets). */
async function removePlaidItem(
  plaid: PlaidConfig,
  accessToken: string,
): Promise<boolean> {
  try {
    const response = await fetch(`${plaid.baseUrl}/item/remove`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Plaid-Version": PLAID_API_VERSION,
      },
      body: JSON.stringify({
        access_token: accessToken,
        client_id: plaid.clientId,
        secret: plaid.secret,
      }),
      signal: AbortSignal.timeout(PLAID_TIMEOUT_MS),
    });
    const text = await response.text();
    if (response.ok) return true;
    let code = `HTTP_${response.status}`;
    let requestId = "n/a";
    try {
      const parsed: unknown = JSON.parse(text);
      if (isRecord(parsed)) {
        code = str(parsed.error_code) ?? code;
        requestId = str(parsed.request_id) ?? requestId;
      }
    } catch {
      // Not JSON; keep the HTTP status as the code.
    }
    console.warn(
      `[delete-account] Plaid item/remove failed (ignored): ${code} (request_id ${requestId})`,
    );
    return false;
  } catch (error) {
    console.warn(
      "[delete-account] couldn't reach Plaid for item/remove (ignored):",
      describeUnknown(error),
    );
    return false;
  }
}

/** Revokes the user's Plaid items (best effort), then deletes them (cascades). */
async function deletePlaidItems(
  admin: AdminClient,
  userId: string,
): Promise<void> {
  const items: Array<{ id: string; accessToken: string | null }> = [];
  for (let from = 0;;) {
    const { data, error } = await admin
      .from("plaid_items")
      .select("id, access_token")
      .eq("user_id", userId)
      .order("id")
      .range(from, from + DB_PAGE_SIZE - 1);
    if (error) {
      console.error(
        `[delete-account] reading Plaid items failed: ${error.message}`,
      );
      throw new HttpError(
        500,
        "server_error",
        "Couldn't delete your brokerage connections. Try again.",
      );
    }
    const rows = Array.isArray(data) ? data.filter(isRecord) : [];
    if (rows.length === 0) break;
    for (const row of rows) {
      const id = str(row.id);
      if (id) items.push({ id, accessToken: str(row.access_token) });
    }
    from += rows.length;
  }
  if (items.length === 0) return;

  const plaid = readPlaidConfig();
  if (plaid) {
    let removed = 0;
    for (const item of items) {
      if (item.accessToken && await removePlaidItem(plaid, item.accessToken)) {
        removed += 1;
      }
    }
    console.log(
      `[delete-account] revoked ${removed}/${items.length} Plaid item(s)`,
    );
  } else {
    console.warn(
      `[delete-account] Plaid isn't configured; ${items.length} item(s) deleted locally without revoking`,
    );
  }

  // Cascades to brokerage_connections → investment_accounts → holdings / transactions.
  const { error } = await admin.from("plaid_items").delete().eq(
    "user_id",
    userId,
  );
  if (error) {
    console.error(
      `[delete-account] deleting Plaid items failed: ${error.message}`,
    );
    throw new HttpError(
      500,
      "server_error",
      "Couldn't delete your brokerage connections. Try again.",
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: storage
// ---------------------------------------------------------------------------

interface StorageFailure {
  message: string;
  statusCode?: string;
  code?: string;
}

function isMissingBucket(error: StorageFailure): boolean {
  return error.code === "NoSuchBucket" || error.statusCode === "404" ||
    /bucket not found/i.test(error.message);
}

/**
 * Every object path under `<root>/` in `bucket`, recursing into sub-folders.
 * Lists everything before anything is removed, so offsets stay stable.
 * Returns null when the bucket doesn't exist.
 */
async function listObjectPaths(
  admin: AdminClient,
  bucket: string,
  root: string,
): Promise<string[] | null> {
  const files: string[] = [];
  const folders: string[] = [root];
  let listCalls = 0;

  while (folders.length > 0) {
    const folder = folders.pop() as string;
    let offset = 0;
    for (;;) {
      if (++listCalls > STORAGE_MAX_LIST_CALLS) {
        console.error(`[delete-account] too many objects in ${bucket}/${root}`);
        throw new HttpError(
          500,
          "server_error",
          "Couldn't delete your photos. Try again.",
        );
      }
      const { data, error } = await admin.storage.from(bucket).list(folder, {
        limit: STORAGE_LIST_PAGE_SIZE,
        offset,
        sortBy: { column: "name", order: "asc" },
      });
      if (error) {
        if (isMissingBucket(error)) return null;
        console.error(
          `[delete-account] listing ${bucket}/${folder} failed: ${error.message}`,
        );
        throw new HttpError(
          500,
          "server_error",
          "Couldn't delete your photos. Try again.",
        );
      }
      const entries = data ?? [];
      if (entries.length === 0) break;
      for (const entry of entries) {
        const name = str(entry.name);
        if (!name) continue;
        const path = `${folder}/${name}`;
        // Folders come back with a null id; files always have one.
        if (entry.id === null || entry.id === undefined) {
          folders.push(path);
        } else {
          files.push(path);
        }
      }
      offset += entries.length;
    }
  }
  return files;
}

/** Deletes every object under `<userId>/` in the image buckets. */
async function deleteStorageObjects(
  admin: AdminClient,
  userId: string,
): Promise<void> {
  for (const bucket of STORAGE_BUCKETS) {
    const paths = await listObjectPaths(admin, bucket, userId);
    if (paths === null) {
      console.warn(
        `[delete-account] bucket "${bucket}" doesn't exist; skipping`,
      );
      continue;
    }
    for (const part of chunk(paths, STORAGE_REMOVE_CHUNK_SIZE)) {
      const { error } = await admin.storage.from(bucket).remove(part);
      if (error) {
        console.error(
          `[delete-account] removing objects from ${bucket} failed: ${error.message}`,
        );
        throw new HttpError(
          500,
          "server_error",
          "Couldn't delete your photos. Try again.",
        );
      }
    }
    if (paths.length > 0) {
      console.log(
        `[delete-account] removed ${paths.length} object(s) from ${bucket}`,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 3: auth user
// ---------------------------------------------------------------------------

async function deleteAuthUser(
  admin: AdminClient,
  userId: string,
): Promise<void> {
  const { error } = await admin.auth.admin.deleteUser(userId);
  if (!error) return;
  if (error.status === 404) {
    console.warn("[delete-account] auth user was already deleted");
    return;
  }
  console.error(
    `[delete-account] auth.admin.deleteUser failed (${
      error.status ?? "?"
    }): ${error.message}`,
  );
  throw new HttpError(
    500,
    "server_error",
    "Couldn't delete your account. Try again.",
  );
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  try {
    if (req.method !== "POST") {
      throw new HttpError(405, "bad_request", "Use POST.");
    }
    const supabaseEnv = readSupabaseEnv();
    const userId = await authenticate(req, supabaseEnv);
    const admin = createAdminClient(supabaseEnv);

    await deletePlaidItems(admin, userId);
    await deleteStorageObjects(admin, userId);
    await deleteAuthUser(admin, userId);

    console.log(`[delete-account] deleted user ${userId}`);
    return jsonResponse(200, { deleted: true });
  } catch (error) {
    return toErrorResponse(error);
  }
});
