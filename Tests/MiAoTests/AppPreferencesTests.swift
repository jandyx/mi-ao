// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation
import Testing

@testable import MiAo

@Test func appPreferencesPersistPrivatelyAndBuildRuntimeArguments() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mi-ao-preferences-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("preferences.json")
    let store = AppPreferencesStore(fileURL: fileURL)

    var preferences = AppPreferences.defaults
    preferences.hasCompletedSetup = true
    preferences.submissionMode = .transcriptionOnly
    preferences.buttonControlEnabled = false
    preferences.voiceConnectionMode = .smartSleep
    preferences.selectedPresetID = "personal"
    preferences.preferredPeripheralIdentifier = UUID(
        uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    )
    try store.save(preferences)

    #expect(store.load() == AppPreferencesSnapshot(preferences: preferences, state: .loaded))
    #expect(
        preferences.runtimeArguments == [
            "--name",
            "小米蓝牙语音遥控器",
            "--no-submit",
            "--no-buttons",
            "--voice-connection-mode",
            "smart_sleep",
            "--preset",
            "personal",
            "--identifier",
            "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        ]
    )

    let directoryMode = try permissions(at: root)
    let fileMode = try permissions(at: fileURL)
    #expect(directoryMode & 0o777 == 0o700)
    #expect(fileMode & 0o777 == 0o600)
}

@Test func appPreferencesQuarantineInvalidJSONAndRecoverDefaults() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mi-ao-preferences-invalid-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fileURL = root.appendingPathComponent("preferences.json")
    try Data("{not-json".utf8).write(to: fileURL)
    let store = AppPreferencesStore(
        fileURL: fileURL,
        now: { Date(timeIntervalSince1970: 0) }
    )

    let snapshot = store.load()
    #expect(snapshot.preferences == .defaults)
    guard case .recoveredInvalid(let quarantineURL) = snapshot.state else {
        Issue.record("损坏配置没有进入隔离恢复状态")
        return
    }
    #expect(quarantineURL.lastPathComponent == "preferences.invalid-19700101-000000.json")
    #expect(FileManager.default.fileExists(atPath: quarantineURL.path))
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    #expect(try permissions(at: quarantineURL) & 0o777 == 0o600)
}

@Test func appPreferencesPreserveUnsupportedFutureSchema() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mi-ao-preferences-future-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fileURL = root.appendingPathComponent("preferences.json")
    var future = AppPreferences.defaults
    future.schemaVersion = AppPreferences.currentSchemaVersion + 1
    try JSONEncoder().encode(future).write(to: fileURL)

    let snapshot = AppPreferencesStore(fileURL: fileURL).load()
    #expect(snapshot.preferences == .defaults)
    #expect(snapshot.state == .unsupportedVersion(AppPreferences.currentSchemaVersion + 1))
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
}

@Test func appPreferencesMigrateV1WithoutPresetSelection() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mi-ao-preferences-v1-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fileURL = root.appendingPathComponent("preferences.json")
    try Data(
        """
        {"schemaVersion":1,"hasCompletedSetup":true,"submissionMode":"codex","buttonControlEnabled":true}
        """.utf8
    ).write(to: fileURL)

    let snapshot = AppPreferencesStore(fileURL: fileURL).load()
    #expect(snapshot.state == .loaded)
    #expect(snapshot.preferences.selectedPresetID == "pointer")
    #expect(snapshot.preferences.voiceConnectionMode == .alwaysReady)
    #expect(snapshot.preferences.hasCompletedSetup)
}

@Test func appPreferencesMigrateV2ToAlwaysReadyVoiceConnection() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mi-ao-preferences-v2-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fileURL = root.appendingPathComponent("preferences.json")
    try Data(
        """
        {"schemaVersion":2,"hasCompletedSetup":true,"submissionMode":"codex","buttonControlEnabled":true,"selectedPresetID":"pointer"}
        """.utf8
    ).write(to: fileURL)

    let snapshot = AppPreferencesStore(fileURL: fileURL).load()
    #expect(snapshot.state == .loaded)
    #expect(snapshot.preferences.voiceConnectionMode == .alwaysReady)

    var migrated = snapshot.preferences
    migrated.voiceConnectionMode = .smartSleep
    try AppPreferencesStore(fileURL: fileURL).save(migrated)
    let reloaded = AppPreferencesStore(fileURL: fileURL).load()
    #expect(reloaded.preferences.schemaVersion == AppPreferences.currentSchemaVersion)
    #expect(reloaded.preferences.voiceConnectionMode == .smartSleep)
}

