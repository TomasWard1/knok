import Foundation
import KnokCore

struct AlertHistoryItem: Identifiable {
    let id: UUID
    let payload: AlertPayload
    var response: AlertResponse?
    let timestamp: Date

    init(payload: AlertPayload) {
        self.id = UUID()
        self.payload = payload
        self.response = nil
        self.timestamp = Date()
    }
}

@MainActor
final class AlertHistory: ObservableObject {
    @Published var items: [AlertHistoryItem] = []

    private let maxItems = 20

    nonisolated init() {}

    func record(payload: AlertPayload) -> UUID {
        let item = AlertHistoryItem(payload: payload)
        items.insert(item, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        return item.id
    }

    func recordResponse(_ response: AlertResponse, for id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].response = response
        }
    }

    func clear() {
        items.removeAll()
    }
}
