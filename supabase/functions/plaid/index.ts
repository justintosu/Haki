// Haki — "plaid" edge function.
//
// Connects brokerages through Plaid and copies investment data into the
// database. Every request must carry the caller's Supabase session
// (`Authorization: Bearer <jwt>`); all data is scoped to that user.
//
// POST JSON {"action": ...}
//   {"action":"link_token"}
//       → {"link_token": string, "expiration": string}
//   {"action":"exchange","public_token": string,"institution_id"?: string,"institution_name"?: string}
//       → {"connection_id": string, "accounts": number, "holdings": number, "transactions": number}
//   {"action":"sync","connection_id"?: string}
//       → {"connections": number, "accounts": number, "holdings": number, "transactions": number}
//   {"action":"remove","connection_id": string}
//       → {"removed": true}
//
// Errors: non-2xx with {"error": {"code": string, "message": string}}.
// Codes: unauthorized, bad_request, not_found, plaid_error,
// plaid_not_configured, server_error.
//
// Self-contained on purpose (no relative imports) so it deploys as one file.

import { createClient } from "npm:@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const PLAID_API_VERSION = "2020-09-14";
const PLAID_TIMEOUT_MS = 30_000;
/** Plaid's maximum page size for /investments/transactions/get. */
const PLAID_TRANSACTIONS_PAGE_SIZE = 500;
/** Safety cap: 40 pages × 500 = 20,000 transactions in the 90-day window. */
const PLAID_TRANSACTIONS_MAX_PAGES = 40;
const TRANSACTION_HISTORY_DAYS = 90;
/** Rows per upsert request. */
const UPSERT_CHUNK_SIZE = 500;
/** Values per `.in()` filter (keeps request URLs short). */
const FILTER_CHUNK_SIZE = 100;
/** Rows requested per page when reading every row of a query. */
const DB_PAGE_SIZE = 1000;
const MAX_BODY_BYTES = 64 * 1024;
const MAX_ERROR_MESSAGE_LENGTH = 500;
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

type ErrorCode =
  | "unauthorized"
  | "bad_request"
  | "not_found"
  | "plaid_error"
  | "plaid_not_configured"
  | "server_error";

/** An error that maps directly to a JSON error response. */
class HttpError extends Error {
  readonly status: number;
  readonly code: ErrorCode;
  readonly extra: Record<string, string>;

  constructor(
    status: number,
    code: ErrorCode,
    message: string,
    extra: Record<string, string> = {},
  ) {
    super(message);
    this.name = "HttpError";
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

/** The JSON body Plaid sends with every non-2xx response. */
interface PlaidErrorBody {
  error_type?: string | null;
  error_code?: string | null;
  error_message?: string | null;
  display_message?: string | null;
  request_id?: string | null;
}

interface PlaidApiErrorInit {
  path: string;
  httpStatus: number;
  errorType: string;
  errorCode: string;
  errorMessage: string;
  displayMessage: string | null;
  requestId: string | null;
}

/** A failed Plaid call (HTTP error, network failure or unreadable response). */
class PlaidApiError extends Error {
  readonly path: string;
  /** 0 when Plaid couldn't be reached. */
  readonly httpStatus: number;
  readonly errorType: string;
  readonly errorCode: string;
  readonly displayMessage: string | null;
  readonly requestId: string | null;

  constructor(init: PlaidApiErrorInit) {
    super(init.errorMessage);
    this.name = "PlaidApiError";
    this.path = init.path;
    this.httpStatus = init.httpStatus;
    this.errorType = init.errorType;
    this.errorCode = init.errorCode;
    this.displayMessage = init.displayMessage;
    this.requestId = init.requestId;
  }
}

/** Plaid errors caused by the server's Plaid setup rather than the user's item. */
const PLAID_CONFIG_ERROR_CODES = new Set([
  "INVALID_API_KEYS",
  "UNAUTHORIZED_ENVIRONMENT",
  "INVALID_PRODUCT",
]);

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

function errorResponse(error: HttpError): Response {
  return jsonResponse(error.status, {
    error: { code: error.code, message: error.message, ...error.extra },
  });
}

function httpErrorFromPlaid(error: PlaidApiError): HttpError {
  const extra = { plaid_error_code: error.errorCode };
  if (PLAID_CONFIG_ERROR_CODES.has(error.errorCode)) {
    return new HttpError(
      503,
      "plaid_not_configured",
      `Plaid rejected the server's configuration (${error.errorCode}). Check PLAID_CLIENT_ID, PLAID_SECRET and PLAID_ENV.`,
      extra,
    );
  }
  const message = error.errorType === "NETWORK_ERROR"
    ? "Couldn't reach Plaid. Try again in a moment."
    : error.displayMessage ?? (error.message ||
      `Plaid couldn't complete the request (${error.errorCode}).`);
  return new HttpError(502, "plaid_error", message, extra);
}

function toErrorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    if (error.status >= 500) {
      console.error(`[plaid] ${error.code}: ${error.message}`);
    }
    return errorResponse(error);
  }
  if (error instanceof PlaidApiError) {
    logPlaidError("request failed", error);
    return errorResponse(httpErrorFromPlaid(error));
  }
  console.error("[plaid] unexpected error:", describeUnknown(error));
  return errorResponse(
    new HttpError(
      500,
      "server_error",
      "Something went wrong on the server. Try again.",
    ),
  );
}

/** Logs a Plaid failure without secrets (never the request body). */
function logPlaidError(context: string, error: unknown): void {
  if (error instanceof PlaidApiError) {
    console.error(
      `[plaid] ${context}: ${error.path} → ${error.httpStatus} ${error.errorType}/${error.errorCode} (request_id ${
        error.requestId ?? "n/a"
      }): ${error.message}`,
    );
  } else {
    console.error(`[plaid] ${context}:`, describeUnknown(error));
  }
}

function describeUnknown(error: unknown): string {
  if (error instanceof Error) return `${error.name}: ${error.message}`;
  try {
    return JSON.stringify(error);
  } catch {
    return String(error);
  }
}

interface DbError {
  message: string;
  code?: string;
}

