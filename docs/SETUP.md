# Setting up Haki's backend

The app talks to the Supabase project **haki** (`https://bixzpnxadghxuvgckksx.supabase.co`). The
database schema, storage buckets and server functions are already deployed. A few settings need
credentials that only you can create, in dashboards only you can sign in to. Until they're done:

- email sign-up works only for the email addresses of your Supabase organization's team members:
  Supabase's built-in sender refuses other addresses ("Email address not authorized") and sends just
  a few emails an hour,
- "Continue with Google" and "Sign in with Apple" show an error,
- "Connect a brokerage" says brokerage connections aren't set up yet,
- the Health tab's meal photo estimates and restaurant menus say AI food features aren't set up yet,
- Ask Haki, clothing auto-tags, outfit ideas and AI flashcards say Haki's AI isn't set up yet.

## 1. Allow the app's redirect URL (2 minutes)

Supabase Dashboard → **Authentication → URL Configuration** → **Redirect URLs** → add:

```
haki://auth-callback
```

Email confirmations, password resets and Google sign-in all return to the app through this URL.

## 2. Google sign-in (about 10 minutes)

1. Go to [Google Cloud Console](https://console.cloud.google.com/) and create a project (or pick an
   existing one).
2. **APIs & Services → OAuth consent screen**: choose *External*, set the app name to **Haki**, add
   your support email, and keep the default scopes (`openid`, `email`, `profile`). While the app is in
   *Testing* mode, add your own Google account under *Test users*.
3. **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - Application type: **Web application**. Supabase does the OAuth exchange on the web, so you
     don't need an iOS client here.
   - Authorized redirect URI:
     ```
     https://bixzpnxadghxuvgckksx.supabase.co/auth/v1/callback
     ```
4. Copy the **Client ID** and **Client secret**.
5. Supabase Dashboard → **Authentication → Sign In / Providers → Google**: enable it and paste both
   values. Save.

## 3. Sign in with Apple (about 10 minutes; needs a paid Apple Developer account)

1. [Apple Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list):
   open (or create) the App ID for the app's bundle identifier. It's currently `justin.Haki`; if you
   want a reverse-DNS identifier such as `com.yourname.haki`, change it in Xcode **before** this step,
   because the bundle ID is permanent once the app is on the App Store. Turn on **Sign in with
   Apple** and save.
2. In Xcode: **Haki target → Signing & Capabilities**, select your team. The *Sign in with Apple*
   capability is already set in `Config/Haki.entitlements`.
3. Supabase Dashboard → **Authentication → Sign In / Providers → Apple**: enable it and enter your
   bundle identifier (e.g. `justin.Haki`) under **Client IDs**. The app signs in natively with an
   identity token, so you don't need a Services ID or secret key.

> Free (personal) Apple teams can't use the Sign in with Apple capability. If Xcode refuses to sign
> for a device, either join the Apple Developer Program or remove the key from
> `Config/Haki.entitlements` for local testing. The Simulator works either way.

## 4. Email sign-up for everyone (needs an email provider)

Email/password is on by default, with **Confirm email** enabled. Supabase's built-in email sender
only delivers to the addresses of your Supabase organization's team members, and only a few
messages per hour. Everyone else gets "Email address not authorized" and can't confirm their
account. Before anyone else signs up with email, set up a custom SMTP provider (for example Resend,
Postmark or Amazon SES) under **Authentication → Emails → SMTP Settings**, then raise the email rate
limit under **Authentication → Rate Limits**. Don't turn off **Confirm email** to work around this:
it would let anyone sign up with an address they don't own.

## 5. Brokerage connections with Plaid (about 5 minutes for Sandbox)

