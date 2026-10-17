// logos.cjs — a merchant descriptor ("UBER *TRIP HELP.UBER.COMCA") to a brand domain to a cached icon.
// Only the server talks to the icon service, and only the brand's domain leaves it: never an amount, a
// date or an account. The phone asks the app API (web/api.cjs), which answers from the cache, so a logo is
// fetched once and then served from disk.
//
// A wrong logo is worse than none, so a descriptor only gets a domain from a curated alias or from a
// domain it spells out itself. People ("Alex"), "Income" and transfers get nothing, and the app keeps
// the category icon.
const fs = require('node:fs')
const path = require('node:path')

// [pattern on the lowercased descriptor, domain]. First match wins. Add a line to teach it a brand.
const ALIASES = [
  [/\bwal-?mart\b|\bwm supercenter\b|\bwalmart\b/, 'walmart.com'],
  [/\bcostco\b/, 'costco.com'],
  [/\bapple\.com|\bitunes\b/, 'apple.com'],
  [/\buber\b/, 'uber.com'],
  [/\blyft\b/, 'lyft.com'],
  [/\bamazon web services\b|\baws\.amazon/, 'aws.amazon.com'],
  [/\bamazon\b|\bamzn\b/, 'amazon.com'],
  [/\bamc \d+|\bamc theat/, 'amctheatres.com'],
  [/\bat&t\b|\batt\b/, 'att.com'],
  [/\bbest ?buy\b|\bbestbuy\b/, 'bestbuy.com'],
  [/\binstacart\b/, 'instacart.com'],
  [/\bcloudflare\b/, 'cloudflare.com'],
  [/\bwingstop\b/, 'wingstop.com'],
  [/\bwalgreens\b/, 'walgreens.com'],
  [/\bgreat clips\b/, 'greatclips.com'],
  [/\bbofa\b|\bbank of america\b|\bbofa\b/, 'bankofamerica.com'],
  [/\bquiktrip\b|^qt \d+/, 'quiktrip.com'],
  [/\bnetflix\b/, 'netflix.com'],
  [/\bspotify\b/, 'spotify.com'],
  [/\bgoogle\b/, 'google.com'],
  [/\byoutube\b/, 'youtube.com'],
  [/\bdoordash\b/, 'doordash.com'],
  [/\bstarbucks\b/, 'starbucks.com'],
  [/\bmcdonald/, 'mcdonalds.com'],
  [/\btarget\b/, 'target.com'],
  [/\bchipotle\b/, 'chipotle.com'],
  [/\bsubway\b/, 'subway.com'],
  [/\bvenmo\b/, 'venmo.com'],
  [/\bpaypal\b/, 'paypal.com'],
]

// A domain the descriptor spells out. Bank text glues the state code on ("help.uber.comca", "aws.amazon.coWA"),
// so up to two stray letters may follow the TLD.
const TLDS = 'com|net|org|io|app|ai|dev|in|us|tv|me|de|uk|ca'
const SPELLED = new RegExp(`\\b((?:[a-z0-9-]+\\.)+(?:${TLDS}))(?:[a-z]{2})?(?![a-z0-9-])`)

function resolveDomain(descriptor) {
  if (typeof descriptor !== 'string') return null
  const text = descriptor.toLowerCase().replace(/\s+/g, ' ').trim().slice(0, 200)
  if (!text) return null
  for (const [pattern, domain] of ALIASES) if (pattern.test(text)) return domain
  const m = SPELLED.exec(text.replace(/^https?:\/\/(www\.)?/, ''))
  if (!m) return null
  const labels = m[1].split('.')
  return labels.slice(-2).join('.')
}

const DOMAIN_OK = /^(?!.*\.\.)[a-z0-9][a-z0-9.-]{1,98}\.[a-z]{2,10}$/
const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
const NEGATIVE_TTL_MS = 7 * 24 * 3600 * 1000
const DEFAULT_URL = 'https://t0.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://{domain}&size=128'

const inflight = new Map()

function dirFor() {
  const dir = process.env.LEDGER_LOGO_DIR || path.join(__dirname, '..', '.data', 'logos')
  fs.mkdirSync(dir, { recursive: true })
  return dir
}

async function fetchIcon(domain) {
  const url = (process.env.LEDGER_LOGO_URL || DEFAULT_URL).replace('{domain}', encodeURIComponent(domain))
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(8000) })
    if (!r.ok) return null
    const buf = Buffer.from(await r.arrayBuffer())
    if (buf.length < 100 || buf.length > 300_000 || !buf.subarray(0, 8).equals(PNG_MAGIC)) return null
    return buf
  } catch {
    return null
  }
}

/** The cached (or freshly fetched) PNG for a domain, or null when the service has none. */
async function iconFor(domain) {
  if (!DOMAIN_OK.test(domain)) return null
  const dir = dirFor()
  const file = path.join(dir, `${domain}.png`)
  const none = path.join(dir, `${domain}.none`)
  if (fs.existsSync(file)) return fs.readFileSync(file)
  if (fs.existsSync(none) && Date.now() - fs.statSync(none).mtimeMs < NEGATIVE_TTL_MS) return null
  if (!inflight.has(domain)) {
    inflight.set(domain, (async () => {
      const icon = await fetchIcon(domain)
      if (icon) fs.writeFileSync(file, icon, { mode: 0o644 })
      else fs.writeFileSync(none, '')
      return icon
    })().finally(() => inflight.delete(domain)))
  }
  return inflight.get(domain)
}

/** {domain, image_base64, mime_type}, or {domain: null} when the merchant has no known brand or icon. */
async function logoFor(descriptor) {
  const domain = resolveDomain(descriptor)
  if (!domain) return { domain: null }
  const icon = await iconFor(domain)
  return icon ? { domain, image_base64: icon.toString('base64'), mime_type: 'image/png' } : { domain: null }
}

module.exports = { resolveDomain, logoFor }