function dbFailure(context: string, error: DbError): HttpError {
  console.error(
    `[plaid] database error while ${context}: ${
      error.code ?? ""
    } ${error.message}`,
  );
  return new HttpError(
    500,
    "server_error",
    "The server couldn't update your brokerage data. Try again.",
  );
}

// ---------------------------------------------------------------------------
// Small value helpers (defensive against missing / mistyped fields)
// ---------------------------------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The object elements of `value` if it's an array, else []. */
function records<T>(value: unknown): T[] {
  if (!Array.isArray(value)) return [];
  return value.filter(isRecord) as unknown as T[];
}

/** Rows from a PostgREST result (`data` is untyped without generated types). */
function rowsOf<T>(data: unknown): T[] {
  return records<T>(data);
}

/** A trimmed, non-empty string, else null. */
function str(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/** A finite number (numeric strings accepted), else null. */
function num(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

/** A valid "yyyy-MM-dd" date (the date part of a timestamp is accepted), else null. */
function isoDate(value: unknown): string | null {
  const text = str(value);
  if (!text) return null;
  const match = /^(\d{4}-\d{2}-\d{2})/.exec(text);
  if (!match) return null;
  const date = new Date(`${match[1]}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString().slice(0, 10) === match[1] ? match[1] : null;
}

function utcDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function truncate(text: string, maxLength: number): string {
  return text.length <= maxLength ? text : `${text.slice(0, maxLength - 1)}…`;
}

function round(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
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
      "[plaid] SUPABASE_URL, SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY is missing",
    );
    throw new HttpError(
      500,
      "server_error",
      "The server is missing its Supabase configuration.",
    );
  }
  return { url, anonKey, serviceRoleKey };
}

type PlaidEnvironment = "sandbox" | "production";

interface PlaidConfig {
  clientId: string;
  secret: string;
  environment: PlaidEnvironment;
  baseUrl: string;
  redirectUri: string | null;
}

type PlaidConfigResult =
  | { ok: true; config: PlaidConfig }
  | { ok: false; reason: string };

function readPlaidConfig(): PlaidConfigResult {
  const clientId = env("PLAID_CLIENT_ID");
  const secret = env("PLAID_SECRET");
  if (!clientId || !secret) {
    return {
      ok: false,
      reason:
        "Brokerage connections aren't set up on the server yet (PLAID_CLIENT_ID and PLAID_SECRET are not set).",
    };
  }
  const environment = (env("PLAID_ENV") ?? "sandbox").toLowerCase();
  if (environment !== "sandbox" && environment !== "production") {
    return {
      ok: false,
      reason:
        `Brokerage connections aren't set up correctly on the server (PLAID_ENV must be "sandbox" or "production").`,
    };
  }
  return {
    ok: true,
    config: {
      clientId,
      secret,
      environment,
      baseUrl: environment === "production"
        ? "https://production.plaid.com"
        : "https://sandbox.plaid.com",
      redirectUri: env("PLAID_REDIRECT_URI"),
    },
  };
}

function requirePlaid(result: PlaidConfigResult): PlaidConfig {
  if (!result.ok) {
    throw new HttpError(503, "plaid_not_configured", result.reason);
  }
  return result.config;
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
        `[plaid] auth.getUser failed (${status}): ${error.message}`,
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
// Request parsing
// ---------------------------------------------------------------------------

type JsonObject = Record<string, unknown>;

async function readJsonObject(req: Request): Promise<JsonObject> {
  const text = await req.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    throw new HttpError(400, "bad_request", "The request body is too large.");
  }
  if (text.trim().length === 0) {
    throw new HttpError(
      400,
      "bad_request",
      'Send a JSON body like {"action": "sync"}.',
    );
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new HttpError(400, "bad_request", "The request body must be JSON.");
  }
  if (!isRecord(parsed)) {
    throw new HttpError(
      400,
      "bad_request",
      "The request body must be a JSON object.",
    );
  }
  return parsed;
}

/** A string field: null when absent, null or blank; 400 when not a string. */
function optionalString(
  body: JsonObject,
  key: string,
  maxLength: number,
): string | null {
  const value = body[key];
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") {
    throw new HttpError(400, "bad_request", `"${key}" must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > maxLength) {
    throw new HttpError(400, "bad_request", `"${key}" is too long.`);
  }
  return trimmed;
}

/** Like optionalString, but an over-long value is shortened instead of rejected. */
function optionalDisplayString(
  body: JsonObject,
  key: string,
  maxLength: number,
): string | null {
  const value = optionalString(body, key, MAX_BODY_BYTES);
  return value === null ? null : truncate(value, maxLength);
}

function requiredString(
  body: JsonObject,
  key: string,
  maxLength: number,
): string {
  const value = optionalString(body, key, maxLength);
  if (value === null) {
    throw new HttpError(400, "bad_request", `"${key}" is required.`);
  }
  return value;
}

function optionalUuid(body: JsonObject, key: string): string | null {
  const value = optionalString(body, key, 64);
  if (value === null) return null;
  if (!UUID_PATTERN.test(value)) {
    throw new HttpError(400, "bad_request", `"${key}" must be a UUID.`);
  }
  return value.toLowerCase();
}

function requiredUuid(body: JsonObject, key: string): string {
  const value = optionalUuid(body, key);
  if (value === null) {
    throw new HttpError(400, "bad_request", `"${key}" is required.`);
  }
  return value;
}

// ---------------------------------------------------------------------------
// Plaid API (REST, no SDK)
// ---------------------------------------------------------------------------

interface PlaidLinkTokenResponse {
  link_token?: string;
  expiration?: string;
  request_id?: string;
}

interface PlaidPublicTokenExchangeResponse {
  access_token?: string;
  item_id?: string;
  request_id?: string;
}

interface PlaidItem {
  item_id?: string;
  institution_id?: string | null;
  /** Present in newer API responses; optional. */
  institution_name?: string | null;
}

interface PlaidItemGetResponse {
  item?: PlaidItem;
  request_id?: string;
}

interface PlaidInstitution {
  institution_id?: string;
  name?: string | null;
}

interface PlaidInstitutionGetByIdResponse {
  institution?: PlaidInstitution;
  request_id?: string;
}

interface PlaidBalances {
  available?: number | null;
  current?: number | null;
  limit?: number | null;
  iso_currency_code?: string | null;
  unofficial_currency_code?: string | null;
}

interface PlaidAccount {
  account_id?: string;
  balances?: PlaidBalances | null;
  mask?: string | null;
  name?: string | null;
  official_name?: string | null;
  type?: string | null;
  subtype?: string | null;
}

interface PlaidSecurity {
  security_id?: string;
  name?: string | null;
  ticker_symbol?: string | null;
  /** equity, etf, mutual fund, cash, cryptocurrency, derivative, fixed income, loan, other */
  type?: string | null;
  is_cash_equivalent?: boolean | null;
  close_price?: number | null;
  iso_currency_code?: string | null;
  unofficial_currency_code?: string | null;
}

interface PlaidHolding {
  account_id?: string;
  security_id?: string;
  institution_price?: number | null;
  institution_price_as_of?: string | null;
  institution_price_datetime?: string | null;
  institution_value?: number | null;
  cost_basis?: number | null;
  quantity?: number | null;
  iso_currency_code?: string | null;
  unofficial_currency_code?: string | null;
}

interface PlaidHoldingsGetResponse {
  accounts?: PlaidAccount[];
  holdings?: PlaidHolding[];
  securities?: PlaidSecurity[];
  item?: PlaidItem;
  request_id?: string;
}

interface PlaidInvestmentTransaction {
  investment_transaction_id?: string;
  account_id?: string;
  security_id?: string | null;
  date?: string;
  name?: string | null;
  quantity?: number | null;
  amount?: number | null;
  price?: number | null;
  fees?: number | null;
  /** buy, sell, cancel, cash, fee, transfer */
  type?: string | null;
  subtype?: string | null;
  iso_currency_code?: string | null;
  unofficial_currency_code?: string | null;
}

interface PlaidInvestmentTransactionsGetResponse {
  accounts?: PlaidAccount[];
  investment_transactions?: PlaidInvestmentTransaction[];
  securities?: PlaidSecurity[];
  total_investment_transactions?: number;
  item?: PlaidItem;
  request_id?: string;
}

/**
 * POSTs to a Plaid endpoint with the client credentials in the body.
 * Throws PlaidApiError on any failure. Never logs the body (it holds secrets).
 */
async function plaidRequest<T>(
  plaid: PlaidConfig,
  path: string,
  body: JsonObject,
): Promise<T> {
  let response: Response;
  let text: string;
  try {
    response = await fetch(`${plaid.baseUrl}${path}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Plaid-Version": PLAID_API_VERSION,
      },
      body: JSON.stringify({
        ...body,
        client_id: plaid.clientId,
        secret: plaid.secret,
      }),
      signal: AbortSignal.timeout(PLAID_TIMEOUT_MS),
    });
    text = await response.text();
  } catch (error) {
    const timedOut = error instanceof DOMException &&
      (error.name === "TimeoutError" || error.name === "AbortError");
    throw new PlaidApiError({
      path,
      httpStatus: 0,
      errorType: "NETWORK_ERROR",
      errorCode: timedOut ? "TIMEOUT" : "NETWORK_ERROR",
      errorMessage: timedOut
        ? "Plaid took too long to respond."
        : "Couldn't reach Plaid.",
      displayMessage: null,
      requestId: null,
    });
  }

  let parsed: unknown = null;
  if (text.length > 0) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = null;
    }
  }

  if (!response.ok) {
    const failure: PlaidErrorBody = isRecord(parsed) ? parsed : {};
    throw new PlaidApiError({
      path,
      httpStatus: response.status,
      errorType: str(failure.error_type) ?? "API_ERROR",
      errorCode: str(failure.error_code) ?? `HTTP_${response.status}`,
      errorMessage: str(failure.error_message) ??
        `Plaid responded with HTTP ${response.status}.`,
      displayMessage: str(failure.display_message),
      requestId: str(failure.request_id),
    });
  }

  if (!isRecord(parsed)) {
    throw new PlaidApiError({
      path,
      httpStatus: response.status,
      errorType: "API_ERROR",
      errorCode: "INVALID_RESPONSE",
      errorMessage: "Plaid sent a response the server couldn't read.",
      displayMessage: null,
      requestId: null,
    });
  }
  return parsed as T;
}

