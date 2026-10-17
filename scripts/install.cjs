#!/usr/bin/env node
// Run Ledger in the background on this computer, start it at sign-in, and publish the iPhone API on your
// tailnet. Works on macOS (launchd agents), Linux (systemd user services) and Windows (started hidden from
// the Startup folder). Safe to run again: it rewrites and restarts everything. Your data in .data/ is never
// touched.
//   node scripts/install.cjs              web app + iPhone API
//   node scripts/install.cjs --mcp        also the MCP server for assistants (docs/extras.md)
//   node scripts/install.cjs --uninstall  stop and remove all of it (the data stays)
//   node scripts/install.cjs --local      don't publish the iPhone API on the tailnet
// A port already taken on this computer? Set it once, e.g. LEDGER_API_PORT=18098 node scripts/install.cjs;
// the choice is kept in .data/install.json for later runs and for the doctor.
//
//   ledger-web   web app        127.0.0.1:42832  (sign in with .data/web-token.txt)
//   ledger-api   iPhone API     127.0.0.1:8098   published to your tailnet only at https://<this computer>:8448
//   ledger-mcp   MCP server     127.0.0.1:42820  (only with --mcp)
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const http = require('node:http')
const { execFileSync, execSync } = require('node:child_process')
const { OS, run, tailscale, tailnet } = require('./platform.cjs')

const ROOT = path.resolve(__dirname, '..')
const DATA = path.join(ROOT, '.data')
const LOGS = path.join(DATA, 'logs')
const NODE = process.execPath
const CONFIG = path.join(DATA, 'install.json')
const saved = (() => { try { return JSON.parse(fs.readFileSync(CONFIG, 'utf8')).ports || {} } catch { return {} } })()
const port = (env, key, fallback) => Number(process.env[env] || saved[key] || fallback)
const PORTS = { web: port('FINANCE_WEB_PORT', 'web', 42832), api: port('LEDGER_API_PORT', 'api', 8098), mcp: port('FINANCE_PORT', 'mcp', 42820) }
const SERVICES = [
  { name: 'ledger-web', entry: 'web/index.cjs', port: PORTS.web, label: 'Ledger web app',
    env: { FINANCE_WEB_HOST: '127.0.0.1', FINANCE_WEB_PORT: PORTS.web } },
  { name: 'ledger-api', entry: 'web/api.cjs', port: PORTS.api, label: 'Ledger iPhone API',
    env: { LEDGER_API_HOST: '127.0.0.1', LEDGER_API_PORT: PORTS.api } },
  { name: 'ledger-mcp', entry: 'server/index.cjs', port: PORTS.mcp, label: 'Ledger MCP server', mcp: true,
    env: { FINANCE_HOST: '127.0.0.1', FINANCE_PORT: PORTS.mcp } },
]
const args = process.argv.slice(2)
const uninstall = args.includes('--uninstall')
const wanted = SERVICES.filter((s) => !s.mcp || args.includes('--mcp'))
const fail = (message) => { console.error(`install: ${message}`); process.exit(1) }

// ---- per-OS service definitions -------------------------------------------------------------

const linux = {
  dir: path.join(os.homedir(), '.config', 'systemd', 'user'),
  file: (s) => path.join(linux.dir, `${s.name}.service`),
  write(s) {
    fs.mkdirSync(linux.dir, { recursive: true })
    fs.writeFileSync(linux.file(s), [
      '[Unit]', `Description=${s.label}`, 'After=network-online.target', '',
      '[Service]', 'Type=simple', `WorkingDirectory=${ROOT}`, `ExecStart=${NODE} ${path.join(ROOT, s.entry)}`,
      ...Object.entries(s.env).map(([k, v]) => `Environment=${k}=${v}`),
      'Restart=on-failure', 'RestartSec=5', '', '[Install]', 'WantedBy=default.target', '',
    ].join('\n'))
  },
  start(names) {
    execFileSync('systemctl', ['--user', 'daemon-reload'])
    for (const n of names) execFileSync('systemctl', ['--user', 'enable', '--now', n], { stdio: 'ignore' })
    for (const n of names) execFileSync('systemctl', ['--user', 'restart', n])
    const user = os.userInfo().username
    if (!/Linger=yes/.test(run('loginctl', ['show-user', user, '-p', 'Linger']) || '') && run('loginctl', ['enable-linger', user]) === null) {
      console.log(`note: run 'sudo loginctl enable-linger ${user}' so Ledger keeps running after you log out`)
    }
  },
  remove(s) {
    run('systemctl', ['--user', 'disable', '--now', s.name])
    fs.rmSync(linux.file(s), { force: true })
  },
}

