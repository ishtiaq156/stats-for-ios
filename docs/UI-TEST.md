# UI acceptance checklist — Mac companion + iPhone

The Mac menu bar layout was visually accepted on October 30, 2026; the Settings window is the next UI focus. This is a **manual review for the current prototype**, not a claim that each interaction has been tested on a physical device. Record which build you used, and take screenshots of visual inconsistencies where helpful. Hide the connection passcode, IP address, and paired-device names in screenshots you share.

## Mac companion

- [ ] Open **Stats Companion** from Xcode. The menu bar icon appears once; clicking it consistently opens a compact status panel. Click outside and open it again.
- [ ] Passcode is readable in both light/dark appearances; copy and refresh icons have clear hit targets and VoiceOver labels. Copy shows short **Copied** feedback. Refresh generates a **different** five-digit code with a new five-minute countdown; the previous code no longer pairs.
- [ ] With no iPhone connected, the network row reports discoverability/port and the device row says **No devices connected**. The yellow device icon is centered with its text while the network icon remains aligned with the start of multiline status. A failed listener should show a warning and useful explanation, not a green success state.
- [ ] Compare with the Hilium menu: the Stats panel should now be about **312 points wide**, with smaller passcode digits, 13-point action labels, tight separators and short rows. Hovering Website, About, Changelog, Settings and Quit, or selecting with **Up/Down**, should show a **blue selection with white text/icons/shortcuts** instead of a gray background. Test **Return**, **Space**, **Escape**, **⌘,** and **⌘Q** (Quit last).
- [ ] **Settings** opens in front. The passcode header, network/device information, action rows, appearance controls, paired phones, and footer fit within the window without clipping. Resize/scroll on a small desktop area.
- [ ] **Changelog** opens and **Back to Settings** returns. **About** comes to the foreground. Website and Feedback & Support open their expected browser pages.
- [ ] **Dock** and **Menu Bar** controls work independently; one remains visible. Check Settings accessibility via Dock before hiding the menu bar icon. Restore your preferred visibility when finished.
- [ ] **Open at login** stays visually neutral when the pointer is over its label or switch: no blue row fill and no forced white text. The switch is aligned with the **right edge** of the menu actions and remains clickable. Arrow-key navigation should show a thin focus outline; **Space/Return** toggles it. If macOS requires approval or installation-location changes, instructions are readable. Restore your preferred setting.
- [ ] **Check for updates** displays checking, success, and retry or availability states as appropriate. Do not install an update just for this UI test.
- [ ] With a phone paired, the connection row shows the phone as active only while it is fetching stats. Settings lists it; the Revoke action is available (exercise only when you intend to re-pair).

## iPhone

- [ ] Launch **Stats** without a selected Mac. The unpaired/preview state is clearly identified; the sample readings do not look like live telemetry.
- [ ] **Add Mac** presents nearby discovery and a manual IP/port fallback. Pairing instructions match the actual Mac menu, and the five-digit code is easy to enter.
- [ ] A wrong/expired code produces useful error text; retry is possible. With a correct code, the selected Mac appears and metrics update.
- [ ] On the overview, CPU, Memory, Storage, and Network use consistent card insets, icon sizes, text hierarchy, chevrons and rounding. Units and progress bars agree with the displayed labels (notably storage used vs free).
- [ ] Each metric card opens its own detail page; the value, unit, recent chart, row labels and time stamp are legible. Wait for two samples before assessing the network throughput and line chart.
- [ ] Disconnect the Mac or briefly move the phone off the local network. A stale reading should have a clear **Disconnected** status rather than appearing fresh; reconnecting should restore live updates.
- [ ] Repeat in **Light/Dark**, larger iOS text, narrow portrait layout, and with VoiceOver. No truncation, overlapping controls, or inaccessible icon-only buttons.

## Report feedback

When something differs from the intended layout, send the **screen**, **appearance** (light/dark), **device or window size**, **steps to reproduce**, **actual result**, and **expected result**. Screenshot comparisons with Hilium are especially useful for exact padding, font size, order, shadow, blur, and separators.

Use any remaining findings to guide the next Settings-window and physical-iPhone testing round.
