# Haki edge functions

Two Supabase Edge Functions (Deno, TypeScript). Each `index.ts` is
self-contained (no shared or relative imports), so each deploys as a single
file. They use `npm:@supabase/supabase-js@2` and call Plaid's REST API
directly with `fetch` (no Plaid SDK).

Both functions:

- **Authenticate every request.** They read `Authorization: Bearer <jwt>` and
  resolve the user with `auth.getUser(jwt)` on an anon-key client. A missing or
  invalid session gets `401 unauthorized`.
- **Write with the service role, scoped by user.** Every query filters by the
  caller's `user_id`. Upserts on globally unique Plaid ids (`plaid_account_id`,
  `plaid_transaction_id`) first check that no other user or connection owns that
  id, so a sync can never overwrite someone else's rows.
- **Never return or log Plaid access tokens.** The tokens stay in `plaid_items`,
  which clients can't read.
- **Respond with JSON.** Errors are non-2xx with
  `{"error": {"code": "...", "message": "..."}}`. `OPTIONS` (CORS preflight)
  returns 204.

## `plaid`

`POST` a JSON body with an `action`:

| Request | Response (200) |
|---|---|
| `{"action":"link_token"}` | `{"link_token": String, "expiration": String}` |
| `{"action":"exchange","public_token": String,"institution_id": String?,"institution_name": String?}` | `{"connection_id": String, "accounts": Int, "holdings": Int, "transactions": Int}` |
| `{"action":"sync","connection_id": String?}` | `{"connections": Int, "accounts": Int, "holdings": Int, "transactions": Int}` |
| `{"action":"remove","connection_id": String}` | `{"removed": true}` |

Error codes:

| Code | Status | Meaning |
|---|---|---|
| `unauthorized` | 401 | Missing or invalid session |
| `bad_request` | 400 / 405 | Bad JSON, unknown action, missing or invalid field, or a method other than POST |
| `not_found` | 404 | The `connection_id` isn't one of the caller's connections |
| `plaid_error` | 502 | Plaid rejected the request or couldn't be reached. The error object also has `plaid_error_code`. |
| `plaid_not_configured` | 503 | `PLAID_CLIENT_ID` or `PLAID_SECRET` is missing, `PLAID_ENV` is invalid, or Plaid rejected the keys (`INVALID_API_KEYS`, `UNAUTHORIZED_ENVIRONMENT`, `INVALID_PRODUCT`) |
| `server_error` | 500 / 503 | Database or configuration failure, or the session couldn't be verified (auth outage) |

What each action does:

- **`link_token`** calls `POST /link/token/create` with `client_name: "Haki"`,
  `user.client_user_id` set to the user id, `products: ["investments"]`,
  `country_codes: ["US"]` and `language: "en"`. It adds `redirect_uri` only when
  `PLAID_REDIRECT_URI` is set.
- **`exchange`**:
  1. Calls `/item/public_token/exchange`.
  2. If the institution id or name is missing, looks it up with `/item/get` and
     `/institutions/get_by_id` (best effort).
  3. Looks for a duplicate. Linking the same login again (for example after
     the app stopped waiting on a slow first sync) gives a new Item with new
     item and account ids. So when the caller already has a connection with
     the same `institution_id`, it calls `/accounts/get` on the new Item and
     compares each account's type, subtype, mask and name with that
     connection's stored `investment_accounts`. Accounts without a mask are
     never matched. Best effort: any failure here skips the check.
  4. Inserts `plaid_items` and `brokerage_connections`. If either insert fails,
     it removes the new item at Plaid so it isn't left orphaned.
  5. Replaces duplicates. Every matching older connection is revoked at Plaid
     and deleted (cascading to its accounts, holdings and transactions), so
     no holding is counted twice. The newest link wins because it has fresh
     credentials. This runs before the first sync, so it still happens if the
     app gives up waiting. A failure is logged and doesn't fail the request.
  6. Syncs the new connection and refreshes today's snapshot.

  If the first sync hits an item error, the connection is still created (with
  `needs_attention`) and the response is still 200, with zero counts.
