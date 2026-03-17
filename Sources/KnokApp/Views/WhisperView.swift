import SwiftUI
import KnokCore

struct WhisperView: View {
    let payload: AlertPayload
    let onDismiss: () -> Void

    @State private var offset: CGFloat = 20
    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(payload.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let message = payload.message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                offset = 0
                opacity = 1
            }
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

    private var iconName: String {
        if payload.title.localizedCaseInsensitiveContains("build") ||
           payload.title.localizedCaseInsensitiveContains("deploy") {
            return "bolt.fill"
        }
        if payload.title.localizedCaseInsensitiveContains("test") {
            return "checkmark.circle.fill"
        }
        if payload.title.localizedCaseInsensitiveContains("error") ||
           payload.title.localizedCaseInsensitiveContains("fail") {
            return "xmark.circle.fill"
        }
        return "bell.fill"
    }

    private var accentColor: Color {
        if payload.title.localizedCaseInsensitiveContains("error") ||
           payload.title.localizedCaseInsensitiveContains("fail") {
            return .red
        }
        if payload.title.localizedCaseInsensitiveContains("build") ||
           payload.title.localizedCaseInsensitiveContains("deploy") ||
           payload.title.localizedCaseInsensitiveContains("pass") {
            return .green
        }
        return .blue
    }
}
