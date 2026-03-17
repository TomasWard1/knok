import SwiftUI
import KnokCore

struct BreakView: View {
    let payload: AlertPayload
    let onAction: (AlertResponse) -> Void

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var pulseAmount: CGFloat = 1

    var body: some View {
        ZStack {
            // Blurred background
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Pulsing alert icon
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                    .scaleEffect(pulseAmount)

                VStack(spacing: 12) {
                    Text(payload.title)
                        .font(.largeTitle)
                        .fontWeight(.black)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    if let message = payload.message {
                        Text(message)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .lineLimit(8)
                    }
                }

                HStack(spacing: 16) {
                    if payload.actions.isEmpty {
                        Button("Acknowledge") {
                            onAction(.dismissed)
                        }
                        .buttonStyle(BreakButtonStyle())
                    } else {
                        ForEach(payload.actions, id: \.id) { action in
                            Button(action.label) {
                                onAction(.buttonClicked(action.id))
                            }
                            .buttonStyle(BreakButtonStyle())
                        }
                    }
                }
            }
            .padding(48)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1
                opacity = 1
            }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulseAmount = 1.1
            }
        }
    }
}

struct BreakButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.red)
                    .opacity(configuration.isPressed ? 0.7 : 1)
            )
    }
}

struct BreakBackdropView: View {
    var body: some View {
        Color.black.opacity(0.7)
            .ignoresSafeArea()
    }
}
