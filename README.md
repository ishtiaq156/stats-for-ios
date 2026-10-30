# Stats for iOS

**See your Mac's activity from your iPhone.** Stats is a native iPhone dashboard paired with a lightweight macOS menu bar companion. Both apps communicate on your local network without an account or cloud service.

> [!NOTE]
> **Early prototype.** The macOS menu bar interface has been reviewed hands-on; the Settings window is next. Automated pairing tests pass, but the current five-digit passcode flow still needs an end-to-end physical-iPhone check before a public release.

## What it does

- **Live Mac activity:** CPU utilization, memory usage, free and total startup-disk space, and network download/upload rates.
- **iPhone overview and charts:** Four metric cards, detail screens, recent readings, and clear sample, connecting, live, and disconnected states.
- **Compact Mac menu:** Network and connected-phone status, a five-digit passcode with copy, refresh, and expiry, Open at login, updates, and Settings.
- **Local pairing:** Bonjour discovery plus manual IP/port fallback; a different encrypted credential is issued to every paired phone, which can be revoked independently.
- **Battery data where available:** Included in the Mac's snapshot; a dedicated battery card is not yet part of the iPhone overview.

The project takes inspiration from [Stats](https://github.com/exelban/stats) for metric coverage and from Hilium and Mirage for the companion experience. The UI and implementation are original; no Stats source has been copied into the project.

## Requirements

| Component | Minimum / tool |
| --- | --- |
| Mac companion | macOS 14+ |
| iPhone dashboard | iOS 17+ |
| Development | Xcode 27.1+, Swift 5.10; XcodeGen for regenerating the project |
| Connection | Mac and iPhone on the same reachable local network |
| iPhone installation | Xcode signing with a free Personal Team is supported |

## Get started

1. Open **`StatsForIOS.xcodeproj`** in Xcode. Run the **`StatsCompanion`** scheme on your Mac and open **Stats Companion** from the menu bar.
2. Select the **`Stats`** scheme, choose your iPhone, configure your **Personal Team** for signing, and run it. Allow **Local Network** access when prompted.
3. On iPhone, choose **Connect a Mac** (or **Add Mac**). Select the discovered Mac, then enter the **five-digit passcode** shown at the top of the Mac menu. If discovery fails, expand **Connect using IP address** and enter the Mac's local IP, the advertised port, and its passcode.
4. View live CPU, Memory, Storage, and Network values. Tap any card for details and recent history.

The passcode lasts five minutes; the **refresh** icon generates a different code and immediately invalidates the old one. One successful pairing also consumes the code. Three failed attempts pause pairing until refresh. The Mac remembers each paired phone, and **Settings** lets you revoke individual access.

> [!TIP]
> Stats Companion tries TCP port **8888** first and chooses an available port if it is occupied. Use the port shown in the menu or Settings for manual pairing. For **Open at login**, install the built Mac app in Applications before enabling the setting.

## Build and test

Choose the appropriate Xcode in `xcode-select`, or set `DEVELOPER_DIR` if you keep Xcode outside Applications (for example, `/Volumes/SSD WD/Applications/Xcode.app/Contents/Developer`).

```sh
# Run when sources are added/removed or project.yml changes.
xcodegen generate

# Build without a signing identity.
xcodebuild -project StatsForIOS.xcodeproj -scheme StatsCompanion -sdk macosx CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StatsForIOS.xcodeproj -scheme Stats -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StatsForIOS.xcodeproj -scheme Stats -sdk iphoneos CODE_SIGNING_ALLOWED=NO build

# Packet, pairing, encryption, and end-to-end local pairing checks.
swift test --package-path Packages/ActivityCore
scripts/test-pairing-smoke.sh
```

XcodeGen reads [`project.yml`](project.yml). The shared Swift package includes a prebuilt SPAKE2 XCFramework. To rebuild it from pinned Rust dependencies, use `scripts/build-spake2.sh` and the [Rust dependency notices](Native/Spake2Bridge/THIRD_PARTY_NOTICES.md).

## How it works

| Part | Responsibility |
| --- | --- |
| [`Apps/Mac`](Apps/Mac) | Menu bar UI, macOS metrics sampler, Bonjour advertisement, authenticated TCP service, paired-phone registry |
| [`Apps/Phone`](Apps/Phone) | Discovery and pairing, Keychain credential storage, overview and detail screens, recent-history charts |
| [`Packages/ActivityCore`](Packages/ActivityCore) | Versioned metric snapshots, packet framing, AES-GCM protection, and SPAKE2 pairing exchange |
| [`Native/Spake2Bridge`](Native/Spake2Bridge) | Pinned Rust implementation and Swift-compatible FFI |
| [`Tests`](Tests) | Local pairing smoke test, including code rotation, authenticated metric fetch, and phone revocation |

The Mac samples about every **two seconds** and holds approximately **30 minutes** of readings in memory. The iPhone requests encrypted snapshots and history from the selected Mac. Passcode pairing derives a temporary session key using SPAKE2; the Mac then issues a distinct 256-bit phone credential stored in Keychain. Subsequent requests use AES-GCM authenticated encryption. Phones paired before the version 0.3 passcode redesign must pair again.

## Current limitations

- Local-network access only. Bonjour may be blocked by guest Wi-Fi, firewall configuration, or iOS privacy settings; manual IP/port pairing is the fallback.
- The Mac companion must be running in a logged-in session. Sleep stops live reporting; restart clears the in-memory history.
- CPU and network rates require two samples, so the first reading may be unavailable. Battery values depend on the Mac hardware.
- iOS background monitoring, widgets, alerts, extra sensors, and remote access are future work.
- Update checks use GitHub Releases and open the release page; automatic in-app installation is not implemented.
- Free Personal Team signing generally requires rebuilding and reinstalling the iPhone app after seven days. TestFlight and App Store distribution require paid developer enrollment.
- The pairing implementation needs an independent protocol review and physical-device testing before public deployment. See [security guidance](SECURITY.md).

For the next round of UI work and verification, see the [UI test checklist](docs/UI-TEST.md), [Mac companion design](docs/COMPANION-DESIGN.md), [pairing decision](docs/adr/0001-passcode-pairing.md), and [roadmap](PLAN.md).
