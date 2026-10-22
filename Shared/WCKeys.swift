import Foundation

/// Keys used in WatchConnectivity payloads between the Watch and the iPhone.
enum WCKey {
    static let kind = "kind"
    static let startedAt = "startedAt"
    static let duration = "duration"
    static let sessionID = "sessionID"
    static let heartRate = "heartRate"
    static let question = "question"
    static let answer = "answer"
    static let requestID = "requestID"
    static let todayCount = "todayCount"
    static let todayDuration = "todayDuration"
    static let modelConfigured = "modelConfigured"
    static let action = "action"
    static let isRecording = "isRecording"
    static let sessionStart = "sessionStart"
}

enum WCKind {
    static let recording = "recording"
    static let ask = "ask"
    static let answer = "answer"
    /// iPhone → Watch: `action` is "start" or "stop".
    static let command = "command"
    /// Watch → iPhone: live recording state.
    static let watchStatus = "watchStatus"
}
