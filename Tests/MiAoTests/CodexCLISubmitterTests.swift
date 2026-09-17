// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation
import Testing

@testable import MiAo

private let tmuxHostedTable = """
    12259     1 ??       /opt/homebrew/bin/tmux
    12260 12259 ttys002  /usr/bin/node
    12518 12260 ??       codex
    """

private let tmuxHostedPanes = "%0\t/dev/ttys002\twork\t0\t1\t1\t1"

private func tmuxRuntime(recorder: CommandRecorder, panes: String = tmuxHostedPanes) -> CodexCLIRuntime {
    CodexCLIRuntime(
        runCommand: { executable, arguments, _ in
            recorder.append(executable: executable, arguments: arguments)
            switch (executable.path, arguments.first) {
            case ("/bin/ps", _):
                return CommandResult(exitCode: 0, output: tmuxHostedTable)
            case ("/opt/homebrew/bin/tmux", "list-panes"):
                return CommandResult(exitCode: 0, output: panes)
            case ("/opt/homebrew/bin/tmux", "list-clients"):
                return CommandResult(exitCode: 0, output: "")
            default:
                return CommandResult(exitCode: 0, output: "")
            }
        },
        runningApplication: { _ in nil },
        runningApplications: { _ in [] },
        isExecutable: { $0 == "/opt/homebrew/bin/tmux" },
        listDirectory: { _ in [] },
        readFile: { _ in nil },
        homeDirectory: "/Users/tester",
        environment: [:]
    )
}

private let immediately: CodexCLISubmitter.Delay = { _, work in work() }

private final class ResultBox: @unchecked Sendable {
    var result: Result<Void, Error>?
}

@Test func transcriptNormalizationCollapsesNewlines() {
    #expect(CodexCLISubmitter.normalizedTranscript("  检查当前项目\n并继续工作 \n\n") == "检查当前项目 并继续工作")
    #expect(CodexCLISubmitter.normalizedTranscript("\n \n").isEmpty)
    #expect(CodexCLISubmitter.normalizedTranscript("单行") == "单行")
}

@Test func tmuxSubmissionUsesBracketedPasteThenEnter() {
    let recorder = CommandRecorder()
    let submitter = CodexCLISubmitter(runtime: tmuxRuntime(recorder: recorder), delay: immediately)
    let box = ResultBox()
    submitter.deliver("检查当前项目\n并继续工作", force: false) { box.result = $0 }

    guard case .success = box.result else {
        Issue.record("tmux 投递没有成功：\(String(describing: box.result))")
        return
    }
    #expect(
        recorder.tmuxCalls == [
            ["list-panes", "-a", "-F", TmuxPane.listFormat],
            ["list-clients", "-F", "#{client_tty}\t#{session_name}"],
            ["set-buffer", "-b", CodexCLISubmitter.tmuxBufferName, "--", "检查当前项目 并继续工作"],
            ["paste-buffer", "-p", "-d", "-b", CodexCLISubmitter.tmuxBufferName, "-t", "%0"],
            ["send-keys", "-t", "%0", "Enter"],
        ]
    )
}

@Test func explicitTmuxTargetSkipsDetection() {
    let recorder = CommandRecorder()
    let submitter = CodexCLISubmitter(
        tmuxTarget: "work:1.0",
        runtime: tmuxRuntime(recorder: recorder),
        delay: immediately
    )
    let box = ResultBox()
    submitter.deliver("hello", force: false) { box.result = $0 }
    guard case .success = box.result else {
        Issue.record("显式 tmux 目标投递失败")
        return
    }
    #expect(!recorder.calls.contains { $0.executable == "/bin/ps" })
    #expect(recorder.tmuxCalls.first == ["set-buffer", "-b", CodexCLISubmitter.tmuxBufferName, "--", "hello"])
    #expect(recorder.tmuxCalls.last == ["send-keys", "-t", "work:1.0", "Enter"])
}

@Test func tmuxSubmissionFailsClearlyWhenNoCodexIsRunning() {
    let recorder = CommandRecorder()
    let submitter = CodexCLISubmitter(
        choice: .app("com.apple.Terminal"),
        runtime: tmuxRuntime(recorder: recorder),
        delay: immediately
    )
    let box = ResultBox()
    submitter.deliver("hello", force: false) { box.result = $0 }
    guard case .failure(let error) = box.result else {
        Issue.record("没有匹配终端时不应成功")
        return
    }
    #expect(error.localizedDescription.contains("未找到运行中的 Codex CLI"))
    #expect(error.localizedDescription.contains("Terminal"))
    #expect(error.localizedDescription.contains("发现 1 个 codex 在别处：tmux %0 · session work"))
    #expect(!recorder.tmuxCalls.contains { $0.first == "set-buffer" })
}

