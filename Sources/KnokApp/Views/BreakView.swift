import SwiftUI
import AppKit
import KnokCore

struct BreakView: View {
    let payload: AlertPayload
    let onAction: (AlertResponse) -> Void
    @Environment(\.knokFontScale) private var scale

    @State private var cardScale: CGFloat = 0.85
    @State private var opacity: Double = 0
    @State private var pulseAmount: CGFloat = 1
    @State private var backdropOpacity: Double = 0

    private var accent: Color { payload.resolvedAccentColor() }

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .opacity(backdropOpacity)

            // Central glassmorphic card
            VStack(spacing: 28) {
                // Pulsing icon
                Image(systemName: payload.resolvedIcon())
                    .font(.system(size: 52 * scale, weight: .medium))
                    .foregroundStyle(accent)
                    .scaleEffect(pulseAmount)
                    .shadow(color: accent.opacity(0.4), radius: 20)

                // Title + message
                VStack(spacing: 10) {
                    Text(payload.title)
                        .font(.system(size: 32 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    if let message = payload.message {
                        Text(message)
                            .font(.system(size: 20 * scale, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineLimit(5)
                    }
                }

                // Action buttons
                HStack(spacing: 12) {
                    if payload.actions.isEmpty {
                        breakButton(label: "Acknowledge", icon: nil, accent: accent) {
                            onAction(.dismissed)
                        }
                    } else {
                        ForEach(payload.actions, id: \.id) { action in
                            breakButton(
                                label: action.label,
                                icon: action.icon ?? (action.url != nil ? "arrow.up.right" : nil),
                                accent: accent
                            ) {
                                if let urlString = action.url, let url = URL(string: urlString) {
                                    NSWorkspace.shared.open(url)
                                }
                                onAction(.buttonClicked(action.id))
                            }
                        }
                    }
                }
            }
            .padding(48)
            .background {
                ZStack {
                    VisualEffectBackground(
                        material: .fullScreenUI,
                        blendingMode: .behindWindow
                    )
                    .opacity(0.5)

                    Color.white.opacity(0.08)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 40, y: 10)
            .scaleEffect(cardScale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                backdropOpacity = 1
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                cardScale = 1
                opacity = 1
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAmount = 1.08
            }
        }
    }

    @ViewBuilder
    private func breakButton(label: String, icon: String?, accent: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14 * scale, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 18 * scale, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(accent.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct BreakBackdropView: View {
    @State private var opacity: Double = 0

    var body: some View {
        Color.black.opacity(0.65)
            .ignoresSafeArea()
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 1
                }
            }
    }
}
