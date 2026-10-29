# Ledger API

The JSON API behind the Ledger iOS app. It runs on your server next to the web app and the
MCP server, and calls the same `server/*.cjs` code they do.

| | |
|---|---|
| URL | `https://<server>.<tailnet>.ts.net:8448/` (tailnet only) |
| Process | `node web/api.cjs`, run in the background by `scripts/install.cjs` (launchd, systemd or the Windows Startup folder) |
| Listens | `127.0.0.1:8098` (`LEDGER_API_PORT`), published with `tailscale serve --bg --https=8448 http://127.0.0.1:8098` |
| Auth | Tailnet membership. The app holds no token or secret |

## Design: one route per MCP tool

The app calls `POST /api/tool/<name>` with the tool's arguments as a JSON object. Every tool in
`server/mcp.mjs` is available under the same name and with the same arguments. Three app-only extras
share the namespace. This gives full parity with the MCP server without re-implementing any of it:

- `api.cjs` builds the MCP server with `buildServer()` from `mcp.mjs` and connects to it in-process
  through the MCP SDK's in-memory transport.
- zod validation, money formatting, the `{amount, amount_cents}` pairs and the ledger rules all come
  from `mcp.mjs` and `db.cjs`.
- A tool added to `mcp.mjs` later appears here after `systemctl --user restart ledger-api`.

REST was the alternative. It would have meant hand-mapping 31 tools to routes and keeping the
two lists in step.

### Requests and answers

```
POST /api/tool/<name>
Content-Type: application/json

{ ...the tool's arguments... }        # {} when there are none
```

| Status | Body |
|---|---|
| 200 | `{"ok": true, "result": <the tool's JSON>}` |
| 400 | `{"ok": false, "error": "Input validation error: ..."}`, or the tool's own error (`no receipt 9`, `need >=2 balance snapshots ...`) |
| 403 | `{"ok": false, "error": "app requests only"}`: an `Origin` header, or not `Content-Type: application/json` |
| 404 | unknown tool or path |
| 405 | a method other than POST on `/api/tool/*` |
| 413 | body too large (1 MB; about 16 MB for `upload_receipt_photo`) |
| 502 | from `tailscale serve`, when `ledger-api` isn't running |

`get_receipt_image` returns its image block as `result.image_base64` and `result.mime_type`. The
image is downscaled to `max_width`, 1200 px by default.

Also available:

- `GET /healthz` returns `{ok, app: "ledger-api", transactions, accounts, receipts, range}`.
- `GET /api/tools` returns `[{name, description, input_schema, extra?}]`, the live list of tools.

## Tools

Money arguments are positive. `direction` carries the sign. Dates are `YYYY-MM-DD`; `posted_at` is
local `YYYY-MM-DDTHH:MM:SS`. Lists come back newest first, except `item_price_history`, which is
oldest first, `inventory`, which is sorted by name, and `shopping_list`, which is in the order items were
added.

| Tool | Arguments (required in bold) | Used by the app for |
|---|---|---|
| `get_status` | | Accounts footer counts |
| `list_accounts` | | (unused; `networth` has better balances) |
| `list_transactions` | from, to (exclusive), account, category, direction, limit (default 100, max 1000; no offset) | Activity, recent rows, an account's rows, the expenses behind a category total (see below) |
| `search_transactions` | **q**, limit | Activity search |
| `spending_summary` | from, to (this month by default) | Home, this month |
| `category_breakdown` | from, to, direction, limit | Home chart |
| `budget_status` | | Home and Budgets |
| `set_budget` | **category**, period, limit or limit_cents | Budgets |
| `list_balances` | account | Account detail |
| `record_balance` | **account**, **as_of_date**, balance or balance_cents, currency | Record Balance |
| `reconcile_account` | **account**, **from**, **to** | Account detail, Reconcile |
| `review_queue` | limit | Review tab and badge |
| `suggest_categories` | limit | Review, suggested category |
| `set_category` | **id**, **category**, subcategory | Detail, Review |
| `mark_reviewed` | **ids** | Detail, Review, and after Log Spending |
| `void_transaction` | **id**, reason | Detail, Review (soft delete) |
| `upsert_transactions` | **items**, source | Log Spending |
| `list_receipts` | limit, unattached_only | Receipts, a transaction's receipts |
| `get_receipt` | **id** | Receipt detail, which polls `bill_status` |
| `get_receipt_image` | **id**, max_width | Receipt detail photo |
| `add_receipt` | merchant, purchased_at, total or total_cents, tax, currency, line_items, transaction_id | (unused; the app uploads photos instead) |
| `set_receipt_items` | **id**, **line_items**, tax | (unused) |
| `item_prices` | q, merchant, limit | Item Prices |
| `item_price_history` | **item_key**, unit | Price history chart |
| `inventory` | q, status, include_untracked | Inventory |
| `mark_used_up` | **item_key**, unit, date | Inventory, Used up |
| `set_item_tracking` | **item_key**, **unit**, **tracked** (true, false or null) | Inventory, Track / Don't track |
| `shopping_list` | | Shopping List |
| `update_shopping_list` | add (`[{name, qty}]`), bought, dismiss, remove (lists of ids) | Shopping List |
| `refresh_shopping_list` | | Shopping List, Update now |
| `list_audit` | limit | Audit Log |

