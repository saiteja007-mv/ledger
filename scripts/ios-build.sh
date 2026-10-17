#!/usr/bin/env bash
# Build the Ledger iPhone app with xtool (Linux, WSL or macOS; no Xcode needed). No signing, no install:
# `ios-install.sh` does that. Run scripts/ios-config.cjs first so the app knows your server and bundle ID.
#   bash scripts/ios-build.sh
# On WSL with the repo on a Windows drive (/mnt/...), the app is mirrored to ~/.cache/ledger-ios first,
# because building on /mnt is slow and unreliable. Anywhere else it builds in ios/ itself.
set -euo pipefail
export PATH="$HOME/swift/usr/bin:$HOME/.local/bin:$PATH"
umask 077
command -v swift >/dev/null || { echo "swift is missing: install the Swift toolchain (docs/ios.md)"; exit 1; }
command -v xtool >/dev/null || { echo "xtool is missing: install it (docs/ios.md)"; exit 1; }

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$REPO/ios"
case "$SRC" in
  /mnt/*)
    DEST=~/.cache/ledger-ios
    mkdir -p "$DEST"
    # Mirror the sources; build dirs survive for incremental builds.
    rsync -a --delete --exclude .build --exclude .swiftpm --exclude xtool --exclude build.log --exclude logic.log "$SRC"/ "$DEST"/
    # A Windows editor may have written CRLF.
    find "$DEST" \( -path "$DEST/.build" -o -path "$DEST/xtool" \) -prune -o -type f \
      \( -name '*.swift' -o -name '*.plist' -o -name '*.yml' -o -name '*.json' \) -exec sed -i 's/\r$//' {} +
    ;;
  *) DEST="$SRC" ;;
esac

cd "$DEST"
grep -q '<key>LedgerServerURL</key>' Info.plist || { echo "Info.plist has no LedgerServerURL"; exit 1; }
ulimit -n 65536 2>/dev/null || true
echo "building Ledger in $DEST ..."
set +e; xtool dev build > build.log 2>&1; rc=$?; set -e
grep -E 'error:|warning:' build.log | sort -u | head -60 || true
[ $rc -eq 0 ] || { echo "BUILD FAILED (exit $rc). Log: $DEST/build.log"; exit $rc; }
# Count each diagnostic once (the compiler also prints it again under a source excerpt).
errors=$( (grep -E '^/[^ ]+:[0-9]+:[0-9]+: error:' build.log || true) | sort -u | wc -l)
warnings=$( (grep -E '^/[^ ]+:[0-9]+:[0-9]+: warning:' build.log || true) | sort -u | wc -l)
[ -x xtool/Ledger.app/Ledger ] || { echo "BUILD FAILED: xtool/Ledger.app/Ledger missing"; exit 1; }
[ -d xtool/Ledger.app/PlugIns/LedgerWidgets.appex ] || { echo "BUILD FAILED: LedgerWidgets.appex is not in the app"; exit 1; }
# Upstream xtool's SDK toolset lacks -all_load, and then the widget extension links as an empty stub.
if command -v llvm-objdump >/dev/null && ! llvm-objdump --macho -h xtool/Ledger.app/PlugIns/LedgerWidgets.appex/LedgerWidgets | grep -q __text; then
  echo "WARNING: the widget extension is empty, so the widgets will be blank. Add -all_load to your xtool SDK toolset (docs/ios.md, Widgets)."
fi

# Logic check: the Foundation-only model files plus Checks/, built for this machine and run.
M=Sources/Ledger
mkdir -p .build
swiftc -o .build/ledger-logic-check Checks/main.swift Checks/LinuxShim.swift \
  $M/Shared/LedgerDate.swift $M/Shared/Money.swift $M/API/JSONValue.swift $M/API/Envelope.swift $M/API/ServerConfig.swift \
  $M/Models/LedgerTransaction.swift $M/Models/Direction.swift $M/Models/NewTransaction.swift \
  $M/Models/TransactionFilter.swift $M/Models/TransactionPeriod.swift $M/Models/NetWorth.swift \
  $M/Models/NetWorthGroup.swift $M/Models/AccountBalance.swift $M/Models/BalanceAnchor.swift \
  $M/Models/CategoryPeriod.swift $M/Models/CategoryScope.swift $M/Models/CategoryTotal.swift \
  $M/Models/TransactionList.swift $M/Models/TransactionPaging.swift $M/Models/SpendingSummary.swift \
  $M/Models/MerchantLogo.swift $M/Models/TransferRoute.swift $M/Models/CategoryName.swift $M/Models/QuickLog.swift \
  Sources/LedgerWidgets/WidgetModels.swift \
  > logic.log 2>&1 || { cat logic.log; echo "LOGIC CHECK DID NOT COMPILE"; exit 1; }
.build/ledger-logic-check || { echo "LOGIC CHECK FAILED"; exit 1; }

echo "BUILD OK: $DEST/xtool/Ledger.app ($errors errors, $warnings warnings)"
