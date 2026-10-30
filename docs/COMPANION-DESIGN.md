# Mac companion redesign

Status: accepted, 30 October 2026.

The Mac companion stays a menu bar app that samples activity for the iPhone. Its menu becomes a compact pairing and connection panel inspired by the supplied Hilium screenshot. The iPhone remains the place to read CPU, memory, storage, network, battery, and history. The interface and wording are original to Stats for iOS.

## Menu

1. **Pair new phone** opens an on-demand five-digit passcode with a copy control and an expiry countdown. The same code remains valid if the menu closes and reopens, until it expires after five minutes. One successful pairing consumes it. Three wrong attempts end the session; a new code must be started on the Mac.
2. **Network status** uses a clear success or warning indicator to report whether the companion is listening and discoverable, with the actual port. It tries port 8888 first and uses an available port if 8888 is occupied. A failure state gives a useful reason instead of claiming discoverability.
3. **Phones** uses a warning indicator when no phones are connected and shows each recently active phone by name otherwise. “Connected” means a successful stats fetch in the last ten seconds. A remembered phone outside that window is “paired,” not “connected.”
4. **Check for updates** compares the installed Mac version with the latest GitHub Release and presents the result. **Website** opens the GitHub repository until a dedicated site exists. **About** opens the native Mac About panel. **Changelog** opens GitHub Releases.
5. **Open at login** is off until the user enables it. **Settings** (`⌘,`) opens a window for paired-phone management and network status. **Quit Stats Companion** (`⌘Q`) quits the app.

Dividers separate pairing and status, links, login and settings, and Quit. The menu does not repeat the live metric dashboard. It uses a compact native macOS popover with clear status, keyboard access, VoiceOver labels, and readable text in both appearances.

## Pairing and device access

- The iPhone finds the Mac with Bonjour, or accepts a local IP address and port when discovery fails. It pairs with the temporary passcode; there is no second approval on the Mac.
- Pairing uses SPAKE2 with key confirmation, then provisions a distinct, high-entropy phone credential and identifier. The five-digit code is never used directly as the long-lived encryption key. Protocol review and interoperability tests are required before removing the old flow.
- The Mac stores a named list of paired phones and their last successful activity time. Settings revokes one phone at a time. A revoked credential cannot read metrics or history.
- Existing installations using the shared setup key must pair again. The old key and QR/manual-key flow are removed when the new protocol is released. The phone must be updated with the companion, since its current build cannot pair with a five-digit code.
- The companion remains local-network-only. Sleeping Macs cannot report live activity. Activity from a phone is established by authenticated fetches, not by mere discovery or a saved pairing.

## Delivery sequence

1. Replace the Mac menu and add real listener, discovery, and phone activity state. Add the Settings and About actions, login item, links, and update check.
2. Implement and review the SPAKE2 enrollment protocol, per-phone credentials, revocation, and migration on both platforms. Keep the existing working transport until the replacement is interoperable.
3. Test on a Mac and physical iPhone: fresh pairing, manual address, expiry, three wrong codes, one-time use, revocation, busy port, sleep/wake, update check, and accessibility.

## Nearby discovery later

Manual IP and port entry is the fallback for this redesign. Peer-to-peer Wi-Fi through Network framework can be evaluated after the new pairing flow is working. Bluetooth would need a separate discovery or transport protocol and is outside this redesign.
