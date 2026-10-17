# Optional extras

Everything here is off until you turn it on, and Ledger works without any of it. `node scripts/doctor.cjs`
shows which ones are set up.

## Assistants over MCP (Claude, ChatGPT)

The MCP server (`server/index.cjs`) gives an assistant the same 25 tools the apps use: read, log, categorise,
budgets, receipts, item prices.

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
