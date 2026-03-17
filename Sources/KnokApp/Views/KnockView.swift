import SwiftUI
import AppKit
import KnokCore

struct KnockView: View {
    let payload: AlertPayload
    let onAction: (AlertResponse) -> Void

    @State private var offset: CGFloat = -60
    @State private var opacity: Double = 0

    private var accent: Color { payload.resolvedAccentColor() }

    var body: some View {
        HStack(spacing: 14) {
            // Accent stripe
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 4, height: 32)

            // Icon
            Image(systemName: payload.resolvedIcon())
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(accent)

            // Title + message
            VStack(alignment: .leading, spacing: 2) {
                Text(payload.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let message = payload.message {
                    Text(message)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            // Action buttons on the right
            HStack(spacing: 8) {
                if payload.actions.isEmpty {
                    Button {
                        dismissWithAnimation { onAction(.dismissed) }
                    } label: {
                        Text("Dismiss")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                } else {
                    ForEach(payload.actions, id: \.id) { action in
                        Button {
                            if let urlString = action.url, let url = URL(string: urlString) {
                                NSWorkspace.shared.open(url)
                            }
                            dismissWithAnimation { onAction(.buttonClicked(action.id)) }
                        } label: {
                            HStack(spacing: 5) {
                                if let btnIcon = action.icon ?? (action.url != nil ? "arrow.up.right" : nil) {
                                    Image(systemName: btnIcon)
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                Text(action.label)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(accent.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                }
            }

            // X dismiss
            Button {
                dismissWithAnimation { onAction(.dismissed) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
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
        .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                offset = 0
                opacity = 1
            }
        }
    }

    private func dismissWithAnimation(then action: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.2)) {
            offset = -60
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            action()
        }
    }
}
