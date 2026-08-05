import Combine

/// UI state shared by every shield window's SwiftUI content. Progress lives
/// inside the holding case so it cannot linger from a cancelled hold.
final class ShieldOverlayModel: ObservableObject {
    enum HoldDisplayState: Equatable {
        case notHolding
        case holding(progress: Double)
    }

    let requiredHoldSeconds: Int
    @Published private(set) var holdDisplayState: HoldDisplayState = .notHolding

    init(requiredHoldSeconds: Int) {
        self.requiredHoldSeconds = requiredHoldSeconds
    }

    func showHoldProgress(_ progress: Double) {
        holdDisplayState = .holding(progress: progress)
    }

    func reset() {
        holdDisplayState = .notHolding
    }
}
