import LocalAuthentication

/// Touch ID confirmation that a human deliberately asked for something.
///
/// This is an intent gate, NOT a privilege boundary. Root comes from the
/// sudoers rule (or the authorization dialog) downstream; anything already
/// running as this user could call `pmset` directly without passing through
/// here. Its job is to make an action that changes persistent system state a
/// deliberate one, not to keep an attacker out.
///
/// An unavailable policy — no enrolled biometry, no password set — is therefore
/// treated as "no gate available", not as a denial: the real authorization step
/// still runs afterwards, so refusing here would only break the feature.
public enum BiometricConfirmation {
    public static func confirmUserPresence(reason: String) async -> Bool {
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            WardLogger.keepAwake.notice("No authentication policy available; deferring to the authorization step.")
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { didConfirm, evaluationError in
                if let evaluationError {
                    WardLogger.keepAwake.notice("Confirmation declined: \(evaluationError.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: didConfirm)
            }
        }
    }
}
