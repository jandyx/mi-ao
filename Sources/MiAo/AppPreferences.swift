// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation

enum SubmissionMode: String, Codable, CaseIterable {
    case codex
    case codexCLI = "codex_cli"
    case transcriptionOnly = "transcription_only"

    var displayName: String {
        switch self {
        case .codex: return "Codex App"
        case .codexCLI: return "Codex CLI"
        case .transcriptionOnly: return "仅转写"
        }
    }

    var codexTarget: CodexSubmitTarget {
        self == .codexCLI ? .codexCLI : .codexApp
    }
}

enum VoiceConnectionMode: String, Codable, CaseIterable {
    case alwaysReady = "always_ready"
    case smartSleep = "smart_sleep"

    var displayName: String {
        switch self {
        case .alwaysReady: return "随时就绪"
        case .smartSleep: return "智能休眠"
        }
    }
}

struct AppPreferences: Codable, Equatable {
    static let currentSchemaVersion = 3

    var schemaVersion = currentSchemaVersion
    var hasCompletedSetup = false
    var submissionMode: SubmissionMode = .codex
    var codexCLITerminal: CodexCLITerminalChoice = .auto
    var codexCLILaunchCommand = CodexCLISubmitter.defaultLaunchCommand
    var buttonControlEnabled = true
    var voiceConnectionMode: VoiceConnectionMode = .alwaysReady
    var selectedPresetID = "pointer"
    var preferredPeripheralIdentifier: UUID?

    static let defaults = AppPreferences()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case hasCompletedSetup
        case submissionMode
        case codexCLITerminal
        case codexCLILaunchCommand
        case buttonControlEnabled
        case voiceConnectionMode
        case selectedPresetID
        case preferredPeripheralIdentifier
    }

    init(
        schemaVersion: Int = currentSchemaVersion,
        hasCompletedSetup: Bool = false,
        submissionMode: SubmissionMode = .codex,
        codexCLITerminal: CodexCLITerminalChoice = .auto,
        codexCLILaunchCommand: String = CodexCLISubmitter.defaultLaunchCommand,
        buttonControlEnabled: Bool = true,
        voiceConnectionMode: VoiceConnectionMode = .alwaysReady,
        selectedPresetID: String = "pointer",
        preferredPeripheralIdentifier: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.hasCompletedSetup = hasCompletedSetup
        self.submissionMode = submissionMode
        self.codexCLITerminal = codexCLITerminal
        self.codexCLILaunchCommand = codexCLILaunchCommand
        self.buttonControlEnabled = buttonControlEnabled
        self.voiceConnectionMode = voiceConnectionMode
        self.selectedPresetID = selectedPresetID
        self.preferredPeripheralIdentifier = preferredPeripheralIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion =
            try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        hasCompletedSetup = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? false
        submissionMode = try container.decodeIfPresent(SubmissionMode.self, forKey: .submissionMode) ?? .codex
        codexCLITerminal =
            try container.decodeIfPresent(String.self, forKey: .codexCLITerminal)
            .flatMap(CodexCLITerminalChoice.init(rawValue:)) ?? .auto
        let launchCommand =
            try container.decodeIfPresent(String.self, forKey: .codexCLILaunchCommand)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        codexCLILaunchCommand = launchCommand.isEmpty ? CodexCLISubmitter.defaultLaunchCommand : launchCommand
        buttonControlEnabled = try container.decodeIfPresent(Bool.self, forKey: .buttonControlEnabled) ?? true
        voiceConnectionMode =
            try container.decodeIfPresent(VoiceConnectionMode.self, forKey: .voiceConnectionMode)
            ?? .alwaysReady
        selectedPresetID = try container.decodeIfPresent(String.self, forKey: .selectedPresetID) ?? "pointer"
        preferredPeripheralIdentifier = try container.decodeIfPresent(
            UUID.self,
            forKey: .preferredPeripheralIdentifier
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(hasCompletedSetup, forKey: .hasCompletedSetup)
        try container.encode(submissionMode, forKey: .submissionMode)
        try container.encode(codexCLITerminal.rawValue, forKey: .codexCLITerminal)
        try container.encode(codexCLILaunchCommand, forKey: .codexCLILaunchCommand)
        try container.encode(buttonControlEnabled, forKey: .buttonControlEnabled)
        try container.encode(voiceConnectionMode, forKey: .voiceConnectionMode)
        try container.encode(selectedPresetID, forKey: .selectedPresetID)
        try container.encodeIfPresent(
            preferredPeripheralIdentifier,
            forKey: .preferredPeripheralIdentifier
        )
    }

    var requiresAccessibility: Bool {
        submissionMode != .transcriptionOnly || buttonControlEnabled
    }

    /// 是否需要 Codex 桌面 App：自动发送到 App，或仅转写但按键仍要操作 App。
    /// Codex CLI 模式下按键动作改走终端，不再依赖 App。
    var requiresCodex: Bool {
        submissionMode == .codex || (buttonControlEnabled && submissionMode == .transcriptionOnly)
    }

    var requiresCodexCLI: Bool {
        submissionMode == .codexCLI
    }

    var requiresCodexCompatibility: Bool {
        submissionMode == .codex
    }

    var runtimeArguments: [String] {
        var arguments = ["--name", "小米蓝牙语音遥控器"]
        switch submissionMode {
        case .transcriptionOnly:
            arguments.append("--no-submit")
        case .codexCLI:
            arguments.append(contentsOf: ["--submit-target", CodexSubmitTarget.codexCLI.rawValue])
            if codexCLITerminal != .auto {
                arguments.append(contentsOf: ["--cli-terminal", codexCLITerminal.rawValue])
            }
            if codexCLILaunchCommand != CodexCLISubmitter.defaultLaunchCommand {
                arguments.append(contentsOf: ["--cli-launch-command", codexCLILaunchCommand])
            }
        case .codex:
            break
        }
        if !buttonControlEnabled {
            arguments.append("--no-buttons")
        }
        arguments.append(contentsOf: ["--voice-connection-mode", voiceConnectionMode.rawValue])
        arguments.append(contentsOf: ["--preset", selectedPresetID])
        if let preferredPeripheralIdentifier {
            arguments.append(contentsOf: ["--identifier", preferredPeripheralIdentifier.uuidString])
        }
        return arguments
    }
}