/** Best-effort /item/remove. Returns whether Plaid confirmed the removal. */
async function removePlaidItem(
  plaid: PlaidConfig,
  accessToken: string,
): Promise<boolean> {
  try {
    await plaidRequest<JsonObject>(plaid, "/item/remove", {
      access_token: accessToken,
    });
    return true;
  } catch (error) {
    logPlaidError("item/remove failed (ignored)", error);
    return false;
  }
}

/** Best-effort institution id/name lookup for an item. */
async function lookupInstitution(
  plaid: PlaidConfig,
  accessToken: string,
  knownId: string | null,
): Promise<{ id: string | null; name: string | null }> {
  let id = knownId;
  let name: string | null = null;
  try {
    const response = await plaidRequest<PlaidItemGetResponse>(
      plaid,
      "/item/get",
      { access_token: accessToken },
    );
    const item: PlaidItem = isRecord(response.item) ? response.item : {};
    id = id ?? str(item.institution_id);
    name = str(item.institution_name);
    if (!name && id) {
      const institution = await plaidRequest<PlaidInstitutionGetByIdResponse>(
        plaid,
        "/institutions/get_by_id",
        { institution_id: id, country_codes: ["US"] },
      );
      const details: PlaidInstitution = isRecord(institution.institution)
        ? institution.institution
        : {};
      name = str(details.name);
    }
  } catch (error) {
    logPlaidError("institution lookup failed (ignored)", error);
  }
  return { id, name };
}

// ---------------------------------------------------------------------------
// Database helpers
// ---------------------------------------------------------------------------

interface DbResult {
  data: unknown;
  error: DbError | null;
}

/**
 * Reads every row of a query by paging with `.range()` until a page comes
 * back empty (robust to any server-side max-rows setting). `page` must apply
 * a stable `.order()`.
 */
