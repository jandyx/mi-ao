// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation

/// 录音目录里的转写记录（`voice-YYYYMMDD-HHMMSS-mmm-xxxx.txt`），供设置向导“语音”页展示。
struct TranscriptEntry: Equatable, Sendable {
    let url: URL
    let recordedAt: Date?
    let text: String

    var fileName: String { url.lastPathComponent }
}

enum TranscriptHistory {
    static let filePrefix = "voice-"
    static let whisperSuffix = ".whisper.txt"

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // 文件名里的时间戳由 SpeechJobQueue 按 UTC 生成，显示时再转本地。
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    /// 从文件名解析录音时间；不合规范返回 nil。
    static func recordedAt(fromFileName name: String) -> Date? {
        guard name.hasPrefix(filePrefix) else { return nil }
        let body = name.dropFirst(filePrefix.count)
        let parts = body.split(separator: "-")
        guard parts.count >= 3 else { return nil }
        return timestampFormatter.date(from: parts[0...2].joined(separator: "-"))
    }

    static func isTranscriptFile(_ name: String) -> Bool {
        name.hasPrefix(filePrefix) && name.hasSuffix(".txt") && !name.hasSuffix(whisperSuffix)
    }

    static func load(
        directory: String,
        limit: Int = 20,
        fileManager: FileManager = .default
    ) -> [TranscriptEntry] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        return
            names
            .filter(isTranscriptFile)
            .sorted(by: >)
            .prefix(limit)
            .map { name in
                let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
                let text =
                    (try? String(contentsOf: url, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return TranscriptEntry(url: url, recordedAt: recordedAt(fromFileName: name), text: text)
            }
    }
}
