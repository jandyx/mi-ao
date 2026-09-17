// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation
import Testing

@testable import MiAo

@Test func setupReportStartsOnlyWhenEveryRealCheckIsReady() {
    let readyChecks = SetupCheckID.allCases.map {
        SetupCheck(
            id: $0,
            title: $0.rawValue,
            detail: "ready",
            state: .ready,
            action: nil,
            actionTitle: nil
        )
    }
    #expect(SetupEnvironmentReport(checks: readyChecks, runtimeActive: false).canStart)
    #expect(!SetupEnvironmentReport(checks: readyChecks, runtimeActive: true).canStart)

    var incompleteChecks = readyChecks
    incompleteChecks[2] = SetupCheck(
        id: .accessibility,
        title: "accessibility",
        detail: "missing",
        state: .actionRequired,
        action: .requestAccessibility,
        actionTitle: "request"
    )
    #expect(!SetupEnvironmentReport(checks: incompleteChecks, runtimeActive: false).canStart)

    incompleteChecks[2] = SetupCheck(
        id: .accessibility,
        title: "accessibility",
        detail: "optional",
        state: .actionRequired,
        action: .requestAccessibility,
        actionTitle: "request",
        requirement: .optional
    )
    #expect(SetupEnvironmentReport(checks: incompleteChecks, runtimeActive: false).canStart)
}

@Test func setupRequirementsFollowEnabledFeatures() {
    let inspector = SetupEnvironmentInspector()
    var minimal = AppPreferences.defaults
    minimal.submissionMode = .transcriptionOnly
    minimal.buttonControlEnabled = false
    let minimalReport = inspector.inspect(configuration: Configuration(), preferences: minimal)
    #expect(minimalReport.check(.accessibility)?.requirement == .optional)
    #expect(minimalReport.check(.codex)?.requirement == .optional)

    let defaultReport = inspector.inspect(
        configuration: Configuration(),
        preferences: .defaults
    )
    #expect(defaultReport.check(.accessibility)?.requirement == .featureRequired)
    #expect(defaultReport.check(.codex)?.requirement == .featureRequired)

    var buttonsOnly = AppPreferences.defaults
    buttonsOnly.submissionMode = .transcriptionOnly
    buttonsOnly.buttonControlEnabled = true
    let buttonsOnlyReport = inspector.inspect(
        configuration: Configuration(),
        preferences: buttonsOnly
    )
    #expect(buttonsOnlyReport.check(.codex)?.requirement == .featureRequired)
}

@Test func parsesSetupGuideModeExplicitly() throws {
    let configuration = try Configuration.parse(["mi-ao", "setup"])
    #expect(configuration.mode == .setup)
}

@Test func codexCLIModeRequiresAccessibilityButNotCodexApp() {
    let inspector = SetupEnvironmentInspector()
    var cli = AppPreferences.defaults
    cli.submissionMode = .codexCLI
    cli.buttonControlEnabled = true
    let report = inspector.inspect(configuration: Configuration(), preferences: cli)
    #expect(report.check(.accessibility)?.requirement == .featureRequired)
    #expect(report.check(.codex)?.requirement == .featureRequired)
    #expect(report.check(.codex)?.title == "Codex CLI")
    #expect(report.check(.voiceLink)?.requirement == .optional)
}

@Test func parsesCodexCLISubmitOptions() throws {
    let defaults = try Configuration.parse(["mi-ao", "run"])
    #expect(defaults.submitTarget == .codexApp)
    #expect(defaults.cliTerminal == .auto)
    #expect(defaults.tmuxTarget == nil)

    let configuration = try Configuration.parse([
        "mi-ao", "run",
        "--submit-target", "codex-cli",
        "--cli-terminal", "app:com.googlecode.iterm2",
        "--cli-launch-command", "cxd --full-auto",
        "--tmux-target", "%3",
    ])
    #expect(configuration.submitTarget == .codexCLI)
    #expect(configuration.cliTerminal == .app("com.googlecode.iterm2"))
    #expect(configuration.cliLaunchCommand == "cxd --full-auto")
    #expect(defaults.cliLaunchCommand == "codex")
    #expect(configuration.tmuxTarget == "%3")
    #expect(configuration.submitToCodex)

    let tmux = try Configuration.parse(["mi-ao", "run", "--cli-terminal", "tmux"])
    #expect(tmux.cliTerminal == .tmux)

    #expect(throws: BridgeError.self) {
        try Configuration.parse(["mi-ao", "run", "--submit-target", "terminal"])
    }
    #expect(throws: BridgeError.self) {
        try Configuration.parse(["mi-ao", "run", "--cli-terminal", "iterm"])
    }
    #expect(throws: BridgeError.self) {
        try Configuration.parse(["mi-ao", "run", "--tmux-target"])
    }
}

@Test func installationContextStillReadsPreFingerprintFormat() throws {
    let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>repositoryRoot</key><string>/tmp/mi-ao</string>
          <key>version</key><string>0.1.0</string>
          <key>installedAt</key><string>2026-07-15T00:00:00Z</string>
        </dict></plist>
        """
    let context = try PropertyListDecoder().decode(
        MiAoInstallationContext.self,
        from: Data(plist.utf8)
    )
    #expect(context.repositoryRoot == "/tmp/mi-ao")
    #expect(context.runtimeRoot == nil)
    #expect(context.codeHash == nil)
}

@Test func installationContextReadsSelfContainedRuntimeRoot() throws {
    let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>repositoryRoot</key><string>/tmp/mi-ao-source</string>
          <key>runtimeRoot</key><string>/Applications/米遥.app/Contents/Resources/Runtime</string>
          <key>version</key><string>0.1.0</string>
          <key>installedAt</key><string>2026-07-15T00:00:00Z</string>
          <key>codeHash</key><string>example</string>
        </dict></plist>
        """
    let context = try PropertyListDecoder().decode(
        MiAoInstallationContext.self,
        from: Data(plist.utf8)
    )
    #expect(context.repositoryRoot == "/tmp/mi-ao-source")
    #expect(context.runtimeRoot == "/Applications/米遥.app/Contents/Resources/Runtime")
    #expect(context.isSelfContained)
}
