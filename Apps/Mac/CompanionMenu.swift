import AppKit
import SwiftUI

private enum MenuAction: Int, CaseIterable {
    case copyPasscode
    case refreshPasscode
    case checkUpdates
    case website
    case about
    case changelog
    case openAtLogin
    case settings
    case quit
}

struct CompanionMenu: View {
    @ObservedObject var model: StatsCompanionModel
    @Environment(\.openSettings) private var openSettings
    @FocusState private var menuFocused: Bool
    @State private var keyboardSelection: MenuAction?
    @State private var hoveredAction: MenuAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            passcodeSection
            statusSection
            menuGroup {
                updateRow
                Divider().padding(.leading, 12)
                row("Website", action: .website)
                Divider().padding(.leading, 12)
                row("About", action: .about)
            }
            menuGroup {
                row("Changelog", action: .changelog, symbol: "chevron.right")
            }
            menuGroup {
                CompanionToggleRow(
                    title: "Open at login",
                    isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }),
                    highlighted: highlighted(.openAtLogin),
                    onHover: { setHover(.openAtLogin, $0) }
                )
                if let error = model.loginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .padding(.horizontal, 12).padding(.bottom, 6)
                }
                Divider().padding(.leading, 12)
                row("Settings", action: .settings, shortcut: "⌘,")
            }
            menuGroup {
                row("Quit Stats Companion", action: .quit, shortcut: "⌘Q")
            }
        }
        .padding(14)
        .frame(width: 440)
        .focusable()
        .focused($menuFocused)
        .focusEffectDisabled()
        .onAppear {
            DispatchQueue.main.async { menuFocused = true }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up: moveSelection(-1)
            case .down: moveSelection(1)
            default: break
            }
        }
        .onKeyPress(.return) {
            activateSelection()
        }
        .onKeyPress(.space) {
            activateSelection()
        }
        .onKeyPress(.escape) {
            keyboardSelection = nil
            return .handled
        }
    }

    private var passcodeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Passcode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let expiry = model.pairingExpires {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(expiry.timeIntervalSince(context.date)))
                        Text("Expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                if let code = model.pairingCode {
                    Text(code)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .textSelection(.enabled)
                    Spacer()
                    CompanionRow(
                        title: "Copy passcode",
                        symbol: "doc.on.doc",
                        iconOnly: true,
                        highlighted: highlighted(.copyPasscode),
                        onHover: { setHover(.copyPasscode, $0) }
                    ) { perform(.copyPasscode) }
                    .frame(width: 44)
                } else if model.pairingLocked {
                    Text("Pairing paused")
                        .font(.headline)
                    Spacer()
                    CompanionRow(
                        title: "Refresh passcode",
                        symbol: "arrow.clockwise",
                        iconOnly: true,
                        highlighted: highlighted(.refreshPasscode),
                        onHover: { setHover(.refreshPasscode, $0) }
                    ) { perform(.refreshPasscode) }
                    .frame(width: 44)
                } else {
                    Text("Generating passcode…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow(
                model.isDiscoverable ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                color: model.isDiscoverable ? .green : .yellow,
                text: networkStatus,
                secondary: false
            )
            let active = model.pairedPhones.filter(\.isConnected)
            if active.isEmpty {
                statusRow("exclamationmark.circle.fill", color: .yellow,
                          text: "No devices connected", secondary: true)
            } else {
                ForEach(active) { phone in
                    statusRow("checkmark.circle.fill", color: .green,
                              text: phone.name, secondary: false)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(groupBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusRow(_ symbol: String, color: Color, text: String, secondary: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(secondary ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var networkStatus: String {
        if model.isDiscoverable, let port = model.port {
            return "Discoverable on the network using port \(port)"
        }
        return model.networkError ?? "Starting local discovery…"
    }

    private var updateRow: some View {
        Group {
            switch model.updateState {
            case .idle:
                row("Check for updates", action: .checkUpdates)
            case .checking:
                CompanionRow(title: "Checking…", symbol: "progress",
                             highlighted: false, enabled: false, showsSpinner: true) {}
            case .upToDate:
                CompanionRow(title: "Up to date", symbol: "checkmark",
                             highlighted: false, enabled: false) {}
            case .available(let version, _):
                row("Update available", action: .checkUpdates, trailing: "v\(version)", symbol: "arrow.up.right")
            case .failed:
                row("Couldn’t check · Retry", action: .checkUpdates, symbol: "exclamationmark.circle")
            }
        }
    }

    private func row(_ title: String, action: MenuAction,
                     trailing: String? = nil, symbol: String? = nil, shortcut: String? = nil) -> some View {
        CompanionRow(
            title: title,
            symbol: symbol,
            trailing: shortcut ?? trailing,
            shortcutKey: action == .settings ? "," : action == .quit ? "q" : nil,
            highlighted: highlighted(action),
            onHover: { setHover(action, $0) }
        ) { perform(action) }
    }

    private var groupBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.68)
    }

    private func menuGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .padding(4)
            .frame(maxWidth: .infinity)
            .background(groupBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var navigableActions: [MenuAction] {
        var result: [MenuAction] = []
        if model.pairingCode != nil { result.append(.copyPasscode) }
        if model.pairingLocked { result.append(.refreshPasscode) }
        if model.updateState != .checking && model.updateState != .upToDate {
            result.append(.checkUpdates)
        }
        result += [.website, .about, .changelog, .openAtLogin, .settings, .quit]
        return result
    }

    private func highlighted(_ action: MenuAction) -> Bool {
        hoveredAction == action || keyboardSelection == action
    }

    private func setHover(_ action: MenuAction, _ hovering: Bool) {
        if hovering {
            hoveredAction = action
            keyboardSelection = nil
        } else if hoveredAction == action {
            hoveredAction = nil
        }
    }

    private func moveSelection(_ delta: Int) {
        let actions = navigableActions
        guard !actions.isEmpty else { return }
        hoveredAction = nil
        if let current = keyboardSelection, let index = actions.firstIndex(of: current) {
            keyboardSelection = actions[(index + delta + actions.count) % actions.count]
        } else {
            keyboardSelection = delta > 0 ? actions[0] : actions[actions.count - 1]
        }
    }

    private func activateSelection() -> KeyPress.Result {
        guard let action = keyboardSelection else { return .ignored }
        perform(action)
        return .handled
    }

    private func perform(_ action: MenuAction) {
        switch action {
        case .copyPasscode:
            guard let code = model.pairingCode else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        case .refreshPasscode:
            model.refreshPasscode()
        case .checkUpdates:
            if case .available(_, let url) = model.updateState {
                NSWorkspace.shared.open(url)
            } else {
                model.checkForUpdates()
            }
        case .website:
            open("https://github.com/ishtiaq156/stats-for-ios")
        case .about:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
            NSApp.windows.first(where: { $0.title.localizedCaseInsensitiveContains("About") })?
                .orderFrontRegardless()
        case .changelog:
            showSettings(.changelog)
        case .openAtLogin:
            model.setOpenAtLogin(!model.openAtLogin)
        case .settings:
            showSettings(.home)
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func showSettings(_ page: CompanionSettingsPage) {
        model.settingsPage = page
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async {
            NSApp.windows.first(where: { $0.title.localizedCaseInsensitiveContains("Settings") })?
                .orderFrontRegardless()
        }
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct CompanionRow: View {
    let title: String
    var symbol: String?
    var trailing: String?
    var iconOnly = false
    var shortcutKey: KeyEquivalent?
    let highlighted: Bool
    var enabled = true
    var showsSpinner = false
    var onHover: (Bool) -> Void = { _ in }
    let action: () -> Void

    @ViewBuilder var body: some View {
        if let shortcutKey {
            button.keyboardShortcut(shortcutKey, modifiers: .command)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !iconOnly {
                    Text(title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                if showsSpinner {
                    ProgressView().controlSize(.small)
                } else if let trailing {
                    Text(trailing)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: iconOnly ? 32 : 34,
                   alignment: iconOnly ? .center : .leading)
            .padding(.horizontal, iconOnly ? 0 : 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(highlighted && enabled ? Color.primary.opacity(0.11) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover(perform: onHover)
        .accessibilityLabel(title)
    }
}

private struct CompanionToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let highlighted: Bool
    let onHover: (Bool) -> Void

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).font(.system(size: 13))
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(highlighted ? Color.primary.opacity(0.11) : .clear)
        )
        .onHover(perform: onHover)
    }
}