@Test func tmuxNavigationSwitchesWindows() {
    let recorder = CommandRecorder()
    let submitter = CodexCLISubmitter(runtime: tmuxRuntime(recorder: recorder), delay: immediately)
    #expect(submitter.navigateTask(.previous))
    #expect(submitter.navigateTask(.next))
    #expect(recorder.tmuxCalls.contains(["previous-window", "-t", "work"]))
    #expect(recorder.tmuxCalls.contains(["next-window", "-t", "work"]))
    #expect(CodexCLISubmitter.tmuxNavigateCommand(.next, session: "s") == ["next-window", "-t", "s"])
}

@Test func tmuxActivationSelectsPaneAndFocusesHostTerminal() {
    let recorder = CommandRecorder()
    let iterm = RunningApplicationInfo(
        pid: 900, bundleIdentifier: "com.googlecode.iterm2", localizedName: "iTerm2",
        isRegular: true, isActive: false
    )
    var runtime = tmuxRuntime(recorder: recorder)
    runtime.runCommand = { executable, arguments, _ in
        recorder.append(executable: executable, arguments: arguments)
        switch (executable.path, arguments.first) {
        case ("/bin/ps", _):
            return CommandResult(
                exitCode: 0,
                output: tmuxHostedTable
                    + "\n  900     1 ??       /Applications/iTerm.app/Contents/MacOS/iTerm2\n  901   900 ttys004  -zsh"
            )
        case ("/opt/homebrew/bin/tmux", "list-panes"):
            return CommandResult(exitCode: 0, output: tmuxHostedPanes)
        case ("/opt/homebrew/bin/tmux", "list-clients"):
            return CommandResult(exitCode: 0, output: "/dev/ttys004\twork")
        default:
            return CommandResult(exitCode: 0, output: "")
        }
    }
    runtime.runningApplication = { $0 == 900 ? iterm : nil }
    let activated = ActivationRecorder()
    let submitter = CodexCLISubmitter(
        runtime: runtime,
        activateApplication: { pid in
            activated.pids.append(pid)
            return true
        },
        delay: immediately
    )
    #expect(submitter.activate())
    #expect(recorder.tmuxCalls.contains(["select-window", "-t", "%0"]))
    #expect(recorder.tmuxCalls.contains(["select-pane", "-t", "%0"]))
    #expect(activated.pids == [900])
    #expect(submitter.launchOrActivate() == .activated)
}

private final class ActivationRecorder: @unchecked Sendable {
    var pids: [pid_t] = []
}

@Test func launchInChosenTerminalUsesItsStrategy() {
    let recorder = CommandRecorder()
    var runtime = tmuxRuntime(recorder: recorder, panes: "")
    runtime.runCommand = { executable, arguments, _ in
        recorder.append(executable: executable, arguments: arguments)
        if executable.path == "/bin/ps" { return CommandResult(exitCode: 0, output: "") }
        return CommandResult(exitCode: 0, output: "")
    }

    runtime.environment = ["SHELL": "/bin/zsh"]

    // 自定义启动命令（alias）经登录 shell 执行。
    let terminal = CodexCLISubmitter(
        choice: .app("com.apple.Terminal"), launchCommand: " cxd ", runtime: runtime, delay: immediately
    )
    #expect(terminal.launchCommand == "cxd")
    #expect(terminal.loginShell == "/bin/zsh")
    #expect(terminal.launchOrActivate() == .cliLaunchRequested(terminal: "Terminal"))
    let osascript = recorder.calls.last { $0.executable == "/usr/bin/osascript" }
    #expect(osascript?.arguments.first == "-e")
    #expect(osascript?.arguments.last?.contains("do script \"/bin/zsh -lic cxd\"") == true)

    let ghostty = CodexCLISubmitter(choice: .app("com.mitchellh.ghostty"), runtime: runtime, delay: immediately)
    #expect(ghostty.launch(commandLine: "codex login") == .cliLaunchRequested(terminal: "Ghostty"))
    let open = recorder.calls.last { $0.executable == "/usr/bin/open" }
    #expect(
        open?.arguments == [
            "-n", "-b", "com.mitchellh.ghostty", "--args", "-e", "/bin/zsh", "-lic", "codex login",
        ]
    )

    let tmux = CodexCLISubmitter(choice: .tmux, launchCommand: "", runtime: runtime, delay: immediately)
    #expect(tmux.launchCommand == "codex")
    guard case .cliNotFound(let hint) = tmux.launchOrActivate() else {
        Issue.record("没有 attached session 时应创建后台 session 并提示 attach")
        return
    }
    #expect(hint.contains("tmux attach -t codex"))
    #expect(recorder.tmuxCalls.contains(["new-session", "-d", "-s", "codex", "/bin/zsh -lic codex"]))

    var noShell = runtime
    noShell.environment = [:]
    #expect(CodexCLISubmitter(runtime: noShell).loginShell == "/bin/zsh")
}