async function selectAll<T>(
  context: string,
  page: (from: number, to: number) => PromiseLike<DbResult>,
): Promise<T[]> {
  const all: T[] = [];
  let from = 0;
  for (;;) {
    const { data, error } = await page(from, from + DB_PAGE_SIZE - 1);
    if (error) throw dbFailure(context, error);
    const rows = rowsOf<T>(data);
    if (rows.length === 0) break;
    all.push(...rows);
    from += rows.length;
  }
  return all;
}

/**
 * Of `keys` (values of a globally unique column), returns those that already
 * exist in `table` on rows that belong to someone else, so an upsert never
 * overwrites another user's row. `belongsToCaller` decides ownership.
 */
async function keysOwnedByOthers(
  admin: AdminClient,
  table: string,
  keyColumn: string,
  ownerColumns: string,
  keys: readonly string[],
  belongsToCaller: (row: JsonObject) => boolean,
): Promise<Set<string>> {
  const foreign = new Set<string>();
  for (const part of chunk(keys, FILTER_CHUNK_SIZE)) {
    const { data, error } = await admin
      .from(table)
      .select(`${keyColumn}, ${ownerColumns}`)
      .in(keyColumn, part);
    if (error) throw dbFailure(`checking ${table} ownership`, error);
    for (const row of rowsOf<JsonObject>(data)) {
      const key = str(row[keyColumn]);
      if (key && !belongsToCaller(row)) foreign.add(key);
    }
  }
  if (foreign.size > 0) {
    console.warn(
      `[plaid] skipped ${foreign.size} ${table} row(s) whose ${keyColumn} belongs to another connection`,
    );
  }
  return foreign;
}

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

type ConnectionStatus = "active" | "needs_attention" | "error";

interface SyncContext {
  admin: AdminClient;
  userId: string;
  plaid: PlaidConfig;
}

interface SyncCounts {
  accounts: number;
  holdings: number;
  transactions: number;
}

/** The brokerage_connections columns sync needs. */
interface ConnectionRow {
  id: string;
  plaid_item_id: string;
  institution_name: string | null;
}

interface AccountRow {
  user_id: string;
  connection_id: string;
  plaid_account_id: string;
  name: string;
  official_name: string | null;
  mask: string | null;
  type: string;
  subtype: string | null;
  current_balance: number | null;
  currency: string;
  updated_at: string;
}

interface HoldingRow {
  user_id: string;
  account_id: string;
  security_id: string;
  ticker: string | null;
  name: string;
  security_type: string | null;
  quantity: number;
  price: number | null;
  price_as_of: string | null;
  value: number;
  cost_basis: number | null;
  currency: string;
  updated_at: string;
}

interface TransactionRow {
  user_id: string;
  account_id: string;
  plaid_transaction_id: string;
  date: string;
  name: string;
  ticker: string | null;
  security_name: string | null;
  type: string;
  subtype: string | null;
  quantity: number | null;
  price: number | null;
  amount: number | null;
  fees: number | null;
  currency: string;
}

interface StoredAccount {
  id: string;
  plaid_account_id: string;
}

function addSecurities(
  map: Map<string, PlaidSecurity>,
  securities: unknown,
): void {
  for (const security of records<PlaidSecurity>(securities)) {
    const id = str(security.security_id);
    if (id) map.set(id, security);
  }
}

function currencyOf(
  ...candidates: Array<
    | {
      iso_currency_code?: string | null;
      unofficial_currency_code?: string | null;
    }
    | null
    | undefined
  >
): string {
  for (const candidate of candidates) {
    if (!candidate) continue;
    const code = str(candidate.iso_currency_code) ??
      str(candidate.unofficial_currency_code);
    if (code) return code.toUpperCase();
  }
  return "USD";
}

async function updateConnection(
  ctx: SyncContext,
  connectionId: string,
  update: {
    status: ConnectionStatus;
    error_message: string | null;
    last_synced_at?: string;
  },
): Promise<void> {
  const { error } = await ctx.admin
    .from("brokerage_connections")
    .update(update)
    .eq("id", connectionId)
    .eq("user_id", ctx.userId);
  if (error) throw dbFailure("updating a brokerage connection", error);
}

/**
 * Stores /investments/holdings/get: upserts qualifying accounts and their
 * holdings, then deletes this connection's holdings Plaid no longer reports.
 * Returns the connection's stored accounts (for transactions) and counts.
 */
async function storeHoldings(
  ctx: SyncContext,
  connectionId: string,
  response: PlaidHoldingsGetResponse,
): Promise<
  { accounts: number; holdings: number; storedAccounts: StoredAccount[] }
