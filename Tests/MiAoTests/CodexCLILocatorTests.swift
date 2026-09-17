// Copyright (c) 2026 FanXeon@Poemcoder with Codex
import Foundation
import Testing

@testable import MiAo

/// 真机 `ps -axo pid=,ppid=,tty=,comm=` 片段：codex 被 node 包装器 spawn，本身没有控制终端。
private let sampleProcessTable = """
        1     0 ??       /sbin/launchd
    12259     1 ??       /opt/homebrew/bin/tmux
    12260 12259 ttys002  /Users/jandyx/.nvm/versions/node/v25.2.1/bin/node
    12518 12260 ??       codex
    16179 12518 ??       /opt/homebrew/Caskroom/codex/0.153.4/bin/codex-code-mode-host
    46889   900 ttys000  /usr/bin/login
    47021 46889 ttys000  -zsh
    47100 47021 ttys000  /opt/homebrew/bin/codex
      900     1 ??       /Applications/iTerm.app/Contents/MacOS/iTerm2
      950   900 ??       /Applications/iTerm.app/Contents/MacOS/iTerm2 Helper
    """

private let sampleTmuxPanes = """
    %10\t/dev/ttys012\tomx-detached\t0\t1\t1\t0
    %0\t/dev/ttys002\tomx-main\t0\t1\t1\t1
    %1\t/dev/ttys003\tomx-main\t0\t0\t1\t1
    """

private func fakeRuntime(
    processTable: String = sampleProcessTable,
    tmuxPanes: String? = sampleTmuxPanes,
    tmuxClients: String = "",
    applications: [pid_t: RunningApplicationInfo] = [:],
    recorder: CommandRecorder? = nil
) -> CodexCLIRuntime {
    CodexCLIRuntime(
        runCommand: { executable, arguments, _ in
            recorder?.append(executable: executable, arguments: arguments)
            switch executable.path {
            case "/bin/ps":
                return CommandResult(exitCode: 0, output: processTable)
            case "/opt/homebrew/bin/tmux":
                switch arguments.first {
                case "list-panes":
                    guard let tmuxPanes else { return CommandResult(exitCode: 1, output: "no server running") }
                    return CommandResult(exitCode: 0, output: tmuxPanes)
                case "list-clients":
                    return CommandResult(exitCode: 0, output: tmuxClients)
                default:
                    return CommandResult(exitCode: 0, output: "")
                }
            default:
                return CommandResult(exitCode: 0, output: "")
            }
        },
        runningApplication: { pid in applications[pid] },
        runningApplications: { bundleIdentifier in
            applications.values.filter { $0.bundleIdentifier == bundleIdentifier }
        },
        isExecutable: { $0 == "/opt/homebrew/bin/tmux" },
        listDirectory: { _ in [] },
        readFile: { _ in nil },
        homeDirectory: "/Users/tester",
        environment: [:]
    )
}

final class CommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [(executable: String, arguments: [String])] = []

    func append(executable: URL, arguments: [String]) {
        lock.lock()
        defer { lock.unlock() }
        calls.append((executable.path, arguments))
    }

    var tmuxCalls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return calls.filter { $0.executable.hasSuffix("/tmux") }.map(\.arguments)
    }
}

@Test func processTableParsesTTYAndCommandPaths() {
    let table = CodexCLIProcessTable.parse(sampleProcessTable)
    #expect(table.count == 10)
    let codex = table.first { $0.pid == 12518 }
    #expect(codex?.ppid == 12260)
    #expect(codex?.tty == nil)
    #expect(codex?.command == "codex")
    let node = table.first { $0.pid == 12260 }
    #expect(node?.tty == "/dev/ttys002")
    #expect(node?.command == "/Users/jandyx/.nvm/versions/node/v25.2.1/bin/node")
    #expect(table.first { $0.pid == 950 }?.command == "/Applications/iTerm.app/Contents/MacOS/iTerm2 Helper")
}

@Test func codexProcessDetectionIgnoresHelpers() {
    #expect(CodexCLIProcessTable.isCodexCLI(command: "codex"))
    #expect(CodexCLIProcessTable.isCodexCLI(command: "/opt/homebrew/bin/codex"))
    #expect(CodexCLIProcessTable.isCodexCLI(command: "codex-aarch64-apple-darwin"))
    #expect(CodexCLIProcessTable.isCodexCLI(command: "/x/node_modules/@openai/codex/bin/codex-x86_64-apple-darwin"))
    #expect(!CodexCLIProcessTable.isCodexCLI(command: "/opt/homebrew/Caskroom/codex/0.153.4/bin/codex-code-mode-host"))
    #expect(!CodexCLIProcessTable.isCodexCLI(command: "codex-something"))
    #expect(!CodexCLIProcessTable.isCodexCLI(command: "/opt/homebrew/bin/tmux"))
}

