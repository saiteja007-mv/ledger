# Optional extras

Everything here is off until you turn it on, and Ledger works without any of it. `node scripts/doctor.cjs`
shows which ones are set up.

## Assistants over MCP (Claude, ChatGPT)

The MCP server (`server/index.cjs`) gives an assistant the same 31 tools the apps use: read, log, categorise,
budgets, receipts, item prices, inventory and the shopping list.

1. `node scripts/install.cjs --mcp` adds the MCP server on `127.0.0.1:42820`. Its bearer token is generated
   on first start in `.data/api-token.txt`; treat it like a password.
2. **Claude Code on the same machine or tailnet**:
   `claude mcp add --transport http ledger http://127.0.0.1:42820/mcp --header "Authorization: Bearer <token>"`.
3. **claude.ai or ChatGPT** need a public HTTPS URL: put the MCP port behind Cloudflare Tunnel or Tailscale
   Funnel. Their connector dialogs have no header field, so the server also accepts `?token=` in the URL; that
   lands in proxy logs and browser history, so prefer a sign-in proxy in front of it if you can.
4. To show the URL in the iPhone app (More > MCP server): `node scripts/ios-config.cjs --mcp https://<your url>/mcp`.

Writes from an assistant land in **Review** until you confirm them.

## Receipt reading

A receipt photo (web app or iPhone) is stored either way. With this on, each photo is also read into a bill:
merchant, date, every line item, tax and total. The items feed **Item Prices**.

- Install [Claude Code](https://claude.com/claude-code) on the server and sign in with your Claude
  subscription. `server/bill.cjs` runs `claude -p` for each photo, one at a time, with no tools. It runs
  `~/.local/bin/claude` unless `CLAUDE_BIN` says otherwise.
- Install ImageMagick (`sudo apt install imagemagick`, `brew install imagemagick`, or on Windows
  `winget install ImageMagick.ImageMagick`): photos are converted and downscaled before reading, and HEIC
  needs it.

The photo goes to Anthropic for reading; nothing else does.

## Shopping List AI

**Inventory** and the **Shopping List** work without any of this. With no key, Ledger keeps a rule-based list.
Add an Anthropic API key and Claude keeps the list instead.

How Inventory learns:

- It is built from the line items on your receipts, so it fills in as receipts are read (see Receipt
  reading) or logged with items. Tax, fees, deposits, coupons, discounts, bag charges and tips are never items.
- An item bought on **2 or more different days** is tracked. One bought once is not: rebuying is what makes
  something a thing you use up. Same-day purchases count as one.
- Tap **Used up** when you finish one. That tells Ledger how fast you really go through it. A rebuy also ends
  the cycle, and an item's usual life is the median of its last 6 finished cycles, scaled by pack size.
- **Track** and **Don't track** override the rule for one item (track something bought once, hide a gift
  bought twice). Items that are off, bought once or lapsed wait in a collapsed **Not tracked** section.

Without a key, the list suggests every tracked item that is used up, running low (about 80% of the last pack
gone, or 2 days left) or about 3 days from running out, with the reason on each row.

To let Claude keep the list:

1. Put your key on one line in `.data/anthropic-key.txt`, or in any file you point `LEDGER_ANTHROPIC_KEY_FILE`
   at (set it in the web app's environment). `.data/` is never committed.
2. Keep that file owner-only, for example `chmod 600 .data/anthropic-key.txt`.
3. Tap **Update now**. The file is read at the start of every run, so a new key needs no restart.

Claude adds what you will probably need soon, changes quantities and removes what is no longer needed, each
with a short reason. It uses `claude-opus-5-5` at low effort, one request per run, billed to your Anthropic
API account (separate from a Claude subscription).

**When it runs.** Only the web app (`ledger-web`) calls Claude. The MCP server, the iPhone API and the web
app's own screens just ask for a run. The web app checks once a minute, and runs when:

- you tap **Update now**, or an assistant calls `refresh_shopping_list`;
- a receipt line or a Used up tap has changed since the last run (the first check counts, as there is no last
  run yet); or
- the server's clock has passed 06:00 and it has not run since then.

**What is sent.** Today's date; for each tracked item its name, unit, status, last bought date and quantity,
quantity left, days left and how long a pack lasts; that item's purchases from the last 90 days (name,
quantity, unit, unit price, store name, date); and the open list (id, name, quantity, reason, who added it).
Not sent: account names, card digits, transaction notes or receipt photos. The key itself goes only to
Anthropic.

