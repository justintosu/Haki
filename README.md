# Haki

Haki is a personal-finance, social and investing app for iPhone, built with SwiftUI, SwiftData,
Swift Charts and Supabase. It shows where your money goes each month, keeps a review queue for new
transactions, and tracks category budgets, recurring bills and net worth. It also connects your
brokerage read-only through Plaid and lets you share posts, trades and portfolio **percentages**
with people you follow.

Money data stays on the device. Your profile, posts and brokerage holdings live in your Haki account
(Supabase). Sign in with Google, Apple or email.

## Features

The app has five tabs: **Home**, **Transactions**, **Feed**, **Invest** and **Profile**.

- **Home**: spending this month compared with last month as a running total, budget left, a review
  queue, upcoming bills, net worth, investments and cash flow. Shortcuts open **Budgets**,
  **Recurring** and **Accounts**.
- **Transactions**: grouped by day, searchable, filterable (needs review, excluded, uncategorized, by
  category or account), swipe to review or exclude. Recategorizing a merchant can apply to all of
  its transactions and creates a rule for future imports.
- **Budgets**: monthly budgets per category, pace, a month-end projection, and six-month history per
  category.
- **Recurring**: tracked bills with this month's paid, upcoming and late status, plus suggestions
  detected from your transaction history.
- **Accounts**: balances grouped by type, and net worth and balance history charts.
- **CSV import**: auto-detects common column layouts, sign conventions and date formats. It cleans
  up merchant names, auto-categorizes and skips duplicates.
- **Feed**: posts from people you follow, or everyone (Explore). Posts can carry photos, cashtags
  ($AAPL) with a "holds this" badge, trades, and portfolio snapshots that contain percentages only.
  Includes likes, comments, activity, people search and ticker feeds.
- **Invest**: connect a brokerage through Plaid (read-only), see holdings, allocation, performance
  history and recent trades, and share your portfolio as percentages.
- **Profile**: your posts grid, followers and following, your shared portfolio (percentages), edit
  profile, settings, sign out and delete account.

## Project layout

```
Haki/
  HakiApp.swift, ContentView.swift   App entry point and tab bar (RootView)
  App/            Cross-tab navigation (AppRouter)
  Core/           Pure Foundation logic: money, dates, analytics, merchant names,
                  categorization, recurring detection, CSV import, net worth, sample data
  Models/         SwiftData models
  Data/           LedgerStore (all database writes) and preview data
  DesignSystem/   Theme and shared views
  Services/       Supabase client, models, AuthService, SocialService, PortfolioService
  Features/       Overview (Home), Transactions, Budgets, Recurring, Accounts, Settings,
                  Auth, Social (Feed), Profile, Invest
Config/           Entitlements (Sign in with Apple) and Info.plist additions (haki:// URL scheme)
supabase/         Database migrations and Edge Functions (plaid, delete-account)
Tests/CoreTests/  Unit tests for Haki/Core
scripts/          test-core.sh (runs the tests), assets/make_icon.py (app icon)
docs/SETUP.md     Backend setup: Google, Apple, email, Plaid
```

`Haki/` is a file-system-synchronized group, so new files you add there are compiled automatically.
Swift file names must be unique across the target.

## Conventions

- **Money** is stored as `Int` cents. **Positive amounts are money out** (purchases); negative
  amounts are money in (income, refunds). This is the same convention Plaid uses, so bank sync can
  be added later without flipping signs.
- **Dates** of transactions are stored at local noon on their calendar day.
- `Haki/Core` must not import SwiftUI or SwiftData. Its types are `nonisolated` so they work from any
  context, and it's compiled and tested on its own.
- Database writes go through `LedgerStore`. It inserts models before setting relationships, keeps
  merchant keys and balance history in sync, and applies categorization rules on import.
- Models keep every stored property defaulted and avoid unique constraints, so the schema stays
  compatible with iCloud sync.
- Services (`AuthService`, `SocialService`, `PortfolioService`) are `@Observable` objects in the
  environment. Their `.preview` instances use sample data and never touch the network, so SwiftUI
  previews work offline (`.previewEnvironment()`).

## Running

Open `Haki.xcodeproj` in Xcode 26.4 or later and run the **Haki** scheme on an iPhone simulator or
device. Xcode fetches the Swift packages (supabase-swift 2.55.6, Plaid LinkKit 7.3.1) on first open.

Email sign-up works right away for the email addresses on your Supabase team. Supabase's built-in
email sender only delivers to those addresses until you add a custom SMTP provider. Google sign-in,
Sign in with Apple, email for everyone else, and brokerage connections each need a one-time setup in
their dashboards; see [docs/SETUP.md](docs/SETUP.md). Once you're signed in, choose **Explore with sample data** on Home to
see the money screens filled in.

## Backend

The Supabase project **haki** hosts auth, the social database, image storage and two Edge Functions:

- `plaid` creates Link tokens, exchanges public tokens, syncs holdings and trades, and removes
  connections.
- `delete-account` deletes the account and all of its server data.

Plaid keys live only in Edge Function secrets. Row-level security limits every table so that people
can read only what they should. Brokerage data is readable only by its owner, and other people see
portfolios only as percentages, through database functions that respect the *Share portfolio*
setting. The schema is in `supabase/migrations/`.

## Tests

The core logic has a dependency-free test suite that runs anywhere a Swift 6.2 toolchain is
installed (macOS or Linux):

```sh
scripts/test-core.sh
```

CI (`.github/workflows/ci.yml`) runs those tests on Linux and builds the app for the iOS Simulator
with Xcode on every push.
