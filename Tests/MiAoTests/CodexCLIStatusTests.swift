// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation
import Testing

@testable import MiAo

@Test func codexCLIVersionParsing() {
    #expect(CodexCLIStatusInspector.parseVersion("codex-cli 0.154.0\n") == "0.154.0")
    #expect(CodexCLIStatusInspector.parseVersion("0.155.0-alpha.1") == "0.155.0-alpha.1")
    #expect(CodexCLIStatusInspector.parseVersion("") == nil)
    #expect(CodexCLIStatusInspector.parseVersion("error: unknown flag") == nil)
}

@Test func codexCLILoginStatusParsing() {
    #expect(CodexCLIStatusInspector.parseLoginStatus(exitCode: 0, output: "Logged in using ChatGPT\n") == .chatGPT)
    #expect(CodexCLIStatusInspector.parseLoginStatus(exitCode: 0, output: "Logged in using an API key") == .apiKey)
    #expect(CodexCLIStatusInspector.parseLoginStatus(exitCode: 1, output: "Not logged in") == .notLoggedIn)
    #expect(CodexCLIStatusInspector.parseLoginStatus(exitCode: 2, output: "") == .notLoggedIn)
    #expect(
        CodexCLIStatusInspector.parseLoginStatus(exitCode: 0, output: "Logged in via device")
            == .unknown("Logged in via device"))
    #expect(CodexCLIStatusInspector.parseLoginStatus(exitCode: 0, output: "") == .unknown("无输出"))
}

@Test func codexCLILoginFallsBackToAuthFile() {
    let chatGPT = Data(
        """
        {"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"access_token":"abc","refresh_token":"r","account_id":"a"}}
        """.utf8
    )
    let apiKey = Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-test","tokens":null}"#.utf8)
    let empty = Data(#"{"tokens":{"access_token":""}}"#.utf8)
    let untagged = Data(#"{"tokens":{"access_token":"abc"}}"#.utf8)
    #expect(CodexCLIStatusInspector.loginFromAuthFile(chatGPT) == .chatGPT)
    #expect(CodexCLIStatusInspector.loginFromAuthFile(apiKey) == .apiKey)
    #expect(CodexCLIStatusInspector.loginFromAuthFile(empty) == .notLoggedIn)
    #expect(CodexCLIStatusInspector.loginFromAuthFile(untagged) == .chatGPT)
    #expect(CodexCLIStatusInspector.loginFromAuthFile(Data("nope".utf8)) == .notLoggedIn)
}

@Test func codexCLIStatusInspectorCombinesExecutableVersionLoginAndProcesses() {
    let runtime = CodexCLIRuntime(
        runCommand: { executable, arguments, _ in
            switch (executable.path, arguments) {
            case ("/Users/tester/.bun/bin/codex", ["--version"]):
                return CommandResult(exitCode: 0, output: "codex-cli 0.154.0")
            case ("/Users/tester/.bun/bin/codex", ["login", "status"]):
                return CommandResult(exitCode: 0, output: "Logged in using ChatGPT")
            case ("/bin/ps", _):
                return CommandResult(exitCode: 0, output: "  42  1 ttys001  codex\n")
            default:
                return CommandResult(exitCode: 1, output: "")
            }
        },
        runningApplication: { _ in nil },
        runningApplications: { _ in [] },
        isExecutable: { $0 == "/Users/tester/.bun/bin/codex" },
        listDirectory: { _ in ["v25.2.1"] },
        readFile: { _ in nil },
        homeDirectory: "/Users/tester",
        environment: ["PATH": "/usr/bin:/bin", "CODEX_HOME": "/Users/tester/.codex-alt"]
    )
    let inspector = CodexCLIStatusInspector(runtime: runtime)
    let candidates = inspector.codexExecutableCandidates()
    #expect(candidates.first == "/usr/bin/codex")
    #expect(candidates.contains("/Users/tester/.nvm/versions/node/v25.2.1/bin/codex"))
    #expect(inspector.authFilePath == "/Users/tester/.codex-alt/auth.json")

    let status = inspector.inspect()
    #expect(status.executable == "/Users/tester/.bun/bin/codex")
    #expect(status.version == "0.154.0")
    #expect(status.login == .chatGPT)
    #expect(status.isInstalled)
    // 没有终端 App 也没有 tmux 时，孤立 codex 进程不会被当作可投递目标。
    #expect(status.running.isEmpty)
}

@Test func codexCLIStatusWithoutExecutableUsesAuthFile() {
    let runtime = CodexCLIRuntime(
        runCommand: { _, _, _ in nil },
        runningApplication: { _ in nil },
        runningApplications: { _ in [] },
        isExecutable: { _ in false },
        listDirectory: { _ in [] },
        readFile: { path in
            path == "/Users/tester/.codex/auth.json"
                ? Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk"}"#.utf8) : nil
        },
        homeDirectory: "/Users/tester",
        environment: [:]
    )
    let status = CodexCLIStatusInspector(runtime: runtime).inspect()
    #expect(!status.isInstalled)
    #expect(status.version == nil)
    #expect(status.login == .apiKey)
}

@Test func codexCLISetupCheckReflectsInstallLoginAndRunningState() {
    let running = CodexCLITarget(codexPID: 7, tty: "/dev/ttys001", transport: .tmux(paneID: "%3", session: "work"))
    let missing = CodexCLIStatus(executable: nil, version: nil, login: .notLoggedIn, running: [])
    let loggedOut = CodexCLIStatus(executable: "/x/codex", version: "0.154.0", login: .notLoggedIn, running: [])
    let idle = CodexCLIStatus(executable: "/x/codex", version: "0.154.0", login: .chatGPT, running: [])
    let active = CodexCLIStatus(executable: "/x/codex", version: "0.154.0", login: .apiKey, running: [running])

    let missingCheck = SetupEnvironmentInspector.codexCLICheck(status: missing, terminal: .auto)
    #expect(missingCheck.state == .blocked)
    #expect(missingCheck.action == .installCodexCLI)
    #expect(missingCheck.requirement == .featureRequired)

    let loggedOutCheck = SetupEnvironmentInspector.codexCLICheck(status: loggedOut, terminal: .tmux)
    #expect(loggedOutCheck.state == .actionRequired)
    #expect(loggedOutCheck.action == .loginCodexCLI)
    #expect(loggedOutCheck.detail.contains("0.154.0"))

    let idleCheck = SetupEnvironmentInspector.codexCLICheck(status: idle, terminal: .app("com.apple.Terminal"))
    #expect(idleCheck.state == .ready)
    #expect(idleCheck.action == .launchCodexCLI)
    #expect(idleCheck.detail.contains("Terminal"))

    let activeCheck = SetupEnvironmentInspector.codexCLICheck(status: active, terminal: .auto)
    #expect(activeCheck.state == .ready)
    #expect(activeCheck.action == nil)
    #expect(activeCheck.detail.contains("tmux %3"))
}
