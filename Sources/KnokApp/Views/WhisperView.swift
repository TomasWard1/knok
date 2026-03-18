import SwiftUI
import AppKit
import KnokCore

// Real behind-window blur using NSVisualEffectView
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct WhisperView: View {
    let payload: AlertPayload
    let onDismiss: () -> Void
    @Environment(\.knokFontScale) private var scale

    @State private var offset: CGFloat = 20
    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            // Accent stripe
            RoundedRectangle(cornerRadius: 1.5)
                .fill(payload.resolvedAccentColor())
                .frame(width: 3)
                .padding(.vertical, 4)

            Image(systemName: payload.resolvedIcon())
                .font(.system(size: 16 * scale, weight: .medium))
                .foregroundStyle(payload.resolvedAccentColor())

            VStack(alignment: .leading, spacing: 2) {
                Text(payload.title)
                    .font(.system(size: 18 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let message = payload.message {
                    Text(message)
                        .font(.system(size: 16 * scale, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 320)
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
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            dismissWithAnimation()
        }
    }

    private func dismissWithAnimation() {
        withAnimation(.easeIn(duration: 0.2)) {
            offset = 10
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}
