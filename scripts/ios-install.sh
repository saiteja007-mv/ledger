#!/usr/bin/env bash
# Build, sign with your Apple ID and install on your iPhone over USB (xtool). Run it again every 7 days:
# a free Apple ID signs apps for a week. The phone must be plugged in, unlocked and trusting this computer.
#   bash scripts/ios-install.sh
# First time only: `xtool auth login` with your Apple ID (docs/ios.md).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash "$HERE/ios-build.sh"
export PATH="$HOME/swift/usr/bin:$HOME/.local/bin:$PATH"
SRC=$(cd "$HERE/../ios" && pwd)
case "$SRC" in /mnt/*) DEST=~/.cache/ledger-ios ;; *) DEST="$SRC" ;; esac
xtool devices --usb --no-wait 2>/dev/null | grep -q . \
  || { echo "No iPhone found over USB. Plug it in, unlock it, tap Trust (WSL: usbipd attach, see docs/ios.md)."; exit 1; }
cd "$DEST"
xtool dev run --usb < /dev/null
echo "Installed. On the phone: Settings > General > VPN & Device Management > trust your Apple ID once."
