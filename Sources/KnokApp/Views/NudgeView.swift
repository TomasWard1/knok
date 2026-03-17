import SwiftUI
import KnokCore

struct NudgeView: View {
    let payload: AlertPayload
    let onAction: (AlertResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hand.point.up")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text(payload.title)
                    .font(.headline)

                Spacer()

                Button {
                    onAction(.dismissed)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let message = payload.message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if !payload.actions.isEmpty {
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(payload.actions, id: \.id) { action in
                        Button(action.label) {
                            onAction(.buttonClicked(action.id))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
