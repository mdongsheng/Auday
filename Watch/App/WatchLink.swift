import Foundation
import WatchConnectivity

/// Observable state the Watch UI reads.
@MainActor
@Observable
final class WatchState {
    static let shared = WatchState()

    var todayCount = 0
    var todayDuration: TimeInterval = 0
    var modelConfigured = true
    var pendingTransfers = 0
    var recent: [WatchChunk] = WatchState.loadRecent()

    var isAsking = false
    var answer: String?
    var pendingRequestID: String?

    func record(_ chunk: WatchChunk) {
        recent.insert(chunk, at: 0)
        recent = Array(recent.prefix(30))
        save()
    }

    func markSent(startedAt: Date) {
        if let index = recent.firstIndex(where: { abs($0.startedAt.timeIntervalSince(startedAt)) < 0.5 }) {
            recent[index].sent = true
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recent) {
            UserDefaults.standard.set(data, forKey: "recentChunks")
        }
    }

    private static func loadRecent() -> [WatchChunk] {
        guard let data = UserDefaults.standard.data(forKey: "recentChunks") else { return [] }
        return (try? JSONDecoder().decode([WatchChunk].self, from: data)) ?? []
    }
}

/// Watch side of WatchConnectivity.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(chunk url: URL, startedAt: Date, duration: TimeInterval, sessionID: UUID, heartRate: Double?) {
        var metadata: [String: Any] = [
            WCKey.kind: WCKind.recording,
            WCKey.startedAt: startedAt.timeIntervalSince1970,
            WCKey.duration: duration,
            WCKey.sessionID: sessionID.uuidString,
        ]
        if let heartRate { metadata[WCKey.heartRate] = heartRate }
        // Queued by the system and delivered even if the iPhone is out of range right now.
        WCSession.default.transferFile(url, metadata: metadata)
        let chunk = WatchChunk(id: UUID(), startedAt: startedAt, duration: duration, sent: false)
        Task { @MainActor in
            WatchState.shared.record(chunk)
            self.refreshPending()
        }
    }

    @MainActor
    func ask(_ question: String) {
        let state = WatchState.shared
        let requestID = UUID().uuidString
        state.isAsking = true
        state.answer = nil
        state.pendingRequestID = requestID
        let payload: [String: Any] = [
            WCKey.kind: WCKind.ask,
            WCKey.question: question,
            WCKey.requestID: requestID,
        ]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in }) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    @MainActor
    func refreshPending() {
        WatchState.shared.pendingTransfers = WCSession.default.outstandingFileTransfers.count
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.apply(context)
            self.refreshPending()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleAnswer(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleAnswer(userInfo)
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        let startedAt = (fileTransfer.file.metadata?[WCKey.startedAt] as? Double).map(Date.init(timeIntervalSince1970:))
        if error == nil {
            try? FileManager.default.removeItem(at: url)
        }
        Task { @MainActor in
            if error == nil, let startedAt { WatchState.shared.markSent(startedAt: startedAt) }
            self.refreshPending()
        }
    }

    @MainActor
    private func apply(_ context: [String: Any]) {
        let state = WatchState.shared
        if let count = context[WCKey.todayCount] as? Int { state.todayCount = count }
        if let duration = context[WCKey.todayDuration] as? Double { state.todayDuration = duration }
        if let configured = context[WCKey.modelConfigured] as? Bool { state.modelConfigured = configured }
    }

    private func handleAnswer(_ message: [String: Any]) {
        guard message[WCKey.kind] as? String == WCKind.answer,
              let answer = message[WCKey.answer] as? String else { return }
        let requestID = message[WCKey.requestID] as? String
        Task { @MainActor in
            let state = WatchState.shared
            guard requestID == nil || requestID == state.pendingRequestID else { return }
            state.answer = answer
            state.isAsking = false
        }
    }
}
