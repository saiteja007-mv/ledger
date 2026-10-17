#!/usr/bin/env node
// Checks a Ledger install from the bottom up and says how to fix what isn't right. Read-only: it never
// changes anything, and it never prints a token.
//   node scripts/doctor.cjs          a table for you
//   node scripts/doctor.cjs --json   for an agent (AGENTS.md); exit code 1 when a required check fails
// Levels: required (Ledger or the iPhone app can't work without it), recommended, optional (the extras).
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const https = require('node:https')
const { OS, which, tailscale, run, tailnet } = require('./platform.cjs')

const ROOT = path.join(__dirname, '..')
const DATA = path.join(ROOT, '.data')
// The ports scripts/install.cjs chose (.data/install.json), unless the environment says otherwise.
const saved = (() => { try { return JSON.parse(fs.readFileSync(path.join(DATA, 'install.json'), 'utf8')).ports || {} } catch { return {} } })()
const PORTS = {
  web: Number(process.env.FINANCE_WEB_PORT || saved.web || 42832),
  api: Number(process.env.LEDGER_API_PORT || saved.api || 8098),
  mcp: Number(process.env.FINANCE_PORT || saved.mcp || 42820),
}
const checks = []
const add = (id, level, ok, detail, fix = null) => checks.push({ id, level, ok, detail, ...(ok ? {} : { fix }) })

// GET a JSON health endpoint. `connectTo` reaches a tailnet name by its IP, for servers without MagicDNS.
function getJson(url, { connectTo, timeout = 4000 } = {}) {
  return new Promise((resolve) => {
    const u = new URL(url)
    const mod = u.protocol === 'https:' ? https : require('node:http')
    const req = mod.get({ host: connectTo || u.hostname, servername: u.hostname, port: u.port, path: u.pathname,
      headers: { Host: u.host }, timeout }, (res) => {
      let body = ''
      res.on('data', (d) => { body += d })
      res.on('end', () => { try { resolve({ status: res.statusCode, json: JSON.parse(body) }) } catch { resolve({ status: res.statusCode, json: null }) } })
    })
    req.on('timeout', () => req.destroy(new Error('timed out')))
    req.on('error', (e) => resolve({ error: e.message }))
  })
}

