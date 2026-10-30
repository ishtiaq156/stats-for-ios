import AppKit
import SwiftUI

struct CompanionSettings: View {
    @ObservedObject var model: StatsCompanionModel
    @State private var copiedPasscode = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var phoneToRevoke: PairedPhone?

    var body: some View {
        Group {
            switch model.settingsPage {
            case .home: settingsHome
            case .changelog: changelogPage
            }
        }
        .frame(width: 460, height: min(760, NSScreen.main?.visibleFrame.height ?? 760))
        .background(.regularMaterial)
        .background(SettingsWindowConfigurator())
        .alert("Revoke phone access?", isPresented: Binding(
            get: { phoneToRevoke != nil },
            set: { if !$0 { phoneToRevoke = nil } }
        )) {
            Button("Cancel", role: .cancel) { phoneToRevoke = nil }
            Button("Revoke", role: .destructive) {
                if let phoneToRevoke { model.revokePhone(phoneToRevoke.id) }
                phoneToRevoke = nil
            }
        } message: {
            Text("This phone will need to pair again before it can read your Mac's stats.")
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
    }

    private var settingsHome: some View {
        ScrollView {
            VStack(spacing: 10) {
                passcodeHeader
                    .padding(.bottom, 18)

                card {
                    networkStatusRow
                    connectionStatusRow
                    if let address = model.localAddress {
                        Divider().padding(.leading, 34)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Manual address")
                            Spacer()
                            Text(address)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 11)
                        .frame(minHeight: 28)
                    }
                }

                card {
                    updateRow
                    cardDivider
                    actionRow("Website") {
                        open("https://github.com/ishtiaq156/stats-for-ios")
                    }
                    cardDivider
                    actionRow("About") { showAbout() }
                }

                card {
                    actionRow("Changelog", symbol: "chevron.right") {
                        model.settingsPage = .changelog
                    }
                }

                card {
                    settingsToggle(
                        "Dock",
                        detail: "Show Stats Companion in the Dock alongside other apps",
                        isOn: Binding(get: { model.dockVisible }, set: { model.setDockVisible($0) }),
                        disabled: model.dockVisible && !model.menuBarVisible
                    )
                    cardDivider
                    settingsToggle(
                        "Menu Bar",
                        detail: "Stats Companion stays available in the Dock when this is off",
                        isOn: Binding(get: { model.menuBarVisible }, set: { model.setMenuBarVisible($0) }),
                        disabled: model.menuBarVisible && !model.dockVisible
                    )
                    cardDivider
                    settingsToggle(
                        "Open at login",
                        detail: nil,
                        isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }),
                        disabled: false
                    )
                }
                if let error = model.visibilityError ?? model.loginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }

                pairedPhonesSection

