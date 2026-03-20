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

// Hosting view that accepts first mouse click without needing focus
private class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class WindowManager {
    private var activeWindows: [NSWindow] = []
    private var currentCompletion: ((AlertResponse) -> Void)?
    var settings: AppSettings?

    private var fontScale: Double { settings?.fontScale ?? 1.0 }
    private var showInAllSpaces: Bool { settings?.showInAllSpaces ?? true }

    private var spaceBehavior: NSWindow.CollectionBehavior {
        showInAllSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
    }

    func showAlert(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) {
        for window in activeWindows {
            window.close()
        }
        activeWindows.removeAll()

        // Release the previous completion so its waiting thread isn't leaked
        if let previous = currentCompletion {
            previous(.dismissed)
        }
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
        .knokFontScale(fontScale)

        let maxWidth: CGFloat = 340

        // Pass 1: measure ideal width (unconstrained)
        let widthProbe = NSHostingView(rootView: view.fixedSize())
        let idealWidth = widthProbe.fittingSize.width
        let finalWidth = min(idealWidth, maxWidth)

        // Pass 2: measure height at the clamped width
        let heightProbe = NSHostingView(rootView:
            view.frame(width: finalWidth).fixedSize(horizontal: false, vertical: true)
        )
        let finalHeight = max(heightProbe.fittingSize.height, 60)
        let size = NSSize(width: finalWidth, height: finalHeight)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = spaceBehavior
        panel.contentView = FirstClickHostingView(rootView:
            view.frame(width: size.width, height: size.height)
        )
        positionBottomRight(panel)
        panel.orderFrontRegardless()
        activeWindows.append(panel)

        // Auto-dismiss: payload TTL > settings default > 5s fallback
        let ttl: Int
        if payload.ttl > 0 {
            ttl = payload.ttl
        } else if let settingsTTL = settings?.whisperAutoDismiss, settingsTTL > 0 {
            ttl = settingsTTL
        } else {
            ttl = 5
        }
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
        .knokFontScale(fontScale)

        let width: CGFloat = 360
        let wrappedView = view.frame(width: width).fixedSize(horizontal: false, vertical: true)
        let hostingView = FirstClickHostingView(rootView: wrappedView)
        let fittingSize = hostingView.fittingSize
        let size = NSSize(width: width, height: fittingSize.height)
        hostingView.setFrameSize(size)

        let panel = ClickablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = spaceBehavior
        panel.contentView = hostingView
        positionBottomRight(panel)
        panel.orderFrontRegardless()
        activeWindows.append(panel)

        // Auto-dismiss: payload TTL > settings default > 0 (manual)
        let ttl: Int
        if payload.ttl > 0 {
            ttl = payload.ttl
        } else if let settingsTTL = settings?.nudgeAutoDismiss, settingsTTL > 0 {
            ttl = settingsTTL
        } else {
            ttl = 0
        }
        if ttl > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(ttl)) { [weak self] in
                guard let self, self.activeWindows.contains(where: { $0 === panel }) else { return }
                self.complete(.timeout)
            }
        }
    }

    // MARK: - Knock (overlay)

    private func showKnock(payload: AlertPayload) {
        guard let screen = NSScreen.main else { return }

        let view = KnockView(payload: payload) { [weak self] response in
            self?.complete(response)
        }
        .knokFontScale(fontScale)

        let hostingView = FirstClickHostingView(rootView: view.fixedSize())
        hostingView.setFrameSize(hostingView.fittingSize)
        let size = hostingView.fittingSize

        let panel = ClickablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .modalPanel
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = spaceBehavior
        panel.contentView = hostingView

        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.maxY - size.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.orderFrontRegardless()
        activeWindows.append(panel)
    }

    // MARK: - Break (full-screen takeover)

    private func showBreak(payload: AlertPayload) {
        let view = BreakView(payload: payload) { [weak self] response in
            self?.complete(response)
        }
        .knokFontScale(fontScale)

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
                window.contentView = FirstClickHostingView(rootView: view)
            } else {
                window.contentView = NSHostingView(rootView: BreakBackdropView())
            }

            window.orderFrontRegardless()
            activeWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = activeWindows.last(where: { $0.screen == NSScreen.main }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Helpers

    private func positionBottomRight(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - window.frame.width - 16
        let y = screenFrame.minY + 16
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
