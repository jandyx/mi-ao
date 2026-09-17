// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation
import Testing

@testable import MiAo

@Test func runtimeStatusFileRoundTripsAndIgnoresStaleProcess() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mi-ao-runtime-status-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("runtime-status.json")

    let snapshot = MiAoRuntimeStatusSnapshot(
        pid: 4242,
        label: "重连第 3 次 · 16 秒后继续 · ATVV 能力协商超时（已尝试 3 次）",
        issue: "ATVV 能力协商超时（已尝试 3 次）",
        negotiationTimeouts: 3,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    RuntimeStatusFile.write(snapshot, to: url)
    #expect(RuntimeStatusFile.read(from: url) == snapshot)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? Int).map { $0 & 0o777 } == 0o600)
    #expect(RuntimeStatusFile.read(from: root.appendingPathComponent("missing.json")) == nil)
    #expect(snapshot.suggestsRepairing)
    #expect(
        !MiAoRuntimeStatusSnapshot(pid: 1, label: "已就绪", issue: nil, negotiationTimeouts: 1, updatedAt: Date())
            .suggestsRepairing
    )
}

@Test func voiceLinkCheckSurfacesNegotiationTimeouts() {
    let idle = SetupEnvironmentInspector.voiceLinkCheck(snapshot: nil)
    #expect(idle.state == .ready)
    #expect(idle.requirement == .optional)
    #expect(idle.action == nil)

    let healthy = SetupEnvironmentInspector.voiceLinkCheck(
        snapshot: MiAoRuntimeStatusSnapshot(
            pid: 1, label: "已就绪 · 按住语音键说话", issue: nil, negotiationTimeouts: 0, updatedAt: Date()
        )
    )
    #expect(healthy.state == .ready)
    #expect(healthy.detail == "已就绪 · 按住语音键说话")

    let flaky = SetupEnvironmentInspector.voiceLinkCheck(
        snapshot: MiAoRuntimeStatusSnapshot(
            pid: 1, label: "重连第 1 次 · 1 秒后继续 · 未发现已选遥控器", issue: "未发现已选遥控器",
            negotiationTimeouts: 0, updatedAt: Date()
        )
    )
    #expect(flaky.state == .actionRequired)
    #expect(flaky.action == .retryVoiceConnection)
    #expect(flaky.requirement == .optional)

    let broken = SetupEnvironmentInspector.voiceLinkCheck(
        snapshot: MiAoRuntimeStatusSnapshot(
            pid: 1, label: "重连第 4 次 · 8 秒后继续 · ATVV 能力协商超时（已尝试 3 次）",
            issue: "ATVV 能力协商超时（已尝试 3 次）", negotiationTimeouts: 4, updatedAt: Date()
        )
    )
    #expect(broken.state == .actionRequired)
    #expect(broken.action == .retryVoiceConnection)
    #expect(broken.detail.contains("连续 4 次未响应 ATVV 能力协商"))
    #expect(broken.detail.contains("菜单+HOME"))
    // 语音链路问题不阻止向导启动/复查；运行时本身仍在自动重连。
    #expect(!broken.requirement.blocksStart)
}

@Test func reconnectingStatusCarriesReasonForMenuBar() {
    let status = MiAoRuntimeStatus.reconnecting(
        attempt: 2, delaySeconds: 4, reason: "ATVV 能力协商超时（已尝试 3 次）"
    )
    #expect(status.label == "重连第 2 次 · 4 秒后继续 · ATVV 能力协商超时（已尝试 3 次）")
}

@Test func transcriptHistoryListsNewestFinalTranscriptsOnly() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mi-ao-transcripts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for (name, body) in [
        ("voice-20260917-050515-716-3711f60b.txt", "测试。测试。发送。\n"),
        ("voice-20260917-050515-716-3711f60b.whisper.txt", "raw whisper output"),
        ("voice-20260917-050515-716-3711f60b.wav", "not text"),
        ("voice-20260917-045613-818-7fa41a43.txt", "哈喽哈喽。"),
        ("notes.txt", "unrelated"),
    ] {
        try Data(body.utf8).write(to: root.appendingPathComponent(name))
    }

    let entries = TranscriptHistory.load(directory: root.path)
    #expect(
        entries.map(\.fileName) == [
            "voice-20260917-050515-716-3711f60b.txt",
            "voice-20260917-045613-818-7fa41a43.txt",
        ])
    #expect(entries[0].text == "测试。测试。发送。")
    // 文件名时间戳是 UTC：20260917-050515 = 2026-09-17T05:05:15.716Z
    let recordedAt = try #require(entries[0].recordedAt)
    #expect(abs(recordedAt.timeIntervalSince1970 - 1_789_621_515.716) < 0.001)
    #expect(TranscriptHistory.load(directory: root.path, limit: 1).count == 1)
    #expect(TranscriptHistory.load(directory: root.appendingPathComponent("missing").path).isEmpty)
    #expect(TranscriptHistory.recordedAt(fromFileName: "voice-garbage.txt") == nil)
    #expect(!TranscriptHistory.isTranscriptFile("voice-1.whisper.txt"))
}

@Test func runtimeStatusSnapshotCarriesLastVoiceResultAndReadsOlderFiles() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mi-ao-runtime-status-voice-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appendingPathComponent("runtime-status.json")

    let voice = MiAoRuntimeStatusSnapshot.VoiceResult(
        transcript: "检查当前项目", recordedAt: Date(timeIntervalSince1970: 1_700_000_100),
        submissionTarget: "Codex CLI", submitted: true, detail: nil
    )
    let snapshot = MiAoRuntimeStatusSnapshot(
        pid: 1, label: "已发送到 Codex", issue: nil, negotiationTimeouts: 0,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_101), lastVoice: voice
    )
    RuntimeStatusFile.write(snapshot, to: url)
    #expect(RuntimeStatusFile.read(from: url)?.lastVoice == voice)

    // 旧版本写的文件没有 lastVoice 字段，仍能读取。
    try Data(
        """
        {"pid":1,"label":"已就绪","issue":null,"negotiationTimeouts":0,"updatedAt":"2026-09-17T03:00:00Z"}
        """.utf8
    ).write(to: url)
    #expect(RuntimeStatusFile.read(from: url)?.lastVoice == nil)
    #expect(RuntimeStatusFile.read(from: url)?.label == "已就绪")
}