@Test func launchInAttachedTmuxOpensNewWindow() {
    let recorder = CommandRecorder()
    var runtime = tmuxRuntime(recorder: recorder, panes: "%5\t/dev/ttys009\tmain\t2\t1\t1\t1")
    runtime.runCommand = { executable, arguments, _ in
        recorder.append(executable: executable, arguments: arguments)
        switch (executable.path, arguments.first) {
        case ("/bin/ps", _): return CommandResult(exitCode: 0, output: "")
        case ("/opt/homebrew/bin/tmux", "list-panes"):
            return CommandResult(exitCode: 0, output: "%5\t/dev/ttys009\tmain\t2\t1\t1\t1")
        default: return CommandResult(exitCode: 0, output: "")
        }
    }
    runtime.environment = ["SHELL": "/bin/zsh"]
    let submitter = CodexCLISubmitter(choice: .tmux, launchCommand: "cxd", runtime: runtime, delay: immediately)
    #expect(submitter.launchOrActivate() == .cliLaunchRequested(terminal: "tmux · session main"))
    #expect(recorder.tmuxCalls.contains(["new-window", "-t", "main", "-n", "codex", "/bin/zsh -lic cxd"]))
}

@Test func terminalAppActivationSelectsTabByTTYBeforeFallingBack() {
    let recorder = CommandRecorder()
    let iterm = RunningApplicationInfo(
        pid: 700, bundleIdentifier: "com.googlecode.iterm2", localizedName: "iTerm2",
        isRegular: true, isActive: false
    )
    let table = """
         1198     1 ??       /Users/jandyx/Library/Application Support/iTerm2/iTermServer-3.7.0
        81263  1198 ttys001  codex
          700     1 ??       /Applications/iTerm.app/Contents/MacOS/iTerm2
        """
    var runtime = tmuxRuntime(recorder: recorder, panes: "")
    runtime.runningApplications = { $0 == "com.googlecode.iterm2" ? [iterm] : [] }
    runtime.runCommand = { executable, arguments, _ in
        recorder.append(executable: executable, arguments: arguments)
        switch executable.path {
        case "/bin/ps": return CommandResult(exitCode: 0, output: table)
        case "/usr/bin/osascript": return CommandResult(exitCode: 0, output: "focused\n")
        default: return CommandResult(exitCode: 0, output: "")
        }
    }
    let activated = ActivationRecorder()
    let submitter = CodexCLISubmitter(
        choice: .app("com.googlecode.iterm2"),
        runtime: runtime,
        activateApplication: { pid in
            activated.pids.append(pid)
            return true
        },
        delay: immediately
    )
    #expect(submitter.activate())
    let osascript = recorder.calls.last { $0.executable == "/usr/bin/osascript" }
    #expect(osascript?.arguments.last?.contains("/dev/ttys001") == true)
    // AppleScript 精确选中 Tab 成功时不再需要粗暴激活整个 App。
    #expect(activated.pids.isEmpty)

    // AppleScript 找不到对应 session（例如自动化授权被拒）时退化为激活 App。
    runtime.runCommand = { executable, arguments, _ in
        recorder.append(executable: executable, arguments: arguments)
        switch executable.path {
        case "/bin/ps": return CommandResult(exitCode: 0, output: table)
        case "/usr/bin/osascript": return CommandResult(exitCode: 1, output: "not allowed")
        default: return CommandResult(exitCode: 0, output: "")
        }
    }
    let fallback = CodexCLISubmitter(
        choice: .app("com.googlecode.iterm2"),
        runtime: runtime,
        activateApplication: { pid in
            activated.pids.append(pid)
            return true
        },
        delay: immediately
    )
    #expect(fallback.activate())
    #expect(activated.pids == [700])
}
