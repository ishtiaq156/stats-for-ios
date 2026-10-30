# Stats for iOS

Native macOS menu bar companion and iPhone dashboard for local system activity. This is an early prototype: the Mac samples CPU, memory, startup disk capacity, network throughput, and battery where available. The iPhone can discover the Mac on the same network or connect by local address, then read encrypted snapshots after pairing. The earlier QR pairing worked on a physical iPhone through LiveContainer; version 0.3's passcode pairing still needs that check.

Inspired by the metric coverage of [Stats](https://github.com/exelban/stats) and the pairing experience of Hilium and Mirage. The app and its UI are original; no Stats source is currently copied into this repository.

## Build

Xcode 27.1 is installed at `/Volumes/SSD WD/Applications/Xcode.app`. Open `StatsForIOS.xcodeproj` and select either `StatsCompanion` or `Stats`. If command line tools are active, set `DEVELOPER_DIR` for command-line builds:

```sh
export DEVELOPER_DIR='/Volumes/SSD WD/Applications/Xcode.app/Contents/Developer'
xcodebuild -project StatsForIOS.xcodeproj -scheme StatsCompanion -sdk macosx CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StatsForIOS.xcodeproj -scheme Stats -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

The project is generated from `project.yml` with XcodeGen. Run `xcodegen generate` after adding or removing source files or changing target settings. The SPAKE2 bridge is included as a local XCFramework. To rebuild it from the pinned Rust source and lockfile, run `scripts/build-spake2.sh`. Dependency licenses are in [the Rust bridge notices](Native/Spake2Bridge/THIRD_PARTY_NOTICES.md).

The shared packet and pairing tests run with:

```sh
swift test --package-path Packages/ActivityCore
scripts/test-pairing-smoke.sh
```

## Pair locally

1. Run **StatsCompanion** from Xcode. **Stats Companion** appears in the menu bar. Leave it running.
2. Run **Stats** on an iPhone on the same Wi-Fi. In Xcode, select your free **Personal Team** for the phone target and let Xcode manage signing. Tapping **Add Mac** asks for Local Network access; allow it.
3. Read the five-digit passcode at the top of the Mac menu and enter it in **Add Mac** on iPhone. If discovery is blocked, enter the local IP address and actual port shown in the companion's Settings, along with the passcode.
4. The overview changes from labeled sample values to the Mac's readings. Tap a metric for its recent chart and details. A failed connection displays a connection message instead of sample numbers.

The passcode expires after five minutes and is refreshed automatically; one successful pairing consumes it. Three unsuccessful attempts pause pairing until a new code is requested on the Mac. SPAKE2 derives a temporary pairing key; the Mac then issues a distinct 256-bit credential for each phone. Credentials are stored in Keychain and metric requests use AES-GCM authenticated encryption. The companion's Settings lists each phone and lets you revoke it. Phones paired with version 0.2 must pair again. This protocol uses the open-source RustCrypto SPAKE2 crate, which has not received an independent security audit; the implementation still needs protocol and physical-device review before a public release.

## Current limits

- Bonjour discovery may be blocked by guest Wi-Fi or local network privacy settings. Manual address entry is available on the same network.
- The Mac companion must run in a logged-in session. Sleeping Macs stop sampling.
- Values refresh every two seconds while the phone app runs. iOS background execution and widgets are separate work.
- CPU and network rates need two samples, so they show a dash briefly after launch.
- The Mac keeps about 30 minutes of readings in memory. Restarting Stats Companion clears that history. Alerts, sensors, and remote access are future work.
- Update checks use GitHub Releases. An available version opens its release page for download; automatic in-app installation needs a signed release feed and updater integration.
- Free Personal Team provisioning expires after seven days; rebuild and reinstall from Xcode when needed. TestFlight and App Store distribution require paid enrollment.

See [PLAN.md](PLAN.md) for the roadmap.