@Test func ancestorsResolveTTYThroughWrapperAndStopAtCycles() {
    let table = CodexCLIProcessTable.parse(sampleProcessTable)
    #expect(CodexCLIProcessTable.ancestors(of: 12518, in: table).map(\.pid) == [12260, 12259])
    #expect(CodexCLIProcessTable.resolvedTTY(of: 12518, in: table) == "/dev/ttys002")
    #expect(CodexCLIProcessTable.resolvedTTY(of: 47100, in: table) == "/dev/ttys000")
    #expect(CodexCLIProcessTable.isInsideTmux(pid: 12518, in: table))
    #expect(!CodexCLIProcessTable.isInsideTmux(pid: 47100, in: table))

    let cyclic = [
        ProcessTableEntry(pid: 10, ppid: 11, tty: nil, command: "codex"),
        ProcessTableEntry(pid: 11, ppid: 10, tty: nil, command: "zsh"),
    ]
    #expect(CodexCLIProcessTable.ancestors(of: 10, in: cyclic).map(\.pid) == [11])
    #expect(CodexCLIProcessTable.resolvedTTY(of: 10, in: cyclic) == nil)
}

@Test func tmuxPanesParseAndPreferAttachedActivePane() {
    let panes = CodexCLIProcessTable.parseTmuxPanes(sampleTmuxPanes)
    #expect(panes.count == 3)
    #expect(
        panes[0]
            == TmuxPane(
                id: "%10", tty: "/dev/ttys012", session: "omx-detached", windowIndex: 0,
                paneActive: true, windowActive: true, sessionAttached: false
            ))
    #expect(CodexCLIProcessTable.preferredPane(panes)?.id == "%0")
    #expect(CodexCLIProcessTable.preferredPane([panes[2], panes[0]])?.id == "%1")
    #expect(CodexCLIProcessTable.preferredPane([]) == nil)
}

@Test func locatorFindsTmuxPaneAndTerminalAppHosts() {
    let iterm = RunningApplicationInfo(
        pid: 900, bundleIdentifier: "com.googlecode.iterm2", localizedName: "iTerm2",
        isRegular: true, isActive: false
    )
    let helper = RunningApplicationInfo(
        pid: 950, bundleIdentifier: "com.googlecode.iterm2.helper", localizedName: "Helper",
        isRegular: false, isActive: true
    )
    let locator = CodexCLILocator(runtime: fakeRuntime(applications: [900: iterm, 950: helper]))

    let targets = locator.locate()
    #expect(targets.count == 2)
    #expect(
        targets[0]
            == CodexCLITarget(
                codexPID: 12518, tty: "/dev/ttys002", transport: .tmux(paneID: "%0", session: "omx-main")
            ))
    #expect(
        targets[1]
            == CodexCLITarget(
                codexPID: 47100, tty: "/dev/ttys000",
                transport: .terminalApp(bundleIdentifier: "com.googlecode.iterm2", pid: 900, name: "iTerm2"),
                hostBundleIdentifier: "com.googlecode.iterm2", hostName: "iTerm2"
            ))

    #expect(locator.locate(choice: .tmux).map(\.codexPID) == [12518])
    #expect(locator.locate(choice: .app("com.googlecode.iterm2")).map(\.codexPID) == [47100])
    #expect(locator.locate(choice: .app("com.apple.Terminal")).isEmpty)
}

@Test func locatorSkipsHelperOnlyHostsAndHandlesMissingTmux() {
    let helper = RunningApplicationInfo(
        pid: 950, bundleIdentifier: "helper", localizedName: nil, isRegular: false, isActive: false
    )
    let table = """
          900     1 ??       /Applications/Foo.app/Contents/MacOS/Foo
          950   900 ttys009  /Applications/Foo.app/Contents/Frameworks/Helper
          960   950 ttys009  codex
        """
    let locator = CodexCLILocator(
        runtime: fakeRuntime(processTable: table, tmuxPanes: nil, applications: [950: helper]))
    #expect(locator.locate().isEmpty)
    #expect(CodexCLILocator(runtime: fakeRuntime(processTable: "")).locate().isEmpty)
}

@Test func locatorRanksActiveTerminalAheadOfIdleOnes() {
    let table = """
          100     1 ??       /Applications/A.app/Contents/MacOS/A
          101   100 ttys001  codex
          200     1 ??       /Applications/B.app/Contents/MacOS/B
          201   200 ttys002  codex
        """
    let apps: [pid_t: RunningApplicationInfo] = [
        100: RunningApplicationInfo(
            pid: 100, bundleIdentifier: "a", localizedName: "A", isRegular: true, isActive: false),
        200: RunningApplicationInfo(
            pid: 200, bundleIdentifier: "b", localizedName: "B", isRegular: true, isActive: true),
    ]
    let locator = CodexCLILocator(runtime: fakeRuntime(processTable: table, tmuxPanes: nil, applications: apps))
    #expect(locator.locate().map(\.codexPID) == [201, 101])
}