### Inventory and Shopping List

`inventory` returns one row per item and unit, estimated from the lines on receipts: `item_key`, `unit`,
`name`, `tracked` (`auto`, `on` or `off`), `status`, `last_bought`, `last_qty`, `qty_left`, `used_pct`,
`days_left`, `lasts_days`, `days_per_unit`, `cycles`, `last_price` (with `last_price_cents`) and
`cheapest_merchant`. A field that doesn't apply to the status is `null`. `status` is one of:

| Status | Meaning |
|---|---|
| `learning` | tracked, but no finished cycle yet to learn from |
| `in_stock` | enough left |
| `running_low` | 80% of the last pack is gone, or 2 days or fewer are left |
| `used_up` | Used up was tapped since the last purchase |
| `lapsed` | not rebought for 3 times its usual life (and at least 30 days) |
| `off` | switched off with `set_item_tracking` |
| `once` | bought on one day only, so not tracked automatically |

Without `include_untracked`, `lapsed`, `off` and `once` items are left out, unless `status` asks for one
of them. `q` matches the item key or name; `status` keeps one status.

- `mark_used_up` records "ran out" for the unit bought most recently, or the `unit` you give, on `date`
  (today by default). The same item, unit and day twice is recorded once. An item with no purchases is a 400
  (`no purchases of <item_key>`), and so is a `date` that is not a real day or is after today, as there is
  no undo. Returns `{item_key, unit, at}`.
- `set_item_tracking` has to be sent a `tracked`: `true` always tracks the item, `false` hides it, and `null`
  goes back to automatic. Returns `{item_key, unit, tracked}` with `tracked` as `1`, `0` or `null`.
- `shopping_list` returns `{items, total, total_cents, ai}`. Each item has `id`, `item_key`, `unit`, `name`,
  `qty`, `source` (`user`, `ai` or `rule`), `reason`, `last_price` and `cheapest_merchant`. `ai` is
  `{last_run_at, ok, message, pending}`: when Claude last ran, whether that run worked, its status text, and
  whether a run is queued or going.
- `update_shopping_list` takes any of `add`, `bought`, `dismiss` and `remove`; the last three are lists of
  ids from `shopping_list`. `add` puts items on as your own, and a name already open on the list is updated,
  not listed twice. `bought` ticks items off as bought today, which inventory counts as a restock when no
  receipt covers the day. `dismiss` closes only rule and Claude suggestions, `remove` only your own items, and
  an id that doesn't fit is skipped, not an error. Returns `{added, changed}`.
- `refresh_shopping_list` only queues a run (`{queued: true}`). The web app (`ledger-web`) picks it up within
  a minute, so call `shopping_list` afterwards and watch `ai.pending`. See
  [Shopping List AI](extras.md#shopping-list-ai) for what runs and what is sent.

### The rows behind a category total

Budgets and the Home chart expand to the expenses their number adds up. The app asks
`list_transactions` for `{category, from, to, direction: "expense", limit: 1000}`:

- `category` is the text `budget_status` or `category_breakdown` returned, byte for byte; rows
  with none are `"(uncategorized)"`, and the budget `"Total"` sends no category at all.
- `from` and `to` are the first day of the month `budget_status.period_label` (or
  `spending_summary.from`) names and of the next month. Weekly budgets are totalled over the whole
  month by `budget_status`, so their list is the month's too.
- The same set is summed in both places: not voided, direction expense, `base_amount` (USD). The
  list adds up to the number exactly, FX rows included.
- `limit` tops out at 1000 and there is no offset, so a full page is followed by another query
  whose `to` is the last row's `posted_at` plus `"~"` (it sorts after any stamp, so rows tied with
  the last row come back and are dropped by id). The app reads at most 5 pages and says so on screen
  when it stops there.