async function main() {
  // ---- server ----
  const [major, minor] = process.versions.node.split('.').map(Number)
  add('node', 'required', major > 22 || (major === 22 && minor >= 5), `Node ${process.versions.node}`,
    'Install Node.js 22.5 or newer (it has the built-in node:sqlite Ledger uses), e.g. through nvm.')

  let depsOk = true
  for (const dep of ['@modelcontextprotocol/sdk/package.json', 'zod']) {
    try { require.resolve(dep, { paths: [ROOT] }) } catch { depsOk = false }
  }
  add('dependencies', 'required', depsOk, depsOk ? 'installed' : 'node_modules is missing', 'Run `npm ci` in the repo.')

  let stats = null
  const dbFile = process.env.FINANCE_DB || path.join(DATA, 'finance.sqlite')
  if (!fs.existsSync(dbFile)) {
    add('database', 'required', false, 'no database yet', 'It is created when the web app first starts: node scripts/install.cjs')
  } else {
    try {
      const db = require(path.join(ROOT, 'server', 'db.cjs'))
      db.initDb(dbFile)
      stats = db.stats()
      add('database', 'required', true, `${path.relative(ROOT, dbFile)}: ${stats.transactions} transactions, ${stats.accounts} accounts`)
    } catch (e) {
      add('database', 'required', false, `can't open the database: ${e.message}`, 'Check that .data/ is owned and writable by this user (chmod 700 .data).')
    }
  }
  if (stats) {
    add('accounts', 'recommended', stats.accounts > 0, stats.accounts ? `${stats.accounts} accounts` : 'no accounts yet',
      'Do the first setup (AGENTS.md, "First setup"): node scripts/setup.cjs example, then apply your plan.')
  }

  for (const [id, port, app, level, fix] of [
    ['web-app', PORTS.web, 'finance-web', 'required', 'Start it: node scripts/install.cjs'],
    ['iphone-api', PORTS.api, 'ledger-api', 'required', 'Start it: node scripts/install.cjs'],
    ['mcp-server', PORTS.mcp, 'finance-mcp', 'optional', 'Only for assistants (docs/extras.md): node scripts/install.cjs --mcp'],
  ]) {
    const r = await getJson(`http://127.0.0.1:${port}/healthz`)
    const ok = r.status === 200 && r.json?.app === app
    add(id, level, ok, ok ? `answering on 127.0.0.1:${port}` : r.json?.app ? `port ${port} is ${r.json.app}, not ${app}` : `nothing on 127.0.0.1:${port}`, fix)
  }
  add('web-token', 'recommended', fs.existsSync(path.join(DATA, 'web-token.txt')), 'the web sign-in token exists (not shown)',
    'It is created when the web app first starts; then sign in with the contents of .data/web-token.txt.')

  // Started at sign-in by scripts/install.cjs: systemd user units, launchd agents, or the Windows Startup folder.
  const installed = {
    linux: () => ['ledger-web', 'ledger-api'].every((u) => run('systemctl', ['--user', 'is-enabled', u])?.trim() === 'enabled'),
    macos: () => ['web', 'api'].every((n) => fs.existsSync(path.join(os.homedir(), 'Library', 'LaunchAgents', `dev.ledger.${n}.plist`))),
    windows: () => fs.existsSync(path.join(process.env.APPDATA || '', 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup', 'Ledger.vbs')),
  }[OS]
  if (installed) {
    const ok = installed()
    add('services', 'recommended', ok, ok ? 'the web app and iPhone API start at sign-in' : 'not set to start at sign-in', 'node scripts/install.cjs')
  }
  if (OS === 'linux' && run('systemctl', ['--user', 'show-environment'])) {
    const linger = /Linger=yes/.test(run('loginctl', ['show-user', os.userInfo().username, '-p', 'Linger']) || '')
    add('linger', 'recommended', linger, linger ? 'services keep running after logout' : 'services stop when you log out',
      `sudo loginctl enable-linger ${os.userInfo().username}`)
  }

  // ---- tailnet: how the iPhone reaches the API ----
  const net = tailnet()
  const dns = net.dns
  const running = net.state === 'Running'
  add('tailscale', 'required', running, running ? `on the tailnet as ${dns}` : net.state ? `Tailscale is ${net.state}` : 'Tailscale is not installed',
    'Install Tailscale (https://tailscale.com/download) and sign in (Linux: `sudo tailscale up`); sign in to the same tailnet on the iPhone.')
  if (running) {
    const serve = run(tailscale(), ['serve', 'status', '--json'])
    const published = Boolean(serve) && /"8448"/.test(serve) && new RegExp(`127\\.0\\.0\\.1:${PORTS.api}`).test(serve)
    add('tailnet-publish', 'required', published, published ? `https://${dns}:8448 -> 127.0.0.1:${PORTS.api}` : 'port 8448 is not published',
      `node scripts/install.cjs  (it runs: tailscale serve --bg --https=8448 http://127.0.0.1:${PORTS.api})`)
    if (published) {
      const r = await getJson(`https://${dns}:8448/healthz`, { connectTo: net.ip, timeout: 8000 })
      const ok = r.status === 200 && r.json?.app === 'ledger-api'
      add('tailnet-reach', 'required', ok, ok ? `https://${dns}:8448 answers over the tailnet` : `no answer over the tailnet: ${r.error || `HTTP ${r.status}`}`,
        'Check that HTTPS certificates are on for the tailnet (admin console > DNS > HTTPS Certificates) and MagicDNS is enabled.')
    }
  }

  // ---- the iPhone app's configuration and toolchain (only matters on the machine that builds it) ----
  const plist = (f, key) => (fs.readFileSync(f, 'utf8').match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`)) || [])[1] || ''
  try {
    const server = plist(path.join(ROOT, 'ios', 'Info.plist'), 'LedgerServerURL')
    const widgets = plist(path.join(ROOT, 'ios', 'Support', 'LedgerWidgets-Info.plist'), 'LedgerServerURL')
    const bundle = (fs.readFileSync(path.join(ROOT, 'ios', 'xtool.yml'), 'utf8').match(/^bundleID:\s*(\S+)/m) || [])[1]
    const want = dns ? `https://${dns}:8448` : null
    const serverOk = Boolean(server) && server === widgets && (!want || server === want)
    add('ios-server', 'recommended', serverOk, server ? `app points at ${server}` : 'no server built into the app (it will ask at launch; widgets stay empty)',
      `node scripts/ios-config.cjs --server ${want || 'https://<server>.<tailnet>.ts.net:8448'}`)
    add('ios-bundle-id', 'recommended', Boolean(bundle) && bundle !== 'com.example.ledger', `bundle ID ${bundle}`,
      'node scripts/ios-config.cjs --bundle-id com.<yourname>.ledger   (pick once and keep it)')
  } catch (e) {
    add('ios-config', 'recommended', false, `can't read ios/ config: ${e.message}`, 'Restore ios/Info.plist and ios/xtool.yml from git.')
  }
  const home = os.homedir()
  const swift = which('swift', [path.join(home, 'swift', 'usr', 'bin', 'swift')])
  const xtool = which('xtool', [path.join(home, '.local', 'bin', 'xtool')])
  add('ios-toolchain', 'optional', Boolean(swift && xtool), swift && xtool ? 'swift and xtool found' : `missing: ${[!swift && 'swift', !xtool && 'xtool'].filter(Boolean).join(', ')}`,
    OS === 'windows' ? 'The iPhone app builds inside WSL on Windows: run the doctor there too (docs/ios.md).' : 'Only on the machine that builds the iPhone app: see docs/ios.md.')

  // ---- extras ----
  const claude = which('claude', [process.env.CLAUDE_BIN, path.join(home, '.local', 'bin', 'claude')].filter(Boolean))
  add('receipt-reading', 'optional', Boolean(claude), claude ? 'Claude Code found: receipt photos are read into items' : 'receipt photos are stored but not read into items',
    'Install Claude Code and sign in (docs/extras.md, "Receipt reading").')
  // On Windows `convert` is a disk tool, not ImageMagick: only `magick` counts there.
  const convert = OS === 'windows' ? which('magick') : which('convert') || which('magick')
  add('imagemagick', 'optional', Boolean(convert), convert ? 'photos are downscaled for assistants' : 'ImageMagick not found',
    { linux: 'sudo apt install imagemagick', macos: 'brew install imagemagick', windows: 'winget install ImageMagick.ImageMagick' }[OS] || 'Install ImageMagick.')

  return checks
}

main().then((list) => {
  const failedRequired = list.filter((c) => c.level === 'required' && !c.ok)
  if (process.argv.includes('--json')) {
    console.log(JSON.stringify({ ok: failedRequired.length === 0, checks: list }, null, 2))
  } else {
    for (const c of list) {
      console.log(`${c.ok ? 'ok  ' : c.level === 'optional' ? 'skip' : 'FAIL'}  ${c.id.padEnd(16)} ${c.detail}`)
      if (!c.ok) console.log(`      ${''.padEnd(16)} fix: ${c.fix}`)
    }
    console.log(failedRequired.length ? `\n${failedRequired.length} required check(s) failing.` : '\nAll required checks pass.')
  }
  process.exit(failedRequired.length ? 1 : 0)
})
