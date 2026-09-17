// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import AppKit
import ApplicationServices
import Foundation

/// 把转写投递到终端里运行的 Codex CLI（TUI）。
///
/// 两条传输路：
/// - tmux：`paste-buffer -p` 直接写入窗格 pty，不抢焦点、不碰剪贴板、不需要辅助功能权限。
/// - 终端 App：激活承载 codex 的终端，复用 `CodexInjection` 走剪贴板 + Cmd+V + Return。
struct CodexCLISubmitter: Sendable {
    static let tmuxBufferName = "mi-ao-transcript"
    static let enterDelay: TimeInterval = 0.3
    static let terminalActivationDelay: TimeInterval = 0.35

    typealias Delay = @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void

    static let defaultLaunchCommand = "codex"

    let choice: CodexCLITerminalChoice
    let tmuxTarget: String?
    /// 电源键 / “启动 Codex CLI” 在终端里执行的命令行，走用户登录 shell，可用 alias。
    let launchCommand: String
    let runtime: CodexCLIRuntime
    let activateApplication: @Sendable (pid_t) -> Bool
    let delay: Delay

    init(
        choice: CodexCLITerminalChoice = .auto,
        tmuxTarget: String? = nil,
        launchCommand: String = CodexCLISubmitter.defaultLaunchCommand,
        runtime: CodexCLIRuntime = .live,
        activateApplication: @escaping @Sendable (pid_t) -> Bool = { pid in
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows]) ?? false
        },
        delay: @escaping Delay = { seconds, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    ) {
        self.choice = choice
        self.tmuxTarget = tmuxTarget
        let trimmed = launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        self.launchCommand = trimmed.isEmpty ? Self.defaultLaunchCommand : trimmed
        self.runtime = runtime
        self.activateApplication = activateApplication
        self.delay = delay
    }

    private var locator: CodexCLILocator { CodexCLILocator(runtime: runtime) }

    /// 用户的登录 shell（`$SHELL`），决定启动命令在 zsh / bash / fish 里执行。
    var loginShell: String {
        let shell = runtime.environment["SHELL"] ?? ""
        return shell.hasPrefix("/") ? shell : "/bin/zsh"
    }

    /// 转写只保留单行：TUI 里 Enter 是提交，多行粘贴在部分终端还会弹确认。
    static func normalizedTranscript(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func preferredTarget() -> CodexCLITarget? {
        locator.locate(choice: choice).first
    }

    /// 没找到匹配目标时的说明：如果其他地方有 codex 在跑，指出它们在哪，方便改选终端。
    func notFoundMessage() -> String {
        var message = "未找到运行中的 Codex CLI（\(choice.displayName)）"
        if choice != .auto {
            let elsewhere = locator.locate(choice: .auto)
            if !elsewhere.isEmpty {
                let places = elsewhere.prefix(3).map(\.description).joined(separator: "；")
                message += "。发现 \(elsewhere.count) 个 codex 在别处：\(places)。可改选“自动探测”或对应终端"
            } else {
                message += "，请先在 \(choice.displayName) 里运行 codex"
            }
        } else {
            message += "，请先在终端里运行 codex"
        }
        return message + "；transcript 已复制到剪贴板"
    }

    // MARK: - 发送

    func submit(
        _ text: String,
        force: Bool,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { submit(text, force: force, completion: completion) }
            return
        }
        deliver(text, force: force, completion: completion)
    }

    /// 不做主线程切换的发送实现；tmux 路可在任意线程执行，终端 App 路由调用方保证主线程。
    func deliver(
        _ text: String,
        force: Bool,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let transcript = Self.normalizedTranscript(text)
        guard !transcript.isEmpty else {
            completion(.failure(BridgeError.submission("转写为空，已取消发送")))
            return
        }

        if let tmuxTarget {
            submitViaTmux(transcript, target: tmuxTarget, completion: completion)
            return
        }

        guard let target = preferredTarget() else {
            CodexInjection.copyOnly(transcript)
            completion(.failure(BridgeError.submission(notFoundMessage())))
            return
        }

        switch target.transport {
        case .tmux(let paneID, _):
            submitViaTmux(transcript, target: paneID, completion: completion)
        case .terminalApp:
            submitViaTerminalApp(transcript, target: target, force: force, completion: completion)
        }
    }

    /// 激活承载 codex 的终端；Terminal.app / iTerm2 会按 tty 切到对应 Tab，其他终端只激活 App。
    func focusTerminal(_ target: CodexCLITarget) -> Bool {
        guard case .terminalApp(let bundleIdentifier, let pid, _) = target.transport else { return false }
        if let tty = target.tty,
            let invocation = TerminalCatalog.app(for: bundleIdentifier).focusInvocation(tty: tty),
            let result = runtime.runCommand(invocation.executable, invocation.arguments, 5),
            result.succeeded, result.output.contains("focused")
        {
            return true
        }
        return activateApplication(pid)
    }

    /// tmux 命令序列：set-buffer → paste-buffer -p（bracketed paste）→ 延时 → Enter。
    static func tmuxSubmitCommands(_ text: String, target: String) -> (paste: [[String]], enter: [String]) {
        (
            paste: [
                ["set-buffer", "-b", tmuxBufferName, "--", text],
                ["paste-buffer", "-p", "-d", "-b", tmuxBufferName, "-t", target],
            ],
            enter: ["send-keys", "-t", target, "Enter"]
        )
    }

    private func submitViaTmux(
        _ text: String,
        target: String,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        guard runtime.tmuxExecutable != nil else {
            CodexInjection.copyOnly(text)
            completion(.failure(BridgeError.submission("未找到 tmux；transcript 已复制到剪贴板")))
            return
        }
        let commands = Self.tmuxSubmitCommands(text, target: target)
        for arguments in commands.paste {
            guard let result = runtime.tmux(arguments), result.succeeded else {
                CodexInjection.copyOnly(text)
                completion(
                    .failure(
                        BridgeError.submission(
                            "tmux \(arguments.first ?? "") 失败（目标 \(target)）；transcript 已复制到剪贴板"
                        )
                    )
                )
                return
            }
        }
        let runtime = runtime
        let enter = commands.enter
        delay(Self.enterDelay) {
            guard let result = runtime.tmux(enter), result.succeeded else {
                completion(.failure(BridgeError.submission("已粘贴到 tmux \(target)，但发送 Enter 失败")))
                return
            }
            completion(.success(()))
        }
    }

    private func submitViaTerminalApp(
        _ text: String,
        target: CodexCLITarget,
        force: Bool,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let name = target.terminalName
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            CodexInjection.copyOnly(text)
            completion(
                .failure(
                    BridgeError.submission("尚未授予辅助功能权限，无法向 \(name) 粘贴；transcript 已复制到剪贴板")
                )
            )
            return
        }
        guard focusTerminal(target) else {
            CodexInjection.copyOnly(text)
            completion(.failure(BridgeError.submission("无法激活 \(name)；transcript 已复制到剪贴板")))
            return
        }
        delay(Self.terminalActivationDelay) {
            CodexInjection.pasteAndReturn(text, returnDelay: Self.enterDelay, completion: completion)
        }
    }

    // MARK: - 聚焦 / 启动 / 切换

    @discardableResult
    func activate() -> Bool {
        guard let target = preferredTarget() else { return false }
        return activate(target)
    }

    @discardableResult
    func activate(_ target: CodexCLITarget) -> Bool {
        switch target.transport {
        case .tmux(let paneID, let session):
            runtime.tmux(["select-window", "-t", paneID])
            runtime.tmux(["select-pane", "-t", paneID])
            if let host = locator.tmuxClientHost(session: session) {
                return activateApplication(host.pid)
            }
            return true
        case .terminalApp:
            return focusTerminal(target)
        }
    }

    func launchOrActivate() -> CodexActivationResult {
        if let target = preferredTarget() {
            return activate(target) ? .activated : .cliNotFound(hint: "无法聚焦 \(target.terminalName)")
        }
        return launch(commandLine: launchCommand)
    }

    /// 在选定终端里运行一行 shell 命令（默认是启动命令；也用于 `codex login`）。
    func launch(commandLine: String) -> CodexActivationResult {
        switch choice {
        case .tmux:
            return launchInTmux(commandLine: commandLine)
        case .app(let bundleIdentifier):
            return launch(commandLine: commandLine, in: TerminalCatalog.app(for: bundleIdentifier))
        case .auto:
            if locator.tmuxPanes()?.contains(where: \.sessionAttached) == true {
                return launchInTmux(commandLine: commandLine)
            }
            let installed = TerminalCatalog.installed()
            guard let terminal = installed.first(where: \.isRunning)?.app ?? installed.first?.app else {
                return .cliNotFound(hint: "未找到可用终端，请手动打开终端运行 \(commandLine)")
            }
            return launch(commandLine: commandLine, in: terminal)
        }
    }

    /// tmux 里同样经登录 shell 执行，保证 PATH 与 alias 一致。
    func tmuxCommandLine(_ commandLine: String) -> String {
        TerminalApp.shellInvocation(commandLine: commandLine, shell: loginShell)
            .map(TerminalApp.shellQuote).joined(separator: " ")
    }

    private func launchInTmux(commandLine rawCommandLine: String) -> CodexActivationResult {
        guard runtime.tmuxExecutable != nil else {
            return .cliNotFound(hint: "未找到 tmux，请先安装或改选其他终端")
        }
        let commandLine = tmuxCommandLine(rawCommandLine)
        if let attached = locator.tmuxPanes()?.first(where: \.sessionAttached) {
            guard
                let result = runtime.tmux([
                    "new-window", "-t", attached.session, "-n", "codex", commandLine,
                ]),
                result.succeeded
            else {
                return .cliNotFound(hint: "tmux new-window 失败，请手动在 tmux 里运行 \(rawCommandLine)")
            }
            if let host = locator.tmuxClientHost(session: attached.session) {
                _ = activateApplication(host.pid)
            }
            return .cliLaunchRequested(terminal: "tmux · session \(attached.session)")
        }
        guard
            let result = runtime.tmux(["new-session", "-d", "-s", "codex", commandLine]),
            result.succeeded
        else {
            return .cliNotFound(hint: "tmux new-session 失败，请手动在 tmux 里运行 \(rawCommandLine)")
        }
        return .cliNotFound(
            hint: "已在后台 tmux session「codex」运行 \(rawCommandLine)，请在终端执行 tmux attach -t codex"
        )
    }

    private func launch(commandLine: String, in terminal: TerminalApp) -> CodexActivationResult {
        guard let invocation = terminal.launchInvocation(commandLine: commandLine, shell: loginShell) else {
            if let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: terminal.bundleIdentifier
            ).first {
                _ = activateApplication(application.processIdentifier)
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleIdentifier) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) {
                    _, _ in
                }
            }
            return .cliNotFound(hint: "请在 \(terminal.displayName) 里运行 \(commandLine)")
        }
        guard let result = runtime.runCommand(invocation.executable, invocation.arguments, 10), result.succeeded
        else {
            return .cliNotFound(hint: "无法在 \(terminal.displayName) 启动 \(commandLine)，请手动运行")
        }
        return .cliLaunchRequested(terminal: terminal.displayName)
    }

    static func tmuxNavigateCommand(_ direction: CodexTaskDirection, session: String) -> [String] {
        [direction == .previous ? "previous-window" : "next-window", "-t", session]
    }

    /// CLI 模式下的“上一个 / 下一个会话”＝切换终端 Tab / tmux 窗口。
    @discardableResult
    func navigateTask(_ direction: CodexTaskDirection) -> Bool {
        guard let target = preferredTarget() else { return false }
        switch target.transport {
        case .tmux(_, let session):
            return runtime.tmux(Self.tmuxNavigateCommand(direction, session: session))?.succeeded == true
        case .terminalApp:
            guard AXIsProcessTrusted(), focusTerminal(target) else { return false }
            let keyCode: CGKeyCode = direction == .previous ? 33 : 30  // [ / ]
            delay(0.15) {
                CodexInjection.postKey(keyCode: keyCode, flags: [.maskCommand, .maskShift])
            }
            return true
        }
    }

    func diagnostics() -> [String] {
        let status = CodexCLIStatusInspector(runtime: runtime).inspect(choice: choice)
        var lines: [String] = []
        lines.append("命令：\(status.executable ?? "未找到 codex")")
        if let version = status.version { lines.append("版本：\(version)") }
        lines.append("登录：\(status.login.description)")
        lines.append("终端选择：\(choice.displayName)")
        lines.append("启动命令：\(launchCommand)（经 \(loginShell) -lic）")
        lines.append("tmux：\(runtime.tmuxExecutable?.path ?? "未安装")")
        if status.running.isEmpty {
            lines.append("运行中实例：无")
        } else {
            for target in status.running {
                lines.append("运行中实例：pid \(target.codexPID) · \(target.tty ?? "无 tty") · \(target.description)")
            }
        }
        for installation in TerminalCatalog.installed() {
            lines.append(
                "已安装终端：\(installation.app.displayName)\(installation.isRunning ? " · 运行中" : "")"
            )
        }
        return lines
    }
}