### App-only extras

| Tool | Arguments | Result |
|---|---|---|
| `categories` | | Every category in use, plus the standard set from `categorize.cjs`, sorted |
| `networth` | | The web app's `/api/networth`: `{assets_cents, liabilities_cents, net_cents, unverified_count, groups: [{key, label, total_cents, accounts: [{id, name, currency, kind_resolved, is_liability, verified, latest_balance, drift_cents, current_cents, signed_cents, ...}]}]}` |
| `upload_receipt_photo` | **image_base64**, ext (jpg/png/heic/webp/pdf), merchant, purchased_at, total, transaction_id | `{id, inserted, image_path, bytes, transaction_id, bill_status: "pending"}` |
| `merchant_logo` | **merchant** (the transaction's text as the bank wrote it) | `{domain, image_base64, mime_type: "image/png"}`, or `{domain: null}` for a person, a transfer or a brand it doesn't know |

`merchant_logo` is `server/logos.cjs`: a curated alias table (`ALIASES`: add a line to teach it a brand) or a
domain the text spells out gives the brand's domain, and the server fetches that domain's icon once from a public
icon service (`LEDGER_LOGO_URL` overrides it) and caches it in `.data/logos/` (`LEDGER_LOGO_DIR`); a miss is
remembered for a week. Only the domain leaves the server. The app asks once per merchant text and keeps the PNG.

`networth` comes from `server/networth.cjs`. That module is lifted from `web/index.cjs`, which still
has its own copy; point the web app at the module the next time `web/index.cjs` is edited.

## Receipts from the phone

`add_receipt` takes structured fields only, never an image. Photos therefore go through
`upload_receipt_photo`, which does what the web uploader does:

1. It checks the bytes against the claimed type (magic numbers) before ImageMagick ever sees them,
   with a 12 MB limit.
2. It stores the photo content-addressed as `.data/receipts/<sha256>.<ext>`, mode 0600.
3. It creates the receipt (source `ios`) and attaches it to a matching transaction when `total` and
   `purchased_at` are given.
4. It queues the photo to be read into a bill (`bill.cjs`, `claude -p` on the subscription), one
   at a time.

The app sends base64 JSON, not multipart, so uploads pass the same JSON-only guard as every other
write. The phone downsizes photos to 2400 px JPEG first. When ledger-api restarts it resumes its own
unfinished reads; finance-web resumes the web app's.

## Security

- Tailnet only. It binds to loopback, and `tailscale serve` (not Funnel) publishes it. Nothing
  changed in Authentik, Cloudflare, ufw or sudoers.
- Following Pulse, the API refuses any POST that carries an `Origin` header or isn't
  `Content-Type: application/json`. Browsers always send `Origin` on cross-site POSTs and cannot send
  JSON without a CORS preflight, which this API never answers. That stops CSRF and DNS rebinding from
  any web page on a tailnet device. Every route that can write is a POST.
- Inputs are validated by the MCP tools' zod schemas. The extras check their own fields. Tool names
  must match `[a-z_]{1,64}` and an existing tool.
- No shell and no eval. The only child processes are `bill.cjs`'s fixed `claude` and `convert` argv.
- No raw-SQL tool and no hard delete, by the MCP server's design. `void_transaction` is a soft delete,
  and every write is audited (`list_audit`).

## Deploy and test

`node scripts/install.cjs` starts the API in the background, runs `tailscale serve` and checks
`/healthz`; `node scripts/doctor.cjs` checks the whole path from the database to the tailnet.

The test is `test/api.test.cjs`, which is part of `npm test`:

- It starts `api.cjs` on a throwaway database and a random port.
- It checks that every MCP tool is exposed, and that browser-shaped requests are refused.
- It runs log, categorize, review, void, record balance, reconcile, budget and net worth.
- It uploads a photo, round-trips the image, and checks that the bill read settles.

From any tailnet device:

```bash
curl https://<server>.<tailnet>.ts.net:8448/healthz
curl -X POST -H 'Content-Type: application/json' -d '{}' https://<server>.<tailnet>.ts.net:8448/api/tool/networth
curl -X POST -H 'Content-Type: application/json' -d '{"limit":5}' https://<server>.<tailnet>.ts.net:8448/api/tool/list_transactions
```

Logs: `journalctl --user -u ledger-api -f`. Bodies are never logged.
