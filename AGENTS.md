# Setting up Ledger: instructions for an agent

You are helping someone run their own Ledger: a server (web app, iPhone API, optional MCP server, one SQLite
file) and the iPhone app in `ios/`. Their computer may be macOS, Linux or Windows; everything the server needs
is Node.js, and the scripts in `scripts/*.cjs` run the same on all three. Work through the stages in order. At each stage, run the check, fix what
fails, and run the check again before you move on. Talk to the person in plain words; they may not be a
developer.

## Ground rules

- **Never print or paste a secret.** `.data/*-token.txt`, `.data/authentik-proof.txt`, Apple ID passwords and
  API keys stay in their files. Say where a token is (for example "the web sign-in token is in
  `.data/web-token.txt`"); never what it contains.
- **Never commit** `.data/`, a plan file with their balances, or their `ios/` config (server address, bundle
  ID). If they want to contribute code back, those changes stay out of the commit.
- **Never publish a port to the internet.** The iPhone API is tailnet-only by design (Tailscale membership is
  its login). Only the optional MCP server may be made public, and only behind HTTPS (docs/extras.md).
- **Ask before** `sudo`, installing system packages, or anything that touches their Apple ID.
- `node scripts/doctor.cjs --json` is read-only. Run it as often as you like.

## Stage 1: the server

Check: `node scripts/doctor.cjs --json`. Look at `node`, `dependencies`, `database`, `web-app`, `iphone-api`.

1. Node.js 22.5 or newer (`node -v`). If it's older or missing, install the current LTS: from nodejs.org,
   `brew install node` (macOS), `winget install OpenJS.NodeJS.LTS` (Windows), or nvm (Linux). Ask before
   anything that needs sudo or an administrator.
2. `node scripts/install.cjs`. It installs the dependencies, then runs the web app and the iPhone API in the
   background and starts them at sign-in: launchd agents on macOS, systemd user services on Linux, a hidden
   start-up script on Windows. Re-running it is safe; `--uninstall` removes it all and keeps the data.
   - **A port is taken** (the doctor or the installer says so): pick free ones once, e.g.
     `LEDGER_API_PORT=18098 FINANCE_WEB_PORT=18832 node scripts/install.cjs` (PowerShell:
     `$env:LEDGER_API_PORT='18098'` first). They are saved in `.data/install.json`.
   - **macOS**: the repo must not live in Documents, Desktop or Downloads (background agents can't read
     them); the installer refuses and says so. Move it, for example to `~/ledger`.
   - **Linux**: it may ask for their password once for `loginctl enable-linger`, so Ledger keeps running
     after they log out. Without systemd (some containers, WSL without systemd) it says so; then run
     `node web/index.cjs` and `node web/api.cjs` under whatever keeps processes alive there.
   - **Windows**: there is no restart if a process crashes; signing out and in, or running the installer
     again, brings it back. The doctor shows when it's down.
3. The web app is at `http://127.0.0.1:42832` (or the port they chose); they sign in with the token in
   `.data/web-token.txt`.

Done when `web-app`, `iphone-api` and `database` are ok.

## Stage 2: Tailscale (how the iPhone reaches the server)

Check: `tailscale`, `tailnet-publish`, `tailnet-reach` in the doctor.

1. Tailscale on the server, signed in: the app on macOS and Windows (tailscale.com/download), or the package
   plus `sudo tailscale up` on Linux. The Tailscale app on their iPhone signs in to the **same tailnet**.
2. In the Tailscale admin console, MagicDNS and HTTPS certificates must be on (DNS page).
3. Run `node scripts/install.cjs` again: it publishes the API to the tailnet only
   (`tailscale serve --bg --https=8448 http://127.0.0.1:<api port>`). On Linux, if it can't,
   `sudo tailscale set --operator=$USER` once, then run it again.
4. The address the iPhone uses is `https://<this computer's tailnet name>:8448`; the doctor and the installer
   print it. The server has to be on and signed in to Tailscale whenever they use the app.

Done when `tailnet-reach` is ok.

## Stage 3: first setup (their accounts and budgets)

Check: `accounts` in the doctor, and `node scripts/setup.cjs show`.

Ask, a few questions at a time:

1. **Accounts.** For each: a name they will recognise ("Chase Checking", "Visa 1234"; for a card, putting the
   last 4 digits in the name matters if they want bank alerts later), what kind it is, its currency, and its
   balance today. Kinds: `checking` (any bank account, savings too), `credit` (a card; the balance is what they
   owe, as a positive number), `cash`, `wallet` (PayPal, Venmo), `people` (friends who owe them, a Splitwise
   tab). Suggest `Cash` if they use any.
2. **Budgets.** An overall monthly limit (category `Total`) and any per-category limits. Show them the
   categories: `node -e "console.log(require('./server/categorize.cjs').DEFAULT_RULES.map(r=>r.category).filter((c,i,a)=>a.indexOf(c)===i).join(', '))"`.
   Budgets are optional.

Then:

1. Write their answers as a plan in `.data/setup-plan.json` (inside `.data/`, so it is never committed). The
   format is in `node scripts/setup.cjs example` and at the top of `scripts/setup.cjs`.
2. `node scripts/setup.cjs apply .data/setup-plan.json --dry-run`. It lists every problem at once; fix the
   plan (ask them if you need to) until it says the plan is OK.
3. `node scripts/setup.cjs apply .data/setup-plan.json`, then read the result back to them in a short table:
   accounts with balances, then budgets. Fix anything they correct by editing the plan and applying again;
   it's safe to re-apply.
4. Past transactions are optional: a Money Manager style `.xlsx` export imports with
   `node scripts/import-xlsx.cjs <file> --dry-run`, then without `--dry-run`.

Done when `setup.cjs show` matches what they told you.

## Stage 4: the iPhone app

Read `docs/ios.md` first. Check: `ios-server`, `ios-bundle-id`, `ios-toolchain` in the doctor, on the machine
that will build the app (it may not be the server).

1. Toolchain, by their computer (docs/ios.md): **macOS**: Xcode and xtool. **Linux**: Swift and xtool.
   **Windows**: inside WSL (Ubuntu), Swift and xtool, with the iPhone attached to WSL over usbipd; the bash
   scripts in step 4 and 6 run inside WSL, the `node scripts/*.cjs` ones anywhere. Ask before installing;
   it is a large download, and off a Mac it needs an `Xcode.xip` they download with their Apple ID.
2. Bundle ID: propose `com.<their name, lowercase>.ledger` and explain they should keep it (a free Apple ID
   gets 10 new app IDs a week; this app uses two).
3. `node scripts/ios-config.cjs --server https://<tailnet name>:8448 --bundle-id <bundle id>`.
4. `bash scripts/ios-build.sh`. It must end in `BUILD OK` with 0 errors and `LOGIC OK`. If it warns that the
   widget extension is empty, fix the toolset (docs/ios.md, Widgets) before installing.
5. They sign in once: `xtool auth login` (they type the Apple ID password themselves; you never see it). Then
   the phone: plugged in, unlocked, Trust, Developer Mode on.
6. `bash scripts/ios-install.sh`. On the phone: Settings > General > VPN & Device Management > trust their
   Apple ID, then open Ledger, turn Tailscale on, and check their accounts show up.
7. Tell them it has to be re-installed every 7 days with a free Apple ID (step 6 again), and that no data is
   lost when it lapses.

Done when the app shows their accounts.

## Stage 5: extras (only the ones they want)

Ask which of these they want; each one is explained in `docs/extras.md`:

- **Assistants** (Claude, ChatGPT) reading and logging through MCP.
- **Receipt reading**: photos turned into line items and price history. Needs Claude Code on the server.
- **Shopping List AI**: Claude keeps the shopping list. Simple rules keep it with no setup; this needs an
  Anthropic API key in a file (never print it).
- **Bank of America alerts** turned into transactions.
- **Merchant logos**: already on. **Other currencies**: just set the account's currency.

## Finish

Run `node scripts/doctor.cjs` and show them the result: every `required` check ok, and say plainly what any
remaining `recommended` or `optional` line means for them. Then tell them where things are: the web app
address, the sign-in token file, the iPhone app, the 7-day re-install, and that `git pull` followed by
`node scripts/install.cjs` updates the server.

## Working on the code

- `npm test` runs every server test (`node --test`); keep it green. Tests never touch `.data/`.
- `bash scripts/ios-build.sh` builds the app and runs its logic checks (`ios/Checks/main.swift`).
- Money is integer cents, amounts are positive and `direction` carries the sign, writes are idempotent upserts,
  deletes are soft. README.md has the design rules; `docs/api.md` documents the iPhone API.