> {
  const now = new Date().toISOString();
  const plaidAccounts = records<PlaidAccount>(response.accounts);
  const plaidHoldings = records<PlaidHolding>(response.holdings);
  const securities = new Map<string, PlaidSecurity>();
  addSecurities(securities, response.securities);

  // Accounts that have holdings or are investment accounts.
  const accountIdsWithHoldings = new Set<string>();
  for (const holding of plaidHoldings) {
    const accountId = str(holding.account_id);
    if (accountId) accountIdsWithHoldings.add(accountId);
  }
  const accountRows = new Map<string, AccountRow>();
  for (const account of plaidAccounts) {
    const plaidAccountId = str(account.account_id);
    if (!plaidAccountId || accountRows.has(plaidAccountId)) continue;
    const type = str(account.type)?.toLowerCase() ?? null;
    if (!accountIdsWithHoldings.has(plaidAccountId) && type !== "investment") {
      continue;
    }
    const balances: PlaidBalances = isRecord(account.balances)
      ? account.balances
      : {};
    accountRows.set(plaidAccountId, {
      user_id: ctx.userId,
      connection_id: connectionId,
      plaid_account_id: plaidAccountId,
      name: str(account.name) ?? str(account.official_name) ??
        "Investment account",
      official_name: str(account.official_name),
      mask: str(account.mask),
      type: type ?? "investment",
      subtype: str(account.subtype),
      current_balance: num(balances.current),
      currency: currencyOf(balances),
      updated_at: now,
    });
  }

  // Never take over an account row that belongs to another connection.
  const foreignAccounts = await keysOwnedByOthers(
    ctx.admin,
    "investment_accounts",
    "plaid_account_id",
    "user_id, connection_id",
    [...accountRows.keys()],
    (row) => row.user_id === ctx.userId && row.connection_id === connectionId,
  );
  const accountsToUpsert = [...accountRows.values()].filter((row) =>
    !foreignAccounts.has(row.plaid_account_id)
  );

  const accountIdByPlaidId = new Map<string, string>();
  for (const part of chunk(accountsToUpsert, UPSERT_CHUNK_SIZE)) {
    const { data, error } = await ctx.admin
      .from("investment_accounts")
      .upsert(part, { onConflict: "plaid_account_id" })
      .select("id, plaid_account_id");
    if (error) throw dbFailure("saving investment accounts", error);
    for (const row of rowsOf<StoredAccount>(data)) {
      accountIdByPlaidId.set(row.plaid_account_id, row.id);
    }
  }

  // Holdings, merged by (account, security) so one upsert never hits a row twice.
  const holdingRows = new Map<string, HoldingRow>();
  for (const holding of plaidHoldings) {
    const plaidAccountId = str(holding.account_id);
    const securityId = str(holding.security_id);
    const accountId = plaidAccountId
      ? accountIdByPlaidId.get(plaidAccountId)
      : undefined;
    if (!accountId || !securityId) continue;

    const security = securities.get(securityId);
    const quantity = num(holding.quantity) ?? 0;
    const price = num(holding.institution_price);
    const value = num(holding.institution_value) ??
      (price !== null ? quantity * price : 0);
    const costBasis = num(holding.cost_basis);
    const key = `${accountId}|${securityId}`;
    const existing = holdingRows.get(key);
    if (existing) {
      existing.quantity += quantity;
      existing.value += value;
      if (costBasis !== null) {
        existing.cost_basis = (existing.cost_basis ?? 0) + costBasis;
      }
      continue;
    }
    const ticker = str(security?.ticker_symbol);
    holdingRows.set(key, {
      user_id: ctx.userId,
      account_id: accountId,
      security_id: securityId,
      ticker,
      name: str(security?.name) ?? ticker ?? "Unknown security",
      security_type: str(security?.type),
      quantity,
      price,
      price_as_of: isoDate(holding.institution_price_as_of) ??
        isoDate(holding.institution_price_datetime),
      value,
      cost_basis: costBasis,
      currency: currencyOf(holding, security),
      updated_at: now,
    });
  }

  let holdingsCount = 0;
  for (const part of chunk([...holdingRows.values()], UPSERT_CHUNK_SIZE)) {
    const { error } = await ctx.admin
      .from("holdings")
      .upsert(part, { onConflict: "account_id,security_id" });
    if (error) throw dbFailure("saving holdings", error);
    holdingsCount += part.length;
  }

  // Every account this connection has stored (including ones not reported now).
  const storedAccounts = await selectAll<StoredAccount>(
    "reading investment accounts",
    (from, to) =>
      ctx.admin
        .from("investment_accounts")
        .select("id, plaid_account_id")
        .eq("user_id", ctx.userId)
        .eq("connection_id", connectionId)
        .order("id")
        .range(from, to),
  );

  // Delete this connection's holdings that Plaid no longer reports.
  const staleHoldingIds: string[] = [];
  for (
    const accountIds of chunk(
      storedAccounts.map((a) => a.id),
      FILTER_CHUNK_SIZE,
    )
  ) {
    const existing = await selectAll<{
      id: string;
      account_id: string;
      security_id: string;
    }>(
      "reading holdings",
      (from, to) =>
        ctx.admin
          .from("holdings")
          .select("id, account_id, security_id")
          .eq("user_id", ctx.userId)
          .in("account_id", accountIds)
          .order("id")
          .range(from, to),
    );
    for (const row of existing) {
      if (!holdingRows.has(`${row.account_id}|${row.security_id}`)) {
        staleHoldingIds.push(row.id);
      }
    }
  }
  for (const ids of chunk(staleHoldingIds, FILTER_CHUNK_SIZE)) {
    const { error } = await ctx.admin
      .from("holdings")
      .delete()
      .eq("user_id", ctx.userId)
      .in("id", ids);
    if (error) throw dbFailure("removing old holdings", error);
  }

  return {
    accounts: accountIdByPlaidId.size,
    holdings: holdingsCount,
    storedAccounts,
  };
}

/**
 * Fetches the last 90 days of investment transactions (all pages) and
 * upserts them. Returns 0 without failing when Plaid isn't ready yet.
 */
