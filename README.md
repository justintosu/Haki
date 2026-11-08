# Haki

Haki is a personal-finance app for iPhone, built with SwiftUI, SwiftData and Swift Charts. It shows
where your money goes each month, keeps a review queue for new transactions, tracks category budgets
and recurring bills, and charts your net worth over time.

Everything is stored on the device. Automatic bank connections aren't built yet. Until then you can
import CSV exports from your bank (or another finance app), enter transactions by hand, or load
sample data to explore.

## Features

- **Overview**: spending this month compared with last month as a running total, budget left, a
  review queue, upcoming bills, net worth and cash flow.
- **Transactions**: grouped by day, searchable, filterable (needs review, excluded, uncategorized, by
  category or account), swipe to review or exclude. Recategorizing a merchant can apply to all of
  its transactions and creates a rule for future imports.
- **Budgets**: monthly budgets per category, pace and month-end projection, six-month history per
  category.
- **Recurring**: tracked bills with this month's paid, upcoming and late status, plus suggestions
  detected from your transaction history.
- **Accounts**: balances grouped by type, and net worth and balance history charts.
- **CSV import**: auto-detects common column layouts (Date / Description / Amount, Debit / Credit,
  Mint-style transaction type), the amount sign convention and date formats. It cleans up merchant
  names, auto-categorizes and skips duplicates.

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
  Features/       One folder per tab, plus Settings & CSV import
Tests/CoreTests/  Unit tests for Haki/Core
scripts/          test-core.sh (runs the tests), assets/make_icon.py (app icon)
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

## Running

Open `Haki.xcodeproj` in Xcode 26.4 or later and run the **Haki** scheme on an iPhone simulator or
device. On first launch, choose **Explore with sample data** to see every screen filled in.

## Tests

The core logic has a dependency-free test suite that runs anywhere a Swift 6.2 toolchain is
installed (macOS or Linux):

```sh
scripts/test-core.sh
```

CI (`.github/workflows/ci.yml`) runs those tests on Linux and builds the app for the iOS Simulator
with Xcode on every push.
