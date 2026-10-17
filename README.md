# Ledger

Your own personal finance tracker, on your own computer. One SQLite file holds everything, and you use it
from a web app, an iPhone app with home-screen widgets, or an AI assistant (Claude, ChatGPT) over MCP.
Single user, no cloud account, no subscription, two npm dependencies.

## What it does

- **Transactions** across any number of accounts and currencies (non-USD rows are converted at that day's
  ECB rate), with categories, soft deletes, and a **Review** queue for anything an assistant or a bank alert
  wrote.
- **Budgets** per category plus an overall monthly limit, each one opening onto the spending behind it.
- **Net worth**: balances grouped Banking, Cards, Cash and People, reconciled against balances you record.
- **Receipts**: photos from the phone or the web app, optionally read into line items, which feed
  **Item Prices**: what you paid for each item over time.
- **iPhone app**: home, statistics, log spending (also from Siri, Shortcuts and a widget), receipts, item
  prices, accounts; widgets for spending, budgets and recent transactions; Face ID lock.
- **Assistants**: 25 MCP tools so Claude or ChatGPT can read your ledger and log for you.

## What you need

| | |
|---|---|
| A computer that stays on | macOS, Linux or Windows, with Node.js 22.5 or newer |
| [Tailscale](https://tailscale.com) (free) | on that computer and on your iPhone, in the same tailnet. It is how the iPhone reaches your server, and the only login the iPhone needs |
| For the iPhone app | an iPhone, a free Apple ID, and a Mac, a Linux machine or Windows with WSL to build it on ([docs/ios.md](docs/ios.md)) |

Nothing is reachable from the internet unless you choose to publish the optional MCP server.

## Set it up with an agent (recommended)

Clone it, open the folder in Claude Code (or Codex, Cursor, any agent that reads `AGENTS.md`) and ask it to
set Ledger up. `AGENTS.md` walks it through five stages and checks each one before the next:

1. **The server**: installs and starts it, started again at every sign-in.
2. **Tailscale**: publishes the iPhone API on your tailnet, and nowhere else.
3. **First setup**: asks for your accounts, today's balances and your budgets, writes them, and reads them
   back to you.
4. **The iPhone app**: points it at your server, builds it, and installs it with your Apple ID.
5. **Extras**: only the ones you want (docs/extras.md).

It never prints your tokens and never commits your data. `node scripts/doctor.cjs` shows where things stand
at any point.

## Set it up by hand

    git clone https://github.com/saiteja007-mv/ledger.git
    cd ledger
    node scripts/install.cjs                                 # server in the background, started at sign-in
    node scripts/setup.cjs example > .data/setup-plan.json   # edit it: your accounts and budgets
    node scripts/setup.cjs apply .data/setup-plan.json
    node scripts/doctor.cjs                                  # what's working and what isn't, with fixes

`install.cjs` runs the web app and the iPhone API with launchd on macOS, systemd user services on Linux and a
hidden start-up script on Windows. `--mcp` adds the MCP server, `--uninstall` removes it all and keeps your
data, and a port that's taken can be changed once, e.g. `LEDGER_API_PORT=18098 node scripts/install.cjs`.

Then the iPhone app: [docs/ios.md](docs/ios.md). Extras (assistants over MCP, receipt reading, bank alerts,
logos, currencies): [docs/extras.md](docs/extras.md).

## Day to day

- **Web app**: `http://127.0.0.1:42832` on the server; sign in with the token in `.data/web-token.txt`.
- **iPhone**: Tailscale on, then Ledger. With a free Apple ID, re-install every 7 days
  (`bash scripts/ios-install.sh`); your data is on the server, so nothing is lost when it lapses.
- **Update**: `git pull`, then `node scripts/install.cjs`.
- **Back up**: `.data/` is everything (database, receipt photos, tokens). Copy the whole folder.
- **Check**: `node scripts/doctor.cjs`.
- **Remove**: `node scripts/install.cjs --uninstall` (keeps `.data/`).
- **Run in the foreground** while working on it: `node web/index.cjs`, `node web/api.cjs`,
  `node server/index.cjs`. Each generates its token in `.data/` on first start and prints where.

## Repository layout

| | |
|---|---|
| `server/` | the database and money rules (`db.cjs`), the MCP server, categories, reconciliation, bills, FX, logos, net worth |
| `web/` | the web app (`index.cjs`, `public/index.html`) and the iPhone API (`api.cjs`) |
| `ios/` | the iPhone app and widgets (SwiftUI, built with xtool) |
| `scripts/` | install, doctor, first setup, iPhone config and build, importers |
| `docs/` | the iPhone app, the extras, the iPhone API |
| `test/` | `npm test` |

## Architecture

Three front doors over one SQLite file:

| | MCP server | Web UI | iPhone API |
|---|---|---|---|
| Entry point | `server/index.cjs` | `web/index.cjs` | `web/api.cjs` |
| Default port | `localhost:42820` | `localhost:42832` | `localhost:8098`, tailnet `:8448` |
| Auth | bearer token | token → signed session cookie | tailnet membership |
| Serves | `/mcp` and `/healthz`, nothing else | the app + its REST API | one route per MCP tool ([docs/api.md](docs/api.md)) |

All three go through the same `server/db.cjs`, so the money rules live in exactly one place.
**DB:** `.data/finance.sqlite` (gitignored — never commit). Several processes open it, so
`db.cjs` sets `busy_timeout` alongside WAL.

## Auth — separate tokens per door

**MCP:** single bearer token at `.data/api-token.txt` (or `FINANCE_TOKEN` env), granting all
25 tools. Send as `Authorization: Bearer <token>`. A `?token=` query fallback is also accepted
because the Claude/ChatGPT connector dialogs have no header field and a
single URL is the only way to configure them — it is strictly worse than a header, since URLs
land in proxy logs, browser history and screenshots. Prefer the header wherever the client
allows one.

**Web:** separate token at `.data/web-token.txt` (or `FINANCE_WEB_TOKEN` env), exchanged at
sign-in for an HMAC-signed HttpOnly cookie good for 30 days. Separate on purpose: it gets
pasted into a phone browser, so it must be revocable without breaking the ChatGPT connector.
The signing key is derived from the token, so rewriting `web-token.txt` invalidates every
existing session.

A read/write token split was built and then removed: both tokens lived in the same `.data/`
dir and were pasted into the same class of cloud connector, so the split only defended
"read client compromised, write client not" while doubling the secrets to manage. A leaked
read token is arguably the worse outcome anyway (it exposes every transaction), and writes
are soft-deleted and audited. If you ever expose this to someone other than yourself,
reinstate the split — the plumbing is a small diff in `mcp.mjs`.

## Design rules

1. **Money is integer cents.** The source export contains `79.34999999999999`.
2. **Every write is an idempotent upsert** on `external_id` =
   `sha256(account|posted_at|amount_cents|currency|direction)`. The full timestamp is in the
   key because the history has 8 legitimate same-day, same-amount repeats that a date-only
   key would silently merge.
3. **Amounts are always positive**; `direction` carries the sign.
4. **Transfers are excluded** from income/expense totals.
5. **Soft delete only** (`voided_at`).
6. **Imported history is `reviewed=1`; LLM-written rows are not** — see `review_queue`.
7. **No raw-SQL / execute tool.**

## Web UI

Cal.com design system, single self-contained `web/public/index.html` — no build step, no
framework, no dependencies. Views: Overview, Transactions, Receipts, Review, Categories,
Budgets (per category plus an overall monthly limit), Prices, Accounts.

Everything the MCP tools can do, the UI can do, plus the two things chat is bad at:

- **Receipt images.** MCP `add_receipt` stores structured fields only; the UI uploads the
  actual photo (`capture="environment"` opens the phone camera). Files are content-addressed
  as `sha256.ext` under `.data/receipts/`, so re-uploading the same photo overwrites itself
  rather than accumulating copies, and an abandoned form leaves at most one orphan. Uploads
  POST raw bytes — a `Buffer` write instead of a multipart parser and a dependency.

  Three entry points:
  1. **Receipts tab** — photo first, then type the fields; auto-matches to a transaction
     within 3 days and 2%.
  2. **Any transaction's detail sheet** — `Add receipt photo`; merchant, date and total are
     prefilled from the row, so it is one tap.
  3. **The Add transaction sheet** — pick a photo while entering the expense. The file is
     held client-side until the transaction exists, because a receipt needs a `transaction_id`
     to attach to; `upsertTransactions` therefore returns `ids` (and the same id on a repeat
     upsert, so a re-submit attaches to the existing row instead of a phantom one). If the
     upload fails the transaction is still saved, and the toast says exactly that.

  Because the receipt natural key is `merchant|purchased_at|total`, photographing the same
  purchase twice collides — so `addReceipt`'s conflict clause updates `image_path` too
  (COALESCE'd, so an MCP call that sends no image can't wipe an existing one). Retaking a
  photo replaces it instead of silently keeping the first.
- **The review queue.** `mark_reviewed` must never be called on the user's behalf by an LLM;
  that flag exists precisely because an LLM transcribed the row. Confirming rows one at a
  time in chat is miserable, so the UI gives it checkboxes and a bulk confirm.

## Receipts over MCP — 25 tools

Any connected agent can pull receipts, including the photo itself:

| Tool | Returns |
|---|---|
| `list_receipts` | All receipts newest-first; `unattached_only` finds ones not linked to a transaction |
| `get_receipt` | One receipt plus the transaction it is attached to |
| `get_receipt_image` | **The photo, as an MCP image content block** — a vision-capable agent reads the original instead of trusting transcribed fields |
| `set_receipt_items` | Replace a receipt's line items after reading its photo — web uploads have a photo but no items until someone reads them. Write weighed produce as `"Red onion — 3.53 lb @ $0.59/lb"` and pack sizes as `"Rice 20 lb"` so a per-unit price is derived |
| `item_prices` | **Price tracking** — every item seen on receipts, grouped by normalised name + unit, with purchase count, min/avg/max unit price, latest price and % change vs the previous buy |
| `item_price_history` | Every purchase of one item, oldest first — the series behind the Prices trend chart in the web UI |

`has_image` is computed from the filesystem, not from `image_path`. `add_receipt` accepts an
`image_path` with nothing behind it, so the column alone is not proof a photo exists;
`get_receipt_image` says which of the two cases it hit rather than a bare "not found".

Photos are **downscaled before returning** (`convert`, longest edge 1200px default, q72,
`-auto-orient` for EXIF rotation). A 4.6 MB phone photo comes back at ~90 KB — 50× smaller and
still fully legible — because base64 of a raw photo would consume an agent's context for one
receipt. Without ImageMagick, oversized images are refused rather than shipped raw. PDFs return
a clear error instead of a broken image block.

### Categories

There is no categories table. `GET /api/categories` returns a **union**: every category the
ledger actually uses (with count, spend, income, last-used, budget) plus the standard set from
`categorize.cjs` `DEFAULT_RULES`, flagged `standard` / `in_use`. A category becomes real the
moment it is assigned to a row.

Every category field in the UI is a `<select>` over that union with a trailing
`＋ New category…` option. Free text was the obvious first choice and the wrong one: typing
"Groceries" once and "groceries" the next time creates two categories that never add up.

`renameCategory` bulk-moves a whole category (audited, soft — only the label changes). It
exists because 47% of the imported history sits in `Other`, and the live data may carry
`rent` alongside the standard `Rent`. The display label `(uncategorized)` maps back to
`NULL` on the way in, so renaming it works.

Editable fields are exactly those NOT in the `external_id` key — category, subcategory,
merchant, note. Amount, date, account and direction are the natural key; changing one would
orphan the row from every future re-sync. Correct those by voiding and re-adding.

Images live beside whichever DB is in use, so `FINANCE_DB=/tmp/copy.sqlite` keeps a test
run's uploads out of the real `.data/receipts/`.

## Import

    node scripts/import-xlsx.cjs <export.xlsx> [--dry-run]

Reads columns POSITIONALLY: the export has two columns both named `Accounts` (B and K); K
duplicates the amount. Header-keyed reading silently treats amounts as account names.

## Verify

    npm test                     # every server test, on a throwaway database
    bash scripts/ios-build.sh    # the iPhone app, plus its logic checks

Bank of America alerts, assistants over MCP, receipt reading and the rest are in
[docs/extras.md](docs/extras.md).
