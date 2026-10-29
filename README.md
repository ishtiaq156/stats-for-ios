# Mac Activity

Native macOS menu bar companion and iPhone dashboard for local system activity. This is an early, working build: the Mac samples CPU, memory, startup disk capacity, network throughput, and battery where available. The iPhone discovers the Mac on the same network and reads encrypted snapshots after pairing.

Inspired by the metric coverage of [Stats](https://github.com/exelban/stats) and the pairing experience of Hilium and Mirage. The app and its UI are original; no Stats source is currently copied into this repository.

## Build

Xcode 27.1 is installed at `/Volumes/SSD WD/Applications/Xcode.app`. Open `MacActivity.xcodeproj` and select either `MacActivityMac` or `MacActivityPhone`. If command line tools are active, set `DEVELOPER_DIR` for command-line builds:

```sh
export DEVELOPER_DIR='/Volumes/SSD WD/Applications/Xcode.app/Contents/Developer'
xcodebuild -project MacActivity.xcodeproj -scheme MacActivityMac -sdk macosx CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MacActivity.xcodeproj -scheme MacActivityPhone -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

The project is generated from `project.yml` with XcodeGen. Run `xcodegen generate` after adding or removing source files or changing target settings.

## Pair locally

1. Run **MacActivityMac** from Xcode. Its chart icon appears in the menu bar. Leave it running.
2. Run **MacActivityPhone** on an iPhone on the same Wi-Fi. In Xcode, select your free **Personal Team** for the phone target and let Xcode manage signing. The first launch asks for Local Network access; allow it.
3. Tap **Add Mac**, choose the nearby Mac, then scan the QR code shown in the Mac menu or paste its setup key. Camera access is requested only when scanning.
4. The overview changes from labeled sample values to the Mac's readings. A failed connection displays a connection message instead of sample numbers.

The setup key is a 256-bit secret stored in each device's Keychain. Snapshot requests and responses use AES-GCM authenticated encryption over the local TCP connection. Anyone with the setup key can read metrics, so treat the QR code and copied key as private. **Revoke all paired phones** on the Mac rotates the key. This first version uses a shared key for all paired phones; per-phone revocation and a polished verification step are still planned.

## Current limits

- Discovery requires Bonjour on the same local network. Some guest Wi-Fi networks block it. Manual address entry is not implemented yet.
- The Mac companion must run in a logged-in session. Sleeping Macs stop sampling.
- Values refresh every two seconds while the phone app runs. iOS background execution and widgets are separate work.
- CPU and network rates need two samples, so they show a dash briefly after launch.
- The Mac stores no history yet. Detail charts, alerts, sensors, and remote access are future work.
- Free Personal Team provisioning expires after seven days; rebuild and reinstall from Xcode when needed. TestFlight and App Store distribution require paid enrollment.

See [PLAN.md](PLAN.md) for the roadmap.
