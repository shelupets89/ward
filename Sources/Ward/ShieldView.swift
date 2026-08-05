import SwiftUI

struct ShieldView: View {
    @ObservedObject var overlayModel: ShieldOverlayModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch overlayModel.holdDisplayState {
            case .notHolding:
                CleaningInstructionsView(requiredHoldSeconds: overlayModel.requiredHoldSeconds)
            case .holding(let progress):
                EscapeHoldProgressView(progress: progress)
            }
        }
    }
}

private struct CleaningInstructionsView: View {
    let requiredHoldSeconds: Int

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bubbles.and.sparkles")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.white.opacity(0.18))
            Text("Cleaning mode")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text("Keyboard, trackpad, and screen are locked — wipe away")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.22))
            Text("Hold esc alone for \(requiredHoldSeconds) seconds to exit")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.top, 26)
        }
    }
}

private struct EscapeHoldProgressView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 110, height: 110)
            .animation(.linear(duration: 1.0 / 30.0), value: progress)
            Text("Keep holding esc…")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
