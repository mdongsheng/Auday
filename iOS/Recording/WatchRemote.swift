import Foundation
import WatchConnectivity

/// Mirrors the Watch's recording state on the iPhone and starts/stops recording on the Watch.
@MainActor
@Observable
final class WatchRemote {
    static let shared = WatchRemote()

    private(set) var isWatchAvailable = false
    private(set) var isRecording = false
    private(set) var sessionStart: Date?
    private(set) var heartRate: Double?
    private(set) var isBusy = false
    var lastError: String?

    private var timeoutTask: Task<Void, Never>?

    func refreshAvailability() {
        let session = WCSession.default
        isWatchAvailable = WCSession.isSupported()
            && session.activationState == .activated
            && session.isPaired
            && session.isWatchAppInstalled
    }

    /// Applies a `watchStatus` payload (message or application context) from the Watch.
    func apply(_ payload: [String: Any]) {
        guard payload[WCKey.kind] as? String == WCKind.watchStatus,
              let recording = payload[WCKey.isRecording] as? Bool else { return }
        isRecording = recording
        sessionStart = recording
            ? (payload[WCKey.sessionStart] as? Double).map(Date.init(timeIntervalSince1970:))
            : nil
        heartRate = recording ? payload[WCKey.heartRate] as? Double : nil
        isBusy = false
        lastError = nil
        timeoutTask?.cancel()
    }

    func start() async {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        let session = WCSession.default
        if session.isReachable {
            // The Watch app is already running: a message is the fastest path.
            send(action: "start")
        } else {
            // Wake the Watch app in the background; it starts recording when launched.
            do {
                try await HealthStore.shared.startWatchApp()
            } catch {
                isBusy = false
                lastError = String(localized: "Make sure your Watch is on your wrist and unlocked.")
                return
            }
        }
        armTimeout()
    }

    func stop() {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        send(action: "stop")
        armTimeout()
    }

    private func send(action: String) {
        let payload: [String: Any] = [WCKey.kind: WCKind.command, WCKey.action: action]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in }) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// If the Watch doesn't report back, stop spinning and explain why.
    private func armTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.isBusy else { return }
            self.isBusy = false
            self.lastError = String(localized: "Make sure your Watch is on your wrist and unlocked.")
        }
    }
}