@Test func tmuxSessionAttachedInTerminalMatchesThatTerminalChoice() {
    // codex 在 tmux 里，而 tmux 正 attach 在 iTerm2 窗口：选“iTerm2”也应命中，投递仍走 tmux。
    let iterm = RunningApplicationInfo(
        pid: 900, bundleIdentifier: "com.googlecode.iterm2", localizedName: "iTerm2",
        isRegular: true, isActive: true
    )
    let table = """
        12259     1 ??       /opt/homebrew/bin/tmux
        12260 12259 ttys002  /usr/bin/node
        12518 12260 ??       codex
          900     1 ??       /Applications/iTerm.app/Contents/MacOS/iTerm2
          901   900 ttys004  -zsh
          902   901 ttys004  /opt/homebrew/bin/tmux
        """
    let locator = CodexCLILocator(
        runtime: fakeRuntime(
            processTable: table,
            tmuxPanes: "%0\t/dev/ttys002\twork\t0\t1\t1\t1",
            tmuxClients: "/dev/ttys004\twork",
            applications: [900: iterm]
        )
    )
    let targets = locator.locate(choice: .app("com.googlecode.iterm2"))
    #expect(targets.count == 1)
    #expect(targets.first?.transport == .tmux(paneID: "%0", session: "work"))
    #expect(targets.first?.hostBundleIdentifier == "com.googlecode.iterm2")
    #expect(targets.first?.description == "tmux %0 · session work · iTerm2")
    #expect(locator.locate(choice: .app("com.apple.Terminal")).isEmpty)

    // 未 attach 的后台 session 不属于任何终端。
    let detached = CodexCLILocator(
        runtime: fakeRuntime(
            processTable: table,
            tmuxPanes: "%0\t/dev/ttys002\twork\t0\t1\t1\t0",
            tmuxClients: "",
            applications: [900: iterm]
        )
    )
    #expect(detached.locate(choice: .app("com.googlecode.iterm2")).isEmpty)
    #expect(detached.locate(choice: .auto).first?.description == "tmux %0 · session work · 未 attach")
}

@Test func locatorMapsTerminalDaemonsBackToTheirApp() {
    // iTerm2 的 shell 由 iTermServer 守护进程 fork，父进程链到 launchd 为止，永远碰不到 GUI App。
    let iterm = RunningApplicationInfo(
        pid: 700, bundleIdentifier: "com.googlecode.iterm2", localizedName: "iTerm2",
        isRegular: true, isActive: true
    )
    let table = """
         1198     1 ??       /Users/jandyx/Library/Application Support/iTerm2/iTermServer-3.7.0
        81263  1198 ttys001  codex
          700     1 ??       /Applications/iTerm.app/Contents/MacOS/iTerm2
        """
    let locator = CodexCLILocator(runtime: fakeRuntime(processTable: table, tmuxPanes: nil, applications: [700: iterm]))
    let targets = locator.locate(choice: .app("com.googlecode.iterm2"))
    #expect(targets.count == 1)
    #expect(
        targets.first?.transport == .terminalApp(bundleIdentifier: "com.googlecode.iterm2", pid: 700, name: "iTerm2"))
    #expect(TerminalCatalog.hostBundleIdentifier(forHelperCommand: "/x/iTermServer-3.7.0") == "com.googlecode.iterm2")
    #expect(TerminalCatalog.hostBundleIdentifier(forHelperCommand: "/bin/zsh") == nil)
}

@Test func tmuxClientHostResolvesTerminalFromClientTTY() {
    let iterm = RunningApplicationInfo(
        pid: 900, bundleIdentifier: "com.googlecode.iterm2", localizedName: "iTerm2",
        isRegular: true, isActive: true
    )
    let table = """
          900     1 ??       /Applications/iTerm.app/Contents/MacOS/iTerm2
          901   900 ttys004  /usr/bin/login
          902   901 ttys004  -zsh
          903   902 ttys004  /opt/homebrew/bin/tmux
        """
    let locator = CodexCLILocator(
        runtime: fakeRuntime(
            processTable: table,
            tmuxClients: "/dev/ttys004\tomx-main\n/dev/ttys005\tother",
            applications: [900: iterm]
        )
    )
    #expect(locator.tmuxClientHost(session: "omx-main") == iterm)
    #expect(locator.tmuxClientHost(session: "missing") == nil)
}
