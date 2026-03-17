import SwiftUI
import KnokCore

struct WhisperView: View {
    let payload: AlertPayload
    let onDismiss: () -> Void

    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(payload.title)
                    .font(.headline)
                    .lineLimit(1)

                if let message = payload.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 1
            }
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onDismiss()
            }
        }
    }
}