1. [Plaid Dashboard](https://dashboard.plaid.com/) → team **OneLife** → **Developers → Keys**: copy
   the **client_id** and the **Sandbox secret**.
2. Supabase Dashboard → **Edge Functions → Secrets** (or **Project Settings → Edge Functions**) → add:

   | Name | Value |
   |---|---|
   | `PLAID_CLIENT_ID` | your client_id |
   | `PLAID_SECRET` | your Sandbox secret |
   | `PLAID_ENV` | `sandbox` |

   With the [Supabase CLI](https://supabase.com/docs/guides/cli) installed, this also works:

   ```sh
   supabase secrets set --project-ref bixzpnxadghxuvgckksx \
     PLAID_CLIENT_ID=... PLAID_SECRET=... PLAID_ENV=sandbox
   ```
3. Try it: in the app, open **Invest → Connect a brokerage**, pick any Sandbox institution, and log
   in with username `user_good` and password `pass_good`. Holdings show up right after.

**Going live:** request Production access for the **Investments** product in the Plaid Dashboard, then
switch `PLAID_SECRET` to the Production secret and `PLAID_ENV` to `production`. Some brokerages
(for example Schwab and Fidelity) connect through OAuth in Production. Plaid's OAuth guide explains
how to register a redirect URI. Set it as the optional `PLAID_REDIRECT_URI` secret and the server
function will pass it to Plaid.

## 6. AI food features with Claude (about 5 minutes)

Meal estimates and menu lookups run in the `food-ai` Edge Function, which calls the Anthropic API.

1. [Claude Console](https://platform.claude.com/) → **API keys** → create a key (add billing
   first; there's no free tier for the API).
2. Supabase Dashboard → **Edge Functions → Secrets** → add `ANTHROPIC_API_KEY` with that key, or:

   ```sh
   supabase secrets set --project-ref bixzpnxadghxuvgckksx ANTHROPIC_API_KEY=sk-ant-...
   ```
3. Optional secrets:

   | Name | Default | What it does |
   |---|---|---|
   | `FOOD_AI_MODEL` | `claude-opus-5-5` | The Claude model. `claude-sonnet-5-5` costs about half as much; `claude-haiku-5-5` is far cheaper but less accurate on photos and menus. |
   | `FOOD_AI_DAILY_MEALS` | `50` | Meal estimates per person per day (UTC). |
   | `FOOD_AI_DAILY_MENUS` | `15` | New menu lookups per person per day. Cached menus don't count. |

**What it costs (rough, at Claude Opus 5.5's $4 per million input and $20 per million output
tokens):** a meal estimate reads a photo and some instructions (about 2–4 thousand tokens) and
writes 1–3 thousand, so around 3–7 cents. A menu lookup runs web searches (billed per search) and
reads several pages, so expect roughly 10–30 cents — which is why menus are cached and shared for
14 days. Watch real spend in the Claude Console; switching `FOOD_AI_MODEL` to Sonnet roughly halves it. If Claude declines a
request, the function retries it once on Anthropic's recommended fallback model (server-side
fallback) before telling the person.

Restaurant menus come from public web pages and Claude's estimates, and the app labels them that
way. For allergies, people should always check with the restaurant.

### Ask Haki, wardrobe and flashcards (the `haki-ai` function)

The same `ANTHROPIC_API_KEY` secret powers them. Optional secrets:

| Name | Default | What it does |
|---|---|---|
| `HAKI_AI_MODEL` | `claude-opus-5-5` | The Claude model for the assistant, clothing tags, outfit ideas and flashcards. |
| `HAKI_AI_DAILY_CHAT` | `150` | Assistant requests per person per day. One question can take a few requests: each round of on-phone lookups counts. |
| `HAKI_AI_DAILY_CLOTHING` | `60` | Clothing photo auto-tags per day. |
| `HAKI_AI_DAILY_OUTFITS` | `20` | Outfit-idea requests per day. |
| `HAKI_AI_DAILY_FLASHCARDS` | `20` | AI decks made from notes per day. |

Rough costs at Opus 5.5 prices: a simple assistant question is a few cents; one that needs several
lookups or a web search can be 10–20 cents (the conversation prefix is cached between rounds,
which helps). A clothing tag is about 1–2 cents, outfit ideas or a flashcard deck about 3–8 cents.

## 7. Hevy (nothing to set up on the server)

Each person connects their own Hevy account in **Health → Hevy** with an API key from
[hevy.com → Settings → Developer](https://hevy.com/settings?developer) (needs Hevy Pro). The key is
stored in the iPhone's Keychain and the app talks to Hevy directly. Haki isn't affiliated with Hevy.

## Good to know

- **Free plan pausing:** Supabase pauses free projects after a week without activity. Restore it
  from the dashboard if the app suddenly can't sign in.
- **Privacy model:** money data (transactions, budgets, accounts), the food log, workouts, the
  wardrobe, notes, flashcards and assistant chats stay on the device in SwiftData. Meal and clothing
  photos, note text sent for flashcards, and the answers to the assistant's lookups are sent through
  Haki's functions to Anthropic to be processed, and aren't stored by Haki.
  The server stores profiles, posts and brokerage holdings. Other users only ever see your
  portfolio as **percentages**, and only while *Share portfolio percentages* is on.
- **Account deletion** (required by the App Store) is in **Profile → Settings → Delete account**. It
  removes the account, posts, images and brokerage connections from the server. Public images can
  stay in the storage CDN's cache for up to an hour after they're deleted. Their URLs contain random
  IDs, so they can't be guessed.