- **`sync`** runs the steps below for each of the caller's connections (or only
  `connection_id`), one at a time:
  1. **Holdings.** Calls `/investments/holdings/get`.
     - Upserts `investment_accounts` (conflict `plaid_account_id`) for accounts
       that have holdings or are type `investment`.
     - Upserts `holdings` (conflict `account_id,security_id`). Ticker, name and
       type come from the joined security. `institution_price` becomes `price`,
       `institution_price_as_of` becomes `price_as_of`, `institution_value`
       becomes `value`, and `iso_currency_code` becomes `currency`. Two lots of
       the same security in one account are merged into one row.
     - Deletes this connection's holdings that Plaid no longer reports.
  2. **Transactions.** Calls `/investments/transactions/get` for the last 90
     days, paging with `options.count = 500` and `options.offset` until all are
     fetched. Upserts `investment_transactions` (conflict
     `plaid_transaction_id`). `PRODUCT_NOT_READY` (normal right after linking)
     is skipped without failing. The same applies to holdings.
  3. **Status.** On success the connection gets `status = 'active'`,
     `error_message = null` and `last_synced_at = now()`. On failure it gets a
     readable `error_message`, and the sync moves on to the next connection:
     - Item errors (`ITEM_LOGIN_REQUIRED`, `INVALID_ACCESS_TOKEN`,
       `NO_INVESTMENT_ACCOUNTS`, …) set `needs_attention`. The app has no Plaid
       update mode, so the message tells the user to remove the connection and
       connect it again.
     - Transient errors (institution down, rate limit, network, our own
       database errors) set `error`.
     - If Plaid rejects the server's own keys (`INVALID_API_KEYS`,
       `UNAUTHORIZED_ENVIRONMENT`), the whole request fails with
       `503 plaid_not_configured` and connection statuses are left alone.
  4. **Snapshot.** Finally upserts today's `portfolio_snapshots` row:
     - `total_value` is the sum of the user's holdings `value`.
     - `cost_basis` is the "Invested" amount the app charts against it.
       Holdings with a usable cost basis (`cost_basis > 0` and `value > 0`)
       count at their cost basis. Every other holding (cash, many funds,
       transferred-in lots) counts at its current value. That way the gap
       between the two lines is exactly the gain on holdings that report what
       was paid, the same gain the app's summary card shows. If no holding
       reports a usable cost basis, `cost_basis` is null.

     The date is the US Eastern (market) day, so evening syncs in the US don't
     land on tomorrow. If the user has no holdings stored, today's row is
     deleted instead, so the chart never shows a fake zero. A snapshot failure
     is logged and never fails the request.

  `connections` in the response is the number of connections attempted. Check
  each connection's `status` to see which ones succeeded.
- **`remove`**:
  1. Calls Plaid `/item/remove` (best effort; skipped if Plaid isn't
     configured).
  2. Deletes the `plaid_items` row. This cascades to the connection, its
     accounts, holdings and transactions.
  3. Refreshes today's snapshot.

  `remove` works even without Plaid keys.

## `delete-account`

`POST {}` or `POST {"apple_authorization_code": String}` returns
`{"deleted": true}`. Anything else in the body is ignored. A missing or
malformed body is never an error.

`apple_authorization_code` is a **fresh** Sign in with Apple authorization
code: the UTF-8 string of `ASAuthorizationAppleIDCredential.authorizationCode`.
The app gets it from a new `ASAuthorizationAppleIDProvider` request just before
it deletes an account that has an `apple` identity. Apple's codes are
single-use and expire after about five minutes, so one saved at sign-in won't
work. If the user cancels the Apple sheet, the app should still delete, just
without the code.

The function deletes the caller's account and all of their data, in this order:

0. **Apple token.** Only when a code was sent, the account has an `apple`
   identity and the `APPLE_*` secrets are set. It builds an ES256
   `client_secret` JWT and exchanges the code at
   `https://appleid.apple.com/auth/token`. This happens first, while the code
   is still fresh. If the token's Apple ID isn't the one linked to the account,
   it doesn't revoke anything.
1. **Plaid items.** Calls `/item/remove` for every Plaid item (best effort;
   skipped without Plaid keys), then deletes the user's `plaid_items` rows
   (cascades to all brokerage data).
2. **Storage.** Deletes every object under `<user id>/` in the `avatars` and
   `post-images` buckets. Files are listed with the service-role client,
   paginated and including sub-folders, then removed in chunks.
3. **Apple revoke.** Posts the refresh token (or the access token if Apple
   returned no refresh token) to `https://appleid.apple.com/auth/revoke`. This
   removes Haki from the user's Sign in with Apple apps, which App Review
   expects (guideline 5.1.1(v)). Steps 0 and 3 are best effort. Apple errors,
   timeouts, a missing code and missing secrets are logged (the outcome and
   HTTP status only, never codes, tokens or keys) and never block deletion.
