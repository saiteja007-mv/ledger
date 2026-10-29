# Inventory and Shopping List: design

Status: approved in chat on 2026-10-29. Calls marked *(builder's call)* were made by the designer, not the owner.

## Why

Ledger already knows what you buy: every itemised receipt is stored line by line in `receipt_items`
(name, normalised `item_key`, `qty`, `unit`, unit price, merchant, `purchased_at`), and the Item Prices
screen charts what each item cost over time. It does not know what you still have, how fast you use it,
or what to buy next. This feature answers three questions from data Ledger already has:

1. **What do I have?** Quantity left from the latest purchase of each consumable.
2. **How fast do I use it?** How long one unit usually lasts, and how far through the current one you are.
3. **What should I buy?** A shopping list that keeps itself up to date, with a price hint per item.

## Goals

- Inventory derived from receipts with almost no typing. The only routine input is one tap, **Used up**.
- A Shopping List that Claude maintains on the server, with the owner able to add, remove and tick items.
- The same data through MCP, so Claude/ChatGPT can ask "what's running low?" or say "I finished the milk".
- Works in the public repo without an API key (rule-based list), so friends who self-host are not blocked.

## Non-goals

- Barcode scanning, manual stock counts with +/- buttons, expiry dates, per-location storage.
- Durable goods (electronics, clothes, furniture). Consumables only.
- A "Running low" strip on the Wallet page (offered, not chosen).
- Ordering groceries or sending the list anywhere.

## Anti-goals (would be a failure even if it works)

- The AI deletes or overwrites an item the owner added by hand.
- Account names, card digits or transaction notes are sent to Anthropic.
- The list fills with one-off purchases (a TV, a gift) or keeps re-adding something the owner dismissed.
- The API key is printed, logged, committed or returned by any endpoint.

## Where it lives (owner's decision)

| Surface | Placement |
|---|---|
| iPhone app | More menu, Ledger section: **Inventory** directly under **Item Prices**, then **Shopping List** under Inventory |
| Web app | Two new More views after **Prices**: **Inventory** and **Shopping List** |
| MCP / iPhone API | New tools below; `web/api.cjs` exposes every MCP tool as `POST /api/tool/<name>`, so the iPhone gets them with no extra routes |

Each Inventory item links to its existing price history screen.

## What counts as a consumable

Categories are free text and receipts can be unattached, so category is not used. *(builder's call)*

- A `(item_key, unit)` pair is **tracked automatically once it has been bought on 2 or more distinct dates.**
  Rebuying is what separates milk from a TV.
- A per-item **Track / Don't track** override wins over the rule (track something bought once; hide a gift
  bought twice).
- Lines that are not products never count: total ≤ 0 (discounts, coupons) and names matching a short
  stop list (tax, fee, deposit, bag, tip, service charge). Purchases with no `purchased_at` are skipped;
  same-day purchases of one item merge into one. *(builder's call)*
- Not-tracked items (switched off, bought once, lapsed) stay visible in a collapsed **Not tracked**
  section so they can be switched on. *(builder's call)*

## How usage is estimated

Pure function in a new `server/inventory.cjs`, unit-tested. Per tracked `(item_key, unit)`:

1. Purchases `p_1 … p_n` ordered by date, each with date `t_i` and quantity `q_i` (packs, or weight for
   weighed produce, exactly as `receipt_items` stores it).
2. A cycle ends at `e_i` = the first **Used up** event after `t_i` and before `t_{i+1}`; if there is none,
   `e_i = t_{i+1}` (the rebuy date).
3. Days per unit for that cycle: `d_i = (e_i − t_i) / q_i` *(builder's call: per unit, so 2 gallons last
   twice as long as 1)*.
4. Typical days per unit `L` = median of `d_i` over the last 6 completed cycles. Cycles closed by a
   Used up tap are real; rebuy-closed ones are the estimate.
5. Current state from the latest purchase `t_n, q_n` and today:
   - Used up recorded after `t_n` → **used up**, nothing left.
   - No completed cycle yet → **learning** (show bought date and qty only).
   - Otherwise expected life `E = q_n × L`, elapsed `a = today − t_n`,
     `used = min(1, a / E)`, `days_left = max(0, E − a)`, `qty_left = q_n × (1 − used)`.
6. Status: **running low** when `used ≥ 0.8` or `days_left ≤ 2`; **in stock** otherwise
   *(builder's call on the cut-offs)*.
7. **Lapsed:** no rebuy and no Used up for longer than `3 × E` (and at least 30 days) → the owner probably
   stopped buying it or switched brands. Lapsed items leave the list and the tracked sections and show
   under Not tracked until bought again. *(builder's call)*

Each item returns: `item_key, unit, name, tracked (auto|on|off), status, last_bought, last_qty, qty_left,
used_pct, days_left, lasts_days (= L × last_qty), cycles, last_price, cheapest_merchant`.

## Shopping List

### Rules (always on, and the whole list when there is no API key)

An open list item is suggested for every tracked, non-lapsed item that is **used up**, **running low**,
or has `days_left ≤ 3`.

**Suppression (nothing comes straight back without new information)** *(builder's call)*: once an item
is closed as **bought** (tick or receipt), **dismissed** by the owner, or **removed** by the AI, neither
the rules nor the AI re-add that `item_key` until something new happens to it: a receipt line dated after
the close, or a Used up tap after the close. A tick with no receipt counts as a restock of the last
purchase quantity for the estimator, so the item reads "in stock" again instead of "used up".

### AI upkeep (owner's decision: Claude API with a key file)

- **Key:** read at run time from the file named by `LEDGER_ANTHROPIC_KEY_FILE`, default
  `.data/anthropic-key.txt` (owner-only, git-ignored like the other `.data` token files). Never logged or
  returned. No file → rules only, and the list says so.
- **Client:** official `@anthropic-ai/sdk` (new dependency). Model `claude-opus-5-5`, effort `low`,
  structured output (`output_config.format` JSON schema), server-side refusal fallback
  (`fallbacks: "default"`) *(builder's call; per the Claude API skill's defaults)*.
- **When and where:** only the `ledger-web` process ever calls Claude *(builder's call)*. A timer there
  checks once a minute (one cheap SQL read) for either a **refresh requested** marker or a change in
  `receipt_items` / Used up events since the last run, and also runs once a day at 06:00 local. The MCP
  server, the iPhone API and the web app never call Claude themselves: `refresh_shopping_list` (and the
  web/iPhone "Update now" button) only set the marker and return at once with `queued`; the list shows
  "Updating…" until the run finishes. A lock row in SQLite stops two runs overlapping. Each run has a
  2-minute timeout.
- **Input:** today's date, the inventory rows above, the last 90 days of purchases of tracked items
  (item, qty, unit, unit price, merchant, date) and the current open list including the owner's items.
- **Output (schema):** `add[] {item_key|null, name, qty, unit, reason}`, `update[] {id, qty, reason}`,
  `remove[] {id, reason}`. The server applies it and **refuses** to remove or change `source = 'user'`
  items or re-add dismissed ones.
- **Failure:** any API error, refusal or schema failure leaves the rule-based list in place and records
  the error for display ("Updated by rules: Claude unavailable").
- **Privacy:** only item names, quantities, units, prices, merchants and dates are sent. No account
  names, card digits, transaction notes or receipt photos.

### Owner actions

Add an item (free text, optional qty), tick it as bought, dismiss a suggestion, remove their own item.
When a new receipt line matches an open item's `item_key`, the item closes as **bought** automatically.
A typed name goes through the same normaliser as receipt lines (`parseReceiptLine`) to get an
`item_key`, so it can auto-close from a receipt and is merged with an open rule/AI row for the same key
instead of duplicating it (the owner's row wins). *(builder's call)*

### Price hint (owner's decision)

Per item: latest unit price and the merchant with the lowest unit price over the last 90 days, from the
existing price data. The list shows an estimated total of `qty × latest unit price` over items that have
a price.

## Data

New tables in `server/db.cjs` (same `CREATE TABLE IF NOT EXISTS` style):

```sql
CREATE TABLE IF NOT EXISTS item_settings (
  item_key TEXT NOT NULL, unit TEXT NOT NULL,
  tracked  INTEGER,                         -- NULL = auto (2+ purchases), 1 = on, 0 = off
  PRIMARY KEY (item_key, unit)
);
CREATE TABLE IF NOT EXISTS item_events (
  id INTEGER PRIMARY KEY, item_key TEXT NOT NULL, unit TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind = 'used_up'),
  at   TEXT NOT NULL, actor TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS shopping_list (
  id INTEGER PRIMARY KEY, item_key TEXT, unit TEXT, name TEXT NOT NULL, qty REAL,
  source TEXT NOT NULL CHECK (source IN ('rule','ai','user')),
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','bought','dismissed','removed')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT, closed_at TEXT
);
```

The last AI run (time, ok/error, message), the refresh-requested marker and the run lock live in a small
`shopping_state` table *(builder's call)*. Every new write function calls `audit()` itself: the MCP
`W(...)` wrapper is an alias of `T(...)` and does not audit on its own.

## MCP tools (names are the builder's call)

| Tool | Kind | Purpose |
|---|---|---|
| `inventory` | read | Tracked items with the fields above; filter `status` (`running_low`, `used_up`, …) and `q`; `include_untracked` adds off, bought-once and lapsed items |
| `mark_used_up` | write | `item_key`, optional `unit` (default: the unit bought most recently), optional date (default today) |
| `set_item_tracking` | write | `item_key`, `unit`, `tracked: true / false / null (auto)` |
| `shopping_list` | read | Open items with source, reason, price hint and estimated total, plus last AI run status |
| `update_shopping_list` | write | `add` / `bought` / `dismiss` / `remove` by id or name |
| `refresh_shopping_list` | write | Request a run now: sets the marker and returns `queued` (ledger-web runs it within a minute) |

## iPhone app

- `Route` cases `inventory` and `shoppingList`; More rows under Item Prices with matching icons.
- `InventoryView`: sections Running low, In stock, Used up, Learning, and a collapsed Not tracked. Row: name, qty left + unit, a usage
  bar, "~N days left", "lasts ~X days", and a **Used up** button. Tap → item detail with the price chart
  (reuse `PriceHistoryView`), purchase list and Track / Don't track.
- `ShoppingListView`: open items with reason and price hint, swipe to dismiss/remove, tick to mark
  bought, an add field, the estimated total, and a footer "Updated by Claude 2h ago" or "Rules only".
- Models decode the tool JSON; their pure logic joins `ios/Checks` like the existing models.

## Web app

Two More views styled like Prices, with the same actions as the iPhone.

## Testing

- `test/inventory.test.cjs`: estimator (per-unit lifespans, used-up overrides, learning, lapsed,
  cut-offs, ticks as restocks), tracking rule (non-product lines excluded, same-day merge), list rules
  (suppression after bought/dismissed/AI-removed until new information, user items untouched, typed names
  merged by key), and applying an AI response that tries to remove a user item (must be refused).
- AI path tested with a stubbed client; no test calls the real API.
- `npm test` and `scripts/ios-build.sh` (BUILD OK, LOGIC OK) before any PR.

## Rollout

1. Public repo `saiteja007-mv/ledger`: PRs for server + MCP + web, then iPhone. Scrub rules apply.
2. Owner's install: the finance-mcp agent (ideapad) ports the server and MCP changes into `~/finance-mcp`
   and points `LEDGER_ANTHROPIC_KEY_FILE` at the key file; the iPhone changes go to
   `saiteja007-mv/homelab-ios` (`Ledger/`) and are installed only when the owner says so.

## Open (owner)

- The path of the Claude API key file on ideapad. The code defaults to `.data/anthropic-key.txt`; the
  install only needs the env var set to the real path.

## Left to the builder

View layout details, icons, copy, the exact AI prompt wording, and table/function names beyond those
fixed above.
