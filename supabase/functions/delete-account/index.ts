// Haki — "delete-account" edge function.
//
// POST {} or {"apple_authorization_code": string} with the caller's Supabase
// session (`Authorization: Bearer <jwt>`)
//   → {"deleted": true}
//
// `apple_authorization_code` is optional: a fresh Sign in with Apple
// authorization code (UTF-8 of `ASAuthorizationAppleIDCredential
// .authorizationCode`) the app requests just before deleting an account that
// has an Apple identity. Codes are single-use and expire after five minutes,
// so one saved at sign-in won't work. Anything else in the body is ignored.
//
// Permanently deletes the caller's account and all of their data:
//   0. If an Apple code was sent and the account has an Apple identity,
//      exchanges the code at Apple for a token (up front, while the code is
//      still fresh).
//   1. Revokes every Plaid item at Plaid (best effort; skipped when Plaid
//      isn't configured) and deletes the stored items, which cascades to
//      brokerage connections, accounts, holdings and transactions.
//   2. Deletes every storage object under "<user id>/" in the "avatars" and
//      "post-images" buckets.
//   3. Revokes the Apple token from step 0 through Apple's REST API, so the
//      app no longer appears under the user's Sign in with Apple apps
//      (App Store guideline 5.1.1(v)). Best effort: Apple errors, a missing
//      code or missing APPLE_* secrets are logged and never block deletion.
//   4. Deletes the auth user; the profile, posts, likes, comments, follows
//      and snapshots cascade from it.
// If step 2 or 4 fails the request fails and the account still exists, so
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
/** Bodies larger than this are ignored (the only field is a short code). */
const MAX_BODY_BYTES = 16 * 1024;
const MAX_APPLE_CODE_LENGTH = 1024;
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
/** The `aud` claim Apple requires in a client secret. */
const APPLE_AUDIENCE = "https://appleid.apple.com";
/** Client secrets are made per call, so they only need to live briefly. */
const APPLE_CLIENT_SECRET_LIFETIME_S = 5 * 60;
const APPLE_TIMEOUT_MS = 10_000;
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

interface AppleConfig {
  teamId: string;
  keyId: string;
  /** The Sign in with Apple key (.p8, PKCS#8 PEM). */
  privateKey: string;
  /** The app's bundle ID: native sign-in codes are issued to it. */
  clientId: string;
}

