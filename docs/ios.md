# The iPhone app

`ios/` is a SwiftUI app with home-screen widgets (spending, budgets, recent transactions, quick add). It talks
to your server's iPhone API (`web/api.cjs`) over Tailscale, so the phone needs Tailscale on, signed in to the
same tailnet as the server. There is no App Store build: you build it yourself and install it with your own
Apple ID. A free Apple ID works; the app then has to be re-installed every 7 days.

It builds with [xtool](https://github.com/xtool-org/xtool), which drives SwiftPM, so no Xcode project is
needed. xtool runs on macOS and Linux; on Windows it runs inside WSL (Ubuntu). The build machine doesn't have
to be the server: the app only needs the server's tailnet address.

| Your computer | Build with | Run the `.sh` scripts in |
|---|---|---|
| macOS | Xcode + xtool | Terminal |
| Linux | Swift + xtool | your shell |
| Windows | Swift + xtool inside WSL, the iPhone attached to WSL with usbipd | the WSL shell (the repo can stay on `C:`; the build copies it into WSL) |

## 1. Toolchain

- **macOS**: install Xcode once (it brings the iOS SDK), then xtool, following xtool's README.
- **Linux or WSL**: install Swift 6.x and xtool, then let `xtool setup` build the iOS SDK from an `Xcode.xip`
  you download from developer.apple.com (follow xtool's README). Two things matter for this app:
  - **Widgets**: upstream xtool's SDK toolset is missing the linker flag `-all_load`, and without it the widget
    extension links as an empty stub, so the widgets stay blank. `scripts/ios-build.sh` warns when that happens.
    The fix is to add `-all_load` to the linker flags in
    `~/.swiftpm/swift-sdks/darwin.artifactbundle/toolset-swb.json` (see xtool issue #313).
  - **USB on WSL**: attach the iPhone to WSL with [usbipd-win](https://github.com/dorssel/usbipd-win)
    (`usbipd attach --wsl --busid <id>`). If installs fail with `muxError` ("message was too large"),
    the distro's usbmuxd needs the USB/IP fix described in xtool's issues.

Apple's licence for its SDKs allows them only on Apple hardware; xtool on Linux uses the SDK from Xcode.
The Mac route avoids that question.

## 2. Your Apple ID and phone

1. `xtool auth login` with your Apple ID (a free one is fine).
2. On the iPhone: Settings > Privacy & Security > Developer Mode on (it asks once xtool has paired).
3. Plug the iPhone in, unlock it and tap Trust.

A free Apple ID allows 3 sideloaded apps on the phone at once and 10 new app IDs a week. Ledger uses two app
IDs (the app and its widgets), so choose a bundle ID once and keep it.

## 3. Point the app at your server

```bash
node scripts/ios-config.cjs --server https://<server>.<tailnet>.ts.net:8448 --bundle-id com.<yourname>.ledger
```

`node scripts/install.cjs` prints the exact server address at the end, and `node scripts/doctor.cjs` checks that
the app and widgets point at it. Without `--server` the app asks for the address at launch, but the widgets
can only use the built-in one.

## 4. Build and install

```bash
bash scripts/ios-build.sh      # build + logic checks
bash scripts/ios-install.sh    # build, sign with your Apple ID, install over USB
```

The first launch asks for Face ID (or tap Use Passcode for the iPhone passcode), then shows your accounts. If it says the Ledger API is unreachable, turn
Tailscale on on the phone.

Every 7 days (free Apple ID) the app stops opening; plug the phone in and run `scripts/ios-install.sh` again.
Your data is on the server, so nothing is lost.

## Siri, Shortcuts and widgets

Log Spending opens filled in from a `ledger://add?amount=12.50&merchant=Starbucks&category=Food&account=Cash`
link, which Siri, Shortcuts and automations can open; More > Siri & Shortcuts in the app walks through it. Add
the widgets from the home screen's edit mode; they refresh about every 30 minutes.
