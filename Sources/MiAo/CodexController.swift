// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation

/// 按发送目标把 Codex 相关操作转发到 Codex App（`CodexSubmitter`）或 Codex CLI（`CodexCLISubmitter`）。
struct CodexController: Sendable {
    let target: CodexSubmitTarget
    let cliTerminal: CodexCLITerminalChoice
    let cliLaunchCommand: String
    let tmuxTarget: String?

    init(
        target: CodexSubmitTarget = .codexApp,
        cliTerminal: CodexCLITerminalChoice = .auto,
        cliLaunchCommand: String = CodexCLISubmitter.defaultLaunchCommand,
        tmuxTarget: String? = nil
    ) {
        self.target = target
        self.cliTerminal = cliTerminal
        self.cliLaunchCommand = cliLaunchCommand
        self.tmuxTarget = tmuxTarget
    }

    init(configuration: Configuration) {
        self.init(
            target: configuration.submitTarget,
            cliTerminal: configuration.cliTerminal,
            cliLaunchCommand: configuration.cliLaunchCommand,
            tmuxTarget: configuration.tmuxTarget
        )
    }

    var cli: CodexCLISubmitter {
        CodexCLISubmitter(choice: cliTerminal, tmuxTarget: tmuxTarget, launchCommand: cliLaunchCommand)
    }

    var displayName: String { target.displayName }

    func submit(
        _ text: String,
        force: Bool,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        switch target {
        case .codexApp: CodexSubmitter().submit(text, force: force, completion: completion)
        case .codexCLI: cli.submit(text, force: force, completion: completion)
        }
    }

    @discardableResult
    func activate() -> Bool {
        switch target {
        case .codexApp: return CodexSubmitter().activateCodex()
        case .codexCLI: return cli.activate()
        }
    }

    func launchOrActivate() -> CodexActivationResult {
        switch target {
        case .codexApp: return CodexSubmitter().launchOrActivateCodex()
        case .codexCLI: return cli.launchOrActivate()
        }
    }

    @discardableResult
    func navigateTask(_ direction: CodexTaskDirection) -> Bool {
        switch target {
        case .codexApp: return CodexSubmitter().navigateTask(direction)
        case .codexCLI: return cli.navigateTask(direction)
        }
    }

    func diagnostics() -> [String] {
        switch target {
        case .codexApp: return CodexSubmitter().editorDiagnostics()
        case .codexCLI: return cli.diagnostics()
        }
    }
}

/// 运行时共享的当前发送目标；设置向导改动偏好后通过分布式通知热更新，无需重启米遥。
final class CodexTargetRegistry: @unchecked Sendable {
    static let shared = CodexTargetRegistry()

    private let lock = NSLock()
    private var storedController = CodexController()
    private var storedSubmitEnabled = true
    private var storedTmuxTarget: String?

    var controller: CodexController {
        lock.lock()
        defer { lock.unlock() }
        return storedController
    }

    /// 语音转写后是否自动发送（对应偏好里的“仅转写”）。
    var submitEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedSubmitEnabled
    }

    func configure(with configuration: Configuration) {
        lock.lock()
        defer { lock.unlock() }
        storedController = CodexController(configuration: configuration)
        storedSubmitEnabled = configuration.submitToCodex
        storedTmuxTarget = configuration.tmuxTarget
    }

    /// 用最新偏好覆盖发送目标；命令行显式指定的 `--tmux-target` 继续保留。
    func apply(preferences: AppPreferences) {
        lock.lock()
        defer { lock.unlock() }
        storedController = CodexController(
            target: preferences.submissionMode.codexTarget,
            cliTerminal: preferences.codexCLITerminal,
            cliLaunchCommand: preferences.codexCLILaunchCommand,
            tmuxTarget: storedTmuxTarget
        )
        storedSubmitEnabled = preferences.submissionMode != .transcriptionOnly
    }
}
