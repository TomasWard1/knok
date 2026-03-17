import SwiftUI
import KnokCore

struct KnockView: View {
    let payload: AlertPayload
    let onAction: (AlertResponse) -> Void

    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text(payload.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            if let message = payload.message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
            }

            HStack(spacing: 12) {
                if payload.actions.isEmpty {
                    Button("Dismiss") {
                        onAction(.dismissed)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    ForEach(payload.actions, id: \.id) { action in
                        Button(action.label) {
                            onAction(.buttonClicked(action.id))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
        }
        .padding(32)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                scale = 1
                opacity = 1
            }
        }
    }
}
