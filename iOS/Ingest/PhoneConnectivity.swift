import Foundation
import SwiftData
import WatchConnectivity

/// iPhone side of WatchConnectivity: receives audio chunks and questions from the Watch.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Status

    @MainActor
    func pushStatus() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let start = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.startedAt >= start })
        let today = (try? Persistence.context.fetch(descriptor)) ?? []
        try? WCSession.default.updateApplicationContext([
            WCKey.todayCount: today.count,
            WCKey.todayDuration: today.reduce(0) { $0 + $1.duration },
            WCKey.modelConfigured: ModelSettings.shared.isConfigured,
        ])
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushStatus() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this method returns, so move it synchronously.
        let metadata = file.metadata ?? [:]
        let ext = file.fileURL.pathExtension.isEmpty ? "m4a" : file.fileURL.pathExtension
        let name = AudioStorage.newFileName(ext: ext)
        do {
            try FileManager.default.moveItem(at: file.fileURL, to: AudioStorage.url(for: name))
        } catch {
            return
        }
        let startedAt = (metadata[WCKey.startedAt] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .now
        let duration = metadata[WCKey.duration] as? Double ?? 0
        let sessionID = (metadata[WCKey.sessionID] as? String).flatMap(UUID.init(uuidString:))
        let heartRate = metadata[WCKey.heartRate] as? Double

        Task { @MainActor in
            RecordingIngest.add(
                fileName: name,
                startedAt: startedAt,
                duration: duration,
                source: .watch,
                sessionID: sessionID,
                heartRate: heartRate
            )
            self.pushStatus()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(["ack": true])
        handle(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    // MARK: Ask from Watch

    private func handle(_ message: [String: Any]) {
        guard message[WCKey.kind] as? String == WCKind.ask,
              let question = message[WCKey.question] as? String,
              let requestID = message[WCKey.requestID] as? String else { return }
        Task { @MainActor in
            let answer: String
            do {
                answer = try await ChatEngine.shared.answerForWatch(question)
            } catch {
                answer = error.localizedDescription
            }
            self.send(answer: answer, requestID: requestID)
        }
    }

    private func send(answer: String, requestID: String) {
        let payload: [String: Any] = [
            WCKey.kind: WCKind.answer,
            WCKey.answer: answer,
            WCKey.requestID: requestID,
        ]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }
}
