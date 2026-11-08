# Haki

Haki is a personal-finance, social, investing and health app for iPhone, built with SwiftUI,
SwiftData, Swift Charts, MapKit and Supabase. It shows where your money goes each month, keeps a
review queue for new transactions, and tracks category budgets, recurring bills and net worth. It
connects your brokerage read-only through Plaid and lets you share posts, trades and portfolio
**percentages** with people you follow. Its Health tab estimates calories and protein from a photo
of your meal, finds healthy options on nearby menus, and logs strength workouts (with optional
Hevy sync).

Money, food and workout data stay on the device. Your profile, posts and brokerage holdings live in
your Haki account (Supabase). Sign in with Google, Apple or email.

## Features

The app has five tabs: **Home**, **Feed**, **Invest**, **Health** and **Profile**.

- **Home**: spending this month compared with last month as a running total, budget left, a review
  queue, upcoming bills, net worth, investments and cash flow. Shortcuts open **Transactions**,
  **Budgets**, **Recurring** and **Accounts**.
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
- **Health — food**: snap or pick a photo of a meal (or describe it) and Haki's AI estimates each
  item's calories, protein, carbs and fat for you to adjust and log. A daily log by meal, calorie
  and protein goals (suggested from your height, weight, age, activity and goal), streaks and
  "log again".
- **Health — eat nearby**: search restaurants, cafés and grocery stores on a map; open one to see its
  menu with prices, calories and protein (published where available, otherwise estimated),
  filters (high protein, under 600 kcal, under $15, vegetarian…), sorts (healthiest, protein per
  calorie or per dollar) and best picks for the calories you have left. Log a dish in one tap.
- **Health — workouts**: log sets, reps and weight with the previous session alongside, a rest
  timer, PR detection, routines, exercise history and weekly progress. Connect a **Hevy** account
  (Hevy Pro API key) to bring your Hevy workouts in and post workouts logged in Haki to Hevy.
- **Profile**: your posts grid, followers and following, your shared portfolio (percentages), edit
  profile, settings, sign out and delete account.

## Project layout

```
Haki/
  HakiApp.swift, ContentView.swift   App entry point and tab bar (RootView)
  App/            Cross-tab navigation (AppRouter)
  Core/           Pure Foundation logic: money, dates, analytics, merchant names,
                  categorization, recurring detection, CSV import, net worth, sample data,
                  nutrition targets, menu ranking, exercise library, workout math, Hevy JSON
  Models/         SwiftData models
  Data/           LedgerStore, FoodStore, WorkoutStore (all database writes), health
                  settings and preview data
  DesignSystem/   Theme and shared views
  Services/       Supabase client, models, AuthService, SocialService, PortfolioService,
                  FoodAIService, HevySyncService (+ Hevy client and Keychain)
  Features/       Overview (Home), Transactions, Budgets, Recurring, Accounts, Settings,
                  Auth, Social (Feed), Profile, Invest, Health, Food, Places, Workouts, Hevy
Config/           Entitlements (Sign in with Apple) and Info.plist additions (haki:// URL scheme,
                  camera and location usage text)
supabase/         Database migrations and Edge Functions (plaid, delete-account, food-ai)
Tests/CoreTests/  Unit tests for Haki/Core
scripts/          test-core.sh (runs the tests), assets/make_icon.py (app icon)
docs/SETUP.md     Backend setup: Google, Apple, email, Plaid, Anthropic (food AI)
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
- Database writes go through `LedgerStore` (money), `FoodStore` and `WorkoutStore`. They insert
  models before setting relationships, keep merchant keys and balance history in sync, and apply
  categorization rules on import. Workout weights are stored in kilograms and shown in the
  person's unit.
- Models keep every stored property defaulted and avoid unique constraints, so the schema stays
  compatible with iCloud sync.
- Services (`AuthService`, `SocialService`, `PortfolioService`, `FoodAIService`,
  `HevySyncService`) are `@Observable` objects in the environment. Their `.preview` instances use sample data and never touch the network, so SwiftUI
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

The Supabase project **haki** hosts auth, the social database, image storage and three Edge Functions:

- `plaid` creates Link tokens, exchanges public tokens, syncs holdings and trades, and removes
  connections.
- `delete-account` deletes the account and all of its server data.
- `food-ai` calls Claude (Anthropic API) to estimate a meal's nutrition from a photo or
  description, and to research a restaurant's menu with web search (then turn it into structured
  items with prices, calories, protein and health tags). Menus are cached for 14 days and shared;
  each account has a daily limit (50 meal estimates, 15 new menu lookups). Meal photos aren't
  stored on the server.

Hevy sync runs on the device: the app calls Hevy's API directly with the person's own API key,
kept in the Keychain, so workouts never pass through Haki's servers.

Plaid and Anthropic keys live only in Edge Function secrets. Row-level security limits every table so that people
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
