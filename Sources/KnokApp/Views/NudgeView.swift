import SwiftUI
import AppKit
import KnokCore

struct NudgeView: View {
    let payload: AlertPayload
    let onAction: (AlertResponse) -> Void
    @Environment(\.knokFontScale) private var scale

    @State private var offset: CGFloat = 20
    @State private var opacity: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: accent stripe + icon + title + X
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(payload.resolvedAccentColor())
                    .frame(width: 3, height: 24)

                Image(systemName: payload.resolvedIcon())
                    .font(.system(size: 16 * scale, weight: .medium))
                    .foregroundStyle(payload.resolvedAccentColor())

                Text(payload.title)
                    .font(.system(size: 18 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    dismissWithAnimation { onAction(.dismissed) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }

            // Message
            if let message = payload.message {
                Text(message)
                    .font(.system(size: 16 * scale, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(4)
                    .padding(.leading, 0)
            }

            // Action buttons or dismiss
            if payload.actions.isEmpty {
                Button {
                    dismissWithAnimation { onAction(.dismissed) }
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 13 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(payload.actions, id: \.id) { action in
                        Button {
                            if let urlString = action.url,
                               let url = URL(string: urlString),
                               let scheme = url.scheme?.lowercased(),
                               scheme == "http" || scheme == "https" {
                                NSWorkspace.shared.open(url)
                            }
                            dismissWithAnimation { onAction(.buttonClicked(action.id)) }
                        } label: {
                            HStack(spacing: 5) {
                                if let btnIcon = action.icon ?? (action.url != nil ? "arrow.up.right" : nil) {
                                    Image(systemName: btnIcon)
                                        .font(.system(size: 10 * scale, weight: .semibold))
                                }
                                Text(action.label)
                                    .font(.system(size: 13 * scale, weight: .medium, design: .rounded))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, 9)
                            .padding(.horizontal, 8)
                            .background(payload.resolvedAccentColor().opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background {
            ZStack {
                VisualEffectBackground(
                    material: .fullScreenUI,
                    blendingMode: .behindWindow
                )
                .opacity(0.6)

                Color.white.opacity(0.12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                offset = 0
                opacity = 1
            }
        }
    }

    private func dismissWithAnimation(then action: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.2)) {
            offset = 10
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            action()
        }
    }
}
