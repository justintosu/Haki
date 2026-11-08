# Setting up Haki's backend

The app talks to the Supabase project **haki** (`https://bixzpnxadghxuvgckksx.supabase.co`). The
database schema, storage buckets and server functions are already deployed. A few settings need
credentials that only you can create, in dashboards only you can sign in to. Until they're done:

- email sign-up works (with Supabase's default, rate-limited email sender),
- "Continue with Google" and "Sign in with Apple" show an error,
- "Connect a brokerage" says brokerage connections aren't set up yet.

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

## 4. Email sign-in (optional tuning)

Email/password is on by default, with **Confirm email** enabled. Supabase's built-in email sender
only allows a few messages per hour. Before real users sign up, set up a custom SMTP provider under
**Authentication → Emails → SMTP Settings**, and edit the templates if you like.

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

## Good to know

- **Free plan pausing:** Supabase pauses free projects after a week without activity. Restore it
  from the dashboard if the app suddenly can't sign in.
- **Privacy model:** money data (transactions, budgets, accounts) stays on the device in SwiftData.
  The server stores profiles, posts and brokerage holdings. Other users only ever see your
  portfolio as **percentages**, and only while *Share portfolio percentages* is on.
- **Account deletion** (required by the App Store) is in **Profile → Settings → Delete account**. It
  removes the account, posts, images and brokerage connections from the server.
