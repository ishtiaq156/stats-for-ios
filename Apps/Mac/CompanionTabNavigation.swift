import AppKit
import SwiftUI

/// Captures the physical Tab key before AppKit converts Shift-Tab into
/// insertBacktab:, which SwiftUI's .onKeyPress(.tab) can miss.
///
/// The monitor belongs to an invisible view in a *single* window. Other app
/// windows, system shortcuts, and other applications retain normal key input.
struct CompanionTabNavigation: NSViewRepresentable {
    /// Return false when a native popover or other control should handle Tab.
    let onTab: (_ backward: Bool) -> Bool
    /// Return false to preserve native activation when no row is selected.
    let onActivate: () -> Bool
    /// Pointer interaction is informational: it must never swallow the event.
    var onPointer: () -> Void = {}

    func makeNSView(context: Context) -> TabMonitorView {
        let view = TabMonitorView()
        view.onTab = onTab
        view.onActivate = onActivate
        view.onPointer = onPointer
        return view
    }

    func updateNSView(_ view: TabMonitorView, context: Context) {
        view.onTab = onTab
        view.onActivate = onActivate
        view.onPointer = onPointer
    }

    static func dismantleNSView(_ view: TabMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class TabMonitorView: NSView {
    var onTab: ((_ backward: Bool) -> Bool)?
    var onActivate: (() -> Bool)?
    var onPointer: (() -> Void)?
    private var monitor: Any?
    private var consumedActivationKeyCode: UInt16?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown
        ]) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window else {
                return event
            }
            if event.type != .keyDown {
                self.onPointer?()
                return event
            }
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                return event
            }
            switch event.keyCode {
            case 48: // Hardware Tab, including Shift-Tab/insertBacktab:.
                return self.onTab?(event.modifierFlags.contains(.shift)) == true ? nil : event
            case 36, 76, 49: // Return, keypad Enter, Space.
                // Keep text selection/editing semantics native, even if a
                // previously keyboard-selected action is still remembered.
                if window.firstResponder is NSTextView { return event }
                if event.isARepeat {
                    // Don't let a held Space/Return trigger a second action
                    // through the SwiftUI responder after we consumed it.
                    return self.consumedActivationKeyCode == event.keyCode ? nil : event
                }
                let handled = self.onActivate?() == true
                self.consumedActivationKeyCode = handled ? event.keyCode : nil
                return handled ? nil : event
            default:
                return event
            }
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
