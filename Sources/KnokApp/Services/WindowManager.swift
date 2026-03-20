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
    /// Windows per alert level (active alert's windows)
    private var levelWindows: [AlertLevel: [NSWindow]] = [:]
    /// Completion callbacks per level
    private var levelCompletions: [AlertLevel: (AlertResponse) -> Void] = [:]
    /// Stacked card hint windows per level (visual cards behind active)
    private var stackHintWindows: [AlertLevel: [NSWindow]] = [:]

    var settings: AppSettings?

    private var fontScale: Double { settings?.fontScale ?? 1.0 }
    private var showInAllSpaces: Bool { settings?.showInAllSpaces ?? true }

    private var spaceBehavior: NSWindow.CollectionBehavior {
        showInAllSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
    }

    /// Show an alert at a specific level. Dismisses any existing alert at that level first.
    func showAlert(payload: AlertPayload, stackDepth: Int, completion: @escaping (AlertResponse) -> Void) {
        // Close any existing windows at this level
        dismissLevel(payload.level)
        levelCompletions[payload.level] = completion

        switch payload.level {
        case .whisper:
            showWhisper(payload: payload, stackDepth: stackDepth)
        case .nudge:
            showNudge(payload: payload, stackDepth: stackDepth)
        case .knock:
            showKnock(payload: payload, stackDepth: stackDepth)
        case .break:
            showBreak(payload: payload)
        }
    }

    /// Hide (but don't complete) a level's windows — used for priority suspension
    func suspendLevel(_ level: AlertLevel) {
        for window in levelWindows[level] ?? [] {
            window.orderOut(nil)
        }
        for window in stackHintWindows[level] ?? [] {
            window.orderOut(nil)
        }
    }

    /// Re-show a suspended level's windows
    func resumeLevel(_ level: AlertLevel) {
        for window in levelWindows[level] ?? [] {
            window.orderFrontRegardless()
        }
        for window in stackHintWindows[level] ?? [] {
            window.orderFrontRegardless()
        }
    }

    /// Dismiss a specific level's windows and fire completion
    func dismissLevel(_ level: AlertLevel) {
        for window in levelWindows[level] ?? [] {
            window.close()
        }
        levelWindows[level] = nil

        for window in stackHintWindows[level] ?? [] {
            window.close()
        }
        stackHintWindows[level] = nil
    }

    /// Update the stack hint cards behind the active alert (call when queue changes)
    func updateStackHints(level: AlertLevel, depth: Int) {
        // Remove existing hints
        for window in stackHintWindows[level] ?? [] {
            window.close()
        }
        stackHintWindows[level] = nil

        guard depth > 0 else { return }
        guard level != .break else { return }
        guard let mainWindow = levelWindows[level]?.first else { return }

        let hintCount = min(depth, 3)
        var hints: [NSWindow] = []
        let mainFrame = mainWindow.frame

        for i in 1...hintCount {
            let yOffset = CGFloat(i) * 14
            let xInset = CGFloat(i) * 4

            let hintWidth = mainFrame.width - xInset * 2
            let hintHeight = mainFrame.height

            let hintPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: NSSize(width: hintWidth, height: hintHeight)),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            hintPanel.level = mainWindow.level
            hintPanel.isFloatingPanel = true
            hintPanel.hidesOnDeactivate = false
            hintPanel.isReleasedWhenClosed = false
            hintPanel.backgroundColor = .clear
            hintPanel.isOpaque = false
            hintPanel.hasShadow = false
            hintPanel.collectionBehavior = spaceBehavior
            hintPanel.ignoresMouseEvents = true

            let hintView = NSHostingView(rootView:
                StackHintCard(
                    width: hintWidth,
                    height: hintHeight,
                    cornerRadius: 12,
                    opacity: max(0.3, 0.7 - Double(i) * 0.15)
                )
            )
            hintView.setFrameSize(NSSize(width: hintWidth, height: hintHeight))
            hintPanel.contentView = hintView

            // Position: peeking out above the active alert
            var origin = mainFrame.origin
            origin.x += xInset
            origin.y += yOffset

            hintPanel.setFrameOrigin(origin)
            hintPanel.setContentSize(NSSize(width: hintWidth, height: hintHeight))

            hintPanel.orderFront(nil)
            hintPanel.order(.below, relativeTo: mainWindow.windowNumber)
            hints.append(hintPanel)
        }

        stackHintWindows[level] = hints
    }

    func dismissAll() {
        for level in AlertLevel.allCases {
            dismissLevel(level)
        }
        levelCompletions.removeAll()
    }

    private func complete(_ response: AlertResponse, level: AlertLevel) {
        dismissLevel(level)
        let completion = levelCompletions.removeValue(forKey: level)
        completion?(response)
    }

    // MARK: - Whisper (menu bar flash)

    private func showWhisper(payload: AlertPayload, stackDepth: Int) {
        let view = WhisperView(payload: payload) { [weak self] in
            self?.complete(.dismissed, level: .whisper)
        }
        .knokFontScale(fontScale)

        let maxWidth: CGFloat = 340

        let widthProbe = NSHostingView(rootView: view.fixedSize())
        let idealWidth = widthProbe.fittingSize.width
        let finalWidth = min(idealWidth, maxWidth)

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
        levelWindows[.whisper] = [panel]

        // Show stack hints
        if stackDepth > 0 {
            updateStackHints(level: .whisper, depth: stackDepth)
        }

        // Auto-dismiss
        let ttl: Int
        if payload.ttl > 0 {
            ttl = payload.ttl
        } else if let settingsTTL = settings?.whisperAutoDismiss, settingsTTL > 0 {
            ttl = settingsTTL
        } else {
            ttl = 5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(ttl)) { [weak self] in
            guard let self, self.levelWindows[.whisper]?.contains(where: { $0 === panel }) == true else { return }
            self.complete(.timeout, level: .whisper)
        }
    }

    // MARK: - Nudge (floating banner)

    private func showNudge(payload: AlertPayload, stackDepth: Int) {
        let view = NudgeView(payload: payload) { [weak self] response in
            self?.complete(response, level: .nudge)
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
        levelWindows[.nudge] = [panel]

        // Show stack hints
        if stackDepth > 0 {
            updateStackHints(level: .nudge, depth: stackDepth)
        }

        // Auto-dismiss
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
                guard let self, self.levelWindows[.nudge]?.contains(where: { $0 === panel }) == true else { return }
                self.complete(.timeout, level: .nudge)
            }
        }
    }

    // MARK: - Knock (overlay)

    private func showKnock(payload: AlertPayload, stackDepth: Int) {
        guard let screen = NSScreen.main else { return }

        let view = KnockView(payload: payload) { [weak self] response in
            self?.complete(response, level: .knock)
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
        levelWindows[.knock] = [panel]

        // Show stack hints
        if stackDepth > 0 {
            updateStackHints(level: .knock, depth: stackDepth)
        }
    }

    // MARK: - Break (full-screen takeover)

    private func showBreak(payload: AlertPayload) {
        var windows: [NSWindow] = []

        let view = BreakView(payload: payload) { [weak self] response in
            self?.complete(response, level: .break)
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
            windows.append(window)
        }

        levelWindows[.break] = windows

        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = windows.last(where: { $0.screen == NSScreen.main }) {
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

// MARK: - Stack Hint Card (visual indicator of queued alerts)

struct StackHintCard: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let opacity: Double

    var body: some View {
        ZStack {
            VisualEffectBackground(
                material: .fullScreenUI,
                blendingMode: .behindWindow
            )
            .opacity(0.6)

            Color.white.opacity(0.12)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        .frame(width: width, height: height)
        .opacity(opacity)
    }
}