const xml = (t) => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;')
const macos = {
  dir: path.join(os.homedir(), 'Library', 'LaunchAgents'),
  label: (s) => `dev.ledger.${s.name.replace('ledger-', '')}`,
  file: (s) => path.join(macos.dir, `${macos.label(s)}.plist`),
  domain: () => `gui/${process.getuid()}`,
  write(s) {
    fs.mkdirSync(macos.dir, { recursive: true })
    const log = path.join(LOGS, `${s.name}.log`)
    fs.writeFileSync(macos.file(s), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${macos.label(s)}</string>
  <key>ProgramArguments</key><array><string>${xml(NODE)}</string><string>${xml(path.join(ROOT, s.entry))}</string></array>
  <key>WorkingDirectory</key><string>${xml(ROOT)}</string>
  <key>EnvironmentVariables</key><dict>${Object.entries(s.env).map(([k, v]) => `<key>${k}</key><string>${v}</string>`).join('')}</dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${xml(log)}</string>
  <key>StandardErrorPath</key><string>${xml(log)}</string>
</dict>
</plist>
`)
  },
  start(names) {
    for (const s of SERVICES.filter((x) => names.includes(x.name))) {
      run('launchctl', ['bootout', `${macos.domain()}/${macos.label(s)}`])
      execFileSync('launchctl', ['bootstrap', macos.domain(), macos.file(s)])
    }
  },
  remove(s) {
    run('launchctl', ['bootout', `${macos.domain()}/${macos.label(s)}`])
    fs.rmSync(macos.file(s), { force: true })
  },
}

// No service manager a normal user can use without admin rights, so: a script in the Startup folder that
// starts each process hidden at sign-in, run once now too. It doesn't restart a crashed process; the doctor
// notices, and running this again (or signing out and in) brings it back.
const windows = {
  file: path.join(process.env.APPDATA || os.homedir(), 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup', 'Ledger.vbs'),
  vbs(names) {
    const quote = (s) => `"${s.replace(/"/g, '""')}"`
    const lines = SERVICES.filter((s) => names.includes(s.name)).map((s) => {
      const cmd = `cmd /c ""${NODE}" "${path.join(ROOT, s.entry)}" >> "${path.join(LOGS, `${s.name}.log`)}" 2>&1"`
      const env = Object.entries(s.env).map(([k, v]) => `env(${quote(k)}) = ${quote(String(v))}`)
      return [...env, `sh.Run ${quote(cmd)}, 0, False`].join('\r\n')
    })
    return [
      "' Ledger: starts the web app and the iPhone API hidden at sign-in. Written by scripts/install.cjs;",
      "' run it again to change this, or with --uninstall to remove it.",
      'Set sh = CreateObject("WScript.Shell")',
      'Set env = sh.Environment("Process")',
      `sh.CurrentDirectory = ${quote(ROOT)}`,
      ...lines, '',
    ].join('\r\n')
  },
  // Stops the Ledger processes this repo started: matched on the full path of their entry file.
  stop(services) {
    const paths = services.map((s) => path.join(ROOT, s.entry).replace(/'/g, "''"))
    const filter = paths.map((p) => `$_.CommandLine -like '*${p}*'`).join(' -or ')
    run('powershell', ['-NoProfile', '-NonInteractive', '-Command',
      `Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { ${filter} } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }`])
  },
  install(names) {
    windows.stop(SERVICES)
    fs.mkdirSync(path.dirname(windows.file), { recursive: true })
    fs.writeFileSync(windows.file, windows.vbs(names))
    execFileSync('wscript', [windows.file])
  },
  remove() {
    windows.stop(SERVICES)
    fs.rmSync(windows.file, { force: true })
  },
}

// ---- steps ------------------------------------------------------------------------------------

const health = (port) => new Promise((resolve) => {
  http.get({ host: '127.0.0.1', port, path: '/healthz', timeout: 2000 }, (res) => { res.resume(); resolve(res.statusCode === 200) })
    .on('error', () => resolve(false)).on('timeout', function () { this.destroy() })
})

async function waitHealthy(services) {
  for (let i = 0; i < 60; i++) {   // up to 30 s: a first start on Windows can be slow while it's scanned
    const up = await Promise.all(services.map((s) => health(s.port)))
    if (up.every(Boolean)) return []
    await new Promise((r) => setTimeout(r, 500))
  }
  const up = await Promise.all(services.map((s) => health(s.port)))
  return services.filter((_, i) => !up[i])
}

function publish() {
  const cli = tailscale()
  const net = tailnet()
  if (!cli || net.state !== 'Running') return null
  if (run(cli, ['serve', '--bg', '--https=8448', `http://127.0.0.1:${PORTS.api}`]) === null) {
    fail(OS === 'linux'
      ? `could not publish port 8448 on the tailnet. Run 'sudo tailscale set --operator=${os.userInfo().username}' once, then this again.`
      : 'could not publish port 8448 on the tailnet: check that Tailscale is running and signed in, then run this again.')
  }
  return net.dns
}

async function main() {
  const [major, minor] = process.versions.node.split('.').map(Number)
  if (!(major > 22 || (major === 22 && minor >= 5))) fail(`Node ${process.versions.node} is too old: Ledger needs 22.5+ (built-in node:sqlite)`)
  const manager = { linux, macos: macos, windows }[OS]
  if (!manager) fail(`${process.platform} isn't supported; run node web/index.cjs and node web/api.cjs yourself`)
  // A reachable user manager, not just the binary: WSL without systemd has `systemctl` but no manager.
  if (OS === 'linux' && run('systemctl', ['--user', 'show-environment']) === null) {
    fail('no systemd user manager here: run `node web/index.cjs` and `node web/api.cjs` under whatever keeps processes alive on this system')
  }

  if (uninstall) {
    if (OS === 'windows') windows.remove()
    else for (const s of SERVICES) manager.remove(s)
    run(tailscale(), ['serve', '--https=8448', 'off'])
    console.log('Ledger is stopped and no longer starts at sign-in. Your data is still in .data/.')
    return
  }

  // macOS keeps background agents out of Documents, Desktop and Downloads.
  if (OS === 'macos' && /^(Documents|Desktop|Downloads)(\/|$)/.test(path.relative(os.homedir(), ROOT))) {
    fail(`launchd can't run Ledger from ${ROOT}: move the folder somewhere like ~/ledger, then run this again`)
  }
  if (!fs.existsSync(path.join(ROOT, 'node_modules', '@modelcontextprotocol', 'sdk'))) {
    console.log('installing dependencies (npm ci) ...')
    // A fixed command string: on Windows npm is a .cmd, which only runs through a shell.
    execSync('npm ci --no-audit --no-fund', { cwd: ROOT, stdio: 'inherit' })
  }
  fs.mkdirSync(LOGS, { recursive: true, mode: 0o700 })
  if (OS !== 'windows') fs.chmodSync(DATA, 0o700)
  fs.writeFileSync(CONFIG, JSON.stringify({ ports: PORTS }, null, 2) + '\n')

  const names = wanted.map((s) => s.name)
  if (OS === 'windows') {
    windows.install(names)
  } else {
    for (const s of SERVICES) (wanted.includes(s) ? manager.write(s) : manager.remove(s))
    manager.start(names)
  }

  const down = await waitHealthy(wanted)
  if (down.length) {
    const log = path.join(LOGS, `${down[0].name}.log`)
    const where = OS === 'linux' ? `journalctl --user -u ${down[0].name} -n 50` : log
    if (OS !== 'linux' && fs.existsSync(log)) console.error(fs.readFileSync(log, 'utf8').split(/\r?\n/).slice(-15).join(os.EOL))
    fail(`${down.map((s) => s.name).join(', ')} did not start. Look at: ${where}`)
  }

  const dns = args.includes('--local') ? null : publish()
  console.log('Ledger is running and starts again at sign-in.')
  console.log(`  web app:     http://127.0.0.1:${PORTS.web}   (sign in with the token in .data/web-token.txt)`)
  if (dns) {
    console.log(`  iPhone app:  https://${dns}:8448   <- for: node scripts/ios-config.cjs --server`)
  } else if (args.includes('--local')) {
    console.log(`  iPhone API:  http://127.0.0.1:${PORTS.api}   (not published on the tailnet: --local)`)
  } else {
    console.log('  iPhone app:  not reachable yet. Install Tailscale on this computer, sign in, then run this again (AGENTS.md, Stage 2).')
  }
  if (wanted.some((s) => s.mcp)) console.log(`  MCP server:  http://127.0.0.1:${PORTS.mcp}/mcp   (token in .data/api-token.txt; docs/extras.md)`)
}

main().catch((e) => fail(e.message))