async function syncTransactions(
  ctx: SyncContext,
  accessToken: string,
  storedAccounts: readonly StoredAccount[],
  initialSecurities: unknown,
): Promise<number> {
  if (storedAccounts.length === 0) return 0;
  const accountIdByPlaidId = new Map(
    storedAccounts.map((a) => [a.plaid_account_id, a.id] as const),
  );
  const securities = new Map<string, PlaidSecurity>();
  addSecurities(securities, initialSecurities);

  const endDate = utcDate(new Date());
  const startDate = utcDate(
    new Date(Date.now() - TRANSACTION_HISTORY_DAYS * 24 * 60 * 60 * 1000),
  );

  const fetched = new Map<string, PlaidInvestmentTransaction>();
  let offset = 0;
  for (let page = 0; page < PLAID_TRANSACTIONS_MAX_PAGES; page++) {
    let response: PlaidInvestmentTransactionsGetResponse;
    try {
      response = await plaidRequest<PlaidInvestmentTransactionsGetResponse>(
        ctx.plaid,
        "/investments/transactions/get",
        {
          access_token: accessToken,
          start_date: startDate,
          end_date: endDate,
          options: { count: PLAID_TRANSACTIONS_PAGE_SIZE, offset },
        },
      );
    } catch (error) {
      // Normal right after linking: Plaid is still pulling history.
      if (
        error instanceof PlaidApiError &&
        error.errorCode === "PRODUCT_NOT_READY"
      ) {
        console.log("[plaid] investment transactions not ready yet; skipping");
        return 0;
      }
      throw error;
    }

    addSecurities(securities, response.securities);
    const batch = records<PlaidInvestmentTransaction>(
      response.investment_transactions,
    );
    for (const transaction of batch) {
      const id = str(transaction.investment_transaction_id);
      if (id) fetched.set(id, transaction);
    }
    if (batch.length === 0) break;
    offset += batch.length;
    const total = num(response.total_investment_transactions);
    if (
      total !== null
        ? offset >= total
        : batch.length < PLAID_TRANSACTIONS_PAGE_SIZE
    ) {
      break;
    }
    if (page === PLAID_TRANSACTIONS_MAX_PAGES - 1) {
      console.warn(
        `[plaid] stopped after ${offset} investment transactions (page cap)`,
      );
    }
  }

  const rows: TransactionRow[] = [];
  for (const [plaidTransactionId, transaction] of fetched) {
    const plaidAccountId = str(transaction.account_id);
    const accountId = plaidAccountId
      ? accountIdByPlaidId.get(plaidAccountId)
      : undefined;
    const date = isoDate(transaction.date);
    if (!accountId || !date) continue;
    const securityId = str(transaction.security_id);
    const security = securityId ? securities.get(securityId) : undefined;
    const securityName = str(security?.name);
    const type = str(transaction.type)?.toLowerCase() ?? "";
    rows.push({
      user_id: ctx.userId,
      account_id: accountId,
      plaid_transaction_id: plaidTransactionId,
      date,
      name: str(transaction.name) ?? securityName ?? (type || "Transaction"),
      ticker: str(security?.ticker_symbol),
      security_name: securityName,
      type,
      subtype: str(transaction.subtype),
      quantity: num(transaction.quantity),
      price: num(transaction.price),
      amount: num(transaction.amount),
      fees: num(transaction.fees),
      currency: currencyOf(transaction, security),
    });
  }

  const foreign = await keysOwnedByOthers(
    ctx.admin,
    "investment_transactions",
    "plaid_transaction_id",
    "user_id",
    rows.map((row) => row.plaid_transaction_id),
    (row) => row.user_id === ctx.userId,
  );
  const toUpsert = rows.filter((row) => !foreign.has(row.plaid_transaction_id));

  let count = 0;
  for (const part of chunk(toUpsert, UPSERT_CHUNK_SIZE)) {
    const { error } = await ctx.admin
      .from("investment_transactions")
      .upsert(part, { onConflict: "plaid_transaction_id" });
    if (error) throw dbFailure("saving investment transactions", error);
    count += part.length;
  }
  return count;
}

const RELOGIN_ERROR_CODES = new Set([
  "ITEM_LOGIN_REQUIRED",
  "INVALID_CREDENTIALS",
  "INVALID_MFA",
  "INVALID_SEND_METHOD",
  "INVALID_UPDATED_USERNAME",
  "ITEM_LOCKED",
  "MFA_NOT_SUPPORTED",
  "USER_SETUP_REQUIRED",
  "USER_INPUT_TIMEOUT",
]);

const DISCONNECTED_ERROR_CODES = new Set([
  "ACCESS_NOT_GRANTED",
  "INVALID_ACCESS_TOKEN",
  "ITEM_NOT_FOUND",
]);

/** A readable status + message for a connection whose sync failed. */
function describeSyncProblem(
  error: unknown,
  institution: string,
): { status: ConnectionStatus; message: string } {
  if (!(error instanceof PlaidApiError)) {
    return {
      status: "error",
      message: `Haki couldn't finish syncing ${institution}. Try again later.`,
    };
  }
  if (RELOGIN_ERROR_CODES.has(error.errorCode)) {
    return {
      status: "needs_attention",
      message:
        `${institution} needs you to sign in again. Remove this connection and connect it again to resume syncing.`,
    };
  }
  if (DISCONNECTED_ERROR_CODES.has(error.errorCode)) {
    return {
      status: "needs_attention",
      message:
        `${institution} is no longer connected. Remove this connection and connect it again.`,
    };
  }
  if (
    error.errorCode === "NO_INVESTMENT_ACCOUNTS" ||
    error.errorCode === "NO_ACCOUNTS"
  ) {
    return {
      status: "needs_attention",
      message: `No investment accounts were found at ${institution}.`,
    };
  }
  if (error.errorType === "ITEM_ERROR") {
    return {
      status: "needs_attention",
      message: error.displayMessage ??
        `${institution} needs attention (${error.errorCode}). Try removing it and connecting it again.`,
    };
  }
  if (
    error.errorType === "INSTITUTION_ERROR" ||
    error.errorType === "NETWORK_ERROR"
  ) {
    return {
      status: "error",
      message:
        `${institution} isn't responding right now. Haki will try again the next time it syncs.`,
    };
  }
  if (error.errorType === "RATE_LIMIT_EXCEEDED") {
    return {
      status: "error",
      message:
        `Too many sync requests for ${institution}. Try again in a few minutes.`,
    };
  }
  return {
    status: "error",
    message: error.displayMessage ??
      `Couldn't sync ${institution} right now (${error.errorCode}). Try again later.`,
  };
}

/**
 * Syncs one connection. Never throws: failures are recorded on the
 * connection (status + error_message) so other connections keep syncing.
 */
async function syncConnection(
  ctx: SyncContext,
  connection: ConnectionRow,
  accessToken: string | null,
): Promise<SyncCounts> {
  const institution = str(connection.institution_name) ?? "Your brokerage";
  const counts: SyncCounts = { accounts: 0, holdings: 0, transactions: 0 };
  let holdingsSyncedAt: string | null = null;

  try {
    if (!accessToken) {
      throw new PlaidApiError({
        path: "(local)",
        httpStatus: 0,
        errorType: "INVALID_INPUT",
        errorCode: "ITEM_NOT_FOUND",
        errorMessage: "No Plaid item is stored for this connection.",
        displayMessage: null,
        requestId: null,
      });
    }

    let holdingsResponse: PlaidHoldingsGetResponse;
    try {
      holdingsResponse = await plaidRequest<PlaidHoldingsGetResponse>(
        ctx.plaid,
        "/investments/holdings/get",
        { access_token: accessToken },
      );
    } catch (error) {
      if (
        error instanceof PlaidApiError &&
        error.errorCode === "PRODUCT_NOT_READY"
      ) {
        // Plaid is still preparing the item; the next sync will pick it up.
        console.log("[plaid] holdings not ready yet; skipping this connection");
        await updateConnection(ctx, connection.id, {
          status: "active",
          error_message: null,
        });
        return counts;
      }
      throw error;
    }

    const stored = await storeHoldings(ctx, connection.id, holdingsResponse);
    counts.accounts = stored.accounts;
    counts.holdings = stored.holdings;
    holdingsSyncedAt = new Date().toISOString();

    counts.transactions = await syncTransactions(
      ctx,
      accessToken,
      stored.storedAccounts,
      holdingsResponse.securities,
    );

    await updateConnection(ctx, connection.id, {
      status: "active",
      error_message: null,
      last_synced_at: new Date().toISOString(),
    });
  } catch (error) {
    logPlaidError(`sync of connection ${connection.id} failed`, error);
    const problem = describeSyncProblem(error, institution);
    try {
      await updateConnection(ctx, connection.id, {
        status: problem.status,
        error_message: truncate(problem.message, MAX_ERROR_MESSAGE_LENGTH),
        ...(holdingsSyncedAt ? { last_synced_at: holdingsSyncedAt } : {}),
      });
    } catch (updateError) {
      console.error(
        "[plaid] couldn't record the sync failure:",
        describeUnknown(updateError),
      );
    }
  }
  return counts;
}

