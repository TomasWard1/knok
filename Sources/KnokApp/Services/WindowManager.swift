// PLACEHOLDER — to be implemented by agent
import AppKit
import SwiftUI
import KnokCore

@MainActor
final class WindowManager {
    private var activeWindows: [NSWindow] = []

    func showAlert(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) {
        switch payload.level {
        case .whisper:
            showWhisper(payload: payload, completion: completion)
        case .nudge:
            showNudge(payload: payload, completion: completion)
        case .knock:
            showKnock(payload: payload, completion: completion)
        case .break:
            showBreak(payload: payload, completion: completion)
        }
    }

    func dismissAll() {
        for window in activeWindows {
            window.close()
        }
        activeWindows.removeAll()
    }

    // MARK: - Whisper (menu bar flash)

    private func showWhisper(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) {
        // Whisper shows a small floating panel near the menu bar
        let view = WhisperView(payload: payload) {
            completion(.dismissed)
        }
        let panel = makePanel(
            content: view,
            level: .floating,
            size: NSSize(width: 320, height: 80)
        )
        positionNearMenuBar(panel)
        showAndTrack(panel)

        // Auto-dismiss whisper after 5 seconds if no TTL set
        let ttl = payload.ttl > 0 ? payload.ttl : 5
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(ttl)) { [weak self] in
            if self?.activeWindows.contains(where: { $0 === panel }) == true {
                panel.close()
                self?.activeWindows.removeAll { $0 === panel }
                completion(.timeout)
            }
        }
    }

    // MARK: - Nudge (floating banner)

    private func showNudge(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) {
        let view = NudgeView(payload: payload) { response in
            completion(response)
        }
        let panel = makePanel(
            content: view,
            level: .floating,
            size: NSSize(width: 400, height: 160)
        )
        positionTopRight(panel)
        showAndTrack(panel)
    }

    // MARK: - Knock (overlay)

    private func showKnock(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) {
        let view = KnockView(payload: payload) { response in
            completion(response)
        }
        let panel = makePanel(
            content: view,
            level: .modalPanel,
            size: NSSize(width: 500, height: 300)
        )
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.4)
        centerOnScreen(panel)
        showAndTrack(panel)

        // Also show a dimming overlay behind
        for screen in NSScreen.screens {
            let dimWindow = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            dimWindow.level = .modalPanel - 1
            dimWindow.backgroundColor = NSColor.black.withAlphaComponent(0.3)
            dimWindow.isOpaque = false
            dimWindow.ignoresMouseEvents = true
            dimWindow.orderFront(nil)
            activeWindows.append(dimWindow)
        }
    }

    // MARK: - Break (full-screen takeover)

    private func showBreak(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) {
        let view = BreakView(payload: payload) { response in
            completion(response)
        }

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            // Only put the interactive content on the main screen
            if screen == NSScreen.main {
                window.contentView = NSHostingView(rootView: view)
            } else {
                // Other screens get a blur overlay
                let blurView = BreakBackdropView()
                window.contentView = NSHostingView(rootView: blurView)
            }

            window.orderFrontRegardless()
            activeWindows.append(window)
        }
    }

    // MARK: - Helpers

    private func makePanel<V: View>(content: V, level: NSWindow.Level, size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = level
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: content)
        return panel
    }

    private func positionNearMenuBar(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - window.frame.width - 16
        let y = screenFrame.maxY - window.frame.height - 8
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionTopRight(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - window.frame.width - 16
        let y = screenFrame.maxY - window.frame.height - 16
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func centerOnScreen(_ window: NSWindow) {
        window.center()
    }

    private func showAndTrack(_ window: NSWindow) {
        window.orderFrontRegardless()
        activeWindows.append(window)
    }
}
