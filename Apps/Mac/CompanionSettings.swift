import AppKit
import SwiftUI

struct CompanionSettings: View {
    @ObservedObject var model: StatsCompanionModel

    var body: some View {
        Group {
            switch model.settingsPage {
            case .home:
                settingsHome
            case .changelog:
                changelogPage
            }
        }
        .frame(width: 520, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var settingsHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .padding(.bottom, 2)

                section("Appearance") {
                    settingsToggle(
                        "Dock",
                        detail: "Show Stats Companion in the Dock alongside other apps",
                        isOn: Binding(get: { model.dockVisible }, set: { model.setDockVisible($0) }),
                        disabled: model.dockVisible && !model.menuBarVisible
                    )
                    Divider()
                    settingsToggle(
                        "Menu Bar",
                        detail: "Stats Companion stays available in the Dock when this is off",
                        isOn: Binding(get: { model.menuBarVisible }, set: { model.setMenuBarVisible($0) }),
                        disabled: model.menuBarVisible && !model.dockVisible
                    )
                    Divider()
                    settingsToggle(
                        "Open at login",
                        detail: nil,
                        isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }),
                        disabled: false
                    )
                }
                if let error = model.visibilityError ?? model.loginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                section("Network") {
                    detailRow("Status", value: model.isDiscoverable ? "Discoverable" : (model.networkError ?? "Starting"))
                    if let address = model.localAddress {
                        Divider()
                        detailRow("Local address", value: address)
                    }
                }

                section("Paired phones") {
                    if model.pairedPhones.isEmpty {
                        Text("No phones paired yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    ForEach(model.pairedPhones) { phone in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(phone.name)
                                Text(phone.lastSeen.map { "Last active \($0.formatted())" } ?? "Never active")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Revoke") { model.revokePhone(phone.id) }
                                .buttonStyle(.bordered)
                        }
                        .padding(10)
                        if phone.id != model.pairedPhones.last?.id { Divider() }
                    }
                }

                section("More") {
                    actionRow("Check for updates", symbol: "arrow.clockwise") {
                        model.checkForUpdates()
                    }
                    if model.updateState == .checking {
                        ProgressView().controlSize(.small).padding(.horizontal, 10)
                    } else if model.updateState == .upToDate {
                        Text("Up to date").font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                    } else if case .available(let version, let url) = model.updateState {
                        Button("Version \(version) available") { NSWorkspace.shared.open(url) }
                            .padding(.horizontal, 10)
                    }
                    Divider()
                    actionRow("Website", symbol: "arrow.up.right") {
                        open("https://github.com/ishtiaq156/stats-for-ios")
                    }
                    Divider()
                    actionRow("About", symbol: "info.circle") { showAbout() }
                    Divider()
                    actionRow("Changelog", symbol: "chevron.right") {
                        model.settingsPage = .changelog
                    }
                }

                HStack {
                    Button("Quit Stats Companion") { NSApp.terminate(nil) }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Feedback & Support") {
                        open("https://github.com/ishtiaq156/stats-for-ios/issues/new")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
    }

    private var changelogPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    model.settingsPage = .home
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Back to Settings")
                Text("Changelog")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(CompanionRelease.notes) { release in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Stats Companion \(release.version)")
                                .font(.headline)
                            Label(release.date, systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(release.changes, id: \.self) { change in
                                    HStack(alignment: .top, spacing: 9) {
                                        Text("•")
                                        Text(change).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.leading, 8)
            VStack(spacing: 0, content: content)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func settingsToggle(_ title: String, detail: String?,
                                isOn: Binding<Bool>, disabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(disabled)
        .padding(10)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .font(.system(size: 13))
        .padding(10)
    }

    private func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        SettingsActionRow(title: title, symbol: symbol, action: action)
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
}

private struct SettingsActionRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovered ? Color.primary.opacity(0.1) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct CompanionRelease: Identifiable {
    let version: String
    let date: String
    let changes: [String]
    var id: String { version }

    static let notes: [CompanionRelease] = [
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