/**
 * Upserts today's (UTC) portfolio snapshot from the user's stored holdings.
 * With no holdings stored (no connections left, or none has synced data),
 * today's snapshot is removed instead, so the chart never shows a fake 0.
 */
async function refreshSnapshot(
  admin: AdminClient,
  userId: string,
): Promise<void> {
  const date = utcDate(new Date());
  const holdings = await selectAll<{ value: unknown; cost_basis: unknown }>(
    "reading holdings for the snapshot",
    (from, to) =>
      admin
        .from("holdings")
        .select("id, value, cost_basis")
        .eq("user_id", userId)
        .order("id")
        .range(from, to),
  );

  if (holdings.length === 0) {
    const { error } = await admin
      .from("portfolio_snapshots")
      .delete()
      .eq("user_id", userId)
      .eq("date", date);
    if (error) throw dbFailure("clearing today's snapshot", error);
    return;
  }

  let totalValue = 0;
  let costBasis = 0;
  let hasCostBasis = false;
  for (const holding of holdings) {
    totalValue += num(holding.value) ?? 0;
    const cost = num(holding.cost_basis);
    if (cost !== null) {
      costBasis += cost;
      hasCostBasis = true;
    }
  }

  const { error: upsertError } = await admin
    .from("portfolio_snapshots")
    .upsert(
      {
        user_id: userId,
        date,
        total_value: round(totalValue, 4),
        cost_basis: hasCostBasis ? round(costBasis, 4) : null,
      },
      { onConflict: "user_id,date" },
    );
  if (upsertError) throw dbFailure("saving today's snapshot", upsertError);
}

/** The snapshot is a convenience; a failure must not fail the request. */
async function refreshSnapshotSafely(
  admin: AdminClient,
  userId: string,
): Promise<void> {
  try {
    await refreshSnapshot(admin, userId);
  } catch (error) {
    console.error(
      "[plaid] snapshot refresh failed (ignored):",
      describeUnknown(error),
    );
  }
}