/** Sign in with Apple REST credentials, or null when any is missing. */
function readAppleConfig(): AppleConfig | null {
  const teamId = env("APPLE_TEAM_ID");
  const keyId = env("APPLE_KEY_ID");
  const privateKey = env("APPLE_PRIVATE_KEY");
  const clientId = env("APPLE_CLIENT_ID");
  if (!teamId || !keyId || !privateKey || !clientId) return null;
  return { teamId, keyId, privateKey, clientId };
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

interface Caller {
  /** Lowercase UUID. */
  id: string;
  /** Whether the account has a Sign in with Apple identity. */
  hasAppleIdentity: boolean;
  /** Apple user ids (`sub`) of those identities, when GoTrue reports them. */
  appleSubjects: Set<string>;
}

/** Returns the signed-in caller or throws 401. */
async function authenticate(
  req: Request,
  config: SupabaseEnv,
): Promise<Caller> {
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

  const appleSubjects = new Set<string>();
  let hasAppleIdentity = false;
  for (const identity of data.user?.identities ?? []) {
    if (identity.provider !== "apple") continue;
    hasAppleIdentity = true;
    // GoTrue reports the provider's user id as `id` and in identity_data.
    const subject = str(identity.identity_data?.sub) ?? str(identity.id);
    if (subject) appleSubjects.add(subject);
  }
  const providers: unknown = data.user?.app_metadata?.providers;
  if (Array.isArray(providers) && providers.includes("apple")) {
    hasAppleIdentity = true;
  }
  return { id: id.toLowerCase(), hasAppleIdentity, appleSubjects };
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
// Steps 0 and 3: Sign in with Apple
// ---------------------------------------------------------------------------

/**
 * The optional `apple_authorization_code` from the body. The body used to be
 * ignored, so anything unexpected is ignored too rather than rejected:
 * revoking Apple's token must never stand in the way of deleting an account.
 */
async function readAppleAuthorizationCode(
  req: Request,
): Promise<string | null> {
  let text: string;
  try {
    text = await req.text();
  } catch {
    return null;
  }
  if (text.trim().length === 0) return null;
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    console.warn("[delete-account] the request body is too large; ignoring it");
    return null;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    console.warn("[delete-account] the request body isn't JSON; ignoring it");
    return null;
  }
  if (!isRecord(parsed)) return null;
  const code = str(parsed.apple_authorization_code);
  if (!code) return null;
  if (code.length > MAX_APPLE_CODE_LENGTH) {
    console.warn(
      "[delete-account] apple_authorization_code is too long; ignoring it",
    );
    return null;
  }
  return code;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

/** Decodes standard or URL-safe base64 (padding optional), else null. */
function decodeBase64(text: string): Uint8Array | null {
  const unpadded = text.replace(/-/g, "+").replace(/_/g, "/").replace(
    /={0,2}$/,
    "",
  );
  if (!/^[A-Za-z0-9+/]*$/.test(unpadded)) return null;
  const padded = unpadded + "=".repeat((4 - (unpadded.length % 4)) % 4);
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

/**
 * The DER bytes of a PKCS#8 PEM key (Apple's .p8 file). Accepts the PEM with
 * real or escaped ("\n") line breaks, or just its base64 body.
 */
function pkcs8FromPem(pem: string): Uint8Array | null {
  const body = pem
    .replace(/-----(BEGIN|END) [A-Z ]+-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  if (body.length === 0) return null;
  return decodeBase64(body);
}

/**
 * The ES256-signed JWT Apple accepts as `client_secret`. WebCrypto's ECDSA
 * signature is already the raw r||s form that JWS needs.
 */
async function appleClientSecret(config: AppleConfig): Promise<string> {
  const der = pkcs8FromPem(config.privateKey);
  if (!der) throw new Error("APPLE_PRIVATE_KEY isn't a PKCS#8 PEM key");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({ alg: "ES256", kid: config.keyId });
  const claims = base64UrlJson({
    iss: config.teamId,
    iat: now,
    exp: now + APPLE_CLIENT_SECRET_LIFETIME_S,
    aud: APPLE_AUDIENCE,
    sub: config.clientId,
  });
  const signingInput = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

/** POSTs a form to Apple. Throws only when Apple can't be reached. */
async function postAppleForm(
  url: string,
  form: Record<string, string>,
): Promise<{ ok: boolean; status: number; body: unknown }> {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: new URLSearchParams(form).toString(),
    signal: AbortSignal.timeout(APPLE_TIMEOUT_MS),
  });
  const text = await response.text();
  let body: unknown = null;
  if (text.length > 0) {
    try {
      body = JSON.parse(text);
    } catch {
      body = null;
    }
  }
  return { ok: response.ok, status: response.status, body };
}

/** Apple's OAuth `error` code (e.g. invalid_grant); never echoes anything else. */
function appleErrorCode(body: unknown): string {
  const code = isRecord(body) ? str(body.error) : null;
  return code && /^[a-z_]{1,64}$/i.test(code) ? code : "unknown";
}

/** The `sub` claim of a JWT, without verifying it, else null. */
function jwtSubject(token: string | null): string | null {
  const payload = token?.split(".")[1];
  if (!payload) return null;
  const bytes = decodeBase64(payload);
  if (!bytes) return null;
  try {
    const claims: unknown = JSON.parse(new TextDecoder().decode(bytes));
    return isRecord(claims) ? str(claims.sub) : null;
  } catch {
    return null;
  }
}

/** An Apple token to revoke once the rest of the account is gone. */
interface AppleGrant {
  config: AppleConfig;
  token: string;
  tokenTypeHint: "refresh_token" | "access_token";
}

/**
 * Step 0: exchanges the app's fresh authorization code for an Apple token.
 * Best effort: returns null (and logs why, never the code, tokens or key)
 * whenever revocation isn't possible.
 */
async function exchangeAppleCode(
  caller: Caller,
  code: string | null,
): Promise<AppleGrant | null> {
  if (!caller.hasAppleIdentity) {
    if (code) {
      console.warn(
        "[delete-account] an Apple code was sent, but the account has no Apple identity; ignoring it",
      );
    }
    return null;
  }
  if (!code) {
    console.warn(
      "[delete-account] no Apple authorization code was sent; Sign in with Apple won't be revoked",
    );
    return null;
  }
  const config = readAppleConfig();
  if (!config) {
    console.warn(
      "[delete-account] APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY or APPLE_CLIENT_ID is missing; Sign in with Apple won't be revoked",
    );
    return null;
  }
  try {
    const result = await postAppleForm(APPLE_TOKEN_URL, {
      client_id: config.clientId,
      client_secret: await appleClientSecret(config),
      code,
      grant_type: "authorization_code",
    });
    if (!result.ok) {
      console.warn(
        `[delete-account] Apple token exchange failed (ignored): HTTP ${result.status} ${
          appleErrorCode(result.body)
        }`,
      );
      return null;
    }
    const body = isRecord(result.body) ? result.body : {};
    // Only revoke the Apple ID that is linked to this account.
    const subject = jwtSubject(str(body.id_token));
    if (
      subject && caller.appleSubjects.size > 0 &&
      !caller.appleSubjects.has(subject)
    ) {
      console.warn(
        "[delete-account] the Apple ID that sent the code isn't the one linked to this account; not revoking",
      );
      return null;
    }
    const refreshToken = str(body.refresh_token);
    if (refreshToken) {
      return { config, token: refreshToken, tokenTypeHint: "refresh_token" };
    }
    const accessToken = str(body.access_token);
    if (accessToken) {
      return { config, token: accessToken, tokenTypeHint: "access_token" };
    }
    console.warn(
      "[delete-account] Apple returned no token to revoke (ignored)",
    );
    return null;
  } catch (error) {
    console.warn(
      "[delete-account] couldn't exchange the Apple code (ignored):",
      describeUnknown(error),
    );
    return null;
  }
}

/** Step 3: revokes the token from step 0. Best effort; never throws. */
async function revokeAppleGrant(grant: AppleGrant): Promise<void> {
  try {
    // A new client secret: the one from step 0 may be close to expiring.
    const result = await postAppleForm(APPLE_REVOKE_URL, {
      client_id: grant.config.clientId,
      client_secret: await appleClientSecret(grant.config),
      token: grant.token,
      token_type_hint: grant.tokenTypeHint,
    });
    if (result.ok) {
      console.log("[delete-account] revoked Sign in with Apple");
    } else {
      console.warn(
        `[delete-account] Apple revoke failed (ignored): HTTP ${result.status} ${
          appleErrorCode(result.body)
        }`,
      );
    }
  } catch (error) {
    console.warn(
      "[delete-account] couldn't revoke Sign in with Apple (ignored):",
      describeUnknown(error),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4: auth user
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
    const caller = await authenticate(req, supabaseEnv);
    const userId = caller.id;
    const appleCode = await readAppleAuthorizationCode(req);
    const admin = createAdminClient(supabaseEnv);

    // Exchanged first: Apple's codes expire five minutes after they're issued.
    const appleGrant = await exchangeAppleCode(caller, appleCode);
    await deletePlaidItems(admin, userId);
    await deleteStorageObjects(admin, userId);
    if (appleGrant) await revokeAppleGrant(appleGrant);
    await deleteAuthUser(admin, userId);

    console.log(`[delete-account] deleted user ${userId}`);
    return jsonResponse(200, { deleted: true });
  } catch (error) {
    return toErrorResponse(error);
  }
});
