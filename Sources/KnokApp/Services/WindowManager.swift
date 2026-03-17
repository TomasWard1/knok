import AppKit
import SwiftUI
import KnokCore

// Custom panel that can become key window (required for SwiftUI button clicks)
private class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// Custom window that can become key (for break-level fullscreen)
private class ClickableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class WindowManager {
    private var activeWindows: [NSWindow] = []
    private var currentCompletion: ((AlertResponse) -> Void)?

    func showAlert(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) {
        // Dismiss previous windows without calling previous completion
        for window in activeWindows {
            window.close()
        }
        activeWindows.removeAll()
        currentCompletion = completion

        switch payload.level {
        case .whisper:
            showWhisper(payload: payload)
        case .nudge:
            showNudge(payload: payload)
        case .knock:
            showKnock(payload: payload)
        case .break:
            showBreak(payload: payload)
        }
    }

    func dismissAll() {
        for window in activeWindows {
            window.close()
        }
        activeWindows.removeAll()
    }

    private func complete(_ response: AlertResponse) {
        dismissAll()
        let completion = currentCompletion
        currentCompletion = nil
        completion?(response)
    }

    // MARK: - Whisper (menu bar flash)

    private func showWhisper(payload: AlertPayload) {
        let view = WhisperView(payload: payload) { [weak self] in
            self?.complete(.dismissed)
        }
        let panel = makePanel(
            content: view,
            level: .floating,
            size: NSSize(width: 320, height: 80),
            canActivate: false
        )
        positionNearMenuBar(panel)
        panel.orderFrontRegardless()
        activeWindows.append(panel)

        // Auto-dismiss whisper after 5 seconds if no TTL set
        let ttl = payload.ttl > 0 ? payload.ttl : 5
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(ttl)) { [weak self] in
            guard let self, self.activeWindows.contains(where: { $0 === panel }) else { return }
            self.complete(.timeout)
        }
    }

    // MARK: - Nudge (floating banner)

    private func showNudge(payload: AlertPayload) {
        let view = NudgeView(payload: payload) { [weak self] response in
            self?.complete(response)
        }
        let panel = makePanel(
            content: view,
            level: .floating,
            size: NSSize(width: 400, height: 160),
            canActivate: true
        )
        positionTopRight(panel)
        panel.makeKeyAndOrderFront(nil)
        activeWindows.append(panel)
    }

    // MARK: - Knock (overlay)

    private func showKnock(payload: AlertPayload) {
        // First, show dimming overlays behind
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
            dimWindow.orderFrontRegardless()
            activeWindows.append(dimWindow)
        }

        // Then show the interactive panel on top
        let view = KnockView(payload: payload) { [weak self] response in
            self?.complete(response)
        }
        let panel = makePanel(
            content: view,
            level: .modalPanel,
            size: NSSize(width: 500, height: 300),
            canActivate: true
        )
        panel.backgroundColor = .clear
        centerOnScreen(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        activeWindows.append(panel)
    }

    // MARK: - Break (full-screen takeover)

    private func showBreak(payload: AlertPayload) {
        let view = BreakView(payload: payload) { [weak self] response in
            self?.complete(response)
        }

        for screen in NSScreen.screens {
            let window = ClickableWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            if screen == NSScreen.main {
                window.contentView = NSHostingView(rootView: view)
            } else {
                window.contentView = NSHostingView(rootView: BreakBackdropView())
            }

            window.orderFrontRegardless()
            activeWindows.append(window)
        }

        // Activate app and make main screen window key
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = activeWindows.last(where: { $0.screen == NSScreen.main }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Helpers

    private func makePanel<V: View>(content: V, level: NSWindow.Level, size: NSSize, canActivate: Bool) -> NSPanel {
        let styleMask: NSWindow.StyleMask = canActivate
            ? [.titled, .closable, .fullSizeContentView]
            : [.nonactivatingPanel, .fullSizeContentView]

        let panel = ClickablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.level = level
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.contentView = NSHostingView(rootView:
            content
                .frame(width: size.width, height: size.height)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
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
}
