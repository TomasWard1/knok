import Foundation
import KnokCore

/// Queued alert entry: payload + completion callback
struct QueuedAlert {
    let payload: AlertPayload
    let completion: (AlertResponse) -> Void
}

/// Per-level alert queues with position-aware suspension.
/// Break suspends everything. Nudge suspends whisper (same screen area).
/// Knock coexists with nudge/whisper (different screen position).
@MainActor
final class AlertQueue {
    /// Max alerts per level queue
    let maxPerLevel: Int

    /// Per-level queues (FIFO)
    private var queues: [AlertLevel: [QueuedAlert]] = [:]

    /// Currently active alert per level (the one being displayed)
    private(set) var active: [AlertLevel: QueuedAlert] = [:]

    /// Levels whose display is suspended by a higher-priority active alert
    private var suspended: Set<AlertLevel> = []

    /// Callback: called when an alert should be displayed
    var onShow: ((AlertPayload, AlertLevel, @escaping (AlertResponse) -> Void) -> Void)?

    /// Callback: called when a level's windows should be hidden (suspended)
    var onSuspend: ((AlertLevel) -> Void)?

    /// Callback: called when a level's windows should be restored
    var onResume: ((AlertLevel) -> Void)?

    /// Callback: called when queue depth changes for a level with an active alert (for stack visual)
    var onQueueDepthChanged: ((AlertLevel, Int) -> Void)?

    init(maxPerLevel: Int = 10) {
        self.maxPerLevel = maxPerLevel
        for level in AlertLevel.allCases {
            queues[level] = []
        }
    }

    /// Total pending alerts across all levels (not counting active ones)
    var totalPending: Int {
        queues.values.reduce(0) { $0 + $1.count }
    }

    /// Pending count for a specific level (not counting active)
    func pendingCount(for level: AlertLevel) -> Int {
        queues[level]?.count ?? 0
    }

    /// Enqueue an alert. Returns false if queue is full (caller should respond with queue_full).
    @discardableResult
    func enqueue(payload: AlertPayload, completion: @escaping (AlertResponse) -> Void) -> Bool {
        let level = payload.level
        let currentCount = (queues[level]?.count ?? 0) + (active[level] != nil ? 1 : 0)

        if currentCount >= maxPerLevel {
            return false
        }

        let entry = QueuedAlert(payload: payload, completion: completion)

        if active[level] == nil {
            activate(entry, for: level)
        } else {
            queues[level, default: []].append(entry)
            let newDepth = queues[level]?.count ?? 0
            onQueueDepthChanged?(level, newDepth)
        }

        return true
    }

    /// Called when the user responds to an alert at the given level.
    /// Triggers the next alert in queue if available.
    func complete(level: AlertLevel, response: AlertResponse) {
        guard let current = active[level] else { return }
        active[level] = nil
        current.completion(response)

        // Show next in this level's queue
        dequeueNext(for: level)
    }

    /// Dismiss all alerts at a specific level, completing them with .dismissed
    func dismissAll(for level: AlertLevel) {
        if let current = active[level] {
            active[level] = nil
            current.completion(.dismissed)
        }
        let pending = queues[level] ?? []
        queues[level] = []
        for entry in pending {
            entry.completion(.dismissed)
        }
    }

    /// Dismiss everything (app shutdown, etc.)
    func dismissAllLevels() {
        for level in AlertLevel.allCases {
            dismissAll(for: level)
        }
        suspended.removeAll()
    }

    // MARK: - Internal

    private func activate(_ entry: QueuedAlert, for level: AlertLevel) {
        active[level] = entry

        // Check suspensions based on position-aware rules
        updateSuspensions()

        // If this level is itself suspended, don't show yet (it will show when resumed)
        if suspended.contains(level) {
            return
        }

        onShow?(entry.payload, level) { [weak self] response in
            self?.complete(level: level, response: response)
        }
    }

    private func dequeueNext(for level: AlertLevel) {
        guard var queue = queues[level], !queue.isEmpty else {
            // No more alerts at this level — check if we should resume suspended levels
            updateSuspensions()
            return
        }

        let next = queue.removeFirst()
        queues[level] = queue
        activate(next, for: level)
    }

    /// Compute which levels should be suspended based on position-aware rules:
    /// - Break: suspends everything (fullscreen takeover)
    /// - Knock: coexists with nudge/whisper (different screen position)
    /// - Nudge: suspends whisper (same bottom-right area)
    /// - Whisper: doesn't suspend anything
    private func updateSuspensions() {
        var shouldSuspend: Set<AlertLevel> = []

        // Break suspends all other active levels
        if active[.break] != nil {
            for level in AlertLevel.allCases where level != .break {
                if active[level] != nil {
                    shouldSuspend.insert(level)
                }
            }
        }

        // Nudge suspends whisper (same screen area, nudge takes priority)
        if active[.nudge] != nil && active[.whisper] != nil && !shouldSuspend.contains(.whisper) {
            shouldSuspend.insert(.whisper)
        }

        // Apply changes: newly suspended
        for level in shouldSuspend where !suspended.contains(level) {
            suspended.insert(level)
            onSuspend?(level)
        }

        // Apply changes: newly resumed
        for level in suspended where !shouldSuspend.contains(level) {
            suspended.remove(level)
            if let entry = active[level] {
                onShow?(entry.payload, level) { [weak self] response in
                    self?.complete(level: level, response: response)
                }
            }
        }

        suspended = shouldSuspend
    }
}