4. **Auth user.** Calls `auth.admin.deleteUser(uid)`. The profile, posts, likes,
   comments, follows and snapshots cascade from it.

If step 2 or 4 fails, the request returns `500 server_error` and the account
still exists, so the user can retry with a new Apple code. The function works
without any Plaid or Apple secrets.
Error codes: `unauthorized`, `bad_request` (non-POST), `server_error`.

## Secrets

Supabase provides these automatically to deployed functions:
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

Set these yourself:

| Secret | Required | Notes |
|---|---|---|
| `PLAID_CLIENT_ID` | for brokerage features | From the Plaid Dashboard → Developers → Keys |
| `PLAID_SECRET` | for brokerage features | Use the secret for the environment in `PLAID_ENV` (sandbox and production secrets differ) |
| `PLAID_ENV` | no | `sandbox` (default) or `production`. It selects `https://sandbox.plaid.com` or `https://production.plaid.com`. |
| `PLAID_REDIRECT_URI` | no | Only for OAuth institutions using a universal link. It must also be listed under Allowed redirect URIs in the Plaid Dashboard. |
| `APPLE_TEAM_ID` | to revoke Sign in with Apple | Your Apple Developer Team ID |
| `APPLE_KEY_ID` | to revoke Sign in with Apple | The Key ID of a key with **Sign in with Apple** enabled for the app's App ID (Certificates, Identifiers & Profiles → Keys) |
| `APPLE_PRIVATE_KEY` | to revoke Sign in with Apple | That key's `.p8` file contents (PKCS#8 PEM). Real or `\n`-escaped line breaks both work. |
| `APPLE_CLIENT_ID` | to revoke Sign in with Apple | The app's **bundle ID** (currently `justin.Haki`), not a Services ID. Native sign-in codes are issued to the bundle ID. |

Without the Plaid keys, `plaid` answers `503 plaid_not_configured` (except
`remove`), and `delete-account` still works. Without the four `APPLE_*`
secrets, `delete-account` still deletes the account but logs a warning and
can't revoke Sign in with Apple.

## Deploy with the Supabase CLI

From the repository root:

```sh
supabase login
supabase link --project-ref bixzpnxadghxuvgckksx   # once per checkout

supabase secrets set PLAID_CLIENT_ID=your-client-id PLAID_SECRET=your-sandbox-secret PLAID_ENV=sandbox
supabase secrets set APPLE_TEAM_ID=your-team-id APPLE_KEY_ID=your-key-id APPLE_CLIENT_ID=justin.Haki
supabase secrets set APPLE_PRIVATE_KEY="$(cat AuthKey_YOURKEYID.p8)"
# optional:
# supabase secrets set PLAID_REDIRECT_URI=https://your.domain/plaid-oauth

supabase functions deploy plaid
supabase functions deploy delete-account
```

Deployment notes:

- Without `supabase link`, add `--project-ref bixzpnxadghxuvgckksx` to each
  command.
- If the CLI asks for `supabase/config.toml`, run `supabase init` once at the
  repo root. It doesn't touch `migrations/` or `functions/`.
- JWT verification at the gateway can stay on (the default). The functions also
  verify the caller themselves, so `--no-verify-jwt` is safe if the gateway
  check ever gets in the way (for example, with new asymmetric signing keys).
- Changing secrets takes effect on the next invocation; you don't need to
  redeploy.

The app calls the functions through `Backend.client.functions` (supabase-swift),
which sends the signed-in user's access token automatically.

## Local testing

```sh
# supabase/functions/.env.local — never commit this file
# PLAID_CLIENT_ID=...
# PLAID_SECRET=...
# PLAID_ENV=sandbox

supabase start
supabase functions serve --env-file supabase/functions/.env.local

curl -i -X POST http://127.0.0.1:54321/functions/v1/plaid \
  -H "Authorization: Bearer $USER_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"link_token"}'
```

Plaid sandbox tips:

- **Link.** Sign in with `user_good` / `pass_good`.
- **Without the app.** Get a public token from `POST
  https://sandbox.plaid.com/sandbox/public_token/create` with `institution_id`
  (for example `ins_109508`) and `initial_products: ["investments"]`. Then call
  `{"action":"exchange","public_token":"..."}`.
- **Trigger `needs_attention`.** Call `/sandbox/item/reset_login` on an item,
  then run `{"action":"sync"}`.

Type-check without deploying (Deno 2):

```sh
deno check supabase/functions/plaid/index.ts supabase/functions/delete-account/index.ts
```