                HStack {
                    Button("Quit Stats Companion") { NSApp.terminate(nil) }
                    Spacer()
                    Button("Feedback & Support") {
                        open("https://github.com/ishtiaq156/stats-for-ios/issues/new")
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 72)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var passcodeHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text("Passcode")
                if let expiry = model.pairingExpires {
                    Text("·")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(expiry.timeIntervalSince(context.date)))
                        Text("Expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                            .monospacedDigit()
                    }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if let code = model.pairingCode {
                    Text(code)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .textSelection(.enabled)
                    Button {
                        copyPasscode(code)
                    } label: {
                        Image(systemName: copiedPasscode ? "checkmark" : "text.document.fill")
                            .font(.system(size: 14))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .help(copiedPasscode ? "Passcode copied" : "Copy passcode")
                    .accessibilityLabel(copiedPasscode ? "Passcode copied" : "Copy passcode")
                } else if model.pairingLocked {
                    Text("Pairing paused")
                        .font(.headline)
                    Button("New code") { model.refreshPasscode() }
                        .buttonStyle(.bordered)
                } else {
                    Text("Generating passcode…")
                        .foregroundStyle(.secondary)
                    ProgressView().controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var networkStatusRow: some View {
        let network = CompanionConnectionPresentation.network(model)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: network.symbol)
                .foregroundStyle(network.color)
                .font(.system(size: 21))
            Text(network.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var connectionStatusRow: some View {
        HStack(alignment: .top, spacing: 10) {
            let active = model.pairedPhones.filter(\.isConnected)
            Image(systemName: "iphone.circle.fill")
                .foregroundStyle(active.isEmpty ? Color.secondary : Color.green)
                .font(.system(size: 21))
            Text(active.isEmpty ? "No devices connected" : active.map(\.name).joined(separator: ", "))
                .foregroundStyle(active.isEmpty ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var updateRow: some View {
        Group {
            switch model.updateState {
            case .idle:
                actionRow("Check for updates") { model.checkForUpdates() }
            case .checking:
                statusActionRow("Checking…", spinner: true)
            case .upToDate:
                statusActionRow("Up to date", symbol: "checkmark")
            case .available(let version, let url):
                actionRow("Download version \(version)", symbol: "arrow.down.circle") {
                    NSWorkspace.shared.open(url)
                }
            case .failed:
                actionRow("Couldn’t check · Retry", symbol: "exclamationmark.circle") {
                    model.checkForUpdates()
                }
            }
        }
    }

    private var pairedPhonesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Paired phones")
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 10)
            card {
                if model.pairedPhones.isEmpty {
                    Text("No phones paired yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                } else {
                    ForEach(model.pairedPhones) { phone in
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: phone.isConnected ? "iphone.circle.fill" : "iphone")
                                .font(.system(size: 17))
                                .foregroundStyle(phone.isConnected ? Color.green : Color.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(phone.name)
                                    .font(.system(size: 13))
                                    .lineLimit(2)
                                Text(phone.isConnected ? "Connected" :
                                     (phone.lastSeen.map { "Last active \($0.formatted())" } ?? "Never active"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Revoke", role: .destructive) { phoneToRevoke = phone }
                                .buttonStyle(.bordered)
                        }
                        .padding(10)
                        if phone.id != model.pairedPhones.last?.id { cardDivider }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var changelogPage: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Changelog")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                HStack {
                    Button {
                        model.settingsPage = .home
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .accessibilityLabel("Back to Settings")
                    Spacer()
                }
                .padding(.leading, 20)
            }
            .frame(height: 45)
            .padding(.top, 70)
            .padding(.bottom, 42)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    ForEach(CompanionRelease.notes) { release in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Stats Companion \(release.version)")
                                .font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 7) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.red)
                                Text(release.date)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13))
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(release.changes, id: \.self) { change in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("•")
                                        Text(change)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.top, 3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 25)
            }
            .scrollIndicators(.visible)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 12))
    }

    private var cardDivider: some View {
        Divider().padding(.leading, 10).padding(.trailing, 10)
    }

    private func actionRow(_ title: String, symbol: String? = nil,
                           action: @escaping () -> Void) -> some View {
        SettingsActionRow(title: title, symbol: symbol, action: action)
    }

    private func statusActionRow(_ title: String, symbol: String? = nil,
                                 spinner: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            if spinner {
                ProgressView().controlSize(.small)
            } else if let symbol {
                Image(systemName: symbol)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 42)
    }

    private func settingsToggle(_ title: String, detail: String?,
                                isOn: Binding<Bool>, disabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(disabled)
        .padding(.horizontal, 10)
        .frame(minHeight: detail == nil ? 42 : 52)
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.windows.first(where: { $0.title.localizedCaseInsensitiveContains("About") })?
            .orderFrontRegardless()
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyPasscode(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copiedPasscode = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(1.5)) }
            catch { return }
            copiedPasscode = false
        }
    }
}

private struct SettingsActionRow: View {
    let title: String
    let symbol: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(hovered ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

private struct CompanionRelease: Identifiable {
    let version: String
    let date: String
    let changes: [String]
    var id: String { version }

    static let notes: [CompanionRelease] = [
        .init(version: "0.3.2", date: "October 30, 2026", changes: [
            "Reworked the Mac Settings window around the passcode, connection status, actions, and visibility controls.",
            "Refined the menu spacing, typography, separators, and passcode copy feedback.",
            "Stopped a menu bar visibility update loop that could prevent the menu from opening."
        ]),
        .init(version: "0.3.1", date: "October 30, 2026", changes: [
            "Refined the menu with pointer and keyboard row highlights, a persistent passcode, and clearer network status.",
            "Added Dock and Menu Bar controls, a fuller Settings page, and an in-app changelog.",
            "Improved update check feedback and brought the About window to the front."
        ]),
        .init(version: "0.3.0", date: "October 30, 2026", changes: [
            "Replaced shared-key QR pairing with a temporary five-digit passcode and a separate credential for each phone.",
            "Added individual phone revocation and connected-device status.",
            "Added login startup, update checks, and a port 8888 fallback."
        ]),
        .init(version: "0.2.0", date: "October 29, 2026", changes: [
            "Added recent activity charts for CPU, memory, storage, and network.",
            "The iPhone remembers the last paired Mac."
        ]),
        .init(version: "0.1.0", date: "October 29, 2026", changes: [
            "Introduced the Mac sampler, local discovery, encrypted snapshots, and the iPhone overview."
        ])
    ]
}
