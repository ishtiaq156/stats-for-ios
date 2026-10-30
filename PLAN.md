# Stats for iOS — working plan

## Goal

See the current health and activity of one or more Macs from an iPhone: CPU, memory, storage, network, and battery at a glance, with deeper history when opened. The first release works on the same local network, requires no account or server, and is installable through Xcode with a free Apple Personal Team.

## Product shape

- **Mac companion:** a small menu bar app that samples system metrics, advertises itself on the local network, and serves data only to paired phones. It launches at login after the user enables that setting.
- **iPhone app:** a native SwiftUI app with a device picker, live overview, detail screens, and a pairing flow. The phone never needs privileged access to macOS.
- **Shared protocol:** versioned metric snapshots with timestamps, units, and explicit unavailable values. A rolling history is kept locally on the Mac; the phone requests recent history when a detail screen opens.

## First usable version

1. **Vertical slice:** Mac companion reads CPU, memory, disk capacity/free space, network throughput, and battery where present; iPhone discovers the Mac, pairs, and shows a live overview. Sampling starts at 2 seconds while viewed and slows when idle. Values include a “last updated” timestamp; disconnected and sleeping Macs are shown clearly.
2. **Pairing:** the Mac shows a QR code containing its identity fingerprint and a high-entropy one-time setup secret. Bonjour finds nearby Macs. The iPhone confirms the Mac name and a short code shown on both devices. The QR data authenticates the encrypted setup connection; long-lived device credentials go in Keychain. The Mac has a list of paired phones and a revoke action. Manual address entry with the full setup key is a fallback for networks where Bonjour is blocked.
3. **Detail:** CPU use and per-core activity; memory pressure and used/free; disk volume capacity and read/write rates; network upload/download and interface; battery charge, charging state, and health when available. Small charts show recent samples. Each metric has consistent units and a clear empty/unavailable state.
4. **Polish:** multiple Macs, reorderable overview cards, light/dark mode, Dynamic Type, VoiceOver labels, reduced motion, reconnect behavior, and permission/error guidance.

## Architecture choices

- **Native Swift/SwiftUI** for both apps; a shared Swift package for metric models, wire messages, and unit formatting.
- **Stats as a reference for collectors**, especially CPU, disk, network, battery, and sensor edge cases. Reuse selected MIT-licensed code only where it reduces work, retaining its copyright and license notice. Keep our app and user interface distinct. Review the installed Stats app and source before choosing exact collectors.
- **Network framework + Bonjour** for local discovery and transport. Declare local network usage and the specific Bonjour service in the iPhone app. The first implementation uses a QR-delivered 256-bit setup key and AES-GCM authenticated encryption. A later security pass should give each phone a distinct credential and assess forward secrecy; the current Mac action revokes all phones by rotating the shared key.
- **Mac owns history** so the iPhone can reconnect and retrieve the last few hours without running continuously in the background. Limit storage and allow clearing it.
- **No cloud in the first release.** The domain is reserved for a possible later website or relay; it is not needed for local viewing. A user-managed VPN such as Tailscale can be evaluated for remote viewing before operating our own service.

## UX direction

- Take inspiration from Hilium and Mirage’s nearby-device discovery, clear device identity, short pairing steps, and connection feedback. Build original visuals and copy.
- Pairing flow: **Find Mac → verify code → connected overview**. Show what the companion is sharing before confirmation. Keep a visible retry and manual-address path.
- Overview: Mac name, connection state, last sample time, then four prominent cards (CPU, memory, storage, network). Tapping a card opens its chart and detail. Battery appears when applicable. Avoid presenting a stale value as live.
- Use restrained motion and native controls; make charts legible at a glance rather than copying a desktop monitoring dashboard onto a phone.

## Delivery gates

| Gate | Done when |
| --- | --- |
| Toolchain | Xcode project builds for Mac, iOS simulator, and a physical iPhone with free signing. |
| Metrics | Each collector is checked against macOS’s own readings; missing sensors do not break snapshots. |
| Pairing | A new phone pairs in under a minute on a normal LAN; an unpaired client receives no metrics; revocation works. |
| Reliability | Reconnects after app relaunch, Wi-Fi change, Mac sleep/wake; stale data is labeled. |
| Usability | Overview and pairing work in light/dark mode, larger text, and VoiceOver. |
| Release | Reproducible local build and installation instructions, with the seven-day free provisioning refresh documented. |

## Later, only after the local version works

- Remote access outside the LAN; choose VPN first and assess a hosted relay only if needed.
- GPU, temperatures, fans, process list, configurable alerts, and widgets. These require separate performance, permission, and accuracy checks. iOS widgets cannot provide continuously live numbers.
- Paid Apple Developer membership only if distribution or a required capability cannot be achieved with free signing. TestFlight and App Store release require membership.

## Known constraints and decisions to validate

- The Mac companion must be running in a logged-in user session to sample; Mac sleep stops live updates.
- Free Personal Team provisioning expires after seven days and requires rebuilding/reinstalling the iPhone app. Current Apple limits also apply to App IDs, devices, and installed apps.
- iOS normally suspends apps in the background. The live screen updates while the app is open; background widgets/alerts are a separate design problem.
- Decide the oldest supported iOS/macOS versions and confirm the target iPhone model before setting deployment targets. Initial assumption: iOS 17+ and macOS 14+.
- Inspect Mirage’s pairing screens from the user’s local IPA only if public screenshots and hands-on use do not give enough detail; use observations for UX, not its code or assets.

## Next release focus

Compare displayed values with macOS's own readings, polish reconnection and pairing, then add per-phone credentials and revocation. Evaluate remote access only after local behavior is reliable.

## Progress — 29 October 2026

- Xcode project, shared package, Mac sampler, iPhone overview, Bonjour discovery, encrypted local snapshot transport, QR setup code, and Keychain storage are implemented.
- Both targets build for Mac/iOS simulator, and the iPhone target builds for iOS device with signing disabled. The simulator overview has been visually checked.
- A manual address fallback is implemented. Bonjour publication was verified, and the user confirmed live readings on a physical iPhone through LiveContainer. Shared packet tests cover decryption, wrong keys, tampering, and frame bounds. Per-phone revocation and remote access remain open.
- Version 0.2 adds 30 minutes of in-memory history on the Mac, detail charts on iPhone, and reopening the last paired Mac. The new history request still needs a physical-iPhone check.
