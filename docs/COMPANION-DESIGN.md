# Mac companion redesign

Status: accepted, 30 October 2026.

The Mac companion stays a menu bar app that samples activity for the iPhone. Its menu becomes a compact pairing and connection panel inspired by the supplied Hilium screenshot. The iPhone remains the place to read CPU, memory, storage, network, battery, and history. The interface and wording are original to Stats for iOS.

## Menu

1. **Passcode** is always shown at the top of the menu with copy and refresh controls and an expiry countdown. The refresh control immediately replaces the active code with a different five-digit code and resets its five-minute expiry; the previous code stops working. It also rotates after five minutes or one successful pairing. Three wrong attempts pause pairing until the Mac user refreshes the code.
2. **Network status** uses a clear success or warning indicator to report whether the companion is listening and discoverable, with the actual port. It tries port 8888 first and uses an available port if 8888 is occupied. A failure state gives a useful reason instead of claiming discoverability.
3. **Phones** uses a warning indicator when no phones are connected and shows each recently active phone by name otherwise. “Connected” means a successful stats fetch in the last ten seconds. A remembered phone outside that window is “paired,” not “connected.”
4. **Check for updates** compares the installed Mac version with the latest GitHub Release and presents checking and up-to-date states inline. An available version links to its release page until a signed update feed supports in-app installation. **Website** opens the GitHub repository until a dedicated site exists. **About** opens the native Mac About panel in front. **Changelog** opens the scrollable release-notes page in Settings.
5. **Open at login** is off until the user enables it. **Settings** (`⌘,`) opens a window with the passcode and connection status first, followed by updates, links, Dock, Menu Bar, login, paired-phone management, and support. **Quit Stats Companion** (`⌘Q`) quits the app. Dock and Menu Bar cannot both be hidden.

Dividers separate pairing and status, links, login and settings, and Quit. The menu does not repeat the live metric dashboard. It uses a compact native macOS popover with hover and keyboard row highlights, VoiceOver labels, and readable text in both appearances.

For the compact-menu visual pass, the status panel is 312 points wide with 13-point menu labels, 26-point action rows, tighter separators, and a 30-point passcode. These dimensions are tuned against the supplied Hilium screenshot. Hovering or keyboard-selecting an action uses macOS's selected-content blue background and selected-menu-item white text, including on its shortcut or icon. The smaller native **Open at login** switch stays unfilled on pointer hover; keyboard navigation uses a thin focus outline rather than the action-row highlight.

The no-device icon is vertically centered with its single-line label while the network indicator stays aligned to the first line when its status wraps. The login switch is pinned to the trailing menu inset. A small refresh icon sits beside the passcode copy action and is reachable with arrow keys.

## Pairing and device access

- The iPhone finds the Mac with Bonjour, or accepts a local IP address and port when discovery fails. It pairs with the temporary passcode; there is no second approval on the Mac.
- Pairing uses SPAKE2 with key confirmation, then provisions a distinct, high-entropy phone credential and identifier. The five-digit code is never used directly as the long-lived encryption key. Protocol review and physical-device tests remain necessary before a public release.
- The Mac stores a named list of paired phones and their last successful activity time. Settings revokes one phone at a time. A revoked credential cannot read metrics or history.
- Existing installations using the shared setup key must pair again. The old key and QR/manual-key flow have been removed. The phone must run a passcode-capable build of Stats.
- The companion remains local-network-only. Sleeping Macs cannot report live activity. Activity from a phone is established by authenticated fetches, not by mere discovery or a saved pairing.

## Verification

The pairing smoke test covers enrollment, authenticated metric fetches, and revocation. The Mac release build and code signature have been checked. Manual checks remain for pointer and keyboard navigation, About and Settings window order, Dock and Menu Bar visibility, update feedback, and physical iPhone pairing.

## Nearby discovery later

Manual IP and port entry is the fallback for this redesign. Peer-to-peer Wi-Fi through Network framework can be evaluated after the new pairing flow is working. Bluetooth would need a separate discovery or transport protocol and is outside this redesign.