/** Access tokens for the given plaid_items ids, scoped to the user. */
async function loadAccessTokens(
  admin: AdminClient,
  userId: string,
  plaidItemIds: readonly string[],
): Promise<Map<string, string>> {
  const tokens = new Map<string, string>();
  for (const ids of chunk(plaidItemIds, FILTER_CHUNK_SIZE)) {
    const { data, error } = await admin
      .from("plaid_items")
      .select("id, access_token")
      .eq("user_id", userId)
      .in("id", ids);
    if (error) throw dbFailure("reading Plaid items", error);
    for (const row of rowsOf<{ id: string; access_token: unknown }>(data)) {
      const token = str(row.access_token);
      if (token) tokens.set(row.id, token);
    }
  }
  return tokens;
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

async function actionLinkToken(
  plaid: PlaidConfig,
  userId: string,
): Promise<{ link_token: string; expiration: string }> {
  const request: JsonObject = {
    client_name: "Haki",
    user: { client_user_id: userId },
    products: ["investments"],
    country_codes: ["US"],
    language: "en",
  };
  if (plaid.redirectUri) request.redirect_uri = plaid.redirectUri;

  const response = await plaidRequest<PlaidLinkTokenResponse>(
    plaid,
    "/link/token/create",
    request,
  );
  const linkToken = str(response.link_token);
  if (!linkToken) {
    throw new HttpError(
      502,
      "plaid_error",
      "Plaid didn't return a link token.",
    );
  }
  return {
    link_token: linkToken,
    // Link tokens last 4 hours unless Plaid says otherwise.
    expiration: str(response.expiration) ??
      new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString(),
  };
}

async function actionExchange(
  ctx: SyncContext,
  body: JsonObject,
): Promise<{
  connection_id: string;
  accounts: number;
  holdings: number;
  transactions: number;
}> {
  const publicToken = requiredString(body, "public_token", 512);
  let institutionId = optionalString(body, "institution_id", 128);
  let institutionName = optionalDisplayString(body, "institution_name", 200);

  const exchanged = await plaidRequest<PlaidPublicTokenExchangeResponse>(
    ctx.plaid,
    "/item/public_token/exchange",
    { public_token: publicToken },
  );
  const accessToken = str(exchanged.access_token);
  const itemId = str(exchanged.item_id);
  if (!accessToken || !itemId) {
    throw new HttpError(
      502,
      "plaid_error",
      "Plaid didn't return an item for this connection.",
    );
  }

  if (!institutionId || !institutionName) {
    const found = await lookupInstitution(
      ctx.plaid,
      accessToken,
      institutionId,
    );
    institutionId = institutionId ?? found.id;
    institutionName = institutionName ??
      (found.name ? truncate(found.name, 200) : null);
  }

  const { data: itemRow, error: itemError } = await ctx.admin
    .from("plaid_items")
    .insert({ user_id: ctx.userId, item_id: itemId, access_token: accessToken })
    .select("id")
    .single();
  const plaidItemId = isRecord(itemRow) ? str(itemRow.id) : null;
  if (itemError || !plaidItemId) {
    // 23505 = the item is already stored; don't revoke a live connection.
    if (itemError?.code !== "23505") {
      await removePlaidItem(ctx.plaid, accessToken);
    }
    throw dbFailure(
      "saving the Plaid item",
      itemError ?? { message: "insert returned no row" },
    );
  }

  const { data: connectionRow, error: connectionError } = await ctx.admin
    .from("brokerage_connections")
    .insert({
      plaid_item_id: plaidItemId,
      user_id: ctx.userId,
      institution_id: institutionId,
      institution_name: institutionName ?? "Brokerage",
      status: "active",
    })
    .select("id, plaid_item_id, institution_name")
    .single();
  const connection: ConnectionRow | null =
    isRecord(connectionRow) && str(connectionRow.id)
      ? {
        id: String(connectionRow.id),
        plaid_item_id: plaidItemId,
        institution_name: str(connectionRow.institution_name),
      }
      : null;
  if (connectionError || !connection) {
    const { error: cleanupError } = await ctx.admin
      .from("plaid_items")
      .delete()
      .eq("id", plaidItemId)
      .eq("user_id", ctx.userId);
    if (cleanupError) {
      console.error(
        "[plaid] couldn't clean up the Plaid item:",
        cleanupError.message,
      );
    }
    await removePlaidItem(ctx.plaid, accessToken);
    throw dbFailure(
      "saving the brokerage connection",
      connectionError ?? { message: "insert returned no row" },
    );
  }

  const counts = await syncConnection(ctx, connection, accessToken);
  await refreshSnapshotSafely(ctx.admin, ctx.userId);
  return { connection_id: connection.id, ...counts };
}

async function actionSync(
  ctx: SyncContext,
  body: JsonObject,
): Promise<{
  connections: number;
  accounts: number;
  holdings: number;
  transactions: number;
}> {
  const connectionId = optionalUuid(body, "connection_id");

  let query = ctx.admin
    .from("brokerage_connections")
    .select("id, plaid_item_id, institution_name")
    .eq("user_id", ctx.userId);
  if (connectionId) query = query.eq("id", connectionId);
  const { data, error } = await query.order("created_at", { ascending: true });
  if (error) throw dbFailure("reading brokerage connections", error);

  const connections = rowsOf<ConnectionRow>(data).filter((row) =>
    str(row.id) && str(row.plaid_item_id)
  );
  if (connectionId && connections.length === 0) {
    throw new HttpError(
      404,
      "not_found",
      "That brokerage connection wasn't found.",
    );
  }

  const tokens = await loadAccessTokens(
    ctx.admin,
    ctx.userId,
    connections.map((c) => c.plaid_item_id),
  );

  const totals = {
    connections: connections.length,
    accounts: 0,
    holdings: 0,
    transactions: 0,
  };
  for (const connection of connections) {
    const counts = await syncConnection(
      ctx,
      connection,
      tokens.get(connection.plaid_item_id) ?? null,
    );
    totals.accounts += counts.accounts;
    totals.holdings += counts.holdings;
    totals.transactions += counts.transactions;
  }

  await refreshSnapshotSafely(ctx.admin, ctx.userId);
  return totals;
}

async function actionRemove(
  admin: AdminClient,
  userId: string,
  plaid: PlaidConfigResult,
  body: JsonObject,
): Promise<{ removed: true }> {
  const connectionId = requiredUuid(body, "connection_id");

  const { data: connectionRow, error: connectionError } = await admin
    .from("brokerage_connections")
    .select("id, plaid_item_id")
    .eq("id", connectionId)
    .eq("user_id", userId)
    .maybeSingle();
  if (connectionError) {
    throw dbFailure("reading the brokerage connection", connectionError);
  }
  const plaidItemId = isRecord(connectionRow)
    ? str(connectionRow.plaid_item_id)
    : null;
  if (!isRecord(connectionRow) || !plaidItemId) {
    throw new HttpError(
      404,
      "not_found",
      "That brokerage connection wasn't found.",
    );
  }

  const { data: itemRow, error: itemError } = await admin
    .from("plaid_items")
    .select("id, access_token")
    .eq("id", plaidItemId)
    .eq("user_id", userId)
    .maybeSingle();
  if (itemError) throw dbFailure("reading the Plaid item", itemError);
  const accessToken = isRecord(itemRow) ? str(itemRow.access_token) : null;

  // Revoke at Plaid first (best effort), so the token stops working.
  if (accessToken) {
    if (plaid.ok) {
      await removePlaidItem(plaid.config, accessToken);
    } else {
      console.warn(
        "[plaid] Plaid isn't configured; deleting the item locally only",
      );
    }
  }

  if (isRecord(itemRow)) {
    // Cascades to the connection, its accounts, holdings and transactions.
    const { error } = await admin
      .from("plaid_items")
      .delete()
      .eq("id", plaidItemId)
      .eq("user_id", userId);
    if (error) throw dbFailure("deleting the Plaid item", error);
  } else {
    const { error } = await admin
      .from("brokerage_connections")
      .delete()
      .eq("id", connectionId)
      .eq("user_id", userId);
    if (error) throw dbFailure("deleting the brokerage connection", error);
  }

  await refreshSnapshotSafely(admin, userId);
  return { removed: true };
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
    const body = await readJsonObject(req);
    const admin = createAdminClient(supabaseEnv);
    const plaid = readPlaidConfig();

    switch (body.action) {
      case "link_token":
        return jsonResponse(
          200,
          await actionLinkToken(requirePlaid(plaid), userId),
        );
      case "exchange":
        return jsonResponse(
          200,
          await actionExchange(
            { admin, userId, plaid: requirePlaid(plaid) },
            body,
          ),
        );
      case "sync":
        return jsonResponse(
          200,
          await actionSync({ admin, userId, plaid: requirePlaid(plaid) }, body),
        );
      case "remove":
        return jsonResponse(
          200,
          await actionRemove(admin, userId, plaid, body),
        );
      default:
        throw new HttpError(
          400,
          "bad_request",
          '"action" must be one of "link_token", "exchange", "sync" or "remove".',
        );
    }
  } catch (error) {
    return toErrorResponse(error);
  }
});
