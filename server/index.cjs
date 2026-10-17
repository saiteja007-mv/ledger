// finance-mcp HTTP entrypoint. Serves ONLY /mcp (+ /healthz). There is no web UI and no
// REST surface — fewer doors on something that holds bank data and accepts writes.
const http = require('node:http')
const fs = require('node:fs')
const path = require('node:path')
const crypto = require('node:crypto')

const db = require('./db.cjs')
const categorize = require('./categorize.cjs')
const reconcile = require('./reconcile.cjs')

const PORT = Number(process.env.FINANCE_PORT || 42820)
// Bind loopback only. Public reach comes from the cloudflared tunnel, which terminates
// here — binding 0.0.0.0 would additionally expose this to the whole LAN for no benefit.
const HOST = process.env.FINANCE_HOST || '127.0.0.1'
const DATA_DIR = path.join(__dirname, '..', '.data')

// One token, granting read + write. Generated on first boot and persisted 0600.
// Migration: if an older write-token.txt exists, adopt its value so anything already
// configured with it keeps working instead of silently 401-ing.
function loadToken(name = 'api') {
  const envKey = 'FINANCE_TOKEN'
  if (process.env[envKey]) return process.env[envKey]
  const file = path.join(DATA_DIR, `${name}-token.txt`)
  try { const v = fs.readFileSync(file, 'utf8').trim(); if (v) return v } catch {}
  try {
    const legacy = fs.readFileSync(path.join(DATA_DIR, 'write-token.txt'), 'utf8').trim()
    if (legacy) { fs.writeFileSync(file, legacy + '\n', { mode: 0o600 }); console.log(`[finance-mcp] adopted existing write token as the single token -> ${file}`); return legacy }
  } catch {}
  fs.mkdirSync(DATA_DIR, { recursive: true })
  const tok = crypto.randomBytes(32).toString('hex')
  fs.writeFileSync(file, tok + '\n', { mode: 0o600 })
  console.log(`[finance-mcp] generated ${name} token -> ${file}`)
  return tok
}

async function main() {
  db.initDb()
  const token = loadToken()
  const { createMcpHandler } = await import('./mcp.mjs')
  const handleMcp = createMcpHandler({ db, categorize, reconcile, token })

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`)
    if (url.pathname === '/healthz') {
      res.writeHead(200, { 'Content-Type': 'application/json' })
      return res.end(JSON.stringify({ ok: true, app: 'finance-mcp', ...db.stats() }))
    }
    if (url.pathname !== '/mcp') {
      res.writeHead(404, { 'Content-Type': 'application/json' })
      return res.end(JSON.stringify({ error: 'not found' }))
    }
    // Cap the body: a write endpoint on the public internet should not accept unbounded input.
    let body = ''
    let tooBig = false
    req.on('data', (c) => {
      body += c
      if (body.length > 2_000_000) { tooBig = true; req.destroy() }
    })
    req.on('end', () => {
      if (tooBig) {
        res.writeHead(413, { 'Content-Type': 'application/json' })
        return res.end(JSON.stringify({ error: 'payload too large' }))
      }
      handleMcp(req, res, body).catch((e) => {
        if (!res.headersSent) res.writeHead(500, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ error: String(e?.message || e) }))
      })
    })
  })

  server.listen(PORT, HOST, () => {
    const s = db.stats()
    console.log(`[finance-mcp] listening on http://${HOST}:${PORT}/mcp`)
    console.log(`[finance-mcp] ${s.transactions} transactions, ${s.accounts} accounts, range ${s.range?.first?.slice(0, 10)} -> ${s.range?.last?.slice(0, 10)}`)
  })
}

main().catch((e) => { console.error('[finance-mcp] fatal:', e); process.exit(1) })