@Test func appPreferencesBuildCodexCLIRuntimeArguments() throws {
    var preferences = AppPreferences.defaults
    preferences.submissionMode = .codexCLI
    #expect(
        preferences.runtimeArguments == [
            "--name", "小米蓝牙语音遥控器",
            "--submit-target", "codex-cli",
            "--voice-connection-mode", "always_ready",
            "--preset", "pointer",
        ]
    )

    preferences.codexCLITerminal = .app("com.googlecode.iterm2")
    preferences.codexCLILaunchCommand = "cxd"
    #expect(
        preferences.runtimeArguments == [
            "--name", "小米蓝牙语音遥控器",
            "--submit-target", "codex-cli",
            "--cli-terminal", "app:com.googlecode.iterm2",
            "--cli-launch-command", "cxd",
            "--voice-connection-mode", "always_ready",
            "--preset", "pointer",
        ]
    )

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mi-ao-preferences-cli-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("preferences.json")
    let store = AppPreferencesStore(fileURL: fileURL)
    try store.save(preferences)
    #expect(store.load() == AppPreferencesSnapshot(preferences: preferences, state: .loaded))
    let json = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
    )
    #expect(json["submissionMode"] as? String == "codex_cli")
    #expect(json["codexCLITerminal"] as? String == "app:com.googlecode.iterm2")
    #expect(json["codexCLILaunchCommand"] as? String == "cxd")
}

@Test func appPreferencesReadCodexCLIModeWithoutTerminalField() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mi-ao-preferences-cli-legacy-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fileURL = root.appendingPathComponent("preferences.json")
    try Data(
        """
        {"schemaVersion":3,"hasCompletedSetup":true,"submissionMode":"codex_cli","buttonControlEnabled":true,"selectedPresetID":"pointer","voiceConnectionMode":"always_ready"}
        """.utf8
    ).write(to: fileURL)

    let snapshot = AppPreferencesStore(fileURL: fileURL).load()
    #expect(snapshot.state == .loaded)
    #expect(snapshot.preferences.submissionMode == .codexCLI)
    #expect(snapshot.preferences.codexCLITerminal == .auto)
    #expect(snapshot.preferences.codexCLILaunchCommand == "codex")

    try Data(
        """
        {"schemaVersion":3,"submissionMode":"codex","codexCLITerminal":"not-a-choice","codexCLILaunchCommand":"  "}
        """.utf8
    ).write(to: fileURL)
    let fallback = AppPreferencesStore(fileURL: fileURL).load().preferences
    #expect(fallback.codexCLITerminal == .auto)
    #expect(fallback.codexCLILaunchCommand == "codex")
}

@Test func appPreferencesRequirementsFollowSubmissionMode() {
    var preferences = AppPreferences.defaults

    preferences.submissionMode = .codex
    preferences.buttonControlEnabled = false
    #expect(preferences.requiresCodex)
    #expect(!preferences.requiresCodexCLI)
    #expect(preferences.requiresCodexCompatibility)
    #expect(preferences.requiresAccessibility)

    preferences.submissionMode = .codexCLI
    preferences.buttonControlEnabled = true
    #expect(!preferences.requiresCodex)
    #expect(preferences.requiresCodexCLI)
    #expect(!preferences.requiresCodexCompatibility)
    #expect(preferences.requiresAccessibility)
    #expect(preferences.submissionMode.codexTarget == .codexCLI)

    preferences.submissionMode = .transcriptionOnly
    preferences.buttonControlEnabled = true
    #expect(preferences.requiresCodex)
    #expect(!preferences.requiresCodexCLI)
    #expect(preferences.requiresAccessibility)

    preferences.buttonControlEnabled = false
    #expect(!preferences.requiresCodex)
    #expect(!preferences.requiresAccessibility)
    #expect(preferences.submissionMode.codexTarget == .codexApp)
}

private func permissions(at url: URL) throws -> Int {
    let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
    if let number = value as? NSNumber { return number.intValue }
    return try #require(value as? Int)
}