enum AppPreferencesLoadState: Equatable {
    case defaults
    case loaded
    case recoveredInvalid(URL)
    case unsupportedVersion(Int)
}

struct AppPreferencesSnapshot: Equatable {
    let preferences: AppPreferences
    let state: AppPreferencesLoadState
}

enum AppPreferencesError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidPreset

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "配置来自较新的 schema v\(version)，当前版本无法安全写入"
        case .invalidPreset:
            return "按键预设标识不能为空"
        }
    }
}

struct AppPreferencesStore {
    let fileURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        fileURL: URL = AppPreferencesStore.defaultFileURL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
    }

    static var defaultFileURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let dataDirectory: String
        if let override = environment["VOICE_BRIDGE_DATA_DIR"], !override.isEmpty {
            dataDirectory = NSString(string: override).expandingTildeInPath
        } else {
            dataDirectory =
                NSString(string: "~/Library/Application Support/mi-ao").expandingTildeInPath
        }
        return URL(fileURLWithPath: dataDirectory, isDirectory: true)
            .appendingPathComponent("preferences.json")
    }

    func load() -> AppPreferencesSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return AppPreferencesSnapshot(preferences: .defaults, state: .defaults)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            var preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
            guard preferences.schemaVersion <= AppPreferences.currentSchemaVersion else {
                return AppPreferencesSnapshot(
                    preferences: .defaults,
                    state: .unsupportedVersion(preferences.schemaVersion)
                )
            }
            preferences.schemaVersion = AppPreferences.currentSchemaVersion
            return AppPreferencesSnapshot(preferences: preferences, state: .loaded)
        } catch {
            let quarantineURL = quarantineURL(for: now())
            do {
                try prepareDirectory()
                if fileManager.fileExists(atPath: quarantineURL.path) {
                    try fileManager.removeItem(at: quarantineURL)
                }
                try fileManager.moveItem(at: fileURL, to: quarantineURL)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: quarantineURL.path
                )
                return AppPreferencesSnapshot(
                    preferences: .defaults,
                    state: .recoveredInvalid(quarantineURL)
                )
            } catch {
                return AppPreferencesSnapshot(preferences: .defaults, state: .defaults)
            }
        }
    }

    func save(_ preferences: AppPreferences) throws {
        guard preferences.schemaVersion <= AppPreferences.currentSchemaVersion else {
            throw AppPreferencesError.unsupportedVersion(preferences.schemaVersion)
        }
        guard !preferences.selectedPresetID.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AppPreferencesError.invalidPreset
        }
        try prepareDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var currentPreferences = preferences
        currentPreferences.schemaVersion = AppPreferences.currentSchemaVersion
        var data = try encoder.encode(currentPreferences)
        data.append(0x0A)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func prepareDirectory() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }

    private func quarantineURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return fileURL.deletingLastPathComponent()
            .appendingPathComponent("preferences.invalid-\(formatter.string(from: date)).json")
    }
}
