// What scripts/install.cjs and scripts/doctor.cjs need to know about this computer: macOS, Linux or Windows.
const fs = require('node:fs')
const path = require('node:path')
const { execFileSync } = require('node:child_process')

const OS = { darwin: 'macos', linux: 'linux', win32: 'windows' }[process.platform] || process.platform

// An executable: PATH first (with Windows' PATHEXT), then the first of `extra` that exists.
function which(name, extra = []) {
  const exts = OS === 'windows' ? ['', ...(process.env.PATHEXT || '.EXE;.CMD;.BAT').toLowerCase().split(';')] : ['']
  const dirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean)
  const isExe = (p) => {
    try {
      if (!fs.statSync(p).isFile()) return false
      if (OS !== 'windows') fs.accessSync(p, fs.constants.X_OK)
      return true
    } catch { return false }
  }
  return [...dirs.flatMap((d) => exts.map((e) => path.join(d, name + e))), ...extra].find(isExe) || null
}

// The Tailscale CLI, which the macOS and Windows apps don't always put on PATH.
const tailscale = () => which('tailscale', [
  '/Applications/Tailscale.app/Contents/MacOS/Tailscale',
  path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Tailscale', 'tailscale.exe'),
])

// A command's stdout, or null when it is missing or fails. Fixed argv, no shell.
function run(cmd, args, timeout = 15000) {
  if (!cmd) return null
  try { return execFileSync(cmd, args, { encoding: 'utf8', timeout, stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true }) } catch { return null }
}

// This machine's tailnet name ("myserver.tail1234.ts.net") and IPv4, or null when Tailscale isn't up.
function tailnet() {
  const out = run(tailscale(), ['status', '--json'])
  let s = null
  try { s = out && JSON.parse(out) } catch {}
  if (s?.BackendState !== 'Running' || !s.Self?.DNSName) return { state: s?.BackendState || (out ? 'unknown' : null) }
  return { state: 'Running', dns: s.Self.DNSName.replace(/\.$/, ''), ip: s.Self.TailscaleIPs?.find((a) => a.includes('.')) }
}

module.exports = { OS, which, tailscale, run, tailnet }