**What it may change.** It never changes or removes an item you added yourself; the server refuses it
even if Claude tries. It does not put back an item you dismissed, removed or ticked off until something new
happens for that item, a newer receipt line or a Used up tap. The rule-based suggestions follow the same
rule. One run adds at most 40 items.

**When it fails.** The rule-based list is brought up to date first, so no key, a timeout (a run is cut off
at 105 seconds), a refusal, an API error or an unreadable answer all still leave you that list. The line
under the list shows the status ("no API key: rules only", "Claude timed out: rules only", "Updated by Claude
2 h ago"). A failed run is not retried by itself; it waits for something new, **Update now**, or the next
06:00. If you add a key after a run with no key, tap **Update now**.

`LEDGER_SHOPPING_TIMER=off` (in the web app's environment) turns the timer off. Nothing then calls Claude or
refreshes the rule suggestions, and **Update now** just stays queued; items you add, tick off, dismiss or
remove yourself still work.

## Bank of America alerts

BofA can text or email you an alert for every card charge. Ledger turns those into transactions waiting in
Review, on the account whose name contains the card's last 4 digits (name it "Visa 1234", say).

- **From the phone**: an iOS Message or Email automation posts the alert text to
  `POST /api/ingest/bofa` on the web app (raw text or `{"text": "..."}`), with
  `Authorization: Bearer <.data/ingest-token.txt>` (or `FINANCE_INGEST_TOKEN`). That token can do nothing
  else. iOS can't start a Shortcut from an app's push notification, only from a Message or Email
  automation, so turn on BofA's text or email alerts and point the automation at their sender. The reply
  has a human `message` ("Logged $11.98 at CORNER MARKET on Visa 1234") for the Shortcut to show.
- **From Gmail, no phone**: `scripts/bofa-mail-poll.cjs` reads new alerts through a
  [Unipile](https://www.unipile.com)-connected Google account (`UNIPILE_API_BASE`, `UNIPILE_API_KEY`,
  `BOFA_MAIL_ACCOUNT_ID`). Run it every 10 minutes from a scheduler (a systemd timer, launchd, or Task Scheduler on Windows); `--init` marks the current inbox as
  seen, `--dry-run` parses without writing.

Charges become expenses and "We've credited your account" a refund; payments and statement notices are
ignored. The same charge arriving by text and by email is logged once (same card, direction and amount within
2 days, matching merchant), and ride-app holds ("TEMP AUTH HOLD", "PENDING.") are skipped because the final
charge arrives separately. A category is copied only from an earlier row with the same merchant.

## Merchant logos

On by default. The iPhone app shows a brand icon next to recognised merchants. Only the brand's domain leaves
the server, sent to a public icon service; icons are cached in `.data/logos/`. Change the service with
`LEDGER_LOGO_URL` (with `{domain}` in it), or point it at something unreachable to turn logos off.

## Other currencies

Accounts can be in any currency. A non-USD transaction is converted at that day's ECB rate from
[Frankfurter](https://frankfurter.dev) (only the date and the currency code are sent), and totals are in USD.

## Web app behind a sign-in proxy

The web app's own sign-in is the token in `.data/web-token.txt`. If you publish it through Authentik, set
`AUTHENTIK_OWNER_EMAIL` and put the proxy's shared secret in `.data/authentik-proof.txt`; requests carrying
both are signed in without the token.
