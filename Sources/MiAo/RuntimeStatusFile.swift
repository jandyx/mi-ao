// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation

/// 运行时写给设置向导 / doctor 看的语音链路快照。
/// 运行进程与向导是两个进程，向导只能通过这个文件了解“遥控器有没有回应 ATVV 握手”。
struct MiAoRuntimeStatusSnapshot: Codable, Equatable {
    /// 最近一次语音的结果，供设置向导“语音”页展示。
    struct VoiceResult: Codable, Equatable {
        let transcript: String
        let recordedAt: Date
        /// 发送目标描述（例如 "Codex CLI"）；仅转写时为 nil。
        let submissionTarget: String?
        let submitted: Bool
        let detail: String?
    }

    let pid: Int32
    let label: String
    let issue: String?
    /// 连续 ATVV 能力协商超时次数；握手成功后归零。
    let negotiationTimeouts: Int
    let updatedAt: Date
    let lastVoice: VoiceResult?

    init(
        pid: Int32,
        label: String,
        issue: String?,
        negotiationTimeouts: Int,
        updatedAt: Date,
        lastVoice: VoiceResult? = nil
    ) {
        self.pid = pid
        self.label = label
        self.issue = issue
        self.negotiationTimeouts = negotiationTimeouts
        self.updatedAt = updatedAt
        self.lastVoice = lastVoice
    }

    static let negotiationTimeoutAlertThreshold = 2

    var suggestsRepairing: Bool {
        negotiationTimeouts >= Self.negotiationTimeoutAlertThreshold
    }
}

enum RuntimeStatusFile {
    static var url: URL {
        MiAoInstallationContext.fileURL.deletingLastPathComponent()
            .appendingPathComponent("runtime-status.json")
    }

    static func write(_ snapshot: MiAoRuntimeStatusSnapshot, to url: URL = url) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func read(from url: URL = url) -> MiAoRuntimeStatusSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MiAoRuntimeStatusSnapshot.self, from: data)
    }

    static func remove(at url: URL = url) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 只有快照来自当前活着的运行进程才可信。
    static func snapshot(forRuntimePID pid: Int32?) -> MiAoRuntimeStatusSnapshot? {
        guard let pid, let snapshot = read(), snapshot.pid == pid else { return nil }
        return snapshot
    }
}
