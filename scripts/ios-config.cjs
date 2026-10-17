#!/usr/bin/env node
// Point the iPhone app at your server and give it your own bundle ID, before building it.
//   node scripts/ios-config.cjs                         show the current settings
//   node scripts/ios-config.cjs --server https://myserver.your-tailnet.ts.net:8448 --bundle-id com.alex.ledger
//   node scripts/ios-config.cjs --mcp https://ledger.example.com/mcp      optional (docs/extras.md)
//
// Writes ios/xtool.yml (bundleID) and LedgerServerURL / LedgerMCPURL in ios/Info.plist and the widgets'
// Info.plist. A free Apple ID allows 10 new app IDs a week and the app uses two (app + widgets), so pick
// a bundle ID once and keep it: changing it later spends two more.
const fs = require('node:fs')
const path = require('node:path')

const IOS = path.join(__dirname, '..', 'ios')
const FILES = {
  xtool: path.join(IOS, 'xtool.yml'),
  app: path.join(IOS, 'Info.plist'),
  widgets: path.join(IOS, 'Support', 'LedgerWidgets-Info.plist'),
}

const args = process.argv.slice(2)
const flag = (name) => {
  const i = args.indexOf(`--${name}`)
  if (i === -1) return undefined
  const value = args[i + 1]
  if (value === undefined || value.startsWith('--')) fail(`--${name} needs a value`)
  return value
}
function fail(message) {
  console.error(`ios-config: ${message}`)
  process.exit(1)
}

// "host:8448" or a full URL; https unless it says http. Paths are dropped: the app adds /api/tool/ itself.
function normalizeServer(text) {
  let t = String(text).trim()
  if (!t.includes('://')) t = `https://${t}`
  let url
  try { url = new URL(t) } catch { fail(`"${text}" is not a server address`) }
  if (!['https:', 'http:'].includes(url.protocol) || !url.hostname) fail(`"${text}" is not an http(s) address`)
  return `${url.protocol}//${url.host}`
}

const read = (f) => fs.readFileSync(f, 'utf8')
const plistValue = (text, key) => (text.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`)) || [])[1]
function setPlist(file, key, value) {
  const text = read(file)
  const re = new RegExp(`(<key>${key}</key>\\s*<string>)[^<]*(</string>)`)
  if (!re.test(text)) fail(`${path.relative(process.cwd(), file)} has no ${key} key`)
  const escaped = value.replace(/&/g, '&amp;').replace(/</g, '&lt;')
  fs.writeFileSync(file, text.replace(re, `$1${escaped}$2`))
}

const server = flag('server')
const bundleId = flag('bundle-id')
const mcp = flag('mcp')

if (bundleId !== undefined) {
  if (!/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(bundleId)) fail(`"${bundleId}" is not a bundle ID (like com.yourname.ledger)`)
  const text = read(FILES.xtool)
  if (!/^bundleID:.*$/m.test(text)) fail('ios/xtool.yml has no bundleID line')
  fs.writeFileSync(FILES.xtool, text.replace(/^bundleID:.*$/m, `bundleID: ${bundleId}`))
}
if (server !== undefined) {
  const url = normalizeServer(server)
  setPlist(FILES.app, 'LedgerServerURL', url)
  setPlist(FILES.widgets, 'LedgerServerURL', url)
}
if (mcp !== undefined) {
  setPlist(FILES.app, 'LedgerMCPURL', mcp === '' ? '' : new URL(mcp).toString())
}

const current = {
  bundleID: (read(FILES.xtool).match(/^bundleID:\s*(\S+)/m) || [])[1],
  server: plistValue(read(FILES.app), 'LedgerServerURL') || null,
  widgetsServer: plistValue(read(FILES.widgets), 'LedgerServerURL') || null,
  mcp: plistValue(read(FILES.app), 'LedgerMCPURL') || null,
}
console.log(JSON.stringify(current, null, 2))
if (current.bundleID === 'com.example.ledger') console.log('note: still the placeholder bundle ID; set your own with --bundle-id')
if (!current.server) console.log('note: no server set; the app will ask for it at launch, and the widgets stay empty')
